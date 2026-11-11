extends Node
## Agent Guild: Studio: makes characters and companions for Agent Guild.
##
## Options after `--`:
##   --build=MODEL --slot=WORLD/CREW --out=DIR   make a piece, check it, then quit (src/studio/studio.gd)
##   --recolour=LOOK --slot=WORLD/CREW --out=DIR  recolour one of a world's looks into a piece
##   --fetch=WORLD|helpers|all  download that art, then quit
##   --mcp                      serve MCP on stdin and stdout, so an agent can make pieces (with Godot's --headless: no window)
##   --world=guild --theme=light|dark   the world and time of day the window opens on
##   --shot=FILE.png            save a picture of the window, then quit
##   --version                  print this build's version, then quit

const TOOLS := { "anthropic": "Claude Code", "openai": "Codex CLI", "google": "Antigravity CLI", "xai": "Grok Build", "docker": "Docker Agent", "shell": "Shell" }
const GAP := 16.0
const PANEL_WIDTH := 400.0

var options := {}
var world := "guild"
var theme := "light"
var skin := UiSkin.new()
var pieces: PieceLibrary
var stage: StudioStage
var camera: CameraRig
var layer: CanvasLayer
var root: Control
var home: HomePanel
var panel: StudioPanel
var download: ArtDownload
var flow: StudioFlow
var mcp: McpServer
var _art_reason := ""
var _section: Texture2D
var _orbiting := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else "1"
	if options.has("version"):
		print(ProjectSettings.get_setting("application/config/version"))
		get_tree().quit()
		return
	if options.has("check-piece") or options.has("check-source"):
		get_tree().quit(PieceCheck.run(options))
		return
	download = ArtDownload.new()
	add_child(download)
	if options.has("fetch"):
		get_tree().quit(await _fetch(options.fetch))
		return
	if options.has("build") or options.has("recolour"):
		var where := Studio.slot(options.get("slot", ""))
		if not where.has("reason") and await _art(StudioArt.packs_for(where.world)) != "":
			get_tree().quit(1)
			return
		get_tree().quit(await Studio.run(self, options))
		return
	if options.has("mcp"):
		Studio.quiet = true
		mcp = McpServer.new()
		mcp.host = self
		add_child(mcp)
		if DisplayServer.get_name() == "headless":
			return
	_open()

## The art `packs` name, downloaded if it isn't here, then loaded; "" or why
## not, said on the command line.
func _art(packs: Array) -> String:
	var missing := StudioArt.missing(packs)
	if not missing.is_empty():
		print("studio: downloading art (%s), %d MB" % [", ".join(missing), StudioArt.bytes(missing) >> 20])
		download.start(missing)
		var why: String = await download.finished
		if why != "":
			printerr("studio: the art was not downloaded: %s" % why)
			return why
	var reason := StudioArt.load_packs(packs)
	if reason != "":
		printerr("studio: " + reason)
	return reason

func _fetch(what: String) -> int:
	var packs: Array = StudioArt.lock().packs.keys() if what == "all" else [what]
	for pack in packs:
		if not StudioArt.lock().packs.has(pack):
			printerr("studio: there is no %s art; choose one of %s, or all" % [pack, ", ".join(StudioArt.lock().packs.keys())])
			return 1
	var missing := StudioArt.missing(packs)
	if missing.is_empty():
		print("studio: that art is here already, in %s" % StudioArt.folder())
		return 0
	print("studio: downloading art (%s), %d MB" % [", ".join(missing), StudioArt.bytes(missing) >> 20])
	download.start(missing)
	var why: String = await download.finished
	if why != "":
		printerr("studio: the art was not downloaded: %s" % why)
		return 1
	print("studio: the art is in %s" % StudioArt.folder())
	return 0

## The window: the stage, with the first screen beside it.
func _open() -> void:
	world = options.get("world", world) if YardModel.WORLDS.has(options.get("world", world)) else world
	theme = "dark" if options.get("theme", "light") == "dark" else "light"
	get_window().min_size = Vector2i(960, 600)
	pieces = PieceLibrary.new()
	pieces.default_clips = default_clips
	add_child(pieces)
	pieces.changed.connect(_show_home)
	stage = StudioStage.new()
	add_child(stage)
	camera = CameraRig.new()
	add_child(camera)
	camera.make_current()
	stage.camera = camera
	camera.frame(StudioStage.SPOT + Vector3(-0.35, 0.9, 0.5), deg_to_rad(55.0), deg_to_rad(14.0), 4.4)
	layer = CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	home = HomePanel.new()
	root.add_child(home)
	panel = StudioPanel.new()
	panel.pad_screen = func(): return false
	root.add_child(panel)
	layer.add_child(panel.file_dialog)
	layer.add_child(panel.folder_dialog)
	get_tree().node_added.connect(func(node):
		if node.has_meta("section_rule") and _section and node is TextureRect and root.is_ancestor_of(node):
			node.texture = _section)
	root.resized.connect(_layout)
	home.world_chosen.connect(_set_world)
	home.make_requested.connect(func(_w): _start(""))
	home.download_requested.connect(func(_w): _download())
	home.cancel_requested.connect(download.cancel)
	home.edit_requested.connect(_edit)
	home.remove_requested.connect(pieces.remove)
	home.connect_requested.connect(_connect_dialog)
	download.changed.connect(func(): home.show_progress(download.received, download.total))
	download.finished.connect(func(why):
		_art_reason = why
		_show_home())
	_set_world(world)
	_layout()
	if options.has("shot"):
		_shot.call_deferred(options.shot)

func _set_world(next: String) -> void:
	world = next
	_art_reason = ""
	_restyle()
	stage.set_world(world, theme)
	_show_home()

## The controls in the world's look, by day or at dusk.
func _restyle() -> void:
	skin.apply(world, theme, get_window().content_scale_factor)
	root.theme = skin.theme
	panel.file_dialog.theme = skin.theme
	panel.folder_dialog.theme = skin.theme
	var fade := skin.color("gold") if world != "grove" else skin.color("accent")
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 0.9])
	gradient.colors = PackedColorArray([fade, Color(fade, fade.a * 0.35), Color(fade, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 1
	_section = texture
	for line in root.find_children("*", "TextureRect", true, false):
		if line.has_meta("section_rule"):
			line.texture = _section

func _layout() -> void:
	var view := root.size
	if view.x <= 0.0:
		return
	var width := minf(PANEL_WIDTH, view.x * 0.45) if view.x >= 1000.0 else minf(PANEL_WIDTH * 1.4, view.x - GAP * 2.0)
	for side: Control in [home, panel]:
		side.set_anchors_preset(Control.PRESET_TOP_LEFT)
		side.offset_left = GAP
		side.offset_top = GAP
		side.offset_right = GAP + width
		side.offset_bottom = maxf(view.y - GAP, GAP)

func _show_home() -> void:
	if home == null or flow != null:
		return
	var packs := StudioArt.packs_for(world)
	var missing := StudioArt.missing(packs)
	var state := "downloading" if download.running else "ready" if missing.is_empty() else "failed" if _art_reason != "" else "missing"
	var list := []
	for id in pieces.pieces:
		var p: Dictionary = pieces.pieces[id]
		if p.get("source", "") != "local":
			continue
		var slot := "%s, %s" % [YardModel.WORLDS[p.world].title, "Companions" if p.kind == "companion" else "%s crew" % TOOLS.get(p.crew, p.crew)] if PieceLibrary.has_slot(p) else "no slot"
		list.append({ "id": id, "title": p.get("title", id), "slot": slot, "error": p.get("error", ""), "saved": p.get("saved", "") })
	home.show_home(world, state, StudioArt.bytes(missing), _art_reason, list)
	home.show()

func _download() -> void:
	_art_reason = ""
	download.start(StudioArt.missing(StudioArt.packs_for(world)))
	_show_home()

func _edit(id: String) -> void:
	var piece: Dictionary = pieces.pieces.get(id, {})
	if not PieceLibrary.has_slot(piece):
		return
	if piece.world != world:
		_set_world(piece.world)
	if StudioArt.missing(StudioArt.packs_for(world)).is_empty():
		_start(id)

## Studio's screens for one piece: a new one, or the player's piece `edit`.
func _start(edit: String) -> void:
	if flow != null:
		return
	_art_reason = StudioArt.load_packs(StudioArt.packs_for(world))
	if _art_reason != "":
		_show_home()
		return
	home.hide()
	flow = StudioFlow.new()
	add_child(flow)
	flow.ended.connect(func():
		flow = null
		stage.set_theme(theme)
		_show_home())
	flow.start(panel, stage, pieces, TOOLS, world, theme, edit)

## A slot default's clip lengths, which a piece's own must match.
func default_clips(of_world: String, kind: String, crew: String) -> Dictionary:
	var model := Studio.default_model({ "world": of_world, "kind": kind, "crew": crew })
	if model == null:
		return {}
	var clips: Dictionary = (StudioCharacter.default_of(model) if kind == "character" else StudioCompanion.default_of(model)).clips
	var lengths := {}
	for name in clips:
		lengths[name] = clips[name].length
	model.free()
	return lengths

func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_orbiting = event.pressed
	elif event is InputEventMouseMotion and _orbiting:
		camera.orbit(-event.relative.x * 0.006, 0.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and flow != null and panel.visible:
		panel.leave_requested.emit()

func _shot(path: String) -> void:
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

## The agent has gone: with no window, so does Studio.
func agent_disconnected() -> void:
	if home == null:
		get_tree().quit()

## Studio's window, as a program of its own beside an agent's connection.
func open_window() -> bool:
	var before := [] if OS.has_feature("template") else ["--path", ProjectSettings.globalize_path("res://").trim_suffix("/")]
	return OS.create_process(OS.get_executable_path(), before) > 0

## For PowerShell on Windows, and for Terminal's shell (zsh) elsewhere.
static func connect_commands(exe: String, before: Array, posix := OS.get_name() != "Windows") -> Array:
	var args := before + ["--headless", "--no-header", "--", "--mcp"]
	var shell_args := " ".join(args.map(func(a): return _shell_quote(str(a), posix)))
	var line := "%s %s" % [_shell_quote(exe, posix), shell_args]
	var yaml_args := ", ".join(args.map(func(a): return "'%s'" % str(a).replace("'", "''")))
	return [
		["Claude Code", "claude mcp add -s user agent-guild-studio \"--\" " + line],
		["Codex CLI", "codex mcp add agent-guild-studio \"--\" " + line],
		["Antigravity CLI", "agy mcp add agent-guild-studio \"--\" " + line],
		["Grok Build", "grok mcp add agent-guild-studio \"--\" " + line],
		["Docker Agent", "agents:
  root:
    toolsets:
      - type: mcp
        command: '%s'
        args: [%s]" % [exe.replace("'", "''"), yaml_args]],
	]

## Paths always in single quotes, which PowerShell and POSIX shells both take
## literally; they differ only in how a ' inside is written. A bare -- would be
## dropped by PowerShell when the agent's command is an npm .ps1 wrapper, so
## it's always quoted.
static func _shell_quote(text: String, posix := false) -> String:
	if text == "--":
		return "\"--\""
	if text.begins_with("--") and text.substr(2).replace("-", "").is_valid_identifier():
		return text
	return "'%s'" % text.replace("'", "'\''" if posix else "''")

const CONNECT_WIDTH := 640.0

func _connect_dialog(exe := OS.get_executable_path()) -> void:
	var ask := AcceptDialog.new()
	ask.name = "ConnectAgentDialog"
	ask.title = "Connect an agent"
	ask.ok_button_text = "Done"
	ask.theme = skin.theme
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	ask.add_child(box)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = "Run one of these once in %s. Afterwards your agent can make characters and companions with Studio, with no window. If you move this app to another folder, run the command again." % ("Terminal" if OS.get_name() == "macOS" else "PowerShell")
	intro.custom_minimum_size = Vector2(CONNECT_WIDTH, 0)
	box.add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.name = "Commands"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(CONNECT_WIDTH + 12, minf(420.0, get_viewport().get_visible_rect().size.y - 220.0))
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var before := [] if OS.has_feature("template") else ["--path", ProjectSettings.globalize_path("res://").trim_suffix("/")]
	for entry in connect_commands(exe, before):
		var heading := Label.new()
		heading.text = entry[0]
		heading.theme_type_variation = "Section"
		list.add_child(heading)
		var row := HBoxContainer.new()
		list.add_child(row)
		var text := TextEdit.new()
		text.text = entry[1]
		text.editable = false
		text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		text.scroll_fit_content_height = true
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var copy := Button.new()
		copy.text = "Copy"
		copy.tooltip_text = "Copy the %s command" % entry[0]
		var command: String = entry[1]
		copy.pressed.connect(func():
			DisplayServer.clipboard_set(command)
			copy.text = "Copied")
		row.add_child(copy)
	var docker := Label.new()
	docker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	docker.theme_type_variation = "Muted"
	docker.text = "Docker Agent: add the toolset to your agent in its YAML file, with root replaced by your agent's name."
	docker.custom_minimum_size = Vector2(CONNECT_WIDTH, 0)
	box.add_child(docker)
	layer.add_child(ask)
	ask.confirmed.connect(ask.queue_free)
	ask.canceled.connect(ask.queue_free)
	ask.popup_centered()
