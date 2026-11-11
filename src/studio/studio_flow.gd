class_name StudioFlow
extends Node
## One piece being made: the panel's choices made into pieces on a worker
## thread (StudioJob), shown on the stage, then saved as a folder and listed
## under Your pieces. One operation runs at a time. The flow frees itself once
## it has ended and nothing is still under way: a make left running on its
## worker is freed when it's done, never shown; leaving waits for a save
## under way.

signal ended

var panel: StudioPanel
var pieces: PieceLibrary
var stage: StudioStage
var job := StudioJob.new()
var active := false
## The player's piece Studio is making a new version of, or "" for a new one:
## once a new piece is added, Studio is editing it.
var editing := ""
## The last make's result: what to write when the player keeps it.
var _made := {}
## A make the player left before it finished: its result is thrown away.
var _stale := false
## "save" while the piece is being saved, or "".
var _keeping := ""
## Leave was asked while a save was under way: Studio leaves once it's saved.
var _leaving := false
const FINISHING := "Finishing your save…"
## Live recolours: every change is numbered, and only the newest one asked
## for is ever shown; a change waits until the player pauses (RECOLOUR_WAIT).
const RECOLOUR_WAIT := 0.15
## A recolor previews at most this many pixels a side; it's saved whole.
const PREVIEW_SIDE := 1024
var _recolour := {}
var _wanted := 0
var _asked := 0
var _settle := Timer.new()

## Opens the panel for `world` at `theme`: for a new piece, or to edit the
## player's piece `edit`. `tools` names each crew.
func start(with_panel: StudioPanel, with_stage: StudioStage, library: PieceLibrary, tools: Dictionary, world: String, theme: String, edit := "") -> void:
	panel = with_panel
	stage = with_stage
	pieces = library
	active = true
	stage.set_world(world, theme)
	_settle.one_shot = true
	_settle.wait_time = RECOLOUR_WAIT
	_settle.timeout.connect(_run_recolour)
	add_child(_settle)
	panel.slot_chosen.connect(_facts)
	panel.make_requested.connect(_make)
	panel.recolour_changed.connect(_recolour_changed)
	panel.adjusted.connect(_adjusted)
	panel.motion_chosen.connect(stage.play)
	panel.theme_chosen.connect(_light)
	panel.save_requested.connect(_save)
	panel.leave_requested.connect(_leave)
	job.finished.connect(_made_one)
	editing = edit if pieces.pieces.has(edit) else ""
	panel.open(world, tools, theme, _editing())
	panel.show()
	if editing != "":
		panel.reopen(pieces.pieces[editing].get("studio", {}))

## The piece being edited, as the panel shows it, or {}.
func _editing() -> Dictionary:
	var p: Dictionary = pieces.pieces.get(editing, {})
	if p.is_empty():
		return {}
	return { "id": editing, "title": p.title, "where": { "world": p.world, "kind": p.kind, "crew": p.get("crew", "") } }

## The piece is over: the stage empty, the panel closed.
func finish() -> void:
	if not active:
		return
	active = false
	_stale = job.running
	_settle.stop()
	for s in [panel.slot_chosen, panel.make_requested, panel.recolour_changed, panel.adjusted, panel.motion_chosen, panel.theme_chosen, panel.save_requested, panel.leave_requested]:
		for c in s.get_connections():
			s.disconnect(c.callable)
	stage.clear()
	panel.hide()
	ended.emit()
	_free_when_idle()

func _leave() -> void:
	if _keeping == "":
		finish()
		return
	_leaving = true
	panel.working(FINISHING)

func _exit_tree() -> void:
	finish()
	_free_made()

func _light(theme: String) -> void:
	stage.set_theme(theme)

## The slot's facts in words, from its default.
func _facts(where: Dictionary) -> void:
	var model := Studio.default_model(where)
	if model == null:
		panel.show_facts("")
		return
	var yard_extras := YardRig.extras(model)
	var words := []
	words.append("The %s it replaces stands %.1f m tall" % ["character" if where.kind == "character" else "companion", float(yard_extras.get("height", 0.0))])
	if where.kind == "character":
		words.append("walks %.2f m a step" % (float(yard_extras.get("stride", 0.0)) / 2.0))
		if not yard_extras.get("events", []).is_empty():
			words.append("strikes as it works")
	else:
		words.append("hovers beside each session's character, at a little under half size")
	model.free()
	panel.show_facts(", ".join(words) + ".")

## The staged copies stay with the result, to make it again as it's adjusted.
func _make(spec: Dictionary) -> void:
	if job.running or _keeping != "":
		return
	panel.working("Studio is working on it… a detailed model takes up to half a minute.")
	var where: Dictionary = spec.where
	var options: Dictionary = spec.get("options", {})
	var files: Array = spec.get("files", [])
	var recolour: Dictionary = spec.get("recolour", {})
	job.run(get_tree(), func(staged: Dictionary) -> Dictionary:
		var out := Studio.work(where, staged.get("paths", []), recolour, options)
		out.spec = { "where": where, "files": files, "options": options }
		if not staged.is_empty():
			out.staged = staged
			if out.has("pieces"):
				out.notes = out.notes + staged.notes
		return out,
		func() -> Dictionary:
			if files.is_empty():
				return {}
			return await StudioSource.stage(pieces.validator, files))

## The player changed how the piece fits. A character's height shows at
## once, its exact fit made only when it's saved; companions, quick to make,
## turn at once and are made again as set, the newest change only.
func _adjusted(spec: Dictionary) -> void:
	if _made.is_empty() or not _made.has("pieces"):
		return
	_made.erase("kept_in")
	var built: Dictionary = _made.spec.options
	spec = { "where": _made.where, "files": _made.spec.files, "options": spec.options }
	if built.has("map") and not spec.options.has("map"):
		spec.options.map = built.map
	if spec.where.kind == "character":
		_made.want = spec.options
		stage.resize(float(spec.options.get("height_share", 1.0)) / float(built.get("height_share", 1.0)))
		return
	stage.turn(float(spec.options.get("turn", 0.0)) - float(built.get("turn", 0.0)))
	_recolour_changed(spec)

## The player changed a recolor or a companion's fit, or left recoloring
## ({}): anything asked for before is now stale.
func _recolour_changed(spec: Dictionary) -> void:
	_wanted += 1
	_recolour = spec
	if spec.is_empty():
		_settle.stop()
		stage.clear()
		_free_made()
		return
	if _made.get("spec") == spec and not job.running:
		_asked = _wanted
		panel.recolour_shown(spec.where.kind, stage.motion, _made.get("colors", []))
		return
	_settle.start()

func _run_recolour() -> void:
	if not active or job.running or _keeping != "" or _recolour.is_empty() or _asked == _wanted:
		return
	_asked = _wanted
	var spec := _recolour
	var asked := _asked
	var staged: Dictionary = _made.get("staged", {}) if not spec.get("files", []).is_empty() else {}
	job.run(get_tree(), func() -> Dictionary:
		var out := Studio.work(spec.where, staged.get("paths", []), spec.get("recolour", {}), spec.get("options", { "preview": PREVIEW_SIDE }))
		out.asked = asked
		out.spec = spec
		if not staged.is_empty():
			out.staged = staged
		return out)

## Back on the main thread: show what was made, or say why not. A recolour
## overtaken by a newer change is let go, and the newest one asked for.
func _made_one(result: Dictionary) -> void:
	if result.has("exact"):
		return
	var stale_recolour: bool = result.has("asked") and result.asked != _wanted
	if _stale or not active or stale_recolour:
		_stale = false
		_let_go(result)
		_free_when_idle()
		if active and _settle.is_stopped():
			_run_recolour()
		return
	if result.has("unsure"):
		# The last piece shown isn't this model: the stage waits for it.
		stage.clear()
		panel.show_bones(result.unsure, result.map, result.skeleton.names)
		_let_go(result)
		return
	if result.has("reason"):
		panel.show_reason(result.reason)
		_let_go(result)
		return
	if result.get("staged", {}) == _made.get("staged", {}):
		_made.erase("staged")
	_free_made()
	_made = result
	var shown := []
	if result.has("recoloured"):
		shown = result.recoloured.map(func(m): return m.duplicate())
		if result.where.kind == "companion":
			shown.push_front(result.host)
			result.erase("host")
	elif result.where.kind == "character":
		shown = [StudioExport.scene(result.pieces[0], "character"), result.default]
		result.erase("default")
	else:
		shown = [result.host] + result.pieces.map(func(p): return StudioExport.scene(p, "companion"))
		result.erase("host")
	stage.show_models(shown, result.where.kind)
	if result.has("asked"):
		stage.play(stage.motion if stage.motion != "" else "work" if result.where.kind == "character" else "idle")
		if result.has("recoloured"):
			panel.recolour_shown(result.where.kind, stage.motion, result.get("colors", []))
		else:
			panel.adjusted_shown()
		return
	stage.play("work" if result.where.kind == "character" else "idle")
	panel.show_preview(result.where.kind, result.get("notes", []), stage.motion)

## The made piece as it's saved: a recolor previewed smaller, made again at
## full size; a character resized on the stage, fitted at that height. ""
## or why it couldn't be.
func _exact() -> String:
	if _made.has("want") and _made.want != _made.spec.options:
		return await _refit()
	if not _made.get("reduced", false):
		return ""
	_working("Recoloring it at full size…")
	var spec: Dictionary = _made.spec
	job.run(get_tree(), func() -> Dictionary:
		var out := Studio.work(spec.where, [], spec.recolour, {})
		out.exact = true
		return out)
	var full: Dictionary = await job.finished
	if full.has("reason"):
		return full.reason
	for m in _made.recoloured:
		m.free()
	_made.recoloured = full.recoloured
	_made.reduced = false
	full.erase("recoloured")
	_free_result(full)
	return ""

func _refit() -> String:
	var spec := { "where": _made.where, "files": _made.spec.files, "options": _made.want }
	_working("Fitting it at %d%% height… a detailed model takes up to half a minute." % roundi(float(spec.options.get("height_share", 1.0)) * 100.0))
	var staged: Array = _made.staged.paths
	job.run(get_tree(), func() -> Dictionary:
		var out := Studio.work(spec.where, staged, {}, spec.options)
		out.exact = true
		return out)
	var fitted: Dictionary = await job.finished
	if not fitted.has("pieces"):
		var reason: String = fitted.get("reason", "its bones could not be read again")
		_free_result(fitted)
		return reason
	_made.pieces = fitted.pieces
	_made.notes = fitted.notes
	_made.spec = spec
	_made.erase("want")
	if active:
		stage.show_models([StudioExport.scene(fitted.pieces[0], "character"), fitted.default], "character")
		stage.play(stage.motion)
	else:
		fitted.default.free()
	return ""

## Writes the made piece's folder; "" or why it couldn't.
func _write(folder: String, title: String) -> String:
	var where: Dictionary = _made.where
	var models: Array = _made.recoloured if _made.has("recoloured") else _made.pieces.map(func(p): return StudioExport.scene(p, where.kind))
	var manifest := { "format": 1, "kind": where.kind, "world": where.world, "title": title }
	if where.kind == "character":
		manifest.crew = where.crew
	var reason := StudioExport.save(models, folder, manifest)
	if not _made.has("recoloured"):
		for m in models:
			m.free()
	return reason

## How the made piece was made, for editing it later: its model files and
## choices, or the look recolored and how; colors as #RRGGBB.
func _recipe() -> Dictionary:
	var spec: Dictionary = _made.get("spec", {})
	if not spec.get("recolour", {}).is_empty():
		var change: Dictionary = spec.recolour.change.duplicate()
		for key in ["pick", "tint"]:
			if change.get(key) is Color:
				change[key] = "#" + change[key].to_html(false)
		return { "recolour": { "which": spec.recolour.which, "change": change } }
	if not spec.get("files", []).is_empty():
		return { "files": spec.files, "options": spec.options }
	return {}

## Saves the made piece's folder in `parent`, named for its title, never over
## a folder already there; written under another name first, so a folder
## with its name is always whole. A saved piece is listed under Your pieces,
## with how it was made: a new one, or the new version of the one being edited.
func _save(parent: String, title: String) -> void:
	if _made.is_empty() or not _idle():
		return
	var name := title.validate_filename().strip_edges()
	name = name if name != "" else "piece"
	_keeping = "save"
	panel.working("Saving it in %s…" % parent)
	await _shown()
	var reason := await _exact()
	var part := parent.path_join(".%s.part" % name)
	var folder := ""
	if reason == "":
		_working("Saving it in %s…" % parent)
		StudioFiles.remove_tree(part)
		reason = _write(part, title)
	var n := 1
	while reason == "" and folder == "":
		var free := parent.path_join(name if n == 1 else "%s (%d)" % [name, n])
		n += 1
		if DirAccess.dir_exists_absolute(free) or FileAccess.file_exists(free):
			continue
		if DirAccess.rename_absolute(part, free) == OK:
			folder = free
		elif not DirAccess.dir_exists_absolute(free):
			reason = "it could not be moved into %s" % free
	if reason != "":
		StudioFiles.remove_tree(part)
		_kept("It could not be saved: %s. Nothing was left in %s." % [reason, parent], true)
		return
	var id := editing if editing != "" else "local:studio-%d" % int(Time.get_unix_time_from_system() * 1000)
	var listed := await pieces.add_local(folder, id, _recipe())
	if pieces.pieces.get(listed, {}).get("error", "x") == "":
		pieces.pieces[listed].saved = folder
		pieces.keep()
		editing = listed
		if active:
			panel.editing = _editing()
	_kept("Saved to %s." % folder)

## A save is over: said in the panel if Studio is still open.
func _kept(text: String, failed := false) -> void:
	_keeping = ""
	var leave := _leaving and not failed
	_leaving = false
	if active:
		panel.show_done(text)
	if leave:
		finish()
		return
	_free_when_idle()

func _working(text: String) -> void:
	if active:
		panel.working(FINISHING if _leaving else text)

func _idle() -> bool:
	return active and not job.running and _keeping == ""

## Two frames, so the panel shows what's under way before a write holds the game.
func _shown() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _free_when_idle() -> void:
	if not active and not job.running and _keeping == "":
		_free_made()
		StudioRecolour.forget()
		queue_free()

func _free_made() -> void:
	_unstage(_made)
	_free_result(_made)
	_made = {}

## A result that won't be shown: freed, with its staged models unless the
## made piece is still made from them.
func _let_go(result: Dictionary) -> void:
	if result.get("staged", {}) != _made.get("staged", {}):
		_unstage(result)
	_free_result(result)

static func _unstage(result: Dictionary) -> void:
	if result.has("staged"):
		StudioFiles.remove_tree(result.staged.dir)

static func _free_result(result: Dictionary) -> void:
	for key in ["default", "host"]:
		if result.get(key) is Node and is_instance_valid(result[key]):
			result[key].free()
	for m in result.get("recoloured", []):
		if is_instance_valid(m):
			m.free()
