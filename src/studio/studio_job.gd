class_name StudioJob
extends RefCounted
## Runs one of Studio's makes on a worker thread, so the game keeps drawing
## while it works. The work is plain data and models outside the tree (see
## Studio); the result comes back on the main thread, where scenes are built
## and the tree is touched. Hold the job while it runs.

signal finished(result: Dictionary)

var running := false
var _task := -1

## Starts `work` (returning a Dictionary) on the worker pool; `finished`
## fires with its result on the main thread, a frame after it's done.
## `first`, if given, is awaited on the main thread before that and its
## Dictionary handed to `work`; one with a `reason` is the result, and
## `work` never starts.
func run(tree: SceneTree, work: Callable, first := Callable()) -> void:
	if running:
		return
	running = true
	var out := {}
	if first.is_valid():
		var given: Dictionary = await first.call()
		if given.has("reason"):
			running = false
			finished.emit(given)
			return
		work = work.bind(given)
	_task = WorkerThreadPool.add_task(func(): out.merge(work.call(), true))
	while not WorkerThreadPool.is_task_completed(_task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(_task)
	running = false
	finished.emit(out)
