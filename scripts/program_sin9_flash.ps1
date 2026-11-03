param(
    [ValidateSet('Program', 'Verify', 'Reload', 'ReadCode')]
    [string]$Mode = 'Verify',
    [switch]$Driver12VOff
)
$ErrorActionPreference = 'Stop'
if (-not $Driver12VOff) { throw 'Keep motor driver 12V OFF; rerun with -Driver12VOff after checking.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$cliPath = 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe'
$bitstreamPath = Join-Path $projectRoot 'output\board\SIN9_SELECTED_TARGET_2026-10-26.fs'
$expectedHash = 'E11205FCA930BB2A26E0AF79B2EB6905EA01DC9825320E6D3800CC62B0795B95'
if ((Get-FileHash -LiteralPath $bitstreamPath -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Bitstream hash mismatch; no operation performed.'
}
$runStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
function Invoke-Sin9Operation([int]$Index, [string]$Label, [string]$Expected) {
    $logPath = Join-Path $projectRoot "output\board\sin9_flash_${runStamp}_${Label}.log"
    $cliArguments = @('--device', 'GW5AT-60B', '--operation_index', "$Index", '--cable-index', '1', '--frequency', '2.5MHz')
    if ($Index -eq 54 -or $Index -eq 66) { $cliArguments += @('--fsFile', $bitstreamPath) }
    & $cliPath @cliArguments *> $logPath
    $exitCode = $LASTEXITCODE
    $logText = Get-Content -LiteralPath $logPath -Raw
    if ($exitCode -ne 0 -or $logText -notmatch 'Finished\.' -or $logText -notmatch $Expected -or $logText -match '(?im)^\s*Error[:!]') {
        throw "Operation $Label failed; inspect $logPath"
    }
    Write-Output "$Label PASS: $logPath"
    $logText -split "`r?`n" | Where-Object { $_ -match 'Detected Flash|User Code|Status Code|successfully|Cost ' } | Select-Object -Last 8 | Write-Output
}
function Restore-Sin9FromFlash {
    Invoke-Sin9Operation 1 'reload' 'Reprogram'
    # Reprogram returns before serial Flash configuration has completed.
    Start-Sleep -Seconds 12
    Invoke-Sin9Operation 73 'read_code' '0x53494E39'
}
switch ($Mode) {
    'Program' {
        Invoke-Sin9Operation 51 'detect' '0xC22018'
        Invoke-Sin9Operation 54 'program_verify' 'Verify Flash successfully'
        try {
            Invoke-Sin9Operation 66 'independent_verify' 'Verify Flash successfully'
        } catch {
            Write-Warning "First independent verification failed. Log retained; reload and retry verification once, without rewriting Flash. $_"
            Restore-Sin9FromFlash
            Invoke-Sin9Operation 66 'independent_verify_retry' 'Verify Flash successfully'
        }
        Restore-Sin9FromFlash
    }
    'Verify' {
        Invoke-Sin9Operation 66 'independent_verify' 'Verify Flash successfully'
        Restore-Sin9FromFlash
    }
    'Reload' { Restore-Sin9FromFlash }
    'ReadCode' { Invoke-Sin9Operation 73 'read_code' '0x53494E39' }
}
