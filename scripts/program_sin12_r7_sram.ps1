param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r7Root = Split-Path -Parent $PSScriptRoot
$r7Archive = Join-Path $r7Root 'output\board\sin12_hdmi_r7_20261029_223718'
$r7Validation = Get-Content -LiteralPath (Join-Path $r7Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json
$r7Fs = Join-Path $r7Archive 'impl\pnr\sin12_hdmi_system.fs'
$r7ExpectedHash = 'F8E19EB4AB78DDA045A226CE34BAF0FD3B564081B2AB72F293BD8DFB6987365D'
if ($r7Validation.internal_sta_pass -ne $true -or
    $r7Validation.mapped_target.passed -ne $true -or $r7Validation.mapped_target.vectors -ne 2172 -or
    $r7Validation.usercode -ne '534E3247' -or $r7Validation.sources_verified -ne 56 -or
    $r7Validation.setup_violations -ne 0 -or $r7Validation.hold_violations -ne 0 -or
    $r7Validation.fmax_mhz.clk_50m -lt 50 -or $r7Validation.fmax_mhz.camera_pixel -lt 75 -or
    $r7Validation.fmax_mhz.camera_pclk -lt 75 -or
    $r7Validation.tables.'3.1.3.1 Recovery Paths Table[1]'.reported_paths -ne 12 -or
    $r7Validation.tables.'3.1.4.1 Removal Paths Table[1]'.reported_paths -ne 12 -or
    $r7Validation.tables.'3.1.3.2 Recovery Paths Table[2]'.reported_paths -lt 200 -or
    $r7Validation.tables.'3.1.4.2 Removal Paths Table[2]'.reported_paths -lt 200) {
    throw 'R7 internal timing evidence missing or inconsistent.'
}
foreach ($tableName in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]',
                         '3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r7Validation.tables.$tableName.minimum_slack_ns -le 0) { throw "Invalid reset timing: $tableName" }
}
$r7Manifest = Get-Content -LiteralPath (Join-Path $r7Archive 'sin12_hdmi_r7_build_sources.json') -Raw | ConvertFrom-Json
foreach ($entry in $r7Manifest.PSObject.Properties) {
    $r7Source = Join-Path (Join-Path $r7Archive 'sources') $entry.Name
    if ((Get-FileHash -LiteralPath $r7Source -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "R7 frozen source hash mismatch: $($entry.Name)"
    }
}
if ((Get-FileHash -LiteralPath $r7Fs -Algorithm SHA256).Hash -ne $r7ExpectedHash -or
    $r7Validation.fs_sha256 -ne $r7ExpectedHash) { throw 'R7 archived bitstream hash mismatch.' }
if ($ValidateFiles) { Write-Output 'R7 pinned archive/hash/internal timing verified; no hardware access.'; return }
$r7Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r7ActiveProgrammer = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }
if ($r7ActiveProgrammer) { throw 'Another programmer operation is active.' }
$r7Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r7Log = Join-Path $r7Root "output\board\sin12_r7_sram_${r7Stamp}.log"
$r7CodeLog = Join-Path $r7Root "output\board\sin12_r7_code_${r7Stamp}.log"
Write-Output 'Experimental SIN12 R7 SRAM only. MPW/external DVP and HDMI text OSD remain incomplete. No Flash operation.'
& $r7Cli --device GW5AT-60B --operation_index 2 --fsFile $r7Fs --cable-index 1 --frequency 2.5MHz *> $r7Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r7Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r7Log" }
& $r7Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r7CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r7CodeLog -Raw) -notmatch '0x534[Ee]3247') { throw "R7 independent readback mismatch: $r7CodeLog" }
$r7Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R7 experimental SRAM candidate'
    user_code = '0x534E3247'; map_id = '0x2613'; fs_sha256 = $r7ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r7Log, $r7CodeLog)
    note = 'Hardware event only; immutable build verification unchanged. No motor command sent.'
}
$r7Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r7Root "output\board\SIN12_R7_SRAM_EVENT_${r7Stamp}.json") -Encoding UTF8
Write-Output "SIN12 R7 SRAM independently verified: 0x534E3247; map 0x2613. Logs: $r7Log ; $r7CodeLog"
