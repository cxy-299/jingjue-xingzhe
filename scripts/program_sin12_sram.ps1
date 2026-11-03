param([switch]$Driver12VOff, [switch]$WheelsRaised)
$ErrorActionPreference = 'Stop'
if (-not $Driver12VOff -or -not $WheelsRaised) { throw 'Confirm actual driver 12V OFF and wheels raised before SRAM download.' }
$sin12Root = Split-Path -Parent $PSScriptRoot
$sin12Fs = Join-Path $sin12Root 'output\board\sin12_timing_pass_2026-10-27\acg720_motor_bt_autonav.fs'
$sin12Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
if ((Get-FileHash -LiteralPath $sin12Fs -Algorithm SHA256).Hash -ne '30C5896F5B0034E56B159C9E730AEF6ECA8008C1F1ABC0E82814919871EE8D73') { throw 'SIN12 fs hash mismatch.' }
$sin12Stamp = Get-Date -Format yyyyMMdd_HHmmss
$sin12Log = Join-Path $sin12Root "output\board\sin12_sram_${sin12Stamp}.log"
& $sin12Cli --device GW5AT-60B --operation_index 2 --fsFile $sin12Fs --cable-index 1 --frequency 2.5MHz *> $sin12Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $sin12Log -Raw) -notmatch 'Finished\.') { throw "SRAM program failed: $sin12Log" }
$sin12CodeLog = Join-Path $sin12Root "output\board\sin12_code_${sin12Stamp}.log"
& $sin12Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $sin12CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $sin12CodeLog -Raw) -notmatch '0x53494[Ee]43') { throw "SIN12 independent User Code mismatch: $sin12CodeLog" }
Write-Output "SIN12 SRAM verified 0x53494E43. Logs: $sin12Log ; $sin12CodeLog"
