extends RefCounted
## Studio's window making a piece, with the art packs in place (STUDIO_ART
## names their folder): a model is made and shown beside the slot default at
## their stations; its colors are changed as a look's are; it is saved as a
## folder that is never written over, in the colors chosen, and listed under
## Your pieces with how it was made; it is opened again from there as it was
## left; companions show too; and closing the window during a save finishes
## the save first.

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
	tree.root.add_child(main)
	var quits := [0]
	main.on_quit = func(): quits[0] += 1
	main.pieces.root = LIBRARY
	main.pieces.refresh()
	var pieces: PieceLibrary = main.pieces
	var panel: StudioPanel = main.panel
	var stage: StudioStage = main.stage
	var home: HomePanel = main.home
	check(home.art == "ready", "with its art in place, guild shows as %s" % home.art)
	home.make_requested.emit("guild")
	var flow: StudioFlow = main.flow
	check(flow != null and panel.visible and not home.visible and panel.step == "slot" and panel.slots.size() == 7, "Make a piece did not open the slot screen with guild's seven slots")

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

	# Its colors, changed as a look's are: here, turned a third of the way round.
	check(not panel._colors.is_empty(), "the preview has none of the made piece's colors to choose from")
	var as_made: Image = flow._made.pieces[0].surfaces[0].look.image.duplicate()
	panel._tint("hue", 120.0)
	check(await TestRunner.until(tree, func(): return flow._made.has("base") and not flow.job.running and flow._asked == flow._wanted, 120.0), "a color change never reached the stage")
	check(flow._made.get("reduced", false) and stage.models.size() == 2, "the recolored piece is not on the stage beside the default")
	check(panel.options.get("colour", {}).get("hue") == 120.0, "the panel did not keep the color change with the piece's choices")

	panel.save_requested.emit(out, "View test")
	check(await TestRunner.until(tree, func(): return flow._keeping == "" and not flow.job.running and DirAccess.dir_exists_absolute(out.path_join("View test")), 240.0), "the piece was not saved")
	check(FileAccess.file_exists(out.path_join("View test/piece.json")) and FileAccess.file_exists(out.path_join("View test/character.glb")), "the saved folder is not a piece")
	var saved: Dictionary = StudioSource.open(out.path_join("View test/character.glb"))
	if saved.has("model"):
		var read := StudioSource.read(saved.model)
		saved.model.free()
		check(_turned(as_made, read.surfaces[0].look.image) > 0.5, "the saved piece is not in the colors chosen")
	else:
		check(false, "the saved piece could not be opened again")
	var listed: Array = pieces.pieces.values().filter(func(p): return p.get("source", "") == "local")
	check(listed.size() == 1 and listed[0].get("error", "x") == "" and listed[0].title == "View test" and listed[0].world == "guild" and listed[0].crew == where.crew,
		"the saved piece is not listed under Your pieces: %s" % [listed])
	var id: String = listed[0].id if listed.size() == 1 else ""
	if id != "":
		var recipe: Dictionary = listed[0].get("studio", {})
		check(recipe.get("files", []) == [model] and recipe.get("options", {}).get("colour", {}).get("hue") == 120.0 and String(listed[0].get("saved", "")).ends_with("View test"),
			"Your pieces did not keep how the piece was made, its colors and where it was saved: %s" % recipe)
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
	check(await TestRunner.until(tree, func(): return main.flow == null and home.visible, 60.0), "leaving did not bring the first screen back")
	check(stage.models.is_empty() and not panel.visible and home.pieces.size() == 1, "leaving left the stage or the panel showing, or Your pieces empty")

	# Opened again from Your pieces: made again as it was left, colors and all.
	home.edit_requested.emit(id)
	flow = main.flow
	check(flow != null and flow.editing == id, "Edit did not open the piece")
	check(await TestRunner.until(tree, func(): return panel.step == "preview" and not flow.job.running, 180.0), "the piece opened to edit was not made again")
	check(panel.editing.get("id", "") == id and panel.options.get("colour", {}).get("hue") == 120.0 and panel.tints.get("hue") == 120.0, "the piece opened to edit lost its colors: %s" % [panel.options])

	# Closing the window while it saves: the save finishes, then Studio ends.
	panel.save_requested.emit(out, "Closing")
	main.close()
	check(quits[0] == 0, "closing during a save ended Studio before the save was done")
	check(await TestRunner.until(tree, func(): return quits[0] == 1, 240.0), "closing during a save never ended Studio")
	check(FileAccess.file_exists(out.path_join("Closing/piece.json")) and FileAccess.file_exists(out.path_join("Closing/character.glb")), "the piece being saved at closing is not whole")
	check(not DirAccess.dir_exists_absolute(out.path_join(".Closing.part")), "closing during a save left a part folder behind")

	tree.auto_accept_quit = true
	main.queue_free()
	await tree.process_frame
	await tree.process_frame
	StudioFiles.remove_tree(out)
	StudioFiles.remove_tree(ProjectSettings.globalize_path(LIBRARY))
	return failures

## The share of `before`'s colored pixels whose hue is a third of a turn on in `after`.
func _turned(before: Image, after: Image) -> float:
	var a := before.duplicate()
	var b := after.duplicate()
	for image: Image in [a, b]:
		if image.is_compressed():
			image.decompress()
		image.resize(64, 64, Image.INTERPOLATE_NEAREST)
	var colored := 0
	var turned := 0
	for y in 64:
		for x in 64:
			var was: Color = a.get_pixel(x, y)
			if was.s < 0.3 or was.v < 0.2:
				continue
			colored += 1
			if absf(angle_difference(TAU * b.get_pixel(x, y).h, TAU * (was.h + 1.0 / 3.0))) < deg_to_rad(25.0):
				turned += 1
	return float(turned) / maxf(colored, 1.0)

func _copy(name: String) -> String:
	var path := ProjectSettings.globalize_path(OUT.path_join(name + ".glb"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURES + name + ".bin"))
	file.close()
	return path
