class_name StudioExport
## Writes a piece Studio made: its scene, its .glb through Godot's own glTF
## writer, and its folder. Main thread only: it builds nodes and resources.

## The piece's scene: a skeleton with the skinned mesh under it and the
## clips beside it. The yard extras go on the root node, as glTF keeps
## extras on nodes but drops them from a Skeleton3D.
static func scene(piece: Dictionary, kind: String) -> Node3D:
	var rig: Dictionary = piece.rig
	var root := Node3D.new()
	root.name = "piece"
	root.set_meta("extras", { "yard": piece.yard })
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	skeleton.owner = root
	for i in rig.names.size():
		skeleton.add_bone(rig.names[i])
	for i in rig.names.size():
		skeleton.set_bone_parent(i, rig.parents[i])
		skeleton.set_bone_rest(i, rig.rests[i])
		skeleton.reset_bone_pose(i)
	var mesh := ArrayMesh.new()
	var materials := {}
	for s in piece.surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		if not s.normals.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = s.normals
		if not s.uvs.is_empty():
			arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_BONES] = s.bones
		arrays[Mesh.ARRAY_WEIGHTS] = s.weights
		arrays[Mesh.ARRAY_INDEX] = s.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var key := StudioLimits.key(s.look)
		if not materials.has(key):
			materials[key] = material(s.look)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
	var body := MeshInstance3D.new()
	body.name = kind
	body.mesh = mesh
	skeleton.add_child(body)
	body.owner = root
	body.skeleton = NodePath("..")
	var skin := Skin.new()
	var globals := StudioRig.rest_globals(rig)
	for i in rig.names.size():
		skin.add_named_bind(rig.names[i], globals[i].affine_inverse())
	body.skin = skin
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.owner = root
	player.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	for clip in piece.clips:
		library.add_animation(clip, piece.clips[clip])
	player.add_animation_library("", library)
	return root

## A plain material from a look (StudioSource.look).
static func material(look: Dictionary) -> StandardMaterial3D:
	var out := StandardMaterial3D.new()
	out.albedo_color = look.color
	out.transparency = look.transparency
	out.alpha_scissor_threshold = look.scissor
	out.cull_mode = look.cull
	if look.image:
		out.albedo_texture = ImageTexture.create_from_image(look.image)
	return out

static func write_glb(root: Node, path: String) -> Error:
	var doc := GLTFDocument.new()
	doc.image_format = "Lossy WebP"
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	return doc.write_to_filesystem(state, path) if err == OK else err

static func names() -> Array:
	var out: Array = ["piece.json"] + PieceLibrary.PREVIEWS
	for kind in PieceLibrary.FILES:
		out += PieceLibrary.FILES[kind]
	return out

static func other(folder: String) -> String:
	if not DirAccess.dir_exists_absolute(folder):
		return ""
	var dirs := DirAccess.get_directories_at(folder)
	if not dirs.is_empty():
		return dirs[0]
	for file in DirAccess.get_files_at(folder):
		if not file in names():
			return file
	return ""

## A piece folder Looks takes in: its model (a character's one, or a
## companion's four, in order) and piece.json.
static func save(models: Array, folder: String, manifest: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(folder)
	for k in models.size():
		var file: String = PieceLibrary.FILES[manifest.kind][k]
		if write_glb(models[k], folder.path_join(file)) != OK:
			return "its model could not be written to %s" % folder
	var json := FileAccess.open(folder.path_join("piece.json"), FileAccess.WRITE)
	if json == null:
		return "its piece.json could not be written to %s" % folder
	json.store_string(StrictJson.stringify(manifest, " "))
	return ""
