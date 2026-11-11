extends RefCounted
## The art download against a server on this computer: a pack that matches its
## checksum is moved into place; one that doesn't, or that the server doesn't
## have, leaves nothing behind and says why.

const OUT := "user://art-test/"

var failures := []
var _server := TCPServer.new()
var _serving := {}
var _peers := []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
	var folder := ProjectSettings.globalize_path(OUT)
	StudioFiles.remove_tree(folder)
	OS.set_environment("STUDIO_ART", folder)
	var port := 0
	for candidate in range(47810, 47830):
		if _server.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			break
	if port == 0:
		return ["no port on this computer was free for the test's server"]
	OS.set_environment("STUDIO_ART_URL", "http://127.0.0.1:%d/%%s/%%s" % port)
	var good := PackedByteArray()
	good.resize(300000)
	for i in good.size():
		good[i] = i % 251
	var sum := HashingContext.new()
	sum.start(HashingContext.HASH_SHA256)
	sum.update(good)
	var kept: Dictionary = StudioArt._lock
	StudioArt._lock = { "release": "art", "packs": {
		"good": { "asset": "good.zip", "size": good.size(), "sha256": sum.finish().hex_encode() },
		"changed": { "asset": "changed.zip", "size": good.size(), "sha256": "00".repeat(32) },
		"gone": { "asset": "gone.zip", "size": 10, "sha256": "00".repeat(32) } } }
	_serving = { "/art/good.zip": good, "/art/changed.zip": good }
	var download := ArtDownload.new()
	tree.root.add_child(download)
	tree.process_frame.connect(_serve)

	check(StudioArt.missing(["good"]) == ["good"], "a pack not downloaded yet is not counted as missing")
	download.start(["good"])
	check(await download.finished == "", "a pack that matches its checksum was not downloaded")
	check(StudioArt.have("good") and FileAccess.get_file_as_bytes(StudioArt.file("good")) == good, "the downloaded pack is not in place, whole")
	check(download.received == good.size() and download.total == good.size(), "the download did not count its bytes: %d of %d" % [download.received, download.total])

	download.start(["changed"])
	var why: String = await download.finished
	check(why.contains("checksum"), "a pack that doesn't match its checksum was taken: %s" % why)
	check(not StudioArt.have("changed") and DirAccess.get_files_at(folder) == PackedStringArray(["good.zip"]), "a refused download left something behind: %s" % [DirAccess.get_files_at(folder)])

	download.start(["gone"])
	why = await download.finished
	check(why.contains("could not be downloaded"), "a pack the server doesn't have was not refused: %s" % why)
	check(DirAccess.get_files_at(folder) == PackedStringArray(["good.zip"]), "a failed download left something behind: %s" % [DirAccess.get_files_at(folder)])

	tree.process_frame.disconnect(_serve)
	download.queue_free()
	_server.stop()
	StudioArt._lock = kept
	OS.set_environment("STUDIO_ART", "")
	OS.set_environment("STUDIO_ART_URL", "")
	StudioFiles.remove_tree(folder)
	return failures

## Answers each request once its headers have arrived, then closes.
func _serve() -> void:
	while _server.is_connection_available():
		_peers.append([_server.take_connection(), ""])
	for entry in _peers.duplicate():
		var peer: StreamPeerTCP = entry[0]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.erase(entry)
			continue
		var waiting := peer.get_available_bytes()
		if waiting > 0:
			entry[1] += peer.get_data(waiting)[1].get_string_from_utf8()
		if not String(entry[1]).contains("\r\n\r\n"):
			continue
		var path := String(entry[1]).get_slice(" ", 1)
		var body: PackedByteArray = _serving.get(path, PackedByteArray())
		var head := "HTTP/1.1 %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % ["200 OK" if _serving.has(path) else "404 Not Found", body.size()]
		peer.put_data(head.to_utf8_buffer() + body)
		peer.disconnect_from_host()
		_peers.erase(entry)
