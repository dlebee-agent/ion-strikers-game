package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"ionstrikers.com/api/internal/config"
	"ionstrikers.com/api/internal/httpapi"
	"ionstrikers.com/api/internal/serverreg"
	"ionstrikers.com/api/internal/store"
)

func main() {
	if len(os.Args) > 1 {
		runCLI(os.Args[1:])
		return
	}
	runServer()
}

func runServer() {
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		log.Fatalf("config error: %v", err)
	}

	st, err := makeStore(cfg)
	if err != nil {
		log.Fatalf("store init: %v", err)
	}
	reg := serverreg.New(st, cfg.HeartbeatTTL, cfg.MaxClockSkew)

	go evictLoop(reg, cfg.HeartbeatTTL)

	srv := httpapi.New(reg, cfg.JoinTokenSecret, cfg.AssumedProtocolVersion)
	log.Printf("[gameapi] listening on %s (store=%s)", cfg.ListenAddr, cfg.Store)
	if err := http.ListenAndServe(cfg.ListenAddr, srv.Mux); err != nil {
		log.Fatalf("listen: %v", err)
	}
}

func evictLoop(reg *serverreg.Registry, ttl time.Duration) {
	tick := time.NewTicker(ttl / 2)
	defer tick.Stop()
	for range tick.C {
		if err := reg.Evict(); err != nil {
			log.Printf("[gameapi] evict error: %v", err)
		}
	}
}

func makeStore(cfg config.Config) (store.Store, error) {
	switch cfg.Store {
	case "redis":
		return store.NewRedisStore(cfg.RedisURL, cfg.RedisKeyPrefix)
	default:
		return store.NewMemoryStore(), nil
	}
}

// --- CLI ---

func runCLI(args []string) {
	if len(args) == 0 {
		cliUsage()
		os.Exit(1)
	}
	apiURL := os.Getenv("GAME_API_URL")
	if apiURL == "" {
		apiURL = "http://localhost:8080"
	}

	switch args[0] {
	case "list":
		cliList(apiURL)
	case "create":
		cliCreate(apiURL)
	case "join":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "usage: gameapi join <game_id>")
			os.Exit(1)
		}
		cliJoin(apiURL, args[1])
	default:
		cliUsage()
		os.Exit(1)
	}
}

func cliUsage() {
	fmt.Fprintln(os.Stderr, "usage: gameapi [list | create | join <game_id>]")
	fmt.Fprintln(os.Stderr, "  With no arguments, starts the Game API server.")
	fmt.Fprintln(os.Stderr, "  Set GAME_API_URL to override the target (default http://localhost:8080).")
}

func cliList(apiURL string) {
	resp, err := http.Get(apiURL + "/v1/games")
	if err != nil {
		log.Fatalf("list: %v", err)
	}
	defer resp.Body.Close()
	var body json.RawMessage
	json.NewDecoder(resp.Body).Decode(&body)
	fmt.Println(string(body))
}

func cliCreate(apiURL string) {
	resp, err := http.Post(apiURL+"/v1/games", "application/json",
		http.NoBody)
	if err != nil {
		log.Fatalf("create: %v", err)
	}
	defer resp.Body.Close()
	var body json.RawMessage
	json.NewDecoder(resp.Body).Decode(&body)
	fmt.Println(string(body))
}

func cliJoin(apiURL, gameID string) {
	resp, err := http.Post(apiURL+"/v1/games/"+gameID+"/join", "application/json",
		http.NoBody)
	if err != nil {
		log.Fatalf("join: %v", err)
	}
	defer resp.Body.Close()
	var body json.RawMessage
	json.NewDecoder(resp.Body).Decode(&body)
	fmt.Println(string(body))
}
