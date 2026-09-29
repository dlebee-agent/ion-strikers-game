package serverreg_test

import (
	"crypto/rsa"
	"testing"
	"time"

	"ionstrikers.com/api/internal/serverreg"
	"ionstrikers.com/api/internal/signing"
	"ionstrikers.com/api/internal/store"
)

const (
	ttl       = 30 * time.Second
	clockSkew = 60 * time.Second
)

// serverKey is generated once; RSA keygen is slow and the tests only need a
// valid key pair, not a distinct one per case.
var serverKey *rsa.PrivateKey

func init() {
	var err error
	serverKey, err = signing.GenerateKeyPair()
	if err != nil {
		panic(err)
	}
}

func publicKeyPEM(t *testing.T) string {
	t.Helper()
	pem, err := signing.MarshalPublicKey(&serverKey.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	return pem
}

func createCapable(t *testing.T, id string) store.ServerRecord {
	t.Helper()
	return store.ServerRecord{
		ServerID:           id,
		Endpoint:           "192.168.1.10:7777",
		MgmtEndpoint:       "192.168.1.10:9090",
		ProtocolVersion:    1,
		MaxPeers:           2048,
		MaxLobbies:         20,
		AllowDynamicCreate: true,
		ServerPublicKeyPEM: publicKeyPEM(t),
	}
}

func dedicated(t *testing.T, id string) store.ServerRecord {
	t.Helper()
	return store.ServerRecord{
		ServerID:           id,
		Endpoint:           "10.0.0.5:7777",
		MgmtEndpoint:       "10.0.0.5:9090",
		ProtocolVersion:    1,
		MaxPeers:           2048,
		MaxLobbies:         1,
		AllowDynamicCreate: false,
		ServerPublicKeyPEM: publicKeyPEM(t),
	}
}

func newRegistry() *serverreg.Registry {
	return serverreg.New(store.NewMemoryStore(), ttl, clockSkew)
}

// signedHeartbeat authenticates and applies a heartbeat the way the HTTP layer
// does, so tests exercise the real verification path.
func signedHeartbeat(t *testing.T, reg *serverreg.Registry, serverID string, ts int64, peers, lobbies int, games []store.CachedGame) error {
	t.Helper()
	body := []byte("heartbeat-payload")
	sig, err := signing.Sign(serverKey, body)
	if err != nil {
		t.Fatal(err)
	}
	srv, err := reg.VerifyServerMessage(serverID, body, sig, ts)
	if err != nil {
		return err
	}
	return reg.Heartbeat(srv, ts, peers, lobbies, games)
}

func TestRegisterReturnsAPIPublicKey(t *testing.T) {
	reg := newRegistry()

	apiPub, err := reg.Register(createCapable(t, "mgd-1"))
	if err != nil {
		t.Fatal(err)
	}
	if apiPub == "" {
		t.Fatal("registration returned no API public key")
	}
	if _, err := signing.ParsePublicKey(apiPub); err != nil {
		t.Fatalf("API public key is unusable: %v", err)
	}
}

func TestRegisterRequiresServerPublicKey(t *testing.T) {
	reg := newRegistry()

	rec := createCapable(t, "no-key")
	rec.ServerPublicKeyPEM = ""
	if _, err := reg.Register(rec); err == nil {
		t.Fatal("expected registration without a public key to be refused")
	}
}

func TestEachRegistrationGetsItsOwnAPIKey(t *testing.T) {
	reg := newRegistry()

	first, err := reg.Register(createCapable(t, "srv-a"))
	if err != nil {
		t.Fatal(err)
	}
	second, err := reg.Register(createCapable(t, "srv-b"))
	if err != nil {
		t.Fatal(err)
	}
	if first == second {
		t.Fatal("two registrations were issued the same API key")
	}
}

func TestHeartbeatRejectsForgedSignature(t *testing.T) {
	reg := newRegistry()
	if _, err := reg.Register(createCapable(t, "mgd-1")); err != nil {
		t.Fatal(err)
	}

	otherKey, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}
	body := []byte("heartbeat-payload")
	forged, err := signing.Sign(otherKey, body)
	if err != nil {
		t.Fatal(err)
	}

	_, err = reg.VerifyServerMessage("mgd-1", body, forged, time.Now().Unix())
	if err == nil {
		t.Fatal("expected a signature from the wrong key to be rejected")
	}
}

func TestHeartbeatRejectsReplay(t *testing.T) {
	reg := newRegistry()
	if _, err := reg.Register(createCapable(t, "mgd-1")); err != nil {
		t.Fatal(err)
	}

	ts := time.Now().Unix()
	if err := signedHeartbeat(t, reg, "mgd-1", ts, 0, 0, nil); err != nil {
		t.Fatal(err)
	}
	// Replaying the same timestamp must not be accepted a second time.
	if err := signedHeartbeat(t, reg, "mgd-1", ts, 0, 0, nil); err == nil {
		t.Fatal("expected replayed heartbeat to be rejected")
	}
}

func TestHeartbeatRejectsStaleClock(t *testing.T) {
	reg := newRegistry()
	if _, err := reg.Register(createCapable(t, "mgd-1")); err != nil {
		t.Fatal(err)
	}

	old := time.Now().Add(-10 * time.Minute).Unix()
	if err := signedHeartbeat(t, reg, "mgd-1", old, 0, 0, nil); err == nil {
		t.Fatal("expected heartbeat outside the clock skew window to be rejected")
	}
}

func TestHeartbeatRejectsUnregisteredServer(t *testing.T) {
	reg := newRegistry()

	if err := signedHeartbeat(t, reg, "never-registered", time.Now().Unix(), 0, 0, nil); err == nil {
		t.Fatal("expected heartbeat from an unregistered server to be rejected")
	}
}

func TestDedicatedIsListedButNeverACreateHost(t *testing.T) {
	reg := newRegistry()
	if _, err := reg.Register(dedicated(t, "ded-1")); err != nil {
		t.Fatal(err)
	}
	err := signedHeartbeat(t, reg, "ded-1", time.Now().Unix(), 4, 1, []store.CachedGame{
		{GameID: "dm-42", ServerID: "ded-1", DisplayName: "Frag Zone", Mode: "dm"},
	})
	if err != nil {
		t.Fatal(err)
	}

	games, err := reg.ListGames()
	if err != nil {
		t.Fatal(err)
	}
	if len(games) != 1 || games[0].GameID != "dm-42" {
		t.Fatalf("dedicated lobby should be discoverable, got %v", games)
	}

	if _, err := reg.SelectCreateHost(serverreg.AnyProtocol); err == nil {
		t.Fatal("a server that did not advertise create must not host new lobbies")
	}
}

func TestCreateHostPrefersCapableServer(t *testing.T) {
	reg := newRegistry()
	if _, err := reg.Register(dedicated(t, "ded-1")); err != nil {
		t.Fatal(err)
	}
	if _, err := reg.Register(createCapable(t, "mgd-1")); err != nil {
		t.Fatal(err)
	}
	now := time.Now().Unix()
	if err := signedHeartbeat(t, reg, "ded-1", now, 4, 1, nil); err != nil {
		t.Fatal(err)
	}
	if err := signedHeartbeat(t, reg, "mgd-1", now, 0, 0, nil); err != nil {
		t.Fatal(err)
	}

	host, err := reg.SelectCreateHost(serverreg.AnyProtocol)
	if err != nil {
		t.Fatal(err)
	}
	if host.ServerID != "mgd-1" {
		t.Fatalf("expected mgd-1, got %s", host.ServerID)
	}
}

func TestCreateHostSkipsServerAtLobbyLimit(t *testing.T) {
	reg := newRegistry()
	if _, err := reg.Register(createCapable(t, "mgd-full")); err != nil {
		t.Fatal(err)
	}
	if _, err := reg.Register(createCapable(t, "mgd-avail")); err != nil {
		t.Fatal(err)
	}

	now := time.Now().Unix()
	if err := signedHeartbeat(t, reg, "mgd-full", now, 800, 20, nil); err != nil {
		t.Fatal(err)
	}
	if err := signedHeartbeat(t, reg, "mgd-avail", now, 10, 2, nil); err != nil {
		t.Fatal(err)
	}

	host, err := reg.SelectCreateHost(serverreg.AnyProtocol)
	if err != nil {
		t.Fatal(err)
	}
	if host.ServerID != "mgd-avail" {
		t.Fatalf("expected mgd-avail, got %s", host.ServerID)
	}
}

func TestTTLEviction(t *testing.T) {
	shortTTL := 50 * time.Millisecond
	reg := serverreg.New(store.NewMemoryStore(), shortTTL, clockSkew)

	if _, err := reg.Register(createCapable(t, "ephemeral")); err != nil {
		t.Fatal(err)
	}
	if err := signedHeartbeat(t, reg, "ephemeral", time.Now().Unix(), 0, 0, []store.CachedGame{
		{GameID: "g1", ServerID: "ephemeral"},
	}); err != nil {
		t.Fatal(err)
	}

	servers, _ := reg.ListServers()
	if len(servers) != 1 {
		t.Fatal("server should be present before its TTL elapses")
	}

	time.Sleep(shortTTL + 10*time.Millisecond)
	if err := reg.Evict(); err != nil {
		t.Fatal(err)
	}

	if servers, _ = reg.ListServers(); len(servers) != 0 {
		t.Fatal("server should be evicted once heartbeats stop")
	}
	if games, _ := reg.ListGames(); len(games) != 0 {
		t.Fatal("games should be evicted with their server")
	}
}

func TestFindGameOwnerRoutesToOwningServer(t *testing.T) {
	reg := newRegistry()
	if _, err := reg.Register(createCapable(t, "srv-a")); err != nil {
		t.Fatal(err)
	}
	if _, err := reg.Register(dedicated(t, "srv-b")); err != nil {
		t.Fatal(err)
	}

	now := time.Now().Unix()
	if err := signedHeartbeat(t, reg, "srv-a", now, 10, 2, []store.CachedGame{
		{GameID: "game-100", ServerID: "srv-a"},
		{GameID: "game-101", ServerID: "srv-a"},
	}); err != nil {
		t.Fatal(err)
	}
	if err := signedHeartbeat(t, reg, "srv-b", now, 4, 1, []store.CachedGame{
		{GameID: "ded-200", ServerID: "srv-b"},
	}); err != nil {
		t.Fatal(err)
	}

	for gameID, wantServer := range map[string]string{
		"game-100": "srv-a",
		"ded-200":  "srv-b",
	} {
		owner, err := reg.FindGameOwner(gameID)
		if err != nil {
			t.Fatalf("%s: %v", gameID, err)
		}
		if owner.ServerID != wantServer {
			t.Fatalf("%s should belong to %s, got %s", gameID, wantServer, owner.ServerID)
		}
	}

	if _, err := reg.FindGameOwner("nonexistent"); err == nil {
		t.Fatal("expected an unknown game_id to be an error")
	}
}
