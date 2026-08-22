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
$script:IdentityPath = Join-Path -Path $script:SkillRoot -ChildPath 'scripts\lib\unity-test-framework-identity.ps1'
$script:TemplatePath = Join-Path -Path $script:SkillRoot -ChildPath 'templates\minimal-scenario'
$script:CompatibilityPath = Join-Path -Path $script:SkillRoot -ChildPath 'config\unity-play-compatibility.json'
$script:ResultSchemaPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'schemas\unity-play-verification-result-1.0.0.schema.json'
$script:ScenarioSchemaPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'schemas\unity-play-scenario-1.0.0.schema.json'
$script:CompatibilitySchemaPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'schemas\unity-play-compatibility-1.2.0.schema.json'
$script:PreviousCompatibilitySchemaPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'schemas\unity-play-compatibility-1.1.0.schema.json'
$script:ImmutableCompatibilitySchemaPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'schemas\unity-play-compatibility-1.0.0.schema.json'
$script:VendorRoot = Join-Path -Path $script:SkillRoot -ChildPath 'scripts\vendor'
$script:SchemaValidatorPath = Join-Path -Path $script:VendorRoot -ChildPath 'shared\json-schema-validator.ps1'
$script:ProcessLibraryPath = Join-Path -Path $script:VendorRoot -ChildPath 'shared\unity-process-job.ps1'
$script:FingerprintLibraryPath = Join-Path -Path $script:VendorRoot -ChildPath 'doctor\lib\unity-project-fingerprint.ps1'
$script:GitIntegrityLibraryPath = Join-Path -Path $script:VendorRoot -ChildPath 'shared\git-metadata-integrity.ps1'
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
. $script:IdentityPath
. $script:SchemaValidatorPath
. $script:ProcessLibraryPath
. $script:FingerprintLibraryPath
. $script:GitIntegrityLibraryPath

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

# Creates one minimal project with controlled manifest, lock, and scoped-registry provenance evidence.
function New-UpvProvenanceFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ManifestDependency,
        [Parameter(Mandatory = $true)][string]$LockSource,
        [Parameter()][AllowNull()][string]$LockUrl,
        [Parameter()][string]$LockVersion = '1.1.33',
        [Parameter()][AllowNull()][string]$InterceptingScope
    )

    $root = Join-Path $script:ScratchRoot ('provenance-' + $Name)
    [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'Packages'))
    $manifest = [ordered]@{
        dependencies = [ordered]@{
            'com.unity.test-framework' = $ManifestDependency
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($InterceptingScope)) {
        $manifest.scopedRegistries = @([ordered]@{
            name = 'untrusted-interceptor'
            url = 'https://packages.example.invalid'
            scopes = @($InterceptingScope)
        })
    }
    $lockEntry = [ordered]@{
        version = $LockVersion
        depth = 0
        source = $LockSource
        dependencies = [ordered]@{}
    }
    if (-not [string]::IsNullOrWhiteSpace($LockUrl)) {
        $lockEntry.url = $LockUrl
    }
    $lock = [ordered]@{
        dependencies = [ordered]@{
            'com.unity.test-framework' = $lockEntry
        }
    }
    Write-TestText -Path (Join-Path $root 'Packages\manifest.json') -Content (ConvertTo-Json -Depth 10 -InputObject $manifest)
    Write-TestText -Path (Join-Path $root 'Packages\packages-lock.json') -Content (ConvertTo-Json -Depth 10 -InputObject $lock)
    return $root
}

# Adds one deterministic resolved Test Framework package tree to a controlled project fixture.
function Add-UpvResolvedPackageFixture {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$DirectoryName,
        [Parameter()][string]$PackageVersion = '1.1.33',
        [Parameter()][string]$Payload = 'approved package payload'
    )

    $packageRoot = Join-Path $ProjectRoot ('Library\PackageCache\' + $DirectoryName)
    Write-TestText -Path (Join-Path $packageRoot 'package.json') -Content (ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        name = 'com.unity.test-framework'
        version = $PackageVersion
    }))
    Write-TestText -Path (Join-Path $packageRoot 'Runtime\payload.txt') -Content $Payload
    return $packageRoot
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
    $windowsRoot = [Environment]::GetEnvironmentVariable('WINDIR', 'Process')
    $compilerCandidates = @(
        (Join-Path $windowsRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $windowsRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )
    $compilerPath = @($compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($compilerPath.Count -ne 1) {
        throw 'A .NET Framework C# compiler is required for the internal unsigned fake fixture.'
    }
    $sourcePath = [System.IO.Path]::ChangeExtension($OutputPath, '.cs')
    Write-TestText -Path $sourcePath -Content $source
    $compilerOutput = @(& $compilerPath[0] /nologo /target:exe "/out:$OutputPath" $sourcePath 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw 'Unsigned fake Unity compilation failed: ' + [string]::Join([Environment]::NewLine, [string[]]$compilerOutput)
    }
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
        $script:IdentityPath,
        $script:TemplatePath,
        $script:CompatibilityPath,
        $script:ResultSchemaPath,
        $script:ScenarioSchemaPath,
        $script:CompatibilitySchemaPath,
        $script:PreviousCompatibilitySchemaPath,
        $script:ImmutableCompatibilitySchemaPath,
        $script:ProcessLibraryPath,
        $script:FingerprintLibraryPath,
        $script:GitIntegrityLibraryPath,
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
    # Confirms every public release surface resolves to the repository version.
    $repositoryVersion = (Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'VERSION')).Trim()
    $skillVersion = (Get-Content -Raw -LiteralPath (Join-Path $script:SkillRoot 'VERSION')).Trim()
    $runnerVersionContent = Get-Content -Raw -LiteralPath $script:RunnerPath
    $componentVersionMatch = [regex]::Match($runnerVersionContent, '\$script:ComponentVersion\s*=\s*''([^'']+)''')
    $verifierVersionMatch = [regex]::Match($runnerVersionContent, '\$script:VerifierVersion\s*=\s*''([^'']+)''')
    Assert-True -Condition ($repositoryVersion -match '^\d+\.\d+\.\d+$') -Message 'Repository VERSION is semantic'
    Assert-True -Condition $componentVersionMatch.Success -Message 'Runner declares ComponentVersion'
    Assert-True -Condition $verifierVersionMatch.Success -Message 'Runner declares VerifierVersion'
    Assert-Equal -Expected $repositoryVersion -Actual $skillVersion -Message 'Repository and Play Skill versions are consistent'
    Assert-Equal -Expected $repositoryVersion -Actual $componentVersionMatch.Groups[1].Value -Message 'Repository and runner component versions are consistent'
    Assert-Equal -Expected $repositoryVersion -Actual $verifierVersionMatch.Groups[1].Value -Message 'Repository and runner verifier versions are consistent'
    $releaseVersionToken = '`' + $repositoryVersion + '`'
    $readmeVersionContent = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'README.md')
    $skillGuideVersionContent = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'docs\skills\unity-play-verification.md')
    $changelogVersionContent = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'CHANGELOG.md')
    Assert-True -Condition $readmeVersionContent.Contains($releaseVersionToken) -Message 'README records the repository version'
    Assert-True -Condition $skillGuideVersionContent.StartsWith("# Unity Play Verification $repositoryVersion") -Message 'Skill guide heading records the repository version'
    Assert-True -Condition ($changelogVersionContent -match [regex]::Escape("## Component $repositoryVersion")) -Message 'Changelog records the repository version'

    $provenanceContent = Get-Content -Raw -LiteralPath $script:ProvenancePath
    foreach ($vendoredPath in $script:VendoredRuntimePaths) {
        Assert-True -Condition (Test-Path -LiteralPath $vendoredPath -PathType Leaf) -Message "Vendored runtime dependency exists: $vendoredPath"
        $vendoredHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $vendoredPath).Hash.ToLowerInvariant()
        Assert-True -Condition $provenanceContent.Contains($vendoredHash) -Message "Vendored runtime dependency hash is pinned: $vendoredPath"
    }

    $acceptancePath = Join-Path $script:RepositoryRoot 'docs\validation\unity-play-verification-real-unity-acceptance.md'
    $acceptanceContent = Get-Content -Raw -LiteralPath $acceptancePath
    $acceptanceVersionToken = '**`' + $repositoryVersion + '`**'
    Assert-True -Condition $acceptanceContent.Contains("Standalone repository target: $acceptanceVersionToken") -Message 'Acceptance record matches the repository version'
    Assert-True -Condition $acceptanceContent.Contains("Play Skill: $acceptanceVersionToken") -Message 'Acceptance record matches the Play Skill version'
    Assert-True -Condition ($acceptanceContent -match 'SELECTED EDITOR PLAYMODE TESTS AND SOURCE-ONLY SCENARIOS ONLY') -Message 'Acceptance scope is explicitly limited'
    Assert-True -Condition ($acceptanceContent -match '18-case matrix') -Message 'Acceptance document records the full requested real-Unity matrix outcome'
    Assert-True -Condition ($acceptanceContent -match '21 results total') -Message 'Acceptance document records three supplemental compilation-failure cases'
    Assert-True -Condition ($acceptanceContent -match 'Editor-builtin') -Message 'Acceptance document distinguishes Unity 6 builtin provenance from registry provenance'
    Assert-True -Condition ($acceptanceContent -match '(?i)not a security sandbox') -Message 'Acceptance document states the same-user-code threat boundary'
    Assert-True -Condition ($acceptanceContent -notmatch '(?i)C:\\Users|E:\\Unity|Woosik|accessToken') -Message 'Acceptance document excludes local identity, project paths, and access tokens'
    foreach ($acceptedFile in @(
        $script:RunnerPath,
        $script:CorePath,
        $script:IdentityPath,
        (Join-Path $script:SkillRoot 'harness\PlayVerificationHarness.cs'),
        $script:ResultSchemaPath,
        $script:ScenarioSchemaPath,
        $script:CompatibilitySchemaPath,
        $script:PreviousCompatibilitySchemaPath,
        $script:CompatibilityPath
    )) {
        $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $acceptedFile).Hash.ToLowerInvariant()
        Assert-True -Condition $acceptanceContent.Contains($currentHash) -Message "Acceptance document seals current production hash: $acceptedFile"
    }

    $v05ReleaseContent = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'docs\history\unity-agent-pipeline-v0.5.0.md')
    $v06ReleaseContent = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'docs\history\unity-agent-pipeline-v0.6.0.md')
    Assert-True -Condition ($v05ReleaseContent -match 'Release contract status:\s*\*\*FINAL\*\*') -Message 'v0.5.0 release contract is final'
    Assert-True -Condition ($v06ReleaseContent -match 'Release contract status:\s*\*\*FINAL\*\*') -Message 'v0.6.0 release contract is final'

    foreach ($jsonPath in @($script:ResultSchemaPath, $script:ScenarioSchemaPath, $script:CompatibilitySchemaPath, $script:PreviousCompatibilitySchemaPath, $script:ImmutableCompatibilitySchemaPath, $script:CompatibilityPath)) {
        $parsed = Get-Content -Raw -LiteralPath $jsonPath | ConvertFrom-Json -ErrorAction Stop
        Assert-True -Condition ($null -ne $parsed) -Message "JSON parses: $jsonPath"
    }
    $scenarioManifest = Get-Content -Raw -LiteralPath (Join-Path $script:TemplatePath 'manifest.json') | ConvertFrom-Json
    $compatibilityRegistry = Get-Content -Raw -LiteralPath $script:CompatibilityPath | ConvertFrom-Json
    Assert-SchemaValid -Instance $scenarioManifest -SchemaPath $script:ScenarioSchemaPath -Message 'Scenario template validates against schema'
    Assert-SchemaValid -Instance $compatibilityRegistry -SchemaPath $script:CompatibilitySchemaPath -Message 'Compatibility registry validates against schema'
    Assert-Equal -Expected '1.2.0' -Actual $compatibilityRegistry.schemaVersion -Message 'Compatibility registry uses the Editor-bound source-specific schema'
    Assert-Equal -Expected 3 -Actual @($compatibilityRegistry.entries).Count -Message 'All three evidence-complete Unity pairs are registered'
    Assert-Equal -Expected 3 -Actual @($compatibilityRegistry.entries | Where-Object { $_.status -ceq 'APPROVED' }).Count -Message 'All evidence-complete registry and builtin pairs are approved'
    Assert-Equal -Expected 1 -Actual @($compatibilityRegistry.entries | Where-Object { $_.allowedSourceKind -ceq 'registry' }).Count -Message 'Exactly one pair uses official registry provenance'
    Assert-Equal -Expected 2 -Actual @($compatibilityRegistry.entries | Where-Object { $_.allowedSourceKind -ceq 'builtin' }).Count -Message 'Exactly two Unity 6 pairs use Editor-builtin provenance'
    Assert-Equal -Expected '18b9576da338b999a61157c9235f4ef3a91360cc877dbf49281a13f37e7da36b' -Actual $compatibilityRegistry.entries[0].packageTreeSha256 -Message 'Approved Test Framework identity is evidence-derived'
    foreach ($entry in @($compatibilityRegistry.entries)) {
        Assert-True -Condition ([string]$entry.unityExecutableSha256 -match '^[0-9a-f]{64}$') -Message "Approved Unity executable identity is pinned: $($entry.unityVersion)"
    }
    $builtinCompatibility = Get-UpvCompatibilityAssessment `
        -RegistryPath $script:CompatibilityPath `
        -UnityVersion '6000.0.69f1' `
        -TestFrameworkVersion '1.6.0'
    Assert-True -Condition $builtinCompatibility.approved -Message 'Unity 6000.0 builtin compatibility entry is approved'
    Assert-Equal -Expected 'builtin' -Actual $builtinCompatibility.allowedSourceKind -Message 'Unity 6000.0 compatibility source is Editor-builtin'
    Assert-True -Condition ($null -eq $builtinCompatibility.registryOrigin) -Message 'Builtin compatibility entry has no registry origin'
    Assert-Equal -Expected '3927c20e4c76f15951989fd4866546b03d3ebfcc72bb5d708cd6397fad50451d' -Actual $builtinCompatibility.unityExecutableSha256 -Message 'Builtin compatibility entry pins the accepted Editor binary'

    $invalidBuiltinOrigin = Get-Content -Raw -LiteralPath $script:CompatibilityPath | ConvertFrom-Json
    $invalidBuiltinOrigin.entries[1].registryOrigin = 'https://packages.unity.com'
    Assert-True -Condition (@(Invoke-JsonSchemaValidation -Instance $invalidBuiltinOrigin -SchemaPath $script:CompatibilitySchemaPath).Count -gt 0) -Message 'Schema oneOf rejects builtin entries with a registry origin'
    $invalidRegistryOrigin = Get-Content -Raw -LiteralPath $script:CompatibilityPath | ConvertFrom-Json
    $invalidRegistryOrigin.entries[0].registryOrigin = $null
    Assert-True -Condition (@(Invoke-JsonSchemaValidation -Instance $invalidRegistryOrigin -SchemaPath $script:CompatibilitySchemaPath).Count -gt 0) -Message 'Schema oneOf rejects registry entries without the official origin'

    $officialProvenanceRoot = New-UpvProvenanceFixture `
        -Name 'official' `
        -ManifestDependency '1.1.33' `
        -LockSource 'registry' `
        -LockUrl 'https://packages.unity.com'
    $officialProvenance = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $officialProvenanceRoot
    Assert-True -Condition $officialProvenance.accepted -Message ('Official registry provenance is accepted: ' + [string]::Join(' ', [string[]]$officialProvenance.errors))
    Assert-Equal -Expected 'https://packages.unity.com' -Actual $officialProvenance.registryOrigin -Message 'Official registry origin is canonicalized'
    Assert-True -Condition $officialProvenance.sourcePolicyMatched -Message 'Official registry source policy match is explicit'

    $builtinProvenanceRoot = New-UpvProvenanceFixture `
        -Name 'builtin' `
        -ManifestDependency '1.6.0' `
        -LockVersion '1.6.0' `
        -LockSource 'builtin'
    $builtinProvenance = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $builtinProvenanceRoot -AllowedSourceKinds @('builtin')
    Assert-True -Condition $builtinProvenance.accepted -Message ('Editor-builtin provenance is accepted only by its explicit policy: ' + [string]::Join(' ', [string[]]$builtinProvenance.errors))
    Assert-Equal -Expected 'builtin' -Actual $builtinProvenance.packagesLockSource -Message 'Builtin source remains explicit in evidence'
    Assert-True -Condition ($null -eq $builtinProvenance.registryOrigin) -Message 'Builtin source carries no registry origin'
    Assert-True -Condition $builtinProvenance.sourcePolicyMatched -Message 'Builtin source policy match is explicit'
    $builtinUnderRegistryPolicy = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $builtinProvenanceRoot -AllowedSourceKinds @('registry')
    Assert-True -Condition (-not $builtinUnderRegistryPolicy.accepted) -Message 'Builtin source cannot satisfy a registry-only compatibility entry'
    $registryUnderBuiltinPolicy = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $officialProvenanceRoot -AllowedSourceKinds @('builtin')
    Assert-True -Condition (-not $registryUnderBuiltinPolicy.accepted) -Message 'Registry source cannot satisfy an Editor-builtin compatibility entry'

    $builtinWithUrlRoot = New-UpvProvenanceFixture `
        -Name 'builtin-with-url' `
        -ManifestDependency '1.6.0' `
        -LockVersion '1.6.0' `
        -LockSource 'builtin' `
        -LockUrl 'https://packages.unity.com'
    Assert-True -Condition (-not (Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $builtinWithUrlRoot -AllowedSourceKinds @('builtin')).accepted) -Message 'Builtin provenance that claims a registry URL is rejected as ambiguous'

    $builtinScopedRoot = New-UpvProvenanceFixture `
        -Name 'builtin-scoped-registry' `
        -ManifestDependency '1.6.0' `
        -LockVersion '1.6.0' `
        -LockSource 'builtin' `
        -InterceptingScope 'com.unity'
    Assert-True -Condition (-not (Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $builtinScopedRoot -AllowedSourceKinds @('builtin')).accepted) -Message 'Builtin evidence does not bypass a scoped registry interceptor'

    $fileProvenanceRoot = New-UpvProvenanceFixture `
        -Name 'file' `
        -ManifestDependency 'file:../UntrustedTestFramework' `
        -LockSource 'local'
    $fileProvenance = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $fileProvenanceRoot
    Assert-True -Condition (-not $fileProvenance.accepted) -Message 'file: Test Framework with an approved package.json version is rejected before Unity'

    $embeddedProvenanceRoot = New-UpvProvenanceFixture `
        -Name 'embedded' `
        -ManifestDependency '1.1.33' `
        -LockSource 'embedded'
    $embeddedProvenance = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $embeddedProvenanceRoot
    Assert-True -Condition (-not $embeddedProvenance.accepted) -Message 'Embedded Test Framework is rejected'
    Assert-Equal -Expected 'embedded' -Actual $embeddedProvenance.packagesLockSource -Message 'Rejected embedded source remains visible in evidence'

    $gitProvenanceRoot = New-UpvProvenanceFixture `
        -Name 'git' `
        -ManifestDependency 'https://example.invalid/test-framework.git#v1.1.33' `
        -LockSource 'git'
    Assert-True -Condition (-not (Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $gitProvenanceRoot).accepted) -Message 'Git Test Framework is rejected'

    $tarballProvenanceRoot = New-UpvProvenanceFixture `
        -Name 'tarball' `
        -ManifestDependency 'https://example.invalid/com.unity.test-framework-1.1.33.tgz' `
        -LockSource 'local-tarball'
    Assert-True -Condition (-not (Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $tarballProvenanceRoot).accepted) -Message 'Tarball Test Framework is rejected'

    $scopedProvenanceRoot = New-UpvProvenanceFixture `
        -Name 'scoped-registry' `
        -ManifestDependency '1.1.33' `
        -LockSource 'registry' `
        -LockUrl 'https://packages.unity.com' `
        -InterceptingScope 'com.unity'
    $scopedProvenance = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $scopedProvenanceRoot
    Assert-True -Condition (-not $scopedProvenance.accepted) -Message 'Custom scoped registry that can claim com.unity.test-framework is rejected'
    Assert-Equal -Expected 1 -Actual @($scopedProvenance.scopedRegistryInterceptors).Count -Message 'Scoped-registry interceptor evidence is recorded'

    $approvedResolvedRoot = Add-UpvResolvedPackageFixture `
        -ProjectRoot $officialProvenanceRoot `
        -DirectoryName 'com.unity.test-framework@approved'
    $approvedSnapshot = Get-UpvPackageTreeSnapshot -PackageRoot $approvedResolvedRoot
    $approvedIdentity = Get-UpvResolvedTestFrameworkIdentityAssessment `
        -ProjectRoot $officialProvenanceRoot `
        -Provenance $officialProvenance `
        -ExpectedVersion '1.1.33' `
        -ExpectedSourceKind 'registry' `
        -ExpectedRegistryOrigin 'https://packages.unity.com' `
        -ExpectedTreeSha256 $approvedSnapshot.treeSha256 `
        -ExpectedCanonicalization $approvedSnapshot.canonicalization
    Assert-True -Condition $approvedIdentity.accepted -Message ('Official source and exact content hash are accepted: ' + [string]::Join(' ', [string[]]$approvedIdentity.errors))
    Assert-True -Condition $approvedIdentity.identityMatched -Message 'Exact resolved package identity is positively matched'
    Assert-Equal -Expected 2 -Actual $approvedIdentity.fileCount -Message 'Resolved package identity records every fixture file'
    Assert-True -Condition ($approvedIdentity.snapshotAttempts -ge 2) -Message 'Resolved package identity requires two consecutive stable snapshots'

    $builtinResolvedRoot = Add-UpvResolvedPackageFixture `
        -ProjectRoot $builtinProvenanceRoot `
        -DirectoryName 'com.unity.test-framework@builtin' `
        -PackageVersion '1.6.0' `
        -Payload 'approved builtin package payload'
    $builtinSnapshot = Get-UpvPackageTreeSnapshot -PackageRoot $builtinResolvedRoot
    $builtinIdentity = Get-UpvResolvedTestFrameworkIdentityAssessment `
        -ProjectRoot $builtinProvenanceRoot `
        -Provenance $builtinProvenance `
        -ExpectedVersion '1.6.0' `
        -ExpectedSourceKind 'builtin' `
        -ExpectedRegistryOrigin $null `
        -ExpectedTreeSha256 $builtinSnapshot.treeSha256 `
        -ExpectedCanonicalization $builtinSnapshot.canonicalization
    Assert-True -Condition $builtinIdentity.accepted -Message ('Editor-builtin source and exact content hash are accepted: ' + [string]::Join(' ', [string[]]$builtinIdentity.errors))
    Assert-True -Condition $builtinIdentity.identityMatched -Message 'Builtin resolved package identity is positively matched'
    Assert-Equal -Expected 'builtin' -Actual $builtinIdentity.expectedSourceKind -Message 'Builtin identity records its expected source kind'

    $mismatchedIdentity = Get-UpvResolvedTestFrameworkIdentityAssessment `
        -ProjectRoot $officialProvenanceRoot `
        -Provenance $officialProvenance `
        -ExpectedVersion '1.1.33' `
        -ExpectedSourceKind 'registry' `
        -ExpectedRegistryOrigin 'https://packages.unity.com' `
        -ExpectedTreeSha256 '0000000000000000000000000000000000000000000000000000000000000000' `
        -ExpectedCanonicalization $approvedSnapshot.canonicalization
    Assert-True -Condition (-not $mismatchedIdentity.accepted) -Message 'Approved version with different package content hash is rejected'
    Assert-True -Condition (-not $mismatchedIdentity.identityMatched) -Message 'Content mismatch is explicit in identity evidence'

    $missingIdentityRoot = New-UpvProvenanceFixture `
        -Name 'identity-missing' `
        -ManifestDependency '1.1.33' `
        -LockSource 'registry' `
        -LockUrl 'https://packages.unity.com'
    $missingIdentityProvenance = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $missingIdentityRoot
    $missingIdentity = Get-UpvResolvedTestFrameworkIdentityAssessment `
        -ProjectRoot $missingIdentityRoot `
        -Provenance $missingIdentityProvenance `
        -ExpectedVersion '1.1.33' `
        -ExpectedSourceKind 'registry' `
        -ExpectedRegistryOrigin 'https://packages.unity.com' `
        -ExpectedTreeSha256 $approvedSnapshot.treeSha256 `
        -ExpectedCanonicalization $approvedSnapshot.canonicalization
    Assert-True -Condition (-not $missingIdentity.accepted) -Message 'Missing resolved Test Framework package is rejected'

    $duplicateIdentityRoot = New-UpvProvenanceFixture `
        -Name 'identity-duplicate' `
        -ManifestDependency '1.1.33' `
        -LockSource 'registry' `
        -LockUrl 'https://packages.unity.com'
    [void](Add-UpvResolvedPackageFixture -ProjectRoot $duplicateIdentityRoot -DirectoryName 'com.unity.test-framework@one' -Payload 'one')
    [void](Add-UpvResolvedPackageFixture -ProjectRoot $duplicateIdentityRoot -DirectoryName 'com.unity.test-framework@two' -Payload 'two')
    $duplicateIdentity = Get-UpvResolvedTestFrameworkIdentityAssessment `
        -ProjectRoot $duplicateIdentityRoot `
        -Provenance (Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $duplicateIdentityRoot) `
        -ExpectedVersion '1.1.33' `
        -ExpectedSourceKind 'registry' `
        -ExpectedRegistryOrigin 'https://packages.unity.com' `
        -ExpectedTreeSha256 $approvedSnapshot.treeSha256 `
        -ExpectedCanonicalization $approvedSnapshot.canonicalization
    Assert-True -Condition (-not $duplicateIdentity.accepted) -Message 'Duplicate resolved Test Framework packages are rejected'
    Assert-Equal -Expected 2 -Actual $duplicateIdentity.candidateCount -Message 'Duplicate candidate count is recorded'

    $wrongVersionIdentityRoot = New-UpvProvenanceFixture `
        -Name 'identity-version' `
        -ManifestDependency '1.1.33' `
        -LockSource 'registry' `
        -LockUrl 'https://packages.unity.com'
    [void](Add-UpvResolvedPackageFixture -ProjectRoot $wrongVersionIdentityRoot -DirectoryName 'com.unity.test-framework@wrong' -PackageVersion '1.1.32')
    $wrongVersionIdentity = Get-UpvResolvedTestFrameworkIdentityAssessment `
        -ProjectRoot $wrongVersionIdentityRoot `
        -Provenance (Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $wrongVersionIdentityRoot) `
        -ExpectedVersion '1.1.33' `
        -ExpectedSourceKind 'registry' `
        -ExpectedRegistryOrigin 'https://packages.unity.com' `
        -ExpectedTreeSha256 $approvedSnapshot.treeSha256 `
        -ExpectedCanonicalization $approvedSnapshot.canonicalization
    Assert-True -Condition (-not $wrongVersionIdentity.accepted) -Message 'Resolved package.json version mismatch is rejected'

    $blockedPromotion = Get-UpvFinalStatusAssessment `
        -OriginalIntegrityStatus 'UNCHANGED' `
        -GitIntegrityStatus 'UNCHANGED' `
        -BlockerCount 1 `
        -FailureCount 0 `
        -CompatibilityStatus 'BLOCKED' `
        -RequiredScopeStatuses @('VERIFIED_SUCCESS', 'VERIFIED_SUCCESS', 'VERIFIED_SUCCESS')
    Assert-Equal -Expected 'VERIFICATION_BLOCKED' -Actual $blockedPromotion -Message 'Successful test evidence cannot promote a package identity blocker'
    $integrityPrecedence = Get-UpvFinalStatusAssessment `
        -OriginalIntegrityStatus 'UNCHANGED' `
        -GitIntegrityStatus 'CHANGED' `
        -BlockerCount 1 `
        -FailureCount 1 `
        -CompatibilityStatus 'BLOCKED' `
        -RequiredScopeStatuses @('VERIFIED_FAILURE')
    Assert-Equal -Expected 'ORIGINAL_PROJECT_CHANGED' -Actual $integrityPrecedence -Message 'Git metadata change retains highest final-status precedence'

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

    $passedNUnitAnalysis = Get-UpvNUnitAnalysis -Path (Join-Path $nunitRoot 'passed.xml')
    $malformedNUnitAnalysis = Get-UpvNUnitAnalysis -Path (Join-Path $nunitRoot 'malformed.xml')
    $conflictingScopes = Get-UpvBaseVerificationScopeAssessment -EditorLog $failureLogAnalysis -NUnit $passedNUnitAnalysis -ExitCode 0
    Assert-Equal -Expected 'VERIFIED_FAILURE' -Actual $conflictingScopes.scriptCompilation.status -Message 'Editor.log failure overrides a successful NUnit XML for compilation'
    Assert-Equal -Expected 'BLOCKED' -Actual $conflictingScopes.playModeTests.status -Message 'Successful XML plus failing Editor.log is an evidence conflict, not a pass'
    Assert-True -Condition $conflictingScopes.evidenceConflict -Message 'XML success and Editor.log failure conflict is explicit'
    $malformedScopes = Get-UpvBaseVerificationScopeAssessment -EditorLog $safeLogAnalysis -NUnit $malformedNUnitAnalysis -ExitCode 0
    Assert-Equal -Expected 'BLOCKED' -Actual $malformedScopes.scriptCompilation.status -Message 'Malformed NUnit XML cannot promote script compilation'
    Assert-Equal -Expected 'BLOCKED' -Actual $malformedScopes.playModeTests.status -Message 'Malformed NUnit XML blocks PlayMode verification'

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

    $compileFailureBundle = Join-Path $script:ScratchRoot 'compile-failure-bundle'
    Copy-Item -LiteralPath $script:TemplatePath -Destination $compileFailureBundle -Recurse -Force
    $compileFailureSource = Join-Path $compileFailureBundle 'SampleScenarioTests.cs'
    Write-TestText -Path $compileFailureSource -Content ((Get-Content -Raw -LiteralPath $compileFailureSource) + [Environment]::NewLine + 'this is intentionally invalid C#;')
    $compileFailureBundleAssessment = Get-UpvScenarioBundleAssessment -BundlePath $compileFailureBundle -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    Assert-True -Condition $compileFailureBundleAssessment.accepted -Message 'Source-only scenario validation does not claim to compile C# before isolated Unity execution'
    $compileFailureScopes = Get-UpvBaseVerificationScopeAssessment -EditorLog $failureLogAnalysis -NUnit $malformedNUnitAnalysis -ExitCode 1
    Assert-Equal -Expected 'VERIFIED_FAILURE' -Actual $compileFailureScopes.scriptCompilation.status -Message 'Scenario overlay compiler error is classified as a concrete compilation failure'
    $compileFailureFinalStatus = Get-UpvFinalStatusAssessment `
        -OriginalIntegrityStatus 'UNCHANGED' `
        -GitIntegrityStatus 'UNCHANGED' `
        -BlockerCount 0 `
        -FailureCount 1 `
        -CompatibilityStatus 'VERIFIED_SUCCESS' `
        -RequiredScopeStatuses @('VERIFIED_FAILURE', 'BLOCKED', 'BLOCKED', 'NOT_VERIFIED')
    Assert-Equal -Expected 'PLAY_FAILED' -Actual $compileFailureFinalStatus -Message 'Scenario overlay compilation failure is not mislabeled as blocked or verified'

    $unsafeBundle = Join-Path $script:ScratchRoot 'unsafe-bundle'
    Write-TestText -Path (Join-Path $unsafeBundle 'manifest.json') -Content (Get-Content -Raw -LiteralPath (Join-Path $script:TemplatePath 'manifest.json'))
    Write-TestText -Path (Join-Path $unsafeBundle 'unsafe.dll') -Content 'not-a-binary'
    $unsafeBundleAssessment = Get-UpvScenarioBundleAssessment -BundlePath $unsafeBundle -ProjectRoot $script:FixturePath -ProcessTimeoutSeconds 1800
    Assert-True -Condition (-not $unsafeBundleAssessment.accepted) -Message 'Precompiled scenario file is rejected'

    $reservedCollisionRoot = Join-Path $script:ScratchRoot 'reserved-overlay-collision'
    [void][System.IO.Directory]::CreateDirectory((Join-Path $reservedCollisionRoot 'Assets\__UnityPlayVerification'))
    $reservedCollision = Get-UpvReservedScenarioOverlayAssessment -ProjectCopyPath $reservedCollisionRoot
    Assert-True -Condition $reservedCollision.collision -Message 'Existing Assets/__UnityPlayVerification path is detected'
    Assert-True -Condition (-not $reservedCollision.accepted) -Message 'Reserved scenario overlay collision is rejected'

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

    $gitIntegrityProject = Join-Path $script:ScratchRoot 'git-integrity-project'
    [void][System.IO.Directory]::CreateDirectory((Join-Path $gitIntegrityProject '.git'))
    Write-TestText -Path (Join-Path $gitIntegrityProject '.git\HEAD') -Content "ref: refs/heads/main`n"
    $gitBefore = Get-BaselineGitMetadataSnapshot -ProjectRoot $gitIntegrityProject
    Write-TestText -Path (Join-Path $gitIntegrityProject '.git\HEAD') -Content "ref: refs/heads/changed`n"
    $gitAfter = Get-BaselineGitMetadataSnapshot -ProjectRoot $gitIntegrityProject
    $gitAssessment = Get-BaselineGitMetadataAssessment -Before $gitBefore -After $gitAfter
    Assert-Equal -Expected 'CHANGED' -Actual $gitAssessment.status -Message 'Git metadata byte mutation is detected'

    $localSpoofProject = Join-Path $script:ScratchRoot 'local-test-framework-spoof'
    Copy-Item -LiteralPath $script:FixturePath -Destination $localSpoofProject -Recurse -Force
    $localSpoofManifestPath = Join-Path $localSpoofProject 'Packages\manifest.json'
    $localSpoofManifest = Get-Content -Raw -LiteralPath $localSpoofManifestPath | ConvertFrom-Json
    $localSpoofManifest.dependencies.'com.unity.test-framework' = 'file:UntrustedTestFramework'
    Write-TestText -Path $localSpoofManifestPath -Content (ConvertTo-Json -Depth 10 -InputObject $localSpoofManifest)
    $localSpoofLockPath = Join-Path $localSpoofProject 'Packages\packages-lock.json'
    $localSpoofLock = Get-Content -Raw -LiteralPath $localSpoofLockPath | ConvertFrom-Json
    $localSpoofLock.dependencies.'com.unity.test-framework'.source = 'local'
    $localSpoofLock.dependencies.'com.unity.test-framework'.PSObject.Properties.Remove('url')
    Write-TestText -Path $localSpoofLockPath -Content (ConvertTo-Json -Depth 10 -InputObject $localSpoofLock)
    Write-TestText -Path (Join-Path $localSpoofProject 'Packages\UntrustedTestFramework\package.json') -Content '{"name":"com.unity.test-framework","version":"1.1.33"}'
    $localSpoofProduction = Invoke-TestVerifier -Arguments @('-ProjectRoot', $localSpoofProject)
    Assert-True -Condition $localSpoofProduction.result.preflight.localPackagesSafe -Message 'Reproduction reaches provenance after the project-local file package passes copy safety'
    Assert-Equal -Expected 'local' -Actual $localSpoofProduction.result.compatibility.provenance.packagesLockSource -Message 'Rejected production evidence records the actual local package source'
    Assert-True -Condition (@($localSpoofProduction.result.blockers | Where-Object { $_.code -eq 'TEST_FRAMEWORK_PROVENANCE_REJECTED' }).Count -eq 1) -Message 'Production entrypoint blocks same-version local Test Framework provenance'
    Assert-True -Condition (-not $localSpoofProduction.result.unity.processStarted) -Message 'Local Test Framework spoof is blocked before Unity starts'
    Assert-Equal -Expected 'VERIFICATION_BLOCKED' -Actual $localSpoofProduction.result.finalStatus -Message 'Local Test Framework spoof cannot reach PLAY_VERIFIED'

    $fakeUnityPath = New-UpvUnsignedFakeUnity `
        -OutputPath (Join-Path $script:ScratchRoot 'fake-unity\2022.3.62f3\Editor\Unity.exe') `
        -ProductVersion '2022.3.62f3_fixture'
    Assert-True -Condition ((Get-Item -LiteralPath $fakeUnityPath).VersionInfo.ProductVersion -match '^2022\.3\.62f3(?:_|$)') -Message 'Unsigned fake exposes the approved exact ProductVersion token'
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
    Write-TestText -Path (Join-Path $approvedFixturePath 'ProjectSettings\ProjectVersion.txt') -Content "m_EditorVersion: 2022.3.62f3`r`nm_EditorVersionWithRevision: 2022.3.62f3 (96770f904ca7)`r`n"
    $approvedLockPath = Join-Path $approvedFixturePath 'Packages\packages-lock.json'
    $approvedLock = Get-Content -Raw -LiteralPath $approvedLockPath | ConvertFrom-Json
    $approvedLock.dependencies.'com.unity.test-framework'.url = 'https://packages.unity.com'
    Write-TestText -Path $approvedLockPath -Content (ConvertTo-Json -Depth 10 -InputObject $approvedLock)
    $unsignedProduction = Invoke-TestVerifier -Arguments @('-ProjectRoot', $approvedFixturePath, '-UnityExecutable', $fakeUnityPath)
    Assert-Equal -Expected 'VERIFICATION_BLOCKED' -Actual $unsignedProduction.result.finalStatus -Message 'Production entrypoint blocks exact-version unsigned fake Unity'
    Assert-True -Condition (-not $unsignedProduction.result.unity.processStarted) -Message 'Production entrypoint never starts unsigned fake Unity'
    $sourcePreflightUnavailable = @($unsignedProduction.result.blockers | Where-Object { $_.code -eq 'SOURCE_EDITOR_PREFLIGHT_UNAVAILABLE' }).Count -gt 0
    if ($sourcePreflightUnavailable) {
        Assert-True -Condition $true -Message 'Production trust check remains fail-closed when local CIM access prevents reaching the signature gate'
    } else {
        Assert-True -Condition $unsignedProduction.result.unity.executableVersionMatched -Message 'Production fake reaches trust validation with matching ProductVersion'
        $unsignedTrustBlockers = @($unsignedProduction.result.blockers | Where-Object { $_.code -eq 'UNITY_EXECUTABLE_REJECTED' })
        Assert-Equal -Expected 1 -Actual $unsignedTrustBlockers.Count -Message 'Production unsigned fake is rejected by the executable trust gate'
        Assert-True -Condition ($unsignedTrustBlockers[0].message -match '(?i)signature|signed|publisher') -Message 'Production trust rejection is specifically signature or publisher related'
        if (-not [string]::IsNullOrWhiteSpace([string]$unsignedProduction.result.unity.signatureStatus)) {
            Assert-Equal -Expected 'NotSigned' -Actual $unsignedProduction.result.unity.signatureStatus -Message 'Production result records unsigned Authenticode status when the host exposes it'
        }
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

    $insideArtifactRoot = Join-Path $script:FixturePath '__forbidden-upv-artifacts'
    $insideArtifacts = Invoke-TestVerifier -Arguments @('-ProjectRoot', $script:FixturePath, '-ArtifactsRoot', $insideArtifactRoot)
    Assert-Equal -Expected 'VERIFICATION_BLOCKED' -Actual $insideArtifacts.result.finalStatus -Message 'ArtifactsRoot inside the original project is blocked'
    Assert-True -Condition (@($insideArtifacts.result.blockers | Where-Object { $_.code -eq 'ARTIFACT_ROOT_REJECTED' }).Count -eq 1) -Message 'Artifact boundary blocker is explicit'
    Assert-True -Condition (-not (Test-Path -LiteralPath $insideArtifactRoot)) -Message 'Rejected in-project ArtifactsRoot is never created'

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
    Assert-True -Condition ($argumentContractContent -match "OriginalIntegrityStatus -ceq 'CHANGED'") -Message 'Final-status precedence detects changed original copy-set'
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
