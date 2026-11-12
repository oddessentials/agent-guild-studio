class_name PieceLibrary
extends Node

signal changed

const ROOT := "user://pieces/"
const FILES := {
	"character": ["character.glb"],
	"companion": ["companion_0.glb", "companion_1.glb", "companion_2.glb", "companion_3.glb"],
}
const PREVIEWS := ["preview.jpg", "preview.png"]
const PREVIEW_MAX := 1 << 20
const MANIFEST_MAX := 16 << 10
const SECTION := "pieces"

var pieces := {}
var settings: ConfigFile
var settings_path := ""
var default_clips := func(_world: String, _kind: String, _crew: String) -> Dictionary: return {}
var validator: PieceValidator
var root := ROOT
var _scenes := {}
var _loading := {}
var _adding := {}
var _written := {}
const RECORDS := "records"
signal _settled(id: String)

func _ready() -> void:
	validator = PieceValidator.new()
	add_child(validator)
	_restore()

## Whether the piece names a world and a slot there, as Studio needs to edit it.
static func has_slot(piece: Dictionary) -> bool:
	var kind: String = piece.get("kind", "")
	return YardModel.WORLDS.has(piece.get("world", "")) and FILES.has(kind) and (kind != "character" or piece.get("crew", "") in YardModel.PROVIDER_ORDER)

static func slot_of(piece: Dictionary) -> String:
	return "%s/%s" % [piece.world, piece.crew if piece.kind == "character" else "companion"]

func chosen(slot: String) -> String:
	var id: String = settings.get_value(SECTION, slot, "") if settings else ""
	return id if pieces.has(id) and pieces[id].dir != "" and slot_of(pieces[id]) == slot else ""

func choose(slot: String, id: String) -> void:
	if settings == null:
		return
	if id == "":
		if settings.has_section_key(SECTION, slot):
			settings.erase_section_key(SECTION, slot)
	else:
		settings.set_value(SECTION, slot, id)
	if settings_path != "":
		settings.save(settings_path)
	if id != "":
		await load_piece(id)
	changed.emit()

func for_slot(slot: String) -> Array:
	return pieces.values().filter(func(p): return p.has("world") and slot_of(p) == slot)

func add(id: String, folder: String, version: String, source: String, title := "") -> void:
	if _adding.has(id):
		_adding[id] = [folder, version, source, title]
		return
	_adding[id] = []
	await _add(id, folder, version, source, title)
	await _release(id)

# Deferred, so whoever held the piece reads its own result before the next one starts.
func _release(id: String) -> void:
	var next: Array = _adding.get(id, [])
	_adding.erase(id)
	if not next.is_empty():
		await add(id, next[0], next[1], next[2], next[3])
	else:
		_settled.emit.call_deferred(id)

func _add(id: String, folder: String, version: String, source: String, title: String) -> void:
	var old: Dictionary = pieces.get(id, {})
	if old.get("version", "") == version:
		return
	var refuse := func(reason: String, known := {}) -> void:
		var kept: Dictionary = old.duplicate() if old.get("dir", "") != "" else { "id": id, "kind": known.get("kind", ""), "world": known.get("world", ""),
			"crew": known.get("crew", ""), "dir": "", "file_id": old.get("file_id", 0), "published": old.get("published", "") }
		kept.merge({ "title": known.get("title", title if title != "" else String(old.get("title", id))), "source": source, "version": version, "error": reason }, true)
		_settle(kept)
	var manifest := check_folder(folder)
	if manifest.has("reason"):
		refuse.call(manifest.reason)
		return
	var piece := { "id": id, "source": source, "version": version, "error": "", "kind": manifest.kind, "world": manifest.world,
		"crew": manifest.get("crew", ""), "title": title if title != "" else String(manifest.get("title", id)),
		"file_id": old.get("file_id", 0), "published": old.get("published", "") }
	if old.has("visibility"):
		piece.visibility = old.visibility
	var clips: Dictionary = default_clips.call(piece.world, piece.kind, piece.crew)
	for file in FILES[piece.kind]:
		var verdict: Dictionary = await validator.check(folder.path_join(file), piece.kind, clips)
		if verdict.reason != "":
			refuse.call("%s: %s" % [file, verdict.reason], piece)
			return
	var dir := root.path_join("cache").path_join(id.validate_filename()).path_join(version.validate_filename()) + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for file in FILES[piece.kind] + ["piece.json"] + PREVIEWS:
		if FileAccess.file_exists(folder.path_join(file)):
			DirAccess.copy_absolute(folder.path_join(file), ProjectSettings.globalize_path(dir + file))
	var previous: String = old.get("dir", "")
	piece.dir = dir
	_scenes.erase(id)
	if previous != "" and previous != dir:
		_remove_dir(previous)
	_settle(piece)
	if not _slots_wearing(id).is_empty():
		await load_piece(id)

func add_local(folder: String, id := "", studio := {}) -> String:
	if id == "":
		id = local_id()
	while _adding.has(id):
		await _settled
	_adding[id] = []
	var copy := ProjectSettings.globalize_path(root.path_join("local").path_join(id.validate_filename()))
	_remove_dir(copy)
	DirAccess.make_dir_recursive_absolute(copy)
	var names := ["piece.json"] + PREVIEWS
	for kind in FILES:
		names += FILES[kind]
	for file in names:
		if FileAccess.file_exists(folder.path_join(file)):
			DirAccess.copy_absolute(folder.path_join(file), copy.path_join(file))
	await _add(id, copy, str(int(Time.get_unix_time_from_system() * 1000)), "local", "")
	if pieces.has(id) and pieces[id].error == "":
		if studio.is_empty():
			pieces[id].erase("studio")
		else:
			pieces[id].studio = studio
		_save()
		await choose(slot_of(pieces[id]), id)
	await _release(id)
	return id

static func local_id() -> String:
	return "local:" + Crypto.new().generate_random_bytes(16).hex_encode()

func set_published(id: String, file_id: int, version := "", visibility := "") -> void:
	if not pieces.has(id):
		return
	if visibility != "":
		pieces[id].visibility = visibility
	elif int(pieces[id].get("file_id", 0)) != file_id:
		pieces[id].erase("visibility")
	pieces[id].file_id = file_id
	if version != "" or file_id == 0:
		pieces[id].published = version
	_save()
	changed.emit()

func remove(id: String) -> void:
	if not pieces.has(id):
		return
	if pieces[id].dir != "":
		_remove_dir(pieces[id].dir)
	if pieces[id].source == "local":
		_remove_dir(root.path_join("local").path_join(id.validate_filename()))
	pieces.erase(id)
	_scenes.erase(id)
	for slot in _slots_wearing(id):
		settings.erase_section_key(SECTION, slot)
	if settings and settings_path != "":
		settings.save(settings_path)
	_save()
	changed.emit()

func scenes(id: String) -> Array:
	return _scenes.get(id, [])

func load_piece(id: String) -> void:
	if _scenes.has(id) or _loading.has(id) or not pieces.has(id) or pieces[id].dir == "":
		return
	var dir: String = pieces[id].dir
	var files: Array = FILES[pieces[id].kind]
	var built := []
	_loading[id] = true
	var task := WorkerThreadPool.add_task(func():
		for file in files:
			built.append(build(ProjectSettings.globalize_path(dir + file))))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_loading.erase(id)
	if not pieces.has(id) or pieces[id].dir != dir:
		return
	if built.has(null):
		pieces[id].error = "it could not be loaded"
		_save()
	else:
		_scenes[id] = built
	changed.emit()

static func build(path: String) -> PackedScene:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	for texture in state.get_images():
		if texture is ImageTexture:
			var image: Image = texture.get_image()
			if image and not image.is_compressed() and not image.has_mipmaps():
				image.generate_mipmaps()
				texture.set_image(image)
	var node := doc.generate_scene(state)
	if node == null:
		return null
	var scene := PackedScene.new()
	var ok := scene.pack(node) == OK
	node.free()
	return scene if ok else null

static func check_folder(folder: String) -> Dictionary:
	var dir := DirAccess.open(folder)
	if dir == null:
		return { "reason": "its folder cannot be read" }
	if not dir.get_directories().is_empty():
		return { "reason": "its folder holds other folders" }
	var path := folder.path_join("piece.json")
	if not FileAccess.file_exists(path) or FileAccess.open(path, FileAccess.READ).get_length() > MANIFEST_MAX:
		return { "reason": "it has no piece.json" }
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary or manifest.get("format") != 1.0:
		return { "reason": "its piece.json is not format 1" }
	if not manifest.get("kind") in FILES:
		return { "reason": "its piece.json does not say character or companion" }
	if not YardModel.WORLDS.has(manifest.get("world", "")):
		return { "reason": "its piece.json names no world of Agent Guild: World" }
	if manifest.kind == "character" and not manifest.get("crew", "") in YardModel.PROVIDER_ORDER:
		return { "reason": "its piece.json names no crew of Agent Guild: World" }
	if manifest.has("title") and (not manifest.title is String or manifest.title.length() > 128):
		return { "reason": "its title is not text of up to 128 characters" }
	var allowed: Array = FILES[manifest.kind] + ["piece.json"] + PREVIEWS
	for file in dir.get_files():
		if not file in allowed:
			return { "reason": "it holds %s, which a piece may not" % file }
	for file in FILES[manifest.kind]:
		if not FileAccess.file_exists(folder.path_join(file)):
			return { "reason": "it has no %s" % file }
		if FileAccess.open(folder.path_join(file), FileAccess.READ).get_length() > PieceCheck.LIMITS[manifest.kind].file:
			return { "reason": "%s is over %d MB" % [file, PieceCheck.LIMITS[manifest.kind].file >> 20] }
	for file in PREVIEWS:
		if FileAccess.file_exists(folder.path_join(file)) and FileAccess.open(folder.path_join(file), FileAccess.READ).get_length() >= PREVIEW_MAX:
			return { "reason": "its preview is 1 MB or more" }
	return manifest

func _slots_wearing(id: String) -> Array:
	if settings == null or not settings.has_section(SECTION):
		return []
	return Array(settings.get_section_keys(SECTION)).filter(func(slot): return settings.get_value(SECTION, slot) == id)

func _settle(piece: Dictionary) -> void:
	pieces[piece.id] = piece
	_save()
	changed.emit()

## Writes the list as it stands, after a caller changed a piece's own notes.
func keep() -> void:
	_save()

## Each piece's record is a file of its own under records/, written whole
## and then moved into place, so Studio's window and an agent's connection,
## two programs with one list, never write over each other's pieces.
func _save() -> void:
	var dir := ProjectSettings.globalize_path(root.path_join(RECORDS))
	DirAccess.make_dir_recursive_absolute(dir)
	for id in pieces:
		var text := StrictJson.stringify(pieces[id], " ")
		if _written.get(id, "") == text:
			continue
		var path := dir.path_join(_record(id))
		var part := "%s.%d.%d.part" % [path, OS.get_process_id(), get_instance_id()]
		var file := FileAccess.open(part, FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(text)
		file.flush()
		var error := file.get_error()
		file.close()
		if error == OK and DirAccess.rename_absolute(part, path) == OK:
			_written[id] = text
		else:
			DirAccess.remove_absolute(part)
	for id in _written.keys():
		if not pieces.has(id):
			DirAccess.remove_absolute(dir.path_join(_record(id)))
			_written.erase(id)

static func _record(id: String) -> String:
	return id.validate_filename() + ".json"

## Every record on disk: { id: piece } and { id: its text }.
func _read() -> Array:
	var dir := ProjectSettings.globalize_path(root.path_join(RECORDS))
	var found := {}
	var texts := {}
	for name in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		if name.get_extension() != "json":
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(name))
		# A record another program is part way through writing isn't one yet.
		var json := JSON.new()
		var piece = json.data if text != "" and json.parse(text) == OK else null
		if piece is Dictionary and piece.get("id") is String and piece.has("kind") and (piece.get("dir", "") == "" or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(piece.dir))):
			found[piece.id] = piece
			texts[piece.id] = text
	return [found, texts]

func _restore() -> void:
	var read := _read()
	pieces = read[0]
	_written = read[1]
	var legacy := root.path_join("index.json")
	if not FileAccess.file_exists(legacy):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(legacy))
	if not saved is Dictionary:
		return
	for id in saved:
		var piece = saved[id]
		if not pieces.has(id) and piece is Dictionary and piece.has("kind") and (piece.get("dir", "") == "" or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(piece.dir))):
			piece.id = id
			pieces[id] = piece
	_save()
	if pieces.keys().all(func(id): return _written.has(id)):
		DirAccess.rename_absolute(legacy, root.path_join("index.migrated.json"))

## Takes in what another program changed: pieces it added, changed or
## removed. Nothing is read while a piece is being added here.
func refresh() -> void:
	if not _adding.is_empty():
		return
	var read := _read()
	if read[1] == _written:
		return
	for id in pieces.keys():
		if read[0].get(id) != pieces[id]:
			_scenes.erase(id)
	pieces = read[0]
	_written = read[1]
	changed.emit()

func _remove_dir(dir: String) -> void:
	var abs := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file))
	DirAccess.remove_absolute(abs)
