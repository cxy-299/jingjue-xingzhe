[CmdletBinding()]
param(
    [ValidateSet('Enable', 'Disable')]
    [string]$Action = 'Enable',
    [string]$InternetConnection = 'WLAN',
    [string]$PiDeviceDescription = 'Realtek PCIe GbE Family Controller',
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'

try {
    if ($LogPath) {
        'SCRIPT_STARTED' | Set-Content -LiteralPath $LogPath -Encoding UTF8
    }
    $manager = New-Object -ComObject HNetCfg.HNetShare
    $connections = @($manager.EnumEveryConnection())

function Find-Connection([string]$name) {
    foreach ($connection in $connections) {
        $properties = $manager.NetConnectionProps.Invoke($connection)
        if ($properties.Name -eq $name) {
            return $connection
        }
    }
    throw "Network connection not found: $name"
}

function Find-ConnectionByDevice([string]$deviceName) {
    foreach ($connection in $connections) {
        $properties = $manager.NetConnectionProps.Invoke($connection)
        if ($properties.DeviceName -eq $deviceName) {
            return $connection
        }
    }
    throw "Network device not found: $deviceName"
}

    $internet = Find-Connection $InternetConnection
    $pi = Find-ConnectionByDevice $PiDeviceDescription
    $internetConfig = $manager.INetSharingConfigurationForINetConnection.Invoke($internet)
    $piConfig = $manager.INetSharingConfigurationForINetConnection.Invoke($pi)

    if ($Action -eq 'Enable') {
        if (-not $internetConfig.SharingEnabled) {
            $internetConfig.EnableSharing(0)
        }
        if (-not $piConfig.SharingEnabled) {
            $piConfig.EnableSharing(1)
        }
        if ($LogPath) {
            'PI_ICS_ENABLED' | Set-Content -LiteralPath $LogPath -Encoding UTF8
        }
        Write-Output 'PI_ICS_ENABLED'
    }
    else {
        if ($piConfig.SharingEnabled) {
            $piConfig.DisableSharing()
        }
        if ($internetConfig.SharingEnabled) {
            $internetConfig.DisableSharing()
        }
        if ($LogPath) {
            'PI_ICS_DISABLED' | Set-Content -LiteralPath $LogPath -Encoding UTF8
        }
        Write-Output 'PI_ICS_DISABLED'
    }
}
catch {
    $details = ($_ | Format-List * -Force | Out-String)
    if ($LogPath) {
        $details | Set-Content -LiteralPath $LogPath -Encoding UTF8
    }
    Write-Error $details
    exit 1
}
