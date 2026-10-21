# Builds a relocatable release into dist/windows-<arch>/ and checks that it
# launches from another directory using the bundled SDL3.dll.
#
# Usage: scripts/package.ps1
. "$PSScriptRoot/common.ps1"

Assert-Odin
Assert-Sdl

$dist = Join-Path $Root "dist/$Target"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force -Path (Join-Path $dist 'licenses') | Out-Null

Write-Step 'building release'
$exe = Join-Path $dist 'starter.exe'
Invoke-Native $Odin @('build', (Join-Path $Root 'src'), '-vet', '-strict-style', '-o:speed', '-subsystem:windows', "-out:$exe")

Copy-SdlRuntime $dist
Copy-Item -Recurse (Join-Path $Root 'assets') (Join-Path $dist 'assets')
Copy-Item (Join-Path $Root 'LICENSE') (Join-Path $dist 'licenses/LICENSE.starter.txt')
Copy-Item (Join-Path $Prefix 'licenses/SDL3/LICENSE.txt') (Join-Path $dist 'licenses/LICENSE.SDL3.txt')
Remove-Item (Join-Path $dist '*.pdb') -ErrorAction SilentlyContinue

Write-Step 'launch check'
$check = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
New-Item -ItemType Directory -Path $check | Out-Null
try {
    $log = Join-Path $check 'launch.log'
    $env:SDL_VIDEO_DRIVER = 'dummy'; $env:SDL_RENDER_DRIVER = 'software'; $env:SDL_AUDIO_DRIVER = 'dummy'
    # A windows-subsystem exe has no console; capture its output explicitly.
    $p = Start-Process -FilePath $exe -ArgumentList '--frames=10' -WorkingDirectory $check `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru
    $text = (Get-Content $log -Raw) + (Get-Content "$log.err" -Raw)
    if ($p.ExitCode -ne 0) { Write-Host $text; throw "packaged app failed with exit code $($p.ExitCode)" }
    if ($text -notmatch "SDL runtime $([regex]::Escape($Lock.sdl3.version))") { Write-Host $text; throw 'packaged app did not load the locked SDL3' }
} finally {
    Remove-Item -Recurse -Force $check
}
Write-Step "packaged $dist"
