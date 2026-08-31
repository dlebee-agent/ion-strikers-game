// Package mgmt speaks the private Game API -> Game Server management wire.
//
// The transport is newline-delimited JSON over TCP because Godot has no
// built-in HTTP server; the Game Server listens with TCPServer. Every command
// is wrapped in a signed envelope so a server acts only on commands from the
// API it completed a handshake with, rather than anything that can reach the
// management port.
package mgmt

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"time"

	"ionstrikers.com/api/internal/signing"
	"ionstrikers.com/api/internal/store"
)

const dialTimeout = 5 * time.Second

// Envelope carries a signed command. Body is base64 so the exact bytes that
// were signed survive the round trip without depending on canonical JSON.
type Envelope struct {
	Body      string `json:"body"`
	Signature string `json:"sig"`
}

type CreateGameRequest struct {
	Op            string `json:"op"`
	Timestamp     int64  `json:"timestamp"`
	Mode          string `json:"mode"`
	Map           string `json:"map"`
	Rounds        int    `json:"rounds,omitempty"`
	Kills         int    `json:"kills,omitempty"`
	MaxPlayers    int    `json:"max_players"`
	MaxSpectators int    `json:"max_spectators"`
	Bots          bool   `json:"bots"`
	BotsShoot     bool   `json:"bots_shoot"`
	BotsMove      bool   `json:"bots_move"`
	BotSkill      string `json:"bot_skill,omitempty"`
	DisplayName   string `json:"display_name,omitempty"`
}

type JoinGameRequest struct {
	Op        string `json:"op"`
	Timestamp int64  `json:"timestamp"`
	GameID    string `json:"game_id"`
}

type CreateGameResponse struct {
	GameID string `json:"game_id"`
	Error  string `json:"error,omitempty"`
}

type JoinGameResponse struct {
	OK     bool   `json:"ok"`
	Reason string `json:"reason,omitempty"`
	Error  string `json:"error,omitempty"`
}

// CreateGame asks the server to create a lobby. The server rejects this when it
// was configured without allow_dynamic_create.
func CreateGame(srv store.ServerRecord, req CreateGameRequest) (CreateGameResponse, error) {
	req.Op = "create_game"
	req.Timestamp = time.Now().Unix()

	var out CreateGameResponse
	if err := roundTrip(srv, req, &out); err != nil {
		return CreateGameResponse{}, err
	}
	if out.Error != "" {
		return CreateGameResponse{}, fmt.Errorf("%s", out.Error)
	}
	if out.GameID == "" {
		return CreateGameResponse{}, fmt.Errorf("server returned no game_id")
	}
	return out, nil
}

// JoinGame asks the server to validate a slot before the player connects.
func JoinGame(srv store.ServerRecord, gameID string) (JoinGameResponse, error) {
	req := JoinGameRequest{
		Op:        "join_game",
		Timestamp: time.Now().Unix(),
		GameID:    gameID,
	}
	var out JoinGameResponse
	if err := roundTrip(srv, req, &out); err != nil {
		return JoinGameResponse{}, err
	}
	if out.Error != "" {
		return JoinGameResponse{}, fmt.Errorf("%s", out.Error)
	}
	return out, nil
}

func roundTrip(srv store.ServerRecord, req any, out any) error {
	priv, err := signing.ParsePrivateKey(srv.APIPrivateKeyPEM)
	if err != nil {
		return fmt.Errorf("api key for server %q unusable: %w", srv.ServerID, err)
	}

	bodyBytes, err := json.Marshal(req)
	if err != nil {
		return err
	}
	sig, err := signing.Sign(priv, bodyBytes)
	if err != nil {
		return fmt.Errorf("signing command: %w", err)
	}

	envelope, err := json.Marshal(Envelope{
		Body:      base64.StdEncoding.EncodeToString(bodyBytes),
		Signature: sig,
	})
	if err != nil {
		return err
	}

	conn, err := net.DialTimeout("tcp", srv.MgmtEndpoint, dialTimeout)
	if err != nil {
		return fmt.Errorf("dial %s: %w", srv.MgmtEndpoint, err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(dialTimeout))

	if _, err := conn.Write(append(envelope, '\n')); err != nil {
		return fmt.Errorf("write command: %w", err)
	}

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil && len(line) == 0 {
		return fmt.Errorf("read response: %w", err)
	}
	return json.Unmarshal(line, out)
}
