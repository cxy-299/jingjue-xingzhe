#requires -Version 7.0
param([switch]$ValidateFiles,[switch]$UserRequestedSram,[switch]$ConsoleDisconnectedObserved)
$ErrorActionPreference='Stop'
if (-not $ValidateFiles -and (-not $UserRequestedSram -or -not $ConsoleDisconnectedObserved)) {
    throw 'Require an explicit SRAM request and a newly observed disconnected console.'
}
$r18Root=Split-Path -Parent $PSScriptRoot
$r18Archive=Join-Path $r18Root 'output\board\sin12_hdmi_r18_20261101_203535'
$r18ExpectedManifest='3fe04dc01b482fcfb3906dc18035cc6facf1e3014ab8458e6184473ad15c4fe1'
$r18ExpectedFs='fa82712ef797b983b1d73557bd48ecd3a0e0319f42c7b797fc79a885eb7d9855'
$r18ExpectedVg='f1250492f7694d6a760f45a1b9f1e8443a5f38652d20154565a35d7a0ebe6018'
$r18InventoryFile=Join-Path $r18Archive 'SHA256.json'
if ((Get-FileHash -LiteralPath $r18InventoryFile -Algorithm SHA256).Hash -ne $r18ExpectedManifest) { throw 'Pinned manifest mismatch.' }
$r18Inventory=Get-Content -LiteralPath $r18InventoryFile -Raw | ConvertFrom-Json -AsHashtable
if ($r18Inventory.Count -ne 284) { throw 'Pinned archive content count mismatch.' }
foreach ($r18Entry in $r18Inventory.GetEnumerator()) {
    if ((Get-FileHash -LiteralPath (Join-Path $r18Archive $r18Entry.Key) -Algorithm SHA256).Hash -ne $r18Entry.Value) { throw "Archive mismatch: $($r18Entry.Key)" }
}
$r18Report=Get-Content -LiteralPath (Join-Path $r18Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json -AsHashtable
if ($r18Report.passed -ne $true -or $r18Report.user_code -ne '534E3252' -or
    $r18Report.revision -ne 'R18/K12/REV5_ENABLE14' -or $r18Report.counts_per_cell -ne 500 -or
    $r18Report.hardware_sources -ne 58 -or $r18Report.software_sources -ne 119 -or
    $r18Report.netlist_sha256 -ne $r18ExpectedVg -or $r18Report.fs_sha256 -ne $r18ExpectedFs) { throw 'Pinned R18 verification mismatch.' }
foreach ($r18Group in @('hardware','software')) {
    $r18Manifest=Get-Content -LiteralPath (Join-Path $r18Archive $(if ($r18Group -eq 'hardware') {'evidence\sin12_hdmi_r18_build_sources.json'} else {'evidence\sin12_hdmi_r18_software_sources.json'})) -Raw | ConvertFrom-Json -AsHashtable
    if ($r18Manifest.Count -ne $(if ($r18Group -eq 'hardware') {58} else {119})) { throw 'Source manifest count mismatch.' }
    foreach ($r18Entry in $r18Manifest.GetEnumerator()) {
        if ((Get-FileHash -LiteralPath (Join-Path (Join-Path $r18Archive 'sources') $r18Entry.Key) -Algorithm SHA256).Hash -ne $r18Entry.Value) { throw "Snapshot source mismatch: $($r18Entry.Key)" }
    }
}
$r18Sta=$r18Report.sta
if ($r18Sta.internal_sta_checks_pass -ne $true -or $r18Sta.setup_violations -ne 0 -or $r18Sta.hold_violations -ne 0 -or
    $r18Sta.checks.Count -ne 16 -or @($r18Sta.checks.Values | Where-Object {$_ -ne $true}).Count -ne 0 -or
    $r18Sta.fmax_mhz.clk_50m -lt 50 -or $r18Sta.fmax_mhz.camera_pclk -lt 75.002 -or $r18Sta.fmax_mhz.camera_pixel -lt 75) { throw 'STA acceptance mismatch.' }
foreach ($r18Table in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]')) {
    if ($r18Sta.tables[$r18Table].reported_paths -ne 12 -or $r18Sta.tables[$r18Table].endpoint_set.Count -ne 4 -or $r18Sta.tables[$r18Table].minimum_slack_ns -le 0) { throw 'OSER reset coverage mismatch.' }
}
foreach ($r18Table in @('3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r18Sta.tables[$r18Table].reported_paths -lt 200 -or $r18Sta.tables[$r18Table].minimum_slack_ns -le 0) { throw 'Global reset coverage mismatch.' }
}
if ($r18Report.constraint_audit.passed -ne $true -or $r18Report.constraint_audit.active_constraints.Count -ne 16 -or
    $r18Report.constraint_audit.pixel_async_false_path_endpoints.Count -ne 2 -or
    $r18Report.gui_tests -ne 32 -or $r18Report.contract_tests -ne 51) { throw 'Constraint/software coverage mismatch.' }
foreach ($r18Kind in @('TOF','TARGET','NAV')) {
    if ($r18Report.mapped[$r18Kind].passed -ne $true -or $r18Report.mapped[$r18Kind].netlist_sha256 -ne $r18ExpectedVg -or
        $r18Report.mapped[$r18Kind].internal_forces -ne $false) { throw "Mapped report mismatch: $r18Kind" }
}
if ($r18Report.mapped.TOF.checks -ne 91 -or $r18Report.mapped.TARGET.vectors -ne 2172 -or
    $r18Report.mapped.NAV.primitive_count -ne 25924 -or
    'R18_MAPPED_NAV_LEFT_FORWARD_RIGHT_RESTORE_ORIGINAL_GOAL_PASS' -notin $r18Report.mapped.NAV.scenario_markers -or
    'R18_MAPPED_NAV_TWO_NEW_LOCAL_OBSTACLES_LEFT_DETOUR_ORIGINAL_GOAL_PASS' -notin $r18Report.mapped.NAV.scenario_markers) { throw 'Mapped navigation coverage mismatch.' }
$r18Config=Get-Content -LiteralPath (Join-Path $r18Archive 'impl\sin12_hdmi_system_process_config.json') -Raw | ConvertFrom-Json -AsHashtable
$r18Device=Get-Content -LiteralPath (Join-Path $r18Archive 'impl\pnr\device.cfg') -Raw
if ($r18Config.Optimization_Goal -ne 'Timing' -or $r18Config.Place_Option -ne '1' -or $r18Config.Max_Fanout -ne 1000 -or
    $r18Config.Replicate_Resources -ne $true -or $r18Config.Route_Option -ne '2' -or $r18Config.Run_Timing_Driven -ne $true -or
    $r18Config.SSPI -ne $true -or $r18Config.JTAG -ne $false -or $r18Config.MSPI -ne $false -or
    $r18Device -notmatch '0x534E3252' -or $r18Device -notmatch 'set JTAG regular_io = false') { throw 'Device/process mismatch.' }
$r18Fs=Join-Path $r18Archive 'impl\pnr\sin12_hdmi_system.fs'
if ((Get-FileHash -LiteralPath $r18Fs -Algorithm SHA256).Hash -ne $r18ExpectedFs -or
    (Get-FileHash -LiteralPath (Join-Path $r18Archive 'impl\gwsynthesis\sin12_hdmi_system.vg') -Algorithm SHA256).Hash -ne $r18ExpectedVg) { throw 'Bitstream/netlist mismatch.' }
if ($ValidateFiles) { Write-Output 'Pinned R18:284 archive files/58hardware119software,STA/constraint/three new mapped reports verified; no hardware access.';return }
if (Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'programmer_cli.exe'}) { throw 'Another programmer operation is active.' }
$r18Cli='D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r18Stamp=Get-Date -Format yyyyMMdd_HHmmss_fff
$r18Scan=Join-Path $r18Root "output\board\sin12_r18_scan_$r18Stamp.log"
$r18Log=Join-Path $r18Root "output\board\sin12_r18_sram_$r18Stamp.log"
$r18Code=Join-Path $r18Root "output\board\sin12_r18_code_$r18Stamp.log"
$r18EventFile=Join-Path $r18Root "output\board\SIN12_R18_SRAM_EVENT_$r18Stamp.json"
$r18Event=[ordered]@{
    timestamp=(Get-Date -Format o);release='SIN12 R18 SRAM';expected_user_code='0x534E3252';firmware='K12';map_id='2613'
    archive=$r18Archive;archive_files_verified=284;fs_sha256=$r18ExpectedFs;netlist_sha256=$r18ExpectedVg
    user_explicitly_requested_sram=$true;console_disconnected_newly_observed=$true
    physical_preparation_independently_verified=$false;sram_program='not_started';independent_user_code_readback='not_started'
    full_sram_byte_readback_performed=$false;flash_written_this_run=$false;motor_or_serial_command_sent_by_script=$false
    pi_modified=$false;vehicle_validated=$false;logs=@($r18Scan,$r18Log,$r18Code)
    programmer_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    note='SRAM only; separate User Code read; no automatic reconnect or task start.500counts/nominal100mm derived from user R12 scale,not newly ground calibrated.'
}
try {
    & $r18Cli --scan --cable-index 1 --frequency 2.5MHz *> $r18Scan
    $r18Event.scan_exit_code=$LASTEXITCODE
    $r18ScanText=Get-Content -LiteralPath $r18Scan -Raw
    if ($LASTEXITCODE -ne 0 -or $r18ScanText -notmatch '0x0001481B' -or $r18ScanText -notmatch '1 device\(s\) found') { throw 'Expected exactly one GW5AT target; SRAM not started.' }
    $r18Event.sram_program='started'
    & $r18Cli --device GW5AT-60B --operation_index 2 --fsFile $r18Fs --cable-index 1 --frequency 2.5MHz *> $r18Log
    $r18Event.program_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r18Log -Raw) -notmatch 'Finished\.') { $r18Event.sram_program='failed';throw 'R18 SRAM operation failed.' }
    $r18Event.sram_program='passed'
    & $r18Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r18Code
    $r18Event.readback_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r18Code -Raw) -notmatch '0x534[Ee]3252') { $r18Event.independent_user_code_readback='failed';throw 'R18 User Code mismatch.' }
    $r18Event.independent_user_code_readback='passed';$r18Event.observed_user_code='0x534E3252'
} catch { $r18Event.error=$_.Exception.Message;throw }
finally {
    $r18Event.finished_timestamp=(Get-Date -Format o)
    $r18Event | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $r18EventFile -Encoding utf8
    Write-Output "Hardware event: $r18EventFile"
}
Write-Output 'R18 SRAM programmed; independent User Code0x534E3252 matched. Flash not written; no automatic reconnect.'
