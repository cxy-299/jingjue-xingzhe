param(
    [ValidateSet('ValidateFiles','Program','Verify','Reload','ReadCode')]
    [string]$Mode = 'ValidateFiles',
    [switch]$Driver12VOff, [switch]$WheelsRaised,
    [switch]$ExperimentalCandidate
)
$ErrorActionPreference = 'Stop'
$r3FlashRoot = Split-Path -Parent $PSScriptRoot
$r3FlashArchive = Join-Path $r3FlashRoot 'output\board\sin12_hdmi_r3_20261028_220638'
$r3FlashFs = Join-Path $r3FlashArchive 'pnr\sin12_hdmi_system.fs'
$r3FlashHash = 'C37EED0501F03D242AFB610189A5995330354BBE98E7B03B222D1115A1749A6F'
$r3FlashValidation = Get-Content -LiteralPath (Join-Path $r3FlashArchive 'validation.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $r3FlashFs -Algorithm SHA256).Hash -ne $r3FlashHash -or
    -not $r3FlashValidation.internal_setup_hold_pass -or
    -not $r3FlashValidation.oser_reset_recovery_removal_pass_with_startup_protocol) {
    throw 'R3 pinned bitstream or internal timing evidence mismatch; no hardware operation.'
}
if ($Mode -eq 'ValidateFiles') {
    Write-Output 'R3 pinned files valid: 0x534E3243, map0x2613. Experimental candidate: MPW/external DVP signoff and HDMI text OSD incomplete. No hardware operation.'
    return
}
if (-not $Driver12VOff) { throw 'Confirm actual motor driver 12V OFF.' }
if ($Mode -eq 'Program' -and (-not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm wheels raised and explicitly authorized experimental R3 Flash scope.'
}
if ($Mode -eq 'Program') {
    $r3Hardware = Get-Content -LiteralPath (Join-Path $r3FlashRoot 'output\board\SIN12_R3_HARDWARE_VALIDATION_2026-10-28.json') -Raw | ConvertFrom-Json
    if ($r3Hardware.user_code -ne '0x534E3243' -or $r3Hardware.fs_sha256 -ne $r3FlashHash -or
        $r3Hardware.sram_program -ne 'passed' -or -not $r3Hardware.offground_accepted) {
        throw 'Matching R3 SRAM/offground acceptance record missing; no Flash operation.'
    }
}
$r3FlashCli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r3FlashStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$r3FlashLogs = [System.Collections.Generic.List[string]]::new()
$r3FlashEventPath = Join-Path $r3FlashRoot 'output\board\SIN12_R3_FLASH_EVENT_2026-10-28.json'
if ($Mode -ne 'Program') {
    $r3FlashEventPath = Join-Path $r3FlashRoot "output\board\sin12_r3_flash_${r3FlashStamp}_${Mode}_event.json"
}
$r3FlashEvent = [ordered]@{
    timestamp = (Get-Date -Format o); mode = $Mode; user_code = '0x534E3243'; map_id = '0x2613'
    fs_sha256 = $r3FlashHash; experimental_candidate = $true; release_approved = $false
    user_requested_flash = $true; driver_12v_off_confirmed = $Driver12VOff.IsPresent
    flash_program_verify = 'not_run'; independent_verify = 'not_run'; reload_readback = 'not_run'
    physical_cold_boot = 'pending'; ground_acceptance = 'pending'
    acceptance_evidence = 'User reports physical startup/stop normal; brief R3 tests have 56 I frames H0/F00/W0 and no motor trip. All final duty0; M1 first post-stop A+5, no later M1 sample. Ground straightness untested.'
    limitations = @('All-clock MPW coverage incomplete','External DVP signoff incomplete','HDMI sensor text OSD not implemented')
}
function Save-R3FlashEvent {
    $r3FlashEvent['logs'] = @($r3FlashLogs.ToArray())
    $r3FlashEvent | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $r3FlashEventPath -Encoding UTF8
}
function Invoke-R3FlashOperation([int]$Index,[string]$Label,[string]$Expected) {
    $r3FlashEvent['stage']=$Label
    $r3OpLog = Join-Path $r3FlashRoot "output\board\sin12_r3_flash_${r3FlashStamp}_${Label}.log"
    $r3FlashLogs.Add($r3OpLog)
    $r3OpArgs = @('--device','GW5AT-60B','--operation_index',"$Index",'--cable-index','1','--frequency','2.5MHz')
    if ($Index -eq 54 -or $Index -eq 66) { $r3OpArgs += @('--fsFile',$r3FlashFs) }
    & $r3FlashCli @r3OpArgs *> $r3OpLog
    $r3OpExit = $LASTEXITCODE
    $r3OpText = Get-Content -LiteralPath $r3OpLog -Raw
    if ($r3OpExit -ne 0 -or $r3OpText -notmatch 'Finished\.' -or
        $r3OpText -notmatch $Expected -or $r3OpText -match '(?im)^\s*Error[:!]') {
        throw "Operation $Label failed; inspect $r3OpLog. No automatic rewrite or retry."
    }
    Write-Output "$Label PASS: $r3OpLog"
}
function Reload-R3Flash([string]$Phase = 'final') {
    Invoke-R3FlashOperation 1 "${Phase}_reload" 'Reprogram'
    Start-Sleep -Seconds 12
    Invoke-R3FlashOperation 73 "${Phase}_read_code" '0x534[Ee]3243'
}
try {
    switch ($Mode) {
        'Program' {
            Invoke-R3FlashOperation 73 'preflight_code' '0x534[Ee]3243'
            Invoke-R3FlashOperation 51 'detect' '0xC22018'
            Invoke-R3FlashOperation 54 'program_verify' 'Verify Flash successfully'
            $r3FlashEvent['flash_program_verify']='passed';Save-R3FlashEvent
            # Reload before independent verification: avoid the known post-program address7 issue.
            # This does not erase or program Flash a second time.
            Reload-R3Flash 'pre_verify'
            $r3FlashEvent['pre_verify_reload']='passed';Save-R3FlashEvent
            Invoke-R3FlashOperation 66 'independent_verify' 'Verify Flash successfully'
            $r3FlashEvent['independent_verify']='passed';Save-R3FlashEvent
            Reload-R3Flash
            $r3FlashEvent['reload_readback']='passed';Save-R3FlashEvent
        }
        'Verify' {
            Invoke-R3FlashOperation 66 'independent_verify' 'Verify Flash successfully'
            $r3FlashEvent['independent_verify']='passed'
            Reload-R3Flash
            $r3FlashEvent['reload_readback']='passed';Save-R3FlashEvent
        }
        'Reload' { Reload-R3Flash }
        'ReadCode' { Invoke-R3FlashOperation 73 'read_code' '0x534[Ee]3243' }
    }
} catch {
    if ($r3FlashEvent['stage'] -eq 'independent_verify') { $r3FlashEvent['independent_verify']='failed' }
    if ($r3FlashEvent['stage'] -eq 'program_verify') { $r3FlashEvent['flash_program_verify']='failed' }
    $r3FlashEvent['error']=$_.Exception.Message
    Save-R3FlashEvent
    throw
}
# JTAG reload is not a physical power-cycle test and never marks ground acceptance.
