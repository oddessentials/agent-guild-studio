class_name StudioCompanion
## Turns any model into a world's four companions. The model is stood on the
## ground, faced (turned by the player if need be) and sized to the world's
## default helper; the helper's own trunk (hips to head) is built at the same
## shares of the height, with its rest rotations, so its five clips play on
## it as they are, the hips' hop scaled. The model rides the trunk rigidly,
## or softly, its weight blended up the trunk by height; a humanoid's legs
## fold into the hips and its arms into the chest. Four models come from one:
## four tints, or one turned and sized four ways. Plain data, so any thread.

const MOVES := ["rigid", "soft"]
const VARIANTS := ["tint", "turn"]
## The four tints, laid over the source's own colours: as made, warm, cool
## and green.
const TINTS := [Color(1, 1, 1), Color(1.0, 0.82, 0.66), Color(0.72, 0.86, 1.0), Color(0.8, 1.0, 0.74)]
## The four turns and sizes, for one model shown four ways.
const TURNS := [[0.0, 1.0], [12.0, 0.92], [-10.0, 1.06], [6.0, 0.97]]
## Which way a humanoid's arms hang on a companion: down by its sides.
const HANG := { "UpperArm": Vector3(0.2, -1.0, 0.05), "LowerArm": Vector3(0.12, -1.0, 0.15), "Hand": Vector3(0.1, -1.0, 0.15) }
## Where a humanoid's limbs go on the trunk.
const FOLD := { "UpperLeg": "Hips", "LowerLeg": "Hips", "Foot": "Hips", "Toes": "Hips",
	"Shoulder": "Chest", "UpperArm": "Chest", "LowerArm": "Chest", "Hand": "Chest" }

## The world's default helper as plain data: { rig, clips, yard }.
static func default_of(model: Node) -> Dictionary:
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false).front()
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false).front()
	var clips := {}
	for clip in PieceCheck.CLIPS.companion:
		if player.has_animation(clip):
			clips[clip] = player.get_animation(clip)
	return { "rig": StudioRig.of(skeleton, model), "clips": clips, "yard": YardRig.extras(model) }

## One companion as plain data: { rig, surfaces, clips, yard, notes }.
## `source` is StudioSource.read's (a humanoid, with `map`) or read_static's;
## `move` is rigid or soft; `turn` turns the model about its up axis
## (degrees) before it's faced +Z.
static func fit(source: Dictionary, default: Dictionary, options := {}) -> Dictionary:
	var def_rig: Dictionary = default.rig
	var def_rest := StudioRig.rest_globals(def_rig)
	var def_height := float(default.yard.get("height", def_rest[def_rig.names.find("Head")].origin.y / .84))
	var tall := float(options.get("height", def_height))
	var grow := tall / def_height
	var frame := _frame(source, tall, float(options.get("turn", 0.0)))
	# A humanoid's arms come down from a T or A pose to hang at its sides.
	var moved: Array[Transform3D] = []
	if source.has("map"):
		moved = StudioCharacter.turn_limbs(source.rig, source.map, frame, func(side: String, limb: String) -> Vector3:
			var to: Vector3 = HANG.get(limb, Vector3.ZERO)
			return Vector3(to.x * (1.0 if side == "Left" else -1.0), to.y, to.z)).moved
	var rests: Array[Transform3D] = []
	for i in def_rig.names.size():
		var parent: int = def_rig.parents[i]
		var g := Transform3D(def_rest[i].basis.orthonormalized(), def_rest[i].origin * grow)
		var p := Transform3D(def_rest[parent].basis.orthonormalized(), def_rest[parent].origin * grow) if parent >= 0 else Transform3D()
		rests.append(p.affine_inverse() * g)
	var rig := { "names": def_rig.names, "parents": def_rig.parents, "rests": rests, "base": Transform3D() }
	var globals := StudioRig.rest_globals(rig)
	var soft: bool = options.get("move", "rigid") == "soft"
	var to_trunk := _trunk_of(source, rig)
	var surfaces := []
	for s in source.surfaces:
		surfaces.append(_surface(s, frame, moved, rig, globals, to_trunk, soft))
	var notes := []
	if source.has("map"):
		notes.append("Its legs move with its hips and its arms with its chest, as a companion's do.")
	return { "rig": rig, "surfaces": surfaces, "clips": _clips(default, rig, grow), "notes": notes,
		"yard": { "height": snappedf(tall, 1e-4), "stride": float(default.yard.get("stride", 0.66)) * grow, "cycle": default.yard.get("cycle", 1.3333) } }

## Model space to the companion's: a humanoid faced by its legs (as a
## character is); anything else up +Y and facing +Z as made, turned by
## `turn` degrees. Then on the ground, centred, and `tall` high.
static func _frame(source: Dictionary, tall: float, turn: float) -> Transform3D:
	var facing := Basis()
	if source.has("map"):
		var rest := StudioRig.rest_globals(source.rig)
		var map: Dictionary = source.map
		var up: Vector3 = (rest[map.Head].origin - rest[map.Hips].origin).normalized()
		var left: Vector3 = rest[map.LeftUpperLeg].origin - rest[map.RightUpperLeg].origin
		left = (left - up * left.dot(up)).normalized()
		facing = Basis(left, up, left.cross(up)).transposed()
	facing = Basis(Vector3.UP, deg_to_rad(turn)) * facing
	var box := AABB()
	var first := true
	for s in source.surfaces:
		for v in s.verts:
			var p: Vector3 = facing * v
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	var scale := tall / maxf(box.size.y, 1e-6)
	var centre := box.get_center()
	return Transform3D(facing * scale, -Vector3(centre.x, box.position.y, centre.z) * scale)

## Each source bone's trunk bone: a humanoid's by its map (limbs folded),
## else none (the binding decides).
static func _trunk_of(source: Dictionary, rig: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not source.has("map"):
		return out
	var src: Dictionary = source.rig
	var of := {}
	for contract in source.map:
		var trunk: String = contract
		for limb in FOLD:
			if contract.ends_with(limb) and (contract.begins_with("Left") or contract.begins_with("Right")):
				trunk = FOLD[limb]
		if rig.names.has(trunk):
			of[source.map[contract]] = rig.names.find(trunk)
	var by := StudioRig.follows(src)
	for i in src.names.size():
		var at: int = i
		while at >= 0 and not of.has(at):
			at = by[at]
		out.append(of[at] if at >= 0 else rig.names.find("Hips"))
	return out

static func _surface(s: Dictionary, frame: Transform3D, moved: Array[Transform3D], rig: Dictionary, globals: Array[Transform3D], to_trunk: PackedInt32Array, soft: bool) -> Dictionary:
	var n: int = s.verts.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	verts.resize(n)
	normals.resize(n if not s.normals.is_empty() else 0)
	bones.resize(n * 4)
	weights.resize(n * 4)
	var hips: int = rig.names.find("Hips")
	var chain := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"].map(func(b): return rig.names.find(b))
	var normal_frame := frame.basis.inverse().transposed()
	for v in n:
		var place := frame
		if not moved.is_empty():
			# Skinned: where its bones' turns carry it, blended by weight.
			var x := Vector3.ZERO
			var y := Vector3.ZERO
			var z := Vector3.ZERO
			var o := Vector3.ZERO
			var total := 0.0
			for k in s.per:
				var bone: int = s.bones[v * s.per + k]
				var w: float = s.weights[v * s.per + k]
				if bone >= 0 and w > 0.0:
					x += moved[bone].basis.x * w
					y += moved[bone].basis.y * w
					z += moved[bone].basis.z * w
					o += moved[bone].origin * w
					total += w
			if total > 0.0:
				place = Transform3D(Basis(x / total, y / total, z / total), o / total)
		verts[v] = place * s.verts[v]
		if not s.normals.is_empty():
			normals[v] = ((normal_frame if moved.is_empty() else place.basis.inverse().transposed()) * s.normals[v]).normalized()
		var sums := {}
		if not to_trunk.is_empty():
			for k in s.per:
				var bone: int = s.bones[v * s.per + k]
				if bone >= 0 and s.weights[v * s.per + k] > 0.0:
					sums[to_trunk[bone]] = sums.get(to_trunk[bone], 0.0) + s.weights[v * s.per + k]
		elif soft:
			# Between the two trunk joints its height falls between.
			var y := verts[v].y
			var below := 0
			while below + 1 < chain.size() and globals[chain[below + 1]].origin.y <= y:
				below += 1
			if below + 1 < chain.size() and y > globals[chain[0]].origin.y:
				var a: float = globals[chain[below]].origin.y
				var share := clampf((y - a) / (globals[chain[below + 1]].origin.y - a), 0.0, 1.0)
				sums[chain[below]] = 1.0 - share
				sums[chain[below + 1]] = share
			else:
				sums[chain[below]] = 1.0
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

## The helper's clips on the companion: rotations as they are, the hips' hop
## and bob scaled with the height.
static func _clips(default: Dictionary, rig: Dictionary, grow: float) -> Dictionary:
	var def_rig: Dictionary = default.rig
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
			for k in source.track_get_key_count(track):
				var value = source.track_get_key_value(track, k)
				if kind == Animation.TYPE_POSITION_3D:
					value = rig.rests[bone].origin + (value - def_rig.rests[bone].origin) * grow
				anim.track_insert_key(t, source.track_get_key_time(track, k), value)
		out[clip] = anim
	return out

## Four companions from one: tinted four ways (a colour laid over its own),
## or turned and sized four ways about its middle.
static func variants(piece: Dictionary, how: String) -> Array:
	var out := []
	for k in 4:
		var copy := piece.duplicate()
		copy.surfaces = []
		for s in piece.surfaces:
			var c: Dictionary = s.duplicate()
			if how == "tint" and k > 0:
				c.look = s.look.merged({ "color": s.look.color * TINTS[k] }, true)
			elif how == "turn" and k > 0:
				var place := Transform3D(Basis(Vector3.UP, deg_to_rad(TURNS[k][0])).scaled(Vector3.ONE * TURNS[k][1]), Vector3.ZERO)
				var verts := PackedVector3Array()
				var normals := PackedVector3Array()
				for v in s.verts:
					verts.append(place * v)
				for nrm in s.normals:
					normals.append(place.basis.orthonormalized() * nrm)
				c.verts = verts
				c.normals = normals
			copy.surfaces.append(c)
		out.append(copy)
	return out
