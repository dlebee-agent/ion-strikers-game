extends Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--dedicated" in args:
		_start_server(args)
	else:
		get_tree().change_scene_to_file.call_deferred("res://scenes/menu/menu_shell.tscn")


func _start_server(args: PackedStringArray) -> void:
	var port := 7777
	var map_id := "parkour"
	var server_name := ""

	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		elif args[i] == "--map" and i + 1 < args.size():
			map_id = args[i + 1]
		elif args[i] == "--name" and i + 1 < args.size():
			server_name = args[i + 1]

	var server_scene := load("res://net/game_server.gd")
	var server_node: Node = server_scene.new()
	server_node.name = "GameServer"
	server_node.configure(port, map_id, server_name)
	get_tree().root.add_child.call_deferred(server_node)
	queue_free()
