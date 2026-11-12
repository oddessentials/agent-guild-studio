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
	func open_window() -> bool:
		opened += 1
		return true
	func default_clips(_world: String, _kind: String, _crew: String) -> Dictionary:
		return CLIPS

var failures := []
var _lines := []
var _server: McpServer
var _next := 1

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
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
	var four := await _call(tree, "make_companions", { "models": ["a.glb", "b.glb"], "slot": "guild/companion", "to": to })
	check(four.get("isError") == true and "one model or four" in String(four.content[0].text), "two models for companions were not refused")

	other.free()
	host.free()
	StudioFiles.remove_tree(ProjectSettings.globalize_path(OUT))
	return failures

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
