class_name Studio
## Studio turns a model someone already has into a piece, with
## nothing to learn about the contract's skeleton, clips or limits.
##
## Threads: open, map and make work on plain data and on nodes outside the
## tree, so they may run on a worker. Building the piece's scene, writing it
## and checking it (a child process the validator waits for frame by frame)
## stay on the main thread.
##
##   AgentGuildStudio -- --build=model.glb --slot=guild/openai --out=DIR [--height=2.1] [--title=T] [--map=LeftHand=hand_l,...|swap|accept] [--hue=DEGREES] [--tint=#RRGGBB] [--pick=#RRGGBB --spread=0.15]
##   AgentGuildStudio -- --build=ghost.glb[,b.glb,c.glb,d.glb] --slot=grove/companion --out=DIR [--move=rigid|soft] [--variants=tint|turn] [--turn=DEGREES]
##   AgentGuildStudio -- --recolour=look0|look1|look2|agent|shell --slot=... --out=DIR [--pick=#RRGGBB|U,V] [--spread=0.15] [--hue=DEGREES] [--tint=#RRGGBB]

## Each world's Studio clip set: its motions with
## both arms free, on a skeleton of its own, for character pieces.
const CLIP_SETS := "res://assets/premium/studio/%s.glb"

static func version() -> String:
	var stamped := String(ProjectSettings.get_setting("application/config/version", ""))
	return stamped if stamped != "" else "dev"

## { world, kind, crew } for "world/crew" or "world/companion", or { reason }.
static func slot(text: String) -> Dictionary:
	var parts := text.split("/")
	if parts.size() != 2 or not YardModel.WORLDS.has(parts[0]):
		return { "reason": "the slot is a world and a crew, like guild/anthropic" }
	if parts[1] == "companion":
		return { "world": parts[0], "kind": "companion", "crew": "" }
	if not parts[1] in YardModel.PROVIDER_ORDER:
		return { "reason": "%s is not an Agent Guild crew" % parts[1] }
	return { "world": parts[0], "kind": "character", "crew": parts[1] }

## The slot's default model, as the game shows it, outside the tree.
static func default_model(where: Dictionary) -> Node:
	var world: Dictionary = YardModel.WORLDS[where.world]
	var name: String = world.characters + str(YardModel.characterIndex(where.crew)) if where.kind == "character" else world.helpers.agent + "0"
	var path := StudioArt.model_path(where.world, name)
	var scene: PackedScene = load(path) if path != "" else null
	return scene.instantiate() if scene else null

## What a character piece in `world` is built on, as StudioCharacter.fit
## takes a default: the world's clip set's rig and clips, each clip as long
## as the slot default's (`default`), with the default's height, gait and
## glance, and each clip at the set's smaller arm reaches (`reach`: clip to
## [[reach, Animation]], most first); or, with no set in this build, the
## default as it is.
static func built_on(world: String, default: Node) -> Dictionary:
	var slot := StudioCharacter.default_of(default)
	if not ResourceLoader.exists(CLIP_SETS % world):
		return slot
	var model: Node = (load(CLIP_SETS % world) as PackedScene).instantiate()
	var clip_set := StudioCharacter.default_of(model)
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false).front()
	var clips := {}
	var reach := {}
	for clip in slot.clips:
		clips[clip] = _timed(clip_set.clips[clip], slot.clips[clip].length)
		var less := []
		for name in player.get_animation_list():
			if String(name).begins_with(clip + "~"):
				less.append([int(String(name).get_slice("~", 1)) / 100.0, _timed(player.get_animation(name), slot.clips[clip].length)])
		less.sort_custom(func(a, b): return a[0] > b[0])
		reach[clip] = less
	model.free()
	var yard: Dictionary = slot.yard.duplicate()
	yard.events = []
	yard.surface = clip_set.yard.get("surface", yard.get("surface", 0.0))
	return { "rig": clip_set.rig, "clips": clips, "yard": yard, "reach": reach }

## `anim` played over `length` seconds.
static func _timed(anim: Animation, length: float) -> Animation:
	if absf(anim.length - length) < PieceCheck.CLIP_SLACK:
		return anim
	var scale := length / anim.length
	var out: Animation = anim.duplicate()
	out.length = length
	for t in out.get_track_count():
		var keys := []
		for k in out.track_get_key_count(t):
			keys.append([out.track_get_key_time(t, k) * scale, out.track_get_key_value(t, k)])
		while out.track_get_key_count(t) > 0:
			out.track_remove_key(t, 0)
		for key in keys:
			out.track_insert_key(t, key[0], key[1])
	return out

## The player's choices over the guessed map: "Contract=model bone" pairs,
## "swap" for a rig that names its sides the other way round, and "accept"
## to take the bones read from the model's shape as they are. A bone read
## from the shape stays unsure until the player names or accepts it.
static func with_choices(rig: Dictionary, guessed: Dictionary, pairs: String, surfaces := []) -> Dictionary:
	var named: Dictionary = StudioBones.swapped(guessed.map) if "swap" in pairs.split(",", false) else guessed.map.duplicate()
	var chosen := {}
	for pair in pairs.split(",", false):
		var kv := pair.split("=")
		var bone: int = rig.names.find(kv[1]) if kv.size() == 2 else -1
		if bone >= 0:
			named[kv[0]] = bone
			chosen[kv[0]] = true
	var out := StudioBones.settle(rig, named, guessed.rig, surfaces)
	if not "accept" in pairs.split(",", false):
		for bone in guessed.unsure:
			if guessed.unsure[bone] == StudioBones.GUESSED and not chosen.has(bone) and named.has(bone):
				out.unsure[bone] = StudioBones.GUESSED
	return out

## The piece as plain data, or { reason }, or { unsure, map, skeleton } (the
## model's own skeleton) for the player to settle. `path` is a staged model
## (StudioSource.stage).
## `options`: height (metres), map ("Contract=bone" pairs). Built on
## `world`'s clip set (built_on), or with no world on the default's own
## rig and clips. Any thread.
static func make(path: String, default: Node, options := {}, world := "") -> Dictionary:
	var opened := StudioSource.open(path)
	if opened.has("reason"):
		return opened
	var source := StudioSource.read(opened.model)
	opened.model.free()
	if source.has("reason"):
		return source
	source.rig.follows = StudioSource.follows(source.rig, opened.json, opened.nodes)
	var bones := StudioBones.guess(source.rig, StudioBones.from_vrm(opened.json, opened.nodes, source.rig), source.surfaces)
	if options.has("map"):
		bones = with_choices(source.rig, bones, options.map, source.surfaces)
	if bones.has("reason"):
		return { "reason": bones.reason }
	if not bones.unsure.is_empty():
		return { "unsure": bones.unsure, "map": bones.map, "skeleton": source.rig }
	var slot_default := StudioCharacter.default_of(default)
	var piece := StudioCharacter.fit(source, bones.map, built_on(world, default) if world != "" else slot_default, float(options.get("height", 0.0)))
	var default_mesh := StudioSource.read(default)
	if not default_mesh.has("reason"):
		var holds := StudioTools.held(default_mesh)
		piece.notes += StudioTools.carry(piece, slot_default, holds, String(default.name), options.get("permitted", StudioTools.SHAREABLE))
	var fitted := StudioLimits.fit(piece, options.get("limits", PieceCheck.LIMITS.character))
	if fitted.has("reason"):
		return fitted
	piece.notes += fitted.notes
	return piece

## A world's four companions as plain data, { pieces, notes } or { reason }.
## One path is shown four ways (`variants`: tint or turn); four paths are
## one each. A humanoid is folded onto the trunk; anything else rides it
## (`move`: rigid or soft). `turn` turns a model before it's faced. Any thread.
static func make_companions(paths: Array, default: Node, options := {}) -> Dictionary:
	var helper := StudioCompanion.default_of(default)
	var pieces := []
	var notes := []
	for path in paths:
		var opened := StudioSource.open(path)
		if opened.has("reason"):
			return opened
		var source := StudioSource.read(opened.model)
		if not source.has("reason"):
			source.rig.follows = StudioSource.follows(source.rig, opened.json, opened.nodes)
			var bones := StudioBones.guess(source.rig, StudioBones.from_vrm(opened.json, opened.nodes, source.rig), source.surfaces)
			if bones.has("reason") or not bones.unsure.is_empty():
				source = StudioSource.read_still(opened.model)
			else:
				source.map = bones.map
		else:
			source = StudioSource.read_still(opened.model)
		opened.model.free()
		if source.has("reason"):
			return source
		var piece := StudioCompanion.fit(source, helper, options)
		var fitted := StudioLimits.fit(piece, options.get("limits", PieceCheck.LIMITS.companion))
		if fitted.has("reason"):
			return fitted
		notes += piece.notes + fitted.notes
		pieces.append(piece)
	if pieces.size() == 1:
		pieces = StudioCompanion.variants(pieces[0], options.get("variants", "tint"))
	if pieces.size() != 4:
		return { "reason": "companions come as one model or four" }
	var unique := []
	for note in notes:
		if not note in unique:
			unique.append(note)
	return { "pieces": pieces, "notes": unique }

## One of Studio's makes, as the screens ask for it: `files` (one model, or
## companions' one or four) or `recolour` ({ which, change }) for the slot
## `where`. Returns { where, notes, and pieces (plain data) or recoloured
## (models), and the slot default (`default`) or, for companions, a character
## to stand them round (`host`) } or { reason } or { unsure, map, skeleton }.
## A recolor with `options.preview` is made at most that many pixels a side,
## with the look's main colors (`colors`).
## On a worker: models are made outside the tree, for the main thread to show.
static func work(where: Dictionary, files: Array, recolour: Dictionary, options: Dictionary) -> Dictionary:
	var default := default_model(where)
	if default == null:
		return { "reason": "the slot's default model is not in this build" }
	var out := { "where": where, "notes": [] }
	if where.kind == "companion":
		out.host = default_model({ "world": where.world, "kind": "character", "crew": "anthropic" })
	if not recolour.is_empty():
		var shipped := StudioRecolour.models(where, recolour.which)
		default.free()
		if shipped.has("reason"):
			_free_host(out)
			return shipped
		var most := int(options.get("preview", 0))
		if most > 0:
			out.colors = StudioRecolour.palette(shipped.models, most)
			out.reduced = true
		for model in shipped.models:
			StudioRecolour.dress(model, recolour.change, most)
		out.recoloured = shipped.models
		return out
	var made: Dictionary
	if where.kind == "character":
		var o := options.duplicate()
		if o.has("height_share"):
			o.height = float(YardRig.extras(default).get("height", 2.0)) * float(o.height_share)
		made = make(files[0], default, o, where.world) if not files.is_empty() else { "reason": "no model was chosen" }
		if made.has("rig"):
			made = { "pieces": [made], "notes": made.notes }
	else:
		made = make_companions(files, default, options) if not files.is_empty() else { "reason": "no model was chosen" }
		default.free()
	if not made.has("pieces"):
		if where.kind == "character":
			default.free()
		_free_host(out)
		return made
	out.pieces = made.pieces
	out.notes = made.notes
	# The piece's colors changed (`options.colour`, a StudioRecolour change):
	# `base` keeps it as made, to change them again without making it again.
	var colour := StudioRecolour.read(options.get("colour", {}))
	if not StudioRecolour.plain(colour):
		var most := int(options.get("preview", 0))
		out.base = made.pieces
		out.pieces = StudioRecolour.painted(made.pieces, colour, most)
		out.reduced = most > 0
	if where.kind == "character":
		out.default = default
	return out

static func _free_host(out: Dictionary) -> void:
	if out.get("host") is Node:
		out.host.free()
		out.erase("host")

## A change for StudioRecolour from the command line's words: --pick as a
## colour (#RRGGBB) or a point (U,V) on the first model's base colour.
static func change_from(options: Dictionary, models: Array) -> Dictionary:
	var change := { "spread": float(options.get("spread", 0.15)), "hue": float(options.get("hue", 0.0)) }
	if options.has("tint"):
		change.tint = Color(options.tint)
	var pick: String = options.get("pick", "")
	if pick.begins_with("#"):
		change.pick = Color(pick)
	elif pick.contains(","):
		var uv := Vector2(float(pick.get_slice(",", 0)), float(pick.get_slice(",", 1)))
		for mi: MeshInstance3D in models[0].find_children("*", "MeshInstance3D", true, false):
			var material := mi.get_active_material(0)
			if material is BaseMaterial3D and material.albedo_texture:
				var image: Image = material.albedo_texture.get_image().duplicate()
				if image.is_compressed():
					image.decompress()
				change.pick = image.get_pixelv(Vector2i(uv.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(image.get_size() - Vector2i.ONE)))
				break
	return change

## What the last run() said: { reason } when it failed, with { unsure, bones }
## when bones need choosing; else { folder, notes }. `quiet` keeps a run off
## stdout, which an agent's connection owns.
static var said := {}
static var quiet := false

## The --build and --recolour commands: make a piece folder and check it as
## Looks would.
static func run(host: Node, options: Dictionary) -> int:
	said = {}
	var where := slot(options.get("slot", ""))
	if where.has("reason"):
		return _fail(where.reason)
	var default := default_model(where)
	if default == null:
		return _fail("the slot's default model is not in this build")
	var made: Dictionary
	var clips := {}
	if options.has("recolour"):
		var shipped := StudioRecolour.models(where, options.recolour)
		var defaults: Dictionary = (StudioCharacter.default_of(default) if where.kind == "character" else StudioCompanion.default_of(default)).clips
		for name in defaults:
			clips[name] = defaults[name].length
		default.free()
		if shipped.has("reason"):
			return _fail(shipped.reason)
		var change := change_from(options, shipped.models)
		for model in shipped.models:
			StudioRecolour.dress(model, change)
		return await _save(host, where, shipped.models, clips, options.get("title", "%s %s" % [where.world, options.recolour]), [], options)
	var validator := PieceValidator.new()
	host.add_child(validator)
	var staged := await StudioSource.stage(validator, [options.build] if where.kind == "character" else Array(options.build.split(",")))
	validator.queue_free()
	if staged.has("reason"):
		default.free()
		return _fail(staged.reason)
	if where.kind == "character":
		made = make(staged.paths[0], default, options, where.world)
		var defaults: Dictionary = StudioCharacter.default_of(default).clips
		for name in defaults:
			clips[name] = defaults[name].length
		if made.has("rig"):
			made = { "pieces": [made], "notes": made.notes }
	else:
		made = make_companions(staged.paths, default, options)
		var defaults: Dictionary = StudioCompanion.default_of(default).clips
		for name in defaults:
			clips[name] = defaults[name].length
	default.free()
	StudioFiles.remove_tree(staged.dir)
	if made.has("pieces") and (options.has("hue") or options.has("tint") or options.has("pick")):
		if String(options.get("pick", "#")).contains(","):
			return _fail("--pick takes a color (#RRGGBB) for a model you bring")
		made.pieces = StudioRecolour.painted(made.pieces, change_from(options, []))
	if made.has("notes"):
		made.notes = made.notes + staged.notes
	if made.has("unsure"):
		said = { "unsure": made.unsure, "bones": Array(made.skeleton.names) }
		return _fail("these bones need choosing (--map=Contract=bone, swap or accept): " + ", ".join(made.unsure.keys().map(func(k): return "%s (%s)" % [k, made.unsure[k]])))
	if made.has("reason"):
		return _fail(made.reason)
	var models: Array = made.pieces.map(func(p): return StudioExport.scene(p, where.kind))
	return await _save(host, where, models, clips, options.get("title", options.build.get_slice(",", 0).get_file().get_basename()), made.notes, options)

## Writes the models as a piece folder, frees them, and checks each as Looks
## would.
static func _save(host: Node, where: Dictionary, models: Array, clips: Dictionary, title: String, notes: Array, options: Dictionary) -> int:
	var folder := ProjectSettings.globalize_path(options.get("out", "user://studio/build")).rstrip("/\\")
	var manifest := { "format": 1, "kind": where.kind, "world": where.world, "title": title }
	if where.kind == "character":
		manifest.crew = where.crew
	var other := StudioExport.other(folder)
	if other != "":
		for model in models:
			model.free()
		return _fail("%s holds %s, which a piece may not" % [folder, other])
	var part := StudioFiles.make_beside(folder, "part")
	var reason := StudioExport.save(models, part, manifest) if part != "" else "a folder to work in could not be made in %s" % folder.get_base_dir()
	for model in models:
		model.free()
	if reason == "":
		var validator := PieceValidator.new()
		host.add_child(validator)
		for k in models.size():
			var file: String = PieceLibrary.FILES[where.kind][k]
			var verdict: Dictionary = await validator.check(part.path_join(file), where.kind, clips)
			if verdict.reason != "":
				reason = "%s did not pass its check: %s" % [file, verdict.reason]
				break
		validator.queue_free()
	if reason == "":
		reason = PieceLibrary.check_folder(part).get("reason", "")
	if reason == "":
		reason = StudioFiles.move_in(part, folder, StudioExport.names())
	if part != "":
		StudioFiles.remove_tree(part)
	if reason != "":
		return _fail(reason)
	said = { "folder": folder, "notes": notes }
	if not quiet:
		for note in notes:
			print("studio: " + note)
		print("studio: %s pass%s, in %s" % [", ".join(PieceLibrary.FILES[where.kind]), "" if where.kind == "companion" else "es", folder])
	return 0

static func _fail(reason: String) -> int:
	said.reason = reason
	printerr("studio: " + reason)
	return 1
