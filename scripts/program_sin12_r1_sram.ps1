param([switch]$Driver12VOff, [switch]$WheelsRaised)
$ErrorActionPreference = 'Stop'
if (-not $Driver12VOff -or -not $WheelsRaised) { throw 'Confirm actual driver 12V OFF and wheels raised.' }
$sin12R1Root = Split-Path -Parent $PSScriptRoot
$sin12R1Archive = Join-Path $sin12R1Root 'output\board\sin12_r1_map2613_2026-10-27'
$sin12R1Manifest = Get-Content -LiteralPath (Join-Path $sin12R1Archive 'qualification.json') -Raw | ConvertFrom-Json
if (-not $sin12R1Manifest.internal_timing_qualified -or $sin12R1Manifest.user_code -ne '0x534E3241' -or $sin12R1Manifest.map_id -ne '0x2613') { throw 'Not a qualified SIN12 R1 release.' }
$sin12R1Fs = Join-Path $sin12R1Archive 'acg720_motor_bt_autonav.fs'
if ((Get-FileHash -LiteralPath $sin12R1Fs -Algorithm SHA256).Hash -ne $sin12R1Manifest.sha256.'acg720_motor_bt_autonav.fs') { throw 'Bitstream hash mismatch.' }
$sin12R1Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$sin12R1Stamp = Get-Date -Format yyyyMMdd_HHmmss
$sin12R1Log = Join-Path $sin12R1Root "output\board\sin12_r1_sram_${sin12R1Stamp}.log"
& $sin12R1Cli --device GW5AT-60B --operation_index 2 --fsFile $sin12R1Fs --cable-index 1 --frequency 2.5MHz *> $sin12R1Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $sin12R1Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $sin12R1Log" }
$sin12R1CodeLog = Join-Path $sin12R1Root "output\board\sin12_r1_code_${sin12R1Stamp}.log"
& $sin12R1Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $sin12R1CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $sin12R1CodeLog -Raw) -notmatch '0x534[Ee]3241') { throw "Readback mismatch: $sin12R1CodeLog" }
Write-Output "SIN12 R1 SRAM 0x534E3241 verified; map0x2613. Logs: $sin12R1Log ; $sin12R1CodeLog"
