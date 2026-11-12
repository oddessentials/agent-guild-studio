class_name StudioPanel
extends PanelContainer
## Studio's screens for one piece: choose the slot, bring a model (or recolour
## one of the world's looks), check its bones when Studio can't be sure of
## them, see it on the stage, then save its folder. The panel only gathers choices and shows results; StudioFlow does
## the work. Its file dialogs are windows the owner adds beside its controls.

signal slot_chosen(where: Dictionary)
signal make_requested(spec: Dictionary)
## A recolour to see now, as set; {} when the player leaves recolouring.
signal recolour_changed(spec: Dictionary)
## A choice of how the made piece fits changed: { where, files, options }.
signal adjusted(spec: Dictionary)
signal motion_chosen(motion: String)
signal theme_chosen(theme: String)
signal save_requested(folder: String, title: String)
signal leave_requested

const STEPS := ["slot", "bring", "recolour", "bones", "preview", "finish"]
## How close a shade must be to the color changed to change with it.
const SPREAD := 0.15
const LOOK_NAMES := { "look0": "Its first look", "look1": "Its second look", "look2": "Its third look", "agent": "Its agents' helpers", "shell": "Its shells' helpers" }
const MODELS := ["*.glb, *.gltf, *.vrm ; Models", "*.fbx ; FBX (convert to .glb first)"]
## What to export from each common tool, in a line or two.
const GUIDES := [
	["Mixamo", "Upload your model, let it auto-rig, and download it as FBX in T-pose, without animation. Then convert it to .glb: in Blender, import the FBX and export as glTF 2.0."],
	["VRoid Studio", "Export as VRM (0.0 or 1.0). Its expressions and swaying hair are left behind."],
	["Meshy or Tripo", "Rig it as a humanoid, then download the rigged model as GLB."],
	["Blender", "Export glTF binary (.glb) with the armature and its skin; no animation is needed."],
	["Anything else", "For companions, any model will do: a pumpkin, a lantern, a drone."],
]
## What the preview shows them doing, as sessions do in the game.
const CHARACTER_MOTIONS := [["Walk", "walk"], ["Work", "work"], ["Pause", "pause"], ["Rest", "rest"], ["Done", "done"]]
const COMPANION_MOTIONS := [["Idle", "idle"], ["Working", "working"], ["Waiting", "waiting"], ["Done", "done"], ["Moving", "move"]]

var rows: VBoxContainer
var file_dialog: FileDialog
var folder_dialog: FileDialog
## While a file dialog is open (a native one has no visible window).
var dialog_open := false
## Whether this screen is used with a controller, so dialogs are Godot's own.
var pad_screen: Callable
var step := "slot"
var world := ""
var slots := []
var where := {}
var files := []
var facts := ""
var options := {}
var recolour := {}
## The recolour screen's choices, kept while the slot stays the same.
var tints := {}
var motion := ""
var light := "light"
var _bones := {}
var _bone_picks := {}
var _status: Label
var _leave: Button
## The player's piece being edited: { id, title, where }, or {}.
var editing := {}
## The recolored look's own main colors, where they're offered, and the
## color one of them is changed to.
var _colors := []
var _swatches: HFlowContainer
var _to: ColorPickerButton
## Why the model must be chosen again when editing, or "".
var _bring_note := ""
## The button whose action is under way, and the controls held meanwhile.
var _acting: Button
var _held := []

func _init() -> void:
	theme_type_variation = "Side"
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	add_child(scroll)
	hide()
	_dialogs()

## Opens on the first screen, for the world shown; `tools` names each crew.
## Editing one of the player's pieces (`edit`), only its slot is offered.
func open(at_world: String, tools: Dictionary, theme := "light", edit := {}) -> void:
	world = at_world
	light = theme
	editing = edit
	slots = []
	for crew in YardModel.PROVIDER_ORDER:
		slots.append({ "world": world, "kind": "character", "crew": crew, "name": "%s crew" % tools.get(crew, crew.capitalize()) })
	slots.append({ "world": world, "kind": "companion", "crew": "", "name": "Companions" })
	if not edit.is_empty():
		slots = slots.filter(func(s): return s.kind == edit.where.kind and s.crew == edit.where.crew)
	where = slots[0]
	files = []
	recolour = {}
	tints = {}
	options = {}
	_bring_note = ""
	_show_slot()
	slot_chosen.emit(where)

## Back to how the piece being edited was made (StudioFlow._recipe): its
## look's recolor, or its model made again with the same choices; a model
## no longer where it was, or a piece Studio didn't make, is chosen again.
func reopen(recipe: Dictionary) -> void:
	if recipe.has("recolour"):
		tints = _tints_from(recipe.recolour.change, recipe.recolour.which)
		_show_recolour()
		return
	var paths: Array = recipe.get("files", [])
	if not paths.is_empty() and paths.all(func(f): return FileAccess.file_exists(f)):
		files = paths.duplicate()
		options = recipe.get("options", {}).duplicate()
		if options.has("colour"):
			options.colour = StudioRecolour.read(options.colour)
			tints = _tints_from(options.colour, "")
		_show_bring()
		_acting = null
		make_requested.emit({ "where": where, "files": files, "options": options.duplicate() })
		return
	_bring_note = "Its model is no longer at %s. Choose it again, or recolor a look." % ", ".join(paths) if not paths.is_empty() 		else "Studio didn't make this piece. Bring a model, or recolor a look, for its new version."
	_show_bring()

func modal() -> bool:
	return dialog_open

## Back a screen; from the first, out of Studio.
func back() -> void:
	if not _held.is_empty():
		return
	match step:
		"slot":
			leave_requested.emit()
		"bring":
			_show_slot()
		"recolour":
			recolour_changed.emit({})
			_show_bring()
		"bones":
			_show_bring()
		"preview":
			if recolour.is_empty():
				_show_bring()
			else:
				_show_recolour()
		"finish":
			_show_preview(_last_kind, _last_notes)

func _editing_line() -> void:
	if not editing.is_empty():
		_note("Editing %s." % editing.title)

func show_facts(text: String) -> void:
	facts = text
	if step == "slot":
		_show_slot()

## Something is under way: every control but Leave Studio waits.
func working(text: String) -> void:
	_hold(true)
	_status_text(text)

func show_reason(text: String) -> void:
	_hold(false)
	_status_text("Studio couldn't make it: %s." % text)

## Bones Studio can't be sure of: each needed bone, with the model's bone
## chosen for it, the unsure ones marked, for the player to settle.
func show_bones(unsure: Dictionary, map: Dictionary, names: PackedStringArray) -> void:
	step = "bones"
	_bones = { "unsure": unsure, "map": map, "names": names }
	_bone_picks = {}
	_clear("Check its bones")
	_note("Studio couldn't be sure of every bone. Choose the model's bone for each one marked.", "Note")
	var swapped: bool = unsure.values().any(func(w): return "swapped" in w)
	var guessed: bool = unsure.values().any(func(w): return w == StudioBones.GUESSED)
	if swapped:
		_note("Its left and right look the wrong way around.", "Note")
		_action("Swap left and right", "Making…", func(): _make_with("swap"))
	for bone in StudioBones.NEEDED + StudioBones.OPTIONAL:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = _words(bone)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if unsure.has(bone):
			label.theme_type_variation = "Strong"
			label.tooltip_text = unsure[bone]
		row.add_child(label)
		var pick := OptionButton.new()
		pick.add_item("(none)")
		for n in names:
			pick.add_item(n)
		pick.select(int(map[bone]) + 1 if map.has(bone) else 0)
		pick.custom_minimum_size.x = 180
		pick.clip_text = true
		row.add_child(pick)
		_bone_picks[bone] = pick
		rows.add_child(row)
		if unsure.has(bone):
			_note("%s: %s." % [_words(bone), unsure[bone]], "Note")
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	var use := _action("Use these", "Making…", func(): _make_with(_chosen_pairs()), buttons)
	use.theme_type_variation = "Primary"
	if guessed:
		_action("They look right", "Making…", func(): _make_with("accept"), buttons)
	_button("Back", back, buttons)
	_status_line()
	_footer()

var _last_kind := "character"
var _last_notes := []

## The piece in the world: what it does, day or dusk, and what Studio did.
## `colors` are a made piece's own main colors, to choose one to change from.
func show_preview(kind: String, notes: Array, playing := "", colors := []) -> void:
	motion = playing
	if recolour.is_empty():
		_colors = colors
		if tints.is_empty() or tints.get("which", "") != "":
			tints = _fresh_tints("")
	_show_preview(kind, notes)

func show_done(text: String) -> void:
	_hold(false)
	_status_text(text)

func _show_slot() -> void:
	step = "slot"
	_clear("Make a piece" if editing.is_empty() else "Edit a piece")
	_editing_line()
	_note("A piece changes how one crew, or the companions, look in %s." % YardModel.WORLDS[world].title)
	var pick := OptionButton.new()
	for s in slots:
		pick.add_item(s.name)
	pick.select(slots.find(where))
	pick.item_selected.connect(func(i):
		where = slots[i]
		facts = ""
		tints = {}
		slot_chosen.emit(where))
	rows.add_child(pick)
	if facts != "":
		_note(facts)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	var next := _button("Next", _show_bring, buttons)
	next.theme_type_variation = "Primary"
	_footer()

func _show_bring() -> void:
	step = "bring"
	_clear("Bring a model")
	_editing_line()
	if _bring_note != "":
		_note(_bring_note, "Note")
	_button("Choose a model file…" if where.kind == "character" else "Choose one model, or four…", func():
		dialog_open = true
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if where.kind == "character" else FileDialog.FILE_MODE_OPEN_FILES
		file_dialog.use_native_dialog = not pad_screen.call()
		file_dialog.popup_centered_ratio(0.6))
	var chosen := Label.new()
	chosen.theme_type_variation = "Muted"
	chosen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chosen.text = ", ".join(files.map(func(f): return String(f).get_file())) if not files.is_empty() else "No model chosen yet."
	rows.add_child(chosen)
	var make := _action("Make it", "Making…", func():
		recolour = {}
		make_requested.emit({ "where": where, "files": files, "options": options.duplicate() }))
	make.theme_type_variation = "Primary"
	make.disabled = files.is_empty()
	_status_line()
	if not StudioRecolour.sources(where).is_empty():
		_heading("Or recolor one of its looks")
		_note("Turn its colors, change one of them, or lay a color over it, and see it as you go.")
		_button("Recolor a look…", _show_recolour)
	_heading("What to export")
	for guide in GUIDES:
		var line := _note("%s: %s" % guide)
		line.theme_type_variation = "Muted"
	_button("Back", back)
	_footer()

## One of the slot's looks, recolored on the stage a moment after each
## change: all its colors (a hue shift, a tint) or one of them changed to
## another; Next once the stage shows it as set.
func _show_recolour() -> void:
	var looks: Array = StudioRecolour.sources(where)
	if looks.is_empty():
		_show_bring()
		return
	step = "recolour"
	_clear("Recolor a look")
	_swatches = null
	_to = null
	_editing_line()
	if tints.is_empty() or not tints.which in looks:
		tints = _fresh_tints(looks[0])
		_colors = []
	var look_pick := OptionButton.new()
	for l in looks:
		look_pick.add_item(LOOK_NAMES.get(l, l))
	look_pick.select(looks.find(tints.which))
	look_pick.item_selected.connect(func(i):
		_colors = []
		tints.pick = null
		if not tints.chosen:
			tints.to = null
		_fill_swatches()
		_tint("which", looks[i]))
	rows.add_child(look_pick)
	_colour_controls(_show_recolour)
	_status_line()
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	var next := _button("Next", func():
		recolour = { "which": tints.which, "change": _change() }
		show_preview(_last_kind, [], motion), buttons)
	next.theme_type_variation = "Primary"
	next.disabled = true
	next.set_meta("waits", true)
	_button("Back", back, buttons)
	_footer()
	if tints.mode == "one":
		_choose_first()
		_fill_swatches()
	_tint("", null)

## The color choices, for a look or for a made piece: all its colors (a hue
## shift, a tint) or one of them changed to another. `rebuild` shows the
## screen again when the kind of change is switched.
func _colour_controls(rebuild: Callable) -> void:
	_chips("", [["Change all colors", "all"], ["Change one color", "one"]], tints.mode, func(v):
		tints.mode = v
		rebuild.call())
	if tints.mode == "all":
		_slider("Hue shift", -180.0, 180.0, tints.hue, 5.0, func(v): _tint("hue", v), func(v): return "%+d°" % v if v != 0.0 else "0°",
			"Turns its colors around the color wheel; at 0° they stay as made.")
		_swatch("Tint it a color", "over", "tint")
	else:
		var choose := Label.new()
		choose.text = "Color to change"
		rows.add_child(choose)
		_swatches = HFlowContainer.new()
		_swatches.add_theme_constant_override("h_separation", 8)
		_swatches.add_theme_constant_override("v_separation", 8)
		rows.add_child(_swatches)
		var row := HBoxContainer.new()
		var into := Label.new()
		into.text = "Change it to"
		into.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(into)
		_to = _picker(tints.to if tints.to is Color else Color.WHITE, func(c):
			tints.chosen = true
			_tint("to", c))
		_to.disabled = not tints.to is Color
		row.add_child(_to)
		rows.add_child(row)
		_slider("How much counts as that color", 0.05, 0.5, float(tints.get("spread", SPREAD)), 0.01, func(v): _tint("spread", v),
			func(v): return "%d%%" % roundi(v * 100.0), "Lower changes only colors very like it; higher takes in its shades too.")

static func _fresh_tints(which: String) -> Dictionary:
	return { "which": which, "mode": "all", "hue": 0.0, "over": false, "tint": Color("#3060ff"), "pick": null, "to": null, "chosen": false, "spread": SPREAD }

## The screen's choices as a saved change (StudioRecolour's) had them.
static func _tints_from(change: Dictionary, which: String) -> Dictionary:
	var one: bool = change.has("pick")
	return { "which": which, "mode": "one" if one else "all", "hue": 0.0 if one else float(change.get("hue", 0.0)),
		"over": not one and change.has("tint"), "tint": Color(change.get("tint", "#3060ff")) if not one else Color("#3060ff"),
		"pick": Color(change.pick) if one else null, "to": Color(change.tint) if one and change.has("tint") else null, "chosen": one and change.has("tint"),
		"spread": float(change.get("spread", SPREAD)) }

## A made piece's colors as the screen now has them, sent on if they changed.
func _sync_colour() -> void:
	var change := _change()
	var now: Dictionary = {} if StudioRecolour.plain(change) else change
	if now == options.get("colour", {}):
		return
	if now.is_empty():
		options.erase("colour")
	else:
		options.colour = now
	_ready_to_go(false, "Coloring…")
	adjusted.emit({ "where": where, "files": files, "options": options.duplicate() })

## A color clearly unlike `c` to change it to: its opposite hue, or for a
## gray, the same red every time.
static func contrast(c: Color) -> Color:
	if c.s < 0.2:
		return Color("#d03030")
	return Color.from_hsv(fposmod(c.h + 0.5, 1.0), maxf(c.s, 0.6), clampf(c.v, 0.5, 0.9))

## With the look's colors read, the most used one to change, to a color
## unlike it, unless the player has chosen.
func _choose_first() -> void:
	if tints.pick == null and not _colors.is_empty():
		tints.pick = _colors[0]
	if tints.pick is Color and not tints.chosen:
		tints.to = contrast(tints.pick)
	if _to and is_instance_valid(_to) and tints.to is Color:
		_to.color = tints.to
		_to.disabled = false

## The look's own main colors to change, the chosen one lit.
func _fill_swatches() -> void:
	if _swatches == null or not is_instance_valid(_swatches):
		return
	for child in _swatches.get_children():
		child.queue_free()
	if _colors.is_empty():
		var wait := Label.new()
		wait.theme_type_variation = "Muted"
		wait.text = "Reading its colors…"
		_swatches.add_child(wait)
		return
	var group := ButtonGroup.new()
	for c: Color in _colors:
		var b := Button.new()
		b.theme_type_variation = "Choice"
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(40, 32)
		var chip := Image.create(20, 20, false, Image.FORMAT_RGB8)
		chip.fill(c)
		b.icon = ImageTexture.create_from_image(chip)
		b.tooltip_text = "#" + c.to_html(false)
		b.button_pressed = tints.pick is Color and tints.pick.to_html(false) == c.to_html(false)
		b.toggled.connect(func(on):
			if on:
				tints.pick = c
				_choose_first()
				_tint("", null))
		_swatches.add_child(b)

## The stage shows the recolor as set (`kind` of piece, playing `playing`);
## `colors` are its look's own, to choose one to change from.
func recolour_shown(kind: String, playing: String, colors := []) -> void:
	_last_kind = kind
	motion = playing
	if not colors.is_empty() and colors != _colors:
		_colors = colors
		var first: bool = tints.get("pick") == null
		_choose_first()
		_fill_swatches()
		if first and tints.get("mode") == "one":
			_tint("", null)
			return
	_ready_to_go(true, "")

## Next waits while the stage catches up with a change.
func _ready_to_go(ready: bool, text: String) -> void:
	if not step in ["recolour", "preview"]:
		return
	_status_text(text)
	for b in rows.find_children("*", "Button", true, false):
		if b.has_meta("waits"):
			b.disabled = not ready

## A choice changed (`key` to `value`): the stage catches up a moment later.
func _tint(key: String, value) -> void:
	if key != "":
		tints[key] = value
	if step == "preview":
		_sync_colour()
		return
	_ready_to_go(false, "Recoloring…")
	recolour_changed.emit({ "where": where, "recolour": { "which": tints.which, "change": _change() } })

## The change the screen shows: only its mode's choices.
func _change() -> Dictionary:
	var c := { "hue": 0.0, "spread": float(tints.get("spread", SPREAD)) }
	if tints.mode == "one":
		if tints.pick is Color and tints.to is Color:
			c.pick = tints.pick
			c.tint = tints.to
		return c
	c.hue = float(tints.hue)
	if tints.over:
		c.tint = tints.tint
	return c

## A switch and its color: choosing a color switches it on.
func _swatch(text: String, on_key: String, color_key: String) -> CheckBox:
	var row := HBoxContainer.new()
	var on := CheckBox.new()
	on.text = text
	on.button_pressed = tints[on_key]
	on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	on.toggled.connect(func(v): _tint(on_key, v))
	row.add_child(on)
	row.add_child(_picker(tints[color_key], func(c):
		tints[color_key] = c
		if on.button_pressed:
			_tint("", null)
		else:
			on.button_pressed = true))
	rows.add_child(row)
	return on

## A color button whose picker closes on Use this color.
func _picker(color: Color, changed: Callable) -> ColorPickerButton:
	var swatch := ColorPickerButton.new()
	swatch.custom_minimum_size = Vector2(72, 32)
	swatch.edit_alpha = false
	swatch.color = color
	swatch.tooltip_text = "Choose the color"
	var picker := swatch.get_picker()
	picker.presets_visible = false
	picker.edit_intensity = false
	picker.color_modes_visible = false
	var use := Button.new()
	use.text = "Use this color"
	use.theme_type_variation = "Primary"
	use.pressed.connect(func(): swatch.get_popup().hide())
	picker.add_child(use)
	swatch.color_changed.connect(changed)
	return swatch

func _show_preview(kind: String, notes: Array) -> void:
	step = "preview"
	_last_kind = kind
	_last_notes = notes
	_clear("See it on the stage")
	_swatches = null
	_to = null
	_chips("What it does", CHARACTER_MOTIONS if kind == "character" else COMPANION_MOTIONS, motion, func(v):
		motion = v
		motion_chosen.emit(v))
	_chips("Light", [["Day", "light"], ["Dusk", "dark"]], light, func(v):
		light = v
		theme_chosen.emit(v))
	for note in notes:
		_note(note, "Note")
	if notes.is_empty():
		_note("It fits without changes.")
	if recolour.is_empty():
		_adjust(kind)
		_heading("Colors")
		_colour_controls(func(): _show_preview(_last_kind, _last_notes))
	_status_line()
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	var next := _button("Next", _show_finish, buttons)
	next.theme_type_variation = "Primary"
	next.set_meta("waits", true)
	_button("Back", back, buttons)
	_footer()
	if recolour.is_empty():
		if tints.mode == "one":
			_choose_first()
			_fill_swatches()
		_sync_colour()

## How the piece fits, changed on the stage as it's set.
func _adjust(kind: String) -> void:
	var label := Label.new()
	label.text = "Adjust"
	rows.add_child(label)
	if kind == "character":
		_slider("Height", 0.85, 1.15, float(options.get("height_share", 1.0)), 0.01, func(v): _set_option("height_share", v),
			func(v): return "%d%% of the %s's" % [roundi(v * 100.0), where.name], "How tall it stands beside the character it replaces.")
		return
	_choice("How it moves", [["Rigid, all of it together", "rigid"], ["Soft, bending as it rises", "soft"]], options.get("move", "rigid"), func(v): _set_option("move", v))
	_choice("Four from one", [["Four tints", "tint"], ["Four sizes and angles", "turn"]], options.get("variants", "tint"), func(v): _set_option("variants", v))
	_slider("Facing", 0.0, 345.0, float(options.get("turn", 0.0)), 15.0, func(v): _set_option("turn", v), func(v): return "%d°" % v,
		"Turn it if it doesn't face forward.")

func _set_option(key: String, value) -> void:
	options[key] = value
	if where.kind == "companion":
		_ready_to_go(false, "Updating…")
	adjusted.emit({ "where": where, "files": files, "options": options.duplicate() })

## The stage shows the piece as adjusted.
func adjusted_shown() -> void:
	_ready_to_go(true, "")

func _show_finish() -> void:
	step = "finish"
	_clear("Finish")
	_editing_line()
	var label := Label.new()
	label.text = "Title"
	rows.add_child(label)
	var title := LineEdit.new()
	title.text = editing.title if not editing.is_empty() else (String(files[0]).get_file().get_basename() if recolour.is_empty() and not files.is_empty() else "%s recolored" % where.name).capitalize()
	title.max_length = 128
	rows.add_child(title)
	if not editing.is_empty():
		_note("Saving writes a new folder. Your pieces keeps this version of %s." % editing.title)
	var save := _action("Save to a folder…", "Saving…", func():
		dialog_open = true
		folder_dialog.set_meta("title", title.text)
		folder_dialog.use_native_dialog = not pad_screen.call()
		folder_dialog.popup_centered_ratio(0.6))
	save.theme_type_variation = "Primary"
	_status_line()
	_button("Back", back)
	_footer()

## What's happening, under the screen's action.
func _status_line() -> void:
	_status = Label.new()
	_status.theme_type_variation = "Note"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_status)

## Every screen ends with what's happening and a way out, open even while
## something is under way.
func _footer() -> void:
	if _status == null:
		_status_line()
	_leave = _button("Leave Studio", func(): leave_requested.emit())
	_leave.theme_type_variation = "Danger"

## Holds every control but Leave Studio while something is under way, the
## button pressed saying what it's doing; or lets them go as they were.
func _hold(on: bool) -> void:
	for c in _held:
		if is_instance_valid(c[0]):
			c[0].set(c[1], c[2])
	_held.clear()
	if not on:
		return
	for c in rows.find_children("*", "Control", true, false):
		var prop := "disabled" if c is BaseButton else "editable" if c is Slider or c is LineEdit else ""
		if prop == "" or c == _leave or c.is_queued_for_deletion():
			continue
		_held.append([c, prop, c.get(prop)])
		c.set(prop, prop == "disabled")
	if _acting and is_instance_valid(_acting) and not _acting.is_queued_for_deletion():
		_held.append([_acting, "text", _acting.text])
		_acting.text = String(_acting.get_meta("busy"))

func _status_text(text: String) -> void:
	if _status and is_instance_valid(_status):
		_status.text = text

func _make_with(pairs: String) -> void:
	var o: Dictionary = options.duplicate()
	o.map = pairs
	make_requested.emit({ "where": where, "files": files, "options": o })

func _chosen_pairs() -> String:
	var pairs := []
	for bone in _bone_picks:
		var i: int = _bone_picks[bone].selected
		if i > 0:
			pairs.append("%s=%s" % [bone, _bones.names[i - 1]])
	return ",".join(pairs)

func _dialogs() -> void:
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(MODELS)
	file_dialog.title = "A model: .glb, .gltf or .vrm"
	file_dialog.canceled.connect(func(): dialog_open = false)
	file_dialog.file_selected.connect(func(path):
		dialog_open = false
		files = [path]
		_show_bring())
	file_dialog.files_selected.connect(func(paths):
		dialog_open = false
		files = Array(paths)
		_show_bring())
	folder_dialog = FileDialog.new()
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.title = "Where to save the piece's folder"
	folder_dialog.canceled.connect(func(): dialog_open = false)
	folder_dialog.dir_selected.connect(func(dir):
		dialog_open = false
		save_requested.emit(dir, String(folder_dialog.get_meta("title", ""))))

func _clear(heading: String) -> void:
	for child in rows.get_children():
		child.queue_free()
	_status = null
	_held.clear()
	_acting = null
	_heading(heading)

func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "Section" if rows.get_children().any(func(c): return not c.is_queued_for_deletion()) else "Heading"
	rows.add_child(label)
	rows.add_child(UiSkin.section_rule())

func _note(text: String, style := "Muted") -> Label:
	var line := Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.theme_type_variation = style
	line.text = text
	rows.add_child(line)
	return line

func _button(text: String, pressed: Callable, into: Container = null) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(pressed)
	(into if into else rows).add_child(b)
	return b

## A button that starts something: while it runs, it says `busy`.
func _action(text: String, busy: String, pressed: Callable, into: Container = null) -> Button:
	var b := Button.new()
	b.text = text
	b.set_meta("busy", busy)
	b.pressed.connect(func(): _acting = b)
	b.pressed.connect(pressed)
	(into if into else rows).add_child(b)
	return b

func _choice(label_text: String, items: Array, current: String, picked: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var pick := OptionButton.new()
	for item in items:
		pick.add_item(item[0])
	pick.select(maxi(0, items.map(func(i): return i[1]).find(current)))
	pick.item_selected.connect(func(i): picked.call(items[i][1]))
	row.add_child(pick)
	rows.add_child(row)

## One of a set, the chosen one lit.
func _chips(label_text: String, items: Array, current: String, picked: Callable) -> void:
	if label_text != "":
		var label := Label.new()
		label.theme_type_variation = "Field"
		label.text = label_text
		rows.add_child(label)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for item in items:
		var b := Button.new()
		b.text = item[0]
		b.theme_type_variation = "Choice"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = item[1] == current
		b.toggled.connect(func(on): if on: picked.call(item[1]))
		chips.add_child(b)
	rows.add_child(chips)

## A slider under its name and value, with what it does beneath.
func _slider(label_text: String, low: float, high: float, value: float, step_by: float, changed: Callable, say: Callable, explain := "", into: Container = null) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var amount := Label.new()
	amount.theme_type_variation = "Muted"
	amount.text = say.call(value)
	row.add_child(amount)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step_by
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v):
		amount.text = say.call(v)
		changed.call(v))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(row)
	box.add_child(slider)
	if explain != "":
		var line := Label.new()
		line.theme_type_variation = "Muted"
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = explain
		box.add_child(line)
	(into if into else rows).add_child(box)
	return slider

## "LeftUpperArm" as "Left upper arm".
static func _words(bone: String) -> String:
	var out := ""
	for i in bone.length():
		var c := bone[i]
		out += (" " + c.to_lower()) if i > 0 and c == c.to_upper() and c != c.to_lower() else c
	return out
