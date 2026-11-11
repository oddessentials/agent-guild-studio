param([string]$Godot = 'godot', [ValidateSet('Windows', 'macOS')][string]$Platform = 'Windows')

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$build = Join-Path $project 'build'
$lock = Get-Content -LiteralPath (Join-Path $project 'art/art-lock.json') -Raw | ConvertFrom-Json
foreach ($pack in @('guild', 'orbital', 'grove', 'professional', 'goblinville', 'gnomeland', 'helpers')) {
    $entry = $lock.packs.$pack
    if (-not $entry -or -not $entry.asset -or -not $entry.sha256 -or $entry.size -le 0) { throw "art/art-lock.json names no $pack art." }
}

New-Item -ItemType Directory -Path $build -Force | Out-Null
$stage = Join-Path $build ('package-' + [guid]::NewGuid().ToString('N'))
# On a Mac the licence goes inside the app.
$mac = $Platform -eq 'macOS'
$app = Join-Path $stage 'AgentGuildStudio.app'
$bundle = if ($mac) { Join-Path $app 'Contents/Resources' } else { Join-Path $stage 'AgentGuildStudio' }
New-Item -ItemType Directory -Path $(if ($mac) { $stage } else { $bundle }) -Force | Out-Null
try {
    $importLog = & $Godot --headless --path $project --editor --import --quit 2>&1
    $importExit = $LASTEXITCODE
    $importLog | Write-Output
    if ($importExit -ne 0 -or ($importLog -match 'SCRIPT ERROR:')) { throw 'Godot import failed.' }
    $exportLog = & $Godot --headless --path $project --export-release $Platform $(if ($mac) { $app } else { Join-Path $bundle 'AgentGuildStudio.exe' }) 2>&1
    $exportExit = $LASTEXITCODE
    $exportLog | Write-Output
    if ($exportExit -ne 0 -or ($exportLog -match 'SCRIPT ERROR:')) { throw 'Godot export failed.' }
    Copy-Item -LiteralPath (Join-Path $project 'LICENSE') -Destination (Join-Path $bundle 'LICENSE')
    $name = "AgentGuildStudio-$($Platform.ToLower()).zip"
    $zip = Join-Path $stage $name
    if ($mac) {
        # Adding the licence broke the export's ad-hoc signature, and Apple
        # Silicon won't run an app without a valid one, so sign it again.
        & codesign --force --sign - --preserve-metadata=identifier,entitlements,flags,runtime $app
        if ($LASTEXITCODE -ne 0) { throw 'Signing the app failed.' }
        & codesign --verify --deep --strict $app
        if ($LASTEXITCODE -ne 0) { throw 'The signed app does not verify.' }
        & ditto -c -k --keepParent $app $zip
        if ($LASTEXITCODE -ne 0) { throw 'Zipping the app failed.' }
    } else {
        Compress-Archive -LiteralPath $bundle -DestinationPath $zip
    }
    $output = Join-Path $build $name
    Move-Item -LiteralPath $zip -Destination $output -Force
    Write-Output "Packaged $output"
} finally {
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if (-not $resolvedStage.StartsWith([IO.Path]::GetFullPath($build) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Staging path escaped the build directory.' }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}
