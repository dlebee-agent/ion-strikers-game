package serverreg_test

import (
	"testing"
	"time"

	"ionstrikers.com/api/internal/serverreg"
	"ionstrikers.com/api/internal/signing"
	"ionstrikers.com/api/internal/store"
)

// A deployment mid-rollout: one generation of servers on the live protocol and
// one on the next, sharing a registry. Selection has to keep them apart, because
// handing a client the wrong generation fails at the ENet handshake with nothing
// in the API's answer explaining why.

func protoRegistry(t *testing.T) *serverreg.Registry {
	t.Helper()
	return serverreg.New(store.NewMemoryStore(), time.Minute, time.Minute)
}

func registerAt(t *testing.T, reg *serverreg.Registry, id string, protocol int,
	endpoint string, capacity int) {
	t.Helper()
	key, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatalf("keypair: %v", err)
	}
	pub, err := signing.MarshalPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	rec := store.ServerRecord{
		ServerID:           id,
		Endpoint:           endpoint,
		MgmtEndpoint:       "127.0.0.1:9090",
		ServerPublicKeyPEM: pub,
		ProtocolVersion:    protocol,
		AllowDynamicCreate: true,
		MaxLobbies:         capacity,
		MaxPeers:           100,
	}
	if _, err := reg.Register(rec); err != nil {
		t.Fatalf("register %s: %v", id, err)
	}
}

func TestSelectCreateHostMatchesProtocol(t *testing.T) {
	reg := protoRegistry(t)
	registerAt(t, reg, "gs-v9", 9, "host-v9:7777", 4)
	registerAt(t, reg, "gs-v10", 10, "host-v10:7877", 4)

	// Run each several times: the memory store iterates a map, so a filter that
	// merely happened to work once would pass a single attempt.
	for i := 0; i < 50; i++ {
		got, err := reg.SelectCreateHost(9)
		if err != nil {
			t.Fatalf("protocol 9: %v", err)
		}
		if got.ServerID != "gs-v9" {
			t.Fatalf("protocol 9 selected %q (protocol %d)", got.ServerID, got.ProtocolVersion)
		}
		got, err = reg.SelectCreateHost(10)
		if err != nil {
			t.Fatalf("protocol 10: %v", err)
		}
		if got.ServerID != "gs-v10" {
			t.Fatalf("protocol 10 selected %q (protocol %d)", got.ServerID, got.ProtocolVersion)
		}
	}
}

func TestSelectCreateHostRefusesUnknownProtocol(t *testing.T) {
	reg := protoRegistry(t)
	registerAt(t, reg, "gs-v9", 9, "host-v9:7777", 4)

	_, err := reg.SelectCreateHost(11)
	if err == nil {
		t.Fatal("expected a refusal for a protocol nothing serves")
	}
	// The message has to say which of the two reasons applied: "too old for this
	// deployment" and "we are full" call for different actions.
	if want := "no create-capable server speaks protocol 11"; err.Error() != want {
		t.Fatalf("error was %q, want %q", err.Error(), want)
	}
}

func TestSelectCreateHostCapacityBeatsProtocolMessage(t *testing.T) {
	reg := protoRegistry(t)
	// Matching protocol, no capacity: the answer is "full", not "wrong version".
	registerAt(t, reg, "gs-full", 9, "host:7777", 0)

	_, err := reg.SelectCreateHost(9)
	if err == nil {
		t.Fatal("expected a refusal when the only matching host is full")
	}
	if want := "no create-capable server with available capacity"; err.Error() != want {
		t.Fatalf("error was %q, want %q", err.Error(), want)
	}
}

func TestSelectCreateHostAnyProtocol(t *testing.T) {
	reg := protoRegistry(t)
	registerAt(t, reg, "gs-v10", 10, "host-v10:7877", 4)

	got, err := reg.SelectCreateHost(serverreg.AnyProtocol)
	if err != nil {
		t.Fatalf("AnyProtocol should ignore the version: %v", err)
	}
	if got.ServerID != "gs-v10" {
		t.Fatalf("selected %q", got.ServerID)
	}
}

func TestProtocolByServer(t *testing.T) {
	reg := protoRegistry(t)
	registerAt(t, reg, "gs-v9", 9, "host-v9:7777", 4)
	registerAt(t, reg, "gs-v10", 10, "host-v10:7877", 4)

	got, err := reg.ProtocolByServer()
	if err != nil {
		t.Fatalf("ProtocolByServer: %v", err)
	}
	if got["gs-v9"] != 9 || got["gs-v10"] != 10 {
		t.Fatalf("got %v", got)
	}
	if _, ok := got["gs-missing"]; ok {
		t.Fatal("an unregistered server should be absent, not zero")
	}
}

// A re-registration must carry the new protocol through, since that is how a
// pool announces it has been upgraded in place.
func TestReRegisterUpdatesProtocol(t *testing.T) {
	reg := protoRegistry(t)
	registerAt(t, reg, "gs-1", 9, "host:7777", 4)
	registerAt(t, reg, "gs-1", 10, "host:7777", 4)

	if _, err := reg.SelectCreateHost(9); err == nil {
		t.Fatal("the old protocol should no longer be served")
	}
	got, err := reg.SelectCreateHost(10)
	if err != nil {
		t.Fatalf("protocol 10 after re-register: %v", err)
	}
	if got.ProtocolVersion != 10 {
		t.Fatalf("record still reports protocol %d", got.ProtocolVersion)
	}
}
