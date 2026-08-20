[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:RepositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\', '/')
$script:SkillRoot = Join-Path -Path $script:RepositoryRoot -ChildPath 'skills\codex\unity-play-verification'
$script:RunnerPath = Join-Path -Path $script:SkillRoot -ChildPath 'scripts\invoke-unity-play-verification.ps1'
$script:CorePath = Join-Path -Path $script:SkillRoot -ChildPath 'scripts\lib\unity-play-verification-core.ps1'
$script:TemplatePath = Join-Path -Path $script:SkillRoot -ChildPath 'templates\minimal-scenario'
$script:CompatibilityPath = Join-Path -Path $script:SkillRoot -ChildPath 'config\unity-play-compatibility.json'
$script:ResultSchemaPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'schemas\unity-play-verification-result-1.0.0.schema.json'
$script:ScenarioSchemaPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'schemas\unity-play-scenario-1.0.0.schema.json'
$script:CompatibilitySchemaPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'schemas\unity-play-compatibility-1.0.0.schema.json'
$script:VendorRoot = Join-Path -Path $script:SkillRoot -ChildPath 'scripts\vendor'
$script:SchemaValidatorPath = Join-Path -Path $script:VendorRoot -ChildPath 'shared\json-schema-validator.ps1'
$script:ProcessLibraryPath = Join-Path -Path $script:VendorRoot -ChildPath 'shared\unity-process-job.ps1'
$script:FingerprintLibraryPath = Join-Path -Path $script:VendorRoot -ChildPath 'doctor\lib\unity-project-fingerprint.ps1'
$script:ProvenancePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'modules\VENDORED_DEPENDENCIES.md'
$script:VendoredRuntimePaths = @(
    (Join-Path -Path $script:VendorRoot -ChildPath 'doctor\inspect-unity-project.ps1'),
    $script:FingerprintLibraryPath,
    (Join-Path -Path $script:VendorRoot -ChildPath 'shared\unity-baseline-orchestration.ps1'),
    $script:ProcessLibraryPath,
    (Join-Path -Path $script:VendorRoot -ChildPath 'shared\git-metadata-integrity.ps1'),
    (Join-Path -Path $script:VendorRoot -ChildPath 'shared\unity-isolation-path-budget.ps1'),
    $script:SchemaValidatorPath
)
$script:FixturePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'tests\fixtures\unity-minimal-clean'
$script:ScratchRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('unity-play-verification-tests-' + [guid]::NewGuid().ToString('N'))
$script:Assertions = 0

. $script:CorePath
. $script:SchemaValidatorPath
. $script:ProcessLibraryPath
. $script:FingerprintLibraryPath

# Throws when a test condition is false.
function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:Assertions++
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

# Throws when two scalar values differ.
function Assert-Equal {
    param(
        [Parameter()][AllowNull()][object]$Expected,
        [Parameter()][AllowNull()][object]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:Assertions++
    if ($Expected -ne $Actual) {
        throw "Assertion failed: $Message. Expected <$Expected>; actual <$Actual>."
    }
}

# Writes one test artifact as UTF-8 without a byte-order mark.
function Write-TestText {
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

# Compiles an unsigned Unity-shaped executable for internal process and production trust-boundary tests.
function New-UpvUnsignedFakeUnity {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$ProductVersion
    )

    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath))
    $safeProductVersion = $ProductVersion.Replace('"', '')
    $source = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;

[assembly: AssemblyTitle("Unity")]
[assembly: AssemblyProduct("Unity")]
[assembly: AssemblyCompany("Unsigned test fixture")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("6000.0.69.1")]
[assembly: AssemblyInformationalVersion("$safeProductVersion")]

internal static class Program
{
    // Writes a delayed marker only when a child survives Job Object termination.
    private static void WriteDelayedSentinel()
    {
        Thread.Sleep(2500);
        string path = Environment.GetEnvironmentVariable("UPV_FAKE_DELAYED_SENTINEL");
        if (!String.IsNullOrWhiteSpace(path))
        {
            File.WriteAllText(path, "child survived timeout");
        }
    }

    // Runs a short success case or a parent-child timeout case selected by arguments.
    private static int Main(string[] args)
    {
        if (args.Length > 0 && String.Equals(args[0], "--child", StringComparison.Ordinal))
        {
            WriteDelayedSentinel();
            return 0;
        }
        if (args.Length > 0 && String.Equals(args[0], "--parent-child-timeout", StringComparison.Ordinal))
        {
            var child = new ProcessStartInfo();
            child.FileName = Assembly.GetExecutingAssembly().Location;
            child.Arguments = "--child";
            child.UseShellExecute = false;
            Process.Start(child);
            Thread.Sleep(Timeout.Infinite);
        }
        return 0;
    }
}
"@
    Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $OutputPath -OutputType ConsoleApplication
    return [System.IO.Path]::GetFullPath($OutputPath)
}

# Invokes the production entrypoint and parses its single stdout JSON document.
function Invoke-TestVerifier {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'powershell.exe'
    $quoted = foreach ($argument in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:RunnerPath) + $Arguments) {
        if ($argument.Contains('"')) { throw 'Test argument contains a quote.' }
        if ($argument -match '\s') { '"' + $argument + '"' } else { $argument }
    }
    $startInfo.Arguments = [string]::Join(' ', [string[]]$quoted)
    $startInfo.WorkingDirectory = $script:RepositoryRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            throw 'Production verifier fixture timed out.'
        }
        $process.WaitForExit()
        $stdout = $stdoutTask.Result.Trim()
        $stderr = $stderrTask.Result.Trim()
        if ($process.ExitCode -ne 0) {
            throw "Production verifier exited with $($process.ExitCode): $stderr"
        }
        return [pscustomobject][ordered]@{
            stdout = $stdout
            stderr = $stderr
            result = ConvertFrom-Json -InputObject $stdout -ErrorAction Stop
        }
    } finally {
        $process.Dispose()
    }
}

# Validates one parsed instance against a repository JSON Schema.
function Assert-SchemaValid {
    param(
        [Parameter(Mandatory = $true)][object]$Instance,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $errors = @(Invoke-JsonSchemaValidation -Instance $Instance -SchemaPath $SchemaPath)
    Assert-Equal -Expected 0 -Actual $errors.Count -Message ($Message + $(if ($errors.Count -gt 0) { ': ' + [string]::Join('; ', [string[]]@($errors | ForEach-Object { $_.message })) } else { '' }))
}

[void][System.IO.Directory]::CreateDirectory($script:ScratchRoot)
try {
    foreach ($requiredPath in @(
        $script:RunnerPath,
        $script:CorePath,
        $script:TemplatePath,
        $script:CompatibilityPath,
        $script:ResultSchemaPath,
        $script:ScenarioSchemaPath,
        $script:CompatibilitySchemaPath,
        $script:ProcessLibraryPath,
        $script:FingerprintLibraryPath,
        (Join-Path $script:RepositoryRoot '.github\workflows\static-tests.yml'),
        (Join-Path $script:RepositoryRoot 'scripts\install-unity-play-verification-skill.ps1'),
        (Join-Path $script:RepositoryRoot 'modules\VENDORED_DEPENDENCIES.md'),
        (Join-Path $script:RepositoryRoot 'docs\skills\unity-play-verification.md'),
        (Join-Path $script:RepositoryRoot 'docs\validation\unity-play-verification-real-unity-acceptance.md'),
        (Join-Path $script:RepositoryRoot 'docs\history\unity-agent-pipeline-v0.5.0.md'),
        (Join-Path $script:RepositoryRoot 'docs\history\unity-agent-pipeline-v0.6.0.md')
    )) {
        Assert-True -Condition (Test-Path -LiteralPath $requiredPath) -Message "Required Play verification path exists: $requiredPath"
    }
    Assert-Equal -Expected '0.2.0' -Actual ((Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'VERSION')).Trim()) -Message 'Repository VERSION'
    Assert-Equal -Expected '0.2.0' -Actual ((Get-Content -Raw -LiteralPath (Join-Path $script:SkillRoot 'VERSION')).Trim()) -Message 'Play Skill VERSION'

    $provenanceContent = Get-Content -Raw -LiteralPath $script:ProvenancePath
    foreach ($vendoredPath in $script:VendoredRuntimePaths) {
        Assert-True -Condition (Test-Path -LiteralPath $vendoredPath -PathType Leaf) -Message "Vendored runtime dependency exists: $vendoredPath"
        $vendoredHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $vendoredPath).Hash.ToLowerInvariant()
        Assert-True -Condition $provenanceContent.Contains($vendoredHash) -Message "Vendored runtime dependency hash is pinned: $vendoredPath"
    }

    $acceptancePath = Join-Path $script:RepositoryRoot 'docs\validation\unity-play-verification-real-unity-acceptance.md'
    $acceptanceContent = Get-Content -Raw -LiteralPath $acceptancePath
    Assert-True -Condition ($acceptanceContent -match 'APPROVED.+SELECTED EDITOR PLAYMODE TESTS AND SOURCE-ONLY SCENARIOS ONLY') -Message 'Acceptance scope is explicitly limited'
    Assert-True -Condition ($acceptanceContent -match '18 cases total') -Message 'Acceptance document records all 18 real-Unity cases'
    Assert-True -Condition ($acceptanceContent -notmatch '(?i)C:\\Users|E:\\Unity|Woosik|accessToken') -Message 'Acceptance document excludes local identity, project paths, and access tokens'
    foreach ($acceptedFile in @(
        $script:RunnerPath,
        $script:CorePath,
        (Join-Path $script:SkillRoot 'harness\PlayVerificationHarness.cs'),
        $script:ResultSchemaPath,
        $script:ScenarioSchemaPath,
        $script:CompatibilitySchemaPath,
        $script:CompatibilityPath
    )) {
        $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $acceptedFile).Hash.ToLowerInvariant()
        Assert-True -Condition $acceptanceContent.Contains($currentHash) -Message "Acceptance document seals current production hash: $acceptedFile"
    }

    $v05ReleaseContent = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'docs\history\unity-agent-pipeline-v0.5.0.md')
    $v06ReleaseContent = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'docs\history\unity-agent-pipeline-v0.6.0.md')
    Assert-True -Condition ($v05ReleaseContent -match 'Release contract status:\s*\*\*FINAL\*\*') -Message 'v0.5.0 release contract is final'
    Assert-True -Condition ($v06ReleaseContent -match 'Release contract status:\s*\*\*FINAL\*\*') -Message 'v0.6.0 release contract is final'

    foreach ($jsonPath in @($script:ResultSchemaPath, $script:ScenarioSchemaPath, $script:CompatibilitySchemaPath, $script:CompatibilityPath)) {
        $parsed = Get-Content -Raw -LiteralPath $jsonPath | ConvertFrom-Json -ErrorAction Stop
        Assert-True -Condition ($null -ne $parsed) -Message "JSON parses: $jsonPath"
    }
    $scenarioManifest = Get-Content -Raw -LiteralPath (Join-Path $script:TemplatePath 'manifest.json') | ConvertFrom-Json
    $compatibilityRegistry = Get-Content -Raw -LiteralPath $script:CompatibilityPath | ConvertFrom-Json
    Assert-SchemaValid -Instance $scenarioManifest -SchemaPath $script:ScenarioSchemaPath -Message 'Scenario template validates against schema'
    Assert-SchemaValid -Instance $compatibilityRegistry -SchemaPath $script:CompatibilitySchemaPath -Message 'Compatibility registry validates against schema'
    Assert-Equal -Expected 3 -Actual @($compatibilityRegistry.entries).Count -Message 'Initial compatibility registry contains three exact pairs'
    Assert-Equal -Expected 3 -Actual @($compatibilityRegistry.entries | Where-Object { $_.status -ceq 'APPROVED' }).Count -Message 'All three real-Unity acceptance pairs are approved'

    $safeSelector = Test-UpvSelectorValue -Value 'Smoke;Gameplay.*' -Name 'TestFilter'
    $unsafeSelector = Test-UpvSelectorValue -Value "Smoke`nOther" -Name 'TestFilter'
    Assert-True -Condition $safeSelector.accepted -Message 'Normal selector is accepted'
    Assert-True -Condition (-not $unsafeSelector.accepted) -Message 'Line-breaking selector is rejected'
    $commandLineTokens = @(ConvertFrom-UpvWindowsCommandLine -CommandLine '"C:\Program Files\Unity\Editor\Unity.exe" -projectpath "E:\Unity\Different Project" -batchmode')
    Assert-Equal -Expected '-projectpath' -Actual $commandLineTokens[1] -Message 'Windows command line parser preserves project-path switch'
    Assert-Equal -Expected 'E:\Unity\Different Project' -Actual $commandLineTokens[2] -Message 'Windows command line parser preserves quoted project path'

    $argumentRoot = Join-Path $script:ScratchRoot 'argument paths with spaces'
    $projectArguments = New-UpvUnityTestArguments `
        -ProjectPath (Join-Path $argumentRoot 'project') `
        -TestResultsPath (Join-Path $argumentRoot 'result.xml') `
        -EditorLogPath (Join-Path $argumentRoot 'Editor.log') `
        -UpmLogPath (Join-Path $argumentRoot 'upm.log') `
        -Mode 'PROJECT_PLAYMODE_TESTS' `
        -TestFilter 'Smoke;Gameplay.*' `
        -TestCategory 'Fast;UI' `
        -AssemblyNames 'One.Tests;Two.Tests'
    Assert-Equal -Expected 1 -Actual @($projectArguments | Where-Object { $_ -ceq 'Smoke;Gameplay.*' }).Count -Message 'Semicolon filter remains one opaque process argument'
    Assert-Equal -Expected 1 -Actual @($projectArguments | Where-Object { $_ -ceq 'One.Tests;Two.Tests' }).Count -Message 'Assembly selector remains one opaque process argument'
    foreach ($forbiddenArgument in @('-quit', '-nographics', '-runSynchronously')) {
        Assert-True -Condition ($projectArguments -notcontains $forbiddenArgument) -Message "Constructed arguments omit $forbiddenArgument"
    }
    $scenarioArguments = New-UpvUnityTestArguments `
        -ProjectPath (Join-Path $argumentRoot 'project') `
        -TestResultsPath (Join-Path $argumentRoot 'result.xml') `
        -EditorLogPath (Join-Path $argumentRoot 'Editor.log') `
        -UpmLogPath (Join-Path $argumentRoot 'upm.log') `
        -Mode 'SCENARIO_OVERLAY' `
        -TestFilter 'Scenario.Test' `
        -ScenarioId 'scenario-one' `
        -ScenarioResultPath (Join-Path $argumentRoot 'scenario.json') `
        -ScreenshotRoot (Join-Path $argumentRoot 'screenshots') `
        -ScenarioTimeoutSeconds 120
    Assert-Equal -Expected 'scenario-one' -Actual $scenarioArguments[[array]::IndexOf($scenarioArguments, '-upvScenarioId') + 1] -Message 'Scenario ID is emitted as its own process argument'
    Assert-Equal -Expected '120' -Actual $scenarioArguments[[array]::IndexOf($scenarioArguments, '-upvScenarioTimeoutSeconds') + 1] -Message 'Scenario timeout uses invariant text'

    $nunitRoot = Join-Path $script:ScratchRoot 'nunit'
    $passedXml = '<test-run id="2" testcasecount="2" result="Passed" total="2" passed="2" failed="0" inconclusive="0" skipped="0" asserts="2" duration="0.25"><test-suite /></test-run>'
    $failedXml = '<test-run id="2" testcasecount="2" result="Failed" total="2" passed="1" failed="1" inconclusive="0" skipped="0" asserts="2" duration="0.25"><test-suite><test-case fullname="Example.Fail" result="Failed"><failure><message>expected true</message><stack-trace>line 1</stack-trace></failure></test-case></test-suite></test-run>'
    $skippedXml = '<test-run id="2" testcasecount="2" result="Passed" total="2" passed="1" failed="0" inconclusive="0" skipped="1" asserts="1" duration="0.25"><test-suite /></test-run>'
    $inconclusiveXml = '<test-run id="2" testcasecount="1" result="Inconclusive" total="1" passed="0" failed="0" inconclusive="1" skipped="0" asserts="0" duration="0.25"><test-suite /></test-run>'
    $zeroXml = '<test-run id="2" testcasecount="0" result="Passed" total="0" passed="0" failed="0" inconclusive="0" skipped="0" asserts="0" duration="0"><test-suite /></test-run>'
    $cases = @(
        [pscustomobject]@{ name = 'passed'; xml = $passedXml; classification = 'PASSED' },
        [pscustomobject]@{ name = 'failed'; xml = $failedXml; classification = 'FAILED' },
        [pscustomobject]@{ name = 'skipped'; xml = $skippedXml; classification = 'INCOMPLETE' },
        [pscustomobject]@{ name = 'inconclusive'; xml = $inconclusiveXml; classification = 'INCOMPLETE' },
        [pscustomobject]@{ name = 'zero'; xml = $zeroXml; classification = 'ZERO_TESTS' }
    )
    foreach ($case in $cases) {
        $path = Join-Path $nunitRoot ($case.name + '.xml')
        Write-TestText -Path $path -Content $case.xml
        $analysis = Get-UpvNUnitAnalysis -Path $path
        Assert-Equal -Expected $case.classification -Actual $analysis.classification -Message "NUnit $($case.name) classification"
    }
    $failedAnalysis = Get-UpvNUnitAnalysis -Path (Join-Path $nunitRoot 'failed.xml')
    Assert-Equal -Expected 'Example.Fail' -Actual $failedAnalysis.failureDetails[0].name -Message 'NUnit failure name is preserved'
    Write-TestText -Path (Join-Path $nunitRoot 'nunit2.xml') -Content '<test-results total="2" errors="0" failures="0" not-run="0" inconclusive="0" ignored="0" skipped="0" invalid="0" time="0.1"><test-suite success="True" /></test-results>'
    Assert-Equal -Expected 'PASSED' -Actual (Get-UpvNUnitAnalysis -Path (Join-Path $nunitRoot 'nunit2.xml')).classification -Message 'Legacy NUnit 2 success is parsed'
    Write-TestText -Path (Join-Path $nunitRoot 'malformed.xml') -Content '<test-run>'
    Assert-Equal -Expected 'INVALID' -Actual (Get-UpvNUnitAnalysis -Path (Join-Path $nunitRoot 'malformed.xml')).classification -Message 'Malformed NUnit XML is invalid'
    Assert-Equal -Expected 'NOT_ANALYZED' -Actual (Get-UpvNUnitAnalysis -Path (Join-Path $nunitRoot 'missing.xml')).classification -Message 'Missing NUnit XML is not analyzed'

    $logRoot = Join-Path $script:ScratchRoot 'logs'
    $isolatedPath = Join-Path $script:ScratchRoot 'isolated-project'
    $safeLog = @(
        "Built from '6000.0/staging' branch; Version is '6000.0.69f1 (revision)'",
        'BatchMode: 1, IsHumanControllingUs: 0',
        "Successfully changed project path to: $isolatedPath",
        'runTests started'
    ) -join "`r`n"
    Write-TestText -Path (Join-Path $logRoot 'safe.log') -Content $safeLog
    Write-TestText -Path (Join-Path $logRoot 'failure.log') -Content ($safeLog + "`r`nAssets/Test.cs(1,1): error CS1002: ; expected")
    $safeLogAnalysis = Get-UpvEditorLogAnalysis -Path (Join-Path $logRoot 'safe.log') -ExpectedUnityVersion '6000.0.69f1' -ExpectedProjectPath $isolatedPath
    $failureLogAnalysis = Get-UpvEditorLogAnalysis -Path (Join-Path $logRoot 'failure.log') -ExpectedUnityVersion '6000.0.69f1' -ExpectedProjectPath $isolatedPath
    Assert-Equal -Expected 'SAFE' -Actual $safeLogAnalysis.classification -Message 'Complete Editor.log markers are safe'
    Assert-Equal -Expected 'FAILURE' -Actual $failureLogAnalysis.classification -Message 'Compiler error is a concrete log failure'
    Assert-Equal -Expected 'NOT_ANALYZED' -Actual (Get-UpvEditorLogAnalysis -Path (Join-Path $logRoot 'missing.log') -ExpectedUnityVersion '6000.0.69f1' -ExpectedProjectPath $isolatedPath).classification -Message 'Missing Editor.log is not promoted'

    $bundle = Get-UpvScenarioBundleAssessment -BundlePath $script:TemplatePath -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    Assert-True -Condition $bundle.accepted -Message ('Bundled scenario template is accepted: ' + [string]::Join(' ', [string[]]$bundle.errors))
    Assert-Equal -Expected 'sample-editor-playmode' -Actual $bundle.scenarioId -Message 'Scenario ID round-trips'
    Assert-True -Condition ($bundle.treeSha256 -match '^[0-9a-f]{64}$') -Message 'Scenario bundle has deterministic SHA-256'

    $missingPropertyBundle = Join-Path $script:ScratchRoot 'missing-property-bundle'
    Copy-Item -LiteralPath $script:TemplatePath -Destination $missingPropertyBundle -Recurse -Force
    $missingPropertyManifestPath = Join-Path $missingPropertyBundle 'manifest.json'
    $missingPropertyManifest = Get-Content -Raw -LiteralPath $missingPropertyManifestPath | ConvertFrom-Json
    $missingPropertyManifest.PSObject.Properties.Remove('screenshotIds')
    Write-TestText -Path $missingPropertyManifestPath -Content (ConvertTo-Json -Depth 10 -InputObject $missingPropertyManifest)
    $missingPropertyAssessment = Get-UpvScenarioBundleAssessment -BundlePath $missingPropertyBundle -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    Assert-True -Condition (-not $missingPropertyAssessment.accepted) -Message 'Missing required manifest property is rejected'

    $unexpectedPropertyBundle = Join-Path $script:ScratchRoot 'unexpected-property-bundle'
    Copy-Item -LiteralPath $script:TemplatePath -Destination $unexpectedPropertyBundle -Recurse -Force
    $unexpectedPropertyManifestPath = Join-Path $unexpectedPropertyBundle 'manifest.json'
    $unexpectedPropertyManifest = Get-Content -Raw -LiteralPath $unexpectedPropertyManifestPath | ConvertFrom-Json
    $unexpectedPropertyManifest | Add-Member -NotePropertyName arbitraryUnityArguments -NotePropertyValue @('-quit')
    Write-TestText -Path $unexpectedPropertyManifestPath -Content (ConvertTo-Json -Depth 10 -InputObject $unexpectedPropertyManifest)
    $unexpectedPropertyAssessment = Get-UpvScenarioBundleAssessment -BundlePath $unexpectedPropertyBundle -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    Assert-True -Condition (-not $unexpectedPropertyAssessment.accepted) -Message 'Unexpected manifest property is rejected'

    $scalarArrayBundle = Join-Path $script:ScratchRoot 'scalar-array-bundle'
    Copy-Item -LiteralPath $script:TemplatePath -Destination $scalarArrayBundle -Recurse -Force
    $scalarArrayManifestPath = Join-Path $scalarArrayBundle 'manifest.json'
    $scalarArrayManifest = Get-Content -Raw -LiteralPath $scalarArrayManifestPath | ConvertFrom-Json
    $scalarArrayManifest.expectedAssertionIds = 'editor-play-mode-active'
    Write-TestText -Path $scalarArrayManifestPath -Content (ConvertTo-Json -Depth 10 -InputObject $scalarArrayManifest)
    $scalarArrayAssessment = Get-UpvScenarioBundleAssessment -BundlePath $scalarArrayBundle -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    Assert-True -Condition (-not $scalarArrayAssessment.accepted) -Message 'Scalar manifest identifier collection is rejected'

    $mutatingBundle = Join-Path $script:ScratchRoot 'mutating-bundle'
    Copy-Item -LiteralPath $script:TemplatePath -Destination $mutatingBundle -Recurse -Force
    $beforeMutationBundle = Get-UpvScenarioBundleAssessment -BundlePath $mutatingBundle -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    $mutatingSourcePath = Join-Path $mutatingBundle 'SampleScenarioTests.cs'
    Write-TestText -Path $mutatingSourcePath -Content ((Get-Content -Raw -LiteralPath $mutatingSourcePath) + [Environment]::NewLine + '// changed after validation')
    $afterMutationBundle = Get-UpvScenarioBundleAssessment -BundlePath $mutatingBundle -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    Assert-True -Condition ($beforeMutationBundle.treeSha256 -cne $afterMutationBundle.treeSha256) -Message 'Scenario source mutation changes the canonical bundle hash'

    $unsafeBundle = Join-Path $script:ScratchRoot 'unsafe-bundle'
    Write-TestText -Path (Join-Path $unsafeBundle 'manifest.json') -Content (Get-Content -Raw -LiteralPath (Join-Path $script:TemplatePath 'manifest.json'))
    Write-TestText -Path (Join-Path $unsafeBundle 'unsafe.dll') -Content 'not-a-binary'
    $unsafeBundleAssessment = Get-UpvScenarioBundleAssessment -BundlePath $unsafeBundle -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    Assert-True -Condition (-not $unsafeBundleAssessment.accepted) -Message 'Precompiled scenario file is rejected'

    $invalidRegistryPath = Join-Path $script:ScratchRoot 'invalid-compatibility-registry.json'
    $invalidRegistry = Get-Content -Raw -LiteralPath $script:CompatibilityPath | ConvertFrom-Json
    $invalidRegistry.entries[0] | Add-Member -NotePropertyName bypassSignature -NotePropertyValue $true
    Write-TestText -Path $invalidRegistryPath -Content (ConvertTo-Json -Depth 10 -InputObject $invalidRegistry)
    $invalidRegistryAssessment = Get-UpvCompatibilityAssessment `
        -RegistryPath $invalidRegistryPath `
        -UnityVersion '2022.3.62f3' `
        -TestFrameworkVersion '1.1.33'
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($invalidRegistryAssessment.error)) -Message 'Unexpected compatibility registry property is rejected'

    $badManifestBundle = Join-Path $script:ScratchRoot 'bad-manifest-bundle'
    Write-TestText -Path (Join-Path $badManifestBundle 'manifest.json') -Content '{"schemaVersion":"9.0.0"}'
    Write-TestText -Path (Join-Path $badManifestBundle 'Scenario.cs') -Content '// invalid fixture'
    $badManifestAssessment = Get-UpvScenarioBundleAssessment -BundlePath $badManifestBundle -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    Assert-True -Condition (-not $badManifestAssessment.accepted) -Message 'Incomplete or unsupported scenario manifest is rejected'

    $receiptRoot = Join-Path $script:ScratchRoot 'receipt'
    $receiptPath = Join-Path $receiptRoot 'scenario-result.json'
    $screenshotRoot = Join-Path $receiptRoot 'screenshots'
    $expectedScreenshotPath = Join-Path $screenshotRoot 'sample-frame.png'
    $receiptJson = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{
        schemaVersion = '1.0.0'
        scenarioId = 'sample-editor-playmode'
        completed = $true
        error = ''
        scenes = @()
        assertions = @([ordered]@{ id = 'editor-play-mode-active'; passed = $true; detail = 'ok' })
        captures = @([ordered]@{ id = 'sample-frame'; path = $expectedScreenshotPath })
    })
    Write-TestText -Path $receiptPath -Content $receiptJson
    Write-TestText -Path $expectedScreenshotPath -Content 'png-evidence'
    $receipt = Get-UpvScenarioReceiptAssessment -ReceiptPath $receiptPath -ScreenshotRoot $screenshotRoot -Bundle $bundle
    Assert-True -Condition $receipt.accepted -Message ('Complete scenario receipt is accepted: ' + [string]::Join(' ', [string[]]$receipt.errors))
    Assert-True -Condition ($receipt.screenshots[0].sha256 -match '^[0-9a-f]{64}$') -Message 'Screenshot evidence is hashed'

    Remove-Item -LiteralPath $expectedScreenshotPath -Force
    $missingCaptureReceipt = Get-UpvScenarioReceiptAssessment -ReceiptPath $receiptPath -ScreenshotRoot $screenshotRoot -Bundle $bundle
    Assert-True -Condition (-not $missingCaptureReceipt.accepted) -Message 'Missing requested screenshot blocks receipt acceptance'
    Write-TestText -Path $expectedScreenshotPath -Content 'png-evidence'

    $failedAssertionReceiptPath = Join-Path $receiptRoot 'failed-assertion.json'
    $failedAssertionObject = ConvertFrom-Json -InputObject $receiptJson
    $failedAssertionObject.assertions[0].passed = $false
    Write-TestText -Path $failedAssertionReceiptPath -Content (ConvertTo-Json -Depth 10 -InputObject $failedAssertionObject)
    $failedAssertionReceipt = Get-UpvScenarioReceiptAssessment -ReceiptPath $failedAssertionReceiptPath -ScreenshotRoot $screenshotRoot -Bundle $bundle
    Assert-True -Condition (-not $failedAssertionReceipt.accepted) -Message 'Failed scenario assertion rejects receipt'

    $duplicateAssertionReceiptPath = Join-Path $receiptRoot 'duplicate-assertion.json'
    $duplicateAssertionObject = ConvertFrom-Json -InputObject $receiptJson
    $duplicateAssertionObject.assertions = @($duplicateAssertionObject.assertions[0], $duplicateAssertionObject.assertions[0])
    Write-TestText -Path $duplicateAssertionReceiptPath -Content (ConvertTo-Json -Depth 10 -InputObject $duplicateAssertionObject)
    $duplicateAssertionReceipt = Get-UpvScenarioReceiptAssessment -ReceiptPath $duplicateAssertionReceiptPath -ScreenshotRoot $screenshotRoot -Bundle $bundle
    Assert-True -Condition (-not $duplicateAssertionReceipt.accepted) -Message 'Duplicate scenario assertion ID rejects receipt'

    $unexpectedSceneReceiptPath = Join-Path $receiptRoot 'unexpected-scene.json'
    $unexpectedSceneObject = ConvertFrom-Json -InputObject $receiptJson
    $unexpectedSceneObject.scenes = @('Assets/Unexpected.unity')
    Write-TestText -Path $unexpectedSceneReceiptPath -Content (ConvertTo-Json -Depth 10 -InputObject $unexpectedSceneObject)
    $unexpectedSceneReceipt = Get-UpvScenarioReceiptAssessment -ReceiptPath $unexpectedSceneReceiptPath -ScreenshotRoot $screenshotRoot -Bundle $bundle
    Assert-True -Condition (-not $unexpectedSceneReceipt.accepted) -Message 'Unexpected Scene rejects receipt'

    $integrityProject = Join-Path $script:ScratchRoot 'integrity-project'
    Copy-Item -LiteralPath $script:FixturePath -Destination $integrityProject -Recurse -Force
    $integrityBefore = Get-StableUnityCopySetFingerprint -ProjectRoot $integrityProject
    Write-TestText -Path (Join-Path $integrityProject 'Library\ignored.txt') -Content 'generated data'
    $integrityAfterExcludedChange = Get-StableUnityCopySetFingerprint -ProjectRoot $integrityProject
    Assert-Equal -Expected $integrityBefore.treeSha256 -Actual $integrityAfterExcludedChange.treeSha256 -Message 'Generated excluded data does not change original copy-set integrity'
    Write-TestText -Path (Join-Path $integrityProject 'Assets\Scenes\Main.unity') -Content 'mutated source content'
    $integrityAfterSourceChange = Get-StableUnityCopySetFingerprint -ProjectRoot $integrityProject
    Assert-True -Condition ($integrityBefore.treeSha256 -cne $integrityAfterSourceChange.treeSha256) -Message 'Original source-content mutation is detected by the Play copy-set fingerprint'

    $fakeUnityPath = New-UpvUnsignedFakeUnity `
        -OutputPath (Join-Path $script:ScratchRoot 'fake-unity\6000.0.69f1\Editor\Unity.exe') `
        -ProductVersion '6000.0.69f1_fixture'
    Assert-True -Condition ((Get-Item -LiteralPath $fakeUnityPath).VersionInfo.ProductVersion -match '^6000\.0\.69f1(?:_|$)') -Message 'Unsigned fake exposes the approved exact ProductVersion token'
    Assert-Equal -Expected 'NotSigned' -Actual ([string](Get-AuthenticodeSignature -LiteralPath $fakeUnityPath).Status) -Message 'Fake Unity remains unsigned'

    $processRoot = Join-Path $script:ScratchRoot 'internal-process'
    [void][System.IO.Directory]::CreateDirectory($processRoot)
    $internalSuccess = Invoke-UnityProcessInJob `
        -ExecutablePath $fakeUnityPath `
        -Arguments @('--success') `
        -WorkingDirectory $processRoot `
        -StandardOutputPath (Join-Path $processRoot 'success-stdout.log') `
        -StandardErrorPath (Join-Path $processRoot 'success-stderr.log') `
        -TimeoutSeconds 10
    Assert-True -Condition $internalSuccess.processStarted -Message 'Internal unsigned fake process seam starts'
    Assert-Equal -Expected 0 -Actual $internalSuccess.exitCode -Message 'Internal unsigned fake success exit code'
    Assert-True -Condition $internalSuccess.processTreeExitVerified -Message 'Internal unsigned fake success tree exits'

    $delayedSentinelPath = Join-Path $processRoot 'child-survived.txt'
    $previousSentinel = [Environment]::GetEnvironmentVariable('UPV_FAKE_DELAYED_SENTINEL', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('UPV_FAKE_DELAYED_SENTINEL', $delayedSentinelPath, 'Process')
        $internalTimeout = Invoke-UnityProcessInJob `
            -ExecutablePath $fakeUnityPath `
            -Arguments @('--parent-child-timeout') `
            -WorkingDirectory $processRoot `
            -StandardOutputPath (Join-Path $processRoot 'timeout-stdout.log') `
            -StandardErrorPath (Join-Path $processRoot 'timeout-stderr.log') `
            -TimeoutSeconds 1
    } finally {
        [Environment]::SetEnvironmentVariable('UPV_FAKE_DELAYED_SENTINEL', $previousSentinel, 'Process')
    }
    Assert-True -Condition $internalTimeout.timedOut -Message 'Internal fake timeout is recorded'
    Assert-True -Condition $internalTimeout.terminationRequested -Message 'Timeout requests Job Object termination'
    Assert-True -Condition $internalTimeout.processTreeExitVerified -Message 'Timed-out parent and child process tree exits'
    Assert-Equal -Expected 0 -Actual $internalTimeout.activeProcessCountAfterWait -Message 'No process remains active in the timeout Job Object'
    Start-Sleep -Milliseconds 3000
    Assert-True -Condition (-not (Test-Path -LiteralPath $delayedSentinelPath)) -Message 'Timed-out child cannot write its delayed sentinel'

    $approvedFixturePath = Join-Path $script:ScratchRoot 'approved-production-fixture'
    Copy-Item -LiteralPath $script:FixturePath -Destination $approvedFixturePath -Recurse -Force
    $approvedManifestPath = Join-Path $approvedFixturePath 'Packages\manifest.json'
    $approvedManifest = Get-Content -Raw -LiteralPath $approvedManifestPath | ConvertFrom-Json
    $approvedManifest.dependencies.'com.unity.test-framework' = '1.6.0'
    Write-TestText -Path $approvedManifestPath -Content (ConvertTo-Json -Depth 10 -InputObject $approvedManifest)
    $approvedLockPath = Join-Path $approvedFixturePath 'Packages\packages-lock.json'
    $approvedLock = Get-Content -Raw -LiteralPath $approvedLockPath | ConvertFrom-Json
    $approvedLock.dependencies.'com.unity.test-framework'.version = '1.6.0'
    Write-TestText -Path $approvedLockPath -Content (ConvertTo-Json -Depth 10 -InputObject $approvedLock)
    $unsignedProduction = Invoke-TestVerifier -Arguments @('-ProjectRoot', $approvedFixturePath, '-UnityExecutable', $fakeUnityPath)
    Assert-Equal -Expected 'VERIFICATION_BLOCKED' -Actual $unsignedProduction.result.finalStatus -Message 'Production entrypoint blocks exact-version unsigned fake Unity'
    Assert-True -Condition (-not $unsignedProduction.result.unity.processStarted) -Message 'Production entrypoint never starts unsigned fake Unity'
    $sourcePreflightUnavailable = @($unsignedProduction.result.blockers | Where-Object { $_.code -eq 'SOURCE_EDITOR_PREFLIGHT_UNAVAILABLE' }).Count -gt 0
    if ($sourcePreflightUnavailable) {
        Assert-True -Condition $true -Message 'Production trust check remains fail-closed when local CIM access prevents reaching the signature gate'
    } else {
        Assert-True -Condition $unsignedProduction.result.unity.executableVersionMatched -Message 'Production fake reaches trust validation with matching ProductVersion'
        Assert-Equal -Expected 'NotSigned' -Actual $unsignedProduction.result.unity.signatureStatus -Message 'Production result records unsigned Authenticode status'
        Assert-True -Condition (@($unsignedProduction.result.blockers | Where-Object { $_.code -eq 'UNITY_EXECUTABLE_REJECTED' }).Count -eq 1) -Message 'Production unsigned fake is rejected by the executable trust gate'
    }

    $production = Invoke-TestVerifier -Arguments @('-ProjectRoot', $script:FixturePath)
    Assert-True -Condition ($production.stdout.StartsWith('{') -and $production.stdout.EndsWith('}')) -Message 'Production stdout is one JSON object'
    Assert-True -Condition ([string]::IsNullOrWhiteSpace($production.stderr)) -Message 'Normal production stderr is empty'
    Assert-Equal -Expected '1.0.0' -Actual $production.result.schemaVersion -Message 'Production result schema version'
    Assert-Equal -Expected 'VERIFICATION_BLOCKED' -Actual $production.result.finalStatus -Message 'Unapproved or unknown pair blocks before Unity'
    Assert-True -Condition (-not $production.result.unity.processStarted) -Message 'Blocked production preflight does not start Unity'
    Assert-True -Condition $production.result.originalProjectIntegrity.unchanged -Message 'Blocked production preflight preserves original content'
    Assert-SchemaValid -Instance $production.result -SchemaPath $script:ResultSchemaPath -Message 'Production result validates against schema'
    $savedResult = Get-Content -Raw -LiteralPath $production.result.artifacts.resultPath | ConvertFrom-Json
    Assert-Equal -Expected $production.result.finalStatus -Actual $savedResult.finalStatus -Message 'Saved result matches stdout semantics'

    $conflict = Invoke-TestVerifier -Arguments @(
        '-ProjectRoot', $script:FixturePath,
        '-ScenarioBundlePath', $script:TemplatePath,
        '-TestFilter', 'ShouldConflict'
    )
    Assert-True -Condition (@($conflict.result.blockers | Where-Object { $_.code -eq 'SCENARIO_SELECTION_CONFLICT' }).Count -eq 1) -Message 'Scenario and selector conflict is blocked'

    $skillMetadata = Get-Content -Raw -LiteralPath (Join-Path $script:SkillRoot 'agents\openai.yaml')
    $skillInstructions = Get-Content -Raw -LiteralPath (Join-Path $script:SkillRoot 'SKILL.md')
    $runnerContent = Get-Content -Raw -LiteralPath $script:RunnerPath
    $argumentContractContent = $runnerContent + [Environment]::NewLine + (Get-Content -Raw -LiteralPath $script:CorePath)
    Assert-True -Condition ($skillMetadata -match 'allow_implicit_invocation:\s*false') -Message 'Play Skill is explicit-only'
    Assert-True -Condition ($skillInstructions -match '\$unity-play-verification') -Message 'Skill instructions require literal invocation'
    Assert-True -Condition ($runnerContent -match 'Scenario bundle changed after validation and before isolated overlay copy') -Message 'Runner rechecks scenario bundle hash at copy time'
    Assert-True -Condition ($runnerContent -match "originalProjectIntegrity\.status -eq 'CHANGED'") -Message 'Final-status precedence detects changed original copy-set'
    Assert-True -Condition ($runnerContent -match "scripts\\vendor|ChildPath 'vendor'") -Message 'Runner resolves its bundled vendor tree'
    Assert-True -Condition ($runnerContent -notmatch 'unity-project-doctor\\scripts|unity-baseline-verification\\scripts') -Message 'Runner has no sibling Skill runtime path'
    foreach ($requiredArgument in @('-batchmode', '-forgetProjectPath', '-runTests', '-testPlatform', 'PlayMode', '-testResults')) {
        Assert-True -Condition $argumentContractContent.Contains($requiredArgument) -Message "Runner declares required Unity argument $requiredArgument"
    }
    foreach ($forbiddenArgument in @('-quit', '-nographics', '-runSynchronously')) {
        Assert-True -Condition ($runnerContent -match [regex]::Escape("'$forbiddenArgument'")) -Message "Runner explicitly guards forbidden argument $forbiddenArgument"
    }

    $powerShellFiles = @(Get-ChildItem -LiteralPath $script:RepositoryRoot -Filter '*.ps1' -File -Recurse)
    foreach ($file in $powerShellFiles) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        Assert-Equal -Expected 0 -Actual $parseErrors.Count -Message "PowerShell parses: $($file.FullName)"
    }

    Write-Host "Unity Play Verification tests passed. Assertions: $script:Assertions"
} finally {
    if (Test-Path -LiteralPath $script:ScratchRoot -PathType Container) {
        Remove-Item -LiteralPath $script:ScratchRoot -Recurse -Force
    }
}
