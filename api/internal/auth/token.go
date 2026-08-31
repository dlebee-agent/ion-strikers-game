package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"
)

// Token is a short-lived join credential returned to the client.
type Token struct {
	TokenID   string `json:"token_id"`
	GameID    string `json:"game_id"`
	ExpiresAt int64  `json:"expires_at"`
	Signature string `json:"signature"`
}

const tokenLifetime = 30 * time.Second

// Mint creates a signed join token for a game.
func Mint(secret, gameID string) Token {
	id := randomHex(16)
	exp := time.Now().Add(tokenLifetime).Unix()
	sig := sign(secret, id, gameID, exp)
	return Token{
		TokenID:   id,
		GameID:    gameID,
		ExpiresAt: exp,
		Signature: sig,
	}
}

// Verify checks that a token is valid and not expired.
func Verify(secret string, tok Token) error {
	if time.Now().Unix() > tok.ExpiresAt {
		return fmt.Errorf("token expired")
	}
	expected := sign(secret, tok.TokenID, tok.GameID, tok.ExpiresAt)
	if !hmac.Equal([]byte(expected), []byte(tok.Signature)) {
		return fmt.Errorf("invalid token signature")
	}
	return nil
}

func sign(secret, tokenID, gameID string, exp int64) string {
	mac := hmac.New(sha256.New, []byte(secret))
	fmt.Fprintf(mac, "%s:%s:%d", tokenID, gameID, exp)
	return hex.EncodeToString(mac.Sum(nil))
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
