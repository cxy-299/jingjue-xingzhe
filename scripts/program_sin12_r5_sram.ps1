param([switch]$Driver12VOff, [switch]$WheelsRaised, [switch]$ExperimentalCandidate, [switch]$ValidateFiles)
$ErrorActionPreference = 'Stop'
if (-not $ValidateFiles -and (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm driver 12V OFF, wheels raised, and experimental SRAM candidate scope.'
}
$r5Root = Split-Path -Parent $PSScriptRoot
$r5Archive = Join-Path $r5Root 'output\board\sin12_hdmi_r5_20261029_172008'
$r5Validation = Get-Content -LiteralPath (Join-Path $r5Archive 'BUILD_VERIFICATION.json') -Raw | ConvertFrom-Json
$r5Fs = Join-Path $r5Archive 'impl\pnr\sin12_hdmi_system.fs'
$r5ExpectedHash = '0EC9A599BD3C327C190D77B9E42BE6DE0D702BE1044C900E21FCC9F8EAACF69F'
if ($r5Validation.status -ne 'INTERNAL_SETUP_HOLD_RESET_PASS_SRAM_CANDIDATE_NOT_FULL_SIGNOFF' -or
    $r5Validation.user_code -ne '0x534E3245' -or $r5Validation.source_hashes_verified -ne 56 -or
    $r5Validation.setup_violations -ne 0 -or $r5Validation.hold_violations -ne 0 -or
    $r5Validation.oser_reset.recovery_paths -ne 12 -or $r5Validation.oser_reset.removal_paths -ne 12 -or
    $r5Validation.oser_reset.min_recovery_ns -le 0 -or $r5Validation.oser_reset.min_removal_ns -le 0) {
    throw 'R5 internal timing evidence missing or inconsistent.'
}
if ((Get-FileHash -LiteralPath $r5Fs -Algorithm SHA256).Hash -ne $r5ExpectedHash -or
    $r5Validation.fs_sha256 -ne $r5ExpectedHash) { throw 'R5 archived bitstream hash mismatch.' }
if ($ValidateFiles) { Write-Output 'R5 pinned archive/hash/internal timing verified; no hardware access.'; return }
$r5Cli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r5Stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$r5Log = Join-Path $r5Root "output\board\sin12_r5_sram_${r5Stamp}.log"
$r5CodeLog = Join-Path $r5Root "output\board\sin12_r5_code_${r5Stamp}.log"
Write-Output 'Experimental SIN12 R5 SRAM only. MPW/external DVP and HDMI text OSD remain incomplete. No Flash operation.'
& $r5Cli --device GW5AT-60B --operation_index 2 --fsFile $r5Fs --cable-index 1 --frequency 2.5MHz *> $r5Log
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r5Log -Raw) -notmatch 'Finished\.') { throw "SRAM download failed: $r5Log" }
& $r5Cli --device GW5AT-60B --operation_index 73 --cable-index 1 --frequency 2.5MHz *> $r5CodeLog
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $r5CodeLog -Raw) -notmatch '0x534[Ee]3245') { throw "R5 independent readback mismatch: $r5CodeLog" }
$r5Event = [ordered]@{
    timestamp = (Get-Date -Format o)
    release = 'SIN12 R5 experimental SRAM candidate'
    user_code = '0x534E3245'; map_id = '0x2613'; fs_sha256 = $r5ExpectedHash
    sram_program = 'passed'; independent_user_code_readback = 'passed'
    user_confirmed_driver_12v_off = $true; user_confirmed_wheels_raised = $true
    static_accepted = $false; offground_accepted = $false; ground_accepted = $false
    flash_written_this_run = $false; release_approved = $false
    logs = @($r5Log, $r5CodeLog)
    note = 'Hardware event only; immutable build verification unchanged. No motor command sent.'
}
$r5Event | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $r5Root "output\board\SIN12_R5_SRAM_EVENT_${r5Stamp}.json") -Encoding UTF8
Write-Output "SIN12 R5 SRAM independently verified: 0x534E3245; map 0x2613. Logs: $r5Log ; $r5CodeLog"
