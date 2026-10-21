# Host test suite for WG Tunnel.
#
# Builds the C core and the two test harnesses with Zig's clang and runs them.
# No HarmonyOS SDK or device is required.
#
#   pwsh -File tools/run_host_tests.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$zig = "C:\Users\simon\AppData\Local\Microsoft\WinGet\Packages\zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe\zig-x86_64-windows-0.17.0\zig.exe"
if (-not (Test-Path $zig)) {
    $zig = (Get-Command zig -ErrorAction SilentlyContinue).Source
}
if (-not $zig) {
    throw "zig is required (winget install zig.zig)"
}

New-Item -ItemType Directory -Force -Path build | Out-Null
$wg = "entry/src/main/cpp/wg"
$inc = @("-I", $wg, "-I", "$wg/third_party")
$core = @("$wg/wg_proto.c", "$wg/wg_crypto.c", "$wg/wg_blake2s.c", "$wg/third_party/monocypher.c", "$wg/wg_engine.c")
# recycle_probe.c includes wg_engine.c itself, so linking the engine twice would
# duplicate every symbol.
$coreNoEngine = @("$wg/wg_proto.c", "$wg/wg_crypto.c", "$wg/wg_blake2s.c", "$wg/third_party/monocypher.c")

Write-Host "== protocol selftest ==" -ForegroundColor Cyan
# wg_engine.c talks to Winsock, so the self test needs the socket library too.
& $zig cc -std=c11 -O2 @inc -o build/wgtest.exe tools/wgtest.c @core -lws2_32
if ($LASTEXITCODE -ne 0) { throw "protocol selftest did not build" }
& .\build\wgtest.exe selftest
if ($LASTEXITCODE -ne 0) { throw "protocol selftest failed" }

Write-Host "== interop against the python reference ==" -ForegroundColor Cyan
& python tools/interop.py
if ($LASTEXITCODE -ne 0) { throw "interop failed" }

Write-Host "== tunnel engine ==" -ForegroundColor Cyan
& $zig cc -std=c11 -O2 @inc -o build/enginetest.exe tools/enginetest.c @core -lws2_32
& .\build\enginetest.exe
if ($LASTEXITCODE -ne 0) { throw "engine test failed" }

Write-Host "== idle keepalive and socket recycle ==" -ForegroundColor Cyan
# enginetest writes a data packet before it looks for a keepalive, and it runs
# seconds after boot, so it cannot see an idle tunnel on a machine that has been
# up for hours - which is every phone. These two probes ask the question the
# way the device experiences it.
& $zig cc -std=c11 -O2 @inc -o build/keepalive_probe.exe tools/keepalive_probe.c @core -lws2_32
if ($LASTEXITCODE -ne 0) { throw "keepalive probe did not build" }
& .\build\keepalive_probe.exe
if ($LASTEXITCODE -ne 0) { throw "keepalive probe failed" }

& $zig cc -std=c11 -O2 @inc -o build/recycle_probe.exe tools/recycle_probe.c @coreNoEngine -lws2_32
if ($LASTEXITCODE -ne 0) { throw "recycle probe did not build" }
& .\build\recycle_probe.exe
if ($LASTEXITCODE -ne 0) { throw "recycle probe failed" }

Write-Host "== configuration bridge ==" -ForegroundColor Cyan
& $zig c++ -std=c++17 -O2 @inc -o build/jsontest.exe tools/jsontest.cpp
& .\build\jsontest.exe
if ($LASTEXITCODE -ne 0) { throw "json test failed" }

Write-Host "all host tests passed" -ForegroundColor Green
