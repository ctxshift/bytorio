#Requires -Version 7.0
param([int]$Jobs=8)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $source='build/luau-executor/_deps/luau-src'
    if (-not (Test-Path -LiteralPath "$source/CMakeLists.txt")) {
        & "$PSScriptRoot/build-luau-executor.ps1"
        if ($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
    }
    & cmake --fresh -S $source -B .tools/luau-tools -DLUAU_BUILD_CLI=ON -DLUAU_BUILD_TESTS=OFF
    if ($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
    & cmake --build .tools/luau-tools --config Release --target Luau.Analyze.CLI -j $Jobs
    exit $LASTEXITCODE
} finally {Pop-Location}
