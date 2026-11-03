param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r10Root = Split-Path -Parent $PSScriptRoot
$r10Archive = Join-Path $r10Root 'output\board\sin12_hdmi_r10_20261030_161146'
$r10Validation = Get-Content -LiteralPath (Join-Path $r10Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json
$r10Fs = Join-Path $r10Archive 'impl\pnr\sin12_hdmi_system.fs'
$r10ExpectedHash = 'C84C9416E306F09B51E28DD0292BE6CE3F2C454E9136147580CF7B3878471279'
if ($r10Validation.internal_sta_pass -ne $true -or
    $r10Validation.mapped_target.passed -ne $true -or $r10Validation.mapped_target.vectors -ne 2172 -or
    $r10Validation.usercode -ne '534E324A' -or $r10Validation.sources_verified -ne 57 -or
    $r10Validation.setup_violations -ne 0 -or $r10Validation.hold_violations -ne 0 -or
    $r10Validation.fmax_mhz.clk_50m -lt 50 -or $r10Validation.fmax_mhz.camera_pixel -lt 75 -or
    $r10Validation.fmax_mhz.camera_pclk -lt 75 -or
    $r10Validation.tables.'3.1.3.1 Recovery Paths Table[1]'.reported_paths -ne 12 -or
    $r10Validation.tables.'3.1.4.1 Removal Paths Table[1]'.reported_paths -ne 12 -or
    $r10Validation.tables.'3.1.3.2 Recovery Paths Table[2]'.reported_paths -lt 200 -or
    $r10Validation.tables.'3.1.4.2 Removal Paths Table[2]'.reported_paths -lt 200) {
    throw 'R10 internal timing evidence missing or inconsistent.'
}
foreach ($tableName in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]',
                         '3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r10Validation.tables.$tableName.minimum_slack_ns -le 0) { throw "Invalid reset timing: $tableName" }
}
$r10Manifest = Get-Content -LiteralPath (Join-Path $r10Archive 'sin12_hdmi_r10_build_sources.json') -Raw | ConvertFrom-Json
foreach ($entry in $r10Manifest.PSObject.Properties) {
    $r10Source = Join-Path (Join-Path $r10Archive 'sources') $entry.Name
    if ((Get-FileHash -LiteralPath $r10Source -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "R10 frozen source hash mismatch: $($entry.Name)"
    }
}
if ((Get-FileHash -LiteralPath $r10Fs -Algorithm SHA256).Hash -ne $r10ExpectedHash -or
    $r10Validation.fs_sha256 -ne $r10ExpectedHash) { throw 'R10 archived bitstream hash mismatch.' }
if ($r10Validation.mapped_tof.passed -ne $true -or $r10Validation.mapped_tof.checks -ne 91 -or $r10Validation.options.Replicate_Resources -ne $true) { throw 'R10 mapped ToF or replication evidence missing.' }
if ($r10Validation.mapped_approach.passed -ne $true -or $r10Validation.mapped_approach.samples -ne 5000) { throw 'R10 actual mapped approach evidence missing.' }
if ($r10Validation.mapped_lateral.passed -ne $true) { throw 'R10 actual mapped lateral evidence missing.' }
if ($ValidateFiles) { Write-Output 'R10 pinned archive/hash/internal timing verified; no hardware access.'; return }
$r10Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r10ActiveProgrammer = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }
if ($r10ActiveProgrammer) { throw 'Another programmer operation is active.' }
$r10Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r10Log = Join-Path $r10Root "output\board\sin12_r10_sram_${r10Stamp}.log"
$r10CodeLog = Join-Path $r10Root "output\board\sin12_r10_code_${r10Stamp}.log"
Write-Output 'Experimental SIN12 R10 SRAM only. MPW/external DVP and HDMI text OSD remain incomplete. No Flash operation.'
& $r10Cli --device GW5AT-60B --operation_index 2 --fsFile $r10Fs --cable-index 1 --frequency 2.5MHz *> $r10Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r10Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r10Log" }
& $r10Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r10CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r10CodeLog -Raw) -notmatch '0x534[Ee]324A') { throw "R10 independent readback mismatch: $r10CodeLog" }
$r10Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R10 experimental SRAM candidate'
    user_code = '0x534E324A'; map_id = '0x2613'; fs_sha256 = $r10ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r10Log, $r10CodeLog)
    note = 'Hardware event only; immutable build verification unchanged. No motor command sent.'
}
$r10Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r10Root "output\board\SIN12_R10_SRAM_EVENT_${r10Stamp}.json") -Encoding UTF8
Write-Output "SIN12 R10 SRAM independently verified: 0x534E324A; map 0x2613. Logs: $r10Log ; $r10CodeLog"
