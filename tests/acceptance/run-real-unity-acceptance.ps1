[CmdletBinding()]
param(
    [Parameter()]
    [AllowNull()]
    [string]$ArtifactsRoot,

    [Parameter()]
    [ValidateRange(60, 86400)]
    [int]$TimeoutSeconds = 1800,

    [Parameter()]
    [AllowNull()]
    [string[]]$UnityVersions,

    [Parameter()]
    [AllowNull()]
    [string[]]$CaseNames,

    [Parameter()]
    [switch]$DiscoverPackageIdentities
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:RepositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $PSScriptRoot))).TrimEnd('\', '/')
$script:RunnerPath = Join-Path $script:RepositoryRoot 'skills\codex\unity-play-verification\scripts\invoke-unity-play-verification.ps1'
$script:ScenarioPath = Join-Path $script:RepositoryRoot 'skills\codex\unity-play-verification\templates\minimal-scenario'
$script:FingerprintPath = Join-Path $script:RepositoryRoot 'skills\codex\unity-play-verification\scripts\vendor\doctor\lib\unity-project-fingerprint.ps1'
$script:SchemaValidatorPath = Join-Path $script:RepositoryRoot 'skills\codex\unity-play-verification\scripts\vendor\shared\json-schema-validator.ps1'
$script:CorePath = Join-Path $script:RepositoryRoot 'skills\codex\unity-play-verification\scripts\lib\unity-play-verification-core.ps1'
$script:IdentityPath = Join-Path $script:RepositoryRoot 'skills\codex\unity-play-verification\scripts\lib\unity-test-framework-identity.ps1'
$script:ProcessJobPath = Join-Path $script:RepositoryRoot 'skills\codex\unity-play-verification\scripts\vendor\shared\unity-process-job.ps1'
$script:ResultSchemaPath = Join-Path $script:RepositoryRoot 'schemas\unity-play-verification-result-1.0.0.schema.json'
$script:AcceptanceRoot = if ([string]::IsNullOrWhiteSpace($ArtifactsRoot)) {
    Join-Path ([System.IO.Path]::GetTempPath()) ('upv-real-acceptance-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
} else {
    [System.IO.Path]::GetFullPath($ArtifactsRoot)
}

. $script:FingerprintPath
. $script:SchemaValidatorPath
. $script:CorePath
. $script:IdentityPath
. $script:ProcessJobPath

# Writes one acceptance fixture file using UTF-8 without a byte-order mark.
function Write-AcceptanceText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    [void][System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

# Creates a minimal source project for one exact Unity and Test Framework pair.
function New-AcceptanceProject {
    param(
        [Parameter(Mandatory = $true)][object]$Configuration
    )

    $root = Join-Path $script:AcceptanceRoot ('sources\' + $Configuration.unityVersion)
    [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'Assets\Tests\PlayMode'))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'Packages'))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'ProjectSettings'))
    Write-AcceptanceText -Path (Join-Path $root 'ProjectSettings\ProjectVersion.txt') -Content (
        "m_EditorVersion: $($Configuration.unityVersion)`r`n" +
        "m_EditorVersionWithRevision: $($Configuration.unityVersion) ($($Configuration.revision))`r`n"
    )
    Write-AcceptanceText -Path (Join-Path $root 'ProjectSettings\EditorBuildSettings.asset') -Content "%YAML 1.1`r`n--- !u!1045 &1`r`nEditorBuildSettings:`r`n  m_ObjectHideFlags: 0`r`n  serializedVersion: 2`r`n  m_Scenes: []`r`n"

    $manifest = [ordered]@{
        dependencies = [ordered]@{
            'com.unity.test-framework' = $Configuration.testFrameworkVersion
            'com.unity.modules.screencapture' = '1.0.0'
        }
    }
    $testDependencies = [ordered]@{
        'com.unity.ext.nunit' = $Configuration.nunitVersion
        'com.unity.modules.imgui' = '1.0.0'
        'com.unity.modules.jsonserialize' = '1.0.0'
    }
    $testEntry = [ordered]@{
        version = $Configuration.testFrameworkVersion
        depth = 0
        source = $Configuration.testFrameworkSource
        dependencies = $testDependencies
    }
    if ($Configuration.testFrameworkSource -eq 'registry') {
        $testEntry.url = 'https://packages.unity.com'
    }
    $lockDependencies = [ordered]@{
        'com.unity.ext.nunit' = [ordered]@{
            version = $Configuration.nunitVersion
            depth = 1
            source = $Configuration.nunitSource
            dependencies = [ordered]@{}
        }
        'com.unity.modules.imgui' = [ordered]@{
            version = '1.0.0'
            depth = 1
            source = 'builtin'
            dependencies = [ordered]@{}
        }
        'com.unity.modules.jsonserialize' = [ordered]@{
            version = '1.0.0'
            depth = 1
            source = 'builtin'
            dependencies = [ordered]@{}
        }
        'com.unity.modules.imageconversion' = [ordered]@{
            version = '1.0.0'
            depth = 1
            source = 'builtin'
            dependencies = [ordered]@{}
        }
        'com.unity.modules.screencapture' = [ordered]@{
            version = '1.0.0'
            depth = 0
            source = 'builtin'
            dependencies = [ordered]@{
                'com.unity.modules.imageconversion' = '1.0.0'
            }
        }
        'com.unity.test-framework' = $testEntry
    }
    if ($Configuration.nunitSource -eq 'registry') {
        $lockDependencies.'com.unity.ext.nunit'.url = 'https://packages.unity.com'
    }
    $lock = [ordered]@{ dependencies = $lockDependencies }
    Write-AcceptanceText -Path (Join-Path $root 'Packages\manifest.json') -Content (ConvertTo-Json $manifest -Depth 10)
    Write-AcceptanceText -Path (Join-Path $root 'Packages\packages-lock.json') -Content (ConvertTo-Json $lock -Depth 10)

    $asmdef = @'
{
  "name": "Upv.Acceptance.Tests",
  "rootNamespace": "Upv.Acceptance",
  "references": [],
  "includePlatforms": [],
  "excludePlatforms": [],
  "allowUnsafeCode": false,
  "overrideReferences": false,
  "precompiledReferences": [],
  "autoReferenced": true,
  "defineConstraints": [],
  "versionDefines": [],
  "noEngineReferences": false,
  "optionalUnityReferences": ["TestAssemblies"]
}
'@
    $tests = @'
using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace Upv.Acceptance
{
    /// <summary>Provides deterministic pass, fail, skip, and inconclusive PlayMode acceptance cases.</summary>
    public sealed class AcceptanceTests
    {
        /// <summary>Proves a coroutine test executes across multiple Editor PlayMode frames.</summary>
        [UnityTest]
        public IEnumerator PassesAcrossFrames()
        {
            var startingFrame = Time.frameCount;
            yield return null;
            yield return null;
            Assert.Greater(Time.frameCount, startingFrame);
            Assert.IsTrue(Application.isPlaying);
        }

        /// <summary>Produces a deliberate complete NUnit failure for classification acceptance.</summary>
        [UnityTest]
        public IEnumerator FailsDeliberately()
        {
            yield return null;
            Assert.Fail("Intentional Unity Play Verification acceptance failure.");
        }

        /// <summary>Produces a deliberate ignored test for strict completeness acceptance.</summary>
        [UnityTest, Ignore("Intentional Unity Play Verification acceptance skip.")]
        public IEnumerator SkipsDeliberately()
        {
            yield return null;
        }

        /// <summary>Produces a deliberate inconclusive result for strict completeness acceptance.</summary>
        [UnityTest]
        public IEnumerator IsInconclusiveDeliberately()
        {
            yield return null;
            Assert.Inconclusive("Intentional Unity Play Verification acceptance inconclusive result.");
        }
    }
}
'@
    Write-AcceptanceText -Path (Join-Path $root 'Assets\Tests\PlayMode\Upv.Acceptance.Tests.asmdef') -Content $asmdef
    Write-AcceptanceText -Path (Join-Path $root 'Assets\Tests\PlayMode\AcceptanceTests.cs') -Content $tests
    return $root
}

# Creates one source-only scenario bundle whose C# intentionally fails isolated compilation.
function New-AcceptanceCompileFailureScenario {
    $root = Join-Path $script:AcceptanceRoot 'scenario-bundles\compile-failure'
    if (Test-Path -LiteralPath $root -PathType Container) {
        return $root
    }
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $root))
    Copy-Item -LiteralPath $script:ScenarioPath -Destination $root -Recurse -Force
    $sourcePath = Join-Path $root 'SampleScenarioTests.cs'
    $source = Get-Content -Raw -LiteralPath $sourcePath
    Write-AcceptanceText -Path $sourcePath -Content ($source + [Environment]::NewLine + 'this is intentionally invalid C#;')
    return $root
}

# Verifies the exact version and Unity Technologies signature of one acceptance Editor.
function Get-AcceptanceEditorTrust {
    param(
        [Parameter(Mandatory = $true)][string]$UnityExecutable,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion
    )

    $path = Get-UpvNormalizedPath -Path $UnityExecutable
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required acceptance editor is missing: $path"
    }
    if ([System.IO.Path]::GetFileName($path) -ine 'Unity.exe') {
        throw 'Acceptance editor must be named Unity.exe.'
    }
    $reparsePoint = Get-UpvReparsePointOnPath -Path $path
    if ($null -ne $reparsePoint) {
        throw "Acceptance editor path traverses reparse point $reparsePoint."
    }

    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    $productVersion = [string]$item.VersionInfo.ProductVersion
    $match = [regex]::Match($productVersion, '^(?<version>\d+\.\d+\.\d+[abfp]\d+)(?:_|$|\s)')
    if (-not $match.Success -or $match.Groups['version'].Value -cne $ExpectedVersion) {
        throw "Acceptance editor ProductVersion '$productVersion' does not match '$ExpectedVersion'."
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
    $signerSubject = if ($null -eq $signature.SignerCertificate) { $null } else { [string]$signature.SignerCertificate.Subject }
    if ([string]$signature.Status -cne 'Valid') {
        throw "Acceptance editor signature status is $($signature.Status), not Valid."
    }
    if (-not [regex]::IsMatch([string]$signerSubject, '(?i)\bUnity Technologies\b')) {
        throw 'Acceptance editor signer does not identify Unity Technologies.'
    }

    return [pscustomobject][ordered]@{
        path = $path
        productVersion = $productVersion
        detectedVersion = $match.Groups['version'].Value
        sha256 = Get-UpvFileSha256 -Path $path
        signatureStatus = [string]$signature.Status
        signerSubject = $signerSubject
        certificateThumbprint = if ($null -eq $signature.SignerCertificate) { $null } else { [string]$signature.SignerCertificate.Thumbprint }
    }
}

# Locates and hashes exactly one resolved Test Framework package for approval discovery.
function Get-AcceptanceResolvedPackageIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion
    )

    $cacheRoot = Join-Path (Get-UpvNormalizedPath -Path $ProjectRoot) 'Library\PackageCache'
    if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
        throw 'Identity discovery did not produce Library/PackageCache.'
    }
    $candidates = New-Object System.Collections.ArrayList
    foreach ($directory in @(Get-ChildItem -LiteralPath $cacheRoot -Directory -Force -ErrorAction Stop)) {
        $packageJsonPath = Join-Path $directory.FullName 'package.json'
        if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
            continue
        }
        $packageJson = Read-UpvJsonFile -Path $packageJsonPath
        if ([string](Get-UpvJsonProperty -InputObject $packageJson -Name 'name') -ceq 'com.unity.test-framework') {
            [void]$candidates.Add([pscustomobject][ordered]@{
                path = $directory.FullName
                packageJson = $packageJson
            })
        }
    }
    if ($candidates.Count -ne 1) {
        throw "Identity discovery requires exactly one resolved com.unity.test-framework package; found $($candidates.Count)."
    }
    $candidate = $candidates[0]
    $resolvedVersion = [string](Get-UpvJsonProperty -InputObject $candidate.packageJson -Name 'version')
    if ($resolvedVersion -cne $ExpectedVersion) {
        throw "Identity discovery resolved Test Framework '$resolvedVersion', not '$ExpectedVersion'."
    }
    $snapshot = Get-UpvPackageTreeSnapshot -PackageRoot $candidate.path
    return [pscustomobject][ordered]@{
        packageName = 'com.unity.test-framework'
        resolvedVersion = $resolvedVersion
        resolvedPackagePath = $snapshot.root
        fileCount = $snapshot.fileCount
        hashCanonicalization = $snapshot.canonicalization
        packageTreeSha256 = $snapshot.treeSha256
    }
}

# Resolves each approved registry or Editor-builtin package with its signed Editor and writes reproducible identity evidence.
function Invoke-AcceptanceIdentityDiscovery {
    param(
        [Parameter(Mandatory = $true)][object[]]$Configurations
    )

    $discoveries = New-Object System.Collections.ArrayList
    foreach ($configuration in $Configurations) {
        if ($null -ne $UnityVersions -and $UnityVersions.Count -gt 0 -and $configuration.unityVersion -notin $UnityVersions) {
            continue
        }
        Write-Host "Resolving approved Test Framework identity: $($configuration.unityVersion)/$($configuration.testFrameworkVersion)/$($configuration.testFrameworkSource)"
        $trust = Get-AcceptanceEditorTrust -UnityExecutable $configuration.unityExecutable -ExpectedVersion $configuration.unityVersion
        if ($trust.sha256 -cne $configuration.unityExecutableSha256) {
            throw "Acceptance Editor SHA-256 for $($configuration.unityVersion) differs from the approved identity."
        }
        $project = New-AcceptanceProject -Configuration $configuration
        $runRoot = Join-Path $script:AcceptanceRoot ("identity-discovery\" + $configuration.unityVersion)
        [void][System.IO.Directory]::CreateDirectory($runRoot)
        $stdoutPath = Join-Path $runRoot 'stdout.log'
        $stderrPath = Join-Path $runRoot 'stderr.log'
        $editorLogPath = Join-Path $runRoot 'Editor.log'
        $upmLogPath = Join-Path $runRoot 'upm.log'
        $arguments = @(
            '-batchmode',
            '-forgetProjectPath',
            '-projectPath', $project,
            '-quit',
            '-logFile', $editorLogPath,
            '-upmLogFile', $upmLogPath
        )
        $process = Invoke-UnityProcessInJob `
            -ExecutablePath $trust.path `
            -Arguments $arguments `
            -WorkingDirectory $runRoot `
            -StandardOutputPath $stdoutPath `
            -StandardErrorPath $stderrPath `
            -TimeoutSeconds $TimeoutSeconds
        if (
            -not $process.processStarted -or $process.timedOut -or
            -not $process.processTreeExitVerified -or $null -eq $process.exitCode -or [long]$process.exitCode -ne 0
        ) {
            throw "Identity discovery Unity process failed for $($configuration.unityVersion). See $editorLogPath"
        }

        $provenance = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $project -AllowedSourceKinds ([string[]]@($configuration.testFrameworkSource))
        $identity = Get-AcceptanceResolvedPackageIdentity -ProjectRoot $project -ExpectedVersion $configuration.testFrameworkVersion
        [void]$discoveries.Add([pscustomobject][ordered]@{
            status = if ($provenance.accepted) { 'APPROVED_SOURCE_RESOLVED' } else { 'SOURCE_REJECTED' }
            unityVersion = $configuration.unityVersion
            testFrameworkVersion = $configuration.testFrameworkVersion
            requestedSourceKind = $configuration.testFrameworkSource
            resolvedSourceKind = $provenance.packagesLockSource
            registryOrigin = $provenance.registryOrigin
            provenanceAccepted = $provenance.accepted
            provenanceErrors = @($provenance.errors)
            packageTreeSha256 = $identity.packageTreeSha256
            hashCanonicalization = $identity.hashCanonicalization
            fileCount = $identity.fileCount
            resolvedPackagePath = $identity.resolvedPackagePath
            manifestSha256 = Get-UpvFileSha256 -Path (Join-Path $project 'Packages\manifest.json')
            packagesLockSha256 = Get-UpvFileSha256 -Path (Join-Path $project 'Packages\packages-lock.json')
            sourceEvidence = @($provenance.sourceEvidence)
            unity = $trust
            process = $process
            editorLogPath = $editorLogPath
            editorLogSha256 = Get-UpvFileSha256 -Path $editorLogPath
            upmLogPath = $upmLogPath
            upmLogExists = Test-Path -LiteralPath $upmLogPath -PathType Leaf
            upmLogSha256 = if (Test-Path -LiteralPath $upmLogPath -PathType Leaf) { Get-UpvFileSha256 -Path $upmLogPath } else { $null }
        })
        Write-Host "Resolved source/hash: $($provenance.packagesLockSource) / $($identity.packageTreeSha256)"
    }
    if ($discoveries.Count -eq 0) {
        throw 'Identity discovery filters selected zero Unity configurations.'
    }
    $summary = [ordered]@{
        schemaVersion = '1.0.0'
        discoveryStatus = if (@($discoveries | Where-Object { $_.status -eq 'SOURCE_REJECTED' }).Count -gt 0) { 'COMPLETE_WITH_REJECTIONS' } else { 'COMPLETE' }
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        artifactRoot = $script:AcceptanceRoot
        entries = @($discoveries)
    }
    $summaryPath = Join-Path $script:AcceptanceRoot 'package-identity-discovery.json'
    Write-AcceptanceText -Path $summaryPath -Content (ConvertTo-Json $summary -Depth 15)
    Write-Host "Package identity discovery complete: $summaryPath"
    return $summaryPath
}

# Invokes one production verifier case and returns its parsed result and raw JSON.
function Invoke-AcceptanceCase {
    param(
        [Parameter(Mandatory = $true)][object]$Configuration,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$CaseName,
        [Parameter(Mandatory = $true)][string]$ExpectedStatus,
        [Parameter()][AllowNull()][string]$TestFilter,
        [Parameter()][AllowNull()][string]$ScenarioBundlePath
    )

    $caseRoot = Join-Path $script:AcceptanceRoot ("runs\$($Configuration.unityVersion)\$CaseName")
    [void][System.IO.Directory]::CreateDirectory($caseRoot)
    $arguments = @(
        '-ProjectRoot', $ProjectRoot,
        '-UnityExecutable', $Configuration.unityExecutable,
        '-ArtifactsRoot', $caseRoot,
        '-TimeoutSeconds', [string]$TimeoutSeconds
    )
    if (-not [string]::IsNullOrWhiteSpace($ScenarioBundlePath)) {
        $arguments += @('-ScenarioBundlePath', $ScenarioBundlePath)
    } elseif (-not [string]::IsNullOrWhiteSpace($TestFilter)) {
        $arguments += @('-TestFilter', $TestFilter)
    }

    $process = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:RunnerPath @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Verifier process failed for $($Configuration.unityVersion)/$CaseName with exit $LASTEXITCODE."
    }
    $raw = [string]::Join([Environment]::NewLine, [string[]]@($process)).Trim()
    $result = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
    $schemaErrors = @(Invoke-JsonSchemaValidation -Instance $result -SchemaPath $script:ResultSchemaPath)
    if ($schemaErrors.Count -gt 0) {
        throw "Acceptance $($Configuration.unityVersion)/$CaseName returned schema-invalid JSON: $([string]::Join('; ', [string[]]@($schemaErrors | ForEach-Object { $_.message })))"
    }
    if ($result.finalStatus -cne $ExpectedStatus) {
        throw "Acceptance $($Configuration.unityVersion)/$CaseName expected $ExpectedStatus but returned $($result.finalStatus). Result: $($result.artifacts.resultPath)"
    }
    if ($Configuration.approvalExpected) {
        $expectedOrigin = if ($Configuration.testFrameworkSource -ceq 'registry') { 'https://packages.unity.com' } else { $null }
        $preflightOriginMatched = if ($null -eq $expectedOrigin) {
            $null -eq $result.compatibility.provenance.registryOrigin
        } else {
            [string]$result.compatibility.provenance.registryOrigin -ceq $expectedOrigin
        }
        $postRunOriginMatched = if ($null -eq $expectedOrigin) {
            $null -eq $result.compatibility.postRunProvenance.registryOrigin
        } else {
            [string]$result.compatibility.postRunProvenance.registryOrigin -ceq $expectedOrigin
        }
        if (
            $result.compatibility.verificationStatus -cne 'VERIFIED_SUCCESS' -or
            -not [bool]$result.compatibility.provenance.accepted -or
            -not [bool]$result.compatibility.postRunProvenance.accepted -or
            [string]$result.compatibility.allowedSourceKind -cne $Configuration.testFrameworkSource -or
            [string]$result.compatibility.provenance.packagesLockSource -cne $Configuration.testFrameworkSource -or
            [string]$result.compatibility.postRunProvenance.packagesLockSource -cne $Configuration.testFrameworkSource -or
            -not $preflightOriginMatched -or
            -not $postRunOriginMatched -or
            [string]$result.unity.executableSha256 -cne $Configuration.unityExecutableSha256 -or
            -not [bool]$result.compatibility.packageIdentity.identityMatched -or
            -not [bool]$result.compatibility.packageIdentity.accepted -or
            [string]$result.compatibility.packageIdentity.treeSha256 -cne [string]$result.compatibility.packageIdentity.expectedTreeSha256
        ) {
            throw "Acceptance $($Configuration.unityVersion)/$CaseName lacks complete source-specific Test Framework and Unity Editor identity evidence."
        }
    } else {
        if ([bool]$result.unity.processStarted -or $result.compatibility.verificationStatus -cne 'BLOCKED') {
            throw "Source-policy-blocked pair $($Configuration.unityVersion)/$CaseName did not fail closed before Unity."
        }
    }
    if ($result.originalProjectIntegrity.status -cne 'UNCHANGED') {
        throw "Acceptance $($Configuration.unityVersion)/$CaseName changed the source project."
    }
    if ($result.gitMetadataIntegrity.status -notin @('NOT_PRESENT', 'UNCHANGED', 'AMBIENT_CODEX_CHECKPOINTS_ONLY')) {
        throw "Acceptance $($Configuration.unityVersion)/$CaseName violated Git metadata integrity."
    }
    if ($Configuration.approvalExpected -and $CaseName -eq 'scenario') {
        $screenshots = @($result.scenario.screenshots)
        if ($screenshots.Count -ne 1 -or -not $screenshots[0].exists -or [long]$screenshots[0].byteLength -le 0 -or [string]$screenshots[0].sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Acceptance $($Configuration.unityVersion)/scenario lacks complete PNG evidence."
        }
    }
    return [pscustomobject][ordered]@{
        unityVersion = $Configuration.unityVersion
        testFrameworkVersion = $Configuration.testFrameworkVersion
        caseName = $CaseName
        expectedStatus = $ExpectedStatus
        actualStatus = $result.finalStatus
        resultPath = $result.artifacts.resultPath
        resultSha256 = (Get-FileHash -LiteralPath $result.artifacts.resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
        testTotal = $result.nunit.total
        testPassed = $result.nunit.passed
        testFailed = $result.nunit.failed
        testSkipped = $result.nunit.skipped
        testInconclusive = $result.nunit.inconclusive
        originalIntegrity = $result.originalProjectIntegrity.status
        gitIntegrity = $result.gitMetadataIntegrity.status
        processStarted = $result.unity.processStarted
        compatibilityStatus = $result.compatibility.verificationStatus
        preflightSource = $result.compatibility.provenance.packagesLockSource
        postRunSource = $result.compatibility.postRunProvenance.packagesLockSource
        packageTreeSha256 = $result.compatibility.packageIdentity.treeSha256
        expectedPackageTreeSha256 = $result.compatibility.packageIdentity.expectedTreeSha256
        packageIdentityMatched = $result.compatibility.packageIdentity.identityMatched
        screenshotCount = @($result.scenario.screenshots).Count
    }
}

$configurations = @(
    [pscustomobject][ordered]@{
        unityVersion = '2022.3.62f3'
        revision = '96770f904ca7'
        testFrameworkVersion = '1.1.33'
        testFrameworkSource = 'registry'
        nunitVersion = '1.0.6'
        nunitSource = 'registry'
        unityExecutable = 'C:\Program Files\Unity\Hub\Editor\2022.3.62f3\Editor\Unity.exe'
        unityExecutableSha256 = '02e80b2c1d7f983375c97b612655be9f8ed852121e3a4eedf1570701c48ea5cd'
        approvalExpected = $true
    },
    [pscustomobject][ordered]@{
        unityVersion = '6000.0.69f1'
        revision = '5f8607f5118b'
        testFrameworkVersion = '1.6.0'
        testFrameworkSource = 'builtin'
        nunitVersion = '2.0.3'
        nunitSource = 'builtin'
        unityExecutable = 'C:\Program Files\Unity\Hub\Editor\6000.0.69f1\Editor\Unity.exe'
        unityExecutableSha256 = '3927c20e4c76f15951989fd4866546b03d3ebfcc72bb5d708cd6397fad50451d'
        approvalExpected = $true
    },
    [pscustomobject][ordered]@{
        unityVersion = '6000.5.3f1'
        revision = 'c2eb47b3a2a9'
        testFrameworkVersion = '1.7.0'
        testFrameworkSource = 'builtin'
        nunitVersion = '2.1.0'
        nunitSource = 'builtin'
        unityExecutable = 'C:\Program Files\Unity\Hub\Editor\6000.5.3f1\Editor\Unity.exe'
        unityExecutableSha256 = '5e54f3a9953179419ddf8af860c3ccdcbb6ada45276fa9df06fdaaaa1124a118'
        approvalExpected = $true
    }
)
$caseDefinitions = @(
    [pscustomobject][ordered]@{ name = 'pass'; expectedStatus = 'PLAY_VERIFIED'; testFilter = 'Upv.Acceptance.AcceptanceTests.PassesAcrossFrames'; scenarioKind = $null; approvedOnly = $false },
    [pscustomobject][ordered]@{ name = 'fail'; expectedStatus = 'PLAY_FAILED'; testFilter = 'Upv.Acceptance.AcceptanceTests.FailsDeliberately'; scenarioKind = $null; approvedOnly = $false },
    [pscustomobject][ordered]@{ name = 'skip'; expectedStatus = 'VERIFICATION_BLOCKED'; testFilter = 'Upv.Acceptance.AcceptanceTests.SkipsDeliberately'; scenarioKind = $null; approvedOnly = $false },
    [pscustomobject][ordered]@{ name = 'inconclusive'; expectedStatus = 'VERIFICATION_BLOCKED'; testFilter = 'Upv.Acceptance.AcceptanceTests.IsInconclusiveDeliberately'; scenarioKind = $null; approvedOnly = $false },
    [pscustomobject][ordered]@{ name = 'zero'; expectedStatus = 'VERIFICATION_BLOCKED'; testFilter = 'Upv.Acceptance.NoSuchTest'; scenarioKind = $null; approvedOnly = $false },
    [pscustomobject][ordered]@{ name = 'scenario'; expectedStatus = 'PLAY_VERIFIED'; testFilter = $null; scenarioKind = 'PASS'; approvedOnly = $false },
    [pscustomobject][ordered]@{ name = 'scenario-compile-fail'; expectedStatus = 'PLAY_FAILED'; testFilter = $null; scenarioKind = 'COMPILE_FAILURE'; approvedOnly = $true }
)

[void][System.IO.Directory]::CreateDirectory($script:AcceptanceRoot)
if ($DiscoverPackageIdentities) {
    [void](Invoke-AcceptanceIdentityDiscovery -Configurations $configurations)
    return
}
$results = New-Object System.Collections.ArrayList
foreach ($configuration in $configurations) {
    if ($null -ne $UnityVersions -and $UnityVersions.Count -gt 0 -and $configuration.unityVersion -notin $UnityVersions) {
        continue
    }
    if (-not (Test-Path -LiteralPath $configuration.unityExecutable -PathType Leaf)) {
        throw "Required acceptance editor is missing: $($configuration.unityExecutable)"
    }
    $project = New-AcceptanceProject -Configuration $configuration
    $before = Get-StableUnityCopySetFingerprint -ProjectRoot $project
    foreach ($caseDefinition in $caseDefinitions) {
        if ($null -ne $CaseNames -and $CaseNames.Count -gt 0 -and $caseDefinition.name -notin $CaseNames) {
            continue
        }
        if ($caseDefinition.approvedOnly -and -not $configuration.approvalExpected) {
            continue
        }
        $expectedStatus = if ($configuration.approvalExpected) { $caseDefinition.expectedStatus } else { 'VERIFICATION_BLOCKED' }
        $scenarioBundle = if ($caseDefinition.scenarioKind -eq 'PASS') {
            $script:ScenarioPath
        } elseif ($caseDefinition.scenarioKind -eq 'COMPILE_FAILURE') {
            New-AcceptanceCompileFailureScenario
        } else {
            $null
        }
        $caseParameters = @{
            Configuration = $configuration
            ProjectRoot = $project
            CaseName = $caseDefinition.name
            ExpectedStatus = $expectedStatus
            TestFilter = $caseDefinition.testFilter
            ScenarioBundlePath = $scenarioBundle
        }
        Write-Host "Starting real-Unity acceptance: $($configuration.unityVersion)/$($caseDefinition.name)"
        [void]$results.Add((Invoke-AcceptanceCase @caseParameters))
        Write-Host "Passed real-Unity acceptance: $($configuration.unityVersion)/$($caseDefinition.name)"
    }
    $after = Get-StableUnityCopySetFingerprint -ProjectRoot $project
    if ($before.treeSha256 -cne $after.treeSha256) {
        throw "Acceptance source project changed for Unity $($configuration.unityVersion)."
    }
}

if ($results.Count -eq 0) {
    throw 'Acceptance filters selected zero cases.'
}

$summary = [ordered]@{
    schemaVersion = '1.0.0'
    acceptanceStatus = if (@($results | Where-Object { $_.compatibilityStatus -eq 'BLOCKED' }).Count -gt 0) { 'PARTIAL_SOURCE_POLICY_BLOCKED' } else { 'APPROVED' }
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    artifactRoot = $script:AcceptanceRoot
    caseCount = $results.Count
    approvedIdentityCaseCount = @($results | Where-Object { $_.packageIdentityMatched }).Count
    sourcePolicyBlockedCaseCount = @($results | Where-Object { $_.compatibilityStatus -eq 'BLOCKED' }).Count
    results = @($results)
}
$summaryPath = Join-Path $script:AcceptanceRoot 'acceptance-summary.json'
Write-AcceptanceText -Path $summaryPath -Content (ConvertTo-Json $summary -Depth 10)
Write-Host "Unity Play Verification real-Unity acceptance completed. Status: $($summary.acceptanceStatus); cases: $($results.Count)"
Write-Host "Summary: $summaryPath"
