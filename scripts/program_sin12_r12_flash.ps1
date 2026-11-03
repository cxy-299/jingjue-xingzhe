param(
    [ValidateSet('ValidateFiles','Program','Verify','Reload','ReadCode')]
    [string]$Mode = 'ValidateFiles',
    [switch]$Driver12VOff, [switch]$WheelsRaised,
    [switch]$ExperimentalCandidate
)
$ErrorActionPreference = 'Stop'
$r12FlashRoot = Split-Path -Parent $PSScriptRoot
$r12FlashArchive = Join-Path $r12FlashRoot 'output\board\sin12_hdmi_r12_20261030_180232'
$r12FlashFs = Join-Path $r12FlashArchive 'impl\pnr\sin12_hdmi_system.fs'
$r12FlashHash = '6E95B71A7D1D4B12E1AE255FF54EB86BBD15B857110033744165E8D1DD741DA0'
# Reuse the existing read-only archive/timing/mapped-source validation, not its
# SRAM programming branch. This also validates all 57 frozen source hashes.
& (Join-Path $PSScriptRoot 'program_sin12_r12_sram.ps1') -ValidateFiles
if ((Get-FileHash -LiteralPath $r12FlashFs -Algorithm SHA256).Hash -ne $r12FlashHash) {
    throw 'R12 pinned Flash image mismatch.'
}
$r12FlashSramEvents = Get-ChildItem -LiteralPath (Join-Path $r12FlashRoot 'output\board') -Filter 'SIN12_R12_SRAM_EVENT_*.json' |
    Sort-Object LastWriteTime -Descending
$r12FlashSramEvidence = $null
foreach ($r12FlashSramFile in $r12FlashSramEvents) {
    $r12FlashSramRecord = Get-Content -LiteralPath $r12FlashSramFile.FullName -Raw | ConvertFrom-Json
    if ($r12FlashSramRecord.fs_sha256 -eq $r12FlashHash -and
        $r12FlashSramRecord.user_code -eq '0x534E324C' -and
        $r12FlashSramRecord.sram_program -eq 'passed' -and
        $r12FlashSramRecord.independent_user_code_readback -eq 'passed') {
        $r12FlashSramEvidence = $r12FlashSramFile.FullName
        break
    }
}
if (-not $r12FlashSramEvidence) { throw 'Matching R12 SRAM programming/readback evidence missing.' }
if ($Mode -eq 'ValidateFiles') {
    Write-Output 'R12 Flash files valid: pinned 534E324C/map2613; matching SRAM/readback event exists. No hardware access. Field/vision acceptance remains separate.'
    return
}
if (-not $Driver12VOff -or -not $WheelsRaised -or -not $ExperimentalCandidate) {
    throw 'Confirm current motor 12V OFF, wheels raised and user-authorized R12 development Flash scope.'
}
$r12FlashCli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
if (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }) {
    throw 'Another programmer operation is active.'
}
$r12FlashStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$r12FlashLogs = [System.Collections.Generic.List[string]]::new()
$r12FlashEventPath = Join-Path $r12FlashRoot "output\board\SIN12_R12_FLASH_EVENT_${r12FlashStamp}.json"
$r12FlashEvent = [ordered]@{
    timestamp = (Get-Date -Format o); mode = $Mode; user_code = '0x534E324C'; map_id = '0x2613'
    fs_sha256 = $r12FlashHash; development_flash = $true; release_approved = $false
    user_requested_flash = $true; driver_12v_off_confirmed = $Driver12VOff.IsPresent
    wheels_raised_confirmed = $WheelsRaised.IsPresent; sram_evidence = $r12FlashSramEvidence
    flash_program_verify = 'not_run'; independent_verify = 'not_run'; reload_readback = 'not_run'
    physical_cold_boot = 'pending'; complete_field_acceptance = 'not_claimed'
    previous_flash_archive = 'output/board/sin12_hdmi_r4_20261029_001740'
    acceptance_scope = 'User requests persistence of the already SRAM-tested R12 for continued debugging. Vision target-loss/ToF-camera alignment and custom model training remain separate, not marked passed.'
    limitations = @('50MHz setup margin only 0.008ns','All-clock MPW coverage incomplete',
                    'External DVP signoff incomplete','HDMI sensor text OSD not implemented')
}
function Save-R12FlashEvent {
    $r12FlashEvent['logs'] = @($r12FlashLogs.ToArray())
    $r12FlashEvent | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $r12FlashEventPath -Encoding UTF8
}
function Invoke-R12FlashOperation([int]$Index,[string]$Label,[string]$Expected) {
    $r12FlashEvent['stage'] = $Label
    Save-R12FlashEvent
    $r12OpLog = Join-Path $r12FlashRoot "output\board\sin12_r12_flash_${r12FlashStamp}_${Label}.log"
    $r12FlashLogs.Add($r12OpLog)
    $r12OpArgs = @('--device','GW5AT-60B','--operation_index',"$Index",'--cable-index','1','--frequency','2.5MHz')
    if ($Index -eq 54 -or $Index -eq 66) { $r12OpArgs += @('--fsFile',$r12FlashFs) }
    & $r12FlashCli @r12OpArgs *> $r12OpLog
    $r12OpExit = $LASTEXITCODE
    $r12OpText = Get-Content -LiteralPath $r12OpLog -Raw
    if ($r12OpExit -ne 0 -or $r12OpText -notmatch 'Finished\.' -or
        $r12OpText -notmatch $Expected -or $r12OpText -match '(?im)^\s*Error[:!]') {
        throw "Operation $Label failed; inspect $r12OpLog. No automatic retry or rewrite."
    }
    Write-Output "$Label PASS: $r12OpLog"
}
function Reload-R12Flash([string]$Phase = 'final') {
    Invoke-R12FlashOperation 1 "${Phase}_reload" 'Reprogram'
    Start-Sleep -Seconds 12
    Invoke-R12FlashOperation 73 "${Phase}_read_code" '0x534[Ee]324[Cc]'
}
try {
    switch ($Mode) {
        'Program' {
            Invoke-R12FlashOperation 73 'preflight_code' '0x534[Ee]324[Cc]'
            Invoke-R12FlashOperation 51 'detect' '0xC22018'
            Invoke-R12FlashOperation 54 'program_verify' 'Verify Flash successfully'
            $r12FlashEvent['flash_program_verify'] = 'passed'; Save-R12FlashEvent
            # Known Programmer post-write verify addressing issue: reload once
            # before independent verify. This does not program Flash a second time.
            Reload-R12Flash 'pre_verify'
            $r12FlashEvent['pre_verify_reload'] = 'passed'; Save-R12FlashEvent
            Invoke-R12FlashOperation 66 'independent_verify' 'Verify Flash successfully'
            $r12FlashEvent['independent_verify'] = 'passed'; Save-R12FlashEvent
            Reload-R12Flash
            $r12FlashEvent['reload_readback'] = 'passed'; Save-R12FlashEvent
        }
        'Verify' {
            Invoke-R12FlashOperation 66 'independent_verify' 'Verify Flash successfully'
            $r12FlashEvent['independent_verify'] = 'passed'
            Reload-R12Flash
            $r12FlashEvent['reload_readback'] = 'passed'; Save-R12FlashEvent
        }
        'Reload' { Reload-R12Flash; $r12FlashEvent['reload_readback'] = 'passed'; Save-R12FlashEvent }
        'ReadCode' { Invoke-R12FlashOperation 73 'read_code' '0x534[Ee]324[Cc]'; Save-R12FlashEvent }
    }
} catch {
    if ($r12FlashEvent['stage'] -eq 'independent_verify') { $r12FlashEvent['independent_verify'] = 'failed' }
    if ($r12FlashEvent['stage'] -eq 'program_verify') { $r12FlashEvent['flash_program_verify'] = 'failed' }
    $r12FlashEvent['error'] = $_.Exception.Message
    Save-R12FlashEvent
    throw
}
# JTAG reload/readback is not physical cold boot, nor model/task acceptance.
