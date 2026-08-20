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
    [string[]]$CaseNames
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
$script:ResultSchemaPath = Join-Path $script:RepositoryRoot 'schemas\unity-play-verification-result-1.0.0.schema.json'
$script:AcceptanceRoot = if ([string]::IsNullOrWhiteSpace($ArtifactsRoot)) {
    Join-Path ([System.IO.Path]::GetTempPath()) ('upv-real-acceptance-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
} else {
    [System.IO.Path]::GetFullPath($ArtifactsRoot)
}

. $script:FingerprintPath
. $script:SchemaValidatorPath

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

# Invokes one production verifier case and returns its parsed result and raw JSON.
function Invoke-AcceptanceCase {
    param(
        [Parameter(Mandatory = $true)][object]$Configuration,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$CaseName,
        [Parameter(Mandatory = $true)][string]$ExpectedStatus,
        [Parameter()][AllowNull()][string]$TestFilter,
        [Parameter()][switch]$Scenario
    )

    $caseRoot = Join-Path $script:AcceptanceRoot ("runs\$($Configuration.unityVersion)\$CaseName")
    [void][System.IO.Directory]::CreateDirectory($caseRoot)
    $arguments = @(
        '-ProjectRoot', $ProjectRoot,
        '-UnityExecutable', $Configuration.unityExecutable,
        '-ArtifactsRoot', $caseRoot,
        '-TimeoutSeconds', [string]$TimeoutSeconds
    )
    if ($Scenario) {
        $arguments += @('-ScenarioBundlePath', $script:ScenarioPath)
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
    },
    [pscustomobject][ordered]@{
        unityVersion = '6000.0.69f1'
        revision = '5f8607f5118b'
        testFrameworkVersion = '1.6.0'
        testFrameworkSource = 'builtin'
        nunitVersion = '2.0.3'
        nunitSource = 'builtin'
        unityExecutable = 'C:\Program Files\Unity\Hub\Editor\6000.0.69f1\Editor\Unity.exe'
    },
    [pscustomobject][ordered]@{
        unityVersion = '6000.5.3f1'
        revision = 'c2eb47b3a2a9'
        testFrameworkVersion = '1.7.0'
        testFrameworkSource = 'builtin'
        nunitVersion = '2.1.0'
        nunitSource = 'builtin'
        unityExecutable = 'C:\Program Files\Unity\Hub\Editor\6000.5.3f1\Editor\Unity.exe'
    }
)
$caseDefinitions = @(
    [pscustomobject][ordered]@{ name = 'pass'; expectedStatus = 'PLAY_VERIFIED'; testFilter = 'Upv.Acceptance.AcceptanceTests.PassesAcrossFrames'; scenario = $false },
    [pscustomobject][ordered]@{ name = 'fail'; expectedStatus = 'PLAY_FAILED'; testFilter = 'Upv.Acceptance.AcceptanceTests.FailsDeliberately'; scenario = $false },
    [pscustomobject][ordered]@{ name = 'skip'; expectedStatus = 'VERIFICATION_BLOCKED'; testFilter = 'Upv.Acceptance.AcceptanceTests.SkipsDeliberately'; scenario = $false },
    [pscustomobject][ordered]@{ name = 'inconclusive'; expectedStatus = 'VERIFICATION_BLOCKED'; testFilter = 'Upv.Acceptance.AcceptanceTests.IsInconclusiveDeliberately'; scenario = $false },
    [pscustomobject][ordered]@{ name = 'zero'; expectedStatus = 'VERIFICATION_BLOCKED'; testFilter = 'Upv.Acceptance.NoSuchTest'; scenario = $false },
    [pscustomobject][ordered]@{ name = 'scenario'; expectedStatus = 'PLAY_VERIFIED'; testFilter = $null; scenario = $true }
)

[void][System.IO.Directory]::CreateDirectory($script:AcceptanceRoot)
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
        $caseParameters = @{
            Configuration = $configuration
            ProjectRoot = $project
            CaseName = $caseDefinition.name
            ExpectedStatus = $caseDefinition.expectedStatus
            TestFilter = $caseDefinition.testFilter
        }
        if ($caseDefinition.scenario) {
            $caseParameters.Scenario = $true
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
    acceptanceStatus = 'APPROVED'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    artifactRoot = $script:AcceptanceRoot
    caseCount = $results.Count
    results = @($results)
}
$summaryPath = Join-Path $script:AcceptanceRoot 'acceptance-summary.json'
Write-AcceptanceText -Path $summaryPath -Content (ConvertTo-Json $summary -Depth 10)
Write-Host "Unity Play Verification real-Unity acceptance passed. Cases: $($results.Count)"
Write-Host "Summary: $summaryPath"
