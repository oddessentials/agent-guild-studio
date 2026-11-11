class_name StudioTearing
## How much a clip tears a piece's mesh, measured as rig.py measures the
## cast's (torn): at 16 moments of the clip, the largest share of any part of
## the body (an arm, a hand, a leg with its foot, the trunk, the head) whose
## triangles stretch past STRETCH times a rest edge. Plain data, any thread.

const STRETCH := 2.0
## A part torn over more than TORN of its surface needs fixing.
const TORN := .03
## A small part is measured against no less than FLOOR of the whole body.
const FLOOR := .02
const MOMENTS := 16
const PARTS := { "Shoulder": "arm", "UpperArm": "arm", "LowerArm": "arm", "Hand": "hand",
	"UpperLeg": "leg", "LowerLeg": "leg", "Foot": "leg", "Toes": "leg" }

## The body part a bone moves, or "" for a held tool's socket.
static func part_of(bone: String) -> String:
	if bone in ["Neck", "Head"]:
		return "head"
	if bone.begins_with("Prop"):
		return ""
	for suffix in PARTS:
		if bone.ends_with(suffix):
			return PARTS[suffix] + bone[0]
	return "trunk"

## The triangles of a piece's surfaces (StudioCharacter.fit) at rest, by part:
## what worst() measures clips against.
static func body(rig: Dictionary, surfaces: Array) -> Dictionary:
	var verts := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var tris := PackedInt32Array()
	var parts := PackedStringArray()
	for s in surfaces:
		var base := verts.size()
		verts.append_array(s.verts)
		bones.append_array(s.bones)
		weights.append_array(s.weights)
		for i in range(0, s.indices.size(), 3):
			var v: int = s.indices[i]
			var strongest := 0
			for k in 4:
				if s.weights[v * 4 + k] > s.weights[v * 4 + strongest]:
					strongest = k
			tris.append_array([base + v, base + s.indices[i + 1], base + s.indices[i + 2]])
			parts.append(part_of(rig.names[s.bones[v * 4 + strongest]]))
	var rest := _edges(verts, tris)
	var areas := PackedFloat32Array()
	var by_part := {}
	var total := 0.0
	for t in range(0, tris.size(), 3):
		var a := verts[tris[t]]
		var area := (verts[tris[t + 1]] - a).cross(verts[tris[t + 2]] - a).length() / 2.0
		areas.append(area)
		total += area
		var part := parts[t / 3]
		if part != "":
			by_part[part] = by_part.get(part, 0.0) + area
	return { "verts": verts, "bones": bones, "weights": weights, "tris": tris, "parts": parts, "rest": rest,
		"areas": areas, "by_part": by_part, "total": total, "globals": StudioRig.rest_globals(rig) }

## The largest share of any part torn at MOMENTS moments of `anim`.
static func worst(rig: Dictionary, shape: Dictionary, anim: Animation) -> float:
	var most := 0.0
	var inverse: Array[Transform3D] = []
	for g in shape.globals:
		inverse.append(g.affine_inverse())
	for m in MOMENTS:
		var posed := StudioRig.globals(rig, StudioRig.pose(rig, anim, anim.length * m / MOMENTS))
		var skin: Array[Transform3D] = []
		for b in posed.size():
			skin.append(posed[b] * inverse[b])
		var at := PackedVector3Array()
		at.resize(shape.verts.size())
		for v in shape.verts.size():
			var p := Vector3.ZERO
			for k in 4:
				var w: float = shape.weights[v * 4 + k]
				if w > 0.0:
					p += skin[shape.bones[v * 4 + k]] * shape.verts[v] * w
			at[v] = p
		var edges := _edges(at, shape.tris)
		var torn := {}
		for t in shape.parts.size():
			var part: String = shape.parts[t]
			if part == "":
				continue
			for e in 3:
				if edges[t * 3 + e] > STRETCH * maxf(shape.rest[t * 3 + e], 1e-9):
					torn[part] = torn.get(part, 0.0) + shape.areas[t]
					break
		for part in torn:
			most = maxf(most, torn[part] / maxf(shape.by_part[part], FLOOR * shape.total))
	return most

static func _edges(verts: PackedVector3Array, tris: PackedInt32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(tris.size())
	for t in range(0, tris.size(), 3):
		var a := verts[tris[t]]
		var b := verts[tris[t + 1]]
		var c := verts[tris[t + 2]]
		out[t] = a.distance_to(b)
		out[t + 1] = b.distance_to(c)
		out[t + 2] = c.distance_to(a)
	return out
