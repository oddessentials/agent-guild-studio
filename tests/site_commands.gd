extends SceneTree

const EXE := "C:/x/AgentGuildStudio.exe"
const MAC_EXE := "/x/AgentGuildStudio.app/Contents/MacOS/Agent Guild Studio"

func _initialize() -> void:
	var page := FileAccess.get_file_as_string("res://site/index.md").replace("\r\n", "\n")
	var main: GDScript = load("res://src/app/main.gd")
	var wanted := []
	for entry in main.connect_commands(EXE, [], false):
		wanted.append([entry[0], entry[1].replace("'%s'" % EXE, "$exe") if entry[0] != "Docker Agent" else entry[1].replace(EXE, "<exe>")])
	for entry in main.connect_commands(MAC_EXE, [], true):
		if entry[0] != "Docker Agent":
			wanted.append(["Mac " + entry[0], entry[1].replace("'%s'" % MAC_EXE, "\"$exe\"")])
	var failed := 0
	for entry in wanted:
		if not page.contains(entry[1]):
			failed += 1
			printerr("FAIL the page's %s step isn't the Connect dialog's command: %s" % entry)
	print("site commands: %d of %d match" % [wanted.size() - failed, wanted.size()])
	quit(1 if failed else 0)
