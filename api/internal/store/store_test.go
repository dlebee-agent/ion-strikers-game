package store_test

import (
	"testing"
	"time"

	"ionstrikers.com/api/internal/store"

	"github.com/alicebob/miniredis/v2"
)

func testStoreScenarios(t *testing.T, s store.Store) {
	t.Helper()

	srv := store.ServerRecord{
		ServerID:           "s1",
		Endpoint:           "10.0.0.1:7777",
		MgmtEndpoint:       "http://10.0.0.1:9090",
		MaxPeers:           2048,
		MaxLobbies:         20,
		AllowDynamicCreate: true,
	}
	ded := store.ServerRecord{
		ServerID:           "d1",
		Endpoint:           "10.0.0.2:7777",
		MgmtEndpoint:       "http://10.0.0.2:9090",
		MaxPeers:           2048,
		MaxLobbies:         1,
		AllowDynamicCreate: false,
	}

	if err := s.PutServer(srv, 30*time.Second); err != nil {
		t.Fatal(err)
	}
	if err := s.PutServer(ded, 30*time.Second); err != nil {
		t.Fatal(err)
	}

	// both listed
	servers, err := s.ListServers()
	if err != nil {
		t.Fatal(err)
	}
	if len(servers) != 2 {
		t.Fatalf("expected 2 servers, got %d", len(servers))
	}

	// put games for both
	if err := s.PutGames("s1", []store.CachedGame{
		{GameID: "g1", ServerID: "s1"},
	}, 30*time.Second); err != nil {
		t.Fatal(err)
	}
	if err := s.PutGames("d1", []store.CachedGame{
		{GameID: "g2", ServerID: "d1"},
	}, 30*time.Second); err != nil {
		t.Fatal(err)
	}

	games, err := s.ListGames()
	if err != nil {
		t.Fatal(err)
	}
	if len(games) != 2 {
		t.Fatalf("expected 2 games, got %d", len(games))
	}

	// delete one server
	if err := s.DeleteServer("d1"); err != nil {
		t.Fatal(err)
	}
	servers, _ = s.ListServers()
	if len(servers) != 1 {
		t.Fatalf("expected 1 server after delete, got %d", len(servers))
	}
}

func TestMemoryStore(t *testing.T) {
	s := store.NewMemoryStore()
	testStoreScenarios(t, s)
}

func TestRedisStore(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatal(err)
	}
	defer mr.Close()

	rs, err := store.NewRedisStore("redis://"+mr.Addr(), "test:v1:")
	if err != nil {
		t.Fatal(err)
	}
	testStoreScenarios(t, rs)
}

func TestRedisPrefixIsolation(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatal(err)
	}
	defer mr.Close()

	s1, _ := store.NewRedisStore("redis://"+mr.Addr(), "deploy-a:")
	s2, _ := store.NewRedisStore("redis://"+mr.Addr(), "deploy-b:")

	srvA := store.ServerRecord{ServerID: "srv-a", Endpoint: "a:7777", MgmtEndpoint: "http://a:9090", AllowDynamicCreate: true}
	srvB := store.ServerRecord{ServerID: "srv-b", Endpoint: "b:7777", MgmtEndpoint: "http://b:9090", AllowDynamicCreate: true}

	s1.PutServer(srvA, 30*time.Second)
	s2.PutServer(srvB, 30*time.Second)

	list1, _ := s1.ListServers()
	list2, _ := s2.ListServers()

	if len(list1) != 1 || list1[0].ServerID != "srv-a" {
		t.Fatalf("deploy-a should only see srv-a, got %v", list1)
	}
	if len(list2) != 1 || list2[0].ServerID != "srv-b" {
		t.Fatalf("deploy-b should only see srv-b, got %v", list2)
	}
}

func TestMemoryTTLEviction(t *testing.T) {
	s := store.NewMemoryStore()
	ttl := 50 * time.Millisecond
	srv := store.ServerRecord{ServerID: "eph", Endpoint: "e:7777", MgmtEndpoint: "http://e:9090"}
	s.PutServer(srv, ttl)
	s.PutGames("eph", []store.CachedGame{{GameID: "g1", ServerID: "eph"}}, ttl)

	time.Sleep(ttl + 10*time.Millisecond)
	s.EvictExpired()

	servers, _ := s.ListServers()
	if len(servers) != 0 {
		t.Fatal("expected 0 servers after eviction")
	}
	games, _ := s.ListGames()
	if len(games) != 0 {
		t.Fatal("expected 0 games after eviction")
	}
}
