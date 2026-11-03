param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r9Root = Split-Path -Parent $PSScriptRoot
$r9Archive = Join-Path $r9Root 'output\board\sin12_hdmi_r9_20261030_135330'
$r9Validation = Get-Content -LiteralPath (Join-Path $r9Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json
$r9Fs = Join-Path $r9Archive 'impl\pnr\sin12_hdmi_system.fs'
$r9ExpectedHash = '9EB3E89E8B4D4002BB4493AA3C865CA0095F639A2ABA2C08B5568E22B0BFC0DB'
if ($r9Validation.internal_sta_pass -ne $true -or
    $r9Validation.mapped_target.passed -ne $true -or $r9Validation.mapped_target.vectors -ne 2172 -or
    $r9Validation.usercode -ne '534E3249' -or $r9Validation.sources_verified -ne 57 -or
    $r9Validation.setup_violations -ne 0 -or $r9Validation.hold_violations -ne 0 -or
    $r9Validation.fmax_mhz.clk_50m -lt 50 -or $r9Validation.fmax_mhz.camera_pixel -lt 75 -or
    $r9Validation.fmax_mhz.camera_pclk -lt 75 -or
    $r9Validation.tables.'3.1.3.1 Recovery Paths Table[1]'.reported_paths -ne 12 -or
    $r9Validation.tables.'3.1.4.1 Removal Paths Table[1]'.reported_paths -ne 12 -or
    $r9Validation.tables.'3.1.3.2 Recovery Paths Table[2]'.reported_paths -lt 200 -or
    $r9Validation.tables.'3.1.4.2 Removal Paths Table[2]'.reported_paths -lt 200) {
    throw 'R9 internal timing evidence missing or inconsistent.'
}
foreach ($tableName in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]',
                         '3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r9Validation.tables.$tableName.minimum_slack_ns -le 0) { throw "Invalid reset timing: $tableName" }
}
$r9Manifest = Get-Content -LiteralPath (Join-Path $r9Archive 'sin12_hdmi_r9_build_sources.json') -Raw | ConvertFrom-Json
foreach ($entry in $r9Manifest.PSObject.Properties) {
    $r9Source = Join-Path (Join-Path $r9Archive 'sources') $entry.Name
    if ((Get-FileHash -LiteralPath $r9Source -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "R9 frozen source hash mismatch: $($entry.Name)"
    }
}
if ((Get-FileHash -LiteralPath $r9Fs -Algorithm SHA256).Hash -ne $r9ExpectedHash -or
    $r9Validation.fs_sha256 -ne $r9ExpectedHash) { throw 'R9 archived bitstream hash mismatch.' }
if ($r9Validation.mapped_tof.passed -ne $true -or $r9Validation.mapped_tof.checks -ne 91 -or $r9Validation.options.Replicate_Resources -ne $true) { throw 'R9 mapped ToF or replication evidence missing.' }
if ($r9Validation.mapped_approach.passed -ne $true -or $r9Validation.mapped_approach.samples -ne 5000) { throw 'R9 actual mapped approach evidence missing.' }
if ($ValidateFiles) { Write-Output 'R9 pinned archive/hash/internal timing verified; no hardware access.'; return }
$r9Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r9ActiveProgrammer = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }
if ($r9ActiveProgrammer) { throw 'Another programmer operation is active.' }
$r9Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r9Log = Join-Path $r9Root "output\board\sin12_r9_sram_${r9Stamp}.log"
$r9CodeLog = Join-Path $r9Root "output\board\sin12_r9_code_${r9Stamp}.log"
Write-Output 'Experimental SIN12 R9 SRAM only. MPW/external DVP and HDMI text OSD remain incomplete. No Flash operation.'
& $r9Cli --device GW5AT-60B --operation_index 2 --fsFile $r9Fs --cable-index 1 --frequency 2.5MHz *> $r9Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r9Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r9Log" }
& $r9Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r9CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r9CodeLog -Raw) -notmatch '0x534[Ee]3249') { throw "R9 independent readback mismatch: $r9CodeLog" }
$r9Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R9 experimental SRAM candidate'
    user_code = '0x534E3249'; map_id = '0x2613'; fs_sha256 = $r9ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r9Log, $r9CodeLog)
    note = 'Hardware event only; immutable build verification unchanged. No motor command sent.'
}
$r9Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r9Root "output\board\SIN12_R9_SRAM_EVENT_${r9Stamp}.json") -Encoding UTF8
Write-Output "SIN12 R9 SRAM independently verified: 0x534E3249; map 0x2613. Logs: $r9Log ; $r9CodeLog"
