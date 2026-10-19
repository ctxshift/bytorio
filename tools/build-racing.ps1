#Requires -Version 7.0
param()
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & "$PSScriptRoot/build-luau-executor.ps1"
    if ($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
    & "$PSScriptRoot/build-odin.ps1" -Game racing
    if ($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
    & node experiments/luau-executor/stage.mjs build/racing-player racing
    exit $LASTEXITCODE
} finally {Pop-Location}
