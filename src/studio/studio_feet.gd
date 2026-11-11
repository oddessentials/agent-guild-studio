class_name StudioFeet
## Plants a piece's feet at the speed the game walks it. The game moves every
## piece at its slot default's stride / cycle and plays the walk in place, so
## a planted foot must travel back at exactly that speed under the body (and
## stay still in clips played standing). The piece's feet follow the
## default's, moved to the piece's legs; while one is as low as it goes it is
## planted, held on the ground at that speed, and it swings the default's way
## in between,
## and solves each leg to reach (knee bent the default's way, hips lowered
## where a leg can't reach). Plain data, so any thread.

const SIDES := ["Left", "Right"]
const FPS := 24.0
## A foot is planted while its ankle is this close (a share of the height)
## to the lowest it goes in the clip.
const PLANTED := .005
## How far a planted foot may slide, as a share of the height (rig.py's).
const SLIDE := .02
## A step Studio walks for a default that glides instead (robed, floating):
## planted this share of the cycle, the foot lifted this share of the height.
const STANCE := .6
const LIFT := .04

## Rewrites the legs' rotations and the hips' travel in `anim` (the piece's
## copy of the default's clip `theirs`) so its feet are planted at `speed`.
## `height` is the piece's. Whether the default glides, so the piece's legs
## take Studio's own step instead of following its feet.
static func pin(anim: Animation, rig: Dictionary, theirs: Animation, def_rig: Dictionary, speed: float, height: float) -> bool:
	# Keyed on the clip's own step (Godot's importer bakes clips at 30 fps),
	# so the piece's legs are sampled where its other bones are, written or
	# loaded back.
	var step: float = anim.step if anim.step > 0.0 else 1.0 / FPS
	var frames := int(round(anim.length / step))
	var looped := anim.loop_mode != Animation.LOOP_NONE
	var rest := StudioRig.rest_globals(rig)
	var def_rest := StudioRig.rest_globals(def_rig)
	var bone := func(r: Dictionary, name: String) -> int: return r.names.find(name)
	var hips: int = bone.call(rig, "Hips")
	var mine := []
	var targets := {}
	var glides := false
	for k in frames + 1:
		mine.append(StudioRig.pose(rig, anim, minf(k * step, anim.length)))
	for side in SIDES:
		var foot: int = bone.call(rig, side + "Foot")
		var def_foot: int = bone.call(def_rig, side + "Foot")
		var reach: float = rest[bone.call(rig, side + "UpperLeg")].origin.y - rest[foot].origin.y
		var def_reach: float = def_rest[bone.call(def_rig, side + "UpperLeg")].origin.y - def_rest[def_foot].origin.y
		var path := PackedVector3Array()
		var low := INF
		for k in frames + 1:
			var at: Vector3 = StudioRig.globals(def_rig, StudioRig.pose(def_rig, theirs, minf(k * step, theirs.length)))[def_foot].origin
			var moved := at - def_rest[def_foot].origin
			path.append(rest[foot].origin + Vector3(moved.x, moved.y * reach / def_reach, moved.z))
			low = minf(low, path[k].y)
		# A default that glides moves its feet far less than the body travels
		# while one is down: the piece steps for itself.
		var travel := 0.0
		for p in path:
			travel = maxf(travel, absf(p.z - path[0].z))
		if speed > 0.0 and travel < 0.25 * speed * anim.length * STANCE:
			glides = true
			path = _step(rest[foot].origin, frames, step, anim.length, speed, height, 0.0 if side == "Left" else 0.5)
			low = rest[foot].origin.y
		# Planted as slide() judges it, so what's held is what's measured.
		var planted := PackedByteArray()
		for k in frames + 1:
			planted.append(1 if path[k].y <= low + PLANTED * height else 0)
		targets[side] = _planted(path, planted, speed * step, low, looped)
	var keys := {}
	for name in ["Hips"] + SIDES.map(func(s): return s + "UpperLeg") + SIDES.map(func(s): return s + "LowerLeg") + SIDES.map(func(s): return s + "Foot"):
		keys[name] = []
	for k in frames + 1:
		var locals: Array[Transform3D] = mine[k]
		var globals := StudioRig.globals(rig, locals)
		var drop := 0.0
		for side in SIDES:
			var upper: int = bone.call(rig, side + "UpperLeg")
			var lower: int = bone.call(rig, side + "LowerLeg")
			var foot: int = bone.call(rig, side + "Foot")
			var longest: float = (rest[lower].origin.distance_to(rest[upper].origin) + rest[foot].origin.distance_to(rest[lower].origin)) * 0.999
			var to: Vector3 = targets[side][k] - globals[upper].origin
			var flat := Vector2(to.x, to.z).length_squared()
			if to.length() > longest and flat < longest * longest:
				drop = maxf(drop, -to.y - sqrt(longest * longest - flat))
		if drop > 0.0:
			locals[hips].origin -= (globals[rig.parents[hips]].basis.inverse() if rig.parents[hips] >= 0 else Basis()) * Vector3(0, drop, 0)
			globals = StudioRig.globals(rig, locals)
		for side in SIDES:
			_reach(rig, locals, globals, side, targets[side][k], rest)
		keys.Hips.append(locals[hips].origin)
		for name in keys:
			if name != "Hips":
				keys[name].append(locals[bone.call(rig, name)].basis.get_rotation_quaternion())
	for name in keys:
		var kind := Animation.TYPE_POSITION_3D if name == "Hips" else Animation.TYPE_ROTATION_3D
		var path := NodePath("Skeleton3D:" + name)
		for t in range(anim.get_track_count() - 1, -1, -1):
			if anim.track_get_path(t) == path and anim.track_get_type(t) == kind:
				anim.remove_track(t)
		var t := anim.add_track(kind)
		anim.track_set_path(t, path)
		for k in frames + 1:
			anim.track_insert_key(t, minf(k * step, anim.length), keys[name][k])
	return glides

## Studio's own step for a foot resting at `rest`: planted STANCE of the cycle
## and travelling back at `speed`, then carried forward in a low arc; `phase`
## puts the two feet half a cycle apart.
static func _step(rest: Vector3, frames: int, step: float, length: float, speed: float, height: float, phase: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var reach := speed * length * STANCE / 2.0
	for k in frames + 1:
		var q := fposmod(minf(k * step, length) / length + phase, 1.0)
		if q < STANCE:
			out.append(rest + Vector3(0, 0, reach - 2.0 * reach * q / STANCE))
		else:
			var s := (q - STANCE) / (1.0 - STANCE)
			out.append(rest + Vector3(0, LIFT * height * sin(PI * s), -reach + 2.0 * reach * s))
	return out

## The ankle's path with each planted stretch held on the ground (at the
## ankle's lowest, `ground`), travelling back (-Z) `travel` metres a frame,
## and each swing shifted to meet them.
static func _planted(path: PackedVector3Array, planted: PackedByteArray, travel: float, ground: float, looped: bool) -> PackedVector3Array:
	var order := frames_in_order(planted, looped)
	var n := order.size()
	var out := path.duplicate()
	var fix := PackedVector3Array()
	fix.resize(n)
	var held := PackedByteArray()
	held.resize(n)
	var start := -1
	for i in n:
		var k := order[i]
		if planted[k] and (i == 0 or not planted[order[i - 1]]):
			start = i
		if planted[k] and start >= 0:
			var first := order[start]
			var still := Vector3(path[first].x, path[k].y, path[first].z - travel * (i - start))
			fix[i] = still - path[k]
			out[k] = still
			held[i] = 1
	# A swing carries the gap left at the end of one planted stretch to
	# nothing by the start of the next, so the foot lands where it should.
	var i := 0
	while i < n:
		if held[i]:
			i += 1
			continue
		var from := i - 1
		var to := i
		while to < n and not held[to]:
			to += 1
		var a: Vector3 = fix[from] if from >= 0 else Vector3.ZERO
		var b: Vector3 = fix[to] if to < n else Vector3.ZERO
		for j in range(i, to):
			out[order[j]] = path[order[j]] + a.lerp(b, float(j - from) / float(to - from))
		i = to
	if looped:
		out[path.size() - 1] = out[0]
	return out

## The frames of a clip in the order its feet live them. A looping clip's
## last frame is its first again, so it's left out, and the cycle starts on a
## frame with the foot in the air, so no planted stretch is cut in two.
static func frames_in_order(planted: PackedByteArray, looped: bool) -> PackedInt32Array:
	var n := planted.size() - (1 if looped else 0)
	var first := 0
	if looped:
		while first < n and planted[first]:
			first += 1
		if first == n:
			first = 0
	var out := PackedInt32Array()
	for i in n:
		out.append((first + i) % n)
	return out

## Turns one leg so its ankle reaches `target`: the thigh and shin in the
## plane the clip already bends the knee in, the foot kept as the clip has it.
static func _reach(rig: Dictionary, locals: Array[Transform3D], globals: Array[Transform3D], side: String, target: Vector3, rest: Array[Transform3D]) -> void:
	var upper: int = rig.names.find(side + "UpperLeg")
	var lower: int = rig.names.find(side + "LowerLeg")
	var foot: int = rig.names.find(side + "Foot")
	var hip := globals[upper].origin
	var knee := globals[lower].origin
	var ankle := globals[foot].origin
	var a: float = rest[lower].origin.distance_to(rest[upper].origin)
	var b: float = rest[foot].origin.distance_to(rest[lower].origin)
	var to := target - hip
	var d := clampf(to.length(), absf(a - b) + 1e-4, (a + b) * 0.999)
	var along := to.normalized()
	var bend := (knee - hip) - along * (knee - hip).dot(along)
	if bend.length() < 1e-5:
		bend = globals[upper].basis.z.normalized()
	bend = bend.normalized()
	var cos_hip := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var new_knee := hip + along * a * cos_hip + bend * a * sqrt(1.0 - cos_hip * cos_hip)
	var new_ankle := hip + along * d
	var thigh := Basis(Quaternion((knee - hip).normalized(), (new_knee - hip).normalized()))
	var shin := Basis(Quaternion((thigh * (ankle - knee)).normalized(), (new_ankle - new_knee).normalized()))
	var upper_g := Transform3D(thigh * globals[upper].basis, hip)
	var lower_g := Transform3D(shin * thigh * globals[lower].basis, new_knee)
	var parent: Transform3D = globals[rig.parents[upper]]
	locals[upper].basis = (parent.basis.inverse() * upper_g.basis).orthonormalized()
	locals[lower].basis = (upper_g.basis.inverse() * lower_g.basis).orthonormalized()
	locals[foot].basis = (lower_g.basis.inverse() * globals[foot].basis).orthonormalized()

## How far a planted foot slides on the ground while the game moves the body
## at `speed`, in metres: the worst of either foot across its planted
## stretches. A foot is planted while it is as low as it goes in the clip.
## A foot down through a whole looping walk slides the body's whole travel.
static func slide(rig: Dictionary, anim: Animation, speed: float, height: float) -> float:
	var frames := int(round(anim.length * FPS))
	var worst := 0.0
	var poses := []
	for k in frames + 1:
		poses.append(StudioRig.globals(rig, StudioRig.pose(rig, anim, minf(k / FPS, anim.length))))
	for side in SIDES:
		var foot: int = rig.names.find(side + "Foot")
		var low := INF
		for g in poses:
			low = minf(low, g[foot].origin.y)
		var planted := PackedByteArray()
		for g in poses:
			planted.append(1 if g[foot].origin.y <= low + PLANTED * height else 0)
		var looped := anim.loop_mode != Animation.LOOP_NONE
		if looped and speed > 0.0 and Array(planted).all(func(p): return p == 1):
			# Down the whole looping walk while the body travels: the foot must
			# jump back by the whole travel every time the walk starts again.
			worst = maxf(worst, speed * anim.length)
			continue
		var order := frames_in_order(planted, looped)
		var stretch := []
		for i in order.size() + 1:
			var k: int = order[i] if i < order.size() else -1
			if k >= 0 and planted[k]:
				# On the ground, the body's travel carries the foot back.
				var at: Vector3 = poses[k][foot].origin
				stretch.append(Vector2(at.x, at.z + speed * i / FPS))
			elif not stretch.is_empty():
				var box := Rect2(stretch[0], Vector2.ZERO)
				for p in stretch:
					box = box.expand(p)
				worst = maxf(worst, box.size.length())
				stretch = []
	return worst
