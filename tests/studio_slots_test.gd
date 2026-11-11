extends RefCounted
## Studio against every real slot, with every art pack in place (STUDIO_ART
## names their folder): the Mixamo fixture becomes
## a character for each world's every crew, on its world's clip set, passing
## the game's check with that slot's own clip lengths (the pounding gnome's
## longer work too), planting its feet at that slot's walking speed and
## working with both arms, though most defaults keep theirs still; a ball
## becomes each world's four companions; and every look and helper set of
## every world is recoloured. With STUDIO_PIECES set, every piece is kept
## there for agent-guild's checker (tools/check_with_agent_guild.mjs).

const FIXTURES := "res://tests/fixtures/pieces/"
const OUT := "user://studio/slots-test/"

var failures := []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
	for world in YardModel.WORLDS:
		var reason := StudioArt.load_packs(StudioArt.packs_for(world))
		if reason != "":
			return [reason + "; build the packs (tools/pack_art.py) and set STUDIO_ART to their folder"]
	var validator := PieceValidator.new()
	tree.root.add_child(validator)
	var source := _copy("studio_mixamo")
	var ball := _copy("studio_ball")
	for world in YardModel.WORLDS:
		for crew in YardModel.PROVIDER_ORDER:
			var where := Studio.slot("%s/%s" % [world, crew])
			var default := Studio.default_model(where)
			var theirs := StudioCharacter.default_of(default)
			var piece := Studio.make(source, default, {}, world)
			default.free()
			if not piece.has("surfaces"):
				check(false, "%s/%s: the fixture was not made into a piece: %s" % [world, crew, piece.get("reason", piece.get("unsure", ""))])
				continue
			for side in ["Left", "Right"]:
				var swing := maxf(_swing(piece.clips.work_0, side + "UpperArm"), _swing(piece.clips.work_0, side + "LowerArm"))
				check(swing >= ARMS_WORK, "%s/%s: its %s arm turns %.1f° at work" % [world, crew, side.to_lower(), swing])
			var speed := StudioCharacter.walking_speed(theirs.yard)
			var slid := StudioFeet.slide(piece.rig, piece.clips.walk, speed, float(piece.yard.height))
			check(slid <= StudioFeet.SLIDE * float(piece.yard.height), "%s/%s: its feet slide %.3f m at %.2f m/s" % [world, crew, slid, speed])
			var reason := await _passes(validator, [StudioExport.scene(piece, "character")], where, _lengths(theirs), "made")
			check(reason == "", "%s/%s: the piece did not pass the game's check: %s" % [world, crew, reason])
			for which in ["look0", "look1", "look2"]:
				var looks := StudioRecolour.models(where, which)
				check(looks.has("models"), "%s/%s: %s is not in this build" % [world, crew, which])
				if looks.has("models"):
					for m in looks.models:
						StudioRecolour.dress(m, { "hue": 30.0 })
					var why := await _passes(validator, looks.models, where, _lengths(theirs), which)
					check(why == "", "%s/%s: its recoloured %s did not pass the game's check: %s" % [world, crew, which, why])
		var companions_slot := Studio.slot("%s/companion" % world)
		var helper := Studio.default_model(companions_slot)
		var helper_data := StudioCompanion.default_of(helper)
		var made := Studio.make_companions([ball], helper)
		helper.free()
		check(made.has("pieces"), "%s: a ball was not made into companions: %s" % [world, made.get("reason", "")])
		if made.has("pieces"):
			var reason := await _passes(validator, made.pieces.map(func(p): return StudioExport.scene(p, "companion")), companions_slot, _lengths(helper_data), "made")
			check(reason == "", "%s: the companions did not pass the game's check: %s" % [world, reason])
		for which in ["agent", "shell"]:
			var sets := StudioRecolour.models(companions_slot, which)
			check(sets.has("models"), "%s: its %s helpers are not in this build" % [world, which])
			if sets.has("models"):
				for m in sets.models:
					StudioRecolour.dress(m, { "hue": 30.0 })
				var why := await _passes(validator, sets.models, companions_slot, _lengths(helper_data), which)
				check(why == "", "%s: its recoloured %s helpers did not pass the game's check: %s" % [world, which, why])
		var look := Studio.slot("%s/anthropic" % world)
		var shipped := StudioRecolour.models(look, "look0")
		check(shipped.has("models"), "%s: its first look is not in this build" % world)
		if shipped.has("models"):
			var default := Studio.default_model(look)
			var lengths := _lengths(StudioCharacter.default_of(default))
			default.free()
			var colors := StudioRecolour.palette(shipped.models, StudioFlow.PREVIEW_SIDE)
			var seen := _changed_share(shipped.models[0], { "pick": colors[0], "spread": StudioPanel.SPREAD, "tint": StudioPanel.contrast(colors[0]) }) if not colors.is_empty() else 0.0
			check(seen >= 0.02, "%s: Change one color first changes %s, %.1f%% of its look" % [world, colors.front() if colors else "nothing", seen * 100.0])
			for m in shipped.models:
				m.free()
	validator.free()
	_keep()
	_empty(OUT)
	return failures

func _keep() -> void:
	var to := OS.get_environment("STUDIO_PIECES")
	if to == "":
		return
	var from := ProjectSettings.globalize_path(OUT)
	for name in DirAccess.get_directories_at(from):
		DirAccess.make_dir_recursive_absolute(to.path_join(name))
		for file in DirAccess.get_files_at(from.path_join(name)):
			DirAccess.copy_absolute(from.path_join(name).path_join(file), to.path_join(name).path_join(file))

## The share of a model's vertices whose base color `change` visibly changes.
func _changed_share(model: Node, change: Dictionary) -> float:
	var seen := 0
	var all := 0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var material := mi.get_active_material(s)
			if not material is BaseMaterial3D or material.albedo_texture == null:
				continue
			var image: Image = material.albedo_texture.get_image().duplicate()
			image.decompress()
			var size := Vector2(image.get_size())
			for uv: Vector2 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]:
				var c := image.get_pixelv(Vector2i((Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0)) * size).floor().clamp(Vector2.ZERO, size - Vector2.ONE)))
				var to := StudioRecolour.changed(c, change)
				all += 1
				if Vector3(to.r - c.r, to.g - c.g, to.b - c.b).length() > 0.05:
					seen += 1
	return float(seen) / maxi(all, 1)

## The least an arm turns at work, in degrees.
const ARMS_WORK := 5.0

## The most `bone` turns from where it starts in `anim`, in degrees.
static func _swing(anim: Animation, bone: String) -> float:
	var t := anim.find_track(NodePath("Skeleton3D:" + bone), Animation.TYPE_ROTATION_3D)
	if t < 0:
		return 0.0
	var start: Quaternion = anim.rotation_track_interpolate(t, 0.0)
	var most := 0.0
	for k in 48:
		most = maxf(most, rad_to_deg(start.angle_to(anim.rotation_track_interpolate(t, anim.length * k / 48.0))))
	return most

static func _lengths(model: Dictionary) -> Dictionary:
	var out := {}
	for clip in model.clips:
		out[clip] = model.clips[clip].length
	return out

## Writes the models as a piece and checks each as Looks would; frees them.
func _passes(validator: PieceValidator, models: Array, where: Dictionary, lengths: Dictionary, what: String) -> String:
	var folder := ProjectSettings.globalize_path(OUT.path_join("%s-%s-%s" % [where.world, where.crew if where.kind == "character" else "companion", what]))
	var manifest := { "format": 1, "kind": where.kind, "world": where.world, "title": "Slot test" }
	if where.kind == "character":
		manifest.crew = where.crew
	var reason := StudioExport.save(models, folder, manifest)
	for m in models:
		m.free()
	if reason != "":
		return reason
	for k in models.size():
		var verdict: Dictionary = await validator.check(folder.path_join(PieceLibrary.FILES[where.kind][k]), where.kind, lengths)
		if verdict.reason != "":
			return "%s: %s" % [PieceLibrary.FILES[where.kind][k], verdict.reason]
	return ""

func _copy(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var path := ProjectSettings.globalize_path(OUT.path_join(name + ".glb"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURES + name + ".bin"))
	file.close()
	return path

func _empty(dir: String) -> void:
	var abs := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for sub in DirAccess.get_directories_at(abs):
		_empty(dir.path_join(sub))
	for file in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file))
	DirAccess.remove_absolute(abs)
