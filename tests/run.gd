extends SceneTree
## Headless test runner.
##   godot --headless --path . --script res://tests/run.gd -- contract terminal ...
## Each name is tests/<name>_test.gd, whose run(tree) returns a list of failures.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	quit(1 if await TestRunner.run(self, OS.get_cmdline_user_args()) else 0)
