#requires -Version 7.0
param([switch]$ValidateFiles, [switch]$UserRequestedSram)
$ErrorActionPreference='Stop'
if (-not $ValidateFiles -and -not $UserRequestedSram) { throw 'Explicit user request for R17 SRAM required; never run automatically.' }
$r17Root=Split-Path -Parent $PSScriptRoot
$r17Archive=Join-Path $r17Root 'output\board\sin12_hdmi_r17_20261101_163807'
$r17ExpectedFs='8549e8358534c07f616b650ae468b6b13b4c349be03340620ea8dde9e043fd88'
$r17ExpectedVg='b97af24fd4f2997e6ea2530df954b038a327a0870919279229efc19e07c1dff9'
$r17Fs=Join-Path $r17Archive 'impl\pnr\sin12_hdmi_system.fs'
$r17Report=Get-Content -Raw -LiteralPath (Join-Path $r17Archive 'BUILD_VERIFICATION.json') | ConvertFrom-Json -AsHashtable
$r17Inventory=Get-Content -Raw -LiteralPath (Join-Path $r17Archive 'ARCHIVE_SHA256.json') | ConvertFrom-Json -AsHashtable
if ($r17Inventory.Count -ne 588 -or $r17Report.usercode -ne '534E3251' -or $r17Report.firmware -ne 'K11' -or
    $r17Report.map_id -ne '2613' -or $r17Report.hardware_source_count -ne 58 -or $r17Report.software_validation_source_count -ne 98 -or
    $r17Report.fs_sha256 -ne $r17ExpectedFs -or $r17Report.netlist_sha256 -ne $r17ExpectedVg -or
    $r17Report.internal_sta_checks_pass -ne $true -or $r17Report.setup_violations -ne 0 -or $r17Report.hold_violations -ne 0 -or
    $r17Report.constraint_audit.passed -ne $true -or $r17Report.constraint_audit.active_constraints.Count -ne 16 -or
    $r17Report.constraint_audit.pixel_async_false_path_endpoints.Count -ne 2) { throw 'Pinned R17 evidence mismatch.' }
foreach ($r17Key in @('tof','target','recovery','settle','nav','two_stage')) {
    if ($r17Report.mapped[$r17Key].passed -ne $true -or $r17Report.mapped[$r17Key].netlist_sha256 -ne $r17ExpectedVg -or
        $r17Report.mapped[$r17Key].internal_forces -ne $false) { throw "Mapped evidence mismatch: $r17Key" }
}
if ($r17Report.mapped.tof.checks -ne 91 -or $r17Report.mapped.target.vectors -ne 2172 -or
    $r17Report.mapped.recovery.primitive_count -ne 3751 -or $r17Report.mapped.nav.primitive_count -ne 24466 -or
    $r17Report.mapped.settle.primitive_count -ne 3751 -or $r17Report.mapped.two_stage.primitive_count -ne 3751 -or
    $r17Report.fmax_mhz.clk_50m -lt 50 -or $r17Report.fmax_mhz.camera_pclk -lt 75.002 -or $r17Report.fmax_mhz.camera_pixel -lt 75 -or
    $r17Report.software_tests.nongui -ne 174 -or $r17Report.software_tests.isolated_tk -ne 106 -or $r17Report.software_tests.skips -ne 0) { throw 'R17 timing/coverage mismatch.' }
foreach ($r17Table in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]')) {
    if ($r17Report.tables[$r17Table].reported_paths -ne 12 -or $r17Report.tables[$r17Table].endpoint_set.Count -ne 4 -or
        $r17Report.tables[$r17Table].minimum_slack_ns -le 0) { throw "Serializer timing mismatch: $r17Table" }
}
foreach ($r17Table in @('3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r17Report.tables[$r17Table].reported_paths -lt 200 -or $r17Report.tables[$r17Table].minimum_slack_ns -le 0) { throw "Global reset timing mismatch: $r17Table" }
}
foreach ($r17Entry in $r17Inventory.GetEnumerator()) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $r17Archive $r17Entry.Key)).Hash -ne $r17Entry.Value) { throw "Archive hash mismatch: $($r17Entry.Key)" }
}
foreach ($r17Entry in $r17Report.source_hashes.GetEnumerator()) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path (Join-Path $r17Archive 'sources') $r17Entry.Key)).Hash -ne $r17Entry.Value) { throw "Archived source mismatch: $($r17Entry.Key)" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $r17Fs).Hash -ne $r17ExpectedFs -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $r17Archive 'impl\gwsynthesis\sin12_hdmi_system.vg')).Hash -ne $r17ExpectedVg) { throw 'Pinned bitstream/netlist mismatch.' }
$r17Process=Get-Content -Raw -LiteralPath (Join-Path $r17Archive 'impl\sin12_hdmi_system_process_config.json') | ConvertFrom-Json -AsHashtable
$r17Cfg=Get-Content -Raw -LiteralPath (Join-Path $r17Archive 'impl\pnr\device.cfg')
if ($r17Process.Optimization_Goal -ne 'Timing' -or $r17Process.Place_Option -ne '1' -or $r17Process.Max_Fanout -ne 1000 -or
    $r17Process.Replicate_Resources -ne $true -or $r17Process.Route_Option -ne '2' -or $r17Process.Run_Timing_Driven -ne $true -or
    $r17Process.SSPI -ne $true -or $r17Process.JTAG -ne $false -or $r17Process.MSPI -ne $false -or
    $r17Cfg -notmatch '0x534E3251' -or $r17Cfg -notmatch 'set JTAG regular_io = false') { throw 'Device/process configuration mismatch.' }
if ($ValidateFiles) { Write-Output 'Pinned R17:588 archive hashes,58 hardware/98 software snapshots,STA/constraints/six mapped reports verified; no hardware access.'; return }
if (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }) { throw 'Another programmer operation is active.' }
$r17Cli='D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r17Stamp=Get-Date -Format yyyyMMdd_HHmmss_fff
$r17Log=Join-Path $r17Root "output\board\sin12_r17_sram_$r17Stamp.log"
$r17CodeLog=Join-Path $r17Root "output\board\sin12_r17_code_$r17Stamp.log"
$r17EventFile=Join-Path $r17Root "output\board\SIN12_R17_SRAM_EVENT_$r17Stamp.json"
$r17Event=[ordered]@{
    timestamp=(Get-Date -Format o);release='SIN12 R17 experimental SRAM';expected_user_code='0x534E3251';firmware='K11';map_id='2613'
    archive=$r17Archive;fs_sha256=$r17ExpectedFs;netlist_sha256=$r17ExpectedVg;archive_files_verified=588
    user_explicitly_requested_sram=$true;physical_preparation_independently_verified=$false
    sram_program='not_started';independent_user_code_readback='not_started';full_sram_byte_readback_performed=$false
    flash_written_this_run=$false;motor_or_serial_command_sent_by_script=$false;pi_modified=$false
    vehicle_validated=$false;logs=@($r17Log,$r17CodeLog)
    programmer_script_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash
    current_host_console_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $r17Root 'fpga\motor_bt_drive\pc_unified_console.py')).Hash
    note='SRAM only with separate User Code read; no automatic host reconnect/mission start. Pi digit backend deployment and physical acceptance remain separate.'
}
try {
    $r17Event.sram_program='started'
    & $r17Cli --device GW5AT-60B --operation_index 2 --fsFile $r17Fs --cable-index 1 --frequency 2.5MHz *> $r17Log
    $r17Event.program_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -Raw -LiteralPath $r17Log) -notmatch 'Finished\.') { $r17Event.sram_program='failed';throw "SRAM download failed: $r17Log" }
    $r17Event.sram_program='passed'
    & $r17Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r17CodeLog
    $r17Event.readback_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -Raw -LiteralPath $r17CodeLog) -notmatch '0x534[Ee]3251') { $r17Event.independent_user_code_readback='failed';throw "R17 User Code mismatch: $r17CodeLog" }
    $r17Event.independent_user_code_readback='passed';$r17Event.observed_user_code='0x534E3251'
} catch { $r17Event.error=$_.Exception.Message;throw }
finally {
    $r17Event.finished_timestamp=(Get-Date -Format o)
    $r17Event | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -LiteralPath $r17EventFile
    Write-Output "Hardware event: $r17EventFile"
}
Write-Output 'R17 SRAM programmed; independent User Code0x534E3251 matched. Flash not written; Pi unchanged.'
