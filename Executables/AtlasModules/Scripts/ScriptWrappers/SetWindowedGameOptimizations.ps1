#Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [ValidateSet(0, 1)]
    [int]$Enabled = 1,
    [switch]$IncludeDefaultUser
)

$ErrorActionPreference = 'Stop'

function Set-WindowedGameOptimizationState {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet(0, 1)]
        [int]$State
    )

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }

    $valueName = 'DirectXUserGlobalSettings'
    $property = Get-ItemProperty -LiteralPath $RegistryPath -Name $valueName -ErrorAction SilentlyContinue
    $existingValue = if ($null -eq $property) { '' } else { [string]$property.$valueName }
    $updatedTokens = @(($existingValue -split ';') |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            $_ -notmatch '^\s*SwapEffectUpgradeEnable\s*='
        } |
        ForEach-Object { $_.Trim() })

    $updatedValue = (($updatedTokens + "SwapEffectUpgradeEnable=$State") -join ';') + ';'
    New-ItemProperty -LiteralPath $RegistryPath -Name $valueName -PropertyType String -Value $updatedValue -Force | Out-Null
}

Set-WindowedGameOptimizationState -RegistryPath 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -State $Enabled

if ($IncludeDefaultUser) {
    $defaultUserHive = 'Registry::HKEY_USERS\AME_UserHive_Default'
    if (-not (Test-Path -LiteralPath $defaultUserHive)) {
        throw 'Default User hive is not loaded.'
    }

    Set-WindowedGameOptimizationState -RegistryPath "$defaultUserHive\Software\Microsoft\DirectX\UserGpuPreferences" -State $Enabled
}
