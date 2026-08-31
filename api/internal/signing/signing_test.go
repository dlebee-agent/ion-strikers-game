package signing_test

import (
	"strings"
	"testing"

	"ionstrikers.com/api/internal/signing"
)

func TestSignAndVerifyRoundTrip(t *testing.T) {
	key, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}

	msg := []byte(`{"op":"create_game","timestamp":1234567890}`)
	sig, err := signing.Sign(key, msg)
	if err != nil {
		t.Fatal(err)
	}
	if err := signing.Verify(&key.PublicKey, msg, sig); err != nil {
		t.Fatalf("valid signature did not verify: %v", err)
	}
}

func TestVerifyRejectsTamperedMessage(t *testing.T) {
	key, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}

	sig, err := signing.Sign(key, []byte("original"))
	if err != nil {
		t.Fatal(err)
	}
	if err := signing.Verify(&key.PublicKey, []byte("tampered"), sig); err == nil {
		t.Fatal("expected a signature over different bytes to fail")
	}
}

func TestVerifyRejectsWrongKey(t *testing.T) {
	signer, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}
	other, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}

	msg := []byte("payload")
	sig, err := signing.Sign(signer, msg)
	if err != nil {
		t.Fatal(err)
	}
	if err := signing.Verify(&other.PublicKey, msg, sig); err == nil {
		t.Fatal("expected verification against an unrelated key to fail")
	}
}

// The public key crosses the wire as PEM and is parsed back by the peer, so a
// round trip through that encoding must preserve verification.
func TestPublicKeySurvivesPEMRoundTrip(t *testing.T) {
	key, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}

	pem, err := signing.MarshalPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(pem, "BEGIN PUBLIC KEY") {
		t.Fatalf("expected PKIX PEM, got: %s", pem)
	}

	parsed, err := signing.ParsePublicKey(pem)
	if err != nil {
		t.Fatal(err)
	}

	msg := []byte("payload")
	sig, err := signing.Sign(key, msg)
	if err != nil {
		t.Fatal(err)
	}
	if err := signing.Verify(parsed, msg, sig); err != nil {
		t.Fatalf("signature did not verify against the re-parsed key: %v", err)
	}
}

func TestPrivateKeySurvivesPEMRoundTrip(t *testing.T) {
	key, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}

	parsed, err := signing.ParsePrivateKey(signing.MarshalPrivateKey(key))
	if err != nil {
		t.Fatal(err)
	}

	msg := []byte("payload")
	sig, err := signing.Sign(parsed, msg)
	if err != nil {
		t.Fatal(err)
	}
	if err := signing.Verify(&key.PublicKey, msg, sig); err != nil {
		t.Fatalf("re-parsed private key produced an unverifiable signature: %v", err)
	}
}

func TestParseRejectsGarbage(t *testing.T) {
	if _, err := signing.ParsePublicKey("not a pem block"); err == nil {
		t.Fatal("expected non-PEM input to be refused")
	}
	if _, err := signing.ParsePrivateKey("not a pem block"); err == nil {
		t.Fatal("expected non-PEM input to be refused")
	}
}

func TestVerifyRejectsNonBase64Signature(t *testing.T) {
	key, err := signing.GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}
	if err := signing.Verify(&key.PublicKey, []byte("payload"), "!!!not base64!!!"); err == nil {
		t.Fatal("expected a malformed signature to be refused")
	}
}
