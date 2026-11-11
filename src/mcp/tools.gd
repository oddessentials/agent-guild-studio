class_name McpTools
extends RefCounted
## The tools an agent gets. Each checks its arguments against its own schema,
## then runs Studio as its command line does (Studio.run), with no window:
## the piece is made, written as a folder and checked.

const MAKING := ["make_character", "make_companions", "recolor_look", "check_piece"]
const LOOKS := ["look0", "look1", "look2"]
const HELPERS := ["agent", "shell"]

var server: McpServer
var _defs: Array = []
var _by_name := {}

func _init(owner: McpServer) -> void:
	server = owner
	_defs = _definitions()
	for d in _defs:
		_by_name[d.name] = d

func has(name: String) -> bool:
	return _by_name.has(name)

func definitions() -> Array:
	return _defs

func is_async(name: String) -> bool:
	return name in MAKING

func is_long(_name: String) -> bool:
	return false

func can_run_while_rendering(name: String) -> bool:
	return name not in MAKING

func waits_for_person(_name: String) -> bool:
	return false

func failure(text: String, data: Variant = null) -> Dictionary:
	var out := {"content": [{"type": "text", "text": text}], "isError": true}
	if data != null:
		out["structuredContent"] = data
	return out

func _done(text: String, data: Variant = null) -> Dictionary:
	var out := {"content": [{"type": "text", "text": text if data == null else text + "\n" + JSON.stringify(data)}], "isError": false}
	if data != null:
		out["structuredContent"] = data
	return out

## A make can't be stopped part way; a cancelled one's answer is never sent.
func cancel(_ctx: Dictionary) -> void:
	pass

func call_tool(ctx: Dictionary, name: String, args: Dictionary) -> void:
	var problem := check(_by_name[name].inputSchema, args, "")
	if problem != "":
		server.respond(ctx, failure("Invalid arguments: " + problem))
		return
	var result: Dictionary = await Callable(self, "_tool_" + name).call(ctx, args)
	if not result.is_empty():
		server.respond(ctx, result)

static func check(schema: Dictionary, value: Variant, at: String) -> String:
	var here := at if at != "" else "arguments"
	match schema.get("type"):
		"object":
			if not value is Dictionary:
				return "%s must be an object." % here
			var props: Dictionary = schema.get("properties", {})
			for key in schema.get("required", []):
				if not value.has(key):
					return "%s needs `%s`." % [here, key]
			for key in value:
				if not props.has(key):
					if schema.get("additionalProperties", true) == false:
						return "%s doesn't take `%s`." % [here, key]
					continue
				var inner := check(props[key], value[key], (at + "." if at != "" else "") + str(key))
				if inner != "":
					return inner
		"array":
			if not value is Array:
				return "%s must be a list." % here
			if value.size() < int(schema.get("minItems", 0)):
				return "%s needs at least %d entries." % [here, schema.minItems]
			if schema.has("maxItems") and value.size() > int(schema.maxItems):
				return "%s takes at most %d entries." % [here, schema.maxItems]
			for i in value.size():
				var inner := check(schema.items, value[i], "%s[%d]" % [here, i])
				if inner != "":
					return inner
		"string":
			if not value is String:
				return "%s must be text." % here
			if schema.has("enum") and value not in schema.enum:
				return "%s must be one of: %s." % [here, ", ".join(schema.enum)]
			if value.length() < int(schema.get("minLength", 0)) or (schema.has("maxLength") and value.length() > int(schema.maxLength)):
				return "%s must be %d to %d characters." % [here, int(schema.get("minLength", 0)), int(schema.get("maxLength", 0))]
		"number", "integer":
			if not (value is float or value is int) or not is_finite(float(value)):
				return "%s must be a number." % here
			if schema.type == "integer" and float(value) != floorf(float(value)):
				return "%s must be a whole number." % here
			if (schema.has("minimum") and float(value) < float(schema.minimum)) or (schema.has("maximum") and float(value) > float(schema.maximum)):
				return "%s must be from %s to %s." % [here, schema.get("minimum", "-∞"), schema.get("maximum", "∞")]
		"boolean":
			if not value is bool:
				return "%s must be true or false." % here
	return ""

static func _object(props: Dictionary, required: Array) -> Dictionary:
	return {"type": "object", "properties": props, "required": required, "additionalProperties": false}

static func _path(what: String) -> Dictionary:
	return {"type": "string", "minLength": 1, "maxLength": 4096, "description": what}

static func _colour(what: String) -> Dictionary:
	return {"type": "string", "minLength": 7, "maxLength": 7, "description": what + ", as #RRGGBB."}

static func _slots(kind: String) -> Array:
	var out := []
	for world in YardModel.WORLDS:
		if kind == "companion":
			out.append("%s/companion" % world)
		else:
			for crew in YardModel.PROVIDER_ORDER:
				out.append("%s/%s" % [world, crew])
	return out

func _definitions() -> Array:
	var read := {"readOnlyHint": true, "openWorldHint": false}
	var writes := {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": true}
	var to := _path("The folder to write the piece in, as a full path. It must not exist yet, or be empty, unless `replace` is true.")
	var title := {"type": "string", "minLength": 1, "maxLength": 128, "description": "The piece's name, as people see it."}
	var replace := {"type": "boolean", "description": "Write into a folder that already holds files."}
	return [
		{"name": "list_slots", "title": "List slots", "description": "Every slot a piece can be made for, by world: each crew's character and the world's companions, the looks each can be recolored from, and whether the world's art is on this computer yet.",
			"inputSchema": _object({}, []), "annotations": read},
		{"name": "make_character", "title": "Make a character", "description": "Turns one model file (.glb, .gltf or .vrm; convert FBX first) into a character for a crew's slot, fitted to the world's skeleton, clips and limits, then checks it. If Studio can't be sure of some bones it says which and lists the model's bones; call again with `bones`.",
			"inputSchema": _object({"model": _path("The model file, as a full path."), "slot": {"type": "string", "enum": _slots("character")}, "to": to, "title": title,
				"height": {"type": "number", "minimum": 0.5, "maximum": 5, "description": "How tall it stands, in metres. Left out, it stands as tall as the character it replaces."},
				"bones": {"type": "string", "minLength": 1, "maxLength": 4096, "description": "Comma-separated choices: pairs like LeftHand=hand_l naming the model's bone for a skeleton bone, `swap` for a rig that names its sides the other way round, `accept` to take Studio's guesses."},
				"replace": replace}, ["model", "slot", "to"]), "annotations": writes},
		{"name": "make_companions", "title": "Make companions", "description": "Turns one model, shown four ways, or four models into a world's four companions, then checks them. A humanoid is folded onto the trunk; anything else rides it.",
			"inputSchema": _object({"models": {"type": "array", "items": _path("A model file, as a full path."), "minItems": 1, "maxItems": 4, "description": "One model or four."},
				"slot": {"type": "string", "enum": _slots("companion")}, "to": to, "title": title,
				"move": {"type": "string", "enum": ["rigid", "soft"], "description": "How a model that isn't a humanoid moves with the trunk."},
				"variants": {"type": "string", "enum": ["tint", "turn"], "description": "How one model is shown four ways."},
				"turn": {"type": "number", "minimum": -180, "maximum": 180, "description": "Degrees to turn a model that doesn't face forward."},
				"replace": replace}, ["models", "slot", "to"]), "annotations": writes},
		{"name": "recolor_look", "title": "Recolor a look", "description": "Recolors one of a slot's own looks into a piece: the mesh and clips stay the world's, only the base colors change. A character slot has look0, look1 and look2; a companion slot has agent and shell. Give `hue`, `tint`, or both; with `change_color` only colors near it change.",
			"inputSchema": _object({"slot": {"type": "string", "enum": _slots("character") + _slots("companion")}, "look": {"type": "string", "enum": LOOKS + HELPERS}, "to": to, "title": title,
				"hue": {"type": "number", "minimum": -360, "maximum": 360, "description": "Degrees to turn the hue."},
				"tint": _colour("A color laid over it"), "change_color": _colour("The one color to change"),
				"spread": {"type": "number", "minimum": 0.01, "maximum": 1, "description": "How near a color must be to `change_color` to change, from 0 to 1. Left out, 0.15."},
				"replace": replace}, ["slot", "look", "to"]), "annotations": writes},
		{"name": "check_piece", "title": "Check a piece", "description": "Checks a piece folder (piece.json and its models) as Studio checks the ones it makes, for the world and slot its piece.json names.",
			"inputSchema": _object({"folder": _path("The piece's folder, as a full path.")}, ["folder"]), "annotations": read},
		{"name": "show_window", "title": "Show the window", "description": "Opens the Studio window, so the person can make or edit a piece themselves.",
			"inputSchema": _object({}, []), "annotations": read},
	]

func _tool_list_slots(_ctx: Dictionary, _args: Dictionary) -> Dictionary:
	var worlds := []
	for world in YardModel.WORLDS:
		var missing := StudioArt.missing(StudioArt.packs_for(world))
		var slots := []
		for crew in YardModel.PROVIDER_ORDER:
			slots.append({"slot": "%s/%s" % [world, crew], "kind": "character", "crew": server.host.TOOLS.get(crew, crew), "looks": LOOKS})
		slots.append({"slot": "%s/companion" % world, "kind": "companion", "looks": HELPERS})
		worlds.append({"world": world, "title": YardModel.WORLDS[world].title, "art": "here" if missing.is_empty() else "downloads on first use",
			"download_mb": StudioArt.bytes(missing) >> 20, "slots": slots})
	return _done("%d worlds, %d slots each." % [worlds.size(), YardModel.PROVIDER_ORDER.size() + 1], {"worlds": worlds})

func _tool_make_character(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var options := {"build": args.model, "slot": args.slot, "out": args.to}
	if args.has("height"):
		options.height = args.height
	if args.has("bones"):
		options.map = args.bones
	return await _make(ctx, args, options)

func _tool_make_companions(ctx: Dictionary, args: Dictionary) -> Dictionary:
	if args.models.size() != 1 and args.models.size() != 4:
		return failure("Companions come as one model or four.")
	var options := {"build": ",".join(args.models), "slot": args.slot, "out": args.to}
	for key in ["move", "variants", "turn"]:
		if args.has(key):
			options[key] = args[key]
	return await _make(ctx, args, options)

func _tool_recolor_look(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var companions: bool = String(args.slot).ends_with("/companion")
	if (args.look in HELPERS) != companions:
		return failure("A character slot is recolored from look0, look1 or look2; a companion slot from agent or shell.")
	if not args.has("hue") and not args.has("tint"):
		return failure("Give `hue`, `tint`, or both.")
	for key in ["tint", "change_color"]:
		if args.has(key) and not String(args[key]).is_valid_html_color():
			return failure("`%s` must be a color as #RRGGBB." % key)
	var options := {"recolour": args.look, "slot": args.slot, "out": args.to}
	for pair in [["hue", "hue"], ["tint", "tint"], ["change_color", "pick"], ["spread", "spread"]]:
		if args.has(pair[0]):
			options[pair[1]] = args[pair[0]]
	return await _make(ctx, args, options)

## One Studio run for a slot: its art fetched first, the folder it writes
## refused if it holds anything, and what Studio said given back as data.
func _make(ctx: Dictionary, args: Dictionary, options: Dictionary) -> Dictionary:
	var to: String = args.to
	if not to.is_absolute_path():
		return failure("`to` must be a full path.")
	if FileAccess.file_exists(to):
		return failure("%s is a file, not a folder." % to)
	if DirAccess.dir_exists_absolute(to) and not args.get("replace", false) and not (DirAccess.get_files_at(to).is_empty() and DirAccess.get_directories_at(to).is_empty()):
		return failure("%s already holds files. Choose another folder, or set `replace`." % to)
	if args.has("title"):
		options.title = args.title
	var where := Studio.slot(options.slot)
	var reason := await _art(ctx, where.world)
	if reason != "":
		return failure("The world's art isn't here: %s." % reason)
	server.progress(ctx, 2.0, 3.0, "Making the piece")
	if await Studio.run(server.host, options) != 0:
		if Studio.said.has("unsure"):
			return failure("Studio isn't sure of these bones: %s. Call again with `bones`: pairs like LeftHand=<one of the model's bones>, or `swap`, or `accept` to take its guesses." % ", ".join(Studio.said.unsure.keys()),
				{"unsure": Studio.said.unsure, "model_bones": Studio.said.bones})
		return failure("Studio couldn't make it: %s." % Studio.said.get("reason", "it failed"))
	var files := Array(DirAccess.get_files_at(Studio.said.folder))
	return _done("Made and checked. The piece is in %s." % Studio.said.folder, {"folder": Studio.said.folder, "files": files, "slot": options.slot, "notes": Studio.said.notes})

## The world's art, downloaded if it isn't here, then loaded; "" or why not.
func _art(ctx: Dictionary, world: String) -> String:
	var packs := StudioArt.packs_for(world)
	var missing := StudioArt.missing(packs)
	if not missing.is_empty():
		var download: ArtDownload = server.host.download
		var tell := func(): server.progress(ctx, float(download.received) / maxf(download.total, 1.0), 3.0, "Downloading the world's art, %d of %d MB" % [download.received >> 20, download.total >> 20])
		download.changed.connect(tell)
		download.start(missing)
		var why: String = await download.finished
		download.changed.disconnect(tell)
		if why != "":
			return why
	server.progress(ctx, 1.0, 3.0, "Opening the world's art")
	return StudioArt.load_packs(packs)

func _tool_check_piece(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var folder: String = args.folder
	var manifest := PieceLibrary.check_folder(folder)
	if manifest.has("reason"):
		return _done("It doesn't pass: %s." % manifest.reason, {"passes": false, "reason": manifest.reason})
	var reason := await _art(ctx, manifest.world)
	if reason != "":
		return failure("The world's art isn't here: %s." % reason)
	var clips: Dictionary = server.host.default_clips(manifest.world, manifest.kind, manifest.get("crew", ""))
	var validator := PieceValidator.new()
	server.host.add_child(validator)
	var why := ""
	for file in PieceLibrary.FILES[manifest.kind]:
		var verdict: Dictionary = await validator.check(folder.path_join(file), manifest.kind, clips)
		if verdict.reason != "":
			why = "%s: %s" % [file, verdict.reason]
			break
	validator.queue_free()
	var slot := "%s/%s" % [manifest.world, manifest.crew if manifest.kind == "character" else "companion"]
	if why != "":
		return _done("It doesn't pass: %s." % why, {"passes": false, "reason": why, "slot": slot})
	return _done("It passes, for %s." % slot, {"passes": true, "slot": slot, "title": manifest.get("title", "")})

func _tool_show_window(_ctx: Dictionary, _args: Dictionary) -> Dictionary:
	if not server.host.open_window():
		return failure("Studio couldn't open its window.")
	return _done("The Studio window is opening.")
