#requires -Version 7.0
param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Require fresh confirmation: S, COM9 disconnected, driver12V OFF, wheels raised, FPGA powered and JTAG connected. SRAM only.'
}
$r16Root = Split-Path -Parent $PSScriptRoot
$r16Archive = Join-Path $r16Root 'output\board\sin12_hdmi_r16_20261101_124306'
$r16Report = Get-Content -Raw -LiteralPath (Join-Path $r16Archive 'BUILD_VERIFICATION.json') | ConvertFrom-Json
$r16Expected = 'f0a46afd38573c970c87b8e4597f467eeba47c2ec2c9a1e7f3eede4764cf927e'
$r16NetHash = '3c377e6eebc840823255587840ac565facf321b7e976aa6fb1c475d89e5a2375'
$r16Fs = Join-Path $r16Archive 'impl\pnr\sin12_hdmi_system.fs'
if ($r16Report.usercode -ne '534E3250' -or $r16Report.firmware -ne 'K10' -or
    $r16Report.map_id -ne '2613' -or $r16Report.hardware_source_count -ne 57 -or
    $r16Report.software_validation_source_count -ne 73 -or
    $r16Report.internal_sta_checks_pass -ne $true -or $r16Report.setup_violations -ne 0 -or
    $r16Report.hold_violations -ne 0 -or $r16Report.fs_sha256 -ne $r16Expected -or
    $r16Report.netlist_sha256 -ne $r16NetHash -or $r16Report.constraint_audit.passed -ne $true) {
    throw 'Pinned R16 evidence mismatch.'
}
foreach ($r16Key in @('tof','target','recovery','settle','nav')) {
    if ($r16Report.mapped.$r16Key.passed -ne $true -or
        $r16Report.mapped.$r16Key.netlist_sha256 -ne $r16NetHash -or
        $r16Report.mapped.$r16Key.internal_forces -ne $false) { throw "Mapped evidence mismatch: $r16Key" }
}
if ($r16Report.mapped.tof.checks -ne 91 -or $r16Report.mapped.target.vectors -ne 2172 -or
    $r16Report.mapped.recovery.primitive_count -ne 3242 -or $r16Report.mapped.settle.primitive_count -ne 3242 -or
    $r16Report.mapped.nav.primitive_count -ne 24010 -or $r16Report.fmax_mhz.clk_50m -lt 50 -or
    $r16Report.fmax_mhz.camera_pclk -lt 75.002 -or $r16Report.fmax_mhz.camera_pixel -lt 75 -or
    $r16Report.forward_counts_per_100mm -ne 333 -or $r16Report.ground_distance_calibrated -ne $false) {
    throw 'R16 coverage, timing or provisional odometry mismatch.'
}
foreach ($r16Table in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]')) {
    if ($r16Report.tables.$r16Table.reported_paths -ne 12 -or $r16Report.tables.$r16Table.endpoint_set.Count -ne 4 -or
        $r16Report.tables.$r16Table.minimum_slack_ns -le 0) { throw "Serializer timing invalid: $r16Table" }
}
foreach ($r16Table in @('3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r16Report.tables.$r16Table.reported_paths -lt 200 -or $r16Report.tables.$r16Table.minimum_slack_ns -le 0) {
        throw "Global reset timing invalid: $r16Table"
    }
}
$r16Inventory = Get-Content -Raw -LiteralPath (Join-Path $r16Archive 'ARCHIVE_SHA256.json') | ConvertFrom-Json
foreach ($r16Entry in $r16Inventory.PSObject.Properties) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $r16Archive $r16Entry.Name)).Hash -ne $r16Entry.Value) {
        throw "Archive hash mismatch: $($r16Entry.Name)"
    }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $r16Fs).Hash -ne $r16Expected -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $r16Archive 'impl\gwsynthesis\sin12_hdmi_system.vg')).Hash -ne $r16NetHash) {
    throw 'Pinned R16 bitstream/netlist mismatch.'
}
$r16Cfg = Get-Content -Raw -LiteralPath (Join-Path $r16Archive 'impl\pnr\device.cfg')
$r16Process = Get-Content -Raw -LiteralPath (Join-Path $r16Archive 'impl\sin12_hdmi_system_process_config.json') | ConvertFrom-Json -AsHashtable
if ($r16Cfg -notmatch 'set SSPI regular_io = true' -or $r16Cfg -notmatch 'set JTAG regular_io = false' -or
    $r16Cfg -notmatch 'set MSPI regular_io = false' -or $r16Cfg -notmatch '0x534E3250' -or
    $r16Process.Replicate_Resources -ne $true -or $r16Process.Route_Option -ne '2' -or
    $r16Process.Run_Timing_Driven -ne $true -or $r16Process.SSPI -ne $true -or
    $r16Process.JTAG -ne $false -or $r16Process.MSPI -ne $false) { throw 'R16 device/process configuration mismatch.' }
if ($ValidateFiles) { Write-Output 'Pinned R16 archive: all hashes/internal timing/five scoped mapped reports checked; no hardware access.'; return }
$r16Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
if (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }) { throw 'Another programmer operation is active.' }
$r16Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r16Log = Join-Path $r16Root "output\board\sin12_r16_sram_$r16Stamp.log"
$r16CodeLog = Join-Path $r16Root "output\board\sin12_r16_code_$r16Stamp.log"
$r16EventFile = Join-Path $r16Root "output\board\SIN12_R16_SRAM_EVENT_$r16Stamp.json"
$r16Event = [ordered]@{
    timestamp=(Get-Date -Format o); release='SIN12 R16 experimental SRAM'; expected_user_code='0x534E3250'
    map_id='0x2613'; fs_sha256=$r16Expected; archive=$r16Archive
    sram_program='not_started'; independent_user_code_readback='not_started'; full_sram_byte_readback_performed=$false
    user_confirmed_driver_12v_off=$true; user_confirmed_wheels_raised=$true
    user_confirmed_stopped_and_com9_disconnected=$true; user_confirmed_fpga_powered_and_jtag_connected=$true
    flash_written_this_run=$false; motor_or_serial_command_sent=$false; pi_modified=$false
    static_accepted=$false; offground_accepted=$false; ground_accepted=$false; release_approved=$false
    logs=@($r16Log,$r16CodeLog); programmer_script_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash
    note='SRAM download and separate USER CODE read only; not full SRAM byte verification or vehicle acceptance. Flash unchanged. 333 counts/100mm provisional; setup margin39ps.'
}
try {
    Write-Output 'R16 SRAM ONLY; no Flash or motor command. 39ps setup margin/external timing limitations remain.'
    $r16Event.sram_program='started'
    & $r16Cli --device GW5AT-60B --operation_index 2 --fsFile $r16Fs --cable-index 1 --frequency 2.5MHz *> $r16Log
    $r16Event.program_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -Raw -LiteralPath $r16Log) -notmatch 'Finished\.') {
        $r16Event.sram_program='failed'; throw "SRAM download failed: $r16Log"
    }
    $r16Event.sram_program='passed'
    & $r16Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r16CodeLog
    $r16Event.readback_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -Raw -LiteralPath $r16CodeLog) -notmatch '0x534[Ee]3250') {
        $r16Event.independent_user_code_readback='failed'; throw "Independent R16 USER CODE mismatch: $r16CodeLog"
    }
    $r16Event.independent_user_code_readback='passed'; $r16Event.observed_user_code='0x534E3250'
} catch {
    $r16Event.error=$_.Exception.Message; throw
} finally {
    $r16Event.finished_timestamp=(Get-Date -Format o)
    $r16Event | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 -LiteralPath $r16EventFile
    Write-Output "Hardware event: $r16EventFile"
}
Write-Output "R16 SRAM programmed; independent USER CODE 0x534E3250 matched. Flash NOT written. Logs: $r16Log ; $r16CodeLog"
