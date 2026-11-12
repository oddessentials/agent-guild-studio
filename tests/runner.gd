class_name TestRunner
extends RefCounted
## Runs tests/<name>_test.gd files, each of whose run(tree) returns a list of
## failures; the number of failures. Used by tests/run.gd in the editor and by
## the exported app's --test option, so CI checks the shipped build itself.

## Counts script errors. One in a test, or in anything it loads, stops its
## run() part way, which then returns no failures as if it had passed.
class ScriptErrors extends Logger:
	var count := 0
	var _lock := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			_lock.lock()
			count += 1
			_lock.unlock()

static func run(tree: SceneTree, names: Array) -> int:
	var failed := 0
	var errors := ScriptErrors.new()
	OS.add_logger(errors)
	for name in names:
		print("RUN %s" % name)
		var before := errors.count
		var script: GDScript = load("res://tests/%s_test.gd" % name)
		if script == null or not script.can_instantiate():
			print("FAIL %s: did not load" % name)
			failed += 1
			continue
		var test = script.new()
		var failures: Array = await test.run(tree)
		if errors.count > before:
			failures.append("%d script error(s), printed above" % (errors.count - before))
		for f in failures:
			print("FAIL %s: %s" % [name, f])
		print("%s %s" % ["PASS" if failures.is_empty() else "FAIL", name])
		failed += failures.size()
	OS.remove_logger(errors)
	return failed

## Waits for cond to hold, frame by frame; false once timeout seconds pass,
## which only bounds a failure.
static func until(tree: SceneTree, cond: Callable, timeout := 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await tree.process_frame
	return true
