// Package signing implements the asymmetric message authentication used
// between the Game API and Game Servers.
//
// RSA with PKCS#1 v1.5 over SHA-256 is used rather than EdDSA because Godot's
// built-in Crypto class only exposes RSA (generate_rsa/sign/verify), and the
// Game Server runs in Godot. Godot signs with PSA_ALG_RSA_PKCS1V15_SIGN(SHA256),
// which is wire-compatible with rsa.SignPKCS1v15 here. Public keys cross the
// wire as PKIX PEM, which Godot's CryptoKey.load_from_string accepts.
package signing

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"fmt"
)

const KeyBits = 2048

// GenerateKeyPair returns a new RSA private key.
func GenerateKeyPair() (*rsa.PrivateKey, error) {
	return rsa.GenerateKey(rand.Reader, KeyBits)
}

// MarshalPublicKey encodes a public key as PKIX PEM ("BEGIN PUBLIC KEY").
func MarshalPublicKey(pub *rsa.PublicKey) (string, error) {
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		return "", err
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})), nil
}

// MarshalPrivateKey encodes a private key as PKCS#1 PEM, for persistence.
func MarshalPrivateKey(priv *rsa.PrivateKey) string {
	der := x509.MarshalPKCS1PrivateKey(priv)
	return string(pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: der}))
}

// ParsePublicKey accepts either PKIX ("PUBLIC KEY") or PKCS#1 ("RSA PUBLIC KEY") PEM.
func ParsePublicKey(pemStr string) (*rsa.PublicKey, error) {
	block, _ := pem.Decode([]byte(pemStr))
	if block == nil {
		return nil, fmt.Errorf("no PEM block found in public key")
	}

	if pub, err := x509.ParsePKIXPublicKey(block.Bytes); err == nil {
		rsaPub, ok := pub.(*rsa.PublicKey)
		if !ok {
			return nil, fmt.Errorf("public key is not RSA")
		}
		return rsaPub, nil
	}

	rsaPub, err := x509.ParsePKCS1PublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("unparseable public key: %w", err)
	}
	return rsaPub, nil
}

// ParsePrivateKey accepts PKCS#1 or PKCS#8 PEM.
func ParsePrivateKey(pemStr string) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(pemStr))
	if block == nil {
		return nil, fmt.Errorf("no PEM block found in private key")
	}

	if priv, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return priv, nil
	}

	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("unparseable private key: %w", err)
	}
	priv, ok := parsed.(*rsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("private key is not RSA")
	}
	return priv, nil
}

// Sign returns a base64 PKCS#1 v1.5 signature over SHA-256 of msg.
func Sign(priv *rsa.PrivateKey, msg []byte) (string, error) {
	digest := sha256.Sum256(msg)
	sig, err := rsa.SignPKCS1v15(rand.Reader, priv, crypto.SHA256, digest[:])
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(sig), nil
}

// Verify checks a base64 PKCS#1 v1.5 signature over SHA-256 of msg.
func Verify(pub *rsa.PublicKey, msg []byte, sigB64 string) error {
	sig, err := base64.StdEncoding.DecodeString(sigB64)
	if err != nil {
		return fmt.Errorf("signature is not valid base64: %w", err)
	}
	digest := sha256.Sum256(msg)
	return rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig)
}
