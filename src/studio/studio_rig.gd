class_name StudioRig
## A skeleton as plain data (bone names, parents and local rests) and the
## poses a clip gives it. Plain data can be worked on off the main thread.

## The skeleton of a model not in the tree; `base` places it in the model.
static func of(skeleton: Skeleton3D, model: Node) -> Dictionary:
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	var rests: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
		parents.append(skeleton.get_bone_parent(i))
		rests.append(skeleton.get_bone_rest(i))
	return { "names": names, "parents": parents, "rests": rests, "base": placement(skeleton, model) }

## A node's transform relative to the model it belongs to, without the tree.
static func placement(node: Node, model: Node) -> Transform3D:
	var out := Transform3D()
	var at := node
	while at != null and at != model:
		if at is Node3D:
			out = (at as Node3D).transform * out
		at = at.get_parent()
	return out

## Each bone's transform in the model, from local transforms.
static func globals(rig: Dictionary, locals: Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(locals.size())
	var done := PackedByteArray()
	done.resize(locals.size())
	for i in locals.size():
		_global(rig, locals, i, out, done)
	return out

static func _global(rig: Dictionary, locals: Array, i: int, out: Array[Transform3D], done: PackedByteArray) -> Transform3D:
	if done[i] == 0:
		var parent: int = rig.parents[i]
		out[i] = (_global(rig, locals, parent, out, done) if parent >= 0 else rig.base) * locals[i]
		done[i] = 1
	return out[i]

static func rest_globals(rig: Dictionary) -> Array[Transform3D]:
	return globals(rig, rig.rests)

## The local transforms a clip gives at time t; bones it has no track for
## stay at rest, as they do when the game plays it.
static func pose(rig: Dictionary, anim: Animation, t: float) -> Array[Transform3D]:
	var locals: Array[Transform3D] = rig.rests.duplicate()
	for track in anim.get_track_count():
		var bone: int = rig.names.find(String(anim.track_get_path(track).get_concatenated_subnames()))
		if bone < 0:
			continue
		match anim.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				locals[bone].basis = Basis(anim.rotation_track_interpolate(track, t)).scaled(locals[bone].basis.get_scale())
			Animation.TYPE_POSITION_3D:
				locals[bone].origin = anim.position_track_interpolate(track, t)
	return locals

## The bone each bone moves with: its parent, or for a bone a VRM aims at
## another (a twist or sleeve bone), the bone that turns toward that target.
static func follows(rig: Dictionary) -> PackedInt32Array:
	return rig.get("follows", rig.parents)

## Descendants of a bone, the bone first, by what each moves with.
static func subtree(rig: Dictionary, bone: int) -> PackedInt32Array:
	var by := follows(rig)
	var out := PackedInt32Array([bone])
	var at := 0
	while at < out.size():
		for i in by.size():
			if by[i] == out[at]:
				out.append(i)
		at += 1
	return out

## Whether `bone` is `ancestor` or under it.
static func is_under(rig: Dictionary, bone: int, ancestor: int) -> bool:
	while bone >= 0:
		if bone == ancestor:
			return true
		bone = rig.parents[bone]
	return false
