class_name GameApiClient
extends Node

## Player-facing HTTPS client for list/create/join. The Game API never sits
## on the gameplay path — after this returns host/port/token, the caller
## opens ENet and sends JoinAuth.

const DEFAULT_API_URL := "https://api.ionstrikers.com"

var api_url: String = DEFAULT_API_URL

const _TIMEOUT_S := 8.0


func _init() -> void:
	api_url = _read_api_url()


## Every call states the wire version this build speaks, so the API can pick a
## server that can actually talk to us. Without it the API has to guess from the
## version that shipped before this field existed, and a deployment running two
## generations of server would hand us one at random — refused at the ENet
## handshake, with nothing in the HTTP answer explaining why.
func list_games() -> Dictionary:
	return await _http(HTTPClient.METHOD_GET,
		"/v1/games?protocol=%d" % Protocol.PROTOCOL_VERSION)


func create_game(settings: Dictionary) -> Dictionary:
	var payload := settings.duplicate()
	payload["protocol_version"] = Protocol.PROTOCOL_VERSION
	return await _http(HTTPClient.METHOD_POST, "/v1/games", payload)


func join_game(game_id: String) -> Dictionary:
	return await _http(HTTPClient.METHOD_POST, "/v1/games/%s/join" % game_id,
		{"protocol_version": Protocol.PROTOCOL_VERSION})


func _read_api_url() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--api-url" and i + 1 < args.size():
			return args[i + 1].rstrip("/")
	return DEFAULT_API_URL


func _http(method: int, path: String, payload: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = _TIMEOUT_S
	add_child(http)

	var body := ""
	if payload != null:
		body = JSON.stringify(payload)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var err := http.request(api_url + path, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "Could not reach the Game API."}

	var completed: Array = await http.request_completed
	http.queue_free()

	var result: int = completed[0]
	var code: int = completed[1]
	var raw: PackedByteArray = completed[3]
	var text := raw.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Could not reach the Game API."}

	if code < 200 or code >= 300:
		var reason := text.strip_edges()
		if reason.is_empty():
			reason = "Game API error (HTTP %d)." % code
		return {"ok": false, "error": reason, "code": code}

	if text.is_empty():
		return {"ok": true}

	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Game API returned invalid JSON."}

	var data: Dictionary = json.data
	data["ok"] = true
	return data
