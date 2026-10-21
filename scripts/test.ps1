# Runs unit tests and the headless lifecycle integration tests.
#
# Usage: scripts/test.ps1
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

& "$PSScriptRoot/build.ps1" debug
Write-Step 'lifecycle cases: debug'
Invoke-Native $runner @((Join-Path $Build 'starter-debug.exe'), (Join-Path $Build 'integration-logs/debug'))

& "$PSScriptRoot/build.ps1" release
Write-Step 'lifecycle cases: release'
Invoke-Native $runner @((Join-Path $Build 'starter.exe'), (Join-Path $Build 'integration-logs/release'), '--release')
