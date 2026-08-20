[CmdletBinding()]
param(
    [Parameter()]
    [switch]$RequireLinkCreation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RepositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\', '/')
$script:InstallerPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'scripts\install-unity-play-verification-skill.ps1'
$script:SkillSource = Join-Path -Path $script:RepositoryRoot -ChildPath 'skills\codex\unity-play-verification'
$script:ScratchRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('upv-installer-tests-' + [guid]::NewGuid().ToString('N'))
$script:Assertions = 0

# Throws when an installer test condition is false.
function Assert-UpvInstallerTrue {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:Assertions++
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

# Invokes the standalone installer in a child Windows PowerShell process.
function Invoke-UpvInstallerTestProcess {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter()][string[]]$AdditionalArguments = @()
    )

    $previousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:InstallerPath -DestinationRoot $DestinationRoot @AdditionalArguments 2>&1
        )
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorPreference
    }
    return [pscustomobject][ordered]@{
        exitCode = $exitCode
        output = [string]::Join([Environment]::NewLine, [string[]]@($output))
    }
}

# Resolves the single target recorded by an installed symbolic link.
function Get-UpvInstallerTestLinkTarget {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Link
    )

    $target = [string]@($Link.Target)[0]
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path -Path $Link.Parent.FullName -ChildPath $target
    }
    return [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
}

[void][System.IO.Directory]::CreateDirectory($script:ScratchRoot)
try {
    Assert-UpvInstallerTrue -Condition (Test-Path -LiteralPath $script:InstallerPath -PathType Leaf) -Message 'Standalone installer exists'
    Assert-UpvInstallerTrue -Condition (Test-Path -LiteralPath (Join-Path $script:SkillSource 'SKILL.md') -PathType Leaf) -Message 'Only installable Play Skill source exists'

    $whatIfRoot = Join-Path $script:ScratchRoot 'whatif\skills'
    $whatIfFirst = Invoke-UpvInstallerTestProcess -DestinationRoot $whatIfRoot -AdditionalArguments @('-WhatIf')
    $whatIfSecond = Invoke-UpvInstallerTestProcess -DestinationRoot $whatIfRoot -AdditionalArguments @('-WhatIf')
    Assert-UpvInstallerTrue -Condition ($whatIfFirst.exitCode -eq 0) -Message 'First WhatIf succeeds'
    Assert-UpvInstallerTrue -Condition ($whatIfSecond.exitCode -eq 0) -Message 'Repeated WhatIf succeeds'
    Assert-UpvInstallerTrue -Condition (-not (Test-Path -LiteralPath $whatIfRoot)) -Message 'WhatIf creates no destination'
    Assert-UpvInstallerTrue -Condition ($whatIfFirst.output -match 'unity-play-verification') -Message 'WhatIf names only the Play Skill'

    $conflictRoot = Join-Path $script:ScratchRoot 'conflict\skills'
    $conflictPath = Join-Path $conflictRoot 'unity-play-verification'
    [void][System.IO.Directory]::CreateDirectory($conflictPath)
    $sentinel = Join-Path $conflictPath 'preserve.txt'
    [System.IO.File]::WriteAllText($sentinel, 'preserve')
    $conflict = Invoke-UpvInstallerTestProcess -DestinationRoot $conflictRoot
    Assert-UpvInstallerTrue -Condition ($conflict.exitCode -ne 0) -Message 'Existing directory conflict is rejected'
    Assert-UpvInstallerTrue -Condition (Test-Path -LiteralPath $sentinel -PathType Leaf) -Message 'Conflict directory is not changed'
    Assert-UpvInstallerTrue -Condition ($conflict.output -match 'Refusing to replace existing Directory') -Message 'Conflict reports exact entry type'

    $actualRoot = Join-Path $script:ScratchRoot 'actual\skills'
    $firstInstall = Invoke-UpvInstallerTestProcess -DestinationRoot $actualRoot
    if ($firstInstall.exitCode -ne 0) {
        $privilegeFailure = $firstInstall.output -match '(?i)privilege|symbolic link'
        if ($RequireLinkCreation -or -not $privilegeFailure) {
            throw "Actual installer execution failed: $($firstInstall.output)"
        }
        Write-Warning 'Symbolic-link creation check skipped because this token lacks the required Windows privilege.'
    } else {
        $secondInstall = Invoke-UpvInstallerTestProcess -DestinationRoot $actualRoot
        $linkPath = Join-Path $actualRoot 'unity-play-verification'
        $link = Get-Item -LiteralPath $linkPath -Force
        Assert-UpvInstallerTrue -Condition ($secondInstall.exitCode -eq 0) -Message 'Repeated actual install succeeds'
        Assert-UpvInstallerTrue -Condition ($link.LinkType -in @('SymbolicLink', 'Junction')) -Message 'Installer creates a verified filesystem link'
        $actualTarget = Get-UpvInstallerTestLinkTarget -Link $link
        Assert-UpvInstallerTrue -Condition ([System.StringComparer]::OrdinalIgnoreCase.Equals($actualTarget, [System.IO.Path]::GetFullPath($script:SkillSource).TrimEnd('\', '/'))) -Message 'Installed link targets standalone Play Skill'
        Assert-UpvInstallerTrue -Condition ($secondInstall.output -match '\[unchanged\]') -Message 'Repeated install reports unchanged'
    }

    Write-Host "Unity Play Verification installer tests passed. Assertions: $script:Assertions"
} finally {
    if (Test-Path -LiteralPath $script:ScratchRoot -PathType Container) {
        Remove-Item -LiteralPath $script:ScratchRoot -Recurse -Force
    }
}
