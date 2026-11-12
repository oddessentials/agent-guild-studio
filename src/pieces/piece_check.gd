class_name PieceCheck

# premium.json's detail plus 5%: held props and TRELLIS.2's overshoot put our own premium models just over it.
const LIMITS := {
	"character": { "faces": 210000, "texture": 4096, "file": 128 << 20 },
	"companion": { "faces": 63000, "texture": 2048, "file": 48 << 20 },
}
const MAPS := 4
const JSON_MAX := 1 << 20
const COUNTS := { "nodes": 256, "meshes": 16, "materials": 16, "textures": 16, "images": 8, "samplers": 16,
	"animations": 16, "accessors": 2048, "bufferViews": 2048, "skins": 2, "buffers": 1 }
const DEPTH := 32
const JOINTS := 128
const EXTENSIONS := ["EXT_texture_webp", "KHR_texture_basisu", "KHR_texture_transform", "KHR_materials_emissive_strength"]
const CLIPS := {
	"character": ["walk", "work_0", "work_1", "pause", "idle_0", "idle_1", "idle_2", "done"],
	"companion": ["idle", "working", "waiting", "done", "move"],
}
const TRUNK := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]
const CLIP_SLACK := 1.0 / 24.0
const TIMEOUT := 30.0

# A model brought to Studio, before Studio fits it to the limits above.
const SOURCE := { "faces": 2000000, "texture": 8192, "file": 256 << 20, "memory": 1 << 30, "files": 64, "beside": 512 << 20 }
const SOURCE_COUNTS := { "nodes": 8192, "meshes": 1024, "materials": 1024, "textures": 1024, "images": 256, "samplers": 1024,
	"animations": 1024, "accessors": 65536, "bufferViews": 65536, "skins": 64, "buffers": 64 }
const SOURCE_DEPTH := 256
const SOURCE_JOINTS := 2048
const SOURCE_BUFFERS := ["bin"]
const SOURCE_IMAGES := ["png", "jpg", "jpeg", "webp"]
const SOURCE_TIMEOUT := 60.0

const _SIZES := { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 }
const _WIDTHS := { "SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16 }

static func check_file(path: String, kind: String, clips: Dictionary, headers := true) -> Dictionary:
	if not LIMITS.has(kind):
		return { "reason": "it is not a character or a companion" }
	if headers:
		var reason := check_headers(path, kind)
		if reason != "":
			return { "reason": reason }
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return { "reason": "it is not a glTF model Godot can read" }
	var root := doc.generate_scene(state)
	if root == null:
		return { "reason": "it is not a glTF model Godot can read" }
	var failures := rigged(root, kind)
	if failures.is_empty():
		failures = clip_lengths(root, clips)
	root.free()
	return { "reason": failures[0] if not failures.is_empty() else "" }

static func check_headers(path: String, kind: String) -> String:
	return _headers(path, kind, [])

# { reason, files }: `files` are the buffers and images the model names, as paths from its folder.
static func check_source(path: String) -> Dictionary:
	var files := []
	return { "reason": _headers(path, "source", files), "files": files }

static func _headers(path: String, kind: String, files: Array) -> String:
	var studio := kind == "source"
	var limit: Dictionary = SOURCE if studio else LIMITS[kind]
	var counts: Dictionary = SOURCE_COUNTS if studio else COUNTS
	var what := "model" if studio else kind
	var folder := path.get_base_dir()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "the file cannot be read"
	var size := file.get_length()
	if size > limit.file:
		return "the file is over %d MB" % (limit.file >> 20)
	var data := file.get_buffer(size)
	var text := data
	var bin := PackedByteArray()
	# Godot reads a file as binary glTF by these four bytes, whatever its name; anything else as glTF JSON.
	if not studio or (size >= 4 and data.decode_u32(0) == 0x46546C67):
		if size < 20 or data.decode_u32(0) != 0x46546C67 or data.decode_u32(4) != 2 or data.decode_u32(8) != size:
			return "it is not a complete binary glTF (.glb) file"
		var json_len := data.decode_u32(12)
		if data.decode_u32(16) != 0x4E4F534A or (not studio and json_len > JSON_MAX) or 20 + json_len > size:
			return "its glTF JSON is missing or over %d KB" % (JSON_MAX >> 10)
		var at := 20 + json_len
		if at + 8 <= size:
			var bin_len := data.decode_u32(at)
			if data.decode_u32(at + 4) != 0x004E4942 or at + 8 + bin_len > size:
				return "its binary chunk is damaged"
			bin = data.slice(at + 8, at + 8 + bin_len)
		text = data.slice(20, 20 + json_len)
	var gltf = JSON.parse_string(text.get_string_from_utf8())
	if not gltf is Dictionary:
		return "its glTF JSON cannot be read"
	for key in counts:
		var list = gltf.get(key, [])
		if not list is Array:
			return "its %s are malformed" % key
		if list.size() > counts[key]:
			return "it has more than %d %s" % [counts[key], key]
	if not studio:
		for ext in gltf.get("extensionsRequired", []):
			if not ext in EXTENSIONS:
				return "it needs the glTF extension %s, which Agent Guild: World does not support" % ext
	var beside := [0]
	var held: Array[PackedByteArray] = []
	for buffer in gltf.get("buffers", []):
		var bytes := bin if held.is_empty() else PackedByteArray()
		if buffer.has("uri"):
			if not studio:
				return "it refers to data outside the file"
			var named = _named(buffer.uri, folder, SOURCE_BUFFERS, files, beside)
			if named is String:
				return named
			bytes = named
		if int(buffer.get("byteLength", 0)) > bytes.size():
			return "it refers to data outside the file"
		held.append(bytes)
	var views: Array = gltf.get("bufferViews", [])
	for view in views:
		var buffer := int(view.get("buffer", -1))
		if buffer < 0 or buffer >= held.size() or int(view.get("byteOffset", 0)) < 0 or int(view.get("byteLength", -1)) < 0 \
				or int(view.get("byteOffset", 0)) + int(view.byteLength) > held[buffer].size():
			return "its data views reach past its data"
	var accessors: Array = gltf.get("accessors", [])
	var unbacked := 0
	for a in accessors:
		var own: bool = a.has("bufferView")
		if (not studio and (a.has("sparse") or not own)) or (own and (int(a.bufferView) < 0 or int(a.bufferView) >= views.size())):
			return "an accessor has no data of its own"
		var width: int = _SIZES.get(int(a.get("componentType", 0)), 0) * _WIDTHS.get(a.get("type", ""), 0)
		var count := int(a.get("count", -1))
		if width == 0 or count < 0 or count > 4 * int(limit.faces):
			return "an accessor reaches past its data"
		if not own:
			# Godot fills an accessor with no data of its own with zeros.
			unbacked += count * width
			continue
		var view: Dictionary = views[int(a.bufferView)]
		var stride := maxi(int(view.get("byteStride", 0)), width)
		if count > 0 and int(a.get("byteOffset", 0)) + stride * (count - 1) + width > int(view.byteLength):
			return "an accessor reaches past its data"
	if unbacked > limit.file:
		return "its accessors would take %d MB with no data of their own" % (unbacked >> 20)
	var faces := 0
	for mesh in gltf.get("meshes", []):
		for p in mesh.get("primitives", []):
			var source = p.get("indices", p.get("attributes", {}).get("POSITION", -1))
			var triangles := int(p.get("mode", 4)) == 4
			if (not studio and not triangles) or int(source) < 0 or int(source) >= accessors.size():
				return "a mesh is not made of triangles"
			if triangles:
				faces += int(accessors[int(source)].count) / 3
	if faces > limit.faces:
		return "it has %d faces; a %s may have %d" % [faces, what, limit.faces]
	var reason := _check_nodes(gltf, SOURCE_DEPTH if studio else DEPTH, SOURCE_JOINTS if studio else JOINTS, studio)
	if reason != "":
		return reason
	var decoded := 0
	for image in gltf.get("images", []):
		var bytes: PackedByteArray
		if image.has("uri"):
			if not studio:
				return "it refers to an image outside the file"
			var named = _named(image.uri, folder, SOURCE_IMAGES, files, beside)
			if named is String:
				return named
			bytes = named
		elif not image.has("bufferView") or int(image.bufferView) < 0 or int(image.bufferView) >= views.size():
			return "it refers to an image outside the file"
		else:
			var view: Dictionary = views[int(image.bufferView)]
			bytes = held[int(view.buffer)].slice(int(view.get("byteOffset", 0)), int(view.get("byteOffset", 0)) + int(view.byteLength))
		var dims := image_size(bytes)
		if dims == Vector2i.ZERO:
			return "an image is not PNG, JPEG, WebP or KTX2"
		if dims.x > limit.texture or dims.y > limit.texture:
			return "an image is %d × %d; a %s's may be at most %d" % [dims.x, dims.y, what, limit.texture]
		decoded += dims.x * dims.y * 4 if studio else dims.x * dims.y * 16 / 3
	var most: int = limit.memory if studio else MAPS * limit.texture * limit.texture * 16 / 3
	if decoded > most:
		return "its images would take %d MB; a %s's may take %d MB" % [decoded >> 20, what, most >> 20]
	return ""

# The bytes `uri` names, or (a String) why not. The name is decoded as Godot's glTF loader decodes it, so the file
# checked here is the file it opens.
static func _named(uri, folder: String, kinds: Array, files: Array, beside: Array):
	if not uri is String:
		return "it names a file in a way Studio cannot read"
	if uri.begins_with("data:"):
		return Marshalls.base64_to_raw(uri.substr(uri.find(",") + 1))
	var parts := PackedStringArray(Array(uri.uri_file_decode().split("/")).filter(func(part): return part != "."))
	var name := "/".join(parts)
	for i in name.length():
		if name.unicode_at(i) < 32:
			return "it names a file in a way Studio cannot read"
	if name.contains("\\") or name.contains(":") or parts.is_empty() or parts.has("") or parts.has(".."):
		return "it names %s, which is not a file in its own folder" % name
	if not name.get_extension().to_lower() in kinds:
		return "it names %s; beside a model, Studio reads .%s files" % [name, ", .".join(kinds)]
	var dir := DirAccess.open(folder)
	var at := ""
	for part in parts:
		at = at.path_join(part)
		if dir == null or dir.is_link(at):
			return "it names %s, which is a link" % name
	var file := FileAccess.open(folder.path_join(name), FileAccess.READ)
	if file == null:
		return "it names %s, which is not beside it" % name
	if not name in files:
		files.append(name)
		beside[0] += file.get_length()
		if files.size() > SOURCE.files:
			return "it names more than %d files beside it" % SOURCE.files
		if file.get_length() > SOURCE.file or beside[0] > SOURCE.beside:
			return "the files beside it are over %d MB" % (SOURCE.beside >> 20)
	return file.get_buffer(file.get_length())

static func _check_nodes(gltf: Dictionary, most_deep: int, most_joints: int, pointers: bool) -> String:
	var nodes: Array = gltf.get("nodes", [])
	var parent := {}
	for i in nodes.size():
		for c in nodes[i].get("children", []):
			if int(c) < 0 or int(c) >= nodes.size() or parent.has(int(c)) or int(c) == i:
				return "its node tree is malformed"
			parent[int(c)] = i
	for i in nodes.size():
		var depth := 1
		var n := i
		while parent.has(n):
			n = parent[n]
			depth += 1
			if depth > most_deep:
				return "its node tree is deeper than %d (or loops)" % most_deep
	for scene in gltf.get("scenes", []):
		for r in scene.get("nodes", []):
			if int(r) < 0 or int(r) >= nodes.size() or parent.has(int(r)):
				return "its node tree is malformed"
	for skin in gltf.get("skins", []):
		var joints: Array = skin.get("joints", [])
		if joints.size() > most_joints:
			return "a skin has more than %d joints" % most_joints
		for j in joints:
			if int(j) < 0 or int(j) >= nodes.size():
				return "a skin names a node that does not exist"
	for anim in gltf.get("animations", []):
		for c in anim.get("channels", []):
			if pointers and not c.get("target", {}).has("node") and c.get("target", {}).get("extensions", {}).has("KHR_animation_pointer"):
				continue
			var target = c.get("target", {}).get("node", -1)
			if int(target) < 0 or int(target) >= nodes.size():
				return "a clip moves a node that does not exist"
	return ""

static func image_size(b: PackedByteArray) -> Vector2i:
	var be := func(at: int, n: int) -> int:
		var v := 0
		for i in n:
			v = (v << 8) | b[at + i]
		return v
	if b.size() >= 24 and b.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return Vector2i(be.call(16, 4), be.call(20, 4))
	if b.size() >= 28 and b.slice(0, 12) == PackedByteArray([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A]):
		return Vector2i(b.decode_u32(20), maxi(1, b.decode_u32(24)))
	if b.size() >= 30 and b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP":
		match b.slice(12, 16).get_string_from_ascii():
			"VP8 ":
				return Vector2i(b.decode_u16(26) & 0x3FFF, b.decode_u16(28) & 0x3FFF)
			"VP8L":
				return Vector2i(1 + (b[21] | ((b[22] & 0x3F) << 8)), 1 + ((b[22] >> 6) | (b[23] << 2) | ((b[24] & 0x0F) << 10)))
			"VP8X":
				return Vector2i(1 + (b[24] | (b[25] << 8) | (b[26] << 16)), 1 + (b[27] | (b[28] << 8) | (b[29] << 16)))
		return Vector2i.ZERO
	if b.size() >= 4 and b[0] == 0xFF and b[1] == 0xD8:
		var at := 2
		while at + 9 < b.size():
			if b[at] != 0xFF:
				return Vector2i.ZERO
			var marker := b[at + 1]
			if marker >= 0xC0 and marker <= 0xCF and not marker in [0xC4, 0xC8, 0xCC]:
				return Vector2i(be.call(at + 7, 2), be.call(at + 5, 2))
			at += 2 + be.call(at + 2, 2)
	return Vector2i.ZERO

static func rigged(root: Node, kind: String) -> Array:
	var out := []
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return ["it has no skeleton"]
	var skeleton: Skeleton3D = skeletons.front()
	if (skeleton.find_bone("LeftUpperLeg") >= 0) != (kind == "character"):
		return ["it is not a %s" % kind]
	var profile := SkeletonProfileHumanoid.new()
	for i in profile.bone_size:
		var bone := profile.get_bone_name(i)
		if not profile.is_required(i) and skeleton.find_bone(bone) < 0:
			continue
		if kind == "companion" and not bone in TRUNK:
			continue
		var index := skeleton.find_bone(bone)
		if index < 0:
			out.append("it has no %s bone" % bone)
			continue
		var parent := profile.get_bone_parent(i)
		if parent != &"" and skeleton.get_bone_name(skeleton.get_bone_parent(index)) != parent:
			out.append("its %s bone is under %s, not %s" % [bone, skeleton.get_bone_name(skeleton.get_bone_parent(index)), parent])
	if kind == "character":
		for socket in ["PropLeft", "PropRight"]:
			if skeleton.find_bone(socket) < 0:
				out.append("it has no %s socket" % socket)
		var yard := YardRig.extras(root)
		for key in ["height", "stride", "cycle", "surface"]:
			if not yard.has(key) or float(yard[key]) <= 0.0:
				out.append("it has no yard.%s" % key)
	var players := root.find_children("*", "AnimationPlayer", true, false)
	var player: AnimationPlayer = null if players.is_empty() else players.front()
	for clip in CLIPS[kind]:
		if player == null or not player.has_animation(clip):
			out.append("it has no %s clip" % clip)
	return out

static func clip_lengths(root: Node, expected: Dictionary) -> Array:
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return []
	var player: AnimationPlayer = players.front()
	for clip in expected:
		if player.has_animation(clip) and absf(player.get_animation(clip).length - float(expected[clip])) > CLIP_SLACK:
			return ["its %s clip is %.2f s; the default's is %.2f s" % [clip, player.get_animation(clip).length, float(expected[clip])]]
	return []

static func clips_arg(clips: Dictionary) -> String:
	return ",".join(clips.keys().map(func(k): return "%s:%s" % [k, clips[k]]))

static func clips_from(arg: String) -> Dictionary:
	var out := {}
	for pair in arg.split(",", false):
		var kv := pair.split(":")
		if kv.size() == 2:
			out[kv[0]] = float(kv[1])
	return out

static var _done := false

static func run(options: Dictionary) -> int:
	var watchdog := Thread.new()
	watchdog.start(_watch.bind(Time.get_ticks_msec() + int(float(options.get("check-timeout", TIMEOUT)) * 1000) + 5000))
	if options.get("check-fault", "") == "crash":
		OS.kill(OS.get_process_id())
	var verdict: Dictionary
	if options.has("check-source"):
		verdict = StudioSource.check(options["check-source"], options.get("check-dir", ""))
	else:
		verdict = check_file(options["check-piece"], options.get("check-kind", ""), clips_from(options.get("check-clips", "")),
			options.get("check-stage", "") != "load")
	var file := FileAccess.open(options.get("check-out", ""), FileAccess.WRITE)
	if file:
		file.store_string(StrictJson.stringify(verdict))
		file.close()
	_done = true
	watchdog.wait_to_finish()
	return 0 if file else 1

static func _watch(deadline: int) -> void:
	while not _done and Time.get_ticks_msec() < deadline:
		OS.delay_msec(100)
	if not _done:
		OS.kill(OS.get_process_id())
