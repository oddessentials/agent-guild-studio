class_name HomePanel
extends PanelContainer
## Studio's first screen: choose a world, get its art if this computer does
## not have it yet, start a piece, and see the pieces made here to edit or
## remove them. The panel only gathers choices; the app does the work.

signal world_chosen(world: String)
signal make_requested(world: String)
signal download_requested(world: String)
signal cancel_requested
signal edit_requested(id: String)
signal remove_requested(id: String)
signal connect_requested

const WORLD_ORDER := ["guild", "orbital", "grove", "professional", "goblinville", "gnomeland"]

var rows: VBoxContainer
var world := "guild"
## "ready", "missing", "downloading" or "failed", for the world chosen.
var art := "missing"
var art_bytes := 0
var art_reason := ""
var received := 0
var total := 0
var pieces: Array = []
var _bar: ProgressBar
var _progress: Label

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

## Shows the world chosen, its art's state and the pieces made here
## ({ id, title, slot, error } each).
func show_home(at_world: String, state: String, bytes: int, reason: String, list: Array) -> void:
	world = at_world
	art = state
	art_bytes = bytes
	art_reason = reason
	pieces = list
	_build()

## A download's progress, while one runs.
func show_progress(got: int, of: int) -> void:
	received = got
	total = of
	if _bar and is_instance_valid(_bar):
		_bar.max_value = maxi(of, 1)
		_bar.value = got
		_progress.text = "%d of %d MB" % [got >> 20, of >> 20]

func _build() -> void:
	for child in rows.get_children():
		child.queue_free()
	_bar = null
	_heading("Agent Guild: Studio", true)
	_note("Make characters and companions for Agent Guild from a model you have, or by recoloring a world's own.")
	var label := Label.new()
	label.text = "World"
	label.theme_type_variation = "Field"
	rows.add_child(label)
	var pick := OptionButton.new()
	for id in WORLD_ORDER:
		pick.add_item(YardModel.WORLDS[id].title)
	pick.select(WORLD_ORDER.find(world))
	pick.disabled = art == "downloading"
	pick.item_selected.connect(func(i): world_chosen.emit(WORLD_ORDER[i]))
	rows.add_child(pick)
	match art:
		"ready":
			var make := _button("Make a piece", func(): make_requested.emit(world))
			make.theme_type_variation = "Primary"
		"downloading":
			_note("Downloading this world's art…", "Note")
			_bar = ProgressBar.new()
			_bar.show_percentage = false
			_bar.custom_minimum_size.y = 8
			rows.add_child(_bar)
			_progress = _note("")
			show_progress(received, total)
			_button("Cancel", func(): cancel_requested.emit())
		_:
			if art == "failed":
				_note("The art was not downloaded: %s. Nothing was left behind." % art_reason, "Note")
			_note("This world's art is a %d MB download, kept on this computer." % (art_bytes >> 20))
			var get_it := _button("Download its art" if art == "missing" else "Try again", func(): download_requested.emit(world))
			get_it.theme_type_variation = "Primary"
	_heading("Your pieces", false)
	if pieces.is_empty():
		_note("Pieces you save are listed here, to edit later.")
	for piece: Dictionary in pieces:
		var card := PanelContainer.new()
		card.theme_type_variation = "Inset"
		rows.add_child(card)
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 6)
		card.add_child(entry)
		var name := Label.new()
		name.text = piece.title
		name.theme_type_variation = "Strong"
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.tooltip_text = "%s\n%s" % [piece.title, piece.get("saved", "")]
		entry.add_child(name)
		var slot := Label.new()
		slot.text = piece.slot
		slot.theme_type_variation = "Muted"
		slot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slot.tooltip_text = piece.slot
		entry.add_child(slot)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		entry.add_child(line)
		var id: String = piece.id
		var edit := _button("Edit", func(): edit_requested.emit(id), line)
		edit.disabled = art == "downloading" or piece.error != ""
		var remove := _button("Remove", func(): remove_requested.emit(id), line)
		remove.theme_type_variation = "Quiet"
		remove.tooltip_text = "Remove from this list. The saved folder is kept."
		if piece.error != "":
			var problem := Label.new()
			problem.text = "It can't be edited: %s." % piece.error
			problem.theme_type_variation = "Note"
			problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			entry.add_child(problem)
	_heading("Agents", false)
	_note("An agent can make pieces with Studio for you.")
	_button("Connect an agent…", func(): connect_requested.emit())
	var version := Studio.version()
	_note("Development build" if version == "dev" else "Build " + version.get_slice(".", 2))

func _heading(text: String, first: bool) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "Heading" if first else "Section"
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
