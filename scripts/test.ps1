# Runs unit tests and the headless lifecycle integration tests, including the
# optional examples whose libraries are installed.
#
# Usage: scripts/test.ps1 [-RequireFeatures]
#   -RequireFeatures  fail instead of skipping examples whose libraries are missing
param([switch]$RequireFeatures)
. "$PSScriptRoot/common.ps1"

Assert-Odin
Assert-Sdl
New-Item -ItemType Directory -Force -Path $Build | Out-Null
Copy-SdlRuntime $Build

Write-Step 'unit tests: game'
Invoke-Native $Odin @('test', (Join-Path $Root 'game'), '-vet', '-strict-style', "-out:$(Join-Path $Build 'game-tests.exe')")

Write-Step 'unit tests: src (pure procedures only)'
Invoke-Native $Odin @('test', (Join-Path $Root 'src'), '-vet', '-strict-style', "-out:$(Join-Path $Build 'src-tests.exe')")

Write-Step 'integration runner'
$runner = Join-Path $Build 'integration.exe'
Invoke-Native $Odin @('build', (Join-Path $Root 'tests/integration'), '-vet', '-strict-style', "-out:$runner")

function Test-App([string]$App, [string]$Suite) {
    foreach ($mode in 'debug', 'release') {
        & "$PSScriptRoot/build.ps1" $mode $App
        $exe = if ($mode -eq 'debug') { "$App-debug.exe" } else { "$App.exe" }
        $runnerArgs = @((Join-Path $Build $exe), (Join-Path $Build "integration-logs/$App-$mode"), "--suite=$Suite")
        if ($mode -eq 'release') { $runnerArgs += '--release' }
        Write-Step "lifecycle cases: $App ($mode)"
        Invoke-Native $runner $runnerArgs
    }
}

Test-App 'starter' 'starter'

# Feature isolation: the baseline must not import the optional libraries.
$deps = (& dumpbin /nologo /dependents (Join-Path $Build 'starter.exe')) -join "`n"
if ($deps -match 'SDL3_(image|ttf)') { Write-Host $deps; throw 'baseline starter links an optional library' }
Write-Step 'baseline links only SDL3'

foreach ($pair in @(@('images', 'image', '-WithImage'), @('text', 'text', '-WithText'))) {
    $app, $feature, $flag = $pair
    if (-not (Test-Feature $feature)) {
        if ($RequireFeatures) { throw "example '$app' requires: scripts/bootstrap.ps1 $flag" }
        Write-Step "skipping example '$app' (run scripts/bootstrap.ps1 $flag)"
        continue
    }
    Test-App $app $app
}
