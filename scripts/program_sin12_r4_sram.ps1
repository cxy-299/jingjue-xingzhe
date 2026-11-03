param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r4Root = Split-Path -Parent $PSScriptRoot
$r4Archive = Join-Path $r4Root 'output\board\sin12_hdmi_r4_20261029_001740'
$r4Validation = Get-Content -LiteralPath (Join-Path $r4Archive 'validation.json') -Raw | ConvertFrom-Json
$r4Fs = Join-Path $r4Archive 'pnr\sin12_hdmi_system.fs'
$r4ExpectedHash = '6F04FF7AB38BBC4901E102299DDA092AC8558B0C235EC8E657334CA20218F60A'
if (-not $r4Validation.internal_setup_hold_pass -or -not $r4Validation.oser_reset_recovery_removal_pass_with_startup_protocol) { throw 'Internal timing evidence missing.' }
if ((Get-FileHash -LiteralPath $r4Fs -Algorithm SHA256).Hash -ne $r4ExpectedHash) { throw 'R4 archived bitstream hash mismatch.' }
if ($ValidateFiles) { Write-Output 'R4 pinned archive/hash/internal timing verified; no hardware access.'; return }
$r4Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r4Stamp = Get-Date -Format yyyyMMdd_HHmmss
$r4Log = Join-Path $r4Root "output\board\sin12_r4_sram_${r4Stamp}.log"
$r4CodeLog = Join-Path $r4Root "output\board\sin12_r4_code_${r4Stamp}.log"
Write-Output 'Experimental SIN12 R4 SRAM only: All-clock MPW/external DVP signoff and HDMI text OSD remain incomplete. No Flash operation.'
& $r4Cli --device GW5AT-60B --operation_index 2 --fsFile $r4Fs --cable-index 1 --frequency 2.5MHz *> $r4Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r4Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r4Log" }
& $r4Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r4CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r4CodeLog -Raw) -notmatch '0x534[Ee]3244') { throw "R4 independent readback mismatch: $r4CodeLog" }
$r4Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R4 experimental HDMI/motor SRAM candidate'
    user_code = '0x534E3244'; map_id = '0x2613'; fs_sha256 = $r4ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r4Log, $r4CodeLog)
    note = 'Hardware event only; immutable build validation remains a build-time snapshot. No motor command sent.'
}
$r4Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r4Root 'output\board\SIN12_R4_HARDWARE_VALIDATION_2026-10-29.json') -Encoding UTF8
Write-Output "SIN12 R4 SRAM independently verified: 0x534E3244; map 0x2613. Logs: $r4Log ; $r4CodeLog"
