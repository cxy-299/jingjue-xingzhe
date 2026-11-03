param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r11Root = Split-Path -Parent $PSScriptRoot
$r11Archive = Join-Path $r11Root 'output\board\sin12_hdmi_r11_20261030_171959'
$r11Validation = Get-Content -LiteralPath (Join-Path $r11Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json
$r11Fs = Join-Path $r11Archive 'impl\pnr\sin12_hdmi_system.fs'
$r11ExpectedHash = '163FF85A549498705C1B0DA80D28F3CD70C6CAC2B051A3335904EEA87B3E0DF3'
if ($r11Validation.internal_sta_pass -ne $true -or
    $r11Validation.mapped_target.passed -ne $true -or $r11Validation.mapped_target.vectors -ne 2172 -or
    $r11Validation.usercode -ne '534E324B' -or $r11Validation.sources_verified -ne 57 -or
    $r11Validation.setup_violations -ne 0 -or $r11Validation.hold_violations -ne 0 -or
    $r11Validation.fmax_mhz.clk_50m -lt 50 -or $r11Validation.fmax_mhz.camera_pixel -lt 75 -or
    $r11Validation.fmax_mhz.camera_pclk -lt 75 -or
    $r11Validation.tables.'3.1.3.1 Recovery Paths Table[1]'.reported_paths -ne 12 -or
    $r11Validation.tables.'3.1.4.1 Removal Paths Table[1]'.reported_paths -ne 12 -or
    $r11Validation.tables.'3.1.3.2 Recovery Paths Table[2]'.reported_paths -lt 200 -or
    $r11Validation.tables.'3.1.4.2 Removal Paths Table[2]'.reported_paths -lt 200) {
    throw 'R11 internal timing evidence missing or inconsistent.'
}
foreach ($tableName in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]',
                         '3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r11Validation.tables.$tableName.minimum_slack_ns -le 0) { throw "Invalid reset timing: $tableName" }
}
$r11Manifest = Get-Content -LiteralPath (Join-Path $r11Archive 'sin12_hdmi_r11_build_sources.json') -Raw | ConvertFrom-Json
foreach ($entry in $r11Manifest.PSObject.Properties) {
    $r11Source = Join-Path (Join-Path $r11Archive 'sources') $entry.Name
    if ((Get-FileHash -LiteralPath $r11Source -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "R11 frozen source hash mismatch: $($entry.Name)"
    }
}
if ((Get-FileHash -LiteralPath $r11Fs -Algorithm SHA256).Hash -ne $r11ExpectedHash -or
    $r11Validation.fs_sha256 -ne $r11ExpectedHash) { throw 'R11 archived bitstream hash mismatch.' }
if ($r11Validation.mapped_tof.passed -ne $true -or $r11Validation.mapped_tof.checks -ne 91 -or $r11Validation.options.Replicate_Resources -ne $true) { throw 'R11 mapped ToF or replication evidence missing.' }
if ($r11Validation.mapped_approach.passed -ne $true -or $r11Validation.mapped_approach.samples -ne 5000) { throw 'R11 actual mapped approach evidence missing.' }
if ($r11Validation.mapped_lateral.passed -ne $true) { throw 'R11 actual mapped lateral evidence missing.' }
if ($ValidateFiles) { Write-Output 'R11 pinned archive/hash/internal timing verified; no hardware access.'; return }
$r11Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r11ActiveProgrammer = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }
if ($r11ActiveProgrammer) { throw 'Another programmer operation is active.' }
$r11Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r11Log = Join-Path $r11Root "output\board\sin12_r11_sram_${r11Stamp}.log"
$r11CodeLog = Join-Path $r11Root "output\board\sin12_r11_code_${r11Stamp}.log"
Write-Output 'Experimental SIN12 R11 SRAM only. MPW/external DVP and HDMI text OSD remain incomplete. No Flash operation.'
& $r11Cli --device GW5AT-60B --operation_index 2 --fsFile $r11Fs --cable-index 1 --frequency 2.5MHz *> $r11Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r11Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r11Log" }
& $r11Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r11CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r11CodeLog -Raw) -notmatch '0x534[Ee]324B') { throw "R11 independent readback mismatch: $r11CodeLog" }
$r11Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R11 experimental SRAM candidate'
    user_code = '0x534E324B'; map_id = '0x2613'; fs_sha256 = $r11ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r11Log, $r11CodeLog)
    note = 'Hardware event only; immutable build verification unchanged. No motor command sent.'
}
$r11Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r11Root "output\board\SIN12_R11_SRAM_EVENT_${r11Stamp}.json") -Encoding UTF8
Write-Output "SIN12 R11 SRAM independently verified: 0x534E324B; map 0x2613. Logs: $r11Log ; $r11CodeLog"
