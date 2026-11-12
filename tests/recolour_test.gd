extends RefCounted
## The color rule on colors and materials made here, none of them a world's:
## a picked color becomes the chosen one, lighter or darker, with its shading
## kept in order; colors not picked stay; and every color a piece or a model
## shows by changes, as a value and as a texture, base color and glow.

var failures := []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

static func near(a: Color, b: Color, levels := 2.0) -> bool:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() <= levels / 255.0

func run(_tree: SceneTree) -> Array:
	var dark := Color8(12, 10, 10)
	var cream := Color8(232, 226, 208)
	var white := Color8(240, 240, 235)
	var navy := Color8(32, 40, 64)
	var green := Color8(40, 180, 60)
	var lighter := { "pick": dark, "spread": 0.15, "tint": cream }
	var darker := { "pick": white, "spread": 0.15, "tint": navy }
	check(near(StudioRecolour.changed(dark, lighter), cream), "a dark color changed to a light one became %s, not %s" % [StudioRecolour.changed(dark, lighter), cream])
	check(near(StudioRecolour.changed(white, darker), navy), "a light color changed to a dark one became %s, not %s" % [StudioRecolour.changed(white, darker), navy])
	var fold := StudioRecolour.changed(Color8(20, 18, 18), lighter)
	var crease := StudioRecolour.changed(Color8(6, 5, 5), lighter)
	check(fold.v > StudioRecolour.changed(dark, lighter).v and crease.v < StudioRecolour.changed(dark, lighter).v, "going lighter, the picked color's shades lost their order")
	var shade := StudioRecolour.changed(Color8(225, 225, 221), darker)
	check(shade.v < StudioRecolour.changed(white, darker).v and shade.v > 0.0, "going darker, the picked color's shades lost their order or went black")
	check(near(StudioRecolour.changed(green, lighter), green) and near(StudioRecolour.changed(green, darker), green), "a color far from the pick changed")
	var laid := StudioRecolour.changed(Color8(128, 128, 128), { "tint": cream })
	check(absf(laid.h - cream.h) < 0.02 and laid.v <= 0.51, "a color laid over everything changed more than the hue and a share of the brightness: %s" % laid)
	check(StudioRecolour.plain({ "hue": 0.0, "spread": 0.15 }) and not StudioRecolour.plain({ "hue": 0.0, "tint": cream }), "a change that changes nothing is not told from one that does")
	var back := StudioRecolour.read(JSON.parse_string(JSON.stringify(StudioRecolour.written(lighter))))
	check(near(back.pick, dark, 0.5) and near(back.tint, cream, 0.5), "a change did not come back from a recipe as it went in: %s" % back)

	var image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, dark)
	image.set_pixel(1, 0, green)
	var kept := image.duplicate()
	var piece := { "title": "made here", "surfaces": [
		{ "name": "cloth", "look": { "color": Color.WHITE, "image": image } },
		{ "name": "trim", "look": { "color": dark, "image": image } },
		{ "name": "plain", "look": { "color": Color(dark, 0.5), "image": null } } ] }
	var painted: Array = StudioRecolour.painted([piece], lighter)
	var cloth: Dictionary = painted[0].surfaces[0].look
	check(near(cloth.image.get_pixel(0, 0), cream, 6.0) and near(cloth.image.get_pixel(1, 0), green, 6.0), "a piece's texture did not take the change: %s %s" % [cloth.image.get_pixel(0, 0), cloth.image.get_pixel(1, 0)])
	check(near(painted[0].surfaces[1].look.color, cream) and near(painted[0].surfaces[2].look.color, cream) and is_equal_approx(painted[0].surfaces[2].look.color.a, 0.5),
		"a piece's plain colors did not take the change, or lost how see-through they are")
	check(painted[0].surfaces[0].look.image == painted[0].surfaces[1].look.image, "one texture two surfaces share was changed twice")
	check(image.get_data() == kept.get_data() and piece.surfaces[1].look.color == dark and painted[0].title == "made here", "changing a piece's colors changed the piece it was made from")
	check(StudioRecolour.painted([piece], { "hue": 0.0 })[0] == piece, "a change that changes nothing made a new piece")

	var material := StandardMaterial3D.new()
	material.albedo_color = dark
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.emission_enabled = true
	material.emission = dark
	material.emission_texture = ImageTexture.create_from_image(image)
	var box := BoxMesh.new()
	box.material = material
	var model := Node3D.new()
	var part := MeshInstance3D.new()
	part.mesh = box
	model.add_child(part)
	StudioRecolour.dress(model, lighter)
	var dressed: BaseMaterial3D = part.get_surface_override_material(0)
	check(dressed != null and near(dressed.albedo_color, cream) and near(dressed.albedo_texture.get_image().get_pixel(0, 0), cream, 6.0), "a model's base color did not take the change")
	check(dressed != null and near(dressed.emission, cream) and near(dressed.emission_texture.get_image().get_pixel(0, 0), cream, 6.0), "a model's glow did not take the change")
	check(material.albedo_color == dark and material.emission == dark, "changing a model's colors changed the material it shares")
	model.free()
	StudioRecolour.forget()
	return failures
