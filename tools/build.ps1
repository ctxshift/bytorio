param(
    [ValidateSet('native', 'web')][string]$Target = 'native',
    [string]$EmsdkRoot = $env:EMSDK,
    [string]$NativeGenerator = '',
    [int]$Jobs = 8
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root "build/$Target"

if ($Target -eq 'native') {
    $configureArgs = @('-S', $root, '-B', $output, '-DCMAKE_BUILD_TYPE=Release')
    if ($NativeGenerator) { $configureArgs += @('-G', $NativeGenerator) }
    & cmake @configureArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & cmake --build $output --config Release --target player core_tests -j $Jobs
} else {
    if (-not $EmsdkRoot) { $EmsdkRoot = Join-Path $root '.tools/emsdk' }
    $emcmake = Join-Path $EmsdkRoot 'upstream/emscripten/emcmake.exe'
    if (-not (Test-Path -LiteralPath $emcmake)) {
        throw 'Emscripten 6.0.12 is required. Set EMSDK or use -EmsdkRoot with an installed and activated SDK.'
    }
    & $emcmake cmake -S $root -B $output -G Ninja -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & cmake --build $output --target player -j $Jobs
}
exit $LASTEXITCODE
