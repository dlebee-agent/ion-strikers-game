package httpapi_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"ionstrikers.com/api/internal/httpapi"
	"ionstrikers.com/api/internal/serverreg"
	"ionstrikers.com/api/internal/signing"
	"ionstrikers.com/api/internal/store"
)

// End to end over HTTP with two generations of server registered at once, which
// is the deployment this filtering exists for: a live pool and a release
// candidate pool sharing one API and one hostname.
//
// The failure being prevented is quiet. Without filtering, create returns 200
// with a host the client cannot speak to, and the player sees "protocol version
// mismatch" from the game server with nothing in the API's answer to explain it.

const assumedProtocol = 9

func protoSetup(t *testing.T) *httptest.Server {
	t.Helper()
	reg := serverreg.New(store.NewMemoryStore(), 30*time.Second, 60*time.Second)
	api := httpapi.New(reg, joinSecret, assumedProtocol)
	ts := httptest.NewServer(api.Mux)
	t.Cleanup(ts.Close)
	return ts
}

// registerAtProtocol is register() with the wire version and endpoint varied, so
// one test can stand up two generations.
func registerAtProtocol(t *testing.T, ts *httptest.Server, f *fakeGameServer,
	serverID string, protocol int, endpoint string) {
	t.Helper()

	pubPEM, err := signing.MarshalPublicKey(&serverKey.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(store.ServerRecord{
		ServerID:           serverID,
		Endpoint:           endpoint,
		MgmtEndpoint:       f.addr(),
		ProtocolVersion:    protocol,
		MaxPeers:           2048,
		MaxLobbies:         20,
		AllowDynamicCreate: true,
		ServerPublicKeyPEM: pubPEM,
	})
	resp, err := http.Post(ts.URL+"/v1/internal/register", "application/json",
		bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("register %s: status %d", serverID, resp.StatusCode)
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

type connectResp struct {
	Host            string `json:"host"`
	Port            int    `json:"port"`
	GameID          string `json:"game_id"`
	ProtocolVersion int    `json:"protocol_version"`
}

func createWith(t *testing.T, ts *httptest.Server, body string) (*http.Response, connectResp) {
	t.Helper()
	resp, err := http.Post(ts.URL+"/v1/games", "application/json", bytes.NewReader([]byte(body)))
	if err != nil {
		t.Fatal(err)
	}
	var out connectResp
	if resp.StatusCode == http.StatusOK {
		if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
			t.Fatalf("decode: %v", err)
		}
	}
	resp.Body.Close()
	return resp, out
}

func TestCreateHonoursStatedProtocol(t *testing.T) {
	ts := protoSetup(t)
	v9 := newFakeGameServer(t, true)
	v10 := newFakeGameServer(t, true)
	registerAtProtocol(t, ts, v9, "gs-v9", 9, "host-v9:7777")
	registerAtProtocol(t, ts, v10, "gs-v10", 10, "host-v10:7877")
	heartbeat(t, ts, "gs-v9", 0, 0, nil).Body.Close()
	heartbeat(t, ts, "gs-v10", 0, 0, nil).Body.Close()

	// Repeated, because the memory store iterates a map: one pass could match by
	// luck even with the filter removed.
	for i := 0; i < 25; i++ {
		resp, out := createWith(t, ts, `{"protocol_version":10,"mode":"arena","map":"parkour"}`)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("create at 10: status %d", resp.StatusCode)
		}
		if out.Host != "host-v10" || out.ProtocolVersion != 10 {
			t.Fatalf("create at 10 landed on %s:%d (protocol %d)",
				out.Host, out.Port, out.ProtocolVersion)
		}

		resp, out = createWith(t, ts, `{"protocol_version":9,"mode":"arena","map":"parkour"}`)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("create at 9: status %d", resp.StatusCode)
		}
		if out.Host != "host-v9" || out.ProtocolVersion != 9 {
			t.Fatalf("create at 9 landed on %s:%d (protocol %d)",
				out.Host, out.Port, out.ProtocolVersion)
		}
	}
}

// A shipped client that predates the field sends no protocol_version. It has to
// land on the generation it can actually speak, not on whichever host sorts
// first, which is the whole point of the assumed default.
func TestCreateWithoutProtocolUsesAssumed(t *testing.T) {
	ts := protoSetup(t)
	v9 := newFakeGameServer(t, true)
	v10 := newFakeGameServer(t, true)
	registerAtProtocol(t, ts, v9, "gs-v9", 9, "host-v9:7777")
	registerAtProtocol(t, ts, v10, "gs-v10", 10, "host-v10:7877")
	heartbeat(t, ts, "gs-v9", 0, 0, nil).Body.Close()
	heartbeat(t, ts, "gs-v10", 0, 0, nil).Body.Close()

	for i := 0; i < 25; i++ {
		resp, out := createWith(t, ts, `{"mode":"arena","map":"parkour"}`)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("status %d", resp.StatusCode)
		}
		if out.ProtocolVersion != assumedProtocol {
			t.Fatalf("unversioned create got protocol %d, want %d",
				out.ProtocolVersion, assumedProtocol)
		}
	}
}

// An empty body already meant "server defaults"; it must keep meaning that.
func TestCreateWithEmptyBodyStillWorks(t *testing.T) {
	ts := protoSetup(t)
	v9 := newFakeGameServer(t, true)
	registerAtProtocol(t, ts, v9, "gs-v9", 9, "host-v9:7777")
	heartbeat(t, ts, "gs-v9", 0, 0, nil).Body.Close()

	resp, err := http.Post(ts.URL+"/v1/games", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

func TestCreateRefusedWhenNoServerSpeaksProtocol(t *testing.T) {
	ts := protoSetup(t)
	v9 := newFakeGameServer(t, true)
	registerAtProtocol(t, ts, v9, "gs-v9", 9, "host-v9:7777")
	heartbeat(t, ts, "gs-v9", 0, 0, nil).Body.Close()

	resp, _ := createWith(t, ts, `{"protocol_version":11,"mode":"arena"}`)
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("status %d, want 503", resp.StatusCode)
	}
}

func TestJoinRefusesProtocolMismatch(t *testing.T) {
	ts := protoSetup(t)
	v10 := newFakeGameServer(t, true)
	registerAtProtocol(t, ts, v10, "gs-v10", 10, "host-v10:7877")
	heartbeat(t, ts, "gs-v10", 1, 1, []store.CachedGame{
		{GameID: "g-v10", ServerID: "gs-v10", MapID: "parkour", Mode: "arena"},
	}).Body.Close()

	// A v10 client joins its own generation's lobby.
	resp := joinAs(t, ts, "g-v10", `{"protocol_version":10}`)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("matching join: status %d", resp.StatusCode)
	}
	resp.Body.Close()

	// A v9 client must be told plainly rather than handed a token for a server
	// that will refuse its handshake.
	resp = joinAs(t, ts, "g-v10", `{"protocol_version":9}`)
	if resp.StatusCode != http.StatusConflict {
		t.Fatalf("mismatched join: status %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()

	// And the same for a client that states nothing, since assumed is 9 here.
	resp = joinAs(t, ts, "g-v10", "")
	if resp.StatusCode != http.StatusConflict {
		t.Fatalf("unversioned join: status %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()
}

func joinAs(t *testing.T, ts *httptest.Server, gameID, body string) *http.Response {
	t.Helper()
	var reader *bytes.Reader
	if body == "" {
		reader = bytes.NewReader(nil)
	} else {
		reader = bytes.NewReader([]byte(body))
	}
	resp, err := http.Post(fmt.Sprintf("%s/v1/games/%s/join", ts.URL, gameID),
		"application/json", reader)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestBrowseFiltersByProtocol(t *testing.T) {
	ts := protoSetup(t)
	v9 := newFakeGameServer(t, true)
	v10 := newFakeGameServer(t, true)
	registerAtProtocol(t, ts, v9, "gs-v9", 9, "host-v9:7777")
	registerAtProtocol(t, ts, v10, "gs-v10", 10, "host-v10:7877")
	heartbeat(t, ts, "gs-v9", 1, 1, []store.CachedGame{
		{GameID: "g-v9", ServerID: "gs-v9", MapID: "parkour", Mode: "arena"},
	}).Body.Close()
	heartbeat(t, ts, "gs-v10", 1, 1, []store.CachedGame{
		{GameID: "g-v10", ServerID: "gs-v10", MapID: "skydeck", Mode: "dm"},
	}).Body.Close()

	for _, tc := range []struct {
		query    string
		wantIDs  []string
		wantProt int
	}{
		{"?protocol=9", []string{"g-v9"}, 9},
		{"?protocol=10", []string{"g-v10"}, 10},
		{"", []string{"g-v9"}, assumedProtocol},
		{"?protocol=any", []string{"g-v9", "g-v10"}, 0},
		{"?protocol=0", []string{"g-v9", "g-v10"}, 0},
		{"?protocol=11", nil, 11},
	} {
		ids, prot := browse(t, ts, tc.query)
		if prot != tc.wantProt {
			t.Errorf("%q: reported protocol %d, want %d", tc.query, prot, tc.wantProt)
		}
		if len(ids) != len(tc.wantIDs) {
			t.Errorf("%q: got %v, want %v", tc.query, ids, tc.wantIDs)
			continue
		}
		seen := map[string]bool{}
		for _, id := range ids {
			seen[id] = true
		}
		for _, want := range tc.wantIDs {
			if !seen[want] {
				t.Errorf("%q: missing %s (got %v)", tc.query, want, ids)
			}
		}
	}
}

func TestBrowseRejectsBadProtocolQuery(t *testing.T) {
	ts := protoSetup(t)
	resp, err := http.Get(ts.URL + "/v1/games?protocol=banana")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status %d, want 400", resp.StatusCode)
	}
}

// A lobby whose owning server has expired has no protocol on record, and must
// not be listed: the owner is gone, so it is not joinable by anyone.
func TestBrowseDropsLobbiesWithNoLiveOwner(t *testing.T) {
	reg := serverreg.New(store.NewMemoryStore(), 30*time.Second, 60*time.Second)
	api := httpapi.New(reg, joinSecret, assumedProtocol)
	ts := httptest.NewServer(api.Mux)
	t.Cleanup(ts.Close)

	f := newFakeGameServer(t, true)
	registerAtProtocol(t, ts, f, "gs-v9", 9, "host-v9:7777")
	// A heartbeat naming a lobby owned by a server that never registered.
	heartbeat(t, ts, "gs-v9", 1, 1, []store.CachedGame{
		{GameID: "g-orphan", ServerID: "gs-gone", MapID: "parkour", Mode: "arena"},
	}).Body.Close()

	ids, _ := browse(t, ts, "?protocol=9")
	for _, id := range ids {
		if id == "g-orphan" {
			t.Fatal("a lobby with no live owner was listed")
		}
	}
}

func browse(t *testing.T, ts *httptest.Server, query string) ([]string, int) {
	t.Helper()
	resp, err := http.Get(ts.URL + "/v1/games" + query)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("browse%q: status %d", query, resp.StatusCode)
	}
	var out struct {
		Games []struct {
			GameID string `json:"game_id"`
		} `json:"games"`
		Protocol int `json:"protocol"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	ids := make([]string, 0, len(out.Games))
	for _, g := range out.Games {
		ids = append(ids, g.GameID)
	}
	return ids, out.Protocol
}
