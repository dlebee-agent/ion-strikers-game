package discovery

import (
	"encoding/json"
	"net/http"
	"sort"

	"ionstrikers.com/api/internal/serverreg"
	"ionstrikers.com/api/internal/store"
)

type Handler struct {
	Registry *serverreg.Registry
}

type gameListResponse struct {
	Games []gameEntry `json:"games"`
	Dev   bool        `json:"dev,omitempty"`
}

type gameEntry struct {
	GameID      string `json:"game_id"`
	Name        string `json:"name"`
	Mode        string `json:"mode"`
	Map         string `json:"map"`
	Players     int    `json:"players"`
	Humans      int    `json:"humans"`
	Max         int    `json:"max"`
	Spectators  int    `json:"spectators"`
	SpecMax     int    `json:"spec_max"`
	Capacity    int    `json:"capacity"`
	Blue        int    `json:"blue"`
	Red         int    `json:"red"`
	Round       int    `json:"round"`
	BotsShoot   bool   `json:"bots_shoot"`
}

// ServeHTTP handles GET /v1/games.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	games, err := h.Registry.ListGames()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Check if any registered server has dev mode enabled.
	servers, _ := h.Registry.ListServers()
	anyDev := false
	for _, s := range servers {
		if s.DevMode {
			anyDev = true
			break
		}
	}

	entries := make([]gameEntry, 0, len(games))
	for _, g := range games {
		if g.LifecycleState == "over" {
			continue
		}
		entries = append(entries, toEntry(g))
	}
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Players > entries[j].Players
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(gameListResponse{Games: entries, Dev: anyDev})
}

func toEntry(g store.CachedGame) gameEntry {
	return gameEntry{
		GameID:    g.GameID,
		Name:      g.DisplayName,
		Mode:      g.Mode,
		Map:       g.MapID,
		Players:   g.Players,
		Humans:    g.Humans,
		Max:       g.MaxPlayers,
		Spectators: g.Spectators,
		SpecMax:   g.MaxSpectators,
		Capacity:  g.Capacity,
		Blue:      g.ScoreBlue,
		Red:       g.ScoreRed,
		Round:     g.Round,
		BotsShoot: g.BotsShoot,
	}
}
