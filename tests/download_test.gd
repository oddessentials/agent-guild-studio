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
		"active": { "asset": "active.zip", "size": 300000, "sha256": good[1].sha256 },
		"stalled": { "asset": "stalled.zip", "size": 300000, "sha256": good[1].sha256 },
		"changed": { "asset": "changed.zip", "size": 300000, "sha256": "00".repeat(32) },
		"gone": { "asset": "gone.zip", "size": 10, "sha256": "00".repeat(32) } } }
	server.serving = { "/art/good.zip": good[0], "/art/changed.zip": good[0], "/art/active.zip": good[0] }
	server.holding = ["/art/stalled.zip"]
	server.pausing = { "/art/active.zip": 100000 }
	var download := ArtDownload.new()
	if OS.get_environment("STUDIO_TEST_CURL") == "0":
		download.with_curl = false
	tree.root.add_child(download)
	tree.process_frame.connect(server.poll)

	print("CHECK download normal completion (%s)" % ("curl" if download.with_curl else "HTTP"))
	check(StudioArt.missing(["good"]) == ["good"], "a pack not downloaded yet is not counted as missing")
	download.start(["good"])
	check(await download.finished == "", "a pack that matches its checksum was not downloaded")
	check(StudioArt.have("good") and FileAccess.get_file_as_bytes(StudioArt.file("good")) == good[0], "the downloaded pack is not in place, whole")
	check(download.received == 300000 and download.total == 300000, "the download did not count its bytes: %d of %d" % [download.received, download.total])

	for pack in ["active", "stalled"]:
		print("CHECK download cancellation: %s" % pack)
		var reasons := []
		var finished := func(reason: String): reasons.append(reason)
		download.finished.connect(finished)
		download.start([pack])
		check(await TestRunner.until(tree, func(): return "/art/%s.zip" % pack in server.requested), "%s request never reached the server" % pack)
		if pack == "active":
			check(await TestRunner.until(tree, func(): return download.received > 0), "the active response never wrote any bytes")
		check(download.running and download.received < download.total, "%s request finished before cancellation" % pack)
		download.cancel()
		download.cancel()
		check(await TestRunner.until(tree, func(): return not download.running), "%s cancellation never finished" % pack)
		check(not download.running and reasons == ["it was cancelled"], "%s cancellation did not finish exactly once: %s" % [pack, reasons])
		check(DirAccess.get_files_at(folder) == PackedStringArray(["good.zip"]), "%s cancellation left a partial download" % pack)
		download.finished.disconnect(finished)

	print("CHECK download normal completion after cancellation")
	download.start(["good"])
	check(await download.finished == "" and download.received == download.total, "a normal download did not recover after cancellation")

	download.start(["changed"])
	var why: String = await download.finished
	check(why.contains("checksum"), "a pack that doesn't match its checksum was taken: %s" % why)
	check(not StudioArt.have("changed") and DirAccess.get_files_at(folder) == PackedStringArray(["good.zip"]), "a refused download left something behind: %s" % [DirAccess.get_files_at(folder)])

	download.start(["gone"])
	why = await download.finished
	check(why.contains("could not be downloaded"), "a pack the server doesn't have was not refused: %s" % why)
	check(DirAccess.get_files_at(folder) == PackedStringArray(["good.zip"]), "a failed download left something behind: %s" % [DirAccess.get_files_at(folder)])

	print("CHECK download shutdown during active transfer")
	download.start(["active"])
	check(await TestRunner.until(tree, func(): return download.received > 0), "the closing download never wrote any bytes")
	download.free()
	check(DirAccess.get_files_at(folder) == PackedStringArray(["good.zip"]), "closing the downloader left a partial download")

	tree.process_frame.disconnect(server.poll)
	server.stop()
	StudioArt._lock = kept
	OS.set_environment("STUDIO_ART", "")
	OS.set_environment("STUDIO_ART_URL", "")
	StudioFiles.remove_tree(folder)
	return failures
