# Builds the starter (or an optional example) against the locked native libraries.
#
# Usage: scripts/build.ps1 [debug|release] [starter|images|text]   (default: debug starter)
# Output: build/<app>-debug.exe or build/<app>.exe
# (The parameter is not called $Target: common.ps1 uses that for the host triple.)
#   images needs scripts/bootstrap.ps1 -WithImage; text needs -WithText.
param(
    [ValidateSet('debug', 'release')][string]$Mode = 'debug',
    [ValidateSet('starter', 'images', 'text')][string]$App = 'starter'
)
. "$PSScriptRoot/common.ps1"

Assert-Odin
Assert-Sdl
switch ($App) {
    'starter' { $src = Join-Path $Root 'src' }
    'images'  { $src = Join-Path $Root 'examples/images'; Assert-Feature 'image' }
    'text'    { $src = Join-Path $Root 'examples/text'; Assert-Feature 'text' }
}
New-Item -ItemType Directory -Force -Path $Build | Out-Null

if ($Mode -eq 'debug') {
    $out = Join-Path $Build "$App-debug.exe"; $flags = @('-debug')
} else {
    $out = Join-Path $Build "$App.exe"; $flags = @('-o:speed')
}

Write-Step "building $App ($Mode) -> $out"
Invoke-Native $Odin (@('build', $src, '-vet', '-strict-style', "-out:$out") + $flags)

Copy-SdlRuntime $Build
$assets = Join-Path $Build 'assets'
if (Test-Path $assets) { Remove-Item -Recurse -Force $assets }
Copy-Item -Recurse (Join-Path $Root 'assets') $assets
