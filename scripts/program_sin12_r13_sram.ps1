param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Require fresh human confirmation: 12V OFF, wheels raised, stopped/disconnected COM9, FPGA powered and JTAG connected; SRAM only.'
}
$r13Root = Split-Path -Parent $PSScriptRoot
$r13Archive = Join-Path $r13Root 'output\board\sin12_hdmi_r13_20261030_221757'
$r13Report = Get-Content -LiteralPath (Join-Path $r13Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json
$r13Expected = '798df05e1ae0bb391882e22142c7a1bd3f0c53674783c54842c84255645c2d8a'
$r13Fs = Join-Path $r13Archive 'impl\pnr\sin12_hdmi_system.fs'
if ($r13Report.usercode -ne '534E324D' -or $r13Report.map_id -ne '2613' -or
    $r13Report.sources_verified -ne 57 -or -not $r13Report.internal_sta_checks_pass -or
    -not $r13Report.scoped_offline_validation_complete -or $r13Report.setup_violations -ne 0 -or
    $r13Report.hold_violations -ne 0 -or $r13Report.fs_sha256 -ne $r13Expected) { throw 'Pinned R13 evidence mismatch.' }
foreach ($c in $r13Report.checks.PSObject.Properties) { if ($c.Value -ne $true) { throw "Timing check failed: $($c.Name)" } }
foreach ($key in @('tof','target','approach','lateral','recovery')) {
    if ($r13Report.mapped.$key.passed -ne $true -or $r13Report.mapped.$key.netlist_sha256 -ne $r13Report.netlist_sha256) { throw "Mapped R13 evidence mismatch: $key" }
}
if ($r13Report.mapped.tof.checks -ne 91 -or $r13Report.mapped.target.vectors -ne 2172 -or
    $r13Report.mapped.approach.samples -ne 5000 -or $r13Report.mapped.recovery.primitive_count -ne 2722) { throw 'Mapped validation coverage mismatch.' }
if ($r13Report.fmax_mhz.clk_50m -lt 50 -or $r13Report.fmax_mhz.camera_pixel -lt 75 -or
    $r13Report.fmax_mhz.camera_pclk -lt 75 -or $r13Report.options.Replicate_Resources -ne $true -or
    $r13Report.options.Route_Option -ne 2 -or $r13Report.options.Run_Timing_Driven -ne $true) { throw 'R13 timing or PnR options mismatch.' }
foreach ($table in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]')) {
    if ($r13Report.tables.$table.reported_paths -ne 12 -or $r13Report.tables.$table.endpoint_set.Count -ne 4 -or
        $r13Report.tables.$table.minimum_slack_ns -le 0) { throw "R13 serializer reset timing invalid: $table" }
}
foreach ($table in @('3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r13Report.tables.$table.reported_paths -lt 200 -or $r13Report.tables.$table.minimum_slack_ns -le 0) { throw "R13 global reset timing invalid: $table" }
}
$r13Inventory = Get-Content -LiteralPath (Join-Path $r13Archive 'ARCHIVE_SHA256.json') -Raw | ConvertFrom-Json
foreach ($entry in $r13Inventory.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $r13Archive $entry.Name) -Algorithm SHA256).Hash -ne $entry.Value) { throw "R13 archived file hash mismatch: $($entry.Name)" }
}
if ((Get-FileHash -LiteralPath $r13Fs -Algorithm SHA256).Hash -ne $r13Expected) { throw 'R13 bitstream hash mismatch.' }
$r13Cfg = Get-Content -LiteralPath (Join-Path $r13Archive 'impl\pnr\device.cfg') -Raw
if ($r13Cfg -notmatch 'set SSPI regular_io = true' -or $r13Cfg -notmatch 'set JTAG regular_io = false' -or
    $r13Cfg -notmatch 'set MSPI regular_io = false' -or $r13Cfg -notmatch '0x534E324D') { throw 'R13 device configuration mismatch.' }
if ($ValidateFiles) { Write-Output 'Pinned R13 archive/hash/scoped mapped/internal timing checked. NO hardware access.'; return }
$r13Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
if (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }) { throw 'Another programmer operation is active.' }
$r13Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r13Log = Join-Path $r13Root "output\board\sin12_r13_sram_$r13Stamp.log"
$r13CodeLog = Join-Path $r13Root "output\board\sin12_r13_code_$r13Stamp.log"
Write-Output 'R13 experimental SRAM ONLY. No Flash or motor command. External DVP/MPW/PCLK/OSD gaps remain.'
& $r13Cli --device GW5AT-60B --operation_index 2 --fsFile $r13Fs --cable-index 1 --frequency 2.5MHz *> $r13Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r13Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r13Log" }
& $r13Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r13CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r13CodeLog -Raw) -notmatch '0x534[Ee]324[Dd]') { throw "R13 independent USER CODE readback failed: $r13CodeLog" }
$r13Event = [ordered]@{
    timestamp=(Get-Date -Format o); release='SIN12 R13 experimental SRAM'; user_code='0x534E324D'; map_id='0x2613'; fs_sha256=$r13Expected
    sram_program='passed'; independent_user_code_readback='passed'; full_sram_byte_readback_performed=$false
    user_confirmed_driver_12v_off=$true; user_confirmed_wheels_raised=$true; user_confirmed_stopped_com9_disconnected=$true
    static_accepted=$false; offground_accepted=$false; ground_accepted=$false; flash_written_this_run=$false; release_approved=$false
    flash_baseline='R12 / 0x534E324C'; logs=@($r13Log,$r13CodeLog)
    note='Hardware configuration event only; immutable offline archive unchanged; no serial/motor/Pi action. Power cycling FPGA reloads R12 Flash.'
}
$r13EventPath = Join-Path $r13Root "output\board\SIN12_R13_SRAM_EVENT_$r13Stamp.json"
$r13Event | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $r13EventPath -Encoding UTF8
Write-Output "R13 SRAM programmed and independently USER CODE verified 0x534E324D. Flash remains R12. Event: $r13EventPath"
