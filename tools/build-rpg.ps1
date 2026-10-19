#Requires -Version 7.0
param([string]$EmsdkRoot = $env:EMSDK, [string]$Odin = '')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & ./tools/build-odin.ps1 all -Game rpg -Odin $Odin -Fixtures
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & ./tools/build.ps1 native -Game rpg
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & ./tools/build.ps1 web -Game rpg -EmsdkRoot $EmsdkRoot
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & node tools/stage-rpg.mjs
    exit $LASTEXITCODE
} finally { Pop-Location }
