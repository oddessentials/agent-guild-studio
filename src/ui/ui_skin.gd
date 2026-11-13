class_name UiSkin
extends RefCounted
## The controls' look for a world by day or at dusk, from that world's web
## skin (ui/skins/<world>/tokens.json): one Theme every control shares,
## rebuilt in place, so a change of world, time of day or scale restyles
## everything at once. Controls pick a role with theme_type_variation:
##   PanelContainer: Bar, Side, Dialog, Inset, Pill, Failed (a red screen), FailedBanner
##   Label: Title, Subtitle, Heading, Section (a heading after others), Field, Muted, Note, Strong, Small, TagName, TagState, Level, Alert
##   Button: Primary, Quiet, Row, Danger, Close
##   AcceptDialog: Framed (the dialog's frame inside the window, no title bar)
## Name tags and the roster's provider marks take their colour from the
## world's halls, so they set it themselves (tag_box, gem). Any other control
## that styles itself carries a "skin_exception" meta saying why: the
## wordmark, the world's title scrim and the terminal.

const DIR := "res://ui/"
## Each framed skin's frames, as its skin.css draws them: the image, its
## border-image slice and border width, and where the fill starts inside it.
const FRAMES := {
	"guild": { "side": ["frame.png", 168, 44, 9], "dialog": ["frame-ornate.png", 232, 54, 44] },
	"goblinville": { "side": ["frame.svg", 30, 22, 6], "dialog": ["frame.svg", 30, 22, 6] },
	"gnomeland": { "side": ["frame.svg", 30, 22, 6], "dialog": ["frame.svg", 30, 22, 6] },
	# Orbital's HUD brackets, as its cards draw them: drawn here in the skin's colours.
	"orbital": { "side": ["@hud", 20, 20, 1], "dialog": ["@hud", 20, 20, 1] },
}
## Each skin's level mark and the colour of the number on it, as its skin.css
## draws .level-badge; professional has none and draws "Lv" in a pill.
const LEVEL := {
	"guild": ["level-medallion.png", "#f6dea6"],
	"orbital": ["level.svg", "#eaf6ff"],
	"grove": ["stone.png", "#f3f6ee"],
	"goblinville": ["level.svg", "#ffe3b0"],
	"gnomeland": ["level.svg", "#fbe3a6"],
}
## A dialog window's title bar, in logical pixels: room for its close button
## (dialogs carry their own heading).
const TITLE := 24
## Text sizes in logical pixels; nothing is smaller than 12 (Steam Deck).
const SIZE := { "body": 15, "small": 13, "tiny": 12, "heading": 17, "title": 26 }
## Padding inside side panels and dialogs, in logical pixels.
const PAD := { "side": Vector2(24, 16), "dialog": Vector2(28, 24) }

var theme := Theme.new()
var world := ""
var mode := ""
var scale := 1.0
var tokens := {}
var _t := {}
var _icons := {}
var _gems := {}

static var _fonts := {}

## Restyles every control for this world, time of day ("light" or "dark") and scale.
func apply(next_world: String, next_mode: String, next_scale: float) -> void:
	if next_world == world and next_mode == mode and is_equal_approx(next_scale, scale):
		return
	if next_world != world:
		tokens = JSON.parse_string(FileAccess.get_file_as_string(DIR + "skins/%s/tokens.json" % next_world))
	world = next_world
	mode = next_mode
	scale = next_scale
	_t = tokens[mode]
	_gems.clear()
	_build()

func dark() -> bool:
	return mode == "dark"

func color(name: String, alpha := 1.0) -> Color:
	var c := Color.html(_t.get(name, "#ff00ff"))
	c.a *= alpha
	return c

func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = load(DIR + "icons/%s.svg" % name)
	return _icons[name]

## A line icon in a colour, for places that cannot tint one (a window's close button).
func tinted(name: String, c: Color) -> Texture2D:
	var key := "%s/%s" % [name, c.to_html()]
	if not _icons.has(key):
		# The imported icon keeps its SVG, so an export needs no copy of the file.
		var svg := (icon(name) as DPITexture).get_source().replace("'white'", "'#%s'" % c.to_html(false)).replace("\"white\"", "\"#%s\"" % c.to_html(false))
		_icons[key] = DPITexture.create_from_string(svg)
	return _icons[key]

## The world's illustration for an empty list, as its web skin shows it.
func empty_state() -> Texture2D:
	var light := DIR + "skins/%s/empty-state-light.webp" % world
	return load(light if not dark() and ResourceLoader.exists(light) else DIR + "skins/%s/empty-state.webp" % world)

## The world's mark under a session's level, or null where the skin has none.
func level_mark() -> Texture2D:
	return load(DIR + "skins/%s/%s" % [world, LEVEL[world][0]]) if LEVEL.has(world) else null

## The world's icon for a provider, as its web skin shows it.
func provider_icon(id: String) -> Texture2D:
	var ext := "svg" if world == "professional" else "webp"
	var path := DIR + "skins/%s/providers/%s.%s" % [world, id, ext]
	if not ResourceLoader.exists(path):
		path = DIR + "providers/%s.svg" % id
	return load(path) if ResourceLoader.exists(path) else null

## A glossy status gem in a colour, as the web skins draw connection dots.
func gem(c: Color, size := 10) -> Texture2D:
	var key := "%s/%d" % [c.to_html(), size]
	if not _gems.has(key):
		var dark_edge := c.darkened(0.45)
		_gems[key] = DPITexture.create_from_string(("<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 20 20'>"
			+ "<defs><radialGradient id='g' cx='0.35' cy='0.3' r='0.75'><stop offset='0.14' stop-color='#ffffff'/>"
			+ "<stop offset='0.48' stop-color='#%s'/><stop offset='1' stop-color='#%s'/></radialGradient></defs>"
			+ "<circle cx='10' cy='10' r='9' fill='url(#g)'/></svg>") % [size, size, c.to_html(false), dark_edge.to_html(false)])
	return _gems[key]

## One of World's own dialogs: the frame inside its window and no title bar,
## its heading beside a close button that does what the window's did (cancels
## and hides), and its buttons together at the right. After its last add_button.
static func frame_dialog(dialog: AcceptDialog, heading: Label, scrolls := true) -> void:
	dialog.borderless = true
	dialog.theme_type_variation = "Framed"
	var column := heading.get_parent()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	column.move_child(head, heading.get_index())
	column.remove_child(heading)
	head.add_child(heading)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.theme_type_variation = "Close"
	close.icon = load(DIR + "icons/close.svg")
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		dialog.notification(Window.NOTIFICATION_WM_CLOSE_REQUEST)
		dialog.close_requested.emit())
	head.add_child(close)
	var spacers := dialog.get_ok_button().get_parent().get_children().filter(func(c): return not c is Button)
	for spacer in spacers.slice(1):
		spacer.size_flags_horizontal = Control.SIZE_FILL
		spacer.custom_minimum_size.x = 4
	spacers.back().hide()
	if scrolls:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		dialog.remove_child(column)
		scroll.add_child(column)
		dialog.add_child(scroll)
		dialog.set_meta("scroll", scroll)

static func popup_dialog(dialog: AcceptDialog, width: int) -> void:
	_cap_dialog(dialog)
	dialog.popup_centered(Vector2i(width, 0))

static func refit_dialog(dialog: AcceptDialog) -> void:
	if not dialog.visible:
		return
	var room := _cap_dialog(dialog)
	dialog.size = Vector2i(dialog.size.x, 0)
	dialog.position = (Vector2i(room) - dialog.size) / 2

static func _cap_dialog(dialog: AcceptDialog) -> Vector2:
	var room := dialog.get_parent().get_viewport().get_visible_rect().size
	var scroll: ScrollContainer = dialog.get_meta("scroll")
	var chrome: float = dialog.get_theme_stylebox("panel").get_minimum_size().y + dialog.get_ok_button().get_parent().get_combined_minimum_size().y + dialog.get_theme_constant("buttons_separation")
	scroll.custom_minimum_size.y = minf((scroll.get_child(0) as Control).get_combined_minimum_size().y, maxf(room.y - 32.0 - chrome, 48.0))
	return room

## A heading's rule: the skin's gold, fading out to the right. YardUI paints
## every one it finds by its "section_rule" meta when the look changes.
static func section_rule() -> TextureRect:
	var line := TextureRect.new()
	line.custom_minimum_size.y = 1
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_meta("section_rule", true)
	return line

## A name tag's plate: dark over any world, edged in its hall's colour.
## Lit (chosen or under the pointer), it is ringed in gold as the web's are.
func tag_box(edge: Color, on: bool) -> StyleBoxFlat:
	var s := _flat(Color(0.05, 0.08, 0.09, 0.94 if on else 0.84), 5)
	s.border_color = edge
	s.border_width_bottom = 2
	if on:
		s.bg_color = Color(0.09, 0.16, 0.17, 0.96)
		s.border_width_left = 1
		s.border_width_top = 1
		s.border_width_right = 1
		s.border_color = Color("#e0bf79")
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 8 if on else 5
	s.shadow_offset = Vector2(0, 2)
	_margins(s, 9, 4, 9, 5)
	return s

## The brand's own face, the same in every world (docs/SKINS.md leaves the brand alone).
func brand_font() -> Font:
	return _font("cinzel", 700)

func display_font() -> Font:
	return _font(tokens.font, 700 if tokens.font != "inter" else 650)

func body_font(weight := 400) -> Font:
	return _font("inter", weight)

static func font(name: String, weight: int) -> Font:
	return _font(name, weight)

## A font file at a weight, falling back to Inter for glyphs it lacks.
static func _font(name: String, weight: int) -> Font:
	var key := "%s/%d" % [name, weight]
	if not _fonts.has(key):
		var file: FontFile = load(DIR + "fonts/%s.woff2" % name)
		var v := FontVariation.new()
		v.base_font = file
		if file.get_supported_variation_list().has(TextServerManager.get_primary_interface().name_to_tag("wght")):
			v.variation_opentype = { TextServerManager.get_primary_interface().name_to_tag("wght"): weight }
		if name != "inter":
			v.fallbacks = [_font("inter", 500)]
		_fonts[key] = v
	return _fonts[key]

func _build() -> void:
	var t := theme
	t.clear()
	t.default_font = body_font()
	t.default_font_size = SIZE.body
	var text := color("text")
	var muted := color("muted")
	var heading := color("heading")

	t.set_color("font_color", "Label", text)
	t.set_color("default_color", "RichTextLabel", text)
	t.set_font("bold_font", "RichTextLabel", body_font(700))
	_label("Title", display_font(), SIZE.title, color("gold-ink") if dark() else heading)
	t.set_color("font_shadow_color", "Title", Color(0, 0, 0, 0.55) if dark() else Color(1, 1, 1, 0.6))
	t.set_constant("shadow_offset_y", "Title", 2)
	t.set_constant("shadow_outline_size", "Title", 6)
	_label("Subtitle", body_font(), SIZE.small, muted)
	_label("Heading", display_font(), SIZE.heading, heading)
	_label("Section", display_font(), SIZE.heading, heading)
	var above := StyleBoxEmpty.new()
	above.content_margin_top = 16
	theme.set_stylebox("normal", "Section", above)
	_label("Field", body_font(600), SIZE.small, text)
	var field_above := StyleBoxEmpty.new()
	field_above.content_margin_top = 8
	theme.set_stylebox("normal", "Field", field_above)
	_label("Muted", body_font(), SIZE.small, muted)
	_label("Small", body_font(), SIZE.tiny, muted)
	_label("Note", body_font(500), SIZE.small, color("warn"))
	_label("Strong", body_font(600), SIZE.body, text)
	_label("Alert", body_font(600), SIZE.body, color("danger"))
	# Name tags sit over the world in every theme, so their text is always light.
	_label("TagName", body_font(600), 14, Color("#f8ecd4"))
	_label("TagState", body_font(500), SIZE.tiny, Color("#cfc7b6"))
	if LEVEL.has(world):
		_label("Level", display_font(), 16, Color(LEVEL[world][1]))
		theme.set_color("font_shadow_color", "Level", Color(0, 0, 0, 0.8))
		theme.set_constant("shadow_offset_y", "Level", 1)
		theme.set_constant("shadow_outline_size", "Level", 4)
	else:
		_label("Level", body_font(600), SIZE.tiny, text)
	for type in ["TagName", "TagState"]:
		theme.set_color("font_shadow_color", type, Color(0, 0, 0, 0.7))
		theme.set_constant("shadow_offset_y", type, 1)
		theme.set_constant("shadow_offset_x", type, 0)

	_panels()
	_buttons()
	_fields()
	_lists()

func _label(type: String, font: Font, size: int, c: Color) -> void:
	theme.set_type_variation(type, "Label")
	theme.set_font("font", type, font)
	theme.set_font_size("font_size", type, size)
	theme.set_color("font_color", type, c)

func _panels() -> void:
	var t := theme
	var bar := _flat(Color.html(_t.bar) if _t.has("bar") else color("surface", 0.9), 0)
	bar.border_width_bottom = 1
	bar.border_color = color("gold", 0.35) if not _t.has("rule") else Color(0, 0, 0, 0)
	_margins(bar, 16, 10, 16, 10)
	t.set_type_variation("Bar", "PanelContainer")
	t.set_stylebox("panel", "Bar", bar)
	for role in ["side", "dialog"]:
		var box: StyleBox = _framed(FRAMES[world][role], color("surface"), PAD[role]) if FRAMES.has(world) else _surface(role)
		var type := "Side" if role == "side" else "Dialog"
		t.set_type_variation(type, "PanelContainer")
		t.set_stylebox("panel", type, box)
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	var inset := _flat(color("surface-2", 0.6), maxi(int(_t.radius), 4))
	_margins(inset, 12, 8, 12, 8)
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", inset)
	var pill := _flat(color("surface-2", 0.9), 999)
	pill.border_width_left = 1
	pill.border_width_top = 1
	pill.border_width_right = 1
	pill.border_width_bottom = 1
	pill.border_color = color("gold", 0.3)
	_margins(pill, 10, 4, 10, 4)
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", pill)
	t.set_type_variation("Failed", "PanelContainer")
	t.set_stylebox("panel", "Failed", _flat(color("danger", 0.3), 0))
	var failed := _flat(color("surface"), int(_t.radius))
	failed.set_border_width_all(2)
	failed.border_color = color("danger")
	_margins(failed, PAD.side.x, PAD.side.y, PAD.side.x, PAD.side.y)
	t.set_type_variation("FailedBanner", "PanelContainer")
	t.set_stylebox("panel", "FailedBanner", failed)
	var tip := _surface("dialog")
	_margins(tip, 10, 6, 10, 7)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", color("text"))
	t.set_font_size("font_size", "TooltipLabel", SIZE.small)
	# A dialog window: the world's dialog frame drawn around it and its title
	# bar, the surface inside, and a close button in the skin's colours.
	var frame: StyleBox = t.get_stylebox("panel", "Dialog").duplicate()
	var edge := 14.0 if not FRAMES.has(world) else float(FRAMES[world].dialog[2]) * 0.7
	frame.expand_margin_left = edge
	frame.expand_margin_right = edge
	frame.expand_margin_bottom = edge
	frame.expand_margin_top = TITLE + edge * 0.6
	t.set_stylebox("embedded_border", "Window", frame)
	t.set_stylebox("embedded_unfocused_border", "Window", frame)
	t.set_constant("title_height", "Window", TITLE)
	t.set_color("title_color", "Window", color("heading"))
	t.set_font("title_font", "Window", display_font())
	t.set_font_size("title_font_size", "Window", SIZE.heading)
	t.set_icon("close", "Window", tinted("close", color("muted")))
	t.set_icon("close_pressed", "Window", tinted("close", color("gold-ink") if world != "professional" else color("accent")))
	t.set_constant("close_h_offset", "Window", 18)
	t.set_constant("close_v_offset", "Window", 16)
	var inside := _flat(color("surface"), 0)
	_margins(inside, 6, 4, 6, 6)
	t.set_stylebox("panel", "AcceptDialog", inside)
	t.set_constant("buttons_separation", "AcceptDialog", 12)
	t.set_type_variation("Framed", "AcceptDialog")
	t.set_stylebox("panel", "Framed", t.get_stylebox("panel", "Dialog"))
	t.set_constant("buttons_separation", "Framed", 24)
	t.set_constant("buttons_min_width", "Framed", 112)

## A plain panel for skins without frames: the surface, a hairline border and
## the skin's radius, lifted off the world by a soft shadow.
func _surface(role: String) -> StyleBoxFlat:
	var s := _flat(color("surface"), int(_t.radius) + (2 if role == "side" else 4))
	s.border_color = color("border") if world == "professional" else color("gold", 0.28)
	if world == "grove":
		# Grove's cards: rounder, edged toward the skin's green.
		s.set_corner_radius_all(18)
		s.border_color = color("border").lerp(color("accent"), 0.35)
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.38) if dark() else Color(0.27, 0.19, 0.05, 0.14)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	var pad: Vector2 = PAD[role]
	_margins(s, pad.x, pad.y, pad.x, pad.y)
	return s

## A frame drawn from the skin's image at the screen's scale, filled inside.
func _framed(spec: Array, fill: Color, pad: Vector2) -> StyleBoxTexture:
	var file: String = DIR + "skins/%s/%s" % [world, spec[0]]
	var slice: float = spec[1]
	var border: float = spec[2]
	var k := border * scale / slice
	var art: Image
	if spec[0] == "@hud":
		art = Image.new()
		art.load_svg_from_string(_hud(), k)
	elif file.ends_with(".svg"):
		# The imported frame keeps its SVG; an export has no copy of the file itself.
		art = Image.new()
		art.load_svg_from_string((load(file) as DPITexture).get_source(), k)
	else:
		art = (load(file) as Texture2D).get_image()
		art.decompress()
		art.clear_mipmaps()
		art.convert(Image.FORMAT_RGBA8)
		art.resize(maxi(4, roundi(art.get_width() * k)), maxi(4, roundi(art.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	var size := art.get_size()
	var inset := roundi(float(spec[3]) * k)
	var framed := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	framed.fill_rect(Rect2i(Vector2i(inset, inset), size - Vector2i(inset, inset) * 2), fill)
	framed.blend_rect(art, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var tex := ImageTexture.create_from_image(framed)
	tex.set_size_override(Vector2i((Vector2(size) / scale).round()))
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.set_texture_margin_all(border)
	# The padding starts where the frame's art ends.
	var edge := float(spec[3]) * k / scale
	_margins(s, pad.x + edge, pad.y + edge, pad.x + edge, pad.y + edge)
	return s

## A hairline border with bracketed corners in the accent, 64 units square.
func _hud() -> String:
	var hud := color("accent")
	var line := color("border")
	return ("<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'>"
		+ "<rect x='0.5' y='0.5' width='63' height='63' fill='none' stroke='#%s' stroke-width='1'/>"
		+ "<path d='M1 17 V1 H17 M47 1 H63 V17 M63 47 V63 H47 M17 63 H1 V47' fill='none' stroke='#%s' stroke-opacity='0.75' stroke-width='2'/></svg>") % [line.to_html(false), hud.to_html(false)]

func _buttons() -> void:
	var t := theme
	var r := int(_t.radius)
	var normal := _flat(color("surface-2", 0.92), r)
	normal.set_border_width_all(1)
	normal.border_color = color("border") if world == "professional" else color("gold", 0.32)
	_margins(normal, 14, 8, 14, 8)
	var hover := normal.duplicate()
	hover.bg_color = color("surface", 0.98)
	hover.border_color = color("gold", 0.7) if world != "professional" else color("accent", 0.6)
	var pressed := normal.duplicate()
	pressed.bg_color = color("accent-fill", 0.22)
	pressed.border_color = color("accent", 0.7)
	var disabled := normal.duplicate()
	disabled.bg_color = color("surface-2", 0.5)
	disabled.border_color = color("border", 0.5)
	var focus := _flat(Color(0, 0, 0, 0), r + 2)
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = color("focus")
	focus.set_expand_margin_all(2)
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, color("text"))
		t.set_color("font_hover_color", type, color("heading"))
		t.set_color("font_pressed_color", type, color("heading"))
		t.set_color("font_hover_pressed_color", type, color("heading"))
		t.set_color("font_focus_color", type, color("text"))
		t.set_color("font_disabled_color", type, color("muted", 0.7))
		t.set_color("icon_normal_color", type, color("muted"))
		t.set_color("icon_hover_color", type, color("gold-ink") if world != "professional" else color("accent"))
		t.set_color("icon_pressed_color", type, color("gold-ink") if world != "professional" else color("accent"))
		t.set_color("icon_hover_pressed_color", type, color("gold-ink") if world != "professional" else color("accent"))
		t.set_color("icon_focus_color", type, color("text"))
		t.set_constant("h_separation", type, 8)
		t.set_constant("icon_max_width", type, 18)
	t.set_icon("arrow", "OptionButton", icon("chevron"))
	t.set_constant("arrow_margin", "OptionButton", 12)
	# The chevron is white: drawn in the button's text colour, it shows by day too.
	t.set_constant("modulate_arrow", "OptionButton", 1)

	# Quiet: no plate until hovered, for the top bar's toggles.
	t.set_type_variation("Quiet", "Button")
	var quiet := _flat(Color(0, 0, 0, 0), r)
	_margins(quiet, 10, 8, 10, 8)
	var quiet_hover := quiet.duplicate()
	quiet_hover.bg_color = color("surface-2", 0.7)
	var quiet_on := quiet.duplicate()
	quiet_on.bg_color = color("accent-fill", 0.18)
	quiet_on.border_width_bottom = 2
	quiet_on.border_color = color("gold") if world != "professional" else color("accent")
	t.set_stylebox("normal", "Quiet", quiet)
	t.set_stylebox("hover", "Quiet", quiet_hover)
	t.set_stylebox("pressed", "Quiet", quiet_on)
	t.set_stylebox("hover_pressed", "Quiet", quiet_on)

	# Primary: the skin's filled accent, as the web's main actions are.
	t.set_type_variation("Primary", "Button")
	var primary := _flat(color("accent-fill"), r)
	primary.set_border_width_all(1)
	primary.border_color = color("gold", 0.8) if world == "guild" else color("accent-fill").lightened(0.2)
	_margins(primary, 18, 10, 18, 10)
	var primary_hover := primary.duplicate()
	primary_hover.bg_color = color("accent-fill").lightened(0.12)
	primary_hover.shadow_color = color("accent-fill", 0.45)
	primary_hover.shadow_size = 10
	var primary_down := primary.duplicate()
	primary_down.bg_color = color("accent-fill").darkened(0.12)
	t.set_stylebox("normal", "Primary", primary)
	t.set_stylebox("hover", "Primary", primary_hover)
	t.set_stylebox("pressed", "Primary", primary_down)
	t.set_stylebox("hover_pressed", "Primary", primary_down)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Primary", color("accent-text"))
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		t.set_color(c, "Primary", color("accent-text"))
	t.set_font("font", "Primary", body_font(600))

	# Choice: one of a set, filled in the accent while chosen.
	t.set_type_variation("Choice", "Button")
	var choices := {"normal": normal, "hover": hover, "pressed": primary_down, "hover_pressed": primary, "disabled": disabled}
	for state in choices:
		var choice: StyleBoxFlat = choices[state].duplicate()
		_margins(choice, 10, 8, 10, 8)
		t.set_stylebox(state, "Choice", choice)
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Choice", color("accent-text"))

	t.set_type_variation("Danger", "Button")
	var danger := normal.duplicate()
	danger.border_color = color("danger", 0.6)
	var danger_hover := danger.duplicate()
	danger_hover.bg_color = color("danger", 0.16)
	danger_hover.border_color = color("danger")
	t.set_stylebox("normal", "Danger", danger)
	t.set_stylebox("hover", "Danger", danger_hover)
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "Danger", color("danger"))

	# Close: a dialog's own close button, beside its heading.
	t.set_type_variation("Close", "Button")
	var close := quiet.duplicate()
	_margins(close, 6, 6, 6, 6)
	var close_hover := quiet_hover.duplicate()
	_margins(close_hover, 6, 6, 6, 6)
	t.set_stylebox("normal", "Close", close)
	t.set_stylebox("hover", "Close", close_hover)
	t.set_stylebox("pressed", "Close", close_hover)
	t.set_stylebox("hover_pressed", "Close", close_hover)

	# Row: a list entry; lit in the accent while chosen.
	t.set_type_variation("Row", "Button")
	var row := _flat(Color(0, 0, 0, 0), maxi(r - 1, 4))
	row.set_border_width_all(1)
	row.border_color = Color(0, 0, 0, 0)
	_margins(row, 10, 8, 10, 8)
	var row_hover := row.duplicate()
	row_hover.bg_color = color("surface-2", 0.85)
	var row_on := row.duplicate()
	row_on.bg_color = color("accent", 0.14)
	row_on.border_color = color("gold", 0.45) if world != "professional" else color("accent", 0.45)
	t.set_stylebox("normal", "Row", row)
	t.set_stylebox("hover", "Row", row_hover)
	t.set_stylebox("pressed", "Row", row_on)
	t.set_stylebox("hover_pressed", "Row", row_on)
	# Inside the row, so a scrolling list does not clip it.
	var row_focus := focus.duplicate()
	row_focus.set_expand_margin_all(0)
	row_focus.set_corner_radius_all(maxi(r - 1, 4))
	t.set_stylebox("focus", "Row", row_focus)

	# Switches for the yes-or-no settings.
	for type in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, quiet)
		t.set_stylebox("hover", type, quiet_hover)
		t.set_stylebox("pressed", type, quiet)
		t.set_stylebox("hover_pressed", type, quiet_hover)
		t.set_icon("checked", type, _switch(true))
		t.set_icon("unchecked", type, _switch(false))
		t.set_icon("checked_disabled", type, _switch(true))
		t.set_icon("unchecked_disabled", type, _switch(false))
		t.set_color("font_pressed_color", type, color("text"))
		t.set_constant("check_v_offset", type, 0)
		# The switch at its own size, not a button icon's.
		t.set_constant("icon_max_width", type, 0)
		t.set_constant("h_separation", type, 10)

func _switch(on: bool) -> Texture2D:
	var track := color("accent-fill") if on else color("muted", 0.45)
	var knob := Color.WHITE if on else color("surface")
	var edge := color("gold") if world != "professional" else color("border")
	# Colours as #rrggbb and an opacity, which is what the SVG renderer reads.
	return DPITexture.create_from_string(("<svg xmlns='http://www.w3.org/2000/svg' width='34' height='20' viewBox='0 0 34 20'>"
		+ "<rect x='1' y='2' width='32' height='16' rx='8' fill='#%s' fill-opacity='%.2f' stroke='#%s' stroke-opacity='0.5' stroke-width='1'/>"
		+ "<circle cx='%d' cy='10' r='6' fill='#%s'/></svg>") % [track.to_html(false), track.a, edge.to_html(false), 25 if on else 9, knob.to_html(false)])

func _fields() -> void:
	var t := theme
	var r := int(_t.radius)
	var field := _flat(color("surface-2", 0.95), r)
	field.set_border_width_all(1)
	field.border_color = color("border")
	_margins(field, 10, 7, 10, 7)
	var focused := field.duplicate()
	focused.border_color = color("focus")
	focused.set_border_width_all(2)
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, focused)
		t.set_stylebox("read_only", type, field)
		t.set_color("font_color", type, color("text"))
		t.set_color("font_readonly_color" if type == "TextEdit" else "font_uneditable_color", type, color("text"))
		t.set_color("font_placeholder_color", type, color("muted", 0.85))
		t.set_color("caret_color", type, color("accent"))
		t.set_color("selection_color", type, color("accent", 0.3))
	var lane := _flat(color("surface-2", 0.95), r)
	lane.set_border_width_all(1)
	lane.border_color = color("border")
	t.set_stylebox("background", "ProgressBar", lane)
	t.set_stylebox("fill", "ProgressBar", _flat(color("accent"), r))
	var track := _flat(color("border"), 2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	var filled := track.duplicate()
	filled.bg_color = color("accent")
	t.set_stylebox("grabber_area", "HSlider", filled)
	var active := filled.duplicate()
	active.bg_color = color("focus")
	t.set_stylebox("grabber_area_highlight", "HSlider", active)
	var knobs := {"grabber": "accent", "grabber_highlight": "focus", "grabber_disabled": "muted"}
	for state in knobs:
		var c := color(knobs[state])
		t.set_icon(state, "HSlider", DPITexture.create_from_string("<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18'><circle cx='9' cy='9' r='7' fill='#%s' stroke='#%s' stroke-width='2'/></svg>" % [c.to_html(false), color("surface").to_html(false)]))
	var slider_focus := focused.duplicate()
	slider_focus.draw_center = false
	t.set_stylebox("focus", "HSlider", slider_focus)
	t.set_color("font_color", "LinkButton", color("accent"))
	t.set_color("font_hover_color", "LinkButton", color("gold-ink"))

func _lists() -> void:
	var t := theme
	var popup := _surface("dialog")
	_margins(popup, 6, 6, 6, 6)
	t.set_stylebox("panel", "PopupMenu", popup)
	var held := popup.duplicate()
	_margins(held, 12, 12, 12, 12)
	t.set_stylebox("panel", "PopupPanel", held)
	var hover := _flat(color("accent", 0.16), maxi(int(_t.radius) - 2, 3))
	t.set_stylebox("hover", "PopupMenu", hover)
	t.set_color("font_color", "PopupMenu", color("text"))
	t.set_color("font_hover_color", "PopupMenu", color("heading"))
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 14)
	t.set_icon("radio_checked", "PopupMenu", icon("check"))
	t.set_icon("checked", "PopupMenu", icon("check"))
	var grab := _flat(color("gold", 0.45) if world != "professional" else color("muted", 0.5), 4)
	var grab_hover := _flat(color("gold", 0.75) if world != "professional" else color("muted", 0.8), 4)
	var lane := StyleBoxFlat.new()
	lane.bg_color = Color(0, 0, 0, 0)
	lane.content_margin_left = 6
	lane.content_margin_right = 0
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, lane)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hover)
		t.set_stylebox("grabber_pressed", type, grab_hover)

func _flat(c: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s

func _margins(s: StyleBox, l: float, top: float, r: float, b: float) -> void:
	s.content_margin_left = l
	s.content_margin_top = top
	s.content_margin_right = r
	s.content_margin_bottom = b
