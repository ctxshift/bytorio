#Requires -Version 7.0
param(
    [ValidateSet('all', 'native', 'web')][string]$Target = 'all',
    [string]$Odin = '',
    [switch]$Fixtures,
    [ValidateSet('hello', 'rpg', 'racing')][string]$Game = 'hello'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not $Odin) {
        $localCompiler = Join-Path $root '.tools/odin/dist/odin.exe'
        if (Test-Path -LiteralPath $localCompiler) { $Odin = $localCompiler }
        else {
            $installed = Get-Command odin -ErrorAction SilentlyContinue
            if ($installed) { $Odin = $installed.Source }
            elseif ($IsWindows) {
                New-Item -ItemType Directory -Force .tools | Out-Null
                $archive = '.tools/odin-dev-2026-10.zip'
                if (-not (Test-Path -LiteralPath $archive)) {
                    Invoke-WebRequest -Uri 'https://github.com/odin-lang/Odin/releases/download/dev-2026-10/odin-windows-amd64-dev-2026-10.zip' -OutFile $archive
                }
                $expected = 'B6B2E426A8B6F147B74EC7E18BEF8DF27CF40FE16193159DF7CA09A0CC0C2011'
                if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) { throw 'Odin archive checksum mismatch.' }
                Expand-Archive -LiteralPath $archive -DestinationPath .tools/odin -Force
                $Odin = $localCompiler
            } else { throw 'Install Odin dev-2026-10 (84bc3fc) and provide -Odin or put it on PATH.' }
        }
    }
    $Odin = (Get-Command $Odin -ErrorAction Stop).Source
    $version = & $Odin version
    if ($version -notmatch '84bc3fc') { throw 'This slice requires Odin dev-2026-10 (84bc3fc).' }
    $common = @('-o:minimal', '-source-code-locations:filename')
    $web = 'build/odin-player/web'
    $native = 'build/odin-player/native'
    $gameSource = 'examples/hello-odin'
    if ($Game -eq 'rpg') {
        & node tools/build-rpg-assets.mjs
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $web = 'build/rpg-odin/web'
        $native = 'build/rpg-odin/native'
        $gameSource = 'examples/rpg-odin'
        $common = @('-o:speed', '-source-code-locations:filename')
    }
    if ($Game -eq 'racing') {
        & node tools/build-racing-assets.mjs
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $web = 'build/racing-odin/web'
        $native = 'build/racing-odin/native'
        $gameSource = 'examples/racing-odin'
        $common = @('-o:speed', '-source-code-locations:filename')
    }
    New-Item -ItemType Directory -Force $web, $native | Out-Null
    & $Odin build $gameSource -target:freestanding_wasm32 -no-entry-point @common "-out:$web/game.wasm" '-extra-linker-flags:--max-memory=8388608'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if ($Target -in @('all', 'web')) {
        & $Odin build runtime/odin/web -target:freestanding_wasm32 -no-entry-point @common "-out:$web/runtime.wasm" '-extra-linker-flags:--max-memory=8388608'
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        foreach ($file in @('player.html','player.js','worker.js','policy.js','executor-cache.js','executor-cache-core.js')) {
            Copy-Item -LiteralPath "runtime/odin/web/$file" -Destination "$web/$file"
        }
        New-Item -ItemType Directory -Force "$web/licenses" | Out-Null
        Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $Odin) 'LICENSE') -Destination "$web/licenses/odin.txt"
    }
    if ($Target -in @('all', 'native')) {
        if (-not $IsWindows) { throw 'The native adapter currently targets Windows x64.' }
        $dependency = '.tools/wasmtime/wasmtime-v49.0.3-x86_64-windows-c-api'
        if (-not (Test-Path -LiteralPath "$dependency/lib/wasmtime.dll")) {
            $archive = '.tools/wasmtime-v49.0.3.zip'
            New-Item -ItemType Directory -Force .tools | Out-Null
            if (-not (Test-Path -LiteralPath $archive)) {
                Invoke-WebRequest -Uri 'https://github.com/bytecodealliance/wasmtime/releases/download/v49.0.3/wasmtime-v49.0.3-x86_64-windows-c-api.zip' -OutFile $archive
            }
            $expected = 'F8DABBC1DF2358F15EFFBD6E50C940C03DF3836E13CBF4F09CDF6369057AED01'
            if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) { throw 'Wasmtime archive checksum mismatch.' }
            Expand-Archive -LiteralPath $archive -DestinationPath .tools/wasmtime -Force
        }
        & $Odin build runtime/odin/native @common "-out:$native/player.exe" "-collection:deps=$dependency/lib"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Copy-Item -LiteralPath "$web/game.wasm" -Destination "$native/game.wasm"
        Copy-Item -LiteralPath "$dependency/lib/wasmtime.dll" -Destination "$native/wasmtime.dll"
        $compilerRoot = Split-Path -Parent $Odin
        Copy-Item -LiteralPath "$compilerRoot/vendor/sdl3/SDL3.dll" -Destination "$native/SDL3.dll"
        New-Item -ItemType Directory -Force "$native/licenses" | Out-Null
        Copy-Item -LiteralPath "$dependency/LICENSE" -Destination "$native/licenses/wasmtime.txt"
        Copy-Item -LiteralPath "$compilerRoot/vendor/sdl3/LICENSE.txt" -Destination "$native/licenses/sdl3.txt"
        Copy-Item -LiteralPath "$compilerRoot/LICENSE" -Destination "$native/licenses/odin.txt"
    }
    if ($Fixtures) {
        New-Item -ItemType Directory -Force "$web/fixtures" | Out-Null
        $kinds = @('loop','abi','offset','command','trap','list-count','list-offset','list-command')
        foreach ($kind in $kinds) {
            $fault = $kinds.IndexOf($kind) + 1
            & $Odin build tests/odin/fixtures -target:freestanding_wasm32 -no-entry-point @common "-define:TEST_FAULT=$fault" "-out:$web/fixtures/$kind.wasm" '-extra-linker-flags:--max-memory=8388608'
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
    }
    Write-Output "Odin $Game $Target build ready in $web and $native."
} finally { Pop-Location }
