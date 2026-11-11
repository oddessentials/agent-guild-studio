extends RefCounted
## Studio makes a character from a Mixamo-named model (tests/fixtures/pieces/
## studio_*.bin, from tools/pieces/make_studio_fixtures.py and
## make_studio_fbx.py): it reads the model as Godot skins it, uneven scales
## and all; keeps its shape; turns every bone as the slot default does through
## every clip; and, once written and loaded back, the mesh moves with its
## source's own weights (hands, hips and four-bone blends), its hands clear of
## its body. Its extras follow the default, it passes the game's own check,
## and what Studio can't tell for sure is left to the player.
##
## A clip that tears a piece's mesh plays at the least smaller arm reach
## that doesn't, as rig.py bakes the cast's, and says so.
##
## A ball and a humanoid become a world's four companions: on the helper's
## trunk, as tall as the helper, its clips played unchanged; riding the trunk
## rigidly or softly, a humanoid's arms hanging and limbs folded in; four
## tints or turns of one model, or four models.
##
## A default's tool is never copied on its own: a piece's hands stay empty,
## and it says why, unless the tool comes away cleanly and is permitted;
## then it is carried in the same hand, where the default holds it.
##
## A look is recoloured: the picked colour (and only colours near it) turns
## or takes a tint, a hue turn with nothing picked moves every colour, and a
## recoloured model keeps its mesh and clips exactly and passes the check.
##
## Every common rig is read: each tool's names, a VRM's own map, a rig
## without shoulders or toes (and one naming its sides the
## other way round), a VRM's aimed sleeves, a part that isn't skinned; and
## pieces come within the limits: too many textures combined into one, too
## many faces reduced.

const FIXTURES := "res://tests/fixtures/pieces/"
const OUT := "user://studio/test/"
## How far a vertex may stray, in metres on a 2 m figure.
const NEAR := 0.002

var failures := []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
	var default: Node = StudioSource.open(_copy("studio_default")).model
	var path := _copy("studio_mixamo")
	var opened: Node = StudioSource.open(path).model
	var source := StudioSource.read(opened)
	opened.free()
	_reads_at_rest(path, source)
	var piece := Studio.make(path, default)
	check(piece.has("rig"), "the Mixamo fixture was not made into a piece: %s" % [piece.get("reason", piece.get("unsure", ""))])
	if not piece.has("rig"):
		default.free()
		return failures
	_keeps_shape(source, piece)
	var folder := ProjectSettings.globalize_path(OUT.path_join("mixamo"))
	var root := StudioExport.scene(piece, "character")
	check(StudioExport.save([root], folder, { "format": 1, "kind": "character", "world": "guild", "crew": "anthropic", "title": "Fixture" }) == "",
		"the piece could not be written")
	root.free()
	var written: Node = StudioSource.open(folder.path_join("character.glb")).model
	var mine := StudioCharacter.default_of(written)
	var theirs := StudioCharacter.default_of(default)
	_turns_like_default(mine, theirs)
	_feet_planted(mine, theirs)
	_keyed_like_default(piece, theirs)
	_short_legs(path, default, theirs)
	_glides(path)
	_eases(default)
	_yard(mine.yard, theirs, mine)
	_moves_with_source(written, mine, source, piece)
	_hands_clear(written, mine)
	written.free()
	var lengths := {}
	for clip in theirs.clips:
		lengths[clip] = theirs.clips[clip].length
	var validator := PieceValidator.new()
	tree.root.add_child(validator)
	var verdict: Dictionary = await validator.check(folder.path_join("character.glb"), "character", lengths)
	check(verdict.reason == "", "the piece did not pass the game's check: %s" % verdict.reason)
	validator.free()
	_names()
	await _rigs(tree, default, lengths)
	await _companions(tree)
	_tools(default)
	_recolours()
	await _recoloured_model(tree, lengths)
	_unsure()
	await _sources(tree)
	default.free()
	_keep()
	_empty(OUT)
	return failures

## With STUDIO_PIECES set, every piece folder this run wrote is copied there,
## for agent-guild's checker (tools/check_with_agent_guild.mjs).
func _keep() -> void:
	var to := OS.get_environment("STUDIO_PIECES")
	if to == "":
		return
	var from := ProjectSettings.globalize_path(OUT)
	for name in DirAccess.get_directories_at(from):
		if not FileAccess.file_exists(from.path_join(name).path_join("piece.json")):
			continue
		DirAccess.make_dir_recursive_absolute(to.path_join(name))
		for file in DirAccess.get_files_at(from.path_join(name)):
			DirAccess.copy_absolute(from.path_join(name).path_join(file), to.path_join(name).path_join(file))

## Studio reads a skinned model where its file puts it at rest (glTF's
## vertices are the rest pose), under an unevenly scaled node and bone.
func _reads_at_rest(path: String, source: Dictionary) -> void:
	var state := GLTFState.new()
	GLTFDocument.new().append_from_file(path, state)
	var authored := []
	for mesh: GLTFMesh in state.get_meshes():
		for s in mesh.mesh.get_surface_count():
			authored.append(mesh.mesh.get_surface_arrays(s)[Mesh.ARRAY_VERTEX])
	var worst := 0.0
	for s in mini(authored.size(), source.surfaces.size()):
		for v in mini(authored[s].size(), source.surfaces[s].verts.size()):
			worst = maxf(worst, authored[s][v].distance_to(source.surfaces[s].verts[v]))
	check(authored.size() == source.surfaces.size() and worst < 1e-4, "Studio read the model %.5f m from where its file puts it" % worst)

## Each part bound to one bone keeps its shape: one scale, no shear.
func _keeps_shape(source: Dictionary, piece: Dictionary) -> void:
	var worst := 0.0
	var scale := -1.0
	for s in source.surfaces.size():
		var src: Dictionary = source.surfaces[s]
		var groups := {}
		for v in src.verts.size():
			if src.weights[v * src.per] > 0.999:
				groups.get_or_add(src.bones[v * src.per], []).append(v)
		for vs in groups.values():
			for a in vs.size():
				for b in range(a + 1, vs.size()):
					var before: float = src.verts[vs[a]].distance_to(src.verts[vs[b]])
					var after: float = piece.surfaces[s].verts[vs[a]].distance_to(piece.surfaces[s].verts[vs[b]])
					if before > 1e-4:
						if scale < 0.0:
							scale = after / before
						worst = maxf(worst, absf(after / before / scale - 1.0))
	check(scale > 0.0 and worst < 1e-3, "a part of the model was stretched or sheared (by %.4f)" % worst)

## Every bone but the legs turns as the default's does through every clip,
## and the hips rise and fall with its, scaled to the piece, never above it
## (lowered a little where a leg can't reach). At rest the arms point its way
## too, or swing out from it about the forward axis (no more than Studio
## allows) to clear the body.
func _turns_like_default(mine: Dictionary, theirs: Dictionary) -> void:
	var turn := 0.0
	var rise := 0.0
	var drop := 0.0
	var worst_bone := ""
	var hips := [mine.rig.names.find("Hips"), theirs.rig.names.find("Hips")]
	var ratio: float = StudioRig.rest_globals(mine.rig)[hips[0]].origin.y / StudioRig.rest_globals(theirs.rig)[hips[1]].origin.y
	var legs := []
	for side in ["Left", "Right"]:
		for bone in ["UpperLeg", "LowerLeg", "Foot"]:
			legs.append(side + bone)
	var a0 := StudioRig.rest_globals(mine.rig)
	var b0 := StudioRig.rest_globals(theirs.rig)
	var at := func(g: Array, rig: Dictionary, name: String) -> Vector3: return g[rig.names.find(name)].origin
	var swing := 0.0
	var off := 0.0
	for side in ["Left", "Right"]:
		var ours: Vector3 = at.call(a0, mine.rig, side + "LowerArm") - at.call(a0, mine.rig, side + "UpperArm")
		var its: Vector3 = at.call(b0, theirs.rig, side + "LowerArm") - at.call(b0, theirs.rig, side + "UpperArm")
		var angle := atan2(ours.x, -ours.y) - atan2(its.x, -its.y)
		swing = maxf(swing, absf(angle))
		var turned := Basis(Vector3.BACK, angle)
		for pair in [["UpperArm", "LowerArm"], ["LowerArm", "Hand"]]:
			var mine_dir: Vector3 = at.call(a0, mine.rig, side + pair[1]) - at.call(a0, mine.rig, side + pair[0])
			var its_dir: Vector3 = at.call(b0, theirs.rig, side + pair[1]) - at.call(b0, theirs.rig, side + pair[0])
			off = maxf(off, mine_dir.angle_to(turned * its_dir))
	check(rad_to_deg(off) < 1.0 and rad_to_deg(swing) <= StudioCharacter.SWING + 1.0,
		"at rest an arm pointed %.2f° from the default's swung out by %.1f°" % [rad_to_deg(off), rad_to_deg(swing)])
	for clip in theirs.clips:
		check(mine.clips.has(clip) and absf(mine.clips[clip].length - theirs.clips[clip].length) < 1e-4, "the piece's %s clip is not the default's length" % clip)
		if not mine.clips.has(clip):
			continue
		for f in int(theirs.clips[clip].length * 24.0) + 1:
			var t := f / 24.0
			var a := StudioRig.globals(mine.rig, StudioRig.pose(mine.rig, mine.clips[clip], t))
			var b := StudioRig.globals(theirs.rig, StudioRig.pose(theirs.rig, theirs.clips[clip], t))
			for i in b.size():
				if theirs.rig.names[i] in legs:
					continue
				var j: int = mine.rig.names.find(theirs.rig.names[i])
				var angle := Quaternion(a[j].basis.orthonormalized()).angle_to(Quaternion(b[i].basis.orthonormalized()))
				if angle > turn:
					turn = angle
					worst_bone = "%s in %s at %.2f s" % [theirs.rig.names[i], clip, t]
			var above := a[hips[0]].origin.y - b[hips[1]].origin.y * ratio
			rise = maxf(rise, above)
			drop = maxf(drop, -above)
	check(rad_to_deg(turn) < 0.2, "a bone turned %.2f° away from the default's (%s)" % [rad_to_deg(turn), worst_bone])
	check(rise < NEAR and drop < 0.05 * float(mine.yard.height), "the hips rose %.4f m above, or fell %.4f m below, the default's scaled to the piece" % [rise, drop])

## Feet stay planted at the speed the game walks the piece, its slot
## default's stride / cycle: in the walk each foot is down as long as the
## default's is, and slides no more than rig.py allows; standing clips the
## same, with the body still.
func _feet_planted(mine: Dictionary, theirs: Dictionary) -> void:
	var speed := float(theirs.yard.stride) / float(theirs.yard.cycle)
	var tall := float(mine.yard.height)
	var worst := ""
	for clip in mine.clips:
		var slid := StudioFeet.slide(mine.rig, mine.clips[clip], speed if clip == "walk" else 0.0, tall)
		if slid > StudioFeet.SLIDE * tall:
			worst += " %s %.3f m" % [clip, slid]
	check(worst == "", "planted feet slid at the game's walking speed:" + worst)
	for side in ["Left", "Right"]:
		var down := _planted_frames(mine, side)
		var theirs_down := _planted_frames(theirs, side)
		check(theirs_down > 0 and down >= theirs_down - 1, "the %s foot is planted for %d of the walk's frames; the default's for %d" % [side.to_lower(), down, theirs_down])

func _companions(tree: SceneTree) -> void:
	var helper_model: Node = StudioSource.open(_copy("studio_helper")).model
	var helper := StudioCompanion.default_of(helper_model)
	var tall := float(helper.yard.height)
	var lengths := {}
	for clip in helper.clips:
		lengths[clip] = helper.clips[clip].length
	var ball := Studio.make_companions([_copy("studio_ball")], helper_model)
	check(ball.has("pieces") and ball.pieces.size() == 4, "a ball was not made into four companions: %s" % [ball.get("reason", "")])
	if ball.has("pieces"):
		var first: Dictionary = ball.pieces[0]
		var low := INF
		var high := -INF
		var rigid := true
		var hips: int = first.rig.names.find("Hips")
		for s in first.surfaces:
			for v in s.verts.size():
				low = minf(low, s.verts[v].y)
				high = maxf(high, s.verts[v].y)
				rigid = rigid and s.bones[v * 4] == hips and is_equal_approx(s.weights[v * 4], 1.0)
		check(absf(low) < 1e-3 and absf(high - tall) < 1e-3, "a companion stands %.3f to %.3f m, not on the ground and %.2f m tall" % [low, high, tall])
		check(rigid, "a rigid companion is not all on its hips")
		var tints: Array = ball.pieces.map(func(p): return p.surfaces[0].look.color.to_html())
		var unique := {}
		for t in tints:
			unique[t] = true
		check(unique.size() == 4, "the four tints are not four colours: %s" % [tints])
		_trunk_turns_like_helper(first, helper)
		for k in 4:
			check(await _passes_as(tree, ball.pieces[k], "companion", "ball%d" % k, lengths) == "", "companion %d did not pass the game's check" % k)
		var four_models: Array = ball.pieces.map(func(p): return StudioExport.scene(p, "companion"))
		check(StudioExport.save(four_models, ProjectSettings.globalize_path(OUT.path_join("companions")), { "format": 1, "kind": "companion", "world": "guild", "title": "Fixture companions" }) == "",
			"the companions could not be written as a piece")
		for m: Node in four_models:
			m.free()
	var soft := Studio.make_companions([_copy("studio_ball")], helper_model, { "move": "soft" })
	if soft.has("pieces"):
		var piece: Dictionary = soft.pieces[0]
		var chain := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"].map(func(b): return piece.rig.names.find(b))
		var g := StudioRig.rest_globals(piece.rig)
		var wrong := 0
		for s in piece.surfaces:
			for v in s.verts.size():
				var below := 0
				for k in chain.size():
					if g[chain[k]].origin.y <= s.verts[v].y:
						below = k
				var near: Array = [chain[below], chain[mini(below + 1, chain.size() - 1)]]
				if not s.bones[v * 4] in near:
					wrong += 1
		check(wrong == 0, "%d of a soft companion's vertices are not on the trunk joints either side of them" % wrong)
	var turned := Studio.make_companions([_copy("studio_ball")], helper_model, { "variants": "turn" })
	if turned.has("pieces"):
		var spans: Array = turned.pieces.map(func(p): return snappedf(p.surfaces[0].verts[0].length(), 1e-4))
		check(spans.size() == 4 and spans[0] != spans[1] and spans[1] != spans[2], "the four turns are not four sizes and turns: %s" % [spans])
	var person := Studio.make_companions([_copy("studio_mixamo")], helper_model)
	check(person.has("pieces"), "a humanoid was not made into companions: %s" % [person.get("reason", "")])
	if person.has("pieces"):
		var widest := 0.0
		for s in person.pieces[0].surfaces:
			for v in s.verts:
				widest = maxf(widest, absf(v.x))
		check(widest < 0.3 * tall, "a humanoid companion's arms do not hang (it is %.2f m wide)" % [widest * 2])
		check(await _passes_as(tree, person.pieces[0], "companion", "person", lengths) == "", "a humanoid companion did not pass the game's check")
	var four := Studio.make_companions([_copy("studio_ball"), _copy("studio_mixamo"), _copy("studio_ball"), _copy("studio_mixamo")], helper_model)
	check(four.has("pieces") and four.pieces[0].surfaces[0].verts.size() != four.pieces[1].surfaces[0].verts.size(),
		"four given models were not made one companion each")
	helper_model.free()

func _tools(default: Node) -> void:
	var path := _copy("studio_mixamo")
	var plain := Studio.make(path, default)
	check(plain.has("surfaces") and plain.notes.any(func(n): return "isn't shared" in n) and not _holds(plain),
		"a default's tool that isn't permitted was carried, or the piece did not say its hand is empty: %s" % [plain.get("notes", [])])
	var shared := Studio.make(path, default, { "permitted": { String(default.name): true } })
	check(shared.has("surfaces") and _holds(shared), "a clean, permitted tool was not carried in the hand")
	if shared.has("surfaces"):
		var g := StudioRig.rest_globals(shared.rig)
		var prop: Vector3 = g[shared.rig.names.find("PropRight")].origin
		var theirs := StudioCharacter.default_of(default)
		var def_prop: Vector3 = StudioRig.rest_globals(theirs.rig)[theirs.rig.names.find("PropRight")].origin
		var reach := 0.0
		for s in shared.surfaces:
			if s.bones[0] == shared.rig.names.find("PropRight"):
				for v in s.verts:
					reach = maxf(reach, v.distance_to(prop))
		check(absf(reach - 0.354) < 0.01, "the carried tool does not hang from the piece's hand as from the default's (reaches %.3f m)" % reach)
	var fused_model: Node = StudioSource.open(_copy("studio_default_fused")).model
	var fused := Studio.make(path, fused_model, { "permitted": { String(fused_model.name): true } })
	check(fused.has("surfaces") and not _holds(fused) and fused.notes.any(func(n): return "part of its own mesh" in n),
		"a tool fused into the default's hand was carried, or the piece did not say so: %s" % [fused.get("notes", [])])
	fused_model.free()

## Whether a piece has a surface all on a prop bone: a tool in its hand.
func _holds(piece: Dictionary) -> bool:
	var props := [piece.rig.names.find("PropLeft"), piece.rig.names.find("PropRight")]
	for s in piece.surfaces:
		var all_prop: bool = s.verts.size() > 0
		for v in s.verts.size():
			all_prop = all_prop and s.bones[v * 4] in props and is_equal_approx(s.weights[v * 4], 1.0)
		if all_prop:
			return true
	return false

func _recolours() -> void:
	var image := Image.create(4, 1, false, Image.FORMAT_RGBA8)
	var red := Color8(200, 40, 40)
	var near := Color8(190, 50, 45)
	var green := Color8(40, 180, 60)
	var grey := Color8(128, 128, 128)
	for x in 4:
		image.set_pixel(x, 0, [red, near, green, grey][x])
	var picked := StudioRecolour.recolour(image, { "pick": red, "spread": 0.15, "hue": 120.0 })
	var close := func(a: Color, b: Color) -> bool: return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() < 3.0 / 255.0
	var hue_of := func(c: Color) -> float: return fposmod(c.h * 360.0, 360.0)
	check(absf(hue_of.call(picked.get_pixel(0, 0)) - fposmod(hue_of.call(red) + 120.0, 360.0)) < 3.0 and not close.call(picked.get_pixel(1, 0), near),
		"the picked colour and one near it did not turn: %s %s" % [picked.get_pixel(0, 0), picked.get_pixel(1, 0)])
	check(close.call(picked.get_pixel(2, 0), green) and close.call(picked.get_pixel(3, 0), grey), "colours far from the pick changed")
	var all := StudioRecolour.recolour(image, { "hue": 60.0 })
	var turned := true
	for x in 3:
		var before: float = hue_of.call([red, near, green][x])
		turned = turned and absf(angle_difference(deg_to_rad(hue_of.call(all.get_pixel(x, 0))), deg_to_rad(before + 60.0))) < deg_to_rad(4.0)
	check(turned, "a hue turn with nothing picked did not turn every colour")
	var tinted := StudioRecolour.recolour(image, { "pick": green, "spread": 0.1, "tint": Color8(40, 80, 220) })
	check(hue_of.call(tinted.get_pixel(2, 0)) > 200.0 and hue_of.call(tinted.get_pixel(2, 0)) < 250.0 and close.call(tinted.get_pixel(0, 0), red),
		"a tint did not take the picked colour, alone, toward its own: %s" % tinted.get_pixel(2, 0))

## A recoloured model is the same model, mesh and clips, in new colours.
func _recoloured_model(tree: SceneTree, lengths: Dictionary) -> void:
	var path := _copy("studio_default")
	var model: Node = StudioSource.open(path).model
	StudioRecolour.dress(model, { "hue": 90.0 })
	var folder := ProjectSettings.globalize_path(OUT.path_join("recolour"))
	check(StudioExport.save([model], folder, { "format": 1, "kind": "character", "world": "guild", "crew": "anthropic", "title": "Recolour" }) == "",
		"a recoloured model could not be written")
	model.free()
	var before := _read("studio_default")
	var after_model: Node = StudioSource.open(folder.path_join("character.glb")).model
	var after := StudioSource.read(after_model)
	var same: bool = before.surfaces.size() == after.surfaces.size()
	var worst := 0.0
	for k in mini(before.surfaces.size(), after.surfaces.size()):
		same = same and before.surfaces[k].verts.size() == after.surfaces[k].verts.size()
		for v in mini(before.surfaces[k].verts.size(), after.surfaces[k].verts.size()):
			worst = maxf(worst, before.surfaces[k].verts[v].distance_to(after.surfaces[k].verts[v]))
	check(same and worst < 1e-4, "recolouring changed the mesh (by %.5f m)" % worst)
	var original: Node = StudioSource.open(path).model
	_turns_like_default(StudioCharacter.default_of(after_model), StudioCharacter.default_of(original))
	original.free()
	var colour: Color = after.surfaces[0].look.image.get_pixel(0, 0)
	var was: Color = before.surfaces[0].look.image.get_pixel(0, 0)
	check(absf(angle_difference(deg_to_rad(colour.h * 360.0), deg_to_rad(was.h * 360.0 + 90.0))) < deg_to_rad(4.0),
		"the recoloured model's texture did not turn: %s from %s" % [colour, was])
	after_model.free()
	var validator := PieceValidator.new()
	tree.root.add_child(validator)
	var verdict: Dictionary = await validator.check(folder.path_join("character.glb"), "character", lengths)
	validator.free()
	check(verdict.reason == "", "a recoloured model did not pass the game's check: %s" % verdict.reason)

## The trunk turns as the helper's does through every clip.
func _trunk_turns_like_helper(piece: Dictionary, helper: Dictionary) -> void:
	var turn := 0.0
	for clip in helper.clips:
		for f in int(helper.clips[clip].length * 24.0) + 1:
			var a := StudioRig.globals(piece.rig, StudioRig.pose(piece.rig, piece.clips[clip], f / 24.0))
			var b := StudioRig.globals(helper.rig, StudioRig.pose(helper.rig, helper.clips[clip], f / 24.0))
			for i in b.size():
				turn = maxf(turn, Quaternion(a[i].basis.orthonormalized()).angle_to(Quaternion(b[i].basis.orthonormalized())))
	check(rad_to_deg(turn) < 0.2, "a companion's trunk turned %.2f° away from the helper's" % rad_to_deg(turn))

## The game's check of one model of a piece, written to its own folder.
func _passes_as(tree: SceneTree, piece: Dictionary, kind: String, name: String, lengths: Dictionary) -> String:
	var folder := ProjectSettings.globalize_path(OUT.path_join(name))
	var root := StudioExport.scene(piece, kind)
	var written := StudioExport.write_glb(root, folder.path_join("model.glb")) if DirAccess.make_dir_recursive_absolute(folder) == OK else FAILED
	root.free()
	if written != OK:
		return "it could not be written"
	var validator := PieceValidator.new()
	tree.root.add_child(validator)
	var verdict: Dictionary = await validator.check(folder.path_join("model.glb"), kind, lengths)
	validator.free()
	return verdict.reason

## The legs Studio solves are keyed on the default clip's own step, as
## Godot's importer bakes it, so nothing is resampled between the two.
func _keyed_like_default(piece: Dictionary, theirs: Dictionary) -> void:
	var walk: Animation = piece.clips.walk
	var step: float = theirs.clips.walk.step
	var off := 0
	for t in walk.get_track_count():
		if String(walk.track_get_path(t)).ends_with("Foot"):
			for k in walk.track_get_key_count(t):
				var at := walk.track_get_key_time(t, k) / step
				if absf(at - roundf(at)) > 1e-3 and not is_equal_approx(walk.track_get_key_time(t, k), walk.length):
					off += 1
	check(step > 0.0 and off == 0, "%d of the feet's keys fall between the default's frames (every %.4f s)" % [off, step])

## A piece too short to reach the default's stride lowers its hips to reach
## it, and its feet still stay planted.
func _short_legs(path: String, default: Node, theirs: Dictionary) -> void:
	var short := Studio.make(path, default, { "height": 0.8 })
	check(short.has("surfaces"), "a short piece was not made: %s" % [short.get("reason", short.get("unsure", ""))])
	if not short.has("surfaces"):
		return
	var speed := float(theirs.yard.stride) / float(theirs.yard.cycle)
	var slid := StudioFeet.slide(short.rig, short.clips.walk, speed, 0.8)
	var hips: int = short.rig.names.find("Hips")
	var rest_y: float = StudioRig.rest_globals(short.rig)[hips].origin.y
	var lowest := INF
	for k in int(round(short.clips.walk.length * StudioFeet.FPS)):
		lowest = minf(lowest, StudioRig.globals(short.rig, StudioRig.pose(short.rig, short.clips.walk, k / StudioFeet.FPS))[hips].origin.y)
	var def_hips: int = theirs.rig.names.find("Hips")
	var def_low := INF
	for k in int(round(theirs.clips.walk.length * StudioFeet.FPS)):
		def_low = minf(def_low, StudioRig.globals(theirs.rig, StudioRig.pose(theirs.rig, theirs.clips.walk, k / StudioFeet.FPS))[def_hips].origin.y)
	var scaled: float = def_low * rest_y / StudioRig.rest_globals(theirs.rig)[def_hips].origin.y
	check(slid <= StudioFeet.SLIDE * 0.8 and lowest < scaled - 0.005,
		"a short piece's feet slid %.3f m, or its hips (lowest %.3f m) did not drop below the default's scaled (%.3f m) to reach" % [slid, lowest, scaled])

## A default that glides (robed, its feet still) gives the piece a step of
## its own at the same speed, and the piece says so.
func _glides(path: String) -> void:
	var robed: Node = StudioSource.open(_copy("studio_default_glide")).model
	var theirs := StudioCharacter.default_of(robed)
	var speed := StudioCharacter.walking_speed(theirs.yard)
	var piece := Studio.make(path, robed)
	robed.free()
	check(StudioFeet.slide(theirs.rig, theirs.clips.walk, speed, 2.0) > StudioFeet.SLIDE * 2.0, "the gliding fixture default does not glide")
	var still := Animation.new()
	still.length = theirs.clips.walk.length
	still.loop_mode = Animation.LOOP_LINEAR
	check(StudioFeet.slide(theirs.rig, still, speed, 2.0) >= speed * still.length * 0.99, "feet down through a whole looping walk were not counted as sliding")
	if not piece.has("surfaces"):
		check(false, "a piece for a gliding default was not made")
		return
	var tall := float(piece.yard.height)
	var slid := StudioFeet.slide(piece.rig, piece.clips.walk, speed, tall)
	var foot: int = piece.rig.names.find("LeftFoot")
	var heights := []
	for k in int(round(piece.clips.walk.length * StudioFeet.FPS)):
		heights.append(StudioRig.globals(piece.rig, StudioRig.pose(piece.rig, piece.clips.walk, k / StudioFeet.FPS))[foot].origin.y)
	var lift: float = heights.max() - heights.min()
	check(lift >= 0.5 * StudioFeet.LIFT * tall, "a piece for a gliding default shuffles (its foot lifts %.3f m) rather than steps" % lift)
	check(slid <= StudioFeet.SLIDE * tall and piece.notes.any(func(n): return "glides" in n),
		"a piece for a gliding default slides %.3f m, or does not say it steps: %s" % [slid, piece.notes])

## How many of the walk's frames a foot is down, as StudioFeet judges it.
## A strip from the left shoulder to the hand, blended at the elbow: its
## work_1 tears it when the forearm pulls away from the elbow, at 80% reach
## too, and at 60% doesn't. The piece plays the 60% clip, and says so.
func _eases(default: Node) -> void:
	var base := StudioCharacter.default_of(default)
	var rig: Dictionary = base.rig
	var globals := StudioRig.rest_globals(rig)
	var upper: int = rig.names.find("LeftUpperArm")
	var lower: int = rig.names.find("LeftLowerArm")
	var points := [globals[upper].origin, globals[lower].origin, globals[rig.names.find("LeftHand")].origin]
	var verts := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in 3:
		for side in [-0.02, 0.02]:
			verts.append(points[i] + Vector3(0, 0, side))
			bones.append_array([upper, lower, 0, 0])
			weights.append_array([[1.0, 0.0], [0.5, 0.5], [0.0, 1.0]][i] + [0.0, 0.0])
	var strip := { "verts": verts, "bones": bones, "weights": weights, "indices": PackedInt32Array([0, 1, 2, 1, 3, 2, 2, 3, 4, 3, 5, 4]) }
	var kept: Animation = base.clips.work_1
	var pulled: Animation = kept.duplicate()
	var track := pulled.add_track(Animation.TYPE_POSITION_3D)
	pulled.track_set_path(track, NodePath("Skeleton3D:LeftLowerArm"))
	pulled.track_insert_key(track, 0.0, rig.rests[lower].origin * 3.0)
	var with_reach := { "rig": rig, "clips": { "work_1": pulled }, "yard": base.yard, "reach": { "work_1": [[0.8, pulled], [0.6, kept]] } }
	var clips := StudioCharacter._clips(with_reach, rig, globals, globals, 2.0, [])
	var shape := StudioTearing.body(rig, [strip])
	check(StudioTearing.worst(rig, shape, clips.work_1) >= StudioTearing.TORN, "a forearm pulled from the elbow did not tear the strip, so easing went untested")
	var notes := StudioCharacter._ease(clips, with_reach, rig, globals, globals, 2.0, [strip])
	check(StudioTearing.worst(rig, shape, clips.work_1) < StudioTearing.TORN and notes == ["Its arms reach 60% as far in its work_1 clip, so its mesh doesn't stretch."],
		"a clip that tore the piece was not played at the least reach that doesn't: %s" % [notes])

func _planted_frames(model: Dictionary, side: String) -> int:
	var walk: Animation = model.clips.walk
	var foot: int = model.rig.names.find(side + "Foot")
	var heights := []
	for k in int(round(walk.length * StudioFeet.FPS)):
		heights.append(StudioRig.globals(model.rig, StudioRig.pose(model.rig, walk, k / StudioFeet.FPS))[foot].origin.y)
	var low: float = heights.min()
	return heights.filter(func(y): return y <= low + StudioFeet.PLANTED * float(model.yard.height)).size()

## Loaded back as the game loads it, the mesh moves as its source's own
## weights move it: each vertex goes where its source bones' contract bones
## carry it. Vertices keep their order through Studio and the glTF writer.
func _moves_with_source(written: Node, mine: Dictionary, source: Dictionary, piece: Dictionary) -> void:
	var mi: MeshInstance3D = written.find_children("*", "MeshInstance3D", true, false).front()
	var own := { "parents": mine.rig.parents, "base": Transform3D() }
	var rest := _skinned(written, mi, StudioRig.globals(own, mine.rig.rests))
	var bones := StudioBones.guess(source.rig)
	var contract := PackedInt32Array()
	for i in source.rig.names.size():
		var at: int = i
		while at >= 0 and not at in bones.map.values():
			at = source.rig.parents[at]
		contract.append(mine.rig.names.find(bones.map.find_key(at)) if at >= 0 else mine.rig.names.find("Hips"))
	var order: bool = rest.size() == source.surfaces.size()
	var still := 0.0
	for s in mini(rest.size(), source.surfaces.size()):
		var verts: PackedVector3Array = rest[s]
		order = order and verts.size() == source.surfaces[s].verts.size()
		for v in mini(verts.size(), piece.surfaces[s].verts.size()):
			still = maxf(still, verts[v].distance_to(piece.surfaces[s].verts[v]))
	check(order and still < NEAR, "loaded back at rest, the piece is not the shape Studio made (%.4f m, in order: %s)" % [still, order])
	var rest_globals := StudioRig.rest_globals(mine.rig)
	var worst := 0.0
	var worst_at := ""
	for shot in [["walk", 0.33], ["work_0", 0.75], ["done", 1.0], ["idle_2", 1.25]]:
		var locals := StudioRig.pose(mine.rig, mine.clips[shot[0]], shot[1])
		var posed := _skinned(written, mi, StudioRig.globals(own, locals))
		var globals := StudioRig.globals(mine.rig, locals)
		for s in mini(posed.size(), source.surfaces.size()):
			var verts: PackedVector3Array = posed[s]
			var still_verts: PackedVector3Array = rest[s]
			var src: Dictionary = source.surfaces[s]
			for v in mini(verts.size(), src.verts.size()):
				var want := Vector3.ZERO
				var total := 0.0
				for k in src.per:
					var w: float = src.weights[v * src.per + k]
					if w > 0.0 and src.bones[v * src.per + k] >= 0:
						var c := contract[src.bones[v * src.per + k]]
						want += (globals[c] * rest_globals[c].affine_inverse() * still_verts[v]) * w
						total += w
				var off := verts[v].distance_to(want / total)
				if off > worst:
					worst = off
					worst_at = "%s at %.2f s, near %s" % [shot[0], shot[1], mine.rig.names[contract[src.bones[v * src.per]]]]
	check(worst < NEAR, "posed, a vertex was %.4f m from where its source's weights carry it (%s)" % [worst, worst_at])

## Where Godot's skinning puts a mesh's vertices in its model, for bones
## posed at `poses` (the skeleton's own space), from the mesh's own skin.
## Godot's bake of this needs a renderer, which headless runs don't have.
func _skinned(model: Node, mi: MeshInstance3D, poses: Array[Transform3D]) -> Array:
	var skeleton: Skeleton3D = mi.get_node(mi.skeleton)
	var place := StudioRig.placement(mi, model)
	var matrices := []
	for b in mi.skin.get_bind_count():
		var bone := mi.skin.get_bind_bone(b)
		matrices.append(poses[bone if bone >= 0 else skeleton.find_bone(mi.skin.get_bind_name(b))] * mi.skin.get_bind_pose(b))
	var out := []
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		var moved := PackedVector3Array()
		for v in verts.size():
			var at := Vector3.ZERO
			for k in per:
				at += (matrices[bones[v * per + k]] * verts[v]) * weights[v * per + k]
			moved.append(place * at)
		out.append(moved)
	return out

## At rest each hand stands clear of the rest of the body beside it.
func _hands_clear(written: Node, mine: Dictionary) -> void:
	var mi: MeshInstance3D = written.find_children("*", "MeshInstance3D", true, false).front()
	var own := { "parents": mine.rig.parents, "base": Transform3D() }
	var rest := _skinned(written, mi, StudioRig.globals(own, mine.rig.rests))
	var g := StudioRig.rest_globals(mine.rig)
	var tall: float = mine.yard.height
	for side in ["Left", "Right"]:
		var arm := ["Shoulder", "UpperArm", "LowerArm", "Hand", "Prop"].map(func(n): return mine.rig.names.find(n + side if n == "Prop" else side + n))
		var hand: Vector3 = g[mine.rig.names.find(side + "Hand")].origin
		var outward := 1.0 if side == "Left" else -1.0
		var reach := -INF
		for s in rest.size():
			var arrays := mi.mesh.surface_get_arrays(s)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per: int = bones.size() / rest[s].size()
			for v in rest[s].size():
				var strongest := 0
				for k in per:
					if weights[v * per + k] > weights[v * per + strongest]:
						strongest = k
				var p: Vector3 = rest[s][v]
				if not _bind_bone(mi, bones[v * per + strongest]) in arm \
						and absf(p.y - hand.y) < .06 * tall and absf(p.z - hand.z) < .08 * tall:
					reach = maxf(reach, outward * p.x)
		check(reach == -INF or outward * hand.x - reach >= StudioCharacter.CLEARANCE * tall - 1e-3,
			"the %s hand is %.3f m from the body beside it" % [side.to_lower(), outward * hand.x - reach])

## The skeleton bone a skin's bind moves, by number or by name.
func _bind_bone(mi: MeshInstance3D, bind: int) -> int:
	var bone := mi.skin.get_bind_bone(bind)
	return bone if bone >= 0 else (mi.get_node(mi.skeleton) as Skeleton3D).find_bone(mi.skin.get_bind_name(bind))

## The extras: the default's stride and cycle, its height, and the station
## surface moved with the shoulders.
func _yard(yard: Dictionary, theirs: Dictionary, mine: Dictionary) -> void:
	var a := StudioRig.rest_globals(mine.rig)
	var b := StudioRig.rest_globals(theirs.rig)
	var shoulders := func(g: Array, rig: Dictionary) -> float: return g[rig.names.find("LeftUpperArm")].origin.y + g[rig.names.find("RightUpperArm")].origin.y
	var surface: float = theirs.yard.surface * shoulders.call(a, mine.rig) / shoulders.call(b, theirs.rig)
	check(is_equal_approx(float(yard.stride), float(theirs.yard.stride)) and is_equal_approx(float(yard.cycle), float(theirs.yard.cycle)),
		"the piece's stride and cycle are not the default's: %s" % yard)
	check(absf(float(yard.height) - float(theirs.yard.height)) < 1e-3 and absf(float(yard.surface) - surface) < 1e-3,
		"the piece's height or surface is off: %s (surface %.4f)" % [yard, surface])

## Each common rig's names map every bone a character needs, and say whose.
func _names() -> void:
	var rig: Dictionary = _read("studio_mixamo").rig
	var plain: PackedStringArray = rig.names.duplicate()
	for i in plain.size():
		plain[i] = plain[i].trim_prefix("mixamorig_")
	var spine := ["Spine", "Spine1", "Spine2"]
	var rigs := {
		"Unreal": ["pelvis", ["spine_01", "spine_02", "spine_03"], "neck_01", "head", "clavicle_*", "upperarm_*", "lowerarm_*", "hand_*", "thigh_*", "calf_*", "foot_*", "ball_*", ["l", "r"]],
		"Character Creator": ["CC_Base_Hip", ["CC_Base_Waist", "CC_Base_Spine01", "CC_Base_Spine02"], "CC_Base_NeckTwist01", "CC_Base_Head",
			"CC_Base_*_Clavicle", "CC_Base_*_Upperarm", "CC_Base_*_Forearm", "CC_Base_*_Hand", "CC_Base_*_Thigh", "CC_Base_*_Calf", "CC_Base_*_Foot", "CC_Base_*_ToeBase", ["L", "R"]],
		"Rigify": ["DEF-spine", ["DEF-spine.001", "DEF-spine.002", "DEF-spine.003"], "DEF-spine.004", "DEF-spine.006", "DEF-shoulder.*", "DEF-upper_arm.*",
			"DEF-forearm.*", "DEF-hand.*", "DEF-thigh.*", "DEF-shin.*", "DEF-foot.*", "DEF-toe.*", ["L", "R"]],
		"Tripo": ["hips", ["spine", "spine1", "chest"], "neck", "head", "shoulder.*", "upperarm.*", "forearm.*", "hand.*", "thigh.*", "shin.*", "foot.*", "toe.*", ["L", "R"]],
		"Godot humanoid": ["Hips", ["Spine", "Chest", "UpperChest"], "Neck", "Head", "*Shoulder", "*UpperArm", "*LowerArm", "*Hand", "*UpperLeg", "*LowerLeg", "*Foot", "*Toes", ["Left", "Right"]],
	}
	var limbs := ["Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "ToeBase"]
	for name in rigs:
		var t: Array = rigs[name]
		var renamed := { "Hips": t[0], "Neck": t[2], "Head": t[3] }
		for k in 3:
			renamed[spine[k]] = t[1][k]
		for s in 2:
			for k in limbs.size():
				renamed[["Left", "Right"][s] + limbs[k]] = String(t[4 + k]).replace("*", t[12][s])
		var named := rig.duplicate()
		named.names = PackedStringArray(Array(plain).map(func(n): return renamed.get(n, n)))
		var bones := StudioBones.guess(named)
		var wrong := []
		for bone in StudioBones.NEEDED + StudioBones.OPTIONAL:
			var mixamo: String = bone
			for side in ["Left", "Right"]:
				for k in limbs.size():
					if bone == side + ["Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toes"][k]:
						mixamo = side + limbs[k]
			if bones.map.get(bone, -1) != plain.find(mixamo):
				wrong.append(bone)
		check(bones.rig == name and wrong.is_empty() and bones.unsure.is_empty(),
			"%s names were read as %s: wrong %s, unsure %s" % [name, bones.rig, wrong, bones.unsure])

## The other rigs: a VRM by its own map, with too many textures; a rig
## without shoulders or toes; one whose names mean
## nothing (read from its shape, every bone unsure until accepted); too many
## faces; and a beard on the head bone that isn't skinned.
func _rigs(tree: SceneTree, default: Node, lengths: Dictionary) -> void:
	var vrm := Studio.make(_copy("studio_vrm"), default)
	check(vrm.has("rig"), "the VRM fixture was not made into a piece: %s" % [vrm.get("reason", vrm.get("unsure", ""))])
	if vrm.has("rig"):
		var images := []
		for s in vrm.surfaces:
			if s.look.image and not s.look.image in images:
				images.append(s.look.image)
		check(images.size() <= StudioLimits.IMAGES, "the VRM's 10 textures were not combined: %d" % images.size())
		_nothing_left_out(vrm)
		_colours_kept(_copy("studio_vrm"), vrm)
		check(await _passes(tree, vrm, "vrm", lengths) == "", "the VRM piece did not pass the game's check")
	var fbx := _copy("studio_fbx", "fbx")
	check("FBX" in StudioSource.open(fbx).get("reason", "") and "FBX" in Studio.make(fbx, default).get("reason", ""), "an FBX was not refused")
	var tripo := Studio.make(_copy("studio_tripo"), default)
	check(tripo.has("rig") and tripo.notes.filter(func(n): return "Studio made one" in n).size() == 4,
		"a rig without shoulders or toes did not get them made: %s" % [tripo.get("notes", tripo.get("unsure", tripo.get("reason", "")))])
	if tripo.has("rig"):
		check(await _passes(tree, tripo, "tripo", lengths) == "", "the piece without shoulders or toes did not pass the game's check")
	var mirrored := Studio.make(_copy("studio_mirrored"), default)
	check("swapped" in str(mirrored.get("unsure", {}).get("LeftUpperLeg", "")), "a rig naming its sides the other way round, without toes, was not left to the player")
	var swapped := Studio.make(_copy("studio_mirrored"), default, { "map": "swap" })
	var faces_front: bool = swapped.has("surfaces") and StudioRig.rest_globals(swapped.rig)[swapped.rig.names.find("LeftUpperLeg")].origin.x > 0.0
	check(faces_front and await _passes(tree, swapped, "mirrored", lengths) == "", "swapping its sides did not make a piece that faces +Z")
	var shaped := Studio.make(_copy("studio_shape"), default)
	var names: Dictionary = StudioBones.guess(_read("studio_mixamo").rig).map
	var guessed: Dictionary = shaped.get("map", {})
	var same := names.keys().all(func(k): return guessed.get(k, -2) == names[k])
	var shape_read := names.keys().filter(func(k): return not k in StudioBones.SPINE)
	check(same and shape_read.all(func(k): return shaped.get("unsure", {}).get(k, "") == StudioBones.GUESSED),
		"a rig read from its shape was not mapped right with every bone unsure: %s" % [shaped.get("unsure", shaped.keys())])
	check(Studio.make(_copy("studio_shape"), default, { "map": "accept" }).has("rig"), "accepting the bones read from the shape did not make a piece")
	check(Studio.make(_copy("studio_shape"), default, { "map": "LeftHand=bone12" }).get("unsure", {}).size() == shape_read.size() - 1,
		"naming one bone accepted the others read from the shape")
	var dense := Studio.make(_copy("studio_dense"), default, { "limits": { "faces": 2000, "texture": 4096 } })
	var faces := 0
	for s in dense.get("surfaces", []):
		faces += s.indices.size() / 3
	check(dense.has("rig") and faces > 0 and faces <= 2000, "a piece with too many faces was not reduced: %d faces" % faces)
	var loose := Studio.make(_copy("studio_loose"), default)
	var beard: Array = loose.get("surfaces", []).filter(func(s): return s.look.image == null and not s.look.color.is_equal_approx(Color.WHITE))
	var head: int = loose.rig.names.find("Head") if loose.has("rig") else -1
	var on_head: bool = not beard.is_empty()
	for s in beard:
		for v in s.verts.size():
			on_head = on_head and s.bones[v * 4] == head and is_equal_approx(s.weights[v * 4], 1.0)
	check(on_head, "a beard on the head bone that isn't skinned did not move with the head")

## No part of the piece stays out in the source's T-pose: a sleeve a VRM
## aims at the forearm turns down with the arm.
func _nothing_left_out(piece: Dictionary) -> void:
	var g := StudioRig.rest_globals(piece.rig)
	var reach := 0.0
	for side in ["LeftHand", "RightHand"]:
		reach = maxf(reach, absf(g[piece.rig.names.find(side)].origin.x))
	var widest := 0.0
	for s in piece.surfaces:
		for v in s.verts:
			widest = maxf(widest, absf(v.x))
	check(widest < reach + 0.1 * float(piece.yard.height), "part of the piece stays out %.2f m, past its hands at %.2f m" % [widest, reach])

## Each part keeps its colour when its texture is combined with the others:
## as many triangles show each colour as did before.
func _colours_kept(path: String, piece: Dictionary) -> void:
	var state := GLTFState.new()
	GLTFDocument.new().append_from_file(path, state)
	var wanted := {}
	for mesh: GLTFMesh in state.get_meshes():
		for k in mesh.mesh.get_surface_count():
			var image: Image = (mesh.mesh.get_surface_material(k) as BaseMaterial3D).albedo_texture.get_image()
			var colour := image.get_pixel(image.get_width() / 2, image.get_height() / 2).to_html(false)
			wanted[colour] = wanted.get(colour, 0) + mesh.mesh.get_surface_arrays(k)[Mesh.ARRAY_INDEX].size() / 3
	var got := {}
	for s in piece.surfaces:
		if s.look.image == null:
			continue
		var size := Vector2(s.look.image.get_size())
		for t in range(0, s.indices.size(), 3):
			var uv: Vector2 = (s.uvs[s.indices[t]] + s.uvs[s.indices[t + 1]] + s.uvs[s.indices[t + 2]]) / 3.0
			var colour: String = s.look.image.get_pixelv(Vector2i(uv * size).clamp(Vector2i.ZERO, Vector2i(size) - Vector2i.ONE)).to_html(false)
			got[colour] = got.get(colour, 0) + 1
	check(got == wanted, "the parts' colours changed when their textures were combined: %s, not %s" % [got, wanted])

## The game's check of a piece, written to its own folder.
func _passes(tree: SceneTree, piece: Dictionary, name: String, lengths: Dictionary) -> String:
	var folder := ProjectSettings.globalize_path(OUT.path_join(name))
	var root := StudioExport.scene(piece, "character")
	var reason := StudioExport.save([root], folder, { "format": 1, "kind": "character", "world": "guild", "crew": "anthropic", "title": name })
	root.free()
	if reason != "":
		return reason
	var validator := PieceValidator.new()
	tree.root.add_child(validator)
	var verdict: Dictionary = await validator.check(folder.path_join("character.glb"), "character", lengths)
	validator.free()
	return verdict.reason

## A fixture read as Studio reads it.
func _read(name: String) -> Dictionary:
	var model: Node = StudioSource.open(_copy(name)).model
	var source := StudioSource.read(model)
	model.free()
	return source

## No legs is refused in words; swapped sides and unknown names are left for
## the player, and their choices settle them.
func _unsure() -> void:
	var default: Node = StudioSource.open(_copy("studio_default")).model
	var legless := Studio.make(_copy("studio_no_legs"), default)
	check("legs" in String(legless.get("reason", "")), "a model with no legs was not refused in words: %s" % legless)
	var swapped := Studio.make(_copy("studio_swapped"), default)
	check("swapped" in str(swapped.get("unsure", {}).get("LeftUpperLeg", "")), "swapped sides were not left to the player: %s" % [swapped.keys()])
	var unknown := Studio.make(_copy("studio_unknown"), default)
	check(unknown.get("unsure", {}).has("LeftLowerArm") and unknown.get("unsure", {}).has("RightLowerArm"),
		"bones with unknown names were not left to the player: %s" % [unknown.get("unsure", {})])
	var chosen := Studio.make(_copy("studio_unknown"), default, { "map": "LeftLowerArm=elbow.L,RightLowerArm=elbow.R" })
	check(chosen.has("rig"), "the player's choices did not settle the unknown bones: %s" % [chosen.get("unsure", chosen.get("reason", ""))])
	default.free()

func _sources(tree: SceneTree) -> void:
	var root := ProjectSettings.globalize_path(OUT.path_join("sources"))
	var folder := root.path_join("up/model")
	var staging := ProjectSettings.globalize_path(StudioSource.STAGED)
	StudioFiles.remove_tree(staging)
	var png := Image.create(4, 4, false, Image.FORMAT_RGB8).save_png_to_buffer()
	var tri := PackedFloat32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]).to_byte_array()
	_put(folder.path_join("tri.bin"), tri)
	for at in ["up/model/textures/skin.png", "up/model/secret.png", "up/above.png"]:
		_put(root.path_join(at), png)
	_put(folder.path_join("wide.png"), Image.create(PieceCheck.SOURCE.texture + 1, 1, false, Image.FORMAT_RGB8).save_png_to_buffer())
	# Files Godot's own loader takes for a texture, wherever a model names one.
	for at in ["up/model/sib.tres", "up/above.tres", "elsewhere.tres"]:
		ResourceSaver.save(ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8)), root.path_join(at))
	check(ResourceLoader.load(root.path_join("elsewhere.tres"), "Texture2D") is Texture2D, "the test's .tres is not one Godot loads as a texture")
	var refused := {
		"../above.tres": "own folder", "../above.png": "own folder", "./../above.png": "own folder", "%2E%2E/above.png": "own folder", "textures\\skin.png": "own folder",
		root.path_join("elsewhere.tres"): "own folder", "sib.tres": "Studio reads", "missing.png": "not beside", "wide.png": str(PieceCheck.SOURCE.texture + 1),
	}
	var here := DirAccess.open(folder)
	if here.create_link(root.path_join("up/above.png"), "link.png") == OK:
		refused["link.png"] = "a link"
	if here.create_link(root.path_join("up"), "linked") == OK:
		refused["linked/above.png"] = "a link"
	for uri in refused:
		var reason: String = PieceCheck.check_source(_gltf(folder, "bad.gltf", [uri], "tri.bin")).reason
		check(refused[uri] in reason, "a model naming the image %s was not refused for it: \"%s\"" % [uri, reason])
	for uri in ["../model/tri.bin", "secret.png"]:
		check(PieceCheck.check_source(_gltf(folder, "bad.gltf", ["textures/skin.png"], uri)).reason != "", "a model naming the buffer %s was not refused" % uri)
	var many := []
	for i in PieceCheck.SOURCE.files + 1:
		_put(folder.path_join("p%d.png" % i), png)
		many.append("p%d.png" % i)
	check("more than" in PieceCheck.check_source(_gltf(folder, "bad.gltf", many, "tri.bin")).reason, "a model naming %d files was not refused" % (many.size() + 1))

	var validator := PieceValidator.new()
	tree.root.add_child(validator)
	var inside := "data:application/octet-stream;base64," + Marshalls.raw_to_base64(tri)
	for model in [_gltf(folder, "tri.gltf", ["textures/skin.png"], "tri.bin"), _gltf(folder, "whole.gltf", ["data:image/png;base64," + Marshalls.raw_to_base64(png)], inside)]:
		var named: bool = model.get_file() == "tri.gltf"
		var staged: Dictionary = await StudioSource.stage(validator, [model])
		check(staged.has("paths"), "%s was refused: %s" % [model.get_file(), staged.get("reason", "")])
		if not staged.has("paths"):
			continue
		check(_files(staged.dir) == (["0/textures/skin.png", "0/tri.bin", "0/tri.gltf"] if named else ["0/whole.gltf"]),
			"%s was not staged with just the files it names: %s" % [model.get_file(), _files(staged.dir)])
		check(staged.notes.size() == (1 if named else 0) and (not named or ("tri.bin" in staged.notes[0] and "textures/skin.png" in staged.notes[0])),
			"the files read beside %s were not said: %s" % [model.get_file(), staged.notes])
		var opened: Dictionary = StudioSource.open(staged.paths[0])
		var meshes: Array = opened.model.find_children("*", "MeshInstance3D", true, false) if opened.has("model") else []
		check(meshes.size() == 1 and meshes[0].mesh.surface_get_material(0).albedo_texture != null, "the staged %s did not open with its texture" % model.get_file())
		if opened.has("model"):
			opened.model.free()
		StudioFiles.remove_tree(staged.dir)
	var dotted: Dictionary = await StudioSource.stage(validator, [_gltf(folder, "dotted.gltf", ["./textures/skin.png"], "./tri.bin")])
	check(dotted.has("paths"), "a model naming ./ files beside it was refused: %s" % dotted.get("reason", ""))
	if dotted.has("dir"):
		var beside: Node = StudioSource.open(_copy("studio_helper")).model
		var made := Studio.make_companions(dotted.paths, beside)
		beside.free()
		check(_files(dotted.dir) == ["0/dotted.gltf", "0/textures/skin.png", "0/tri.bin"] and made.get("pieces", []).size() == 4,
			"a model naming ./ files beside it was not staged with them and made into four companions: %s, %s" % [_files(dotted.dir), made.get("reason", "")])
		StudioFiles.remove_tree(dotted.dir)
	var moving: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_gltf(folder, "moving.gltf", ["textures/skin.png"], "tri.bin")))
	_put(folder.path_join("clip.bin"), PackedFloat32Array([0, 1, 1, 1, 1, 1, 1, 0, 0, 1]).to_byte_array())
	moving.buffers.append({ "uri": "clip.bin", "byteLength": 40 })
	moving.bufferViews += [{ "buffer": 1, "byteLength": 8 }, { "buffer": 1, "byteOffset": 8, "byteLength": 32 }]
	moving.accessors += [{ "bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1] }, { "bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC4" }]
	moving.extensionsUsed = ["KHR_animation_pointer"]
	moving.animations = [{ "samplers": [{ "input": 1, "output": 2 }], "channels": [{ "sampler": 0,
		"target": { "path": "pointer", "extensions": { "KHR_animation_pointer": { "pointer": "/materials/0/pbrMetallicRoughness/baseColorFactor" } } } }] }]
	_put(folder.path_join("moving.gltf"), JSON.stringify(moving).to_utf8_buffer())
	var pointed: Dictionary = await StudioSource.stage(validator, [folder.path_join("moving.gltf")])
	check(pointed.has("paths"), "a model whose clip changes a material, not a node, was refused: %s" % pointed.get("reason", ""))
	if pointed.has("dir"):
		var helper: Node = StudioSource.open(_copy("studio_helper")).model
		var four := Studio.make_companions(pointed.paths, helper)
		helper.free()
		check(four.get("pieces", []).size() == 4, "a model whose clip changes a material was not made into four companions: %s" % four.get("reason", ""))
		StudioFiles.remove_tree(pointed.dir)
	for target in [{ "path": "translation" }, { "node": 7, "path": "translation" }, { "path": "pointer" }]:
		moving.animations[0].channels[0].target = target
		_put(folder.path_join("moving.gltf"), JSON.stringify(moving).to_utf8_buffer())
		check("a clip moves a node" in PieceCheck.check_source(folder.path_join("moving.gltf")).reason, "a clip moving no node, or one that isn't there, was not refused: %s" % target)
	var outside: Dictionary = await StudioSource.stage(validator, [_gltf(folder, "bad.gltf", ["../above.tres"], "tri.bin")])
	check("own folder" in outside.get("reason", ""), "the checker's process did not refuse a model naming a file above it: %s" % outside)
	var unread: Dictionary = await StudioSource.stage(validator, [_copy("studio_fbx", "fbx")])
	check("FBX" in unread.get("reason", ""), "an FBX was not refused before it was staged: %s" % unread)
	var crashed: Dictionary = await validator.check_source(_gltf(folder, "tri.gltf", ["textures/skin.png"], "tri.bin"), staging.path_join("crash"), "crash")
	check(crashed.reason == "it crashed the checker", "a crash while a model was checked was not reported: %s" % crashed.reason)
	check(_files(staging) == [], "refused models left files staged: %s" % [_files(staging)])
	validator.free()

func _gltf(folder: String, name: String, images: Array, buffer: String) -> String:
	var gltf := { "asset": { "version": "2.0" }, "scene": 0, "scenes": [{ "nodes": [0] }], "nodes": [{ "mesh": 0 }],
		"meshes": [{ "primitives": [{ "attributes": { "POSITION": 0 }, "material": 0 }] }],
		"materials": [{ "pbrMetallicRoughness": { "baseColorTexture": { "index": 0 } } }],
		"textures": images.map(func(_uri): return { "source": 0 }), "images": images.map(func(uri): return { "uri": uri }),
		"buffers": [{ "uri": buffer, "byteLength": 36 }], "bufferViews": [{ "buffer": 0, "byteLength": 36 }],
		"accessors": [{ "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0] }] }
	_put(folder.path_join(name), JSON.stringify(gltf).to_utf8_buffer())
	return folder.path_join(name)

func _put(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)

func _files(dir: String, under := "") -> Array:
	var out := []
	for sub in DirAccess.get_directories_at(dir.path_join(under)):
		out += _files(dir, under.path_join(sub))
	for file in DirAccess.get_files_at(dir.path_join(under)):
		out.append(under.path_join(file))
	out.sort()
	return out

func _copy(name: String, extension := "glb") -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var path := ProjectSettings.globalize_path(OUT.path_join(name + "." + extension))
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
