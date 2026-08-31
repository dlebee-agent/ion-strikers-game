package store

import "time"

type ServerRecord struct {
	ServerID           string    `json:"server_id"`
	Endpoint           string    `json:"endpoint"`
	MgmtEndpoint       string    `json:"mgmt_endpoint"`
	BuildVersion       string    `json:"build_version"`
	ProtocolVersion    int       `json:"protocol_version"`
	MaxPeers           int       `json:"max_peers"`
	MaxLobbies         int       `json:"max_lobbies"`
	ActivePeers        int       `json:"active_peers"`
	ActiveLobbies      int       `json:"active_lobbies"`
	AllowDynamicCreate bool      `json:"allow_dynamic_create"`
	DevMode            bool      `json:"dev_mode"`
	LastHeartbeatAt    time.Time `json:"last_heartbeat_at"`

	// Keys established by the registration handshake. The server's public key
	// authenticates its heartbeats; the API keeps a private key minted for this
	// registration and the server holds the matching public key to verify
	// management commands.
	ServerPublicKeyPEM string `json:"server_public_key_pem"`
	APIPrivateKeyPEM   string `json:"api_private_key_pem"`
	APIPublicKeyPEM    string `json:"api_public_key_pem"`

	// Highest heartbeat timestamp accepted so far; older ones are replays.
	LastSignedAt int64 `json:"last_signed_at"`
}

type CachedGame struct {
	GameID       string `json:"game_id"`
	ServerID     string `json:"server_id"`
	DisplayName  string `json:"display_name"`
	Mode         string `json:"mode"`
	MapID        string `json:"map_id"`
	Players      int    `json:"players"`
	Humans       int    `json:"humans"`
	MaxPlayers   int    `json:"max"`
	Spectators   int    `json:"spectators"`
	MaxSpectators int   `json:"spec_max"`
	Capacity     int    `json:"capacity"`
	ScoreBlue    int    `json:"blue"`
	ScoreRed     int    `json:"red"`
	Round        int    `json:"round"`
	BotsShoot    bool   `json:"bots_shoot"`
	LifecycleState string `json:"lifecycle_state"`
}

// Store abstracts registry persistence. Implementations must be safe for
// concurrent use from a single process.
type Store interface {
	PutServer(rec ServerRecord, ttl time.Duration) error
	GetServer(serverID string) (ServerRecord, bool, error)
	ListServers() ([]ServerRecord, error)
	DeleteServer(serverID string) error

	PutGames(serverID string, games []CachedGame, ttl time.Duration) error
	ListGames() ([]CachedGame, error)

	// EvictExpired removes servers (and their games) whose TTL has elapsed.
	// Redis relies on native key expiry; in-memory must sweep.
	EvictExpired() error
}
