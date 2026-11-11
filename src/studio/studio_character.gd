class_name StudioCharacter
## Turns a humanoid into a character for one slot. The model is stood up,
## faced and sized, and its limbs are turned to point the way the slot
## default's rest bones point. The contract skeleton is then built at the
## model's joints with the default's own rest rotations, so the default's
## clips play on it as they are: rotations copied, the hips' travel scaled.
## Everything here is plain data, so it runs on any thread.

const SIDES := ["Left", "Right"]
## The limb bones turned to the default's rest, in order down each limb.
const LIMB := ["Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toes"]
## Where Spine, Chest and UpperChest stand between hips and neck when the
## model has no bone for them (rig.py's shares).
const SPINE_SHARES := { "Spine": .23, "Chest": .47, "UpperChest": .70 }
## Room a hand needs beside the body, as a share of the height: about half
## a hand's width.
const CLEARANCE := .035
## The most an arm swings out to clear the body, in degrees.
const SWING := 30

## The slot default as plain data: { rig, clips: {name: Animation}, yard }.
static func default_of(model: Node) -> Dictionary:
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false).front()
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false).front()
	var clips := {}
	for clip in PieceCheck.CLIPS.character:
		if player.has_animation(clip):
			clips[clip] = player.get_animation(clip)
	return { "rig": StudioRig.of(skeleton, model), "clips": clips, "yard": YardRig.extras(model) }

## The piece as plain data: { rig, surfaces, clips, yard, notes }. `height`
## is the piece's height in metres (else the default's); `notes` says, in
## words, what Studio changed to fit it.
static func fit(source: Dictionary, map: Dictionary, default: Dictionary, height := 0.0) -> Dictionary:
	var src: Dictionary = source.rig
	var rest := StudioRig.rest_globals(src)
	var def_rig: Dictionary = default.rig
	var def_rest := StudioRig.rest_globals(def_rig)
	var tall := height if height > 0.0 else float(default.yard.get("height", 2.0))
	var frame := frame_of(source, map, rest, tall)
	var turned := turn_limbs(src, map, frame, func(side: String, limb: String) -> Vector3:
		return def_rest[def_rig.names.find(side + limb)].basis.orthonormalized().y)
	var moved: Array[Transform3D] = turned.moved
	var at: PackedVector3Array = turned.at
	var fold := _fold(src, map, def_rig)
	var notes := []
	var swung := _clear_hands(source, map, moved, at, fold, def_rig, tall)
	for side in swung:
		notes.append("Its %s arm hangs %d° further out than the character it replaces, so the hand clears the body." % [side.to_lower(), swung[side]])
	for side in SIDES:
		for limb in ["Shoulder", "Toes"]:
			if not map.has(side + limb):
				notes.append("It had no %s %s bone; Studio made one." % [side.to_lower(), limb.to_lower()])
	var rig := _skeleton(map, at, def_rig, def_rest, tall)
	var surfaces := []
	for s in source.surfaces:
		surfaces.append(_surface(s, moved, fold, rig.names.find("Hips")))
	var globals := StudioRig.rest_globals(rig)
	var stepped := []
	var clips := _clips(default, rig, globals, def_rest, tall, stepped)
	notes += _ease(clips, default, rig, globals, def_rest, tall, surfaces)
	if not stepped.is_empty():
		notes.append("The character it replaces glides rather than steps; this piece takes steps of its own, at the same speed.")
	var speed := walking_speed(default.yard)
	for clip in clips:
		var slid := StudioFeet.slide(rig, clips[clip], speed if clip == "walk" else 0.0, tall)
		if slid > StudioFeet.SLIDE * tall:
			notes.append("Its feet slide %d cm in its %s clip." % [roundi(slid * 100.0), clip])
	return { "rig": rig, "surfaces": surfaces, "clips": clips,
		"yard": _yard(default.yard, globals, def_rig, def_rest, rig, tall), "notes": notes }

## How fast the game walks a piece: its slot default's stride / cycle, the
## piece's own being ignored (YardView.movement).
static func walking_speed(yard: Dictionary) -> float:
	return float(yard.get("stride", 0.0)) / float(yard.cycle) if float(yard.get("cycle", 0.0)) > 0.0 else 1.0

## Hands hang the way the default's do, but a body slimmer or wider than the
## default's can leave them inside its hips or thighs. Each such arm swings
## out from the shoulder by as little as clears the hand; the default's
## motion then plays on it unchanged. Degrees swung, by side.
static func _clear_hands(source: Dictionary, map: Dictionary, moved: Array[Transform3D], at: PackedVector3Array, fold: PackedInt32Array, def_rig: Dictionary, tall: float) -> Dictionary:
	var out := {}
	for side in SIDES:
		var hand: int = map.get(side + "Hand", -1)
		var upper: int = map.get(side + "UpperArm", -1)
		if hand < 0 or upper < 0:
			continue
		var arm := ["Shoulder", "UpperArm", "LowerArm", "Hand"].map(func(n): return def_rig.names.find(side + n))
		var outward := 1.0 if side == "Left" else -1.0
		var body := PackedVector3Array()
		for s in source.surfaces:
			for v in s.verts.size():
				var strongest := -1
				var most := 0.0
				for k in s.per:
					if s.weights[v * s.per + k] > most and s.bones[v * s.per + k] >= 0:
						most = s.weights[v * s.per + k]
						strongest = s.bones[v * s.per + k]
				if strongest >= 0 and not fold[strongest] in arm:
					var p: Vector3 = moved[strongest] * s.verts[v]
					if absf(p.y - at[hand].y) < .15 * tall:
						body.append(p)
		var swing := 0
		while swing < SWING:
			var reach := -INF
			for p in body:
				if absf(p.y - at[hand].y) < .06 * tall and absf(p.z - at[hand].z) < .08 * tall:
					reach = maxf(reach, outward * p.x)
			if reach == -INF or outward * at[hand].x >= reach + CLEARANCE * tall:
				break
			var turn := Basis(Vector3.BACK, outward * deg_to_rad(1.0))
			var about := Transform3D(turn, at[upper] - turn * at[upper])
			for d in StudioRig.subtree(source.rig, upper):
				moved[d] = about * moved[d]
				at[d] = about * at[d]
			swing += 1
		if swing > 0:
			out[side] = swing
	return out

## Each model bone's place in the piece ({ moved }: model to piece, by bone)
## and each joint's position ({ at }), once `frame` has stood it up and each
## limb bone found is turned to point the way `want(side, limb)` says (a
## zero vector leaves it). Limbs are turned down each limb in order, each
## turn carrying what hangs from it.
static func turn_limbs(src: Dictionary, map: Dictionary, frame: Transform3D, want: Callable) -> Dictionary:
	var rest := StudioRig.rest_globals(src)
	var moved: Array[Transform3D] = []
	var at := PackedVector3Array()
	for i in src.names.size():
		moved.append(frame)
		at.append(frame * rest[i].origin)
	for side in SIDES:
		for limb in LIMB:
			var bone: int = map.get(side + limb, -1)
			var tip = _tip(src, map, side, limb, at)
			var to: Vector3 = want.call(side, limb)
			if bone < 0 or tip == null or (tip - at[bone]).length() < 1e-5 or to == Vector3.ZERO:
				continue
			var turn := Basis(Quaternion((tip - at[bone]).normalized(), to.normalized()))
			var about := Transform3D(turn, at[bone] - turn * at[bone])
			for d in StudioRig.subtree(src, bone):
				moved[d] = about * moved[d]
				at[d] = about * at[d]
	return { "moved": moved, "at": at }

## Model space to the piece's: up from hips to head, left from the right leg
## to the left (so it faces +Z), feet on the ground, hips over the origin,
## and scaled to `height`.
static func frame_of(source: Dictionary, map: Dictionary, rest: Array[Transform3D], height: float) -> Transform3D:
	var hips: Vector3 = rest[map.Hips].origin
	var up: Vector3 = (rest[map.Head].origin - hips).normalized()
	var left: Vector3 = rest[map.LeftUpperLeg].origin - rest[map.RightUpperLeg].origin
	left = (left - up * left.dot(up)).normalized()
	var turn := Basis(left, up, left.cross(up)).transposed()
	var low := INF
	var high := -INF
	for s in source.surfaces:
		for v in s.verts:
			var y: float = (turn * v).y
			low = minf(low, y)
			high = maxf(high, y)
	var scale := height / maxf(high - low, 1e-6)
	var centre := turn * hips
	return Transform3D(turn * scale, -Vector3(centre.x, low, centre.z) * scale)

## The point a limb bone points at: the next mapped bone down the limb, or
## for hands and toes, their own children (a hand's middle finger first).
static func _tip(src: Dictionary, map: Dictionary, side: String, limb: String, at: PackedVector3Array) -> Variant:
	var next := LIMB.find(limb) + 1
	if limb != "Hand" and limb != "Toes" and next < LIMB.size() and LIMB[next] != "UpperLeg":
		var child: int = map.get(side + LIMB[next], -1)
		return at[child] if child >= 0 else null
	var bone: int = map.get(side + limb, -1)
	var children := []
	for i in src.parents.size():
		if src.parents[i] == bone:
			if limb == "Hand" and "middle" in src.names[i].to_lower():
				return at[i]
			children.append(at[i])
	if children.is_empty():
		return null
	var sum := Vector3.ZERO
	for c in children:
		sum += c
	return sum / children.size()

## The contract skeleton at the model's joints, with the default's rest
## rotations. Bones the model lacks stand between their neighbours.
static func _skeleton(map: Dictionary, at: PackedVector3Array, def_rig: Dictionary, def_rest: Array[Transform3D], tall: float) -> Dictionary:
	var spots := {}
	for name in def_rig.names:
		if map.has(name):
			spots[name] = at[map[name]]
	spots["Root"] = Vector3.ZERO
	for name in SPINE_SHARES:
		if not spots.has(name):
			spots[name] = spots.Hips.lerp(spots.Neck, SPINE_SHARES[name])
	var def_at := func(name: String) -> Vector3: return def_rest[def_rig.names.find(name)].origin
	for side in SIDES:
		spots["Prop" + side] = spots[side + "Hand"]
		# rig.py's clavicle: in from the shoulder, just above it.
		if not spots.has(side + "Shoulder"):
			var arm: Vector3 = spots[side + "UpperArm"]
			spots[side + "Shoulder"] = Vector3(arm.x * .22, arm.y + .01 * tall, arm.z)
		# The default's toes, on a leg as long as this one.
		if not spots.has(side + "Toes"):
			var leg: float = (spots[side + "UpperLeg"].y - spots[side + "Foot"].y) / (def_at.call(side + "UpperLeg").y - def_at.call(side + "Foot").y)
			spots[side + "Toes"] = spots[side + "Foot"] + (def_at.call(side + "Toes") - def_at.call(side + "Foot")) * leg
	var globals: Array[Transform3D] = []
	for i in def_rig.names.size():
		globals.append(Transform3D(def_rest[i].basis.orthonormalized(), spots[def_rig.names[i]]))
	var rests: Array[Transform3D] = []
	for i in def_rig.names.size():
		var parent: int = def_rig.parents[i]
		rests.append(globals[parent].affine_inverse() * globals[i] if parent >= 0 else globals[i])
	return { "names": def_rig.names, "parents": def_rig.parents, "rests": rests, "base": Transform3D() }

## Each model bone's contract bone: its own, or its nearest mapped ancestor's.
## Bones above the hips or beside them go to the hips. `rig` names the
## contract's bones in order.
static func _fold(src: Dictionary, map: Dictionary, rig: Dictionary) -> PackedInt32Array:
	var of := {}
	for name in map:
		of[map[name]] = rig.names.find(name)
	var hips: int = rig.names.find("Hips")
	var by := StudioRig.follows(src)
	var out := PackedInt32Array()
	for i in src.names.size():
		var at: int = i
		while at >= 0 and not of.has(at):
			at = by[at]
		out.append(of[at] if at >= 0 else hips)
	return out

static func _surface(s: Dictionary, moved: Array[Transform3D], fold: PackedInt32Array, hips: int) -> Dictionary:
	var n: int = s.verts.size()
	var per: int = s.per
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	verts.resize(n)
	normals.resize(n if not s.normals.is_empty() else 0)
	bones.resize(n * 4)
	weights.resize(n * 4)
	for v in n:
		var x := Vector3.ZERO
		var y := Vector3.ZERO
		var z := Vector3.ZERO
		var o := Vector3.ZERO
		var total := 0.0
		var sums := {}
		for k in per:
			var bone: int = s.bones[v * per + k]
			var w: float = s.weights[v * per + k]
			if bone < 0 or w <= 0.0:
				continue
			var part := moved[bone]
			x += part.basis.x * w
			y += part.basis.y * w
			z += part.basis.z * w
			o += part.origin * w
			total += w
			sums[fold[bone]] = sums.get(fold[bone], 0.0) + w
		var m := Transform3D(Basis(x / total, y / total, z / total), o / total) if total > 0.0 else moved[0]
		verts[v] = m * s.verts[v]
		if not s.normals.is_empty():
			normals[v] = (m.basis.inverse().transposed() * s.normals[v]).normalized()
		if sums.is_empty():
			sums[hips] = 1.0
		var top: Array = sums.keys()
		top.sort_custom(func(a, b): return sums[a] > sums[b])
		top = top.slice(0, 4)
		var kept := 0.0
		for b in top:
			kept += sums[b]
		for k in 4:
			bones[v * 4 + k] = top[k] if k < top.size() else 0
			weights[v * 4 + k] = sums[top[k]] / kept if k < top.size() else 0.0
	return { "verts": verts, "normals": normals, "uvs": s.uvs, "indices": s.indices, "bones": bones, "weights": weights, "look": s.look }

## The default's clips on the piece: rotation keys as they are (the rests
## match), and the hips' travel scaled by hip height. Keys the import left
## out stay out: the piece plays what the game plays for the default. Then
## the legs are solved so the feet stay planted at the game's walking speed.
static func _clips(default: Dictionary, rig: Dictionary, globals: Array[Transform3D], def_rest: Array[Transform3D], tall: float, stepped: Array) -> Dictionary:
	var def_rig: Dictionary = default.rig
	var hips: int = rig.names.find("Hips")
	var ratio: float = globals[hips].origin.y / def_rest[def_rig.names.find("Hips")].origin.y
	var out := {}
	for clip in default.clips:
		var source: Animation = default.clips[clip]
		var anim := Animation.new()
		anim.length = source.length
		anim.loop_mode = source.loop_mode
		anim.step = source.step
		for track in source.get_track_count():
			var name := String(source.track_get_path(track).get_concatenated_subnames())
			var bone: int = rig.names.find(name)
			var kind := source.track_get_type(track)
			if bone < 0 or not kind in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]:
				continue
			var t := anim.add_track(kind)
			anim.track_set_path(t, NodePath("Skeleton3D:" + name))
			anim.track_set_interpolation_type(t, source.track_get_interpolation_type(track))
			var def_origin: Vector3 = def_rig.rests[bone].origin
			for k in source.track_get_key_count(track):
				var value = source.track_get_key_value(track, k)
				if kind == Animation.TYPE_POSITION_3D:
					value = rig.rests[bone].origin + (value - def_origin) * ratio
				anim.track_insert_key(t, source.track_get_key_time(track, k), value)
		if StudioFeet.pin(anim, rig, source, def_rig, walking_speed(default.yard) if clip == "walk" else 0.0, tall):
			stepped.append(clip)
		out[clip] = anim
	return out

## Clips that tear the piece's mesh (StudioTearing) play as rig.py bakes the
## cast's: at the least smaller arm reach `default` carries that doesn't
## tear it. A clip that tears at every reach plays at the one that tears
## least, and the notes say so.
static func _ease(clips: Dictionary, default: Dictionary, rig: Dictionary, globals: Array[Transform3D], def_rest: Array[Transform3D], tall: float, surfaces: Array) -> Array:
	if not default.has("reach"):
		return []
	var notes := []
	var shape := StudioTearing.body(rig, surfaces)
	for clip in clips.keys():
		var best := [1.0, clips[clip], StudioTearing.worst(rig, shape, clips[clip])]
		if best[2] < StudioTearing.TORN:
			continue
		for less in default.reach.get(clip, []):
			var eased: Animation = _clips({ "rig": default.rig, "clips": { clip: less[1] }, "yard": default.yard }, rig, globals, def_rest, tall, [])[clip]
			var torn := StudioTearing.worst(rig, shape, eased)
			if torn < best[2]:
				best = [less[0], eased, torn]
			if torn < StudioTearing.TORN:
				break
		clips[clip] = best[1]
		if best[2] < StudioTearing.TORN:
			notes.append("Its arms reach %d%% as far in its %s clip, so its mesh doesn't stretch." % [roundi(best[0] * 100.0), clip])
		else:
			notes.append("Its mesh stretches in its %s clip even with its arms reaching less; cleaner skin weights in the model would fix it." % clip)
	return notes

## The yard extras: the piece's height; the default's stride and cycle (the
## game walks every piece at its default's speed); the station surface
## moved with the shoulders, as rig.py places it; the default's glance and
## its blows, moved with the height.
static func _yard(def_yard: Dictionary, globals: Array[Transform3D], def_rig: Dictionary, def_rest: Array[Transform3D], rig: Dictionary, height: float) -> Dictionary:
	var out := { "height": snappedf(height, 1e-4), "stride": def_yard.get("stride", 0.0), "cycle": def_yard.get("cycle", 0.0) }
	if def_yard.has("surface"):
		var mine := 0.0
		var theirs := 0.0
		for side in SIDES:
			mine += globals[rig.names.find(side + "UpperArm")].origin.y
			theirs += def_rest[def_rig.names.find(side + "UpperArm")].origin.y
		out.surface = snappedf(float(def_yard.surface) * mine / theirs, 1e-4)
	var grow := height / float(def_yard.get("height", height))
	out.events = def_yard.get("events", []).map(func(e): return e.merged({ "at": e.at.map(func(c): return snappedf(float(c) * grow, 1e-3)) }, true))
	if def_yard.has("look"):
		out.look = def_yard.look
	return out
