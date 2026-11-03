param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate)
$ErrorActionPreference = 'Stop'
if (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r3Root = Split-Path -Parent $PSScriptRoot
$r3Archive = Join-Path $r3Root 'output\board\sin12_hdmi_r3_20261028_220638'
$r3Validation = Get-Content -LiteralPath (Join-Path $r3Archive 'validation.json') -Raw | ConvertFrom-Json
$r3Fs = Join-Path $r3Archive 'pnr\sin12_hdmi_system.fs'
$r3ExpectedHash = 'C37EED0501F03D242AFB610189A5995330354BBE98E7B03B222D1115A1749A6F'
if (-not $r3Validation.internal_setup_hold_pass -or -not $r3Validation.oser_reset_recovery_removal_pass_with_startup_protocol) { throw 'Internal timing evidence missing.' }
if ((Get-FileHash -LiteralPath $r3Fs -Algorithm SHA256).Hash -ne $r3ExpectedHash) { throw 'R3 archived bitstream hash mismatch.' }
$r3Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r3Stamp = Get-Date -Format yyyyMMdd_HHmmss
$r3Log = Join-Path $r3Root "output\board\sin12_r3_sram_${r3Stamp}.log"
$r3CodeLog = Join-Path $r3Root "output\board\sin12_r3_code_${r3Stamp}.log"
Write-Output 'Experimental SIN12 R3 SRAM only: All-clock MPW/external DVP signoff and HDMI text OSD remain incomplete. No Flash operation.'
& $r3Cli --device GW5AT-60B --operation_index 2 --fsFile $r3Fs --cable-index 1 --frequency 2.5MHz *> $r3Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r3Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r3Log" }
& $r3Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r3CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r3CodeLog -Raw) -notmatch '0x534[Ee]3243') { throw "R3 independent readback mismatch: $r3CodeLog" }
$r3Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R3 experimental HDMI/motor SRAM candidate'
    user_code = '0x534E3243'; map_id = '0x2613'; fs_sha256 = $r3ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r3Log, $r3CodeLog)
    note = 'Hardware event only; immutable build validation remains a build-time snapshot. No motor command sent.'
}
$r3Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r3Root 'output\board\SIN12_R3_HARDWARE_VALIDATION_2026-10-28.json') -Encoding UTF8
Write-Output "SIN12 R3 SRAM independently verified: 0x534E3243; map 0x2613. Logs: $r3Log ; $r3CodeLog"
