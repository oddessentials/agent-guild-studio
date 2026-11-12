extends RefCounted
## One list of pieces for two programs, as Studio's window and an agent's
## connection are: what one adds or removes the other sees, and neither
## writes over a piece the other added.

const FIXTURES := "res://tests/fixtures/pieces/"
const OUT := "user://pieces/shared-test/"
const ROOT := "user://pieces/shared-test/library/"
const CLIPS := { "walk": 1.3333, "work_0": 3.0, "work_1": 5.0, "pause": 5.0, "idle_0": 5.0, "idle_1": 6.0, "idle_2": 5.0, "done": 4.0 }

var failures := []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
	StudioFiles.remove_tree(ProjectSettings.globalize_path(OUT))
	_upgrade(tree)
	StudioFiles.remove_tree(ProjectSettings.globalize_path(OUT))
	var window := _library(tree)
	var agent := _library(tree)
	var seen := [0]
	window.changed.connect(func(): seen[0] += 1)

	var made := await agent.add_local(_folder("agent-made"), "", { "files": ["model.glb"] })
	check(agent.pieces.get(made, {}).get("error", "x") == "", "a valid piece was not listed: %s" % agent.pieces.get(made))
	seen[0] = 0
	window.refresh()
	check(window.pieces.has(made) and window.pieces[made].get("studio", {}).get("files") == ["model.glb"] and seen[0] == 1, "the window did not see the piece the agent made, with how it was made")
	window.refresh()
	check(seen[0] == 1, "looking again with nothing new said the list changed")

	# Each adds one before seeing the other's: both are kept.
	var hers := await window.add_local(_folder("window-made"), "", {})
	var his := await agent.add_local(_folder("agent-second"), "", {})
	var fresh := _library(tree)
	check(fresh.pieces.has(made) and fresh.pieces.has(hers) and fresh.pieces.has(his), "a piece was lost when both added one: %s" % [fresh.pieces.keys()])

	agent.refresh()
	agent.remove(hers)
	window.refresh()
	check(not window.pieces.has(hers) and window.pieces.has(made) and window.pieces.has(his), "the window did not see the agent remove a piece, and only that one")

	var records := ProjectSettings.globalize_path(ROOT.path_join(PieceLibrary.RECORDS))
	FileAccess.open(records.path_join("half.json"), FileAccess.WRITE).store_string("{ \"id\": \"half")
	window.refresh()
	check(window.pieces.size() == 2, "a record caught half written was taken for a piece")

	for library in [window, agent, fresh]:
		library.free()
	StudioFiles.remove_tree(ProjectSettings.globalize_path(OUT))
	return failures

func _upgrade(tree: SceneTree) -> void:
	var folder := _folder("before-upgrade")
	var old := { "id": "local:old", "kind": "character", "world": "guild", "crew": "anthropic", "source": "local",
		"title": "Before upgrade", "dir": folder, "saved": folder, "version": "1", "error": "", "studio": { "files": ["original.glb"] } }
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	FileAccess.open(ROOT.path_join("index.json"), FileAccess.WRITE).store_string(JSON.stringify({ old.id: old }))
	var upgraded := _library(tree)
	check(upgraded.pieces.get(old.id, {}) == old, "upgrading lost a piece from index.json or its editing recipe")
	var again := _library(tree)
	check(again.pieces.get(old.id, {}) == old, "the upgraded piece was not persisted for another program")
	upgraded.remove(old.id)
	var reopened := _library(tree)
	check(not reopened.pieces.has(old.id), "a removed piece came back from the old index on restart")
	for library in [upgraded, again, reopened]:
		library.free()

func _library(tree: SceneTree) -> PieceLibrary:
	var library := PieceLibrary.new()
	library.root = ROOT
	library.default_clips = func(_world, _kind, _crew): return CLIPS
	tree.root.add_child(library)
	return library

func _folder(name: String) -> String:
	var dir := ProjectSettings.globalize_path(OUT + "folders/" + name)
	DirAccess.make_dir_recursive_absolute(dir)
	FileAccess.open(dir.path_join("piece.json"), FileAccess.WRITE).store_string(JSON.stringify({ "format": 1, "kind": "character", "world": "guild", "crew": "anthropic", "title": name }))
	var model := FileAccess.open(dir.path_join("character.glb"), FileAccess.WRITE)
	model.store_buffer(FileAccess.get_file_as_bytes(FIXTURES + "character.bin"))
	model.close()
	return dir
