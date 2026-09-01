package httpapi_test

import (
	"bufio"
	"bytes"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"ionstrikers.com/api/internal/httpapi"
	"ionstrikers.com/api/internal/serverreg"
	"ionstrikers.com/api/internal/signing"
	"ionstrikers.com/api/internal/store"
)

const joinSecret = "test-join-secret"

var serverKey *rsa.PrivateKey

func init() {
	var err error
	serverKey, err = signing.GenerateKeyPair()
	if err != nil {
		panic(err)
	}
}

func setup(t *testing.T) *httptest.Server {
	t.Helper()
	reg := serverreg.New(store.NewMemoryStore(), 30*time.Second, 60*time.Second)
	api := httpapi.New(reg, joinSecret)
	ts := httptest.NewServer(api.Mux)
	t.Cleanup(ts.Close)
	return ts
}

// fakeGameServer speaks the JSON-lines management protocol the real Godot
// server implements, verifying that commands are signed by the API.
type fakeGameServer struct {
	listener       net.Listener
	apiPublicKey   *rsa.PublicKey
	allowCreate    bool
	createdGameID  string
	sawBadSignature bool
}

func newFakeGameServer(t *testing.T, allowCreate bool) *fakeGameServer {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	f := &fakeGameServer{listener: ln, allowCreate: allowCreate, createdGameID: "game-xyz"}
	go f.serve()
	t.Cleanup(func() { ln.Close() })
	return f
}

func (f *fakeGameServer) addr() string { return f.listener.Addr().String() }

func (f *fakeGameServer) serve() {
	for {
		conn, err := f.listener.Accept()
		if err != nil {
			return
		}
		go f.handle(conn)
	}
}

func (f *fakeGameServer) handle(conn net.Conn) {
	defer conn.Close()

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil && len(line) == 0 {
		return
	}

	var env struct {
		Body string `json:"body"`
		Sig  string `json:"sig"`
	}
	if err := json.Unmarshal(line, &env); err != nil {
		writeJSON(conn, map[string]any{"error": "bad envelope"})
		return
	}

	bodyBytes, err := base64.StdEncoding.DecodeString(env.Body)
	if err != nil {
		writeJSON(conn, map[string]any{"error": "bad base64"})
		return
	}

	if f.apiPublicKey == nil || signing.Verify(f.apiPublicKey, bodyBytes, env.Sig) != nil {
		f.sawBadSignature = true
		writeJSON(conn, map[string]any{"error": "signature verification failed"})
		return
	}

	var cmd struct {
		Op     string `json:"op"`
		GameID string `json:"game_id"`
	}
	_ = json.Unmarshal(bodyBytes, &cmd)

	switch cmd.Op {
	case "create_game":
		if !f.allowCreate {
			writeJSON(conn, map[string]any{"error": "this server does not accept lobby creation"})
			return
		}
		writeJSON(conn, map[string]any{"game_id": f.createdGameID})
	case "join_game":
		writeJSON(conn, map[string]any{"ok": true})
	default:
		writeJSON(conn, map[string]any{"error": "unknown op"})
	}
}

func writeJSON(conn net.Conn, v any) {
	b, _ := json.Marshal(v)
	_, _ = conn.Write(append(b, '\n'))
}

// register performs the handshake and hands the minted API public key to the
// fake server, mirroring what ApiRegistrar does in Godot.
func register(t *testing.T, ts *httptest.Server, f *fakeGameServer, serverID string, allowCreate bool) {
	t.Helper()

	pubPEM, err := signing.MarshalPublicKey(&serverKey.PublicKey)
	if err != nil {
		t.Fatal(err)
	}

	body, _ := json.Marshal(store.ServerRecord{
		ServerID:           serverID,
		Endpoint:           "10.0.0.1:7777",
		MgmtEndpoint:       f.addr(),
		ProtocolVersion:    1,
		MaxPeers:           2048,
		MaxLobbies:         20,
		AllowDynamicCreate: allowCreate,
		ServerPublicKeyPEM: pubPEM,
	})

	resp, err := http.Post(ts.URL+"/v1/internal/register", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("register: status %d", resp.StatusCode)
	}

	var out struct {
		APIPublicKeyPEM string `json:"api_public_key_pem"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	apiPub, err := signing.ParsePublicKey(out.APIPublicKeyPEM)
	if err != nil {
		t.Fatal(err)
	}
	f.apiPublicKey = apiPub
}

func heartbeat(t *testing.T, ts *httptest.Server, serverID string, peers, lobbies int, games []store.CachedGame) *http.Response {
	t.Helper()

	body, _ := json.Marshal(map[string]any{
		"server_id":      serverID,
		"timestamp":      time.Now().Unix(),
		"active_peers":   peers,
		"active_lobbies": lobbies,
		"games":          games,
	})
	sig, err := signing.Sign(serverKey, body)
	if err != nil {
		t.Fatal(err)
	}

	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/v1/internal/heartbeat", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set(httpapi.SignatureHeader, sig)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestListIncludesEveryRegisteredServer(t *testing.T) {
	ts := setup(t)

	managed := newFakeGameServer(t, true)
	register(t, ts, managed, "srv-managed", true)
	heartbeat(t, ts, "srv-managed", 5, 1, []store.CachedGame{
		{GameID: "g1", ServerID: "srv-managed", DisplayName: "Arena", MapID: "parkour", Players: 5},
	}).Body.Close()

	private := newFakeGameServer(t, false)
	register(t, ts, private, "srv-private", false)
	heartbeat(t, ts, "srv-private", 3, 1, []store.CachedGame{
		{GameID: "d1", ServerID: "srv-private", DisplayName: "Private", MapID: "parkour", Players: 3},
	}).Body.Close()

	resp, err := http.Get(ts.URL + "/v1/games")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	var result struct {
		Games []struct {
			GameID string `json:"game_id"`
		} `json:"games"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		t.Fatal(err)
	}
	if len(result.Games) != 2 {
		t.Fatalf("both managed and private lobbies should be discoverable, got %d", len(result.Games))
	}
}

func TestListOmitsHostRowsWithNoMap(t *testing.T) {
	ts := setup(t)

	managed := newFakeGameServer(t, true)
	register(t, ts, managed, "srv-managed", true)
	heartbeat(t, ts, "srv-managed", 0, 1, []store.CachedGame{
		{GameID: "host-placeholder", ServerID: "srv-managed", MaxPlayers: 8, Capacity: 8, Round: 1},
		{GameID: "real-lobby", ServerID: "srv-managed", DisplayName: "Arena", MapID: "parkour", Mode: "arena"},
	}).Body.Close()

	resp, err := http.Get(ts.URL + "/v1/games")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	var result struct {
		Games []struct {
			GameID string `json:"game_id"`
			Map    string `json:"map"`
		} `json:"games"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		t.Fatal(err)
	}
	if len(result.Games) != 1 || result.Games[0].GameID != "real-lobby" {
		t.Fatalf("expected only the mapped lobby, got %+v", result.Games)
	}
}

func TestHeartbeatWithoutSignatureRejected(t *testing.T) {
	ts := setup(t)
	f := newFakeGameServer(t, true)
	register(t, ts, f, "srv-1", true)

	body, _ := json.Marshal(map[string]any{
		"server_id": "srv-1",
		"timestamp": time.Now().Unix(),
	})
	resp, err := http.Post(ts.URL+"/v1/internal/heartbeat", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 without a signature, got %d", resp.StatusCode)
	}
}

func TestHeartbeatWithForgedSignatureRejected(t *testing.T) {
	ts := setup(t)
	f := newFakeGameServer(t, true)
	register(t, ts, f, "srv-1", true)

	other, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(map[string]any{
		"server_id": "srv-1",
		"timestamp": time.Now().Unix(),
	})
	forged, err := signing.Sign(other, body)
	if err != nil {
		t.Fatal(err)
	}

	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/v1/internal/heartbeat", bytes.NewReader(body))
	req.Header.Set(httpapi.SignatureHeader, forged)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 for a forged signature, got %d", resp.StatusCode)
	}
}

func TestCreateRoutesToCapableServerAndIsSigned(t *testing.T) {
	ts := setup(t)
	f := newFakeGameServer(t, true)
	register(t, ts, f, "srv-managed", true)
	heartbeat(t, ts, "srv-managed", 0, 0, nil).Body.Close()

	resp, err := http.Post(ts.URL+"/v1/games", "application/json",
		bytes.NewReader([]byte(`{"mode":"arena","map":"parkour"}`)))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var out struct {
		GameID    string `json:"game_id"`
		Host      string `json:"host"`
		Port      int    `json:"port"`
		JoinToken struct {
			Signature string `json:"signature"`
		} `json:"join_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	if out.GameID != f.createdGameID {
		t.Fatalf("expected game_id %q, got %q", f.createdGameID, out.GameID)
	}
	if out.Port != 7777 {
		t.Fatalf("expected the advertised gameplay port, got %d", out.Port)
	}
	if out.JoinToken.Signature == "" {
		t.Fatal("expected a signed join token")
	}
	if f.sawBadSignature {
		t.Fatal("game server saw an unverifiable command from the API")
	}
}

func TestCreateRefusedWhenOnlyPrivateServersRegistered(t *testing.T) {
	ts := setup(t)
	f := newFakeGameServer(t, false)
	register(t, ts, f, "srv-private", false)
	heartbeat(t, ts, "srv-private", 2, 1, nil).Body.Close()

	resp, err := http.Post(ts.URL+"/v1/games", "application/json", bytes.NewReader([]byte("{}")))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 when no server advertises create, got %d", resp.StatusCode)
	}
}

func TestJoinRoutesToOwningServer(t *testing.T) {
	ts := setup(t)
	f := newFakeGameServer(t, false)
	register(t, ts, f, "srv-private", false)
	heartbeat(t, ts, "srv-private", 3, 1, []store.CachedGame{
		{GameID: "ded-1", ServerID: "srv-private"},
	}).Body.Close()

	resp, err := http.Post(ts.URL+"/v1/games/ded-1/join", "application/json", http.NoBody)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 joining a private server's lobby, got %d", resp.StatusCode)
	}

	var out struct {
		GameID string `json:"game_id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	if out.GameID != "ded-1" {
		t.Fatalf("expected game_id ded-1, got %q", out.GameID)
	}
}

func TestJoinUnknownGameIsNotFound(t *testing.T) {
	ts := setup(t)

	resp, err := http.Post(ts.URL+"/v1/games/nope/join", "application/json", http.NoBody)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", resp.StatusCode)
	}
}

func TestHealthEndpoint(t *testing.T) {
	ts := setup(t)

	resp, err := http.Get(ts.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}
}
