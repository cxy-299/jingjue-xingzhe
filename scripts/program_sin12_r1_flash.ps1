param(
    [ValidateSet('ValidateFiles', 'Program', 'Verify', 'Reload', 'ReadCode')]
    [string]$Mode = 'ValidateFiles',
    [switch]$Driver12VOff,
    [switch]$WheelsRaised,
    [switch]$OffgroundAccepted
)
$ErrorActionPreference = 'Stop'
$sin12FlashRoot = Split-Path -Parent $PSScriptRoot
$sin12FlashArchive = Join-Path $sin12FlashRoot 'output\board\sin12_r1_map2613_2026-10-27'
$sin12FlashManifest = Get-Content -LiteralPath (Join-Path $sin12FlashArchive 'qualification.json') -Raw | ConvertFrom-Json
$sin12FlashExpectedHash = 'AE6812CAA8B3B927076F3D2F95E56883CE514631454846C9F94DF9398E0AB2A4'
$sin12FlashFs = Join-Path $sin12FlashArchive 'acg720_motor_bt_autonav.fs'
if (-not $sin12FlashManifest.internal_timing_qualified -or $sin12FlashManifest.user_code -ne '0x534E3241' -or
    $sin12FlashManifest.map_id -ne '0x2613' -or $sin12FlashManifest.setup_violations -ne 0 -or
    $sin12FlashManifest.hold_violations -ne 0 -or $sin12FlashManifest.fmax_mhz -lt 50 -or
    $sin12FlashManifest.sha256.'acg720_motor_bt_autonav.fs' -ne $sin12FlashExpectedHash -or
    (Get-FileHash -LiteralPath $sin12FlashFs -Algorithm SHA256).Hash -ne $sin12FlashExpectedHash) {
    throw 'SIN12 R1 qualification or pinned bitstream hash mismatch; no hardware operation performed.'
}
if ($Mode -eq 'ValidateFiles') {
    Write-Output 'SIN12 R1 files valid: 0x534E3241, map0x2613; no hardware operation performed.'
    return
}
if ($Mode -eq 'Program') {
    $sin12FlashAcceptancePath = Join-Path $sin12FlashRoot 'output\board\SIN12_R1_HARDWARE_VALIDATION_2026-10-28.json'
    if (Test-Path -LiteralPath $sin12FlashAcceptancePath) {
        $sin12FlashAcceptance = Get-Content -LiteralPath $sin12FlashAcceptancePath -Raw | ConvertFrom-Json
        if ($sin12FlashAcceptance.release_promotion_blocked) {
            throw 'R1 promotion blocked by recorded M1/M3 test faults. Use a qualified, accepted replacement release; no hardware operation performed.'
        }
    }
}
if (-not $Driver12VOff) { throw 'Confirm actual motor driver 12V OFF before accessing hardware.' }
if ($Mode -eq 'Program' -and (-not $WheelsRaised -or -not $OffgroundAccepted)) {
    throw 'Program requires actual wheels raised and completed SIN12 R1 off-ground acceptance.'
}
$sin12FlashCli = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$sin12FlashStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
function Invoke-Sin12FlashOperation([int]$Index, [string]$Label, [string]$Expected) {
    $sin12OperationLog = Join-Path $sin12FlashRoot "output\board\sin12_r1_flash_${sin12FlashStamp}_${Label}.log"
    $sin12OperationArgs = @('--device','GW5AT-60B','--operation_index',"$Index",'--cable-index','1','--frequency','2.5MHz')
    if ($Index -eq 54 -or $Index -eq 66) { $sin12OperationArgs += @('--fsFile', $sin12FlashFs) }
    & $sin12FlashCli @sin12OperationArgs *> $sin12OperationLog
    $sin12OperationExit = $LASTEXITCODE
    $sin12OperationText = Get-Content -LiteralPath $sin12OperationLog -Raw
    if ($sin12OperationExit -ne 0 -or $sin12OperationText -notmatch 'Finished\.' -or
        $sin12OperationText -notmatch $Expected -or $sin12OperationText -match '(?im)^\s*Error[:!]') {
        throw "Operation $Label failed; inspect $sin12OperationLog. No automatic rewrite or retry."
    }
    Write-Output "$Label PASS: $sin12OperationLog"
}
function Reload-Sin12Flash {
    Invoke-Sin12FlashOperation 1 'reload' 'Reprogram'
    Start-Sleep -Seconds 12
    Invoke-Sin12FlashOperation 73 'read_code' '0x534[Ee]3241'
}
switch ($Mode) {
    'Program' {
        Invoke-Sin12FlashOperation 51 'detect' '0xC22018'
        Invoke-Sin12FlashOperation 54 'program_verify' 'Verify Flash successfully'
        Invoke-Sin12FlashOperation 66 'independent_verify' 'Verify Flash successfully'
        Reload-Sin12Flash
    }
    'Verify' { Invoke-Sin12FlashOperation 66 'independent_verify' 'Verify Flash successfully' }
    'Reload' { Reload-Sin12Flash }
    'ReadCode' { Invoke-Sin12FlashOperation 73 'read_code' '0x534[Ee]3241' }
}
# Readback is JTAG reload evidence only. Physical power-cycle acceptance is manual.
# This script never marks off-ground or ground test results as passed.
