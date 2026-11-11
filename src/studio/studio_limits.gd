class_name StudioLimits
## Brings a piece within the checker's limits before it's written, and says
## in words what that changed: surfaces that look alike become one, textures
## shrink to the largest side allowed, too many textures are combined into
## one, and too many faces are reduced (meshoptimizer, through Godot's LOD
## builder). Everything is plain data, so it runs on any thread.

const IMAGES := 8
const MATERIALS := 16
## Pixels left around each texture in a combined one, so mipmaps don't bleed.
const PAD := 4

## { notes } or { reason }. `limit` is PieceCheck.LIMITS[kind]; the piece's
## surfaces change in place.
static func fit(piece: Dictionary, limit: Dictionary) -> Dictionary:
	var notes := []
	for s in piece.surfaces:
		_fill(s)
	_merge(piece)
	var reason := _atlas(piece, int(limit.texture), notes)
	if reason != "":
		return { "reason": reason }
	_shrink(piece, int(limit.texture), notes)
	_faces(piece, int(limit.faces), notes)
	if piece.surfaces.size() > MATERIALS:
		return { "reason": "it has %d different materials; a piece may have %d" % [piece.surfaces.size(), MATERIALS] }
	return { "notes": notes }

## Every surface gets normals and UVs, its look's UV scale and offset applied.
static func _fill(s: Dictionary) -> void:
	var n: int = s.verts.size()
	if s.uvs.size() != n:
		s.uvs = PackedVector2Array()
		s.uvs.resize(n)
	var look: Dictionary = s.look
	if look.uv_scale != Vector2.ONE or look.uv_offset != Vector2.ZERO:
		var uvs: PackedVector2Array = s.uvs.duplicate()
		for v in n:
			uvs[v] = uvs[v] * look.uv_scale + look.uv_offset
		s.uvs = uvs
		s.look = look.merged({ "uv_scale": Vector2.ONE, "uv_offset": Vector2.ZERO }, true)
	if s.normals.size() != n:
		var normals := PackedVector3Array()
		normals.resize(n)
		for t in range(0, s.indices.size(), 3):
			var a: int = s.indices[t]
			var b: int = s.indices[t + 1]
			var c: int = s.indices[t + 2]
			var face: Vector3 = (s.verts[b] - s.verts[a]).cross(s.verts[c] - s.verts[a])
			normals[a] += face
			normals[b] += face
			normals[c] += face
		for v in n:
			normals[v] = normals[v].normalized() if normals[v].length_squared() > 0.0 else Vector3.UP
		s.normals = normals

## Surfaces with the same look become one.
static func _merge(piece: Dictionary) -> void:
	var by_look := {}
	for s in piece.surfaces:
		var look := key(s.look)
		if not by_look.has(look):
			by_look[look] = s.duplicate()
			continue
		var into: Dictionary = by_look[look]
		var offset: int = into.verts.size()
		var indices: PackedInt32Array = s.indices.duplicate()
		for i in indices.size():
			indices[i] += offset
		into.verts = into.verts + s.verts
		into.normals = into.normals + s.normals
		into.uvs = into.uvs + s.uvs
		into.bones = into.bones + s.bones
		into.weights = into.weights + s.weights
		into.indices = into.indices + indices
	piece.surfaces = by_look.values()

static func key(look: Dictionary) -> String:
	return "%s|%d|%d|%d|%.3f" % [look.color.to_html(), look.image.get_instance_id() if look.image else 0, look.transparency, look.cull, look.scissor]

static func _images(piece: Dictionary) -> Array:
	var out := []
	for s in piece.surfaces:
		if s.look.image and not s.look.image in out:
			out.append(s.look.image)
	return out

## More textures than a piece may have are drawn into one, each in its own
## cell, and their surfaces' UVs moved into those cells. Textures that repeat
## across their surface (UVs outside 0 to 1) keep their own.
static func _atlas(piece: Dictionary, side: int, notes: Array) -> String:
	var images := _images(piece)
	if images.size() <= IMAGES:
		return ""
	var tiled := []
	for s in piece.surfaces:
		if s.look.image:
			for uv in s.uvs:
				if uv.x < -0.001 or uv.y < -0.001 or uv.x > 1.001 or uv.y > 1.001:
					tiled.append(s.look.image)
					break
	var cells := images.filter(func(i): return not i in tiled)
	if tiled.size() + 1 > IMAGES:
		return "it has %d textures that repeat across their surfaces; a piece may have %d textures" % [tiled.size(), IMAGES]
	var across := ceili(sqrt(cells.size()))
	var biggest := 0
	for image in cells:
		biggest = maxi(biggest, maxi(image.get_width(), image.get_height()))
	var cell := mini(nearest_po2(biggest), side / across)
	var atlas := Image.create(cell * across, cell * across, false, Image.FORMAT_RGBA8)
	var inner := cell - 2 * PAD
	var origin := {}
	for k in cells.size():
		var image: Image = cells[k].duplicate()
		image.convert(Image.FORMAT_RGBA8)
		image.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
		var at := Vector2i(k % across, k / across) * cell + Vector2i(PAD, PAD)
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
		origin[cells[k]] = at
	var size := float(atlas.get_width())
	for s in piece.surfaces:
		if not origin.has(s.look.image):
			continue
		var at: Vector2i = origin[s.look.image]
		var uvs: PackedVector2Array = s.uvs.duplicate()
		for v in uvs.size():
			uvs[v] = (Vector2(at) + uvs[v].clamp(Vector2.ZERO, Vector2.ONE) * inner) / size
		s.uvs = uvs
		s.look = s.look.merged({ "image": atlas }, true)
	_merge(piece)
	notes.append("Its %d textures are combined into one, %d pixels square." % [cells.size(), atlas.get_width()])
	return ""

## Textures no larger than the piece's limit, and no more of them (decoded)
## than four full-size maps.
static func _shrink(piece: Dictionary, side: int, notes: Array) -> void:
	var images := _images(piece)
	var pixels := 0
	for image in images:
		pixels += image.get_width() * image.get_height()
	var budget := float(PieceCheck.MAPS * side * side)
	var scale := sqrt(budget / pixels) if pixels > budget else 1.0
	var shrunk := false
	for image: Image in images:
		var largest := maxi(image.get_width(), image.get_height())
		var by := minf(scale, float(side) / largest)
		if by < 1.0:
			if image.is_compressed():
				image.decompress()
			image.resize(maxi(1, int(image.get_width() * by)), maxi(1, int(image.get_height() * by)), Image.INTERPOLATE_LANCZOS)
			shrunk = true
	if shrunk:
		notes.append("Its textures are made smaller, to fit a piece's limits.")

## Too many faces: each surface keeps the most detailed of its reduced
## versions that brings the whole within the limit.
static func _faces(piece: Dictionary, most: int, notes: Array) -> void:
	var total := 0
	for s in piece.surfaces:
		total += s.indices.size() / 3
	if total <= most:
		return
	var share := float(most) * 0.98 / total
	var kept := 0
	for s in piece.surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_INDEX] = s.indices
		var mesh := ImporterMesh.new()
		mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.generate_lods(25.0, 60.0, [])
		var want := int(s.indices.size() / 3 * share)
		var best: PackedInt32Array = s.indices
		for lod in mesh.get_surface_lod_count(0):
			best = mesh.get_surface_lod_indices(0, lod)
			if best.size() / 3 <= want:
				break
		_keep(s, best)
		kept += s.indices.size() / 3
	notes.append("It had %d faces; Studio kept %d, as a piece may have %d." % [total, kept, most])

## A surface's triangles replaced, and the vertices they no longer use dropped.
static func _keep(s: Dictionary, indices: PackedInt32Array) -> void:
	var renumber := PackedInt32Array()
	renumber.resize(s.verts.size())
	renumber.fill(-1)
	var used := PackedInt32Array()
	for i in indices:
		if renumber[i] < 0:
			renumber[i] = used.size()
			used.append(i)
	var out := { "verts": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(), "bones": PackedInt32Array(), "weights": PackedFloat32Array() }
	for v in used:
		out.verts.append(s.verts[v])
		out.normals.append(s.normals[v])
		out.uvs.append(s.uvs[v])
		for k in 4:
			out.bones.append(s.bones[v * 4 + k])
			out.weights.append(s.weights[v * 4 + k])
	var remapped := PackedInt32Array()
	remapped.resize(indices.size())
	for i in indices.size():
		remapped[i] = renumber[indices[i]]
	s.merge(out, true)
	s.indices = remapped
