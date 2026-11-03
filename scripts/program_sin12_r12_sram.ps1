param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r12Root = Split-Path -Parent $PSScriptRoot
$r12Archive = Join-Path $r12Root 'output\board\sin12_hdmi_r12_20261030_180232'
$r12Validation = Get-Content -LiteralPath (Join-Path $r12Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json
$r12Fs = Join-Path $r12Archive 'impl\pnr\sin12_hdmi_system.fs'
$r12ExpectedHash = '6E95B71A7D1D4B12E1AE255FF54EB86BBD15B857110033744165E8D1DD741DA0'
if ($r12Validation.internal_sta_pass -ne $true -or
    $r12Validation.mapped_target.passed -ne $true -or $r12Validation.mapped_target.vectors -ne 2172 -or
    $r12Validation.usercode -ne '534E324C' -or $r12Validation.sources_verified -ne 57 -or
    $r12Validation.setup_violations -ne 0 -or $r12Validation.hold_violations -ne 0 -or
    $r12Validation.fmax_mhz.clk_50m -lt 50 -or $r12Validation.fmax_mhz.camera_pixel -lt 75 -or
    $r12Validation.fmax_mhz.camera_pclk -lt 75 -or
    $r12Validation.tables.'3.1.3.1 Recovery Paths Table[1]'.reported_paths -ne 12 -or
    $r12Validation.tables.'3.1.4.1 Removal Paths Table[1]'.reported_paths -ne 12 -or
    $r12Validation.tables.'3.1.3.2 Recovery Paths Table[2]'.reported_paths -lt 200 -or
    $r12Validation.tables.'3.1.4.2 Removal Paths Table[2]'.reported_paths -lt 200) {
    throw 'R12 internal timing evidence missing or inconsistent.'
}
foreach ($tableName in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]',
                         '3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r12Validation.tables.$tableName.minimum_slack_ns -le 0) { throw "Invalid reset timing: $tableName" }
}
$r12Manifest = Get-Content -LiteralPath (Join-Path $r12Archive 'sin12_hdmi_r12_build_sources.json') -Raw | ConvertFrom-Json
foreach ($entry in $r12Manifest.PSObject.Properties) {
    $r12Source = Join-Path (Join-Path $r12Archive 'sources') $entry.Name
    if ((Get-FileHash -LiteralPath $r12Source -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "R12 frozen source hash mismatch: $($entry.Name)"
    }
}
if ((Get-FileHash -LiteralPath $r12Fs -Algorithm SHA256).Hash -ne $r12ExpectedHash -or
    $r12Validation.fs_sha256 -ne $r12ExpectedHash) { throw 'R12 archived bitstream hash mismatch.' }
if ($r12Validation.mapped_tof.passed -ne $true -or $r12Validation.mapped_tof.checks -ne 91 -or $r12Validation.options.Replicate_Resources -ne $true) { throw 'R12 mapped ToF or replication evidence missing.' }
if ($r12Validation.mapped_approach.passed -ne $true -or $r12Validation.mapped_approach.samples -ne 5000) { throw 'R12 actual mapped approach evidence missing.' }
if ($r12Validation.mapped_lateral.passed -ne $true) { throw 'R12 actual mapped lateral evidence missing.' }
if ($ValidateFiles) { Write-Output 'R12 pinned archive/hash/internal timing verified; no hardware access.'; return }
$r12Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r12ActiveProgrammer = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }
if ($r12ActiveProgrammer) { throw 'Another programmer operation is active.' }
$r12Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r12Log = Join-Path $r12Root "output\board\sin12_r12_sram_${r12Stamp}.log"
$r12CodeLog = Join-Path $r12Root "output\board\sin12_r12_code_${r12Stamp}.log"
Write-Output 'Experimental SIN12 R12 SRAM only. MPW/external DVP and HDMI text OSD remain incomplete. No Flash operation.'
& $r12Cli --device GW5AT-60B --operation_index 2 --fsFile $r12Fs --cable-index 1 --frequency 2.5MHz *> $r12Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r12Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r12Log" }
& $r12Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r12CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r12CodeLog -Raw) -notmatch '0x534[Ee]324C') { throw "R12 independent readback mismatch: $r12CodeLog" }
$r12Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R12 experimental SRAM candidate'
    user_code = '0x534E324C'; map_id = '0x2613'; fs_sha256 = $r12ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r12Log, $r12CodeLog)
    note = 'Hardware event only; immutable build verification unchanged. No motor command sent.'
}
$r12Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r12Root "output\board\SIN12_R12_SRAM_EVENT_${r12Stamp}.json") -Encoding UTF8
Write-Output "SIN12 R12 SRAM independently verified: 0x534E324C; map 0x2613. Logs: $r12Log ; $r12CodeLog"
