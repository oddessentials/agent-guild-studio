extends RefCounted

var failures := []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
	var previous_size := tree.root.size
	var app: Node = load("res://src/app/main.gd").new()
	tree.root.add_child(app)
	await _layout(tree)
	for world in YardModel.WORLDS:
		for mode in ["light", "dark"]:
			app.theme = mode
			app._set_world(world)
			app._connect_dialog("C:/Apps $x/it's/AgentGuildStudio.exe")
			await _layout(tree)
			var dialog: AcceptDialog = app.layer.get_node("ConnectAgentDialog")
			var fields := dialog.find_children("*", "TextEdit", true, false)
			var before := [] if OS.has_feature("template") else ["--path", ProjectSettings.globalize_path("res://").trim_suffix("/")]
			var commands: Array = app.connect_commands("C:/Apps $x/it's/AgentGuildStudio.exe", before)
			check(fields.size() == commands.size(), "%s/%s: the dialog lost a command" % [world, mode])
			for i in mini(fields.size(), commands.size()):
				var field: TextEdit = fields[i]
				check(field.text == commands[i][1] and not field.editable, "%s/%s: a displayed command changed" % [world, mode])
				var background: Color = app.skin.color("surface").blend(field.get_theme_stylebox("read_only").bg_color)
				var foreground := background.blend(field.get_theme_color("font_readonly_color"))
				check(_contrast(foreground, background) >= 4.5, "%s/%s: read-only command text lacks contrast" % [world, mode])
			for size in [Vector2i(1600, 900), Vector2i(1280, 800), Vector2i(960, 600), Vector2i(1000, 600)]:
				tree.root.size = size
				await _layout(tree)
				check(app.home.size.x <= 400.1 and app.panel.size.x <= 400.1, "%s/%s at %s: the sidebar expands over the preview" % [world, mode, size])
				check(Rect2(Vector2.ZERO, Vector2(size)).encloses(Rect2(Vector2(dialog.position), Vector2(dialog.size))), "%s/%s at %s: the connection dialog extends outside the window" % [world, mode, size])
			var copies := dialog.find_children("*", "Button", true, false).filter(func(b): return b.text == "Copy")
			check(copies.size() == commands.size(), "a connection command lost its Copy button")
			if not copies.is_empty():
				copies.back().grab_focus()
				await _layout(tree)
				var scroll: ScrollContainer = dialog.get_meta("scroll")
				check(scroll.get_global_rect().grow(1.0).encloses(copies.back().get_global_rect()), "%s/%s: the final Copy button %s is outside the scroll area %s" % [world, mode, copies.back().get_global_rect(), scroll.get_global_rect()])
				check(copies.all(func(b): return b.size.y < 60), "a Copy button stretches to the height of its command")
			dialog.queue_free()
			await _layout(tree)
	app.theme = "light"
	app._set_world("guild")
	tree.root.size = Vector2i(960, 600)
	var title := "Moonlit Clockwork Guardian with a deliberately long name for the character library"
	var slot := "The Guild Yard, Antigravity CLI crew"
	app.home.show_home("guild", "ready", 0, "", [{"id": "ui-example", "title": title, "slot": slot, "error": "", "saved": "C:/Characters/Guardian"}])
	await _layout(tree)
	var labels: Array = app.home.find_children("*", "Label", true, false)
	var names: Array = labels.filter(func(label): return label.text == title)
	var slots: Array = labels.filter(func(label): return label.text == slot)
	check(names.size() == 1 and slots.size() == 1, "the library does not show the title and slot separately")
	if names.size() == 1 and slots.size() == 1:
		check(title in names[0].tooltip_text and "C:/Characters/Guardian" in names[0].tooltip_text, "a long title or saved path is inaccessible")
		check(names[0].get_global_rect().end.x <= app.home.get_global_rect().end.x and slots[0].get_global_rect().end.x <= app.home.get_global_rect().end.x, "a library entry overflows the sidebar")
	check(app._empty_preview.visible and not app._preview_hint.visible, "the empty workspace has no guidance")
	for overlay in [app._empty_preview, app._preview_hint]:
		var controls: Array = [overlay] + overlay.find_children("*", "Control", true, false)
		check(controls.all(func(c): return c.mouse_filter == Control.MOUSE_FILTER_IGNORE), "preview guidance intercepts camera input")
	var model := Node3D.new()
	app.stage.models.append(model)
	await _layout(tree)
	check(not app._empty_preview.visible and app._preview_hint.visible, "preview guidance does not follow the model's visibility")
	app.stage.models.clear()
	model.free()
	app.home.hide()
	app.panel.open("guild", app.TOOLS)
	app.panel.show()
	app.panel.where = app.panel.slots[2]
	app.panel.show_preview("character", [], "work")
	await _layout(tree)
	var buttons: Array = app.panel.rows.find_children("*", "Button", true, false)
	var motions: Array = buttons.filter(func(b): return b.text in ["Walk", "Work", "Pause", "Rest", "Done"])
	check(motions.size() == 5, "a character preview motion is missing")
	check(motions.all(func(b): return is_equal_approx(b.global_position.y, motions[0].global_position.y)), "character motion choices wrap unnecessarily")
	var slider: HSlider = app.panel.rows.find_children("*", "HSlider", true, false).front()
	var values := []
	slider.value_changed.connect(func(value): values.append(value))
	slider.value = 1.1
	check(values.size() == 1 and is_equal_approx(app.panel.options.get("height_share", 0.0), 1.1), "the styled height slider changed how its value is delivered")
	app.free()
	tree.auto_accept_quit = true
	tree.root.size = previous_size
	await _layout(tree)
	return failures

func _layout(tree: SceneTree) -> void:
	for i in 8:
		await tree.process_frame

func _contrast(a: Color, b: Color) -> float:
	var first := a.srgb_to_linear()
	var second := b.srgb_to_linear()
	var x := first.r * 0.2126 + first.g * 0.7152 + first.b * 0.0722
	var y := second.r * 0.2126 + second.g * 0.7152 + second.b * 0.0722
	return (maxf(x, y) + 0.05) / (minf(x, y) + 0.05)
