package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	ListenAddr      string
	HeartbeatTTL    time.Duration
	ProtocolVersion int

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
		ListenAddr:      envOr("LISTEN_ADDR", ":8080"),
		HeartbeatTTL:    envDuration("HEARTBEAT_TTL", 30*time.Second),
		ProtocolVersion: envInt("PROTOCOL_VERSION", 1),
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
