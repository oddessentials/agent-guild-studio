class_name StudioRecolour
## Changes a piece's colours: a piece made from a model (painted), or one of
## a world's own looks, a character's for its slot or a set of four helpers
## for its companions (dress). Every colour a material shows by changes, its
## base colour and its glow, as a value and as a texture; the mesh and clips
## are untouched.
##
## A change is { pick, spread, hue, tint }: the colour to change (`pick`, a
## Color; none for all of it) and how near a colour must be to count
## (`spread`, 0 to 1), then its hue turned (`hue`, degrees) and/or a colour
## laid over it (`tint`). Pixels near the pick change fully, fading out
## towards the spread's edge. With a pick and a tint, the picked colour
## becomes the tint, brightness and all, and its shading follows.
##
## Threads: recolour() works on Images and runs anywhere; dress() swaps
## textures on a model outside the tree.

## Bits per channel of the table every pixel looks its change up in.
const BITS := 6
## A preview's table, quicker to make.
const PREVIEW_BITS := 5
## How far apart the swatches offered to change are, and how many of a
## surface's vertices are read to find them.
const SWATCH_APART := 0.12
const SWATCH_SAMPLES := 20000

## The slot's own looks that can be recoloured: a character's three looks
## (look0 is the base model), or a world's agent or shell helper sets.
static func sources(where: Dictionary) -> Array:
	var world: Dictionary = YardModel.WORLDS[where.world]
	if where.kind == "character":
		var base: String = world.characters + str(YardModel.characterIndex(where.crew))
		return ["look0", "look1", "look2"].filter(func(l): return StudioArt.model_path(where.world, _look_name(base, l)) != "")
	return ["agent", "shell"]

## The shipped models a recolour starts from, outside the tree: one for a
## character, four for companions; or { reason }.
static func models(where: Dictionary, which: String) -> Dictionary:
	var world: Dictionary = YardModel.WORLDS[where.world]
	var names := []
	if where.kind == "character":
		var base: String = world.characters + str(YardModel.characterIndex(where.crew))
		if not which in ["look0", "look1", "look2"]:
			return { "reason": "a character is recolored from look0, look1 or look2" }
		names = [_look_name(base, which)]
	else:
		if not which in ["agent", "shell"]:
			return { "reason": "companions are recolored from the agent or shell helpers" }
		for k in 4:
			names.append(String(world.helpers[which]) + str(k))
	var out := []
	for name in names:
		var path := StudioArt.model_path(where.world, name)
		if path == "":
			for m in out:
				m.free()
			return { "reason": "%s is not in this build" % name }
		out.append((load(path) as PackedScene).instantiate())
	return { "models": out }

static func _look_name(base: String, which: String) -> String:
	return base if which == "look0" else "%s_%s" % [base, which]

## The model's colors changed, on its own copies of its materials (the
## shipped ones are the world's too), and every texture it has made plain
## (decompressed) so the glTF writer can take it. Outside the tree. With
## `most`, for a preview: only the textures that show color, at most that
## many pixels a side.
static func dress(model: Node, change: Dictionary, most := 0) -> void:
	var done := {}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var material := mi.get_active_material(s)
			if not material is BaseMaterial3D:
				continue
			if not done.has(material):
				done[material] = material.duplicate()
				_dress(done[material], change, most)
			mi.set_surface_override_material(s, done[material])

const COLORED := ["albedo_texture", "emission_texture"]

static func _dress(material: BaseMaterial3D, change: Dictionary, most: int) -> void:
	material.albedo_color = _keep_alpha(changed(material.albedo_color, change), material.albedo_color)
	if material.emission_enabled:
		material.emission = changed(material.emission, change)
	for slot in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture", "orm_texture"]:
		if not slot in material or (most > 0 and not slot in COLORED):
			continue
		var texture: Texture2D = material.get(slot)
		var image := _plain(texture, most) if texture else null
		if image == null:
			continue
		if slot in COLORED:
			image = recolour(image, change, PREVIEW_BITS if most > 0 else BITS)
		material.set(slot, ImageTexture.create_from_image(image))

static func _keep_alpha(c: Color, from: Color) -> Color:
	return Color(c.r, c.g, c.b, from.a)

## A change as read back from a recipe or a tool's words: its colors, kept
## there as #RRGGBB, as colors.
static func read(change: Dictionary) -> Dictionary:
	var out := change.duplicate()
	for key in ["pick", "tint"]:
		if out.get(key) is String:
			out[key] = Color(out[key])
	return out

## A change as a recipe keeps it: its colors as #RRGGBB.
static func written(change: Dictionary) -> Dictionary:
	var out := change.duplicate()
	for key in ["pick", "tint"]:
		if out.get(key) is Color:
			out[key] = "#" + out[key].to_html(false)
	return out

## Whether the change changes nothing.
static func plain(change: Dictionary) -> bool:
	return float(change.get("hue", 0.0)) == 0.0 and not change.get("tint") is Color

## Pieces made from a model (plain data, Studio.make's) with the change made
## to every surface's color and image; the pieces given are left as they
## were. With `most`, for a preview: images at most that many pixels a side.
## Any thread.
static func painted(pieces: Array, change: Dictionary, most := 0) -> Array:
	if plain(change):
		return pieces
	var images := {}
	var out := []
	for piece: Dictionary in pieces:
		var copy := piece.duplicate()
		copy.surfaces = []
		for s: Dictionary in piece.surfaces:
			var look: Dictionary = s.look.duplicate()
			look.color = _keep_alpha(changed(look.color, change), look.color)
			var image: Image = look.get("image")
			if image:
				if not images.has(image):
					var small: Image = image
					if most > 0 and maxi(image.get_width(), image.get_height()) > most:
						small = image.duplicate()
						if small.is_compressed():
							small.decompress()
						small.clear_mipmaps()
						var side := maxi(small.get_width(), small.get_height())
						small.resize(maxi(1, small.get_width() * most / side), maxi(1, small.get_height() * most / side), Image.INTERPOLATE_BILINEAR)
					images[image] = recolour(small, change, PREVIEW_BITS if most > 0 else BITS)
				look.image = images[image]
			var surface := s.duplicate()
			surface.look = look
			copy.surfaces.append(surface)
		out.append(copy)
	return out

## Base colors decompressed and made smaller, kept while Studio is open: a
## preview's every change starts from them.
static var _plains := {}

## The texture's image, decompressed, at most `most` pixels a side (0: as is).
static func _plain(texture: Texture2D, most: int) -> Image:
	var key := [texture.get_instance_id(), most]
	if _plains.has(key):
		return _plains[key]
	var image := texture.get_image()
	if image == null:
		return null
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	if most > 0:
		image.clear_mipmaps()
		var side := maxi(image.get_width(), image.get_height())
		if side > most:
			image.resize(maxi(1, image.get_width() * most / side), maxi(1, image.get_height() * most / side), Image.INTERPOLATE_BILINEAR)
		_plains[key] = image
	return image

static func forget() -> void:
	_plains.clear()

## The models' main base colors, most used first, as they are before any
## change: read where the mesh shows them (at its vertices' UVs), each at
## least SWATCH_APART from the ones before it, colored shades before gray
## ones; from images at most `most` pixels a side.
static func palette(models: Array, most: int, count := 6) -> Array:
	var cells := {}
	for model: Node in models:
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var material := mi.get_active_material(s)
				var texture: Texture2D = material.albedo_texture if material is BaseMaterial3D else null
				var uvs = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV] if texture else null
				if uvs == null:
					continue
				var image := _plain(texture, most)
				var size := Vector2(image.get_size())
				var step := maxi(1, uvs.size() / SWATCH_SAMPLES)
				for i in range(0, uvs.size(), step):
					var uv: Vector2 = uvs[i]
					var c := image.get_pixelv(Vector2i((Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0)) * size).floor().clamp(Vector2.ZERO, size - Vector2.ONE)))
					var key := (int(c.r * 15.0) << 8) | (int(c.g * 15.0) << 4) | int(c.b * 15.0)
					var cell: Array = cells.get(key, [0, Vector3.ZERO])
					cell[0] += 1
					cell[1] += Vector3(c.r, c.g, c.b)
					cells[key] = cell
	var ranked := cells.values()
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for cell in ranked:
		var mean: Vector3 = cell[1] / float(cell[0])
		var c := Color(mean.x, mean.y, mean.z)
		if out.all(func(o: Color): return Vector3(o.r - c.r, o.g - c.g, o.b - c.b).length() / sqrt(3.0) >= SWATCH_APART):
			out.append(c)
		if out.size() == count:
			break
	# A hue turns only a colored shade: those come first.
	var colored := out.filter(func(c: Color): return c.s >= 0.2 and c.v >= 0.15)
	return colored + out.filter(func(c): return not c in colored)

## The image with the change made.
static func recolour(image: Image, change: Dictionary, bits := BITS) -> Image:
	var out := image.duplicate()
	if out.is_compressed():
		out.decompress()
	out.clear_mipmaps()
	out.convert(Image.FORMAT_RGBA8)
	var table := _table(change, bits)
	var data: PackedByteArray = out.get_data()
	var shift := 8 - bits
	for i in range(0, data.size(), 4):
		var at: int = (((data[i] >> shift) << (2 * bits)) | ((data[i + 1] >> shift) << bits) | (data[i + 2] >> shift)) * 3
		data[i] = clampi(data[i] + table[at], 0, 255)
		data[i + 1] = clampi(data[i + 1] + table[at + 1], 0, 255)
		data[i + 2] = clampi(data[i + 2] + table[at + 2], 0, 255)
	return Image.create_from_data(out.get_width(), out.get_height(), false, Image.FORMAT_RGBA8, data)

## What each colour (to `bits` a channel) becomes, as a change to add.
static func _table(change: Dictionary, bits := BITS) -> PackedInt32Array:
	var cells := 1 << bits
	var table := PackedInt32Array()
	table.resize(cells * cells * cells * 3)
	var half := 0.5 / cells
	for r in cells:
		for g in cells:
			for b in cells:
				var c := Color(float(r) / cells + half, float(g) / cells + half, float(b) / cells + half)
				var to := changed(c, change)
				var at := ((r << (2 * bits)) | (g << bits) | b) * 3
				table[at] = roundi((to.r - c.r) * 255.0)
				table[at + 1] = roundi((to.g - c.g) * 255.0)
				table[at + 2] = roundi((to.b - c.b) * 255.0)
	return table

## One colour with the change made, as much as it is near the pick.
static func changed(c: Color, change: Dictionary) -> Color:
	var share := 1.0
	if change.get("pick") is Color:
		var spread := maxf(float(change.get("spread", 0.15)), 1e-3)
		var p: Color = change.pick
		var near := Vector3(c.r - p.r, c.g - p.g, c.b - p.b).length() / sqrt(3.0)
		share = 1.0 - smoothstep(spread * 0.5, spread, near)
	if share <= 0.0:
		return c
	var to := c
	var hue := float(change.get("hue", 0.0))
	if hue != 0.0:
		to = Color.from_hsv(fposmod(c.h + hue / 360.0, 1.0), c.s, c.v)
	if change.get("tint") is Color:
		var tint: Color = change.tint
		if change.get("pick") is Color:
			# The picked color becomes the tint: lighter by their difference,
			# or darker by their ratio, so its shading keeps its shape.
			var from: float = change.pick.v
			var value := to.v + tint.v - from if tint.v >= from else to.v * tint.v / maxf(from, 1e-3)
			to = Color.from_hsv(tint.h, tint.s, clampf(value, 0.0, 1.0))
		else:
			to = Color.from_hsv(tint.h, lerpf(to.s, tint.s, 0.85), to.v * lerpf(1.0, tint.v, 0.5))
	return Color(c.lerp(to, share), c.a)
