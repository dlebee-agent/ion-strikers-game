package store

import (
	"context"
	"encoding/json"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisStore uses Redis for registry persistence so multiple API replicas
// share the same view. Every key is prefixed with a configurable namespace.
type RedisStore struct {
	client *redis.Client
	prefix string
}

func NewRedisStore(url, prefix string) (*RedisStore, error) {
	opts, err := redis.ParseURL(url)
	if err != nil {
		return nil, err
	}
	return &RedisStore{
		client: redis.NewClient(opts),
		prefix: prefix,
	}, nil
}

func (r *RedisStore) serverKey(id string) string   { return r.prefix + "srv:" + id }
func (r *RedisStore) gamesKey(id string) string     { return r.prefix + "games:" + id }
func (r *RedisStore) serverIndexKey() string         { return r.prefix + "srv_index" }

func (r *RedisStore) PutServer(rec ServerRecord, ttl time.Duration) error {
	ctx := context.Background()
	data, err := json.Marshal(rec)
	if err != nil {
		return err
	}
	pipe := r.client.Pipeline()
	pipe.Set(ctx, r.serverKey(rec.ServerID), data, ttl)
	pipe.SAdd(ctx, r.serverIndexKey(), rec.ServerID)
	_, err = pipe.Exec(ctx)
	return err
}

func (r *RedisStore) GetServer(serverID string) (ServerRecord, bool, error) {
	ctx := context.Background()
	data, err := r.client.Get(ctx, r.serverKey(serverID)).Bytes()
	if err == redis.Nil {
		return ServerRecord{}, false, nil
	}
	if err != nil {
		return ServerRecord{}, false, err
	}
	var rec ServerRecord
	if err := json.Unmarshal(data, &rec); err != nil {
		return ServerRecord{}, false, err
	}
	return rec, true, nil
}

func (r *RedisStore) ListServers() ([]ServerRecord, error) {
	ctx := context.Background()
	ids, err := r.client.SMembers(ctx, r.serverIndexKey()).Result()
	if err != nil {
		return nil, err
	}
	if len(ids) == 0 {
		return nil, nil
	}
	keys := make([]string, len(ids))
	for i, id := range ids {
		keys[i] = r.serverKey(id)
	}
	vals, err := r.client.MGet(ctx, keys...).Result()
	if err != nil {
		return nil, err
	}
	var out []ServerRecord
	for _, v := range vals {
		s, ok := v.(string)
		if !ok || s == "" {
			continue
		}
		var rec ServerRecord
		if err := json.Unmarshal([]byte(s), &rec); err != nil {
			continue
		}
		out = append(out, rec)
	}
	return out, nil
}

func (r *RedisStore) DeleteServer(serverID string) error {
	ctx := context.Background()
	pipe := r.client.Pipeline()
	pipe.Del(ctx, r.serverKey(serverID))
	pipe.Del(ctx, r.gamesKey(serverID))
	pipe.SRem(ctx, r.serverIndexKey(), serverID)
	_, err := pipe.Exec(ctx)
	return err
}

func (r *RedisStore) PutGames(serverID string, games []CachedGame, ttl time.Duration) error {
	ctx := context.Background()
	data, err := json.Marshal(games)
	if err != nil {
		return err
	}
	return r.client.Set(ctx, r.gamesKey(serverID), data, ttl).Err()
}

func (r *RedisStore) ListGames() ([]CachedGame, error) {
	ctx := context.Background()

	var cursor uint64
	var allKeys []string
	pattern := r.prefix + "games:*"
	for {
		keys, next, err := r.client.Scan(ctx, cursor, pattern, 100).Result()
		if err != nil {
			return nil, err
		}
		allKeys = append(allKeys, keys...)
		cursor = next
		if cursor == 0 {
			break
		}
	}
	if len(allKeys) == 0 {
		return nil, nil
	}

	vals, err := r.client.MGet(ctx, allKeys...).Result()
	if err != nil {
		return nil, err
	}
	var out []CachedGame
	for _, v := range vals {
		s, ok := v.(string)
		if !ok || s == "" {
			continue
		}
		var games []CachedGame
		if err := json.Unmarshal([]byte(s), &games); err != nil {
			continue
		}
		out = append(out, games...)
	}
	return out, nil
}

func (r *RedisStore) EvictExpired() error {
	ctx := context.Background()
	ids, err := r.client.SMembers(ctx, r.serverIndexKey()).Result()
	if err != nil {
		return err
	}
	for _, id := range ids {
		exists, err := r.client.Exists(ctx, r.serverKey(id)).Result()
		if err != nil {
			continue
		}
		if exists == 0 {
			r.client.Del(ctx, r.gamesKey(id))
			r.client.SRem(ctx, r.serverIndexKey(), id)
		}
	}
	return nil
}

// Ping checks Redis connectivity.
func (r *RedisStore) Ping() error {
	return r.client.Ping(context.Background()).Err()
}

// Close shuts down the Redis client.
func (r *RedisStore) Close() error {
	return r.client.Close()
}

// compile-time interface check
var _ Store = (*RedisStore)(nil)
