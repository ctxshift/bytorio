#Requires -Version 7.0
param()
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & ./tools/build-rpg.ps1
    exit $LASTEXITCODE
} finally {Pop-Location}
