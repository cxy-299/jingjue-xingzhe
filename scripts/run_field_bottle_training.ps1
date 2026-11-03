param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$evidenceRoot = Join-Path $projectRoot 'output/board/bottle_training_20261030'
$python = Join-Path $projectRoot '.venv-train/Scripts/python.exe'
$lockPath = Join-Path $evidenceRoot 'training.lock'
$lockStream = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $active = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match '-m\s+scripts\.train_field_bottle' }
    if ($active) { throw 'An existing field-bottle training process is active.' }
    $freeze = Get-Content -LiteralPath (Join-Path $evidenceRoot 'training_inputs.json') -Raw | ConvertFrom-Json
    foreach ($entry in $freeze.PSObject.Properties) {
        $actual = (Get-FileHash -LiteralPath (Join-Path $projectRoot $entry.Name) -Algorithm SHA256).Hash
        if ($actual -ne $entry.Value) { throw ('Frozen input changed: ' + $entry.Name) }
    }
    $gpu = Get-Content -LiteralPath (Join-Path $evidenceRoot 'gpu_preflight.json') -Raw | ConvertFrom-Json
    if (-not $gpu.forward_backward_passed -or $gpu.torch -ne '2.7.1+cu128' -or $gpu.ultralytics -ne '8.3.0') { throw 'GPU preflight did not pass for the fixed environment.' }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $invocationDir = Join-Path $evidenceRoot ('training_' + $stamp)
    New-Item -ItemType Directory -Path $invocationDir | Out-Null
    $arguments = @('-u', '-m', 'scripts.train_field_bottle', '--data', 'data/field_bottle/releases/20261030T130347043259Z/dataset.yaml', '--device', '0', '--run')
    $record = [ordered]@{ started_at = (Get-Date -Format o); interpreter = $python; arguments = $arguments; wrapper_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash; state = 'RUNNING'; exit_code = $null }
    $recordPath = Join-Path $invocationDir 'execution.json'
    [System.IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 6))
    Write-Output ('Training evidence: ' + $invocationDir)
    $process = Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $invocationDir 'stdout.log') -RedirectStandardError (Join-Path $invocationDir 'stderr.log') -PassThru
    # Retain the native handle before exit so Windows can retrieve the code.
    $null = $process.Handle
    $record['pid'] = $process.Id
    [System.IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 6))
    $process.WaitForExit()
    $process.Refresh()
    $record['exit_code'] = $process.ExitCode
    $record['state'] = if ($null -eq $process.ExitCode) { 'EXIT_UNKNOWN' } elseif ($process.ExitCode -eq 0) { 'COMPLETED' } else { 'FAILED' }
    $record['finished_at'] = Get-Date -Format o
    [System.IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 6))
    Write-Output ($record | ConvertTo-Json -Depth 6)
    exit $process.ExitCode
}
finally {
    $lockStream.Dispose()
}
