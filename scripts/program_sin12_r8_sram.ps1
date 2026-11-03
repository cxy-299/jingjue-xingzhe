param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r8Root = Split-Path -Parent $PSScriptRoot
$r8Archive = Join-Path $r8Root 'output\board\sin12_hdmi_r8_20261030_125627'
$r8Validation = Get-Content -LiteralPath (Join-Path $r8Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json
$r8Fs = Join-Path $r8Archive 'impl\pnr\sin12_hdmi_system.fs'
$r8ExpectedHash = '7F14E128B4992FE94B154C0E758D69DC3C853C45F9E38898B2C1780428E4D997'
if ($r8Validation.internal_sta_pass -ne $true -or
    $r8Validation.mapped_target.passed -ne $true -or $r8Validation.mapped_target.vectors -ne 2172 -or
    $r8Validation.usercode -ne '534E3248' -or $r8Validation.sources_verified -ne 56 -or
    $r8Validation.setup_violations -ne 0 -or $r8Validation.hold_violations -ne 0 -or
    $r8Validation.fmax_mhz.clk_50m -lt 50 -or $r8Validation.fmax_mhz.camera_pixel -lt 75 -or
    $r8Validation.fmax_mhz.camera_pclk -lt 75 -or
    $r8Validation.tables.'3.1.3.1 Recovery Paths Table[1]'.reported_paths -ne 12 -or
    $r8Validation.tables.'3.1.4.1 Removal Paths Table[1]'.reported_paths -ne 12 -or
    $r8Validation.tables.'3.1.3.2 Recovery Paths Table[2]'.reported_paths -lt 200 -or
    $r8Validation.tables.'3.1.4.2 Removal Paths Table[2]'.reported_paths -lt 200) {
    throw 'R8 internal timing evidence missing or inconsistent.'
}
foreach ($tableName in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]',
                         '3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r8Validation.tables.$tableName.minimum_slack_ns -le 0) { throw "Invalid reset timing: $tableName" }
}
$r8Manifest = Get-Content -LiteralPath (Join-Path $r8Archive 'sin12_hdmi_r8_build_sources.json') -Raw | ConvertFrom-Json
foreach ($entry in $r8Manifest.PSObject.Properties) {
    $r8Source = Join-Path (Join-Path $r8Archive 'sources') $entry.Name
    if ((Get-FileHash -LiteralPath $r8Source -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "R8 frozen source hash mismatch: $($entry.Name)"
    }
}
if ((Get-FileHash -LiteralPath $r8Fs -Algorithm SHA256).Hash -ne $r8ExpectedHash -or
    $r8Validation.fs_sha256 -ne $r8ExpectedHash) { throw 'R8 archived bitstream hash mismatch.' }
if ($r8Validation.mapped_tof.passed -ne $true -or $r8Validation.mapped_tof.checks -ne 91 -or $r8Validation.options.Replicate_Resources -ne $true) { throw 'R8 mapped ToF or replication evidence missing.' }
if ($ValidateFiles) { Write-Output 'R8 pinned archive/hash/internal timing verified; no hardware access.'; return }
$r8Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r8ActiveProgrammer = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }
if ($r8ActiveProgrammer) { throw 'Another programmer operation is active.' }
$r8Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r8Log = Join-Path $r8Root "output\board\sin12_r8_sram_${r8Stamp}.log"
$r8CodeLog = Join-Path $r8Root "output\board\sin12_r8_code_${r8Stamp}.log"
Write-Output 'Experimental SIN12 R8 SRAM only. MPW/external DVP and HDMI text OSD remain incomplete. No Flash operation.'
& $r8Cli --device GW5AT-60B --operation_index 2 --fsFile $r8Fs --cable-index 1 --frequency 2.5MHz *> $r8Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r8Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r8Log" }
& $r8Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r8CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r8CodeLog -Raw) -notmatch '0x534[Ee]3248') { throw "R8 independent readback mismatch: $r8CodeLog" }
$r8Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R8 experimental SRAM candidate'
    user_code = '0x534E3248'; map_id = '0x2613'; fs_sha256 = $r8ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r8Log, $r8CodeLog)
    note = 'Hardware event only; immutable build verification unchanged. No motor command sent.'
}
$r8Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r8Root "output\board\SIN12_R8_SRAM_EVENT_${r8Stamp}.json") -Encoding UTF8
Write-Output "SIN12 R8 SRAM independently verified: 0x534E3248; map 0x2613. Logs: $r8Log ; $r8CodeLog"
