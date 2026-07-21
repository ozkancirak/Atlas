#Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet(0, 1)]
    [int]$Disabled
)

$ErrorActionPreference = 'Stop'

$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\MRT'
$policyValue = 'DontOfferThroughWUAU'

function Remove-MsrtExecutable {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    Get-Process -Name 'MRT' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        $takeOwn = Join-Path $env:SystemRoot 'System32\takeown.exe'
        $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'

        & $takeOwn /F $Path /A | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to take ownership of $Path."
        }

        & $icacls $Path '/grant' '*S-1-5-32-544:(F)' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to grant Administrators access to $Path."
        }

        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        throw "Failed to remove $Path."
    }
}

if ($Disabled -eq 1) {
    New-Item -Path $policyPath -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name $policyValue -PropertyType DWord -Value 1 -Force | Out-Null

    @(
        (Join-Path $env:SystemRoot 'System32\MRT.exe'),
        (Join-Path $env:SystemRoot 'SysWOW64\MRT.exe')
    ) | ForEach-Object {
        Remove-MsrtExecutable -Path $_
    }
} else {
    Remove-ItemProperty -Path $policyPath -Name $policyValue -ErrorAction SilentlyContinue
}
