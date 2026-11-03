param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Require fresh confirmation: S, COM9 disconnected, driver12V OFF, wheels raised, FPGA powered and JTAG connected. SRAM only.'
}
$r15Root = Split-Path -Parent $PSScriptRoot
$r15Archive = Join-Path $r15Root 'output\board\sin12_hdmi_r15_20261031_222655'
$r15Report = Get-Content -Raw -LiteralPath (Join-Path $r15Archive 'BUILD_VERIFICATION.json') | ConvertFrom-Json
$r15Expected = '015718edf6ec6d2e2785c37fb9dde529409359f2ed852aea9045a0ba19940eff'
$r15Fs = Join-Path $r15Archive 'impl\pnr\sin12_hdmi_system.fs'
if ($r15Report.usercode -ne '534E324F' -or $r15Report.firmware -ne 'K0F' -or
    $r15Report.map_id -ne '2613' -or $r15Report.hardware_source_count -ne 57 -or
    $r15Report.internal_sta_checks_pass -ne $true -or $r15Report.setup_violations -ne 0 -or
    $r15Report.hold_violations -ne 0 -or $r15Report.fs_sha256 -ne $r15Expected) { throw 'Pinned R15 evidence mismatch.' }
foreach ($r15Key in @('tof','target','recovery_search')) {
    if ($r15Report.mapped.$r15Key.passed -ne $true -or
        $r15Report.mapped.$r15Key.netlist_sha256 -ne $r15Report.netlist_sha256) { throw "Mapped evidence mismatch: $r15Key" }
}
if ($r15Report.mapped.tof.checks -ne 91 -or $r15Report.mapped.target.vectors -ne 2172 -or
    $r15Report.mapped.recovery_search.primitive_count -ne 3164 -or
    $r15Report.fmax_mhz.clk_50m -lt 50 -or $r15Report.fmax_mhz.camera_pclk -lt 75 -or
    $r15Report.fmax_mhz.camera_pixel -lt 75 -or
    $r15Report.manual_audit.replicate_resources -ne $true -or
    $r15Report.manual_audit.route_option -ne 2 -or $r15Report.manual_audit.timing_driven -ne $true) { throw 'R15 coverage or timing/options mismatch.' }
foreach ($r15Table in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]')) {
    if ($r15Report.tables.$r15Table.reported_paths -ne 12 -or
        $r15Report.tables.$r15Table.endpoint_set.Count -ne 4 -or
        $r15Report.tables.$r15Table.minimum_slack_ns -le 0) { throw "Serializer timing invalid: $r15Table" }
}
foreach ($r15Table in @('3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r15Report.tables.$r15Table.reported_paths -lt 200 -or
        $r15Report.tables.$r15Table.minimum_slack_ns -le 0) { throw "Global reset timing invalid: $r15Table" }
}
$r15Inventory = Get-Content -Raw -LiteralPath (Join-Path $r15Archive 'ARCHIVE_SHA256.json') | ConvertFrom-Json
foreach ($r15Entry in $r15Inventory.PSObject.Properties) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $r15Archive $r15Entry.Name)).Hash -ne $r15Entry.Value) {
        throw "Archive hash mismatch: $($r15Entry.Name)"
    }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $r15Fs).Hash -ne $r15Expected) { throw 'Pinned bitstream mismatch.' }
$r15Cfg = Get-Content -Raw -LiteralPath (Join-Path $r15Archive 'impl\pnr\device.cfg')
if ($r15Cfg -notmatch 'set SSPI regular_io = true' -or $r15Cfg -notmatch 'set JTAG regular_io = false' -or
    $r15Cfg -notmatch 'set MSPI regular_io = false' -or $r15Cfg -notmatch '0x534E324F') { throw 'R15 device configuration mismatch.' }
if ($ValidateFiles) { Write-Output 'Pinned R15 archive: all hashes/internal timing/scoped mapped evidence checked; no hardware access.'; return }
$r15Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
if (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }) { throw 'Another programmer operation is active.' }
$r15Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r15Log = Join-Path $r15Root "output\board\sin12_r15_sram_$r15Stamp.log"
$r15CodeLog = Join-Path $r15Root "output\board\sin12_r15_code_$r15Stamp.log"
$r15EventFile = Join-Path $r15Root "output\board\SIN12_R15_SRAM_EVENT_$r15Stamp.json"
$r15Event = [ordered]@{
    timestamp=(Get-Date -Format o); release='SIN12 R15 experimental SRAM'; expected_user_code='0x534E324F'
    map_id='0x2613'; fs_sha256=$r15Expected; archive=$r15Archive
    sram_program='not_started'; independent_user_code_readback='not_started'; full_sram_byte_readback_performed=$false
    user_confirmed_driver_12v_off=$true; user_confirmed_wheels_raised=$true
    user_confirmed_stopped_and_com9_disconnected=$true; user_confirmed_fpga_powered_and_jtag_connected=$true
    flash_written_this_run=$false; motor_or_serial_command_sent=$false; pi_modified=$false
    static_accepted=$false; offground_accepted=$false; ground_accepted=$false; release_approved=$false
    logs=@($r15Log,$r15CodeLog); programmer_script_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash
    note='SRAM download and separate USER CODE read only; not full memory verification or vehicle acceptance. Flash unchanged.'
}
Write-Output 'R15 SRAM ONLY; no Flash or motor command. 65ps setup margin and existing external timing/MPW/OSD limitations remain.'
try {
    $r15Event.sram_program='started'
    & $r15Cli --device GW5AT-60B --operation_index 2 --fsFile $r15Fs --cable-index 1 --frequency 2.5MHz *> $r15Log
    $r15Event.program_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -Raw -LiteralPath $r15Log) -notmatch 'Finished\.') {
        $r15Event.sram_program='failed'; throw "SRAM download failed: $r15Log"
    }
    $r15Event.sram_program='passed'
    & $r15Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r15CodeLog
    $r15Event.readback_exit_code=$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -or (Get-Content -Raw -LiteralPath $r15CodeLog) -notmatch '0x534[Ee]324[Ff]') {
        $r15Event.independent_user_code_readback='failed'; throw "Independent R15 USER CODE mismatch: $r15CodeLog"
    }
    $r15Event.independent_user_code_readback='passed'
    $r15Event.observed_user_code='0x534E324F'
} catch {
    $r15Event.error=$_.Exception.Message
    throw
} finally {
    $r15Event.finished_timestamp=(Get-Date -Format o)
    $r15Event | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 -LiteralPath $r15EventFile
    Write-Output "Hardware event: $r15EventFile"
}
Write-Output "R15 SRAM programmed; independent USER CODE 0x534E324F matched. Flash NOT written. Logs: $r15Log ; $r15CodeLog"
