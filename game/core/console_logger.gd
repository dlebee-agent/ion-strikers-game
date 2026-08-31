extends Logger

var _mutex := Mutex.new()
var _pending: Array[Dictionary] = []

const MAX_PENDING := 500


func _log_message(message: String, error: bool) -> void:
	_mutex.lock()
	if _pending.size() < MAX_PENDING:
		_pending.append({"text": message.strip_edges(), "level": "error" if error else "print"})
	_mutex.unlock()


func _log_error(function: String, file: String, line: int, code: String,
		rationale: String, _editor_notify: bool, error_type: int,
		_script_backtraces: Array[ScriptBacktrace] = []) -> void:
	var detail := rationale if not rationale.is_empty() else code
	var level := "warning" if error_type == ErrorType.ERROR_TYPE_WARNING else "error"
	var text := "%s (%s:%d)" % [detail, file.get_file(), line]
	_mutex.lock()
	if _pending.size() < MAX_PENDING:
		_pending.append({"text": text, "level": level})
	_mutex.unlock()


func drain() -> Array[Dictionary]:
	_mutex.lock()
	var out := _pending.duplicate()
	_pending.clear()
	_mutex.unlock()
	return out
