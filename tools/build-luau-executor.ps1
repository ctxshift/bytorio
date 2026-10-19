#Requires -Version 7.0
param([int]$Jobs=8)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $output='build/luau-executor'
    $emcmake=Join-Path $root '.tools/emsdk/upstream/emscripten/emcmake.exe'
    # Keep Luau sources with the executor, independent of retired player builds.
    $args=@('cmake','-S','experiments/luau-executor','-B',$output,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release','-DFETCHCONTENT_SOURCE_DIR_LUAU=')
    & $emcmake @args
    if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
    & cmake --build $output --target luau_executor -j $Jobs
    exit $LASTEXITCODE
} finally {Pop-Location}
