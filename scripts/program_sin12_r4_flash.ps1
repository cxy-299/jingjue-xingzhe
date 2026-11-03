param(
    [ValidateSet('ValidateFiles','Program','Verify','Reload','ReadCode')]
    [string]$Mode = 'ValidateFiles',
    [switch]$Driver12VOff, [switch]$WheelsRaised,
    [switch]$ExperimentalCandidate
)
$ErrorActionPreference = 'Stop'
$r4FlashRoot = Split-Path -Parent $PSScriptRoot
$r4FlashArchive = Join-Path $r4FlashRoot 'output\board\sin12_hdmi_r4_20261029_001740'
$r4FlashFs = Join-Path $r4FlashArchive 'pnr\sin12_hdmi_system.fs'
$r4FlashHash = '6F04FF7AB38BBC4901E102299DDA092AC8558B0C235EC8E657334CA20218F60A'
$r4FlashValidation = Get-Content -LiteralPath (Join-Path $r4FlashArchive 'validation.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $r4FlashFs -Algorithm SHA256).Hash -ne $r4FlashHash -or
    -not $r4FlashValidation.internal_setup_hold_pass -or
    -not $r4FlashValidation.oser_reset_recovery_removal_pass_with_startup_protocol) {
    throw 'R4 pinned bitstream or internal timing evidence mismatch; no hardware operation.'
}
if ($Mode -eq 'ValidateFiles') {
    Write-Output 'R4 pinned files valid: 0x534E3244, map0x2613. Experimental candidate: MPW/external DVP signoff and HDMI text OSD incomplete. No hardware operation.'
    return
}
if (-not $Driver12VOff) { throw 'Confirm actual motor driver 12V OFF.' }
if ($Mode -eq 'Program' -and (-not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm wheels raised and explicitly authorized experimental R4 Flash scope.'
}
if ($Mode -eq 'Program') {
    $r4Hardware = Get-Content -LiteralPath (Join-Path $r4FlashRoot 'output\board\SIN12_R4_HARDWARE_VALIDATION_2026-10-29.json') -Raw | ConvertFrom-Json
    if ($r4Hardware.user_code -ne '0x534E3244' -or $r4Hardware.fs_sha256 -ne $r4FlashHash -or
        $r4Hardware.sram_program -ne 'passed' -or -not $r4Hardware.offground_accepted) {
        throw 'Matching R4 SRAM/offground acceptance record missing; no Flash operation.'
    }
}
$r4FlashCli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r4FlashStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$r4FlashLogs = [System.Collections.Generic.List[string]]::new()
$r4FlashEventPath = Join-Path $r4FlashRoot 'output\board\SIN12_R4_FLASH_EVENT_2026-10-29.json'
if ($Mode -ne 'Program') {
    $r4FlashEventPath = Join-Path $r4FlashRoot "output\board\sin12_r4_flash_${r4FlashStamp}_${Mode}_event.json"
}
$r4FlashEvent = [ordered]@{
    timestamp = (Get-Date -Format o); mode = $Mode; user_code = '0x534E3244'; map_id = '0x2613'
    fs_sha256 = $r4FlashHash; experimental_candidate = $true; release_approved = $false
    user_requested_flash = $true; driver_12v_off_confirmed = $Driver12VOff.IsPresent
    flash_program_verify = 'not_run'; independent_verify = 'not_run'; reload_readback = 'not_run'
    physical_cold_boot = 'pending'; ground_acceptance = 'pending'
    acceptance_evidence = 'User completed offground PID trials and explicitly requested R4 Flash for ground testing. Log console_20261029_110344_263112.log confirms C snapshots, K acknowledgments including 6/1/0, valid I frames W0, and final four-wheel target/speed/duty zero. Ground heading and rotation performance remain pending.'
    limitations = @('All-clock MPW coverage incomplete','External DVP signoff incomplete','HDMI sensor text OSD not implemented')
}
function Save-R4FlashEvent {
    $r4FlashEvent['logs'] = @($r4FlashLogs.ToArray())
    $r4FlashEvent | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $r4FlashEventPath -Encoding UTF8
}
function Invoke-R4FlashOperation([int]$Index,[string]$Label,[string]$Expected) {
    $r4FlashEvent['stage']=$Label
    $r4OpLog = Join-Path $r4FlashRoot "output\board\sin12_r4_flash_${r4FlashStamp}_${Label}.log"
    $r4FlashLogs.Add($r4OpLog)
    $r4OpArgs = @('--device','GW5AT-60B','--operation_index',"$Index",'--cable-index','1','--frequency','2.5MHz')
    if ($Index -eq 54 -or $Index -eq 66) { $r4OpArgs += @('--fsFile',$r4FlashFs) }
    & $r4FlashCli @r4OpArgs *> $r4OpLog
    $r4OpExit = $LASTEXITCODE
    $r4OpText = Get-Content -LiteralPath $r4OpLog -Raw
    if ($r4OpExit -ne 0 -or $r4OpText -notmatch 'Finished\.' -or
        $r4OpText -notmatch $Expected -or $r4OpText -match '(?im)^\s*Error[:!]') {
        throw "Operation $Label failed; inspect $r4OpLog. No automatic rewrite or retry."
    }
    Write-Output "$Label PASS: $r4OpLog"
}
function Reload-R4Flash([string]$Phase = 'final') {
    Invoke-R4FlashOperation 1 "${Phase}_reload" 'Reprogram'
    Start-Sleep -Seconds 12
    Invoke-R4FlashOperation 73 "${Phase}_read_code" '0x534[Ee]3244'
}
try {
    switch ($Mode) {
        'Program' {
            Invoke-R4FlashOperation 73 'preflight_code' '0x534[Ee]3244'
            Invoke-R4FlashOperation 51 'detect' '0xC22018'
            Invoke-R4FlashOperation 54 'program_verify' 'Verify Flash successfully'
            $r4FlashEvent['flash_program_verify']='passed';Save-R4FlashEvent
            # Reload before independent verification: avoid the known post-program address7 issue.
            # This does not erase or program Flash a second time.
            Reload-R4Flash 'pre_verify'
            $r4FlashEvent['pre_verify_reload']='passed';Save-R4FlashEvent
            Invoke-R4FlashOperation 66 'independent_verify' 'Verify Flash successfully'
            $r4FlashEvent['independent_verify']='passed';Save-R4FlashEvent
            Reload-R4Flash
            $r4FlashEvent['reload_readback']='passed';Save-R4FlashEvent
        }
        'Verify' {
            Invoke-R4FlashOperation 66 'independent_verify' 'Verify Flash successfully'
            $r4FlashEvent['independent_verify']='passed'
            Reload-R4Flash
            $r4FlashEvent['reload_readback']='passed';Save-R4FlashEvent
        }
        'Reload' { Reload-R4Flash }
        'ReadCode' { Invoke-R4FlashOperation 73 'read_code' '0x534[Ee]3244' }
    }
} catch {
    if ($r4FlashEvent['stage'] -eq 'independent_verify') { $r4FlashEvent['independent_verify']='failed' }
    if ($r4FlashEvent['stage'] -eq 'program_verify') { $r4FlashEvent['flash_program_verify']='failed' }
    $r4FlashEvent['error']=$_.Exception.Message
    Save-R4FlashEvent
    throw
}
# JTAG reload is not a physical power-cycle test and never marks ground acceptance.

