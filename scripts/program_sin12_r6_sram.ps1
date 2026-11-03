param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r6Root = Split-Path -Parent $PSScriptRoot
$r6Archive = Join-Path $r6Root 'output\board\sin12_hdmi_r6_20261029_212136'
$r6Validation = Get-Content -LiteralPath (Join-Path $r6Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json
$r6Fs = Join-Path $r6Archive 'impl\pnr\sin12_hdmi_system.fs'
$r6ExpectedHash = 'F9D6EF4FD04E6B2BF3ACAFBB6DCBFA40AF41FC45773BE478D4C962FBF4001EB8'
if ($r6Validation.internal_sta_pass -ne $true -or
    $r6Validation.usercode -ne '534E3246' -or $r6Validation.sources_verified -ne 56 -or
    $r6Validation.setup_violations -ne 0 -or $r6Validation.hold_violations -ne 0 -or
    $r6Validation.fmax_mhz.control -lt 50 -or $r6Validation.fmax_mhz.camera_pixel -lt 75 -or
    $r6Validation.fmax_mhz.camera_pclk -lt 75 -or
    $r6Validation.tables.'3.1.3.1 Recovery Paths Table[1]'.reported_paths -ne 12 -or
    $r6Validation.tables.'3.1.4.1 Removal Paths Table[1]'.reported_paths -ne 12 -or
    $r6Validation.tables.'3.1.3.2 Recovery Paths Table[2]'.reported_paths -lt 200 -or
    $r6Validation.tables.'3.1.4.2 Removal Paths Table[2]'.reported_paths -lt 200) {
    throw 'R6 internal timing evidence missing or inconsistent.'
}
foreach ($tableName in @('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]',
                         '3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')) {
    if ($r6Validation.tables.$tableName.minimum_slack_ns -le 0) { throw "Invalid reset timing: $tableName" }
}
$r6Manifest = Get-Content -LiteralPath (Join-Path $r6Archive 'sin12_hdmi_r6_build_sources.json') -Raw | ConvertFrom-Json
foreach ($entry in $r6Manifest.PSObject.Properties) {
    $r6Source = Join-Path (Join-Path $r6Archive 'sources') $entry.Name
    if ((Get-FileHash -LiteralPath $r6Source -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "R6 frozen source hash mismatch: $($entry.Name)"
    }
}
if ((Get-FileHash -LiteralPath $r6Fs -Algorithm SHA256).Hash -ne $r6ExpectedHash -or
    $r6Validation.fs_sha256 -ne $r6ExpectedHash) { throw 'R6 archived bitstream hash mismatch.' }
if ($ValidateFiles) { Write-Output 'R6 pinned archive/hash/internal timing verified; no hardware access.'; return }
$r6Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r6ActiveProgrammer = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }
if ($r6ActiveProgrammer) { throw 'Another programmer operation is active.' }
$r6Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r6Log = Join-Path $r6Root "output\board\sin12_r6_sram_${r6Stamp}.log"
$r6CodeLog = Join-Path $r6Root "output\board\sin12_r6_code_${r6Stamp}.log"
Write-Output 'Experimental SIN12 R6 SRAM only. MPW/external DVP and HDMI text OSD remain incomplete. No Flash operation.'
& $r6Cli --device GW5AT-60B --operation_index 2 --fsFile $r6Fs --cable-index 1 --frequency 2.5MHz *> $r6Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r6Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r6Log" }
& $r6Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r6CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r6CodeLog -Raw) -notmatch '0x534[Ee]3246') { throw "R6 independent readback mismatch: $r6CodeLog" }
$r6Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R6 experimental SRAM candidate'
    user_code = '0x534E3246'; map_id = '0x2613'; fs_sha256 = $r6ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r6Log, $r6CodeLog)
    note = 'Hardware event only; immutable build verification unchanged. No motor command sent.'
}
$r6Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r6Root "output\board\SIN12_R6_SRAM_EVENT_${r6Stamp}.json") -Encoding UTF8
Write-Output "SIN12 R6 SRAM independently verified: 0x534E3246; map 0x2613. Logs: $r6Log ; $r6CodeLog"
