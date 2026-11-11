extends RefCounted
## Studio's screens for one piece, on the stage, with the art packs in place
## (STUDIO_ART names their folder): a model is made and shown beside the slot
## default at their stations, saved as a folder that is never written over,
## and listed under Your pieces with how it was made; companions and a
## recolor show too; leaving empties the stage.

const FIXTURES := "res://tests/fixtures/pieces/"
const OUT := "user://studio/view-test/"
const LIBRARY := "user://studio/view-test-library/"

var failures := []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
	var reason := StudioArt.load_packs(StudioArt.packs_for("guild"))
	if reason != "":
		return [reason + "; build the packs (tools/pack_art.py) and set STUDIO_ART to their folder"]
	var out := ProjectSettings.globalize_path(OUT)
	StudioFiles.remove_tree(out)
	StudioFiles.remove_tree(ProjectSettings.globalize_path(LIBRARY))
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://src/app/main.gd").new()
	var pieces := PieceLibrary.new()
	pieces.root = LIBRARY
	pieces.default_clips = main.default_clips
	tree.root.add_child(pieces)
	var stage := StudioStage.new()
	tree.root.add_child(stage)
	var camera := CameraRig.new()
	tree.root.add_child(camera)
	stage.camera = camera
	var panel := StudioPanel.new()
	panel.pad_screen = func(): return false
	tree.root.add_child(panel)
	var flow := StudioFlow.new()
	tree.root.add_child(flow)
	var ended := [false]
	flow.ended.connect(func(): ended[0] = true)
	flow.start(panel, stage, pieces, main.TOOLS, "guild", "light")
	check(panel.visible and panel.step == "slot" and panel.slots.size() == 7, "Studio did not open on the slot screen with guild's seven slots")

	var model := _copy("studio_mixamo")
	var where: Dictionary = panel.slots[1]
	panel.where = where
	panel.files = [model]
	panel.make_requested.emit({ "where": where, "files": [model], "options": {} })
	check(await TestRunner.until(tree, func(): return panel.step == "preview", 180.0), "a made character never reached the preview")
	check(stage.models.size() == 2, "the stage shows %d models, not the piece and the default" % stage.models.size())
	var stations := stage._shown.get_children().filter(func(n): return not n in stage.models and not n.is_queued_for_deletion())
	check(stations.size() == 2, "the stage has %d stations for the two characters" % stations.size())
	check(stage.motion == "work", "the preview starts on %s, not work" % stage.motion)
	stage.play("walk")
	check(stage._players.all(func(p: AnimationPlayer): return p.current_animation == "walk"), "walk did not play on every model")
	stage.set_theme("dark")
	check(stage.theme == "dark" and is_equal_approx(stage._sun.light_energy, StudioStage.SUN_ENERGY.dark), "dusk did not change the stage's light")

	panel.save_requested.emit(out, "View test")
	check(await TestRunner.until(tree, func(): return flow._keeping == "" and not flow.job.running and DirAccess.dir_exists_absolute(out.path_join("View test")), 240.0), "the piece was not saved")
	check(FileAccess.file_exists(out.path_join("View test/piece.json")) and FileAccess.file_exists(out.path_join("View test/character.glb")), "the saved folder is not a piece")
	var listed: Array = pieces.pieces.values().filter(func(p): return p.get("source", "") == "local")
	check(listed.size() == 1 and listed[0].get("error", "x") == "" and listed[0].title == "View test" and listed[0].world == "guild" and listed[0].crew == where.crew,
		"the saved piece is not listed under Your pieces: %s" % [listed])
	if listed.size() == 1:
		check(listed[0].get("studio", {}).get("files", []) == [model] and String(listed[0].get("saved", "")).ends_with("View test"), "Your pieces did not keep how the piece was made and where it was saved")
	panel.save_requested.emit(out, "View test")
	check(await TestRunner.until(tree, func(): return flow._keeping == "" and DirAccess.dir_exists_absolute(out.path_join("View test (2)")), 240.0), "saving again wrote over the first folder instead of beside it")
	check(pieces.pieces.values().filter(func(p): return p.get("source", "") == "local").size() == 1, "saving the piece being made again listed it twice")

	var companions: Dictionary = panel.slots[6]
	panel.where = companions
	var ball := _copy("studio_ball")
	panel.make_requested.emit({ "where": companions, "files": [ball], "options": {} })
	check(await TestRunner.until(tree, func(): return stage._kind == "companion" and not flow.job.running, 180.0), "companions never reached the stage")
	check(stage.models.size() == 1 + StudioStage.COMPANIONS, "the stage shows %d models, not a character and six companions" % stage.models.size())

	panel.leave_requested.emit()
	check(await TestRunner.until(tree, func(): return ended[0], 60.0), "leaving did not end Studio")
	check(stage.models.is_empty() and not panel.visible, "leaving left the stage or the panel showing")
	await TestRunner.until(tree, func(): return not is_instance_valid(flow), 60.0)
	for node in [panel, camera, stage, pieces]:
		node.queue_free()
	main.free()
	await tree.process_frame
	StudioFiles.remove_tree(out)
	StudioFiles.remove_tree(ProjectSettings.globalize_path(LIBRARY))
	return failures

func _copy(name: String) -> String:
	var path := ProjectSettings.globalize_path(OUT.path_join(name + ".glb"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURES + name + ".bin"))
	file.close()
	return path
