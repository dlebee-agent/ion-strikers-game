package httpapi

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strings"

	"ionstrikers.com/api/internal/discovery"
	"ionstrikers.com/api/internal/lobby"
	"ionstrikers.com/api/internal/serverreg"
	"ionstrikers.com/api/internal/store"
)

// SignatureHeader carries the base64 signature over the exact request body.
const SignatureHeader = "X-Signature"

const maxBodyBytes = 1 << 20

type Server struct {
	Registry        *serverreg.Registry
	JoinTokenSecret string
	Mux             *http.ServeMux

	// AssumedProtocolVersion is handed to both handlers so create, join and
	// browse agree on what an unversioned client is. They must agree: a client
	// that browses as one generation and joins as another sees lobbies it is
	// then refused from.
	AssumedProtocolVersion int
}

func New(reg *serverreg.Registry, joinTokenSecret string, assumedProtocolVersion int) *Server {
	s := &Server{
		Registry:               reg,
		JoinTokenSecret:        joinTokenSecret,
		Mux:                    http.NewServeMux(),
		AssumedProtocolVersion: assumedProtocolVersion,
	}
	s.routes()
	return s
}

func (s *Server) routes() {
	disc := &discovery.Handler{
		Registry:               s.Registry,
		AssumedProtocolVersion: s.AssumedProtocolVersion,
	}
	lob := &lobby.Handler{
		Registry:               s.Registry,
		JoinTokenSecret:        s.JoinTokenSecret,
		AssumedProtocolVersion: s.AssumedProtocolVersion,
	}

	s.Mux.HandleFunc("/v1/games", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			disc.ServeHTTP(w, r)
		case http.MethodPost:
			lob.ServeCreate(w, r)
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	})

	s.Mux.HandleFunc("/v1/games/", func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/join") {
			lob.ServeJoin(w, r)
			return
		}
		http.NotFound(w, r)
	})

	s.Mux.HandleFunc("/v1/internal/register", s.handleRegister)
	s.Mux.HandleFunc("/v1/internal/heartbeat", s.handleHeartbeat)
	s.Mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
}

type registerResponse struct {
	Status          string `json:"status"`
	ServerID        string `json:"server_id"`
	APIPublicKeyPEM string `json:"api_public_key_pem"`
}

// handleRegister completes the handshake. It is deliberately unauthenticated:
// being listed grants no authority, and the key exchange is what secures every
// later message in both directions.
func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := readBody(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var rec store.ServerRecord
	if err := json.Unmarshal(body, &rec); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	apiPub, err := s.Registry.Register(rec)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	log.Printf("[api] registered server %q endpoint=%s allow_dynamic_create=%v",
		rec.ServerID, rec.Endpoint, rec.AllowDynamicCreate)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(registerResponse{
		Status:          "registered",
		ServerID:        rec.ServerID,
		APIPublicKeyPEM: apiPub,
	})
}

type heartbeatRequest struct {
	ServerID      string             `json:"server_id"`
	Timestamp     int64              `json:"timestamp"`
	ActivePeers   int                `json:"active_peers"`
	ActiveLobbies int                `json:"active_lobbies"`
	Games         []store.CachedGame `json:"games"`
}

func (s *Server) handleHeartbeat(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := readBody(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var req heartbeatRequest
	if err := json.Unmarshal(body, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	signature := r.Header.Get(SignatureHeader)
	if signature == "" {
		http.Error(w, "missing "+SignatureHeader, http.StatusUnauthorized)
		return
	}

	srv, err := s.Registry.VerifyServerMessage(req.ServerID, body, signature, req.Timestamp)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	if err := s.Registry.Heartbeat(srv, req.Timestamp, req.ActivePeers, req.ActiveLobbies, req.Games); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// readBody returns the exact bytes the peer sent, which is what signatures cover.
func readBody(r *http.Request) ([]byte, error) {
	defer r.Body.Close()
	return io.ReadAll(io.LimitReader(r.Body, maxBodyBytes))
}
