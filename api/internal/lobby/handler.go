package lobby

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"ionstrikers.com/api/internal/auth"
	"ionstrikers.com/api/internal/mgmt"
	"ionstrikers.com/api/internal/serverreg"
	"ionstrikers.com/api/internal/store"
)

type Handler struct {
	Registry        *serverreg.Registry
	JoinTokenSecret string
}

// CreateRequest mirrors the web create screen fields.
type CreateRequest struct {
	Mode          string `json:"mode"`
	Map           string `json:"map"`
	Rounds        int    `json:"rounds,omitempty"`
	Kills         int    `json:"kills,omitempty"`
	MaxPlayers    int    `json:"max_players"`
	MaxSpectators int    `json:"max_spectators"`
	Bots          bool   `json:"bots"`
	BotsShoot     bool   `json:"bots_shoot"`
	BotsMove      bool   `json:"bots_move"`
	DisplayName   string `json:"display_name,omitempty"`
}

type ConnectResponse struct {
	Host      string     `json:"host"`
	Port      int        `json:"port"`
	GameID    string     `json:"game_id"`
	JoinToken auth.Token `json:"join_token"`
}

// ServeCreate handles POST /v1/games.
func (h *Handler) ServeCreate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CreateRequest
	if r.Body != nil {
		defer r.Body.Close()
		// An empty body is allowed; server-side defaults apply.
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil && err.Error() != "EOF" {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
	}

	srv, err := h.Registry.SelectCreateHost()
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}

	created, err := mgmt.CreateGame(srv, mgmt.CreateGameRequest{
		Mode:          req.Mode,
		Map:           req.Map,
		Rounds:        req.Rounds,
		Kills:         req.Kills,
		MaxPlayers:    req.MaxPlayers,
		MaxSpectators: req.MaxSpectators,
		Bots:          req.Bots,
		BotsShoot:     req.BotsShoot,
		BotsMove:      req.BotsMove,
		DisplayName:   req.DisplayName,
	})
	if err != nil {
		http.Error(w, fmt.Sprintf("game server rejected create: %v", err), http.StatusBadGateway)
		return
	}

	writeConnect(w, srv, created.GameID, h.JoinTokenSecret)
}

// ServeJoin handles POST /v1/games/{id}/join.
func (h *Handler) ServeJoin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	gameID := extractGameID(r.URL.Path)
	if gameID == "" {
		http.Error(w, "missing game_id", http.StatusBadRequest)
		return
	}

	srv, err := h.Registry.FindGameOwner(gameID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	// The cached snapshot is only a hint; the server decides.
	joined, err := mgmt.JoinGame(srv, gameID)
	if err != nil {
		http.Error(w, fmt.Sprintf("game server rejected join: %v", err), http.StatusBadGateway)
		return
	}
	if !joined.OK {
		http.Error(w, joined.Reason, http.StatusConflict)
		return
	}

	writeConnect(w, srv, gameID, h.JoinTokenSecret)
}

func writeConnect(w http.ResponseWriter, srv store.ServerRecord, gameID, secret string) {
	host, port := parseEndpoint(srv.Endpoint)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ConnectResponse{
		Host:      host,
		Port:      port,
		GameID:    gameID,
		JoinToken: auth.Mint(secret, gameID),
	})
}

func extractGameID(path string) string {
	// /v1/games/{id}/join
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) >= 4 && parts[0] == "v1" && parts[1] == "games" && parts[3] == "join" {
		return parts[2]
	}
	return ""
}

func parseEndpoint(endpoint string) (string, int) {
	host, portStr, err := net_SplitHostPort(endpoint)
	if err != nil {
		return endpoint, 7777
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return host, 7777
	}
	return host, port
}

// net_SplitHostPort is a thin wrapper so the fallback above stays readable.
func net_SplitHostPort(endpoint string) (string, string, error) {
	i := strings.LastIndex(endpoint, ":")
	if i < 0 {
		return "", "", fmt.Errorf("no port in %q", endpoint)
	}
	return endpoint[:i], endpoint[i+1:], nil
}
