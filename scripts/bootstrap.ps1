# Installs the locked Odin release and builds the locked native dependencies.
#
# Usage: scripts/bootstrap.ps1 [-WithImage] [-WithText] [-AllFeatures] [-Force]
# Run from a Visual Studio developer PowerShell (cl.exe on PATH).
param([switch]$WithImage, [switch]$WithText, [switch]$AllFeatures, [switch]$Force)
. "$PSScriptRoot/common.ps1"

Write-Step "host: $Target"
foreach ($tool in 'cmake', 'ninja', 'cl') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "missing required tool: $tool (use a Visual Studio developer shell; see docs/dependencies.md)"
    }
}

$features = @()
if ($WithImage -or $AllFeatures) { $features += 'image' }
if ($WithText -or $AllFeatures) { $features += 'text' }

# Set when a package rebuilds, so packages after it in the same chain rebuild too.
$script:ChainRebuild = $false

# Downloads, verifies, configures and builds one CMake package from the lock.
# Returns the build directory, or $null if the install stamp is current.
function Build-Package([string]$Key) {
    $pkg   = $Lock.$Key
    $stamp = Join-Path $Prefix ".lock-$Key"
    $want  = $pkg | ConvertTo-Json -Depth 10 -Compress
    $have  = if (Test-Path $stamp) { (Get-Content $stamp -Raw).Trim() } else { '' }
    if (-not $Force -and -not $script:ChainRebuild -and $have -eq $want) {
        Write-Step "$Key $($pkg.version) already installed"
        return $null
    }

    $archive = Join-Path $Root "third_party/src/$(Split-Path -Leaf $pkg.archive.url)"
    Get-VerifiedFile $pkg.archive.url $pkg.archive.sha256 $archive
    $src = Join-Path $Root "third_party/src/$($pkg.dir)"
    if (Test-Path $src) { Remove-Item -Recurse -Force $src }
    Invoke-Native tar @('-xzf', $archive, '-C', (Join-Path $Root 'third_party/src'))

    $buildDir = Join-Path $Root "third_party/build/$Key-$Target"
    if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
    $opts = @($pkg.cmake_options.common) + @($pkg.cmake_options.windows)
    Write-Step "configuring $Key $($pkg.version)"
    Invoke-Native cmake (@('-S', $src, '-B', $buildDir, '-G', 'Ninja') + $opts + @(
        "-DCMAKE_INSTALL_PREFIX=$Prefix", "-DCMAKE_PREFIX_PATH=$Prefix", '-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON'))
    Write-Step "building $Key $($pkg.version)"
    Invoke-Native cmake @('--build', $buildDir)
    return @{ BuildDir = $buildDir; Src = $src; Stamp = $stamp; Want = $want }
}

function Complete-Package([string]$Key, $Built) {
    Invoke-Native cmake @('--install', $Built.BuildDir)
    $licenseFiles = $Lock.$Key.PSObject.Properties['license_files']
    if ($licenseFiles) {
        $dest = Join-Path $Prefix "licenses/$Key"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($file in $licenseFiles.Value) { Copy-Item (Join-Path $Built.Src $file) $dest }
    }
    Set-Content -Path $Built.Stamp -Value $Built.Want -NoNewline
    Write-Step "installed $Key $($Lock.$Key.version) to $Prefix"
}

# Fails if a built DLL imports a dependency the lock forbids.
function Assert-Links([string]$Key, [string]$Dll) {
    $deps = (& dumpbin /nologo /dependents (Join-Path $Prefix "bin/$Dll")) -join "`n"
    foreach ($bad in $Lock.$Key.must_not_link) {
        if ($deps -match "(?i)$bad") { Write-Host $deps; throw "$Dll links forbidden dependency '$bad'" }
    }
    Write-Host "    links ok: $Dll"
}

# --- SDL3 -------------------------------------------------------------------

$built = Build-Package 'sdl3'
if ($built) {
    if (Test-Path $Prefix) { Remove-Item -Recurse -Force $Prefix }
    $config = Get-ChildItem -Recurse -Filter SDL_build_config.h $built.BuildDir | Select-Object -First 1
    if (-not $config) { throw "SDL_build_config.h not found in $($built.BuildDir)" }
    $text = Get-Content $config.FullName -Raw
    $missing = $false
    foreach ($requirement in $Lock.sdl3.required_defines.windows) {
        $found = $requirement.Split('|') | Where-Object { $text -match "(?m)^#define $_ 1" }
        if ($found) { Write-Host "    backend ok: $requirement" }
        else { Write-Host "    backend MISSING: $requirement"; $missing = $true }
    }
    if ($missing) { throw 'required SDL backends missing' }
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    Complete-Package 'sdl3' $built
}

# --- Optional features --------------------------------------------------------

foreach ($feature in $features) {
    $script:ChainRebuild = $false
    foreach ($key in $Lock.features.$feature.packages) {
        $built = Build-Package $key
        if ($built) { Complete-Package $key $built; $script:ChainRebuild = $true }
    }
    switch ($feature) {
        'image' { Assert-Links 'sdl3_image' 'SDL3_image.dll' }
        'text'  { Assert-Links 'sdl3_ttf' 'SDL3_ttf.dll' }
    }
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

# vendor:sdl3 (and its image/ttf packages) link import libraries by path inside
# the Odin distribution. Replace the bundled ones in this project-local copy so
# they match the locked native builds exactly.
$vendorSdl = Join-Path $OdinDir 'vendor/sdl3'
$replacements = @(@{ Name = 'SDL3'; Dir = $vendorSdl })
if (Test-Feature 'image') { $replacements += @{ Name = 'SDL3_image'; Dir = (Join-Path $vendorSdl 'image') } }
if (Test-Feature 'text')  { $replacements += @{ Name = 'SDL3_ttf';   Dir = (Join-Path $vendorSdl 'ttf') } }
foreach ($r in $replacements) {
    Copy-Item (Join-Path $Prefix "lib/$($r.Name).lib") $r.Dir -Force
    Copy-Item (Join-Path $Prefix "bin/$($r.Name).dll") $r.Dir -Force
}

Assert-Odin
Write-Step "odin: $Odin ($(& $Odin version))"
