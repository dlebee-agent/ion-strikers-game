package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	ListenAddr   string
	HeartbeatTTL time.Duration

	// AssumedProtocolVersion is the wire version attributed to a client that
	// does not state one. Clients only began sending protocol_version when
	// protocol 10 shipped, so every request without it comes from a build on
	// the last version that predates the field.
	//
	// Getting this wrong is worse than it looks. Treating "absent" as "match
	// anything" would put an old client on whichever host the registry happened
	// to return first, which is the coin flip this filtering exists to remove.
	// So the default is a real version, not a wildcard, and it is configurable
	// because the right answer changes as old builds age out.
	AssumedProtocolVersion int

	// How far a signed message's timestamp may drift from our clock before it
	// is rejected. Guards replay without demanding tight clock sync.
	MaxClockSkew time.Duration

	// JoinTokenSecret signs player-facing join tokens. Unrelated to the
	// server handshake keys, which are minted per registration.
	JoinTokenSecret string

	Store          string // "memory" or "redis"
	RedisURL       string
	RedisKeyPrefix string
}

func Load() Config {
	return Config{
		ListenAddr:   envOr("LISTEN_ADDR", ":8080"),
		HeartbeatTTL: envDuration("HEARTBEAT_TTL", 30*time.Second),
		// PROTOCOL_VERSION is the older name for this and is still honoured, so
		// an existing environment file keeps working.
		AssumedProtocolVersion: envInt("ASSUMED_PROTOCOL_VERSION",
			envInt("PROTOCOL_VERSION", 9)),
		MaxClockSkew:    envDuration("MAX_CLOCK_SKEW", 60*time.Second),
		JoinTokenSecret: envOr("JOIN_TOKEN_SECRET", "dev-join-secret"),
		Store:           envOr("STORE", "memory"),
		RedisURL:        envOr("REDIS_URL", ""),
		RedisKeyPrefix:  envOr("REDIS_KEY_PREFIX", "ionstrikers:v1:"),
	}
}

func (c Config) Validate() error {
	switch c.Store {
	case "memory":
	case "redis":
		if c.RedisURL == "" {
			return fmt.Errorf("REDIS_URL required when STORE=redis")
		}
	default:
		return fmt.Errorf("unknown STORE %q (want memory or redis)", c.Store)
	}
	if c.JoinTokenSecret == "" {
		return fmt.Errorf("JOIN_TOKEN_SECRET must not be empty")
	}
	return nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}

func envDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}
