param([string]$Page = (Join-Path $PSScriptRoot '../site/index.md'))

$ErrorActionPreference = 'Stop'
$text = Get-Content -Raw -LiteralPath $Page
$install = [regex]::Match($text, '(?ms)^## 2\. .*?^```powershell\r?\n(.*?)^```').Groups[1].Value
if (-not $install) { throw 'The page has no install block under step 2.' }
$root = Join-Path ([IO.Path]::GetTempPath()) ('ags-site-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$kept = $env:LOCALAPPDATA
try {
    $script = Join-Path $root 'install.ps1'
    Set-Content -LiteralPath $script -Value $install
    $env:LOCALAPPDATA = Join-Path $root 'local'
    $printed = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script
    if ($LASTEXITCODE -ne 0) { throw "The install block failed (exit $LASTEXITCODE)." }
    $exe = @($printed)[-1]
    $expected = Join-Path $env:LOCALAPPDATA 'Programs\AgentGuildStudio\AgentGuildStudio.exe'
    if ($exe -ne $expected) { throw "The install block printed '$exe', not '$expected'." }
    node (Join-Path $PSScriptRoot 'mcp_smoke.mjs') $exe
    if ($LASTEXITCODE -ne 0) { throw 'Studio installed from the page did not serve MCP.' }
    Write-Output 'ok   the page installs a working Studio'
} finally {
    $env:LOCALAPPDATA = $kept
    if ($root -and (Split-Path -Leaf $root).StartsWith('ags-site-')) { Remove-Item -LiteralPath $root -Recurse -Force }
}
