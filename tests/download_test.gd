extends RefCounted
## The art download against a server on this computer: a pack that matches its
## checksum is moved into place; one that doesn't, or that the server doesn't
## have, leaves nothing behind and says why.

const OUT := "user://art-test/"

var failures := []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
	var folder := ProjectSettings.globalize_path(OUT)
	StudioFiles.remove_tree(folder)
	var server := LocalServer.new()
	if not server.start():
		return ["no port on this computer was free for the test's server"]
	OS.set_environment("STUDIO_ART", folder)
	OS.set_environment("STUDIO_ART_URL", "http://127.0.0.1:%d/%%s/%%s" % server.port)
	var good := LocalServer.pack("good.zip", 300000)
	var kept: Dictionary = StudioArt._lock
	StudioArt._lock = { "release": "art", "packs": {
		"good": good[1],
		"changed": { "asset": "changed.zip", "size": 300000, "sha256": "00".repeat(32) },
		"gone": { "asset": "gone.zip", "size": 10, "sha256": "00".repeat(32) } } }
	server.serving = { "/art/good.zip": good[0], "/art/changed.zip": good[0] }
	var download := ArtDownload.new()
	tree.root.add_child(download)
	tree.process_frame.connect(server.poll)

	check(StudioArt.missing(["good"]) == ["good"], "a pack not downloaded yet is not counted as missing")
	download.start(["good"])
	check(await download.finished == "", "a pack that matches its checksum was not downloaded")
	check(StudioArt.have("good") and FileAccess.get_file_as_bytes(StudioArt.file("good")) == good[0], "the downloaded pack is not in place, whole")
	check(download.received == 300000 and download.total == 300000, "the download did not count its bytes: %d of %d" % [download.received, download.total])

	download.start(["changed"])
	var why: String = await download.finished
	check(why.contains("checksum"), "a pack that doesn't match its checksum was taken: %s" % why)
	check(not StudioArt.have("changed") and DirAccess.get_files_at(folder) == PackedStringArray(["good.zip"]), "a refused download left something behind: %s" % [DirAccess.get_files_at(folder)])

	download.start(["gone"])
	why = await download.finished
	check(why.contains("could not be downloaded"), "a pack the server doesn't have was not refused: %s" % why)
	check(DirAccess.get_files_at(folder) == PackedStringArray(["good.zip"]), "a failed download left something behind: %s" % [DirAccess.get_files_at(folder)])

	tree.process_frame.disconnect(server.poll)
	download.queue_free()
	server.stop()
	StudioArt._lock = kept
	OS.set_environment("STUDIO_ART", "")
	OS.set_environment("STUDIO_ART_URL", "")
	StudioFiles.remove_tree(folder)
	return failures
