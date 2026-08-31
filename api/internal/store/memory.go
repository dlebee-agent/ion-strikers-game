package store

import (
	"sync"
	"time"
)

type memEntry struct {
	server   ServerRecord
	games    []CachedGame
	expireAt time.Time
}

// MemoryStore is an in-process registry store with TTL-based expiry.
type MemoryStore struct {
	mu      sync.RWMutex
	servers map[string]*memEntry
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{servers: make(map[string]*memEntry)}
}

func (m *MemoryStore) PutServer(rec ServerRecord, ttl time.Duration) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	e, ok := m.servers[rec.ServerID]
	if ok {
		e.server = rec
		e.expireAt = time.Now().Add(ttl)
	} else {
		m.servers[rec.ServerID] = &memEntry{
			server:   rec,
			expireAt: time.Now().Add(ttl),
		}
	}
	return nil
}

func (m *MemoryStore) GetServer(serverID string) (ServerRecord, bool, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	e, ok := m.servers[serverID]
	if !ok || time.Now().After(e.expireAt) {
		return ServerRecord{}, false, nil
	}
	return e.server, true, nil
}

func (m *MemoryStore) ListServers() ([]ServerRecord, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	now := time.Now()
	out := make([]ServerRecord, 0, len(m.servers))
	for _, e := range m.servers {
		if now.After(e.expireAt) {
			continue
		}
		out = append(out, e.server)
	}
	return out, nil
}

func (m *MemoryStore) DeleteServer(serverID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.servers, serverID)
	return nil
}

func (m *MemoryStore) PutGames(serverID string, games []CachedGame, ttl time.Duration) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	e, ok := m.servers[serverID]
	if !ok {
		return nil
	}
	e.games = games
	e.expireAt = time.Now().Add(ttl)
	return nil
}

func (m *MemoryStore) ListGames() ([]CachedGame, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	now := time.Now()
	var out []CachedGame
	for _, e := range m.servers {
		if now.After(e.expireAt) {
			continue
		}
		out = append(out, e.games...)
	}
	return out, nil
}

func (m *MemoryStore) EvictExpired() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	for id, e := range m.servers {
		if now.After(e.expireAt) {
			delete(m.servers, id)
		}
	}
	return nil
}
