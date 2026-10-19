#Requires -Version 7.0
param([int]$Jobs=8)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $output='build/luau-executor'
    $emcmake=Join-Path $root '.tools/emsdk/upstream/emscripten/emcmake.exe'
    $args=@('cmake','-S','experiments/luau-executor','-B',$output,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release')
    $existing=Join-Path $root 'build/native/_deps/luau-src'
    if(Test-Path -LiteralPath $existing){$args+="-DFETCHCONTENT_SOURCE_DIR_LUAU=$existing"}
    & $emcmake @args
    if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
    & cmake --build $output --target luau_executor -j $Jobs
    exit $LASTEXITCODE
} finally {Pop-Location}
