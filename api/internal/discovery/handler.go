package discovery

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"

	"ionstrikers.com/api/internal/serverreg"
	"ionstrikers.com/api/internal/store"
)

type Handler struct {
	Registry *serverreg.Registry

	// AssumedProtocolVersion applies when ?protocol is absent. Browse has to
	// filter for the same reason create does: a lobby a client cannot join is
	// worse than no lobby, because it looks joinable right up to the handshake.
	AssumedProtocolVersion int
}

type gameListResponse struct {
	Games []gameEntry `json:"games"`
	Dev   bool        `json:"dev,omitempty"`
	// Protocol the list was filtered to, so a caller can see which generation
	// it is looking at. Zero means unfiltered.
	Protocol int `json:"protocol"`
}

type gameEntry struct {
	GameID     string `json:"game_id"`
	Name       string `json:"name"`
	Mode       string `json:"mode"`
	Map        string `json:"map"`
	Players    int    `json:"players"`
	Humans     int    `json:"humans"`
	Max        int    `json:"max"`
	Spectators int    `json:"spectators"`
	SpecMax    int    `json:"spec_max"`
	Capacity   int    `json:"capacity"`
	Blue       int    `json:"blue"`
	Red        int    `json:"red"`
	Round      int    `json:"round"`
	BotsShoot  bool   `json:"bots_shoot"`
}

// ServeHTTP handles GET /v1/games.
//
// ?protocol=N restricts the list to lobbies hosted by a server speaking N.
// ?protocol=any (or 0) disables the filter, which is for operators looking at
// the whole deployment; a game client should always state its own version.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	wantProtocol, err := h.requestedProtocol(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	games, err := h.Registry.ListGames()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	protocolByServer := map[string]int{}
	if wantProtocol != serverreg.AnyProtocol {
		protocolByServer, err = h.Registry.ProtocolByServer()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
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
		// The Game Server process is not a lobby. A heartbeat row with no map
		// is the host itself (or a placeholder) and must not appear in browse.
		if g.MapID == "" {
			continue
		}
		// A lobby whose owning server has since expired has no protocol on
		// record. Dropping it is right either way: the owner is gone, so the
		// lobby is not joinable.
		if wantProtocol != serverreg.AnyProtocol {
			if got, ok := protocolByServer[g.ServerID]; !ok || got != wantProtocol {
				continue
			}
		}
		entries = append(entries, toEntry(g))
	}
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Players > entries[j].Players
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(gameListResponse{
		Games: entries, Dev: anyDev, Protocol: wantProtocol,
	})
}

// requestedProtocol reads ?protocol, falling back to the assumed version.
func (h *Handler) requestedProtocol(r *http.Request) (int, error) {
	raw := strings.TrimSpace(r.URL.Query().Get("protocol"))
	if raw == "" {
		return h.AssumedProtocolVersion, nil
	}
	if strings.EqualFold(raw, "any") {
		return serverreg.AnyProtocol, nil
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < 0 {
		return 0, fmt.Errorf("protocol must be a non-negative integer or \"any\"")
	}
	return n, nil
}

func toEntry(g store.CachedGame) gameEntry {
	return gameEntry{
		GameID:     g.GameID,
		Name:       g.DisplayName,
		Mode:       g.Mode,
		Map:        g.MapID,
		Players:    g.Players,
		Humans:     g.Humans,
		Max:        g.MaxPlayers,
		Spectators: g.Spectators,
		SpecMax:    g.MaxSpectators,
		Capacity:   g.Capacity,
		Blue:       g.ScoreBlue,
		Red:        g.ScoreRed,
		Round:      g.Round,
		BotsShoot:  g.BotsShoot,
	}
}
