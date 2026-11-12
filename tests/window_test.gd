extends RefCounted
## Studio's window with no art: its first screen says what a world's art
## needs and follows a download through, a failure and a cancel, leaving
## nothing behind; pieces another program adds appear; closing ends Studio
## once; and the window starts with no agent's options.

const FIXTURES := "res://tests/fixtures/pieces/"
const OUT := "user://window-test/"
const CLIPS := { "walk": 1.3333, "work_0": 3.0, "work_1": 5.0, "pause": 5.0, "idle_0": 5.0, "idle_1": 6.0, "idle_2": 5.0, "done": 4.0 }

var failures := []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func run(tree: SceneTree) -> Array:
	var out := ProjectSettings.globalize_path(OUT)
	StudioFiles.remove_tree(out)
	var art := out.path_join("art")
	var server := LocalServer.new()
	if not server.start():
		return ["no port on this computer was free for the test's server"]
	OS.set_environment("STUDIO_ART", art)
	OS.set_environment("STUDIO_ART_URL", "http://127.0.0.1:%d/%%s/%%s" % server.port)
	var guild := LocalServer.pack("guild.zip", 200000)
	var helpers := LocalServer.pack("helpers.zip", 100000)
	var kept: Dictionary = StudioArt._lock
	StudioArt._lock = { "release": "art", "packs": { "guild": guild[1], "helpers": helpers[1],
		"orbital": { "asset": "orbital.zip", "size": 50, "sha256": "00".repeat(32) }, "grove": { "asset": "grove.zip", "size": 50, "sha256": "00".repeat(32) } } }
	server.serving = { "/art/guild.zip": guild[0], "/art/helpers.zip": helpers[0] }
	server.holding = ["/art/grove.zip"]
	tree.process_frame.connect(server.poll)

	var main: Node = load("res://src/app/main.gd").new()
	tree.root.add_child(main)
	var quits := [0]
	main.on_quit = func(): quits[0] += 1
	var home: HomePanel = main.home
	check(home != null and home.visible and not main.panel.visible, "the window did not open on its first screen")
	check(home.world == "guild" and home.art == "missing" and home.art_bytes == 300000, "the first screen does not say guild's art is a 300000 byte download: %s %d" % [home.art, home.art_bytes])

	home.download_requested.emit("guild")
	check(home.art == "downloading", "a download did not show as under way")
	check(await TestRunner.until(tree, func(): return not main.download.running, 60.0), "the download never ended")
	check(home.art == "ready" and home.received == 300000 and home.total == 300000, "after the download the screen says %s, %d of %d" % [home.art, home.received, home.total])

	home.world_chosen.emit("orbital")
	check(home.world == "orbital" and home.art == "missing" and home.art_bytes == 50, "another world's art is not asked for by itself: %s %d" % [home.art, home.art_bytes])
	home.download_requested.emit("orbital")
	check(await TestRunner.until(tree, func(): return not main.download.running, 60.0), "a download the server refuses never ended")
	check(home.art == "failed" and "could not be downloaded" in home.art_reason, "a failed download shows as %s: %s" % [home.art, home.art_reason])

	home.world_chosen.emit("grove")
	home.download_requested.emit("grove")
	check(home.art == "downloading", "a second download did not start")
	home.cancel_requested.emit()
	check(home.art == "failed" and "cancelled" in home.art_reason, "a cancelled download shows as %s: %s" % [home.art, home.art_reason])
	check(Array(DirAccess.get_files_at(art)) == ["guild.zip", "helpers.zip"], "a failed or cancelled download left something behind: %s" % [DirAccess.get_files_at(art)])

	main.pieces.root = OUT + "library/"
	main.pieces.refresh()
	var agent := PieceLibrary.new()
	agent.root = main.pieces.root
	agent.default_clips = func(_world, _kind, _crew): return CLIPS
	tree.root.add_child(agent)
	var id := await agent.add_local(_folder("from-an-agent"), "", {})
	check(await TestRunner.until(tree, func(): return home.pieces.size() == 1, 30.0), "a piece an agent made never appeared in Your pieces")
	if home.pieces.size() == 1:
		check(home.pieces[0].id == id and home.pieces[0].title == "from-an-agent" and "Claude Code crew" in home.pieces[0].slot, "Your pieces shows %s" % [home.pieces[0]])
	agent.remove(id)
	check(await TestRunner.until(tree, func(): return home.pieces.is_empty(), 30.0), "a piece an agent removed stayed in Your pieces")

	var args: Array = main.window_args()
	check(not "--mcp" in args and not "--headless" in args and not "--" in args, "the window would start with an agent's options: %s" % [args])
	main.close()
	main.close()
	check(quits[0] == 1, "closing the window ended Studio %d times" % quits[0])

	tree.process_frame.disconnect(server.poll)
	tree.auto_accept_quit = true
	agent.free()
	main.free()
	server.stop()
	StudioArt._lock = kept
	OS.set_environment("STUDIO_ART", "")
	OS.set_environment("STUDIO_ART_URL", "")
	StudioFiles.remove_tree(out)
	return failures

func _folder(name: String) -> String:
	var dir := ProjectSettings.globalize_path(OUT + "folders/" + name)
	DirAccess.make_dir_recursive_absolute(dir)
	FileAccess.open(dir.path_join("piece.json"), FileAccess.WRITE).store_string(JSON.stringify({ "format": 1, "kind": "character", "world": "guild", "crew": "anthropic", "title": name }))
	var model := FileAccess.open(dir.path_join("character.glb"), FileAccess.WRITE)
	model.store_buffer(FileAccess.get_file_as_bytes(FIXTURES + "character.bin"))
	model.close()
	return dir
