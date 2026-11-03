param([string]$GowinShell=$env:GOWIN_GW_SH)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
if(-not $GowinShell){$cmd=Get-Command gw_sh.exe -ErrorAction SilentlyContinue;if($cmd){$GowinShell=$cmd.Source}}
if(-not $GowinShell -or -not (Test-Path -LiteralPath $GowinShell)){throw 'Supply -GowinShell pointing to your Gowin IDE bin/gw_sh.exe'}
$active=Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^(gw_sh|gw_syn|gw_pnr|pnr|synthesize)\.exe$'}
if($active){throw 'An active Gowin build exists; do not run concurrently.'}
Push-Location -LiteralPath $projectRoot
try{& $GowinShell 'fpga/sin12_hdmi/build_sin12_hdmi.tcl';exit $LASTEXITCODE}finally{Pop-Location}
