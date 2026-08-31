package serverreg

import (
	"fmt"
	"time"

	"ionstrikers.com/api/internal/signing"
	"ionstrikers.com/api/internal/store"
)

// Registry manages game server registration, heartbeats, and host selection.
//
// Registration is open: any server may announce itself, because appearing in
// the browser grants no authority. What the handshake establishes is continuity
// — after registering, only the holder of the matching private key can
// heartbeat as that server_id, and only this API can issue management commands
// the server will act on.
type Registry struct {
	store        store.Store
	ttl          time.Duration
	maxClockSkew time.Duration
}

func New(s store.Store, heartbeatTTL, maxClockSkew time.Duration) *Registry {
	return &Registry{store: s, ttl: heartbeatTTL, maxClockSkew: maxClockSkew}
}

// Register completes the handshake: it records the server's public key and
// mints a fresh API key pair scoped to this registration. The returned PEM is
// the API public key the server must use to verify management commands.
func (r *Registry) Register(rec store.ServerRecord) (apiPublicKeyPEM string, err error) {
	if rec.ServerID == "" {
		return "", fmt.Errorf("server_id required")
	}
	if rec.Endpoint == "" {
		return "", fmt.Errorf("endpoint required")
	}
	if rec.MgmtEndpoint == "" {
		return "", fmt.Errorf("mgmt_endpoint required")
	}
	if rec.ServerPublicKeyPEM == "" {
		return "", fmt.Errorf("server_public_key_pem required")
	}
	if _, err := signing.ParsePublicKey(rec.ServerPublicKeyPEM); err != nil {
		return "", fmt.Errorf("server public key: %w", err)
	}

	apiKey, err := signing.GenerateKeyPair()
	if err != nil {
		return "", fmt.Errorf("minting API key pair: %w", err)
	}
	apiPub, err := signing.MarshalPublicKey(&apiKey.PublicKey)
	if err != nil {
		return "", fmt.Errorf("encoding API public key: %w", err)
	}

	rec.APIPrivateKeyPEM = signing.MarshalPrivateKey(apiKey)
	rec.APIPublicKeyPEM = apiPub
	rec.LastHeartbeatAt = time.Now()
	// A re-registration restarts the replay window along with the key pair.
	rec.LastSignedAt = 0

	if err := r.store.PutServer(rec, r.ttl); err != nil {
		return "", err
	}
	return apiPub, nil
}

// VerifyServerMessage authenticates a signed message from a registered server.
// signedBytes must be the exact bytes the server signed.
func (r *Registry) VerifyServerMessage(serverID string, signedBytes []byte, signature string, timestamp int64) (store.ServerRecord, error) {
	srv, ok, err := r.store.GetServer(serverID)
	if err != nil {
		return store.ServerRecord{}, err
	}
	if !ok {
		return store.ServerRecord{}, fmt.Errorf("server %q not registered", serverID)
	}

	if err := r.checkFreshness(timestamp, srv.LastSignedAt); err != nil {
		return store.ServerRecord{}, err
	}

	pub, err := signing.ParsePublicKey(srv.ServerPublicKeyPEM)
	if err != nil {
		return store.ServerRecord{}, fmt.Errorf("stored public key unusable: %w", err)
	}
	if err := signing.Verify(pub, signedBytes, signature); err != nil {
		return store.ServerRecord{}, fmt.Errorf("signature verification failed: %w", err)
	}
	return srv, nil
}

func (r *Registry) checkFreshness(timestamp, lastSeen int64) error {
	if timestamp == 0 {
		return fmt.Errorf("timestamp required")
	}
	drift := time.Since(time.Unix(timestamp, 0))
	if drift < 0 {
		drift = -drift
	}
	if drift > r.maxClockSkew {
		return fmt.Errorf("timestamp outside allowed clock skew")
	}
	if timestamp <= lastSeen {
		return fmt.Errorf("stale or replayed message")
	}
	return nil
}

// Heartbeat records a verified lobby snapshot and refreshes the TTL.
// The caller must have already authenticated the message.
func (r *Registry) Heartbeat(srv store.ServerRecord, timestamp int64, activePeers, activeLobbies int, games []store.CachedGame) error {
	srv.ActivePeers = activePeers
	srv.ActiveLobbies = activeLobbies
	srv.LastHeartbeatAt = time.Now()
	srv.LastSignedAt = timestamp

	if err := r.store.PutServer(srv, r.ttl); err != nil {
		return err
	}
	return r.store.PutGames(srv.ServerID, games, r.ttl)
}

// SelectCreateHost returns the first healthy, create-capable server with capacity.
// Servers that did not advertise allow_dynamic_create are never chosen; they are
// discoverable and joinable but do not host lobbies created through this API.
func (r *Registry) SelectCreateHost() (store.ServerRecord, error) {
	servers, err := r.store.ListServers()
	if err != nil {
		return store.ServerRecord{}, err
	}
	for _, s := range servers {
		if !s.AllowDynamicCreate {
			continue
		}
		if s.ActiveLobbies >= s.MaxLobbies {
			continue
		}
		if s.ActivePeers >= s.MaxPeers {
			continue
		}
		return s, nil
	}
	return store.ServerRecord{}, fmt.Errorf("no create-capable server with available capacity")
}

// FindGameOwner returns the server that owns a given game_id.
func (r *Registry) FindGameOwner(gameID string) (store.ServerRecord, error) {
	games, err := r.store.ListGames()
	if err != nil {
		return store.ServerRecord{}, err
	}
	for _, g := range games {
		if g.GameID == gameID {
			srv, ok, err := r.store.GetServer(g.ServerID)
			if err != nil {
				return store.ServerRecord{}, err
			}
			if !ok {
				return store.ServerRecord{}, fmt.Errorf("game %q owner server expired", gameID)
			}
			return srv, nil
		}
	}
	return store.ServerRecord{}, fmt.Errorf("game %q not found", gameID)
}

// ListGames returns all cached games from all registered servers.
func (r *Registry) ListGames() ([]store.CachedGame, error) {
	return r.store.ListGames()
}

// ListServers returns all registered, non-expired servers.
func (r *Registry) ListServers() ([]store.ServerRecord, error) {
	return r.store.ListServers()
}

// Evict removes expired entries from the store.
func (r *Registry) Evict() error {
	return r.store.EvictExpired()
}
