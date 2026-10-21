# Shared helpers for the Windows scripts. Dot-source this file.
# Requires PowerShell 7+ and a Visual Studio developer shell (cl.exe on PATH).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root   = Split-Path -Parent $PSScriptRoot
$Lock   = Get-Content (Join-Path $Root 'deps.lock.json') -Raw | ConvertFrom-Json
$Arch   = switch ($env:PROCESSOR_ARCHITECTURE) { 'AMD64' { 'amd64' } 'ARM64' { 'arm64' } default { throw "unsupported architecture $_" } }
$Target = "windows-$Arch"
$Prefix = Join-Path $Root "third_party/prefix/$Target"
$Build  = Join-Path $Root 'build'
# On Windows the locked Odin always lives in the project: its vendor/sdl3
# import library and DLL are replaced with the locked SDL3 build.
$OdinDir = Join-Path $Root "third_party/odin/$Target"
$Odin    = Join-Path $OdinDir 'odin.exe'

function Write-Step([string]$Message) { Write-Host "==> $Message" }

function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @())
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe exited with code $LASTEXITCODE" }
}

function Get-VerifiedFile([string]$Url, [string]$Sha256, [string]$Dest) {
    if (-not (Test-Path $Dest)) {
        Write-Step "downloading $Url"
        New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
        Invoke-WebRequest -Uri $Url -OutFile "$Dest.part"
        Move-Item "$Dest.part" $Dest
    }
    $got = (Get-FileHash -Algorithm SHA256 $Dest).Hash.ToLowerInvariant()
    if ($got -ne $Sha256) {
        Remove-Item $Dest
        throw "checksum mismatch for ${Url}: expected $Sha256, got $got"
    }
}

function Assert-Odin {
    if (-not (Test-Path $Odin)) { throw "locked Odin not found at $Odin; run scripts/bootstrap.ps1" }
    $short = $Lock.odin.commit.Substring(0, 7)
    if (-not ((& $Odin version) -match ":$short")) { throw "$Odin is not the locked commit $short; run scripts/bootstrap.ps1 -Force" }
}

function Assert-Sdl {
    if (-not (Test-Path (Join-Path $Prefix 'bin/SDL3.dll'))) { throw "locked SDL3 not found in $Prefix; run scripts/bootstrap.ps1" }
}

# Windows finds DLLs next to the executable; keep the locked one there.
function Copy-SdlRuntime([string]$Dir) {
    Copy-Item (Join-Path $Prefix 'bin/SDL3.dll') $Dir -Force
}
