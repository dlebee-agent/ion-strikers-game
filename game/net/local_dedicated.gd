class_name LocalDedicated
extends RefCounted

var pid: int = -1
var port: int = 7777


func start() -> int:
	port = _pick_port()
	var exe := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")

	var args: PackedStringArray = [
		"--path", project_path,
		"--headless",
		"--",
		"--dedicated", "--local",
		"--port", str(port),
		"--parent-pid", str(OS.get_process_id()),
	]

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
	return 7777
