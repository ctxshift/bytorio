#Requires -Version 7.0
param()
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & ./tools/build-luau-executor.ps1
    if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
    & ./tools/build-odin.ps1 all -Game rpg -Fixtures
    if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
    & node experiments/luau-executor/stage.mjs
    exit $LASTEXITCODE
} finally {Pop-Location}
