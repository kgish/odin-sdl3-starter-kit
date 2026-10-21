# Installs the locked Odin release and builds the locked SDL3 release.
#
# Usage: scripts/bootstrap.ps1 [-Force]
# Run from a Visual Studio developer PowerShell (cl.exe on PATH).
param([switch]$Force)
. "$PSScriptRoot/common.ps1"

Write-Step "host: $Target"
foreach ($tool in 'cmake', 'ninja', 'cl') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "missing required tool: $tool (use a Visual Studio developer shell; see docs/dependencies.md)"
    }
}

# --- SDL3 -------------------------------------------------------------------

$sdl     = $Lock.sdl3
$stamp   = Join-Path $Prefix '.sdl3-lock'
$want    = $sdl | ConvertTo-Json -Depth 10 -Compress
$current = if (Test-Path $stamp) { Get-Content $stamp -Raw } else { '' }

if (-not $Force -and $current.Trim() -eq $want) {
    Write-Step "SDL3 $($sdl.version) already installed in $Prefix"
} else {
    $archive = Join-Path $Root "third_party/src/$(Split-Path -Leaf $sdl.archive.url)"
    Get-VerifiedFile $sdl.archive.url $sdl.archive.sha256 $archive

    $src = Join-Path $Root "third_party/src/SDL3-$($sdl.version)"
    if (Test-Path $src) { Remove-Item -Recurse -Force $src }
    Invoke-Native tar @('-xzf', $archive, '-C', (Join-Path $Root 'third_party/src'))

    $buildDir = Join-Path $Root "third_party/build/sdl3-$Target"
    foreach ($dir in $buildDir, $Prefix) { if (Test-Path $dir) { Remove-Item -Recurse -Force $dir } }

    $opts = @($sdl.cmake_options.common) + @($sdl.cmake_options.windows)
    Write-Step "configuring SDL3 $($sdl.version)"
    Invoke-Native cmake (@('-S', $src, '-B', $buildDir, '-G', 'Ninja') + $opts + @("-DCMAKE_INSTALL_PREFIX=$Prefix"))
    Write-Step "building SDL3 $($sdl.version)"
    Invoke-Native cmake @('--build', $buildDir)

    $config = Get-ChildItem -Recurse -Filter SDL_build_config.h $buildDir | Select-Object -First 1
    if (-not $config) { throw "SDL_build_config.h not found in $buildDir" }
    $text = Get-Content $config.FullName -Raw
    $missing = $false
    foreach ($requirement in $sdl.required_defines.windows) {
        $found = $requirement.Split('|') | Where-Object { $text -match "(?m)^#define $_ 1" }
        if ($found) { Write-Host "    backend ok: $requirement" }
        else { Write-Host "    backend MISSING: $requirement"; $missing = $true }
    }
    if ($missing) { throw 'required SDL backends missing' }

    Invoke-Native cmake @('--install', $buildDir)
    Set-Content -Path $stamp -Value $want -NoNewline
    Write-Step "installed SDL3 $($sdl.version) to $Prefix"
}

# --- Odin -------------------------------------------------------------------

$odinArchive = $Lock.odin.archives.$Target
if (-not $odinArchive) { throw "no locked Odin archive for $Target" }
$short = $Lock.odin.commit.Substring(0, 7)
$haveOdin = (Test-Path $Odin) -and ((& $Odin version) -match ":$short")

if ($Force -or -not $haveOdin) {
    $zip = Join-Path $Root "third_party/src/$(Split-Path -Leaf $odinArchive.url)"
    Get-VerifiedFile $odinArchive.url $odinArchive.sha256 $zip
    $tmp = Join-Path $Root "third_party/src/odin-$Target"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive $zip $tmp
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (Test-Path $OdinDir) { Remove-Item -Recurse -Force $OdinDir }
    New-Item -ItemType Directory -Force -Path (Split-Path $OdinDir) | Out-Null
    Move-Item $inner.FullName $OdinDir
    Remove-Item -Recurse -Force $tmp
}

# vendor:sdl3 links vendor/sdl3/SDL3.lib by path. Replace the bundled import
# library and DLL in this project-local copy so they match the locked SDL3.
$vendorSdl = Join-Path $OdinDir 'vendor/sdl3'
Copy-Item (Join-Path $Prefix 'lib/SDL3.lib') $vendorSdl -Force
Copy-Item (Join-Path $Prefix 'bin/SDL3.dll') $vendorSdl -Force

Assert-Odin
Write-Step "odin: $Odin ($(& $Odin version))"
