# Builds relocatable releases into dist/windows-<arch>/ (the starter, plus each
# optional example whose libraries are installed) and checks that they launch
# from another directory using the bundled DLLs.
#
# Usage: scripts/package.ps1
. "$PSScriptRoot/common.ps1"

Assert-Odin
Assert-Sdl

$dist = Join-Path $Root "dist/$Target"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
$licenses = Join-Path $dist 'licenses'
New-Item -ItemType Directory -Force -Path $licenses | Out-Null

function Build-App([string]$Name, [string]$Src) {
    Write-Step "building $Name (release)"
    Invoke-Native $Odin @('build', $Src, '-vet', '-strict-style', '-o:speed', '-subsystem:windows', "-out:$(Join-Path $dist "$Name.exe")")
}

# Copies every license file a package installed into dist. With MSVC, SDL3 and
# SDL3_ttf install them to licenses/<dir>, SDL3_image to share/licenses/<dir>.
function Copy-Licenses([string[]]$Dirs) {
    foreach ($dir in $Dirs) {
        $found = @('licenses', 'share/licenses') | ForEach-Object { Join-Path $Prefix "$_/$dir" } |
            Where-Object { Test-Path $_ }
        if (-not $found) { throw "no installed license files for $dir in $Prefix" }
        foreach ($file in Get-ChildItem $found -File) {
            Copy-Item $file.FullName (Join-Path $licenses "$dir-$($file.Name)")
        }
    }
}

$apps = @('starter')
Build-App 'starter' (Join-Path $Root 'src')
Copy-Licenses @('SDL3')
# The starter embeds glyphs baked from Jersey 10 and Silkscreen (src/*_font.odin).
foreach ($font in 'Jersey10', 'Silkscreen') {
    Copy-Item (Join-Path $Root "assets/fonts/$font-OFL.txt") (Join-Path $licenses "$font-OFL.txt")
}
if (Test-Feature 'image') {
    $apps += 'images'
    Build-App 'images' (Join-Path $Root 'examples/images')
    Copy-Licenses @('SDL3_image')
}
if (Test-Feature 'text') {
    $apps += 'text'
    Build-App 'text' (Join-Path $Root 'examples/text')
    Copy-Licenses @('SDL3_ttf', 'freetype')
    Copy-Item (Join-Path $Root 'assets/fonts/OFL.txt') (Join-Path $licenses 'PressStart2P-OFL.txt')
}
Copy-SdlRuntime $dist
Copy-Item -Recurse (Join-Path $Root 'assets') (Join-Path $dist 'assets')
Copy-Item (Join-Path $Root 'LICENSE') (Join-Path $licenses 'starter-LICENSE.txt')
Remove-Item (Join-Path $dist '*.pdb') -ErrorAction SilentlyContinue

$check = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
New-Item -ItemType Directory -Path $check | Out-Null
try {
    $env:SDL_VIDEO_DRIVER = 'dummy'; $env:SDL_RENDER_DRIVER = 'software'; $env:SDL_AUDIO_DRIVER = 'dummy'
    foreach ($app in $apps) {
        Write-Step "launch check: $app"
        $log = Join-Path $check "$app.log"
        # A windows-subsystem exe has no console; capture its output explicitly.
        $p = Start-Process -FilePath (Join-Path $dist "$app.exe") -ArgumentList '--frames=10' -WorkingDirectory $check `
            -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru
        $text = (Get-Content $log -Raw) + (Get-Content "$log.err" -Raw)
        if ($p.ExitCode -ne 0) { Write-Host $text; throw "packaged $app failed with exit code $($p.ExitCode)" }
        if ($text -notmatch "SDL.* $([regex]::Escape($Lock.sdl3.version))") { Write-Host $text; throw "packaged $app did not load the locked SDL3" }
    }
} finally {
    Remove-Item -Recurse -Force $check
}
Write-Step "packaged $($apps -join ', ') in $dist"
