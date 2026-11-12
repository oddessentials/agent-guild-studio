extends RefCounted
## The agent's tools that need no art: the list of tools, the shared list of
## pieces, opening the window, and arguments refused before any work starts.

const FIXTURES := "res://tests/fixtures/pieces/"
const OUT := "user://pieces/mcp-test/"
const CLIPS := { "walk": 1.3333, "work_0": 3.0, "work_1": 5.0, "pause": 5.0, "idle_0": 5.0, "idle_1": 6.0, "idle_2": 5.0, "done": 4.0 }

class Host extends Node:
	const TOOLS := { "anthropic": "Claude Code" }
	var pieces: PieceLibrary
	var download: ArtDownload
	var opened := 0
	var disconnected := 0
	func open_window() -> bool:
		opened += 1
		return true
	func agent_disconnected() -> void:
		disconnected += 1
	func default_clips(_world: String, _kind: String, _crew: String) -> Dictionary:
		return CLIPS

class HeldTools extends McpTools:
	signal released
	var completed := false
	func _tool_check_piece(_ctx: Dictionary, _args: Dictionary) -> Dictionary:
		await released
		completed = true
		return _done("Finished")

var failures := []
var _lines := []
var _server: McpServer
var _next := 1

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
	await _read_lines(tree)
	StudioFiles.remove_tree(ProjectSettings.globalize_path(OUT))
	var host := Host.new()
	tree.root.add_child(host)
	host.pieces = PieceLibrary.new()
	host.pieces.root = OUT + "library/"
	host.pieces.default_clips = host.default_clips
	host.add_child(host.pieces)
	host.download = ArtDownload.new()
	host.add_child(host.download)
	_server = McpServer.new()
	_server.host = host
	_server.read_stdin = false
	_server.write_line = func(line: String): _lines.append(JSON.parse_string(line))
	host.add_child(_server)
	await _ask(tree, "initialize", { "protocolVersion": "2025-11-25" })

	var listed: Dictionary = await _ask(tree, "tools/list", {})
	var names: Array = listed.get("tools", []).map(func(t): return t.name)
	check(names == ["list_slots", "make_character", "make_companions", "recolor_look", "check_piece", "list_pieces", "remove_piece", "show_window"], "the tools are %s" % [names])
	check(listed.get("tools", []).all(func(t): return t.inputSchema.type == "object" and t.annotations.has("readOnlyHint") and t.has("description")), "a tool lacks a schema, hints or a description")
	check(listed.tools.filter(func(t): return t.name == "check_piece")[0].annotations.openWorldHint == true, "check_piece, which can download a world's art, says it stays offline")
	for name in ["make_character", "make_companions", "recolor_look"]:
		var props: Dictionary = listed.tools.filter(func(t): return t.name == name)[0].inputSchema.properties
		check(props.has("hue") and props.has("tint") and props.has("change_color") and props.has("spread"), "%s takes no color choices" % name)

	var shown := await _call(tree, "show_window", {})
	check(shown.get("isError") == false and host.opened == 1, "show_window did not open the window once")

	var none := await _call(tree, "list_pieces", {})
	check(none.get("structuredContent", {}).get("pieces") == [], "an empty list is not empty: %s" % none)
	var other := PieceLibrary.new()
	other.root = host.pieces.root
	other.default_clips = host.default_clips
	tree.root.add_child(other)
	var id := await other.add_local(_folder("in-the-window"), "", {})
	other.pieces[id].saved = "C:/pieces/in-the-window"
	other.keep()
	var one := await _call(tree, "list_pieces", {})
	var pieces: Array = one.get("structuredContent", {}).get("pieces", [])
	check(pieces.size() == 1 and pieces[0].piece == id and pieces[0].title == "in-the-window" and pieces[0].slot == "guild/anthropic" and pieces[0].folder == "C:/pieces/in-the-window",
		"a piece saved in the window is not listed for the agent: %s" % [pieces])
	var unknown := await _call(tree, "remove_piece", { "piece": "nothing" })
	check(unknown.get("isError") == true and host.pieces.pieces.size() == 1, "removing a piece that isn't there did something")
	var gone := await _call(tree, "remove_piece", { "piece": id })
	other.refresh()
	check(gone.get("isError") == false and other.pieces.is_empty(), "the agent's remove did not take the piece off the window's list")

	var to := ProjectSettings.globalize_path(OUT + "never")
	var color := await _call(tree, "make_character", { "model": "C:/x.glb", "slot": "guild/anthropic", "to": to, "tint": "#zzzzzz" })
	check(color.get("isError") == true and "color" in String(color.content[0].text) and not DirAccess.dir_exists_absolute(to), "a tint that is no color was not refused before any work")
	var nothing := await _call(tree, "recolor_look", { "slot": "guild/anthropic", "look": "look1", "to": to })
	check(nothing.get("isError") == true and "hue" in String(nothing.content[0].text), "a recolor with no color choice was not refused")
	var theirs := ProjectSettings.globalize_path(OUT + "theirs")
	DirAccess.make_dir_recursive_absolute(theirs)
	FileAccess.open(theirs.path_join("notes.txt"), FileAccess.WRITE).store_string("mine")
	var kept := await _call(tree, "make_character", { "model": "C:/x.glb", "slot": "guild/anthropic", "to": theirs, "replace": true })
	check(kept.get("isError") == true and "notes.txt" in String(kept.content[0].text) and FileAccess.get_file_as_string(theirs.path_join("notes.txt")) == "mine",
		"a folder holding someone's own file was not refused before any work: %s" % kept)
	var four := await _call(tree, "make_companions", { "models": ["a.glb", "b.glb"], "slot": "guild/companion", "to": to })
	check(four.get("isError") == true and "one model or four" in String(four.content[0].text), "two models for companions were not refused")
	check(host.opened == 1, "a tool other than show_window opened a window")

	# Text from a person's files (a bone, a title) can hold control characters;
	# the agent's client reads each line with a strict JSON parser.
	var raw := []
	_server.write_line = func(line: String): raw.append(line)
	_server.receive(StrictJson.stringify({ "jsonrpc": "2.0", "id": "odd", "method": "tools/call", "params": { "name": "bone" + String.chr(1) + String.chr(11), "arguments": {} } }))
	_server.write_line = func(line: String): _lines.append(JSON.parse_string(line))
	check(raw.size() == 1 and raw[0].contains("bone\\u0001\\u000b") and RegEx.create_from_string("[\\x00-\\x1f]|\\\\v").search(raw[0]) == null,
		"a reply holds raw control characters or \\v: %s" % [raw])
	await _lifecycle(tree, host)

	other.free()
	host.free()
	StudioFiles.remove_tree(ProjectSettings.globalize_path(OUT))
	return failures

func _read_lines(tree: SceneTree) -> void:
	var bytes := "first €\r\nlast without newline".to_utf8_buffer()
	var at := [0]
	var events := []
	McpServer._read_lines(func():
		if at[0] == bytes.size():
			return PackedByteArray()
		var next := bytes.slice(at[0], at[0] + 1)
		at[0] += 1
		return next,
		func(line: String): events.append(line), func(): events.append("EOF"))
	check(await TestRunner.until(tree, func(): return events.size() == 3), "the stdin reader lost a line or EOF")
	check(events == ["first €\r", "last without newline", "EOF"], "the stdin reader changed UTF-8 or delivered EOF before the final line")

func _lifecycle(tree: SceneTree, host: Host) -> void:
	var held := HeldTools.new(_server)
	_server.tools = held
	_lines.clear()
	_server.receive(JSON.stringify({ "jsonrpc": "2.0", "id": "making", "method": "tools/call", "params": { "name": "check_piece", "arguments": { "folder": "/piece" } } }))
	_server.receive(JSON.stringify({ "jsonrpc": "2.0", "id": "queued", "method": "tools/call", "params": { "name": "show_window", "arguments": {} } }))
	check(not _server._active.is_empty() and _server._queue.size() == 1, "the test did not hold a running tool and queue another")
	_server._stdin_closed()
	_server._stdin_closed()
	check(host.disconnected == 0 and not held.completed, "disconnect quit before the active tool finished")
	check(_server._queue.is_empty(), "disconnect left queued tools waiting to run")
	held.released.emit()
	check(await TestRunner.until(tree, func(): return _server._active.is_empty()), "the active tool did not finish")
	check(held.completed and host.disconnected == 1 and host.opened == 1, "disconnect did not finish the active tool, discard queued work, and notify the host once")
	_server.receive(JSON.stringify({ "jsonrpc": "2.0", "id": "after", "method": "ping" }))
	_server._stdin_closed()
	check(_lines.is_empty() and host.disconnected == 1, "the closed server replied or disconnected twice")

	var cancel_host := Host.new()
	tree.root.add_child(cancel_host)
	var cancelling := McpServer.new()
	cancelling.host = cancel_host
	cancelling.read_stdin = false
	var lines := []
	cancelling.write_line = func(line: String): lines.append(JSON.parse_string(line))
	cancel_host.add_child(cancelling)
	var work := HeldTools.new(cancelling)
	cancelling.tools = work
	var meta := { McpServer.META_VERSION: McpServer.MODERN, McpServer.META_CAPABILITIES: {} }
	cancelling.receive(JSON.stringify({ "jsonrpc": "2.0", "id": "cancelled", "method": "tools/call", "params": { "_meta": meta, "name": "check_piece", "arguments": { "folder": "/piece" } } }))
	cancelling.receive(JSON.stringify({ "jsonrpc": "2.0", "id": "discarded", "method": "tools/call", "params": { "_meta": meta, "name": "show_window", "arguments": {} } }))
	for id in ["cancelled", "discarded"]:
		cancelling.receive(JSON.stringify({ "jsonrpc": "2.0", "method": "notifications/cancelled", "params": { "requestId": id } }))
	work.released.emit()
	check(await TestRunner.until(tree, func(): return cancelling._active.is_empty()), "a cancelled tool did not finish safely")
	cancelling.receive(JSON.stringify({ "jsonrpc": "2.0", "id": "next", "method": "ping", "params": { "_meta": meta } }))
	check(work.completed and cancel_host.opened == 0 and lines.size() == 1 and lines[0].id == "next" and lines[0].result.resultType == "complete", "cancellation answered a cancelled call, ran a cancelled tool, or blocked the next request")
	cancelling._stdin_closed()
	check(cancel_host.disconnected == 1, "an idle disconnect did not notify the host")
	cancel_host.free()

func _ask(tree: SceneTree, method: String, params: Dictionary) -> Dictionary:
	var id := _next
	_next += 1
	_server.receive(JSON.stringify({ "jsonrpc": "2.0", "id": id, "method": method, "params": params }))
	var answer := [{}]
	await TestRunner.until(tree, func():
		for line in _lines:
			if line is Dictionary and line.get("id") == float(id):
				answer[0] = line
				return true
		return false, 60.0)
	return answer[0].get("result", answer[0])

func _call(tree: SceneTree, name: String, args: Dictionary) -> Dictionary:
	return await _ask(tree, "tools/call", { "name": name, "arguments": args })

func _folder(name: String) -> String:
	var dir := ProjectSettings.globalize_path(OUT + "folders/" + name)
	DirAccess.make_dir_recursive_absolute(dir)
	FileAccess.open(dir.path_join("piece.json"), FileAccess.WRITE).store_string(JSON.stringify({ "format": 1, "kind": "character", "world": "guild", "crew": "anthropic", "title": name }))
	var model := FileAccess.open(dir.path_join("character.glb"), FileAccess.WRITE)
	model.store_buffer(FileAccess.get_file_as_bytes(FIXTURES + "character.bin"))
	model.close()
	return dir
