class_name LocalDedicated
extends RefCounted

# Spawns and manages a headless dedicated server child process.

var pid: int = -1
var port: int = 7777


func start(map_id: String, server_name: String) -> int:
	port = _pick_port()
	var exe := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")

	var args: PackedStringArray = [
		"--path", project_path,
		"--headless",
		"--",
		"--dedicated", "--local",
		"--port", str(port),
		"--map", map_id,
	]
	if not server_name.is_empty():
		args.append("--name")
		args.append(server_name)

	pid = OS.create_process(exe, args)
	if pid <= 0:
		push_error("Failed to spawn dedicated server")
		return -1
	print("[launcher] spawned server pid=%d port=%d" % [pid, port])
	return port


func stop() -> void:
	if pid > 0:
		print("[launcher] killing server pid=%d" % pid)
		OS.kill(pid)
		pid = -1


func _pick_port() -> int:
	# Try 7777 first, then increment.  We can't probe UDP easily from GDScript
	# so we just try; if the server fails to bind it exits with code 1 and the
	# client retries on the next port.
	return 7777
