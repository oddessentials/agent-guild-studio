class_name StudioArt
## The worlds' own models, which Studio builds on, recolours and shows: each
## world's characters, station and clip set in a pack of its own, and the
## helpers every world shares in one more. Packs are files of this
## repository's `art` release, named with their sizes and checksums by
## art/art-lock.json (tools/pack_art.py); a pack in place is loaded into
## res:// once, and its models are then found as World finds them.

const PREMIUM := "res://assets/premium/"
const MODELS := "res://assets/models/"
const LOCK := "res://art/art-lock.json"
const LISTS := "res://assets/packs/%s.json"
const URL := "https://github.com/oddessentials/agent-guild-studio/releases/download/%s/%s"
const SHARED := "helpers"

static var _lock := {}
static var _loaded := {}

## A world's own, then the helpers several worlds share, then the stations.
static func model_path(world: String, name: String) -> String:
	for path in [PREMIUM + world + "/" + name + ".glb", PREMIUM + "helpers/" + name + ".glb", MODELS + name + ".glb"]:
		if ResourceLoader.exists(path):
			return path
	return ""

## { release, packs: { name: { asset, size, sha256 } } }
static func lock() -> Dictionary:
	if _lock.is_empty():
		var read = JSON.parse_string(FileAccess.get_file_as_string(LOCK))
		_lock = read if read is Dictionary else { "release": "", "packs": {} }
	return _lock

## The packs a world's pieces are made with.
static func packs_for(world: String) -> Array:
	return [world, SHARED]

## Where packs are kept: STUDIO_ART names another folder, as tests and the
## pack tool do.
static func folder() -> String:
	var named := OS.get_environment("STUDIO_ART")
	return named if named != "" else ProjectSettings.globalize_path("user://art")

static func file(pack: String) -> String:
	return folder().path_join(String(lock().packs[pack].asset))

## STUDIO_ART_URL names another place to download from, as tests do.
static func url(pack: String) -> String:
	var named := OS.get_environment("STUDIO_ART_URL")
	return (named if named != "" else URL) % [lock().release, lock().packs[pack].asset]

static func size(pack: String) -> int:
	return int(lock().packs[pack].size)

## Whether the pack's file is in place, whole.
static func have(pack: String) -> bool:
	if not lock().packs.has(pack):
		return false
	var f := FileAccess.open(file(pack), FileAccess.READ)
	return f != null and f.get_length() == size(pack)

## Those of `packs` still to download.
static func missing(packs: Array) -> Array:
	return packs.filter(func(p): return not _loaded.has(p) and not have(p))

## How many bytes `packs` are to download.
static func bytes(packs: Array) -> int:
	var total := 0
	for p in packs:
		total += size(p)
	return total

## Loads the packs in place into res://; "" or why one couldn't be.
static func load_packs(packs: Array) -> String:
	for pack in packs:
		if _loaded.has(pack):
			continue
		if not have(pack):
			return "the %s art is not downloaded" % pack
		if not ProjectSettings.load_resource_pack(file(pack), false):
			return "the %s art could not be opened" % pack
		# The pack's own list of what it holds, so each is found by its id too.
		var list = JSON.parse_string(FileAccess.get_file_as_string(LISTS % pack))
		if list is Array:
			for entry in list:
				var id := ResourceUID.text_to_id(entry[0])
				if not ResourceUID.has_id(id):
					ResourceUID.add_id(id, entry[1])
		_loaded[pack] = true
	return ""

static func sha256(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var sha := HashingContext.new()
	sha.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		sha.update(f.get_buffer(1 << 20))
	return sha.finish().hex_encode()
