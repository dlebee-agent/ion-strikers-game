extends Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--dedicated" in args:
		_start_server(args)
	else:
		get_tree().change_scene_to_file.call_deferred("res://scenes/menu/menu_shell.tscn")


func _start_server(args: PackedStringArray) -> void:
	var port := 7777
	var parent_pid := -1
	var admin_password := ""
	var api_url := ""
	var register := false
	var allow_dynamic_create := false
	var mgmt_port := 9090
	var max_lobbies := 1
	var server_id := ""
	var public_host := "127.0.0.1"

	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		elif args[i] == "--parent-pid" and i + 1 < args.size():
			parent_pid = int(args[i + 1])
		elif args[i] == "--admin-password" and i + 1 < args.size():
			admin_password = args[i + 1]
		elif args[i] == "--api-url" and i + 1 < args.size():
			api_url = args[i + 1]
		elif args[i] == "--public-host" and i + 1 < args.size():
			public_host = args[i + 1]
		elif args[i] == "--register":
			register = true
		elif args[i] == "--allow-dynamic-create":
			allow_dynamic_create = true
		elif args[i] == "--mgmt-port" and i + 1 < args.size():
			mgmt_port = int(args[i + 1])
		elif args[i] == "--max-lobbies" and i + 1 < args.size():
			max_lobbies = int(args[i + 1])
		elif args[i] == "--server-id" and i + 1 < args.size():
			server_id = args[i + 1]

	if admin_password.is_empty():
		var crypto := Crypto.new()
		admin_password = crypto.generate_random_bytes(32).hex_encode()
		print("[server] admin password: %s" % admin_password)

	var server_scene := load("res://net/game_server.gd")
	var server_node: Node = server_scene.new()
	server_node.name = "GameServer"
	server_node.configure(port, parent_pid, admin_password)
	server_node.set_max_lobbies(max_lobbies)

	# Only servers that register need an identity; a local New Game does not.
	if register and not api_url.is_empty():
		var identity := ServerIdentity.new()
		identity.load_or_create(server_id)
		print("[server] identity %s (create=%s)" % [identity.server_id, allow_dynamic_create])

		var mgmt := MgmtServer.new()
		mgmt.name = "MgmtServer"
		mgmt.port = mgmt_port
		mgmt.allow_dynamic_create = allow_dynamic_create
		mgmt.configure(server_node.get_registry(), server_node)
		mgmt.lobby_created.connect(server_node.attach_instance)
		server_node.add_child(mgmt)

		var registrar := ApiRegistrar.new()
		registrar.name = "ApiRegistrar"
		registrar.api_url = api_url
		registrar.identity = identity
		registrar.endpoint = "%s:%d" % [public_host, port]
		registrar.mgmt_endpoint = "127.0.0.1:%d" % mgmt_port
		registrar.allow_dynamic_create = allow_dynamic_create
		registrar.max_peers = 2048
		registrar.max_lobbies = max_lobbies
		registrar.protocol_version = Protocol.PROTOCOL_VERSION
		registrar.dev_mode = DevMode.active
		registrar.configure(server_node.get_registry())
		# The handshake is what unlocks the management surface.
		registrar.api_key_received.connect(mgmt.set_api_public_key)
		server_node.add_child(registrar)

	get_tree().root.add_child.call_deferred(server_node)
	queue_free()
