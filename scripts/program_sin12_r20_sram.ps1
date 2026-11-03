#requires -Version 7.0
param(
    [switch]$ValidateFiles,
    [switch]$UserRequestedSram,
    [switch]$ConsoleDisconnectedConfirmed,
    [string]$PreparationConfirmation
)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $UserRequestedSram -or -not $ConsoleDisconnectedConfirmed -or -not $PreparationConfirmation)) {
    throw 'Require explicit R20 SRAM request and fresh parked/disconnected/prepared confirmation; old confirmations cannot be reused.'
}
$r20Root = Split-Path -Parent $PSScriptRoot
$r20Out = Join-Path $r20Root 'output\board'
$r20Archive = Join-Path $r20Out 'sin12_hdmi_r20_20261102_143316'
$r20Python = 'C:\Users\caoxi\AppData\Local\Programs\Python\Python310\python.exe'
& $r20Python (Join-Path $PSScriptRoot 'validate_sin12_r20_sram_snapshot.py')
if ($LASTEXITCODE -ne 0) { throw 'Pinned release preflight failed. Hardware untouched.' }
if ($ValidateFiles) { return }
if (Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('programmer_cli.exe','gw_sh.exe','gw_pnr.exe','gw_syn.exe') }) {
    throw 'Another programming/build operation is active.'
}
$r20Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r20Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r20Scan = Join-Path $r20Out "sin12_r20_scan_$r20Stamp.log"
$r20Log = Join-Path $r20Out "sin12_r20_sram_$r20Stamp.log"
$r20Code = Join-Path $r20Out "sin12_r20_code_$r20Stamp.log"
$r20EventFile = Join-Path $r20Out "SIN12_R20_SRAM_EVENT_$r20Stamp.json"
$r20Event = [ordered]@{
    timestamp=(Get-Date -Format o);release='SIN12 R20 SRAM';expected_user_code='0x534E3254';firmware='K14';map_id='2613'
    archive=$r20Archive;archive_files_verified=420
    fs_sha256='509d6a799466a99a39f816745570e4341c450e6cb210454d8e92461abe111873'
    netlist_sha256='f61d0ad4a9f59d11c705bac70d41073684313c6a075cc454c869ef8c2d9fd09a'
    user_explicitly_requested_sram=$true;console_disconnected_newly_confirmed_by_user=$true;preparation_confirmation=$PreparationConfirmation
    physical_preparation_independently_verified=$false;sram_program='not_started';independent_user_code_readback='not_started'
    full_sram_byte_readback_performed=$false;flash_written_this_run=$false;motor_or_serial_command_sent_by_script=$false
    pi_modified=$false;vehicle_validated=$false;GUI_restarted=$false;logs=@($r20Scan,$r20Log,$r20Code)
    programmer_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    validator_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'validate_sin12_r20_sram_snapshot.py') -Algorithm SHA256).Hash
    requested_JTAG_frequency='2.5MHz';note='SRAM only operation2, separate UserCode operation73. No reconnect/task start. Actual CLI frequency may be updated automatically; preserve original logs.'
}
try {
    & $r20Cli --scan --cable-index 1 --frequency 2.5MHz *> $r20Scan
    $r20Event.scan_exit_code = $LASTEXITCODE
    $r20ScanText = Get-Content -LiteralPath $r20Scan -Raw
    if ($LASTEXITCODE -ne 0 -or $r20ScanText -notmatch '0x0001481B' -or $r20ScanText -notmatch '1 device\(s\) found') { throw 'Expected exactly one GW5AT-60B target; SRAM not started.' }
    $r20Event.sram_program = 'started'
    & $r20Cli --device GW5AT-60B --operation_index 2 --fsFile (Join-Path $r20Archive 'impl\pnr\sin12_hdmi_system.fs') --cable-index 1 --frequency 2.5MHz *> $r20Log
    $r20Event.program_exit_code = $LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r20Log -Raw) -notmatch 'Finished\.') { $r20Event.sram_program='failed';throw 'R20 SRAM operation failed.' }
    $r20Event.sram_program = 'passed'
    & $r20Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r20Code
    $r20Event.readback_exit_code = $LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r20Code -Raw) -notmatch '0x534[Ee]3254') { $r20Event.independent_user_code_readback='failed';throw 'R20 UserCode mismatch.' }
    $r20Event.independent_user_code_readback = 'passed'
    $r20Event.observed_user_code = '0x534E3254'
} catch {
    if ($r20Event.sram_program -eq 'started') { $r20Event.sram_program='failed' }
    $r20Event.error=$_.Exception.Message
    throw
} finally {
    $r20Event.finished_timestamp = Get-Date -Format o
    $r20Event | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $r20EventFile -Encoding utf8
    Write-Output "Hardware event: $r20EventFile"
}
Write-Output 'R20 SRAM programmed; independent UserCode0x534E3254 matched. Flash not written; no automatic reconnect.'
