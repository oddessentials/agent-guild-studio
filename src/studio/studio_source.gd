class_name StudioSource
## A model someone brings to Studio, read into plain data: its skeleton, and
## its meshes as they stand at rest in the model's space, skinned the way
## Godot skins them. Opening and reading run on any thread while the model
## is outside the tree.
##
## Godot's loaders open whatever files a model names, so a brought model is
## only ever opened from its staged copy (stage). Its FBX loader searches the
## folders above a model for textures and can't be told not to: FBX is refused.

const EXTENSIONS := ["glb", "gltf", "vrm"]
const FBX := "FBX files can't be opened for now. Convert it to .glb first (Blender: import the FBX, then export as glTF 2.0)"
const STAGED := "user://studio/sources/"

static func refused(path: String) -> String:
	var extension := path.get_extension().to_lower()
	if extension == "fbx":
		return FBX
	return "" if extension in EXTENSIONS else "Studio opens .glb, .gltf and .vrm files"

## { dir, paths, notes } or { reason }: `paths` are the checked copies of
## `files`, in `dir`, which the caller removes when done with them.
static func stage(validator: PieceValidator, files: Array) -> Dictionary:
	for file in files:
		if refused(file) != "":
			return { "reason": refused(file) }
	var out := { "dir": ProjectSettings.globalize_path(STAGED).path_join("%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]), "paths": [], "notes": [] }
	for i in files.size():
		var into: String = out.dir.path_join(str(i))
		var verdict := await validator.check_source(files[i], into)
		if verdict.reason != "":
			StudioFiles.remove_tree(out.dir)
			return { "reason": verdict.reason }
		out.paths.append(into.path_join(String(files[i]).get_file()))
		var beside: Array = verdict.get("files", [])
		if not beside.is_empty():
			var named := ", ".join(beside.slice(0, 3)) + (" and %d more" % (beside.size() - 3) if beside.size() > 3 else "")
			out.notes.append("%s was read with the files it names in its folder: %s." % [String(files[i]).get_file(), named])
	return out

## In the checker's process: { reason, files }. The copy in `dir` is checked
## again, as the files could have changed since they were checked in place.
static func check(source: String, dir: String) -> Dictionary:
	if refused(source) != "":
		return { "reason": refused(source) }
	var seen := PieceCheck.check_source(source)
	if seen.reason != "":
		return seen
	for file in [source.get_file()] + seen.files:
		DirAccess.make_dir_recursive_absolute(dir.path_join(file).get_base_dir())
		if DirAccess.copy_absolute(source.get_base_dir().path_join(file), dir.path_join(file)) != OK:
			return { "reason": "%s could not be read" % file }
	var staged := PieceCheck.check_source(dir.path_join(source.get_file()))
	if staged.reason == "" and staged.files != seen.files:
		staged.reason = "it changed while Studio was reading it"
	if staged.reason != "":
		return staged
	var opened := open(dir.path_join(source.get_file()))
	if opened.has("reason"):
		return { "reason": opened.reason }
	opened.model.free()
	return staged

## { model, json, nodes } or { reason }, of a staged model. `json` is the
## glTF's own JSON; `nodes` names its nodes in order, for a VRM's bone map
## and constraints.
static func open(path: String) -> Dictionary:
	if refused(path) != "":
		return { "reason": refused(path) }
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return { "reason": "it is not a model Studio can read" }
	var model: Node = doc.generate_scene(state)
	if model == null:
		return { "reason": "it is not a model Studio can read" }
	var nodes := PackedStringArray()
	for node: GLTFNode in state.get_nodes():
		nodes.append(node.resource_name)
	return { "model": model, "json": state.json, "nodes": nodes }

## { rig, surfaces } or { reason }. Each surface holds its vertices and
## normals at rest in the model's space, UVs, triangles, per vertex `per`
## pairs of skeleton bone and weight, and its look (see look()). A part that isn't skinned moves with
## the bone it's attached to, or else the joint nearest its middle.
static func read(model: Node) -> Dictionary:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return { "reason": "it has no skeleton" }
	skeletons.sort_custom(func(a, b): return a.get_bone_count() > b.get_bone_count())
	var skeleton: Skeleton3D = skeletons.front()
	var rig := StudioRig.of(skeleton, model)
	# Godot skins in the mesh's space: bones posed in the skeleton's own space,
	# then the mesh's transform. Joints are placed the same way, so the mesh
	# turns about them.
	var own := { "parents": rig.parents, "base": Transform3D() }
	var poses := StudioRig.globals(own, rig.rests)
	var surfaces := []
	var placed := false
	var loose := []
	var looks := {}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		if mi.skin == null:
			loose.append(mi)
			continue
		if mi.get_node_or_null(mi.skeleton) != skeleton:
			continue
		var place := StudioRig.placement(mi, model)
		if not placed:
			rig.base = place
			placed = true
		var binds := PackedInt32Array()
		var matrices: Array[Transform3D] = []
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			if bone < 0:
				bone = skeleton.find_bone(mi.skin.get_bind_name(b))
			binds.append(bone)
			matrices.append(poses[bone] * mi.skin.get_bind_pose(b) if bone >= 0 else Transform3D())
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			surfaces.append(_surface(mi.mesh.surface_get_arrays(s), binds, matrices, place, look(_material(mi, s), looks)))
	if surfaces.is_empty():
		return { "reason": "it has no mesh on its skeleton" }
	var joints := StudioRig.rest_globals(rig)
	for mi: MeshInstance3D in loose:
		var bone := -1
		var place := StudioRig.placement(mi, model)
		var at: Node = mi
		while at != null and at != model and bone < 0:
			if at is BoneAttachment3D and at.get_parent() == skeleton:
				bone = skeleton.find_bone(at.bone_name)
				place = rig.base * poses[bone] * StudioRig.placement(mi, at)
			at = at.get_parent()
		if bone < 0:
			var middle := place * mi.mesh.get_aabb().get_center()
			for j in joints.size():
				if bone < 0 or joints[j].origin.distance_to(middle) < joints[bone].origin.distance_to(middle):
					bone = j
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES:
				var arrays := mi.mesh.surface_get_arrays(s)
				var count: int = arrays[Mesh.ARRAY_VERTEX].size()
				var ones := PackedFloat32Array()
				ones.resize(count)
				ones.fill(1.0)
				var zeros := PackedInt32Array()
				zeros.resize(count)
				arrays[Mesh.ARRAY_BONES] = zeros
				arrays[Mesh.ARRAY_WEIGHTS] = ones
				var still: Array[Transform3D] = [Transform3D()]
				surfaces.append(_surface(arrays, PackedInt32Array([bone]), still, place, look(_material(mi, s), looks)))
	return { "rig": rig, "surfaces": surfaces }

## What each bone moves with (StudioRig.follows): a VRM bone aimed at
## another follows the bone that turns toward it, the target's parent.
static func follows(rig: Dictionary, json: Dictionary, nodes: PackedStringArray) -> PackedInt32Array:
	var out: PackedInt32Array = rig.parents.duplicate()
	var bone := func(node: int) -> int: return rig.names.find(nodes[node].replace(":", "_").replace("/", "_")) if node >= 0 and node < nodes.size() else -1
	var list: Array = json.get("nodes", [])
	for n in list.size():
		var aim: Dictionary = list[n].get("extensions", {}).get("VRMC_node_constraint", {}).get("constraint", {}).get("aim", {})
		var me: int = bone.call(n)
		var target: int = bone.call(int(aim.get("source", -1)))
		if me >= 0 and target >= 0 and rig.parents[target] >= 0:
			out[me] = rig.parents[target]
	return out

## { surfaces } for a model read as one rigid thing: every mesh where it
## stands at rest (skinned ones as their skeleton holds them), with no bones.
static func read_still(model: Node) -> Dictionary:
	var skinned := read(model)
	var surfaces := []
	var looks := {}
	if not skinned.has("reason"):
		surfaces = skinned.surfaces.map(func(s): return s.merged({ "bones": PackedInt32Array(), "weights": PackedFloat32Array(), "per": 0 }, true))
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or (mi.skin != null and not skinned.has("reason")):
			continue
		if not skinned.has("reason") and mi.skin == null and _on_skeleton(mi, model):
			continue
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES:
				var arrays := mi.mesh.surface_get_arrays(s)
				arrays[Mesh.ARRAY_BONES] = null
				arrays[Mesh.ARRAY_WEIGHTS] = null
				var none: Array[Transform3D] = []
				surfaces.append(_surface(arrays, PackedInt32Array(), none, StudioRig.placement(mi, model), look(_material(mi, s), looks)))
	if surfaces.is_empty():
		return { "reason": "it has no mesh" }
	return { "surfaces": surfaces }

## Whether read() already took this unskinned mesh, as a part on a skeleton.
static func _on_skeleton(mi: Node, model: Node) -> bool:
	return not model.find_children("*", "Skeleton3D", true, false).is_empty()

static func _material(mi: MeshInstance3D, s: int) -> Material:
	var material: Material = mi.get_surface_override_material(s)
	if material == null:
		material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(s)
	return material

## What a piece keeps of a material: its base colour and texture (as an
## Image), how it's see-through, which faces it draws, and its UV scale and
## offset. Other maps are left behind. One look per material and one image
## per texture, kept in `looks`.
static func look(material: Material, looks: Dictionary) -> Dictionary:
	if looks.has(material):
		return looks[material]
	var out := { "color": Color.WHITE, "image": null, "transparency": BaseMaterial3D.TRANSPARENCY_DISABLED, "scissor": 0.5,
		"cull": BaseMaterial3D.CULL_BACK, "uv_scale": Vector2.ONE, "uv_offset": Vector2.ZERO }
	if material is BaseMaterial3D:
		out.color = material.albedo_color
		out.transparency = material.transparency
		out.scissor = material.alpha_scissor_threshold
		out.cull = material.cull_mode
		out.uv_scale = Vector2(material.uv1_scale.x, material.uv1_scale.y)
		out.uv_offset = Vector2(material.uv1_offset.x, material.uv1_offset.y)
		var texture: Texture2D = material.albedo_texture
		if texture and not looks.has(texture):
			var image: Image = texture.get_image()
			if image:
				image = image.duplicate()
				if image.is_compressed():
					image.decompress()
			looks[texture] = image
		out.image = looks.get(texture) if texture else null
	looks[material] = out
	return out

static func _surface(arrays: Array, binds: PackedInt32Array, matrices: Array[Transform3D], place: Transform3D, look: Dictionary) -> Dictionary:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
	var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var n := verts.size()
	var per := bone_ids.size() / n if n > 0 else 0
	var out_verts := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_bones := PackedInt32Array()
	out_verts.resize(n)
	out_normals.resize(n)
	out_bones.resize(n * per)
	for v in n:
		var x := Vector3.ZERO
		var y := Vector3.ZERO
		var z := Vector3.ZERO
		var o := Vector3.ZERO
		var total := 0.0
		for k in per:
			var w := weights[v * per + k]
			var bind := bone_ids[v * per + k]
			out_bones[v * per + k] = binds[bind] if w > 0.0 and bind < binds.size() else -1
			if w <= 0.0 or bind >= matrices.size():
				continue
			var m: Transform3D = matrices[bind]
			x += m.basis.x * w
			y += m.basis.y * w
			z += m.basis.z * w
			o += m.origin * w
			total += w
		var skin := Transform3D(Basis(x, y, z), o) if total > 0.0 else Transform3D()
		out_verts[v] = place * (skin * verts[v])
		if not normals.is_empty():
			out_normals[v] = ((place.basis * skin.basis).inverse().transposed() * normals[v]).normalized()
	return { "verts": out_verts, "normals": out_normals if not normals.is_empty() else PackedVector3Array(), "uvs": uvs,
		"indices": indices, "bones": out_bones, "weights": weights, "per": per, "look": look }
