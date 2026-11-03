param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate)
$ErrorActionPreference = 'Stop'
if (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r2Root = Split-Path -Parent $PSScriptRoot
$r2Archive = Join-Path $r2Root 'output\board\sin12_hdmi_r2_mpw_empty_20261028_131249'
$r2Validation = Get-Content -LiteralPath (Join-Path $r2Archive 'validation.json') -Raw | ConvertFrom-Json
$r2Fs = Join-Path $r2Archive 'pnr\sin12_hdmi_system.fs'
$r2ExpectedHash = 'FE2B13DAC77283FB44B70F09638F53B514C5F215725B6D64111EA558AC0504D3'
if (-not $r2Validation.internal_setup_hold_pass -or -not $r2Validation.oser_reset_recovery_removal_pass_with_startup_protocol) { throw 'Internal timing evidence missing.' }
if ((Get-FileHash -LiteralPath $r2Fs -Algorithm SHA256).Hash -ne $r2ExpectedHash) { throw 'R2 archived bitstream hash mismatch.' }
$r2Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r2Stamp = Get-Date -Format yyyyMMdd_HHmmss
$r2Log = Join-Path $r2Root "output\board\sin12_r2_sram_${r2Stamp}.log"
$r2CodeLog = Join-Path $r2Root "output\board\sin12_r2_code_${r2Stamp}.log"
Write-Output 'Experimental SIN12 R2 SRAM only: MPW/external DVP signoff and HDMI text OSD remain incomplete. No Flash operation.'
& $r2Cli --device GW5AT-60B --operation_index 2 --fsFile $r2Fs --cable-index 1 --frequency 2.5MHz *> $r2Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r2Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r2Log" }
& $r2Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r2CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r2CodeLog -Raw) -notmatch '0x534[Ee]3242') { throw "R2 independent readback mismatch: $r2CodeLog" }
$r2Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R2 experimental HDMI/motor SRAM candidate'
    user_code = '0x534E3242'; map_id = '0x2613'; fs_sha256 = $r2ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r2Log, $r2CodeLog)
    note = 'Hardware event only; immutable build validation remains a build-time snapshot. No motor command sent.'
}
$r2Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r2Root 'output\board\SIN12_R2_HARDWARE_VALIDATION_2026-10-28.json') -Encoding UTF8
Write-Output "SIN12 R2 SRAM independently verified: 0x534E3242; map 0x2613. Logs: $r2Log ; $r2CodeLog"
