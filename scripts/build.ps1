# Builds the starter against the locked SDL3.
#
# Usage: scripts/build.ps1 [debug|release]   (default: debug)
# Output: build/starter-debug.exe or build/starter.exe
param([ValidateSet('debug', 'release')][string]$Mode = 'debug')
. "$PSScriptRoot/common.ps1"

Assert-Odin
Assert-Sdl
New-Item -ItemType Directory -Force -Path $Build | Out-Null

if ($Mode -eq 'debug') {
    $out = Join-Path $Build 'starter-debug.exe'; $flags = @('-debug')
} else {
    $out = Join-Path $Build 'starter.exe'; $flags = @('-o:speed')
}

Write-Step "building $Mode -> $out"
Invoke-Native $Odin (@('build', (Join-Path $Root 'src'), '-vet', '-strict-style', "-out:$out") + $flags)

Copy-SdlRuntime $Build
$assets = Join-Path $Build 'assets'
if (Test-Path $assets) { Remove-Item -Recurse -Force $assets }
Copy-Item -Recurse (Join-Path $Root 'assets') $assets
