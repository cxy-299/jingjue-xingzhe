param([string]$Port = 'COM9')
$ErrorActionPreference = 'Stop'
$sin12ConsoleRoot = Split-Path -Parent $PSScriptRoot
$sin12ConsolePython = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python310\python.exe'
if (-not (Test-Path -LiteralPath $sin12ConsolePython)) { $sin12ConsolePython = (Get-Command python -ErrorAction Stop).Source }
Set-Location -LiteralPath $sin12ConsoleRoot
# No --connect: opening the console neither opens a serial port nor permits motion.
& $sin12ConsolePython (Join-Path $sin12ConsoleRoot 'fpga\motor_bt_drive\pc_unified_console.py') --firmware SIN12 --port $Port
if ($LASTEXITCODE -ne 0) { throw "SIN12 console exited with code $LASTEXITCODE" }
