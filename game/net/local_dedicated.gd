class_name LocalDedicated
extends RefCounted

## In-process local game server. Hosts a GameServer node under the scene tree
## root so it survives scene changes and needs no second OS process.

const DEFAULT_PORT := 7777
const LOCAL_BIND_IP := "127.0.0.1"

var server: Node = null
var port: int = DEFAULT_PORT
var admin_password: String = ""


func start() -> int:
	admin_password = _generate_password()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("[launcher] no SceneTree available")
		return -1

	server = load("res://net/game_server.gd").new()
	server.name = "LocalGameServer"
	server.bind_ip = LOCAL_BIND_IP
	server.allow_port_search = true
	server.configure(DEFAULT_PORT, -1, admin_password)
	server.set_max_lobbies(1)

	var failed := [false]
	server.bind_failed.connect(func(_e: int) -> void: failed[0] = true)
	tree.root.add_child(server)

	if failed[0]:
		server.queue_free()
		server = null
		push_error("[launcher] failed to bind local server")
		return -1

	port = server.actual_port
	print("[launcher] in-process server on port %d" % port)
	GameConsole.server_password = admin_password
	return port


func stop() -> void:
	if server != null and is_instance_valid(server):
		print("[launcher] stopping in-process server")
		if server.is_inside_tree():
			server.get_parent().remove_child(server)
		server.free()
	server = null


static func _generate_password() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(32)
	return bytes.hex_encode()
