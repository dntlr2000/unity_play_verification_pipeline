[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DestinationRoot = (Join-Path -Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) -ChildPath '.agents\skills')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Returns a stable absolute path without resolving a symbolic-link target.
function Get-UpvInstallerNormalizedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($fullPath, $pathRoot)) {
        return $fullPath
    }
    return $fullPath.TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ))
}

# Finds an existing filesystem entry, including a dangling symbolic link.
function Get-UpvInstallerPathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $parentPath = Split-Path -Parent $LiteralPath
    $leafName = Split-Path -Leaf $LiteralPath
    if ([string]::IsNullOrWhiteSpace($parentPath) -or -not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        return $null
    }
    return Get-ChildItem -LiteralPath $parentPath -Force |
        Where-Object { $_.Name -ieq $leafName } |
        Select-Object -First 1
}

# Confirms that one existing symbolic link or junction targets the exact standalone Skill source.
function Test-UpvInstallerLinkTarget {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Link,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSource
    )

    if ($Link.LinkType -notin @('SymbolicLink', 'Junction')) {
        return $false
    }
    $targets = @($Link.Target)
    if ($targets.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$targets[0])) {
        return $false
    }
    $rawTarget = [string]$targets[0]
    if (-not [System.IO.Path]::IsPathRooted($rawTarget)) {
        $rawTarget = Join-Path -Path $Link.Parent.FullName -ChildPath $rawTarget
    }
    $actualTarget = Get-UpvInstallerNormalizedPath -Path $rawTarget
    $expectedTarget = Get-UpvInstallerNormalizedPath -Path $ExpectedSource
    return [System.StringComparer]::OrdinalIgnoreCase.Equals($actualTarget, $expectedTarget)
}

# Creates the preferred symbolic link and falls back to a local junction only when Windows denies link privilege.
function New-UpvInstallerSkillLink {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )

    try {
        return New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop
    } catch {
        $privilegeDenied =
            $_.FullyQualifiedErrorId -like 'NewItemSymbolicLinkElevationRequired*' -or
            $_.Exception -is [System.UnauthorizedAccessException]
        if (-not $privilegeDenied) {
            throw
        }
        return New-Item -ItemType Junction -Path $Path -Target $Target -ErrorAction Stop
    }
}

$skillName = 'unity-play-verification'
$repositoryRoot = Get-UpvInstallerNormalizedPath -Path (Split-Path -Parent $PSScriptRoot)
$sourcePath = Get-UpvInstallerNormalizedPath -Path (Join-Path -Path $repositoryRoot -ChildPath 'skills\codex\unity-play-verification')
$destinationRootPath = Get-UpvInstallerNormalizedPath -Path $DestinationRoot
$targetPath = Join-Path -Path $destinationRootPath -ChildPath $skillName

foreach ($requiredSource in @(
    $sourcePath,
    (Join-Path -Path $sourcePath -ChildPath 'SKILL.md'),
    (Join-Path -Path $sourcePath -ChildPath 'VERSION'),
    (Join-Path -Path $sourcePath -ChildPath 'scripts\invoke-unity-play-verification.ps1')
)) {
    if (-not (Test-Path -LiteralPath $requiredSource)) {
        throw "Standalone Unity Play Verification source is incomplete: $requiredSource"
    }
}

$sourceEntry = Get-Item -LiteralPath $sourcePath -Force
if (-not $sourceEntry.PSIsContainer -or $sourceEntry.LinkType) {
    throw "Skill source must be a physical directory inside this repository: $sourcePath"
}

$destinationRootEntry = Get-UpvInstallerPathEntry -LiteralPath $destinationRootPath
if ($null -ne $destinationRootEntry) {
    if (-not $destinationRootEntry.PSIsContainer -or $destinationRootEntry.LinkType) {
        throw "Installation root must be a physical directory, not a file or link: $destinationRootPath"
    }
}

$existingEntry = Get-UpvInstallerPathEntry -LiteralPath $targetPath
if ($null -ne $existingEntry) {
    if (Test-UpvInstallerLinkTarget -Link $existingEntry -ExpectedSource $sourcePath) {
        Write-Host "[unchanged] $skillName -> $sourcePath"
        Write-Host 'Install plan processed. Created: 0; unchanged: 1.'
        return
    }
    $existingType = if ($existingEntry.LinkType) {
        [string]$existingEntry.LinkType
    } elseif ($existingEntry.PSIsContainer) {
        'Directory'
    } else {
        'File'
    }
    throw "Refusing to replace existing $existingType at $targetPath; expected a verified filesystem link to $sourcePath."
}

if ($null -eq $destinationRootEntry) {
    if ($PSCmdlet.ShouldProcess($destinationRootPath, 'Create Codex Skill installation directory')) {
        New-Item -ItemType Directory -Path $destinationRootPath -Force | Out-Null
    }
}

$created = $false
if ($PSCmdlet.ShouldProcess($targetPath, "Create filesystem link to $sourcePath")) {
    $createdEntry = New-UpvInstallerSkillLink -Path $targetPath -Target $sourcePath
    $created = $true
}

if ($created) {
    $installedEntry = Get-UpvInstallerPathEntry -LiteralPath $targetPath
    if ($null -eq $installedEntry -or -not (Test-UpvInstallerLinkTarget -Link $installedEntry -ExpectedSource $sourcePath)) {
        throw "Installed Skill link verification failed: $targetPath"
    }
    Write-Host "[linked:$($createdEntry.LinkType)] $skillName -> $sourcePath"
}
Write-Host ("Install plan processed. Created: {0}; unchanged: 0." -f $(if ($created) { 1 } else { 0 }))
