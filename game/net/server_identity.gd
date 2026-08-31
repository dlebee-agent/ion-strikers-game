class_name ServerIdentity
extends RefCounted

## The server's long-lived identity: a server_id and an RSA key pair, persisted
## so a restart keeps the same identity with the Game API instead of appearing
## as a brand new server.
##
## RSA rather than EdDSA because Godot's Crypto class only offers generate_rsa
## and signs with PKCS#1 v1.5 over SHA-256. That matches what the Go API verifies.

const KEY_BITS := 2048
const DEFAULT_DIR := "user://identity"

var server_id: String = ""
var key: CryptoKey = null

var _dir: String = DEFAULT_DIR


func _init(dir: String = DEFAULT_DIR) -> void:
	_dir = dir


## Loads a persisted identity, generating and saving one on first run.
func load_or_create(explicit_server_id: String = "") -> void:
	DirAccess.make_dir_recursive_absolute(_dir)

	var key_path := _dir.path_join("server.key")
	var id_path := _dir.path_join("server_id.txt")

	var crypto := Crypto.new()
	key = CryptoKey.new()

	if FileAccess.file_exists(key_path) and key.load(key_path) == OK:
		print("[identity] loaded key from %s" % key_path)
	else:
		print("[identity] generating %d-bit RSA key (first run)" % KEY_BITS)
		key = crypto.generate_rsa(KEY_BITS)
		if key.save(key_path) != OK:
			push_error("[identity] could not persist key to %s" % key_path)

	if not explicit_server_id.is_empty():
		server_id = explicit_server_id
	elif FileAccess.file_exists(id_path):
		var f := FileAccess.open(id_path, FileAccess.READ)
		if f:
			server_id = f.get_as_text().strip_edges()
			f.close()

	if server_id.is_empty():
		server_id = "srv-" + crypto.generate_random_bytes(8).hex_encode()

	var wf := FileAccess.open(id_path, FileAccess.WRITE)
	if wf:
		wf.store_string(server_id)
		wf.close()


## PEM public key to hand to the Game API at registration.
func public_key_pem() -> String:
	if key == null:
		return ""
	return key.save_to_string(true)


## Signs bytes with the server's private key. Returns base64, matching the
## encoding the Go side expects.
func sign(data: PackedByteArray) -> String:
	if key == null:
		return ""
	var sig := Crypto.new().sign(HashingContext.HASH_SHA256, _sha256(data), key)
	return Marshalls.raw_to_base64(sig)


## Verifies base64 signature over data using a PEM public key.
static func verify_with_pem(pem: String, data: PackedByteArray, signature_b64: String) -> bool:
	if pem.is_empty() or signature_b64.is_empty():
		return false

	var pub := CryptoKey.new()
	if pub.load_from_string(pem, true) != OK:
		push_error("[identity] could not parse public key PEM")
		return false

	var sig := Marshalls.base64_to_raw(signature_b64)
	if sig.is_empty():
		return false

	return Crypto.new().verify(HashingContext.HASH_SHA256, _sha256(data), sig, pub)


## PackedByteArray has no sha256 helper of its own; only String does.
static func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()
