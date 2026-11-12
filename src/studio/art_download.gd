class_name ArtDownload
extends Node
## Downloads art packs (StudioArt), one after another: each to a part file,
## checked against its checksum, then moved into place. A download that fails
## or is cancelled leaves nothing behind. On Windows the download is curl's,
## which Windows ships; elsewhere it is Godot's own.

signal changed
signal finished(reason: String)

var running := false
var with_curl := OS.get_name() == "Windows"
## Bytes received of `total`, across every pack asked for.
var received := 0
var total := 0
var _packs: Array = []
var _done := 0
var _http: HTTPRequest
var _curl := {}
var _checking := -1
var _ending := false
var _end_reason := ""
var _end_deadline := 0

func start(packs: Array) -> void:
	if running:
		return
	_packs = packs.duplicate()
	if _packs.is_empty():
		finished.emit.call_deferred("")
		return
	running = true
	received = 0
	_done = 0
	total = StudioArt.bytes(_packs)
	DirAccess.make_dir_recursive_absolute(StudioArt.folder())
	var dir := DirAccess.open(StudioArt.folder())
	if dir == null or dir.get_space_left() < total:
		_end("there is not %d MB free in %s" % [total >> 20, StudioArt.folder()])
		return
	_next()

func cancel() -> void:
	if running:
		_end("it was cancelled")

func _part() -> String:
	return StudioArt.file(_packs[0]) + ".part"

func _next() -> void:
	if _packs.is_empty():
		_end("")
		return
	var url := StudioArt.url(_packs[0])
	DirAccess.remove_absolute(_part())
	if with_curl:
		var curl := OS.get_environment("SystemRoot").path_join("System32/curl.exe")
		if not FileAccess.file_exists(curl):
			_end("Windows' curl.exe, part of Windows 10 version 1803 and later, is missing")
			return
		_curl = OS.execute_with_pipe(curl, ["-sS", "--fail", "--location", "--output", _part(), url], false)
		if _curl.is_empty():
			_end("the download could not start")
		return
	if _http == null:
		_http = HTTPRequest.new()
		# Threaded HTTP uses blocking reads. Cancelling then joins that thread,
		# which can freeze the window indefinitely when a server stops replying.
		_http.use_threads = false
		_http.request_completed.connect(func(result: int, code: int, _headers, _body):
			if running and not _ending and _checking == -1:
				_downloaded(result == HTTPRequest.RESULT_SUCCESS and code == 200, "HTTP %d" % code if result == HTTPRequest.RESULT_SUCCESS else "network error %d" % result))
		add_child(_http)
	_http.download_file = _part()
	if _http.request(url) != OK:
		_end("the download could not start")

func _process(_dt: float) -> void:
	if not running:
		return
	if _ending:
		_finish_end()
		return
	if _checking != -1:
		if WorkerThreadPool.is_task_completed(_checking):
			WorkerThreadPool.wait_for_task_completion(_checking)
			_checking = -1
			_checked()
		return
	var f := FileAccess.open(_part(), FileAccess.READ)
	var now := _done + (f.get_length() if f else 0)
	if now != received:
		received = now
		changed.emit()
	if not _curl.is_empty() and not OS.is_process_running(_curl.pid):
		var said: String = _curl.stderr.get_buffer(4096).get_string_from_utf8().strip_edges()
		var code := OS.get_process_exit_code(_curl.pid)
		_curl = {}
		_downloaded(code == 0, said if said != "" else "curl exit code %d" % code)

var _sum := ""

func _downloaded(ok: bool, why: String) -> void:
	if not ok:
		_end("it could not be downloaded (%s)" % why)
		return
	var path := _part()
	_sum = ""
	_checking = WorkerThreadPool.add_task(func(): _sum = StudioArt.sha256(path))

func _checked() -> void:
	var pack: String = _packs[0]
	if _sum != String(StudioArt.lock().packs[pack].sha256):
		_end("the download does not match its checksum")
		return
	DirAccess.remove_absolute(StudioArt.file(pack))
	if DirAccess.rename_absolute(_part(), StudioArt.file(pack)) != OK:
		_end("it could not be moved into %s" % StudioArt.folder())
		return
	_done += StudioArt.size(pack)
	received = _done
	changed.emit()
	_packs.pop_front()
	_next()

func _end(reason: String) -> void:
	if _ending:
		return
	_ending = true
	_end_reason = reason
	_end_deadline = Time.get_ticks_msec() + 2000
	if not _curl.is_empty():
		OS.kill(_curl.pid)
		_curl = {}
	if _http:
		_http.cancel_request()
	if _checking != -1:
		WorkerThreadPool.wait_for_task_completion(_checking)
		_checking = -1
	_finish_end()

func _finish_end() -> void:
	if not _packs.is_empty():
		var part := _part()
		if FileAccess.file_exists(part) and DirAccess.remove_absolute(part) != OK:
			if Time.get_ticks_msec() < _end_deadline:
				return
			_end_reason += "; could not remove %s" % part
	running = false
	_packs = []
	_ending = false
	finished.emit(_end_reason)

func _exit_tree() -> void:
	if running:
		_end("Studio closed")
		while _ending:
			OS.delay_msec(1)
			_finish_end()
