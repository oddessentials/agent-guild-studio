extends RefCounted
## The Connect dialog's commands start Studio with no window, and quote a path
## as PowerShell and zsh each take it literally.

func run(_tree: SceneTree) -> Array:
	var failures := []
	var main: GDScript = load("res://src/app/main.gd")
	var windows: Array = main.connect_commands("C:/Apps $x/it's/AgentGuildStudio.exe", [], false)
	if windows.map(func(c): return c[0]) != ["Claude Code", "Codex CLI", "Antigravity CLI", "Grok Build", "Docker Agent"]:
		failures.append("the commands do not cover every Agent Guild provider")
	if windows[0][1] != "claude mcp add -s user agent-guild-studio \"--\" 'C:/Apps $x/it''s/AgentGuildStudio.exe' --headless --no-header \"--\" --mcp":
		failures.append("the PowerShell command is %s" % windows[0][1])
	if windows[4][1] != "agents:\n  root:\n    toolsets:\n      - type: mcp\n        command: 'C:/Apps $x/it''s/AgentGuildStudio.exe'\n        args: ['--headless', '--no-header', '--', '--mcp']":
		failures.append("the Docker Agent toolset is %s" % windows[4][1])
	var mac: Array = main.connect_commands("/Users/x/Bill's $x/AgentGuildStudio.app/Contents/MacOS/Agent Guild Studio", [], true)
	if mac[0][1] != "claude mcp add -s user agent-guild-studio \"--\" '/Users/x/Bill'\\''s $x/AgentGuildStudio.app/Contents/MacOS/Agent Guild Studio' --headless --no-header \"--\" --mcp":
		failures.append("the zsh command is %s" % mac[0][1])
	return failures
