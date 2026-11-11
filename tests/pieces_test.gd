extends RefCounted

const FIXTURES := "res://tests/fixtures/pieces/"
const OUT := "user://pieces/test/"
const CHARACTER_CLIPS := { "walk": 1.3333, "work_0": 3.0, "work_1": 5.0, "pause": 5.0, "idle_0": 5.0, "idle_1": 6.0, "idle_2": 5.0, "done": 4.0 }
const COMPANION_CLIPS := { "idle": 3.0, "working": 2.0, "waiting": 4.0, "done": 3.0, "move": 1.0 }
const BEFORE_LOADING := {
	"truncated": "complete", "cycle": "deeper", "deep": "deeper", "many_nodes": "nodes",
	"accessor_past_view": "accessor", "external_uri": "outside", "unsupported_extension": "KHR_mesh_quantization",
	"faces_over": "faces", "texture_over": "4097", "textures_over_memory": "MB",
}
const ONCE_LOADED := {
	"missing_bone": "LeftFoot", "missing_socket": "PropRight", "missing_clip": "done clip",
	"missing_extras": "yard.", "clip_length": "work_1",
}

func run(tree: SceneTree) -> Array:
	var failures := []
	for name in BEFORE_LOADING:
		var reason := PieceCheck.check_headers(_fixture(name), "character")
		if not BEFORE_LOADING[name] in reason:
			failures.append("%s: the header check said \"%s\"" % [name, reason])
	for name in ONCE_LOADED:
		var reason: String = PieceCheck.check_file(_fixture(name), "character", CHARACTER_CLIPS).reason
		if not ONCE_LOADED[name] in reason:
			failures.append("%s: the check said \"%s\"" % [name, reason])
	if PieceCheck.check_file(_fixture("companion"), "character", CHARACTER_CLIPS).reason != "it is not a character":
		failures.append("a companion passed as a character")
	failures.append_array(await _isolation(tree))
	failures.append_array(await _library(tree))
	failures.append_array(await _together(tree))
	failures.append_array(_preview(tree))
	_empty(OUT)
	return failures

func _library(tree: SceneTree) -> Array:
	var out := []
	var settings := ConfigFile.new()
	var library := _new_library(tree, settings)
	var slot := "guild/anthropic"
	# A Workshop title can hold any character, a vertical tab included.
	var title := "Test\u000bhero"
	await library.add("ws:1", _folder("good", "character", { "character.glb": "character" }), "100", "workshop", title)
	var piece: Dictionary = library.pieces.get("ws:1", {})
	if piece.get("dir", "") == "" or piece.get("error", "x") != "" or PieceLibrary.slot_of(piece) != slot:
		out.append("a valid character folder was not taken in: %s" % piece)
	await library.choose(slot, "ws:1")
	if library.chosen(slot) != "ws:1" or settings.get_value("pieces", slot, "") != "ws:1":
		out.append("choosing a piece was not kept")
	var scenes := library.scenes("ws:1")
	var model: Node = scenes[0].instantiate() if not scenes.is_empty() else null
	if model == null or model.find_children("*", "AnimationPlayer", true, false).is_empty():
		out.append("a chosen piece did not load as a model with its clips")
	if model:
		model.free()
	var first: String = piece.get("dir", "")
	await library.add("ws:1", _folder("broken", "character", { "character.glb": "missing_clip" }), "200", "workshop")
	piece = library.pieces["ws:1"]
	if piece.dir != first or not "done clip" in piece.error or library.chosen(slot) != "ws:1":
		out.append("a refused update did not leave the last good copy in use: %s" % piece)
	await library.add("ws:1", _folder("good", "character", { "character.glb": "character" }), "300", "workshop", title)
	piece = library.pieces["ws:1"]
	if piece.dir == first or piece.error != "" or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(first)):
		out.append("a passing update did not replace the copy in use: %s" % piece)
	await library.add("ws:2", _folder("extra", "character", { "character.glb": "character", "script.tres": "character" }), "1", "workshop")
	if not "script.tres" in library.pieces["ws:2"].error or library.pieces["ws:2"].dir != "":
		out.append("a folder holding another file was taken in: %s" % library.pieces["ws:2"])
	await library.add("ws:3", _folder("short", "companion", { "companion_0.glb": "companion", "companion_1.glb": "companion", "companion_2.glb": "companion" }), "1", "workshop")
	if not "companion_3.glb" in library.pieces["ws:3"].error:
		out.append("a companion without all four models was taken in: %s" % library.pieces["ws:3"])
	library.free()
	library = _new_library(tree, settings)
	if library.chosen(slot) != "ws:1" or library.pieces.get("ws:1", {}).get("title") != title:
		out.append("a chosen piece did not outlast a restart: %s" % library.pieces.get("ws:1"))
	library.remove("ws:1")
	if library.chosen(slot) != "" or settings.has_section_key("pieces", slot):
		out.append("a removed piece's slot did not go back to the default")
	library.free()
	_empty(LIBRARY)
	return out

func _together(tree: SceneTree) -> Array:
	var out := []
	var library := _new_library(tree, ConfigFile.new())
	var seen := {}
	var add := func(name: String, id: String, fixture: String) -> void:
		await library.add_local(_folder(name, "character", { "character.glb": fixture }), id, { "by": name })
		seen[name] = library.pieces.get(id, {}).duplicate(true)
	add.call("first", "local:one", "character")
	await add.call("refused", "local:one", "missing_clip")
	var first: Dictionary = seen.get("first", {})
	var refused: Dictionary = seen.get("refused", {})
	if first.get("error", "x") != "" or first.get("title") != "first" or first.get("studio") != { "by": "first" }:
		out.append("a piece added while another version of it was on its way did not get its own result: %s" % first)
	if not "done clip" in refused.get("error", "") or refused.get("dir", "") != first.get("dir", "x") \
			or FileAccess.get_file_as_bytes(String(refused.get("dir", "")) + "character.glb") != FileAccess.get_file_as_bytes(FIXTURES + "character.bin"):
		out.append("a refused version added over one on its way did not leave that one whole and in use: %s" % refused)
	add.call("older", "local:two", "character")
	await add.call("newer", "local:two", "character")
	var newer: Dictionary = library.pieces.get("local:two", {})
	var written = JSON.parse_string(FileAccess.get_file_as_string(String(newer.get("dir", "")) + "piece.json"))
	if seen.get("older", {}).get("title") != "older" or seen.older.error != "" or newer.get("title") != "newer" or newer.get("error", "x") != "" \
			or newer.get("studio") != { "by": "newer" } or not written is Dictionary or written.get("title") != "newer":
		out.append("two versions of a piece added together did not each get their result, the later one last: %s, %s" % [seen.get("older"), newer])
	add.call("left", "local:left", "character")
	await add.call("right", "local:right", "character")
	await TestRunner.until(tree, func(): return seen.has("left"))
	for name in ["left", "right"]:
		var piece: Dictionary = library.pieces.get("local:" + name, {})
		if piece.get("title") != name or piece.get("error", "x") != "" or piece.get("studio") != { "by": name } or piece.get("dir", "") == "":
			out.append("two different pieces added together were not both taken in: %s" % piece)
	library.free()
	_empty(LIBRARY)
	return out

func _preview(tree: SceneTree) -> Array:
	var out := []
	var four := {}
	for n in 4:
		four["companion_%d.glb" % n] = "companion"
	for piece in [["character", { "character.glb": "character" }], ["companion", four]]:
		var folder := _folder("preview-" + piece[0], piece[0], piece[1])
		var preview := PiecePreview.new()
		tree.root.add_child(preview)
		preview.stage(piece[1].keys().map(func(f): return PieceLibrary.build(folder.path_join(f))), piece[0])
		var boxes: Array = preview.models.map(PiecePreview.bounds_of)
		var frame := Rect2()
		var whole := true
		for i in boxes.size():
			for c in 8:
				whole = whole and preview.camera.is_position_in_frustum(boxes[i].get_endpoint(c))
				var at := preview.camera.unproject_position(boxes[i].get_endpoint(c))
				frame = Rect2(at, Vector2.ZERO) if i == 0 and c == 0 else frame.expand(at)
			for j in i:
				whole = whole and not boxes[i].intersects(boxes[j])
		if boxes.size() != piece[1].size() or not whole or maxf(frame.size.x, frame.size.y) < 0.5 * PiecePreview.SIZE.x:
			out.append("the %s preview does not show every model whole and apart, filling the frame" % piece[0])
		preview.free()
	return out

const LIBRARY := "user://pieces/test-library/"

func _new_library(tree: SceneTree, settings: ConfigFile) -> PieceLibrary:
	var library := PieceLibrary.new()
	library.root = LIBRARY
	library.settings = settings
	library.default_clips = func(_w, kind, _c): return CHARACTER_CLIPS if kind == "character" else COMPANION_CLIPS
	tree.root.add_child(library)
	return library

func _folder(name: String, kind: String, files: Dictionary) -> String:
	var dir := ProjectSettings.globalize_path(OUT + "folders/" + name)
	_empty(OUT + "folders/" + name + "/")
	DirAccess.make_dir_recursive_absolute(dir)
	var manifest := { "format": 1, "kind": kind, "world": "guild", "title": name }
	if kind == "character":
		manifest.crew = "anthropic"
	FileAccess.open(dir.path_join("piece.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest))
	for file in files:
		var f := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
		f.store_buffer(FileAccess.get_file_as_bytes(FIXTURES + files[file] + ".bin"))
		f.close()
	return dir

func _empty(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for sub in DirAccess.get_directories_at(abs):
		_empty(path.path_join(sub) + "/")
	for file in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file))
	DirAccess.remove_absolute(abs)

func _isolation(tree: SceneTree) -> Array:
	var out := []
	var validator := PieceValidator.new()
	tree.root.add_child(validator)
	var verdict: Dictionary = await validator.check(_fixture("character"), "character", CHARACTER_CLIPS)
	if verdict.reason != "":
		out.append("the valid character was refused in the child: %s" % verdict.reason)
	verdict = await validator.check(_fixture("companion"), "companion", COMPANION_CLIPS)
	if verdict.reason != "":
		out.append("the valid companion was refused in the child: %s" % verdict.reason)
	verdict = await validator.check(_fixture("truncated"), "character", CHARACTER_CLIPS)
	if not "complete" in verdict.reason:
		out.append("the child did not report the truncated file's reason: %s" % verdict.reason)
	validator.timeout = 2.0
	var frames := { "count": 0, "child": -1 }
	var tick := func():
		frames.count += 1
		if validator.pid > 0:
			frames.child = validator.pid
	tree.process_frame.connect(tick)
	verdict = await validator.check(_fixture("cycle"), "character", CHARACTER_CLIPS, "load")
	tree.process_frame.disconnect(tick)
	if verdict.reason != "it took too long to check":
		out.append("a hang was not stopped: %s" % verdict.reason)
	if frames.count < 2:
		out.append("the world's frames stopped during a check")
	if frames.child <= 0 or not await TestRunner.until(tree, func(): return not OS.is_process_running(frames.child)):
		out.append("the hung child was not ended")
	validator.timeout = 60.0
	verdict = await validator.check(_fixture("character"), "character", CHARACTER_CLIPS, "", "crash")
	if verdict.reason != "it crashed the checker":
		out.append("a crash was not reported: %s" % verdict.reason)
	validator.check(_fixture("cycle"), "character", CHARACTER_CLIPS, "load")
	if not await TestRunner.until(tree, func(): return validator.pid > 0):
		out.append("the last child did not start")
	var orphan := validator.pid
	validator.free()
	if not await TestRunner.until(tree, func(): return not OS.is_process_running(orphan)):
		out.append("a child outlived its validator")
	return out

func _fixture(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var path := ProjectSettings.globalize_path(OUT + name + ".glb")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURES + name + ".bin"))
	file.close()
	return path
