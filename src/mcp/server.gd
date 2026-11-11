class_name McpServer
extends Node

const MODERN := "2026-07-28"
const LEGACY := ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
const SUPPORTED := ["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
const META_VERSION := "io.modelcontextprotocol/protocolVersion"
const META_CAPABILITIES := "io.modelcontextprotocol/clientCapabilities"
const META_SERVER := "io.modelcontextprotocol/serverInfo"
const SERVER_INFO := {"name": "agent-guild-studio", "title": "Agent Guild: Studio", "version": "1"}
const PARSE_ERROR := -32700
const INVALID_REQUEST := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602
const UNSUPPORTED_VERSION := -32022
const PERSON_WAIT_MS := 30000
const WINDOW_INIT := "studio-window-initialize"
const WITHOUT_WINDOW := []
const INSTRUCTIONS := "Agent Guild: Studio makes characters and companions for Agent Guild from a model file, or by recoloring one of a world's own looks. It works without a window.
Start with list_slots: a piece is made for one slot, a world's crew such as guild/anthropic, or a world's companions such as guild/companion.
make_character takes one model (.glb, .gltf or .vrm); make_companions takes one model or four; recolor_look changes a world's own look. Each writes a piece folder at `to` and checks it. A world's art downloads the first time it is needed, which can take a while.
When Studio can't be sure of a model's bones, make_character says which, and you call it again with `bones`.
Use check_piece on any piece folder. show_window opens Studio for the person."

var host: Node
var tools: McpTools
var read_stdin := true
var write_line := func(line: String): print(line)
var relay := false
var window_args: Array = []
var launch_window := _launch_window
var write_window := _write_window
var _thread: Thread
var _legacy_version := ""
var _queue: Array = []
var _active: Dictionary = {}
var _waiting_since := -1
var _closed := false
var _window := {}
var _window_open := false
var _window_threads: Array = []
var _forwarded := {}

func _ready() -> void:
	tools = McpTools.new(self)
	if read_stdin:
		_thread = Thread.new()
		_thread.start(_read_lines.bind(OS.read_buffer_from_stdin.bind(1), receive, _stdin_closed))

# One byte at a time: on Windows pipes, larger reads return stale memory
# past the real data (godotengine/godot#124296).
static func _read_lines(next: Callable, got: Callable, ended: Callable) -> void:
	var line := PackedByteArray()
	while true:
		var b: PackedByteArray = next.call()
		if b.is_empty():
			break
		if b[0] == 10:
			got.call_deferred(line.get_string_from_utf8())
			line = PackedByteArray()
		else:
			line.append(b[0])
	if not line.is_empty():
		got.call_deferred(line.get_string_from_utf8())
	ended.call_deferred()

func _stdin_closed() -> void:
	_closed = true
	_queue.clear()
	if _thread and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
	if _window_open:
		if not _window.is_empty():
			_window.stdio.close()
		return
	if host and host.has_method("agent_disconnected"):
		host.agent_disconnected()

func _exit_tree() -> void:
	if _thread and _thread.is_started() and not _thread.is_alive():
		_thread.wait_to_finish()

func _process(_delta: float) -> void:
	if not _queue.is_empty():
		_pump()

func receive(text: String) -> void:
	text = text.strip_edges()
	if text == "" or _closed:
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		_send_error(null, PARSE_ERROR, "Parse error: " + json.get_error_message())
		return
	var msg = json.data
	if msg is Array:
		_send_error(null, INVALID_REQUEST, "Batches aren't supported. Send one message per line.")
		return
	if not msg is Dictionary or msg.get("jsonrpc") != "2.0":
		_send_error(_id_of(msg), INVALID_REQUEST, "Not a JSON-RPC 2.0 message.")
		return
	if not msg.has("method"):
		return
	if not msg.method is String:
		_send_error(_id_of(msg), INVALID_REQUEST, "The method must be a string.")
		return
	if not msg.has("id"):
		_notification_received(msg)
		return
	var id = _id_of(msg)
	if id == null:
		_send_error(null, INVALID_REQUEST, "A request id must be a string or an integer.")
		return
	_queue.append(msg)
	_pump()

static func _id_of(msg: Variant) -> Variant:
	if not msg is Dictionary or not msg.has("id"):
		return null
	var id = msg.id
	if id is String:
		return id
	if (id is float or id is int) and float(id) == floorf(float(id)):
		return int(id)
	return null

func _notification_received(msg: Dictionary) -> void:
	if msg.method != "notifications/cancelled":
		return
	var params = msg.get("params", {})
	if not params is Dictionary:
		return
	var id = _id_of({"id": params.get("requestId")})
	if id == null:
		return
	for i in _queue.size():
		var queued = _id_of(_queue[i])
		if typeof(queued) == typeof(id) and queued == id:
			_queue.remove_at(i)
			if i == 0:
				_waiting_since = -1
			return
	if _forwarded.has(id):
		_forwarded.erase(id)
		write_window.call(JSON.stringify(msg))
		return
	if not _active.is_empty() and typeof(_active.ctx.id) == typeof(id) and _active.ctx.id == id:
		_active.ctx.cancelled = true
		tools.cancel(_active.ctx)

## Runs waiting requests in order. A world being opened holds the queue; while a
## render runs, reading tools still answer and edits are told it's busy.
func _pump() -> void:
	while not _queue.is_empty():
		if not _active.is_empty() and not _active.long:
			return
		var msg: Dictionary = _queue[0]
		var call := _tool_call(msg)
		if not _active.is_empty() and call != "" and not tools.can_run_while_rendering(call):
			_queue.pop_front()
			var ctx := _context(msg)
			if not ctx.has("error"):
				respond(ctx, tools.failure("Studio is making a piece. Wait for it to finish, then try again."))
			continue
		if call != "" and tools.waits_for_person(call):
			if _waiting_since < 0:
				_waiting_since = Time.get_ticks_msec()
			if Time.get_ticks_msec() - _waiting_since < PERSON_WAIT_MS:
				return
			_queue.pop_front()
			_waiting_since = -1
			var waited := _context(msg)
			if not waited.has("error"):
				respond(waited, tools.failure("The person has been editing for a while. Try again in a moment."))
			continue
		_waiting_since = -1
		_queue.pop_front()
		_dispatch(msg)

func _tool_call(msg: Dictionary) -> String:
	if msg.method != "tools/call" or not msg.get("params") is Dictionary:
		return ""
	return str(msg.params.get("name", ""))

func _context(msg: Dictionary) -> Dictionary:
	var ctx := {"id": _id_of(msg), "modern": false, "progress_token": null, "progress": -1.0, "cancelled": false}
	var params = msg.get("params", {})
	if not params is Dictionary:
		_send_error(ctx.id, INVALID_PARAMS, "params must be an object.")
		return {"error": true}
	var meta = params.get("_meta", {})
	if not meta is Dictionary:
		_send_error(ctx.id, INVALID_PARAMS, "_meta must be an object.")
		return {"error": true}
	if meta.has("progressToken") and (meta.progressToken is String or meta.progressToken is float or meta.progressToken is int):
		ctx.progress_token = meta.progressToken
	if meta.has(META_VERSION):
		if meta[META_VERSION] != MODERN:
			_send({"jsonrpc": "2.0", "id": ctx.id, "error": {"code": UNSUPPORTED_VERSION, "message": "Unsupported protocol version",
				"data": {"supported": SUPPORTED, "requested": meta[META_VERSION]}}})
			return {"error": true}
		if not meta.get(META_CAPABILITIES) is Dictionary:
			_send_error(ctx.id, INVALID_PARAMS, "Missing %s in _meta." % META_CAPABILITIES)
			return {"error": true}
		ctx.modern = true
	return ctx

func _dispatch(msg: Dictionary) -> void:
	var ctx := _context(msg)
	if ctx.has("error"):
		return
	var params: Dictionary = msg.get("params", {})
	match msg.method:
		"initialize":
			if ctx.modern:
				_send_error(ctx.id, METHOD_NOT_FOUND, "initialize isn't part of %s. Use server/discover." % MODERN)
				return
			var asked = params.get("protocolVersion")
			_legacy_version = asked if asked in LEGACY else LEGACY[0]
			respond(ctx, {"protocolVersion": _legacy_version, "capabilities": {"tools": {}}, "serverInfo": SERVER_INFO, "instructions": INSTRUCTIONS})
		"server/discover":
			if not ctx.modern:
				_send_error(ctx.id, INVALID_PARAMS, "server/discover needs %s and %s in _meta." % [META_VERSION, META_CAPABILITIES])
				return
			respond(ctx, {"supportedVersions": SUPPORTED, "capabilities": {"tools": {}}, "instructions": INSTRUCTIONS})
		"ping":
			respond(ctx, {})
		"tools/list", "tools/call":
			if not ctx.modern and _legacy_version == "":
				_send_error(ctx.id, INVALID_REQUEST, "Send initialize first, or include %s in _meta." % META_VERSION)
				return
			if msg.method == "tools/list":
				respond(ctx, {"tools": tools.definitions()})
				return
			var name = params.get("name")
			var args = params.get("arguments", {})
			if not name is String or not tools.has(name):
				_send_error(ctx.id, INVALID_PARAMS, "Unknown tool: %s" % str(name))
				return
			if not args is Dictionary:
				respond(ctx, tools.failure("arguments must be an object."))
				return
			if relay and (_window_open or name not in WITHOUT_WINDOW):
				_forward(ctx, msg)
				return
			if tools.is_async(name):
				_active = {"ctx": ctx, "long": tools.is_long(name)}
				await tools.call_tool(ctx, name, args)
				_active = {}
				_pump()
			else:
				tools.call_tool(ctx, name, args)
		_:
			_send_error(ctx.id, METHOD_NOT_FOUND, "Method not found: " + str(msg.method))

func respond(ctx: Dictionary, result: Dictionary) -> void:
	if ctx.cancelled or _closed:
		return
	if ctx.modern:
		result["resultType"] = "complete"
		var meta: Dictionary = result.get("_meta", {})
		meta[META_SERVER] = SERVER_INFO
		result["_meta"] = meta
	_send({"jsonrpc": "2.0", "id": ctx.id, "result": result})

## Progress for a long request, if the client asked for it. It only rises.
func progress(ctx: Dictionary, done: float, total: float, message: String) -> void:
	if ctx.progress_token == null or ctx.cancelled or _closed or done <= ctx.progress:
		return
	ctx.progress = done
	_send({"jsonrpc": "2.0", "method": "notifications/progress", "params": {"progressToken": ctx.progress_token, "progress": done, "total": total, "message": message}})

func _send_error(id: Variant, code: int, message: String) -> void:
	_send({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})

func _send(msg: Dictionary) -> void:
	write_line.call(JSON.stringify(msg))

func _forward(ctx: Dictionary, msg: Dictionary) -> void:
	if not _window_open:
		if not launch_window.call():
			respond(ctx, tools.failure("Studio couldn't open its window."))
			return
		_window_open = true
		if _legacy_version != "":
			write_window.call(JSON.stringify({"jsonrpc": "2.0", "id": WINDOW_INIT, "method": "initialize", "params": {"protocolVersion": _legacy_version}}))
	_forwarded[ctx.id] = ctx
	msg["id"] = ctx.id
	write_window.call(JSON.stringify(msg))

func _launch_window() -> bool:
	var before := [] if OS.has_feature("template") else ["--path", ProjectSettings.globalize_path("res://").trim_suffix("/")]
	var started := OS.execute_with_pipe(OS.get_executable_path(), before + window_args, true)
	if started.is_empty():
		return false
	_window = started
	_window_threads = [Thread.new(), Thread.new()]
	_window_threads[0].start(_read_lines.bind(started.stdio.get_buffer.bind(1), _from_window, _window_closed))
	_window_threads[1].start(_read_lines.bind(started.stderr.get_buffer.bind(1), func(line: String): printerr(line), func(): pass))
	return true

func _write_window(line: String) -> void:
	if _window.is_empty():
		return
	_window.stdio.store_line(line)
	_window.stdio.flush()

func _from_window(line: String) -> void:
	var msg = JSON.parse_string(line)
	if not msg is Dictionary:
		return
	if msg.has("id") and not msg.has("method"):
		if msg.id is String and msg.id == WINDOW_INIT:
			return
		var id = _id_of(msg)
		if not _forwarded.has(id):
			return
		_forwarded.erase(id)
	if not _closed:
		write_line.call(line)

func _window_closed() -> void:
	_window_open = false
	for thread in _window_threads:
		thread.wait_to_finish()
	_window_threads.clear()
	_window = {}
	var waiting := _forwarded.values()
	_forwarded.clear()
	for ctx in waiting:
		respond(ctx, tools.failure("The Studio window was closed. Call the tool again to reopen it."))
	if _closed:
		_stdin_closed()
