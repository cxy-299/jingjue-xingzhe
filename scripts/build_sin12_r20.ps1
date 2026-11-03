param([switch]$PnrOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$activeBuild = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^(gw_sh|gw_syn|gw_pnr|pnr|synthesize)\.exe$'
}
if ($activeBuild) { throw 'An existing Gowin build is active. Do not start a concurrent build.' }
$logPath = Join-Path $projectRoot 'output/board/sin12_hdmi_r20_build.log'
$exitPath = Join-Path $projectRoot 'output/board/sin12_hdmi_r20_build_exit.txt'
if (Test-Path -LiteralPath $logPath) { throw 'Archive the previous R20 log before rebuilding.' }
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'output/board/sin12_hdmi_r20_build_sources.json') -Raw | ConvertFrom-Json
foreach ($entry in $manifest.PSObject.Properties) {
    $actual = (Get-FileHash -LiteralPath (Join-Path $projectRoot $entry.Name) -Algorithm SHA256).Hash
    if ($actual -ne $entry.Value) { throw "Source changed before build: $($entry.Name)" }
}
Set-Content -LiteralPath $exitPath -Value 'RUNNING'
try {
    & 'D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe' $(if ($PnrOnly) {'fpga/sin12_hdmi/build_sin12_hdmi_pnr.tcl'} else {'fpga/sin12_hdmi/build_sin12_hdmi.tcl'}) *> $logPath
    $buildResult = $LASTEXITCODE
    Set-Content -LiteralPath $exitPath -Value $buildResult
    exit $buildResult
} catch {
    Add-Content -LiteralPath $logPath -Value $_
    Set-Content -LiteralPath $exitPath -Value 'RUNNER_ERROR'
    throw
}
