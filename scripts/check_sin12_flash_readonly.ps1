param([switch]$Driver12VOff,[switch]$WheelsRaised,[switch]$UserConfirmedReadOnly)
$ErrorActionPreference='Stop'
if (-not $Driver12VOff -or -not $WheelsRaised -or -not $UserConfirmedReadOnly) { throw 'Current safe-state and read-only user confirmation required.' }
$r12CheckRoot=Split-Path -Parent $PSScriptRoot
$r12CheckFs=Join-Path $r12CheckRoot 'output\board\sin12_hdmi_r12_20261030_180232\impl\pnr\sin12_hdmi_system.fs'
$r12CheckHash='6E95B71A7D1D4B12E1AE255FF54EB86BBD15B857110033744165E8D1DD741DA0'
if ((Get-FileHash -LiteralPath $r12CheckFs -Algorithm SHA256).Hash -ne $r12CheckHash) { throw 'Pinned image hash mismatch.' }
if (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'programmer_cli.exe' }) { throw 'Programmer already active.' }
$r12CheckStamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$r12CheckCli='D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$r12CheckReport=[ordered]@{timestamp=(Get-Date -Format o);operation_scope='Read-only Flash compare and current configuration UserCode, no reload';driver_12v_off_confirmed=$true;wheels_raised_confirmed=$true;flash_written=$false;explicit_reconfiguration_command_issued=$false;motion_commands_sent=$false;reference_release='R12';reference_sha256=$r12CheckHash;flash_compare='not_run';logs=@()}
function Invoke-ReadOnlyCheck([int]$Operation,[string]$Label) {
    if ($Operation -notin @(66,73)) { throw 'Read-only operation allowlist violation.' }
    $r12CheckLog=Join-Path $r12CheckRoot ('output\board\sin12_flash_readonly_'+$r12CheckStamp+'_'+$Label+'.log')
    $r12CheckArgs=@('--device','GW5AT-60B','--operation_index',"$Operation",'--cable-index','1','--frequency','2.5MHz')
    if ($Operation -eq 66) { $r12CheckArgs+=@('--fsFile',$r12CheckFs) }
    & $r12CheckCli @r12CheckArgs *> $r12CheckLog
    $r12CheckExit=$LASTEXITCODE
    $r12CheckText=Get-Content -LiteralPath $r12CheckLog -Raw
    $r12CheckReport.logs+= $r12CheckLog
    if ($r12CheckExit -ne 0 -or $r12CheckText -notmatch 'Finished\.' -or $r12CheckText -match '(?im)^\s*Error[:!]') { throw "Read-only $Label failed; no reload or rewrite attempted. See $r12CheckLog" }
    if ($Operation -eq 66 -and $r12CheckText -notmatch 'Verify Flash successfully') { throw "Flash does not verify against R12: $r12CheckLog" }
    if ($Operation -eq 73) {
        $r12CheckCodes=[regex]::Matches($r12CheckText,'(?i)0x534e32[0-9a-f]{2}') | ForEach-Object {$_.Value.ToUpperInvariant()}
        if (-not $r12CheckCodes) { throw "Current UserCode not recognized: $r12CheckLog" }
        $r12CheckReport[$Label]=@($r12CheckCodes | Select-Object -Unique)
    }
    Write-Output "$Label completed: $r12CheckLog"
}
try {
    Invoke-ReadOnlyCheck 73 'current_code_before'
    Invoke-ReadOnlyCheck 66 'flash_compare'
    $r12CheckReport.flash_compare='passed_against_pinned_R12'
    Invoke-ReadOnlyCheck 73 'current_code_after'
    $r12CheckReport.passed=$true
} catch {
    $r12CheckReport.passed=$false
    $r12CheckReport.error=$_.Exception.Message
    throw
} finally {
    $r12CheckReportPath=Join-Path $r12CheckRoot ('output\board\SIN12_FLASH_READONLY_'+$r12CheckStamp+'.json')
    $r12CheckReport | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $r12CheckReportPath -Encoding UTF8
    Write-Output "Read-only report: $r12CheckReportPath"
}
