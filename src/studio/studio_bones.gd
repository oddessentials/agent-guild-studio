class_name StudioBones
## Which of a model's bones stands for each bone of the contract skeleton.
## A VRM's own humanoid map comes first, then the common tools' bone names;
## the spine between hips and neck is read from the hierarchy. A model whose
## names mean nothing is read from its shape, and every bone found that way
## is unsure. Whatever can't be told for sure goes to the player to settle,
## and is never guessed silently.

## Bones a character needs from its model. The spine, shoulders and toes
## can be made between their neighbours.
const NEEDED := ["Hips", "Neck", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
const OPTIONAL := ["LeftShoulder", "RightShoulder", "LeftToes", "RightToes"]
const SPINE := ["Spine", "Chest", "UpperChest"]
## What each bone hangs from, among the bones mapped by name.
const UNDER := { "Neck": "Hips", "Head": "Neck", "LeftShoulder": "Hips", "RightShoulder": "Hips",
	"LeftUpperArm": "LeftShoulder", "RightUpperArm": "RightShoulder", "LeftLowerArm": "LeftUpperArm", "RightLowerArm": "RightUpperArm",
	"LeftHand": "LeftLowerArm", "RightHand": "RightLowerArm", "LeftUpperLeg": "Hips", "RightUpperLeg": "Hips",
	"LeftLowerLeg": "LeftUpperLeg", "RightLowerLeg": "RightUpperLeg", "LeftFoot": "LeftLowerLeg", "RightFoot": "RightLowerLeg",
	"LeftToes": "LeftFoot", "RightToes": "RightFoot" }
const GUESSED := "read from the model's shape; check it"

## Each rig's names, as plain() gives them, for the hips, neck and head,
## then each side's limb: shoulder, upper arm, forearm, hand, thigh, shin,
## foot and toes; "*" is the side's letter or word as the rig writes it.
const RIGS := {
	"Mixamo": [["hips", "neck", "head"], ["*shoulder", "*arm", "*forearm", "*hand", "*upleg", "*leg", "*foot", "*toebase"], ["left", "right"]],
	"Unreal": [["pelvis", "neck01", "head"], ["clavicle*", "upperarm*", "lowerarm*", "hand*", "thigh*", "calf*", "foot*", "ball*"], ["l", "r"]],
	"Character Creator": [["ccbasehip", "ccbasenecktwist01", "ccbasehead"],
		["ccbase*clavicle", "ccbase*upperarm", "ccbase*forearm", "ccbase*hand", "ccbase*thigh", "ccbase*calf", "ccbase*foot", "ccbase*toebase"], ["l", "r"]],
	"Rigify": [["defspine", "defspine004", "defspine006"],
		["defshoulder*", "defupperarm*", "defforearm*", "defhand*", "defthigh*", "defshin*", "deffoot*", "deftoe*"], ["l", "r"]],
	"Tripo": [["hips", "neck", "head"], ["shoulder*", "upperarm*", "forearm*", "hand*", "thigh*", "shin*", "foot*", "toe*"], ["l", "r"]],
	"Godot humanoid": [["hips", "neck", "head"],
		["*shoulder", "*upperarm", "*lowerarm", "*hand", "*upperleg", "*lowerleg", "*foot", "*toes"], ["left", "right"]],
}
const LIMB := ["Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toes"]

## { map: {contract bone: model bone}, unsure: {contract bone: why}, rig: the
## rig's name }, plus `reason` when the model can't be a character at all.
## `vrm` is a VRM's own map, {contract bone: model bone}, when it has one;
## `surfaces` (StudioSource.read's) lets the feet tell left from right.
static func guess(rig: Dictionary, vrm := {}, surfaces := []) -> Dictionary:
	if not vrm.is_empty():
		return settle(rig, vrm, "VRM", surfaces)
	var best := {}
	var best_name := ""
	for rig_name in RIGS:
		var found := _named(rig, RIGS[rig_name])
		if found.size() > best.size():
			best = found
			best_name = rig_name
	if best.size() >= NEEDED.size() / 2:
		return settle(rig, best, best_name, surfaces)
	var shaped := shape(rig)
	var out := settle(rig, shaped, "", surfaces)
	for bone in shaped:
		if not out.unsure.has(bone):
			out.unsure[bone] = GUESSED
	return out

static func _named(rig: Dictionary, table: Array) -> Dictionary:
	var want := {}
	for k in 3:
		want[table[0][k]] = ["Hips", "Neck", "Head"][k]
	for s in 2:
		for k in LIMB.size():
			want[String(table[1][k]).replace("*", table[2][s])] = ["Left", "Right"][s] + LIMB[k]
	var found := {}
	for i in rig.names.size():
		var contract = want.get(plain(rig.names[i]))
		if contract != null and not found.has(contract):
			found[contract] = i
	return found

## The bones a VRM names for itself, by the glTF node each one is.
static func from_vrm(json: Dictionary, node_names: PackedStringArray, rig: Dictionary) -> Dictionary:
	var ext: Dictionary = json.get("extensions", {})
	var pairs := []
	if ext.has("VRMC_vrm"):
		var bones: Dictionary = ext.VRMC_vrm.get("humanoid", {}).get("humanBones", {})
		for name in bones:
			pairs.append([name, int(bones[name].get("node", -1))])
	elif ext.has("VRM"):
		for b in ext.VRM.get("humanoid", {}).get("humanBones", []):
			pairs.append([String(b.get("bone", "")), int(b.get("node", -1))])
	var out := {}
	for pair in pairs:
		var contract: String = pair[0].substr(0, 1).to_upper() + pair[0].substr(1)
		if pair[1] < 0 or pair[1] >= node_names.size() or not (contract in NEEDED or contract in OPTIONAL or contract in SPINE):
			continue
		var bone: int = rig.names.find(node_names[pair[1]].replace(":", "_").replace("/", "_"))
		if bone >= 0:
			out[contract] = bone
	return out

## The map with the player's (or --map's) choices, checked again.
static func settle(rig: Dictionary, named: Dictionary, rig_name := "", surfaces := []) -> Dictionary:
	var map := named.duplicate()
	var unsure := {}
	if not map.has("Hips") or not (map.has("LeftUpperLeg") or map.has("RightUpperLeg")):
		return { "map": map, "unsure": unsure, "rig": rig_name,
			"reason": "it has no hips and legs Studio can find, so it can't walk as a character" }
	for bone in NEEDED:
		if not map.has(bone):
			unsure[bone] = "no bone matched"
	for bone in UNDER:
		if map.has(bone) and map.has(UNDER[bone]) and (not StudioRig.is_under(rig, map[bone], map[UNDER[bone]]) or map[bone] == map[UNDER[bone]]):
			unsure[bone] = "it is not under %s" % UNDER[bone]
	if map.has("Neck") and map.has("Hips") and StudioRig.is_under(rig, map.Neck, map.Hips):
		var chain := []
		var at: int = rig.parents[map.Neck]
		while at >= 0 and at != map.Hips:
			chain.push_front(at)
			at = rig.parents[at]
		# One to three bones fill Spine, Chest and UpperChest in order; more
		# keep the first, middle and last, and the rest fold into them.
		var picks := chain if chain.size() <= 3 else [chain[0], chain[chain.size() / 2], chain[-1]]
		for name in SPINE:
			map.erase(name)
		for k in picks.size():
			map[SPINE[k]] = picks[k]
	_check_sides(rig, map, unsure, surfaces)
	return { "map": map, "unsure": unsure, "rig": rig_name }

## The same map with every left bone and its right one exchanged, for a rig
## that names its sides the other way round.
static func swapped(map: Dictionary) -> Dictionary:
	var out := {}
	for bone in map:
		var other: String = bone.replace("Left", "@").replace("Right", "Left").replace("@", "Right")
		out[other] = map[bone]
	return out

## Left and right read from the bones' names; a model's toes point forward
## of its legs when they are right, so toes pointing back mean they're swapped.
## Without toes, the feet's own mesh says the same: it reaches forward of
## the ankle.
static func _check_sides(rig: Dictionary, map: Dictionary, unsure: Dictionary, surfaces: Array) -> void:
	for bone in ["Hips", "Head", "LeftUpperLeg", "RightUpperLeg"]:
		if not map.has(bone) or unsure.has(bone):
			return
	var at := StudioRig.rest_globals(rig)
	var up: Vector3 = (at[map.Head].origin - at[map.Hips].origin).normalized()
	var left: Vector3 = at[map.LeftUpperLeg].origin - at[map.RightUpperLeg].origin
	var forward := (left - up * left.dot(up)).normalized().cross(up)
	var votes := 0
	for side in ["Left", "Right"]:
		var foot: int = map.get(side + "Foot", -1)
		var toe := _toe(rig, map, side)
		if foot >= 0 and toe >= 0:
			votes += signi(int(signf(forward.dot(at[toe].origin - at[foot].origin))))
	if votes == 0:
		for side in ["Left", "Right"]:
			var foot: int = map.get(side + "Foot", -1)
			var sum := Vector3.ZERO
			var count := 0
			for s in surfaces:
				for v in s.verts.size():
					if s.bones[v * s.per] == foot and s.weights[v * s.per] > 0.5:
						sum += s.verts[v]
						count += 1
			if foot >= 0 and count > 0:
				var reach := sum / count - at[foot].origin
				votes += signi(int(signf(forward.dot(reach - up * reach.dot(up)))))
	if votes < 0:
		unsure["LeftUpperLeg"] = "its left and right look swapped"
		unsure["RightUpperLeg"] = "its left and right look swapped"

## The bone at a foot's toes: its Toes, else the foot's first child.
static func _toe(rig: Dictionary, map: Dictionary, side: String) -> int:
	if map.has(side + "Toes"):
		return map[side + "Toes"]
	var foot: int = map.get(side + "Foot", -1)
	return rig.parents.find(foot) if foot >= 0 else -1

## A map read from the skeleton's shape alone: the hips are where two
## matching chains (the legs) leave a third (the spine); the chest is where
## two matching chains (the arms) leave a third (the neck and head). Feet
## point forward, which tells left from right. Every bone is unsure.
static func shape(rig: Dictionary) -> Dictionary:
	var at := StudioRig.rest_globals(rig)
	var kids := {}
	for i in rig.parents.size():
		kids.get_or_add(rig.parents[i], []).append(i)
	var depth := func(bone: int) -> int:
		var d := 0
		var stack := [[bone, 1]]
		while not stack.is_empty():
			var top: Array = stack.pop_back()
			d = maxi(d, top[1])
			for c in kids.get(top[0], []):
				stack.append([c, top[1] + 1])
		return d
	var out := {}
	for hips in rig.names.size():
		var children: Array = kids.get(hips, [])
		if children.size() < 3:
			continue
		var pair := _mirrored(children, at, depth)
		if pair.is_empty():
			continue
		var rest := children.filter(func(c): return not c in pair)
		var spine: int = rest.reduce(func(a, b): return a if depth.call(a) >= depth.call(b) else b)
		if at[pair[0]].origin.y > at[spine].origin.y:
			continue
		var chest := spine
		var arms := []
		while kids.get(chest, []).size() > 0:
			var split: Array = kids[chest]
			if split.size() >= 3:
				arms = _mirrored(split, at, depth)
				if not arms.is_empty():
					break
			chest = split.reduce(func(a, b): return a if depth.call(a) >= depth.call(b) else b)
		if arms.is_empty():
			continue
		var neck: int = kids[chest].filter(func(c): return not c in arms).reduce(func(a, b): return a if depth.call(a) >= depth.call(b) else b)
		out.Hips = hips
		out.Neck = neck
		if kids.has(neck):
			out.Head = kids[neck].reduce(func(a, b): return a if depth.call(a) >= depth.call(b) else b)
		var up: Vector3 = (at[neck].origin - at[hips].origin).normalized()
		var legs := [_chain(pair[0], kids, depth), _chain(pair[1], kids, depth)]
		var forward := Vector3.ZERO
		for leg in legs:
			if leg.size() >= 4:
				forward += at[leg[3]].origin - at[leg[2]].origin
		forward = (forward - up * forward.dot(up)).normalized()
		var left := up.cross(forward)
		for k in 2:
			var side := "Left" if (at[pair[k]].origin - at[hips].origin).dot(left) > 0 else "Right"
			var leg: Array = legs[k]
			for n in mini(leg.size(), 4):
				out[side + ["UpperLeg", "LowerLeg", "Foot", "Toes"][n]] = leg[n]
			var arm := _chain(arms[k], kids, depth)
			var arm_side := "Left" if (at[arms[k]].origin - at[chest].origin).dot(left) > 0 else "Right"
			var names := ["Shoulder", "UpperArm", "LowerArm", "Hand"] if arm.size() >= 4 else ["UpperArm", "LowerArm", "Hand"]
			for n in mini(arm.size(), names.size()):
				out[arm_side + names[n]] = arm[n]
		return out
	return out

## Two children whose chains match: as deep as each other, either side of
## their parent.
static func _mirrored(children: Array, at: Array[Transform3D], depth: Callable) -> Array:
	for a in children.size():
		for b in range(a + 1, children.size()):
			var x: int = children[a]
			var y: int = children[b]
			if depth.call(x) == depth.call(y) and depth.call(x) >= 3 and at[x].origin.distance_to(at[y].origin) > 1e-4:
				return [x, y]
	return []

## A bone and its deepest descendants, one per generation.
static func _chain(bone: int, kids: Dictionary, depth: Callable) -> Array:
	var out := [bone]
	while kids.has(out[-1]):
		out.append(kids[out[-1]].reduce(func(a, b): return a if depth.call(a) >= depth.call(b) else b))
	return out

## A bone's name without a Mixamo prefix ("mixamorig:", "mixamorig1_"),
## case, or the dots, underscores, dashes and spaces rigs put between words.
static func plain(name: String) -> String:
	var out := name.get_slice(":", name.get_slice_count(":") - 1).to_lower()
	out = RegEx.create_from_string("^mixamorig[0-9]*_").sub(out, "")
	return RegEx.create_from_string("[._ -]").sub(out, "", true)
