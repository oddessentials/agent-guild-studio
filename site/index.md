# Set up Agent Guild: Studio

Agent Guild: Studio makes characters and companions for Agent Guild, from a model file or by recoloring one of a world's own looks. It runs on Windows 10 or 11 (64-bit) or macOS 13 or later, and works for you with no window.

Agent Guild itself: [agentguild.oddessentials.ai/agents](https://agentguild.oddessentials.ai/agents/). Environments for Agent Guild Yards: [oddessentials.github.io/agent-guild-builders](https://oddessentials.github.io/agent-guild-builders/).

On a Mac, follow the Mac steps further down instead. On Windows, follow these steps in order. Run each block in PowerShell. If your shell isn't PowerShell, save the block as a `.ps1` file and run `powershell -NoProfile -ExecutionPolicy Bypass -File <file>`.

## 1. Choose the folder

Every block below starts with this line, which puts Studio in `%LOCALAPPDATA%\Programs\AgentGuildStudio`:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
```

Change that line in every block, to `$dest = '<folder>'` with any `'` in the folder written as `''`, if:

- the person named a folder: use it.
- Studio is already connected to you or another agent: use the folder that contains its `AgentGuildStudio` folder. Find the connected path with `claude mcp get agent-guild-studio`, `codex mcp get agent-guild-studio`, `agy mcp list` or `grok mcp list`, or in your Docker Agent YAML.

Don't move Studio after connecting it.

## 2. Download and install

If Studio is already running, ask the person to close its window first.

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$zip = Join-Path $env:TEMP 'AgentGuildStudio-windows.zip'
New-Item -ItemType Directory -Force $dest | Out-Null
Invoke-WebRequest 'https://github.com/oddessentials/agent-guild-studio/releases/latest/download/AgentGuildStudio-windows.zip' -OutFile $zip
& "$env:SystemRoot\System32\tar.exe" -xf $zip -C $dest
if ($LASTEXITCODE -ne 0) { throw "Extracting failed (exit $LASTEXITCODE)." }
Remove-Item -LiteralPath $zip
(Resolve-Path -LiteralPath (Join-Path $dest 'AgentGuildStudio\AgentGuildStudio.exe')).Path
```

It prints the full path of `AgentGuildStudio.exe`.

## 3. Connect

Skip this step if Studio is already connected to you. Otherwise run the block for the agent you are.

Claude Code:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildStudio\AgentGuildStudio.exe'
claude mcp add -s user agent-guild-studio "--" $exe --headless --no-header "--" --mcp
```

Codex CLI:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildStudio\AgentGuildStudio.exe'
codex mcp add agent-guild-studio "--" $exe --headless --no-header "--" --mcp
```

Antigravity CLI:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildStudio\AgentGuildStudio.exe'
agy mcp add agent-guild-studio "--" $exe --headless --no-header "--" --mcp
```

Grok Build:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildStudio\AgentGuildStudio.exe'
grok mcp add agent-guild-studio "--" $exe --headless --no-header "--" --mcp
```

Docker Agent: add this toolset to your agent in its YAML file, with `root` replaced by your agent's name and `<exe>` by the path step 2 printed. Write any `'` in the path as `''`.

```yaml
agents:
  root:
    toolsets:
      - type: mcp
        command: '<exe>'
        args: ['--headless', '--no-header', '--', '--mcp']
```

## 4. Check that it works

1. Claude Code: `claude mcp get agent-guild-studio` reports it connected. Grok Build: `grok mcp doctor agent-guild-studio` reports it healthy. Other agents: go to the next step.
2. Start a new session, so the Studio tools load. No window opens.
3. Call the `list_slots` tool. It lists every world's slots, and whether each world's art is on this computer yet.

Studio is now set up. Its tools explain how to make a piece. A world's art downloads the first time a piece is made for it, and is kept outside the install folder.

## Update

Run step 2 again with the same folder. The connection, the downloaded art and the person's pieces are kept. Then start a new session, so the Studio tools load again.

## On a Mac

Follow these steps in order. Run each block in Terminal's shell, zsh, or in bash.

## Mac 1. Choose the folder

Every block below starts with this line, which puts Studio in `~/Applications`:

```zsh
dest="$HOME/Applications"
```

Change that line in every block, to `dest='<folder>'` with any `'` in the folder written as `'\''`, if:

- the person named a folder: use it.
- Studio is already connected to you or another agent: use the folder that contains its `AgentGuildStudio.app`. Find the connected path as in step 1 above.

Don't move Studio after connecting it.

## Mac 2. Download and install

If Studio is already running, ask the person to close its window first.

```zsh
dest="$HOME/Applications"
tmp="$(mktemp -d)" &&
curl -fsSL -o "$tmp/AgentGuildStudio-macos.zip" 'https://github.com/oddessentials/agent-guild-studio/releases/latest/download/AgentGuildStudio-macos.zip' &&
ditto -x -k "$tmp/AgentGuildStudio-macos.zip" "$tmp" &&
mkdir -p "$dest" &&
rm -rf "$dest/AgentGuildStudio.app" &&
mv "$tmp/AgentGuildStudio.app" "$dest/" &&
rm -rf "$tmp" &&
echo "$dest/AgentGuildStudio.app/Contents/MacOS/Agent Guild Studio"
```

It prints the full path of the app's executable. Installed this way, macOS doesn't ask the person before Studio first opens.

## Mac 3. Connect

Skip this step if Studio is already connected to you. Otherwise run the block for the agent you are.

Claude Code:

```zsh
dest="$HOME/Applications"
exe="$dest/AgentGuildStudio.app/Contents/MacOS/Agent Guild Studio"
claude mcp add -s user agent-guild-studio "--" "$exe" --headless --no-header "--" --mcp
```

Codex CLI:

```zsh
dest="$HOME/Applications"
exe="$dest/AgentGuildStudio.app/Contents/MacOS/Agent Guild Studio"
codex mcp add agent-guild-studio "--" "$exe" --headless --no-header "--" --mcp
```

Antigravity CLI:

```zsh
dest="$HOME/Applications"
exe="$dest/AgentGuildStudio.app/Contents/MacOS/Agent Guild Studio"
agy mcp add agent-guild-studio "--" "$exe" --headless --no-header "--" --mcp
```

Grok Build:

```zsh
dest="$HOME/Applications"
exe="$dest/AgentGuildStudio.app/Contents/MacOS/Agent Guild Studio"
grok mcp add agent-guild-studio "--" "$exe" --headless --no-header "--" --mcp
```

Docker Agent: add the toolset shown in step 3 above, with `<exe>` the path Mac step 2 printed.

## Mac 4. Check that it works

Follow step 4 above.

## Mac update

Run Mac step 2 again with the same folder. The connection, the downloaded art and the person's pieces are kept. Then start a new session, so the Studio tools load again.

## Use a character in Grove Companion

A character Studio makes can also be the person's desktop spirit in Agent Guild: Grove Companion. Follow Companion's own steps at [oddessentials.github.io/agent-guild-companions](https://oddessentials.github.io/agent-guild-companions/), with the folder `list_pieces` gives for the character. Grove Companion takes characters, not companions.
