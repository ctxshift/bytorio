param(
    [ValidateSet('native', 'web')][string]$Target = 'native',
    [string]$EmsdkRoot = $env:EMSDK,
    [string]$NativeGenerator = '',
    [int]$Jobs = 8,
    [ValidateSet('hello', 'rpg')][string]$Game = 'hello'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root "build/$Target"
$source = Join-Path $root 'examples/hello/main.luau'
if ($Game -eq 'rpg') {
    Push-Location $root
    try { & node tools/build-rpg-assets.mjs; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } } finally { Pop-Location }
    $source = Join-Path $root 'build/rpg/main.luau'
    $output = Join-Path $root "build/rpg-luau/$Target"
}
$gameArgs = @("-DCONSOLE_GAME_SOURCE=$source")
if ($Game -eq 'rpg') {
    foreach ($dependency in @('luau','sdl3')) {
        $existing = Join-Path $root "build/$Target/_deps/$dependency-src"
        if (Test-Path -LiteralPath $existing) { $gameArgs += "-DFETCHCONTENT_SOURCE_DIR_$($dependency.ToUpper())=$existing" }
    }
}

if ($Target -eq 'native') {
    $configureArgs = @('-S', $root, '-B', $output, '-DCMAKE_BUILD_TYPE=Release')
    if ($NativeGenerator) { $configureArgs += @('-G', $NativeGenerator) }
    & cmake @configureArgs @gameArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & cmake --build $output --config Release --target player core_tests rpg_replay -j $Jobs
} else {
    if (-not $EmsdkRoot) { $EmsdkRoot = Join-Path $root '.tools/emsdk' }
    $emcmake = Join-Path $EmsdkRoot 'upstream/emscripten/emcmake.exe'
    if (-not (Test-Path -LiteralPath $emcmake)) {
        throw 'Emscripten 6.0.12 is required. Set EMSDK or use -EmsdkRoot with an installed and activated SDK.'
    }
    & $emcmake cmake -S $root -B $output -G Ninja -DCMAKE_BUILD_TYPE=Release @gameArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & cmake --build $output --target player -j $Jobs
}
exit $LASTEXITCODE
