[CmdletBinding()]
param(
    [Parameter()]
    [string]$Root,

    [Parameter()]
    [string]$ApbxPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$configurationRoot = Join-Path $resolvedRoot 'Configuration'
$failures = New-Object 'System.Collections.Generic.List[string]'
$checks = 0

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)

    $script:failures.Add($Message)
}

function Assert-RequiredFile {
    param([Parameter(Mandatory)][string]$RelativePath)

    $script:checks++
    $path = Join-Path $script:resolvedRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing required file: $RelativePath"
    }
}

function Test-PowerShellSyntax {
    $files = Get-ChildItem -LiteralPath $script:resolvedRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.psm1') }

    foreach ($file in $files) {
        $script:checks++
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$tokens,
            [ref]$errors
        )

        foreach ($parseError in $errors) {
            $relative = $file.FullName.Substring($script:resolvedRoot.Length).TrimStart('\', '/')
            $message = 'PowerShell parse error in {0}:{1}:{2}: {3}' -f @(
                $relative
                $parseError.Extent.StartLineNumber
                $parseError.Extent.StartColumnNumber
                $parseError.Message
            )
            Add-Failure $message
        }
    }
}

function Test-YamlReferences {
    if (-not (Test-Path -LiteralPath $script:configurationRoot -PathType Container)) {
        Add-Failure 'Missing Configuration directory.'
        return
    }

    $taskPattern = '(?i)!task:\s*\{[^}\r\n]*path:\s*[''"](?<path>[^''"]+)[''"]'
    $filePattern = '(?i)(?<path>(?:Executables|Images)[\\/][^\r\n''"]+?\.(?:ps1|psm1|cmd|bat|reg|exe|xml|pow|png|jpg|jpeg|ico|url|lnk))'
    $yamlFiles = Get-ChildItem -LiteralPath $script:configurationRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.yml', '.yaml') }

    foreach ($yamlFile in $yamlFiles) {
        $content = [IO.File]::ReadAllText($yamlFile.FullName)
        $relativeYaml = $yamlFile.FullName.Substring($script:resolvedRoot.Length).TrimStart('\', '/')

        foreach ($match in [regex]::Matches($content, $taskPattern)) {
            $script:checks++
            $relativeTask = $match.Groups['path'].Value -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
            $target = Join-Path $script:configurationRoot $relativeTask
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                Add-Failure "Missing !task reference in ${relativeYaml}: $relativeTask"
            }
        }

        foreach ($match in [regex]::Matches($content, $filePattern)) {
            $script:checks++
            $relativeFile = $match.Groups['path'].Value -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
            $target = Join-Path $script:resolvedRoot $relativeFile
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                Add-Failure "Missing playbook file reference in ${relativeYaml}: $relativeFile"
            }
        }
    }
}

function Test-ApbxArchive {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedApbx = (Resolve-Path -LiteralPath $Path).Path
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = $null

    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($resolvedApbx)
        $entries = @($archive.Entries)
        $entryNames = @($entries | ForEach-Object { $_.FullName -replace '\\', '/' })

        foreach ($required in @('playbook.conf', 'Configuration/custom.yml', 'Configuration/tweaks.yml')) {
            $script:checks++
            if ($required -notin $entryNames) {
                Add-Failure "APBX is missing required entry: $required"
            }
        }

        $script:checks++
        if (-not ($entryNames | Where-Object { $_ -like 'Executables/*' })) {
            Add-Failure 'APBX does not contain an Executables directory.'
        }

        foreach ($entryName in $entryNames) {
            $script:checks++
            if ($entryName.StartsWith('/') -or $entryName -match '(^|/)\.\.(/|$)') {
                Add-Failure "Unsafe APBX entry path: $entryName"
            }
        }

        foreach ($duplicate in $entryNames | Group-Object | Where-Object Count -gt 1) {
            Add-Failure "Duplicate APBX entry: $($duplicate.Name)"
        }
    }
    catch {
        Add-Failure "Unable to read APBX archive '$resolvedApbx': $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

foreach ($requiredFile in @(
    'playbook.conf',
    'Configuration\custom.yml',
    'Configuration\tweaks.yml'
)) {
    Assert-RequiredFile $requiredFile
}

Test-PowerShellSyntax
Test-YamlReferences

if ($PSBoundParameters.ContainsKey('ApbxPath')) {
    Test-ApbxArchive -Path $ApbxPath
}

if ($failures.Count -gt 0) {
    Write-Host "Playbook validation failed with $($failures.Count) error(s):" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Playbook validation passed ($checks checks)." -ForegroundColor Green
exit 0
