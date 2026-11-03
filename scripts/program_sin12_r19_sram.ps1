#requires -Version 7.0
param([switch]$ValidateFiles,[switch]$UserRequestedSram,[switch]$ConsoleDisconnectedConfirmed)
$ErrorActionPreference='Stop'
if (-not $ValidateFiles -and (-not $UserRequestedSram -or -not $ConsoleDisconnectedConfirmed)) {
    throw 'Require an explicit SRAM request and a fresh user confirmation that the console is disconnected.'
}
$r19Root=Split-Path -Parent $PSScriptRoot
$r19Archive=Join-Path $r19Root 'output\board\sin12_hdmi_r19_20261102_032140'
$r19ExpectedManifest='7dbaccdc50e8f6f3b88460f2c2d24f745fc34c2b3c07bf25ca3aafd0be4ac934'
$r19ExpectedFs='5dc1ecceed69a21aa2b61d5cd5c498f3af3c5716114c5d0c2a4cf0683246810c'
$r19ExpectedVg='7c1433e0af59d250dbaaa55fc4d8ddc271b559c678de47e4befed569dd353a1a'
$r19InventoryFile=Join-Path $r19Archive 'SHA256.json'
if ((Get-FileHash -LiteralPath $r19InventoryFile -Algorithm SHA256).Hash -ne $r19ExpectedManifest) { throw 'Pinned manifest mismatch.' }
$r19Inventory=Get-Content -LiteralPath $r19InventoryFile -Raw | ConvertFrom-Json -AsHashtable
if ($r19Inventory.Count -ne 724) { throw 'Pinned archive content count mismatch.' }
if (@(Get-ChildItem -LiteralPath $r19Archive -Recurse -File).Count -ne 725) { throw 'Archive has unexpected missing/extra files.' }
foreach ($r19Entry in $r19Inventory.GetEnumerator()) {
    $r19Resolved=[IO.Path]::GetFullPath((Join-Path $r19Archive $r19Entry.Key))
    if (-not $r19Resolved.StartsWith($r19Archive + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Archive inventory path escapes snapshot.' }
    if ((Get-FileHash -LiteralPath (Join-Path $r19Archive $r19Entry.Key) -Algorithm SHA256).Hash -ne $r19Entry.Value) { throw "Archive mismatch: $($r19Entry.Key)" }
}
$r19Report=Get-Content -LiteralPath (Join-Path $r19Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json -AsHashtable
if ($r19Report.passed -ne $true -or $r19Report.user_code -ne '534E3253' -or
    $r19Report.revision -ne 'R19/K13/REV5_ENABLE15' -or $r19Report.counts_per_cell -ne 500 -or
    $r19Report.hardware_sources -ne 58 -or $r19Report.software_sources -ne 151 -or
    $r19Report.netlist_sha256 -ne $r19ExpectedVg -or $r19Report.fs_sha256 -ne $r19ExpectedFs) { throw 'Pinned R19 verification mismatch.' }
foreach ($r19Group in @('hardware','software')) {
    $r19Manifest=Get-Content -LiteralPath (Join-Path $r19Archive $(if ($r19Group -eq 'hardware') {'evidence\sin12_hdmi_r19_build_sources.json'} else {'evidence\sin12_hdmi_r19_software_sources.json'})) -Raw | ConvertFrom-Json -AsHashtable
    if ($r19Manifest.Count -ne $(if ($r19Group -eq 'hardware') {58} else {151})) { throw 'Source manifest count mismatch.' }
    foreach ($r19Entry in $r19Manifest.GetEnumerator()) {
        if ((Get-FileHash -LiteralPath (Join-Path (Join-Path $r19Archive 'sources') $r19Entry.Key) -Algorithm SHA256).Hash -ne $r19Entry.Value) { throw "Snapshot source mismatch: $($r19Entry.Key)" }
    }
}
$r19Sta=$r19Report.sta
if ($r19Sta.internal_sta_checks_pass -ne $true -or $r19Sta.setup_violations -ne 0 -or $r19Sta.hold_violations -ne 0 -or
    $r19Sta.checks.Count -ne 16 -or @($r19Sta.checks.Values | Where-Object {$_ -ne $true}).Count -ne 0 -or
    $r19Sta.fmax_mhz.clk_50m -lt 50 -or $r19Sta.fmax_mhz.camera_pclk -lt 75.002 -or $r19Sta.fmax_mhz.camera_pixel -lt 75) { throw 'STA acceptance mismatch.' }
foreach ($r19Table in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]')) {
    if ($r19Sta.tables[$r19Table].reported_paths -ne 12 -or $r19Sta.tables[$r19Table].endpoint_set.Count -ne 4 -or $r19Sta.tables[$r19Table].minimum_slack_ns -le 0) { throw 'OSER reset coverage mismatch.' }
}
foreach ($r19Table in @('3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r19Sta.tables[$r19Table].reported_paths -lt 200 -or $r19Sta.tables[$r19Table].minimum_slack_ns -le 0) { throw 'Global reset coverage mismatch.' }
}
if ($r19Report.constraint_audit.passed -ne $true -or $r19Report.constraint_audit.active_constraints.Count -ne 16 -or
    $r19Report.constraint_audit.pixel_async_false_path_endpoints.Count -ne 2 -or
    $r19Report.tests.passed -ne $true -or $r19Report.tests.isolated_gui_tests -ne 41 -or
    $r19Report.tests.unit_tests -ne 64 -or $r19Report.tests.task5_additional_gui_regressions -ne 2 -or
    $r19Report.tests.new_rtl_scenarios -ne 21 -or $r19Report.tests.production_width_regression_groups -ne 7 -or
    $r19Report.final_validation.passed -ne $true) { throw 'Constraint/software coverage mismatch.' }
foreach ($r19Kind in @('TOF','TARGET','NAV')) {
    if ($r19Report.mapped[$r19Kind].passed -ne $true -or $r19Report.mapped[$r19Kind].netlist_sha256 -ne $r19ExpectedVg -or
        $r19Report.mapped[$r19Kind].internal_forces -ne $false) { throw "Mapped report mismatch: $r19Kind" }
}
if ($r19Report.mapped.TOF.checks -ne 91 -or $r19Report.mapped.TARGET.vectors -ne 2172 -or
    $r19Report.mapped.NAV.primitive_count -ne 26775 -or
    'R19_MAPPED_NAV_LEFT_FORWARD_THREE_RIGHT_RESTORE_ORIGINAL_GOAL_PASS' -notin $r19Report.mapped.NAV.scenario_markers -or
    'R19_MAPPED_NAV_TWO_NEW_OBSTACLES_KEEP_GOAL_OCCUPIED_CELL_SAFE_STOP_PASS' -notin $r19Report.mapped.NAV.scenario_markers) { throw 'Mapped navigation coverage mismatch.' }
$r19Config=Get-Content -LiteralPath (Join-Path $r19Archive 'impl\sin12_hdmi_system_process_config.json') -Raw | ConvertFrom-Json -AsHashtable
$r19Device=Get-Content -LiteralPath (Join-Path $r19Archive 'impl\pnr\device.cfg') -Raw
if ($r19Config.Optimization_Goal -ne 'Timing' -or $r19Config.Place_Option -ne '0' -or $r19Config.Max_Fanout -ne 1000 -or
    $r19Config.Replicate_Resources -ne $true -or $r19Config.Route_Option -ne '2' -or $r19Config.Run_Timing_Driven -ne $true -or
    $r19Config.SSPI -ne $true -or $r19Config.JTAG -ne $false -or $r19Config.MSPI -ne $false -or
    $r19Device -notmatch '0x534E3253' -or $r19Device -notmatch 'set JTAG regular_io = false') { throw 'Device/process mismatch.' }
$r19Fs=Join-Path $r19Archive 'impl\pnr\sin12_hdmi_system.fs'
if ((Get-FileHash -LiteralPath $r19Fs -Algorithm SHA256).Hash -ne $r19ExpectedFs -or
    (Get-FileHash -LiteralPath (Join-Path $r19Archive 'impl\gwsynthesis\sin12_hdmi_system.vg') -Algorithm SHA256).Hash -ne $r19ExpectedVg) { throw 'Bitstream/netlist mismatch.' }
foreach ($r19Marker in @(
 'R19_MAPPED_NAV_FIXED_MAP_17_2_NEAR_RAY_PROJECTS17_4_PASS',
 'R19_MAPPED_NAV_SUBTICK_NEAR_LATCH_NO_REBOUND_PASS',
 'R19_MAPPED_NAV_OUTSIDE_RAY_INVALID_NO_FALSE_EDGE_CELL_PASS',
 'R19_MAPPED_NAV_WEST_NEGATIVE_CONSTANTS_FIVE_LEGS_ORIGINAL_GOAL_PASS',
 'R19_MAPPED_NAV_SOUTH_NEGATIVE_CONSTANTS_FIVE_LEGS_ORIGINAL_GOAL_PASS')) {
    if ($r19Marker -notin $r19Report.mapped.NAV.scenario_markers) { throw 'Mapped detour evidence incomplete.' }
}
if ($ValidateFiles) { Write-Output 'Pinned R19:724 archive files/58hardware151software,STA/constraint/three new mapped reports verified; no hardware access.';return }
if (Get-CimInstance Win32_Process | Where-Object {$_.Name -in @('programmer_cli.exe','gw_sh.exe')}) { throw 'Another programming/build operation is active.' }
$r19Cli='D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r19Stamp=Get-Date -Format yyyyMMdd_HHmmss_fff
$r19Scan=Join-Path $r19Root "output\board\sin12_r19_scan_$r19Stamp.log"
$r19Log=Join-Path $r19Root "output\board\sin12_r19_sram_$r19Stamp.log"
$r19Code=Join-Path $r19Root "output\board\sin12_r19_code_$r19Stamp.log"
$r19EventFile=Join-Path $r19Root "output\board\SIN12_R19_SRAM_EVENT_$r19Stamp.json"
$r19Event=[ordered]@{
    timestamp=(Get-Date -Format o);release='SIN12 R19 SRAM';expected_user_code='0x534E3253';firmware='K13';map_id='2613'
    archive=$r19Archive;archive_files_verified=724;fs_sha256=$r19ExpectedFs;netlist_sha256=$r19ExpectedVg
    user_explicitly_requested_sram=$true;console_disconnected_newly_confirmed_by_user=$true;console_confirmation='User: driving console disconnected, immediately before this operation';console_window_absent_on_readonly_inventory=$true
    physical_preparation_independently_verified=$false;sram_program='not_started';independent_user_code_readback='not_started'
    full_sram_byte_readback_performed=$false;flash_written_this_run=$false;motor_or_serial_command_sent_by_script=$false
    pi_modified=$false;vehicle_validated=$false;logs=@($r19Scan,$r19Log,$r19Code)
    programmer_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    note='SRAM only; separate User Code read; no automatic reconnect or task start.500counts/nominal100mm derived from user R12 scale,not newly ground calibrated.'
}
try {
    & $r19Cli --scan --cable-index 1 --frequency 2.5MHz *> $r19Scan
    $r19Event.scan_exit_code=$LASTEXITCODE
    $r19ScanText=Get-Content -LiteralPath $r19Scan -Raw
    if ($LASTEXITCODE -ne 0 -or $r19ScanText -notmatch '0x0001481B' -or $r19ScanText -notmatch '1 device\(s\) found') { throw 'Expected exactly one GW5AT target; SRAM not started.' }
    $r19Event.sram_program='started'
    & $r19Cli --device GW5AT-60B --operation_index 2 --fsFile $r19Fs --cable-index 1 --frequency 2.5MHz *> $r19Log
    $r19Event.program_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r19Log -Raw) -notmatch 'Finished\.') { $r19Event.sram_program='failed';throw 'R19 SRAM operation failed.' }
    $r19Event.sram_program='passed'
    & $r19Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r19Code
    $r19Event.readback_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r19Code -Raw) -notmatch '0x534[Ee]3253') { $r19Event.independent_user_code_readback='failed';throw 'R19 User Code mismatch.' }
    $r19Event.independent_user_code_readback='passed';$r19Event.observed_user_code='0x534E3253'
} catch {
    if ($r19Event.sram_program -eq 'started') { $r19Event.sram_program='failed' }
    $r19Event.error=$_.Exception.Message;throw
}
finally {
    $r19Event.finished_timestamp=(Get-Date -Format o)
    $r19Event | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $r19EventFile -Encoding utf8
    Write-Output "Hardware event: $r19EventFile"
}
Write-Output 'R19 SRAM programmed; independent User Code0x534E3253 matched. Flash not written; no automatic reconnect.'
