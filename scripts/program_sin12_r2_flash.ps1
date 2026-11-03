param(
    [ValidateSet('ValidateFiles','Program','Verify','Reload','ReadCode')]
    [string]$Mode = 'ValidateFiles',
    [switch]$Driver12VOff, [switch]$WheelsRaised,
    [switch]$ExperimentalCandidate
)
$ErrorActionPreference = 'Stop'
$r2FlashRoot = Split-Path -Parent $PSScriptRoot
$r2FlashArchive = Join-Path $r2FlashRoot 'output\board\sin12_hdmi_r2_mpw_empty_20261028_131249'
$r2FlashFs = Join-Path $r2FlashArchive 'pnr\sin12_hdmi_system.fs'
$r2FlashHash = 'FE2B13DAC77283FB44B70F09638F53B514C5F215725B6D64111EA558AC0504D3'
$r2FlashValidation = Get-Content -LiteralPath (Join-Path $r2FlashArchive 'validation.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $r2FlashFs -Algorithm SHA256).Hash -ne $r2FlashHash -or
    -not $r2FlashValidation.internal_setup_hold_pass -or
    -not $r2FlashValidation.oser_reset_recovery_removal_pass_with_startup_protocol) {
    throw 'R2 pinned bitstream or internal timing evidence mismatch; no hardware operation.'
}
if ($Mode -eq 'ValidateFiles') {
    Write-Output 'R2 pinned files valid: 0x534E3242, map0x2613. Experimental candidate: MPW/external DVP signoff and HDMI text OSD incomplete. No hardware operation.'
    return
}
if (-not $Driver12VOff) { throw 'Confirm actual motor driver 12V OFF.' }
if ($Mode -eq 'Program' -and (-not $WheelsRaised -or -not $ExperimentalCandidate)) {
    throw 'Confirm wheels raised and explicitly authorized experimental R2 Flash scope.'
}
$r2FlashCli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r2FlashStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$r2FlashLogs = [System.Collections.Generic.List[string]]::new()
$r2FlashEventPath = Join-Path $r2FlashRoot 'output\board\SIN12_R2_FLASH_EVENT_2026-10-28.json'
if ($Mode -ne 'Program') {
    $r2FlashEventPath = Join-Path $r2FlashRoot "output\board\sin12_r2_flash_${r2FlashStamp}_${Mode}_event.json"
}
$r2FlashEvent = [ordered]@{
    timestamp = (Get-Date -Format o); mode = $Mode; user_code = '0x534E3242'; map_id = '0x2613'
    fs_sha256 = $r2FlashHash; experimental_candidate = $true; release_approved = $false
    user_requested_flash = $true; driver_12v_off_confirmed = $Driver12VOff.IsPresent
    flash_program_verify = 'not_run'; independent_verify = 'not_run'; reload_readback = 'not_run'
    physical_cold_boot = 'pending'; ground_acceptance = 'pending'
    mission_completion_evidence = 'User reports no problem; latest PC log shows J S03 then S0C, no S06 observed.'
    limitations = @('MPW signoff incomplete','External DVP signoff incomplete','HDMI sensor text OSD not implemented')
}
function Save-R2FlashEvent {
    $r2FlashEvent['logs'] = @($r2FlashLogs.ToArray())
    $r2FlashEvent | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $r2FlashEventPath -Encoding UTF8
}
function Invoke-R2FlashOperation([int]$Index,[string]$Label,[string]$Expected) {
    $r2FlashEvent['stage']=$Label
    $r2OpLog = Join-Path $r2FlashRoot "output\board\sin12_r2_flash_${r2FlashStamp}_${Label}.log"
    $r2FlashLogs.Add($r2OpLog)
    $r2OpArgs = @('--device','GW5AT-60B','--operation_index',"$Index",'--cable-index','1','--frequency','2.5MHz')
    if ($Index -eq 54 -or $Index -eq 66) { $r2OpArgs += @('--fsFile',$r2FlashFs) }
    & $r2FlashCli @r2OpArgs *> $r2OpLog
    $r2OpExit = $LASTEXITCODE
    $r2OpText = Get-Content -LiteralPath $r2OpLog -Raw
    if ($r2OpExit -ne 0 -or $r2OpText -notmatch 'Finished\.' -or
        $r2OpText -notmatch $Expected -or $r2OpText -match '(?im)^\s*Error[:!]') {
        throw "Operation $Label failed; inspect $r2OpLog. No automatic rewrite or retry."
    }
    Write-Output "$Label PASS: $r2OpLog"
}
function Reload-R2Flash {
    Invoke-R2FlashOperation 1 'reload' 'Reprogram'
    Start-Sleep -Seconds 12
    Invoke-R2FlashOperation 73 'read_code' '0x534[Ee]3242'
}
try {
    switch ($Mode) {
        'Program' {
            Invoke-R2FlashOperation 73 'preflight_code' '0x534[Ee]3242'
            Invoke-R2FlashOperation 51 'detect' '0xC22018'
            Invoke-R2FlashOperation 54 'program_verify' 'Verify Flash successfully'
            $r2FlashEvent['flash_program_verify']='passed';Save-R2FlashEvent
            Invoke-R2FlashOperation 66 'independent_verify' 'Verify Flash successfully'
            $r2FlashEvent['independent_verify']='passed';Save-R2FlashEvent
            Reload-R2Flash
            $r2FlashEvent['reload_readback']='passed';Save-R2FlashEvent
        }
        'Verify' {
            Invoke-R2FlashOperation 66 'independent_verify' 'Verify Flash successfully'
            $r2FlashEvent['independent_verify']='passed'
            Reload-R2Flash
            $r2FlashEvent['reload_readback']='passed';Save-R2FlashEvent
        }
        'Reload' { Reload-R2Flash }
        'ReadCode' { Invoke-R2FlashOperation 73 'read_code' '0x534[Ee]3242' }
    }
} catch {
    if ($r2FlashEvent['stage'] -eq 'independent_verify') { $r2FlashEvent['independent_verify']='failed' }
    if ($r2FlashEvent['stage'] -eq 'program_verify') { $r2FlashEvent['flash_program_verify']='failed' }
    $r2FlashEvent['error']=$_.Exception.Message
    Save-R2FlashEvent
    throw
}
# JTAG reload is not a physical power-cycle test and never marks ground acceptance.
