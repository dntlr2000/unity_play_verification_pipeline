[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$ProjectRoot = (Get-Location).Path,

    [Parameter()]
    [AllowNull()]
    [string]$UnityExecutable,

    [Parameter()]
    [AllowNull()]
    [string]$ArtifactsRoot,

    [Parameter()]
    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = 1800,

    [Parameter()]
    [AllowNull()]
    [string]$TestFilter,

    [Parameter()]
    [AllowNull()]
    [string]$TestCategory,

    [Parameter()]
    [AllowNull()]
    [string]$AssemblyNames,

    [Parameter()]
    [AllowNull()]
    [string]$ScenarioBundlePath,

    [Parameter()]
    [switch]$Pretty
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:SchemaVersion = '1.0.0'
$script:ComponentVersion = '0.2.0'
$script:VerifierVersion = '0.2.0'
$script:ExpectedDoctorSchemaVersion = '1.1.0'
$script:ExpectedDoctorScannerVersion = '0.2.1'
$script:SkillRoot = Split-Path -Parent $PSScriptRoot
$script:VendorRoot = Join-Path -Path $PSScriptRoot -ChildPath 'vendor'
$script:DoctorScannerPath = Join-Path -Path $script:VendorRoot -ChildPath 'doctor\inspect-unity-project.ps1'
$script:FingerprintLibraryPath = Join-Path -Path $script:VendorRoot -ChildPath 'doctor\lib\unity-project-fingerprint.ps1'
$script:SharedLibraryRoot = Join-Path -Path $script:VendorRoot -ChildPath 'shared'
$script:OrchestrationLibraryPath = Join-Path -Path $script:SharedLibraryRoot -ChildPath 'unity-baseline-orchestration.ps1'
$script:ProcessLibraryPath = Join-Path -Path $script:SharedLibraryRoot -ChildPath 'unity-process-job.ps1'
$script:GitIntegrityLibraryPath = Join-Path -Path $script:SharedLibraryRoot -ChildPath 'git-metadata-integrity.ps1'
$script:IsolationPathBudgetLibraryPath = Join-Path -Path $script:SharedLibraryRoot -ChildPath 'unity-isolation-path-budget.ps1'
$script:CoreLibraryPath = Join-Path -Path $PSScriptRoot -ChildPath 'lib\unity-play-verification-core.ps1'
$script:IdentityLibraryPath = Join-Path -Path $PSScriptRoot -ChildPath 'lib\unity-test-framework-identity.ps1'
$script:CompatibilityRegistryPath = Join-Path -Path $script:SkillRoot -ChildPath 'config\unity-play-compatibility.json'
$script:HarnessRoot = Join-Path -Path $script:SkillRoot -ChildPath 'harness'
$script:Blockers = New-Object System.Collections.ArrayList
$script:Failures = New-Object System.Collections.ArrayList
$script:Warnings = New-Object System.Collections.ArrayList
$script:Evidence = New-Object System.Collections.ArrayList
$script:EvidenceSequence = 0
$script:NormalizedProjectRoot = $null
$script:SessionRoot = $null
$script:OriginalFingerprintBefore = $null
$script:OriginalFingerprintAfter = $null
$script:GitSnapshotBefore = $null
$script:GitSnapshotAfter = $null
$script:ScenarioBundle = $null
$script:TestFrameworkProvenance = $null
$script:CompatibilityAssessment = $null

[Console]::OutputEncoding = $script:Utf8NoBom

foreach ($libraryPath in @(
    $script:FingerprintLibraryPath,
    $script:OrchestrationLibraryPath,
    $script:ProcessLibraryPath,
    $script:GitIntegrityLibraryPath,
    $script:IsolationPathBudgetLibraryPath,
    $script:CoreLibraryPath,
    $script:IdentityLibraryPath
)) {
    if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
        throw "Required Unity Play Verification library was not found: $libraryPath"
    }
    . $libraryPath
}

# Creates the stable result shape before any validation or filesystem write occurs.
function New-UpvResult {
    return [ordered]@{
        schemaVersion = $script:SchemaVersion
        componentVersion = $script:ComponentVersion
        verifierVersion = $script:VerifierVersion
        projectRoot = $null
        doctor = [ordered]@{
            sourcePath = $null
            sha256 = $null
            schemaVersion = $null
            scannerVersion = $null
            projectRoot = $null
            finalStatus = $null
            warningCount = 0
            warnings = @()
            blockedCheckCount = 0
            fingerprintMatched = $false
            accepted = $false
        }
        compatibility = [ordered]@{
            registryPath = $script:CompatibilityRegistryPath
            registrySchemaVersion = $null
            verificationStatus = 'NOT_VERIFIED'
            reason = 'Test Framework provenance and resolved package identity have not been verified.'
            unityVersion = $null
            testFrameworkVersion = $null
            testFrameworkSource = $null
            entryFound = $false
            entryStatus = $null
            allowedSourceKind = $null
            registryOrigin = $null
            unityExecutableSha256 = $null
            packageTreeSha256 = $null
            hashCanonicalization = $null
            evidencePath = $null
            approved = $false
            provenance = [ordered]@{
                packageName = 'com.unity.test-framework'
                manifestPath = $null
                packagesLockPath = $null
                manifestDependency = $null
                declaredVersion = $null
                resolvedVersion = $null
                packagesLockSource = $null
                packagesLockUrl = $null
                registryOrigin = $null
                expectedRegistryOrigin = $null
                registryOriginMatched = $false
                allowedSourceKinds = @()
                sourcePolicyMatched = $false
                scopedRegistryInterceptors = @()
                sourceEvidence = @()
                accepted = $false
                errors = @()
            }
            postRunProvenance = [ordered]@{
                packageName = 'com.unity.test-framework'
                manifestPath = $null
                packagesLockPath = $null
                manifestDependency = $null
                declaredVersion = $null
                resolvedVersion = $null
                packagesLockSource = $null
                packagesLockUrl = $null
                registryOrigin = $null
                expectedRegistryOrigin = $null
                registryOriginMatched = $false
                allowedSourceKinds = @()
                sourcePolicyMatched = $false
                scopedRegistryInterceptors = @()
                sourceEvidence = @()
                accepted = $false
                errors = @()
            }
            packageIdentity = [ordered]@{
                packageName = 'com.unity.test-framework'
                declaredVersion = $null
                resolvedVersion = $null
                packagesLockSource = $null
                registryOrigin = $null
                expectedSourceKind = $null
                expectedRegistryOrigin = $null
                sourceEvidence = @()
                packageCacheRoot = $null
                resolvedPackagePath = $null
                candidateCount = 0
                fileCount = 0
                snapshotAttempts = 0
                hashCanonicalization = $null
                treeSha256 = $null
                expectedTreeSha256 = $null
                identityMatched = $false
                accepted = $false
                errors = @()
            }
        }
        unity = [ordered]@{
            executablePath = $null
            executableSha256 = $null
            fileVersion = $null
            productVersion = $null
            detectedExecutableVersion = $null
            executableVersionMatched = $false
            signatureStatus = $null
            signerSubject = $null
            certificateThumbprint = $null
            publisherMatched = $false
            resolutionStatus = $null
            resolutionSource = $null
            candidates = @()
            arguments = @()
            commandLineContainsOriginalProject = $null
            processStarted = $false
            timedOut = $false
            exitCode = $null
        }
        selection = [ordered]@{
            mode = if ([string]::IsNullOrWhiteSpace($ScenarioBundlePath)) { 'PROJECT_PLAYMODE_TESTS' } else { 'SCENARIO_OVERLAY' }
            testFilter = $TestFilter
            testCategory = $TestCategory
            assemblyNames = $AssemblyNames
            scenarioId = $null
        }
        preflight = [ordered]@{
            artifactRootOutsideProject = $false
            trustedPathsWithoutReparse = $false
            noRunningUnityProcesses = $false
            observedUnityProcessCount = 0
            sourceEditorCheckCompleted = $false
            sourceEditorDetected = $null
            sourceEditorProcessIds = @()
            sourceFingerprintStable = $false
            localPackagesSafe = $false
            isolatedLocalPackagesSafe = $false
        }
        processControl = [ordered]@{
            rootProcessId = $null
            jobObjectCreated = $false
            killOnJobCloseConfigured = $false
            processAssignedToJob = $false
            terminationRequested = $false
            terminationReason = $null
            terminationApiSucceeded = $null
            rootProcessExited = $false
            processTreeExitVerified = $false
            activeProcessCountAfterWait = $null
            treeExitWaitMilliseconds = 0
            controlError = $null
        }
        isolation = [ordered]@{
            artifactsRoot = $null
            sessionRoot = $null
            projectCopyPath = $null
            status = 'NOT_STARTED'
            copiedDirectoryCount = 0
            copiedFileCount = 0
            excludedTopLevelPaths = [string[]](Get-UnityCopyExcludedTopLevelNames)
            sourceFingerprint = $null
            baseCopyFingerprint = $null
            baseCopyMatched = $false
            overlayInjected = $false
            overlayPath = $null
            scenarioBundleSha256 = $null
            harnessSha256 = $null
            localPackageReferences = @()
        }
        artifacts = [ordered]@{
            doctorResultPath = $null
            doctorStderrPath = $null
            editorLogPath = $null
            upmLogPath = $null
            testResultsPath = $null
            standardOutputPath = $null
            standardErrorPath = $null
            scenarioResultPath = $null
            screenshotRoot = $null
            resultPath = $null
            resultWritten = $false
        }
        nunit = [ordered]@{
            exists = $false
            byteLength = $null
            sha256 = $null
            format = $null
            rootResult = $null
            total = 0
            executed = 0
            passed = 0
            failed = 0
            skipped = 0
            inconclusive = 0
            assertions = 0
            durationSeconds = $null
            failureDetails = @()
            classification = 'NOT_ANALYZED'
            error = $null
        }
        editorLog = [ordered]@{
            exists = $false
            byteLength = $null
            sha256 = $null
            detectedUnityVersion = $null
            versionMatched = $false
            batchModeObserved = $false
            isolatedProjectPathObserved = $false
            testRunnerObserved = $false
            compilerErrors = @()
            compilerErrorCount = 0
            failureMarkers = @()
            missingRequiredMarkers = @()
            classification = 'NOT_ANALYZED'
        }
        scenario = [ordered]@{
            requested = -not [string]::IsNullOrWhiteSpace($ScenarioBundlePath)
            bundlePath = $null
            manifestPath = $null
            schemaVersion = $null
            scenarioId = $null
            displayName = $null
            testFilter = $null
            timeoutSeconds = $null
            requiresGraphics = $null
            expectedScenes = @()
            expectedAssertionIds = @()
            screenshotIds = @()
            files = @()
            fileCount = 0
            treeSha256 = $null
            bundleAccepted = $false
            bundleErrors = @()
            receiptExists = $false
            receiptSha256 = $null
            receiptCompleted = $false
            receiptError = $null
            observedScenes = @()
            assertions = @()
            captureReceipts = @()
            screenshots = @()
            receiptAccepted = $false
            receiptErrors = @()
        }
        originalProjectIntegrity = [ordered]@{
            scope = 'PLAY_COPY_SET'
            status = 'NOT_VERIFIED'
            beforeDirectoryCount = $null
            afterDirectoryCount = $null
            beforeFileCount = $null
            afterFileCount = $null
            beforeTreeSha256 = $null
            afterTreeSha256 = $null
            unchanged = $null
        }
        gitMetadataIntegrity = [ordered]@{
            scope = '.git'
            status = 'NOT_VERIFIED'
            presentBefore = $null
            presentAfter = $null
            beforeTreeSha256 = $null
            afterTreeSha256 = $null
            unchanged = $null
            ambientChangesAllowed = $false
            allowedAdditionPrefix = '.git/refs/codex/turn-diffs/checkpoints/'
            addedDirectories = @()
            removedDirectories = @()
            addedFiles = @()
            removedFiles = @()
            changedFiles = @()
        }
        verification = [ordered]@{
            scriptCompilation = [ordered]@{ status = 'NOT_VERIFIED'; reason = 'Unity has not produced compilation evidence.' }
            editorPlayMode = [ordered]@{ status = 'NOT_VERIFIED'; reason = 'Editor PlayMode tests have not run.' }
            playModeTests = [ordered]@{ status = 'NOT_VERIFIED'; reason = 'No PlayMode result has been classified.' }
            scenarioBehavior = [ordered]@{ status = 'NOT_VERIFIED'; reason = 'No scenario overlay was requested.' }
            visualEvidence = [ordered]@{ status = 'NOT_VERIFIED'; reason = 'No screenshot evidence was requested.' }
            playerBuild = [ordered]@{ status = 'NOT_VERIFIED'; reason = 'No Player Build was run.' }
        }
        warnings = @()
        failures = @()
        blockers = @()
        finalStatus = 'VERIFICATION_BLOCKED'
        evidence = @()
    }
}

$script:Result = New-UpvResult

# Adds one ordered evidence record to the public result.
function Add-UpvEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$Check,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter()][AllowNull()][string]$Source,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $script:EvidenceSequence++
    [void]$script:Evidence.Add([ordered]@{
        sequence = $script:EvidenceSequence
        check = $Check
        status = $Status
        source = $Source
        detail = $Detail
    })
}

# Adds one fail-closed prerequisite or evidence blocker.
function Add-UpvBlocker {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Check,
        [Parameter()][AllowNull()][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )

    [void]$script:Blockers.Add([ordered]@{ code = $Code; check = $Check; path = $Path; message = $Message })
}

# Marks the Test Framework provenance or content-identity contract explicitly blocked.
function Set-UpvCompatibilityBlocked {
    param(
        [Parameter(Mandatory = $true)][string]$Reason
    )

    $script:Result.compatibility.verificationStatus = 'BLOCKED'
    $script:Result.compatibility.reason = $Reason
}

# Adds one concrete compilation, test, crash, or scenario failure.
function Add-UpvFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Check,
        [Parameter()][AllowNull()][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )

    [void]$script:Failures.Add([ordered]@{ code = $Code; check = $Check; path = $Path; message = $Message })
}

# Adds one non-blocking diagnostic that does not promote or demote evidence.
function Add-UpvWarning {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Check,
        [Parameter()][AllowNull()][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )

    [void]$script:Warnings.Add([ordered]@{ code = $Code; check = $Check; path = $Path; message = $Message })
}

# Writes one UTF-8 text artifact without a byte-order mark.
function Write-UpvText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $reparsePoint = Get-UpvReparsePointOnPath -Path $Path
    if ($null -ne $reparsePoint) {
        throw "Refusing to write through reparse point $reparsePoint."
    }
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    [void][System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

# Creates a short external artifact session after validating its boundary.
function Initialize-UpvArtifactSession {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedRoot
    )

    $root = Get-UpvNormalizedPath -Path $RequestedRoot
    if (Test-UpvPathWithinRoot -Path $root -Root $script:NormalizedProjectRoot) {
        throw 'ArtifactsRoot must be outside the original Unity project.'
    }
    $reparsePoint = Get-UpvReparsePointOnPath -Path $root
    if ($null -ne $reparsePoint) {
        throw "ArtifactsRoot traverses reparse point $reparsePoint."
    }
    if (Test-Path -LiteralPath $root -PathType Leaf) {
        throw 'ArtifactsRoot is an existing file.'
    }

    [void][System.IO.Directory]::CreateDirectory($root)
    $session = Join-Path -Path $root -ChildPath ('s-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($session)
    if ($null -ne (Get-UpvReparsePointOnPath -Path $session)) {
        throw 'Created artifact session traverses a reparse point.'
    }

    $script:SessionRoot = Get-UpvNormalizedPath -Path $session
    $script:Result.preflight.artifactRootOutsideProject = $true
    $script:Result.preflight.trustedPathsWithoutReparse = $true
    $script:Result.isolation.artifactsRoot = $root
    $script:Result.isolation.sessionRoot = $script:SessionRoot
    $script:Result.isolation.projectCopyPath = Join-Path -Path $script:SessionRoot -ChildPath 'p'
    $script:Result.artifacts.doctorResultPath = Join-Path -Path $script:SessionRoot -ChildPath 'doctor.json'
    $script:Result.artifacts.doctorStderrPath = Join-Path -Path $script:SessionRoot -ChildPath 'doctor-stderr.log'
    $script:Result.artifacts.editorLogPath = Join-Path -Path $script:SessionRoot -ChildPath 'Editor.log'
    $script:Result.artifacts.upmLogPath = Join-Path -Path $script:SessionRoot -ChildPath 'upm.log'
    $script:Result.artifacts.testResultsPath = Join-Path -Path $script:SessionRoot -ChildPath 'test-results.xml'
    $script:Result.artifacts.standardOutputPath = Join-Path -Path $script:SessionRoot -ChildPath 'unity-stdout.log'
    $script:Result.artifacts.standardErrorPath = Join-Path -Path $script:SessionRoot -ChildPath 'unity-stderr.log'
    $script:Result.artifacts.scenarioResultPath = Join-Path -Path $script:SessionRoot -ChildPath 'scenario-result.json'
    $script:Result.artifacts.screenshotRoot = Join-Path -Path $script:SessionRoot -ChildPath 'screenshots'
    $script:Result.artifacts.resultPath = Join-Path -Path $script:SessionRoot -ChildPath 'result.json'
    Add-UpvEvidence -Check 'artifactBoundary' -Status 'PASSED' -Source $script:SessionRoot -Detail 'All mutable artifacts are outside the original project and traverse no reparse point.'
}

# Captures stable source and Git metadata evidence before any Unity process can start.
function Initialize-UpvOriginalIntegrity {
    try {
        $script:OriginalFingerprintBefore = Get-StableUnityCopySetFingerprint -ProjectRoot $script:NormalizedProjectRoot
        $script:Result.preflight.sourceFingerprintStable = $true
        $script:Result.isolation.sourceFingerprint = $script:OriginalFingerprintBefore.treeSha256
        $script:Result.originalProjectIntegrity.beforeDirectoryCount = $script:OriginalFingerprintBefore.directoryCount
        $script:Result.originalProjectIntegrity.beforeFileCount = $script:OriginalFingerprintBefore.fileCount
        $script:Result.originalProjectIntegrity.beforeTreeSha256 = $script:OriginalFingerprintBefore.treeSha256
        Add-UpvEvidence -Check 'sourceFingerprint' -Status 'PASSED' -Source $script:NormalizedProjectRoot -Detail "Stable source fingerprint $($script:OriginalFingerprintBefore.treeSha256) was captured in two passes."
    } catch {
        Add-UpvBlocker -Code 'SOURCE_FINGERPRINT_BLOCKED' -Check 'sourceFingerprint' -Path $script:NormalizedProjectRoot -Message $_.Exception.Message
    }

    try {
        $script:GitSnapshotBefore = Get-BaselineGitMetadataSnapshot -ProjectRoot $script:NormalizedProjectRoot
        $script:Result.gitMetadataIntegrity.presentBefore = [bool]$script:GitSnapshotBefore.present
        $script:Result.gitMetadataIntegrity.beforeTreeSha256 = [string]$script:GitSnapshotBefore.treeSha256
    } catch {
        Add-UpvBlocker -Code 'GIT_METADATA_SNAPSHOT_BLOCKED' -Check 'gitMetadataIntegrity' -Path $script:NormalizedProjectRoot -Message $_.Exception.Message
    }
}

# Runs the bundled Doctor scanner and validates the exact handoff contract.
function Invoke-UpvDoctorPreflight {
    try {
        $process = Invoke-OrchestrationPowerShellScript `
            -ScriptPath $script:DoctorScannerPath `
            -Arguments @('-ProjectRoot', $script:NormalizedProjectRoot) `
            -WorkingDirectory $script:SkillRoot
        Write-UpvText -Path $script:Result.artifacts.doctorStderrPath -Content ([string]$process.stderr)
        if ($process.exitCode -ne 0) {
            throw "Doctor scanner exited with code $($process.exitCode)."
        }
        $stdout = ([string]$process.stdout).Trim()
        if ([string]::IsNullOrWhiteSpace($stdout)) {
            throw 'Doctor scanner produced empty stdout.'
        }
        $doctor = ConvertFrom-Json -InputObject $stdout -ErrorAction Stop
        Write-UpvText -Path $script:Result.artifacts.doctorResultPath -Content $stdout
        $script:Result.doctor.sourcePath = $script:Result.artifacts.doctorResultPath
        $script:Result.doctor.sha256 = Get-UpvFileSha256 -Path $script:Result.artifacts.doctorResultPath
        $script:Result.doctor.schemaVersion = [string](Get-UpvJsonProperty -InputObject $doctor -Name 'schemaVersion')
        $script:Result.doctor.scannerVersion = [string](Get-UpvJsonProperty -InputObject $doctor -Name 'scannerVersion')
        $script:Result.doctor.projectRoot = [string](Get-UpvJsonProperty -InputObject $doctor -Name 'projectRoot')
        $script:Result.doctor.finalStatus = [string](Get-UpvJsonProperty -InputObject $doctor -Name 'finalStatus')
        $script:Result.doctor.warnings = @((Get-UpvJsonProperty -InputObject $doctor -Name 'warnings'))
        $script:Result.doctor.warningCount = $script:Result.doctor.warnings.Count
        $blockedChecks = @((Get-UpvJsonProperty -InputObject $doctor -Name 'blockedChecks'))
        $script:Result.doctor.blockedCheckCount = $blockedChecks.Count

        if ($script:Result.doctor.schemaVersion -cne $script:ExpectedDoctorSchemaVersion) {
            throw "Doctor schemaVersion must be $($script:ExpectedDoctorSchemaVersion)."
        }
        if ($script:Result.doctor.scannerVersion -cne $script:ExpectedDoctorScannerVersion) {
            throw "Doctor scannerVersion must be $($script:ExpectedDoctorScannerVersion)."
        }
        if (-not (Get-UpvNormalizedPath -Path $script:Result.doctor.projectRoot).Equals($script:NormalizedProjectRoot, $script:UpvPathComparison)) {
            throw 'Doctor projectRoot does not match the requested project.'
        }
        if ($script:Result.doctor.finalStatus -notin @('STATIC_AUDIT_COMPLETE', 'STATIC_AUDIT_COMPLETE_WITH_WARNINGS')) {
            throw "Doctor finalStatus is not accepted: $($script:Result.doctor.finalStatus)"
        }
        if ($blockedChecks.Count -ne 0) {
            throw 'Doctor reported one or more blocked checks.'
        }
        $fingerprint = Get-UpvJsonProperty -InputObject $doctor -Name 'projectFingerprint'
        if ([string](Get-UpvJsonProperty -InputObject $fingerprint -Name 'status') -cne 'COMPUTED') {
            throw 'Doctor project fingerprint is not COMPUTED.'
        }
        if ($null -eq $script:OriginalFingerprintBefore) {
            throw 'The verifier source fingerprint is unavailable.'
        }
        $script:Result.doctor.fingerprintMatched = (
            [string](Get-UpvJsonProperty -InputObject $fingerprint -Name 'treeSha256') -ceq
            [string]$script:OriginalFingerprintBefore.treeSha256
        )
        if (-not $script:Result.doctor.fingerprintMatched) {
            throw 'Doctor fingerprint does not match the fresh verifier fingerprint.'
        }
        $unityVersionContainer = Get-UpvJsonProperty -InputObject $doctor -Name 'unityEditorVersion'
        $unityVersion = [string](Get-UpvJsonProperty -InputObject $unityVersionContainer -Name 'editorVersion')
        if ([string]::IsNullOrWhiteSpace($unityVersion)) {
            throw 'Doctor did not parse the project Unity version.'
        }
        $script:Result.compatibility.unityVersion = $unityVersion
        $script:Result.doctor.accepted = $true
        Add-UpvEvidence -Check 'doctor' -Status 'PASSED' -Source $script:Result.artifacts.doctorResultPath -Detail 'Fresh Doctor 0.2.1 evidence and the verifier source fingerprint match.'
    } catch {
        Add-UpvBlocker -Code 'DOCTOR_PREFLIGHT_REJECTED' -Check 'doctor' -Path $script:Result.artifacts.doctorResultPath -Message $_.Exception.Message
    }
}

# Rechecks one observed Unity PID and accepts only a confirmed normal exit race.
function Test-UpvUnityProcessStillRunning {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId
    )

    try {
        $processes = @(Get-Process -Id $ProcessId -ErrorAction Stop | Where-Object {
            [string]::Equals([string]$_.ProcessName, 'Unity', [System.StringComparison]::OrdinalIgnoreCase)
        })
        return $processes.Count -gt 0
    } catch {
        if ($_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound) {
            return $false
        }
        throw
    }
}

# Rejects only an Editor associated with the exact source project and fails closed on ambiguous process evidence.
function Test-UpvSourceProjectNotOpen {
    try {
        $running = @(
            Get-Process -ErrorAction Stop |
                Where-Object { [string]::Equals([string]$_.ProcessName, 'Unity', [System.StringComparison]::OrdinalIgnoreCase) } |
                ForEach-Object { [pscustomobject][ordered]@{ processId = [int]$_.Id } } |
                Sort-Object -Property processId -Unique
        )
        $script:Result.preflight.observedUnityProcessCount = $running.Count
        $script:Result.preflight.noRunningUnityProcesses = $running.Count -eq 0
        $script:Result.preflight.sourceEditorCheckCompleted = $true
        $script:Result.preflight.sourceEditorDetected = $false
        $script:Result.preflight.sourceEditorProcessIds = @()
        if ($running.Count -eq 0) {
            Add-UpvEvidence -Check 'sourceEditorPreflight' -Status 'PASSED' -Source $script:NormalizedProjectRoot -Detail 'Get-Process reported zero running Unity.exe processes.'
            return
        }

        $cimProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'Unity.exe'" -ErrorAction Stop)
        $sourceProcessIds = New-Object System.Collections.ArrayList
        foreach ($runningProcess in $running) {
            $processIdentifier = [int]$runningProcess.processId
            $cimMatches = @($cimProcesses | Where-Object { [int]$_.ProcessId -eq $processIdentifier })
            if ($cimMatches.Count -ne 1) {
                if (Test-UpvUnityProcessStillRunning -ProcessId $processIdentifier) {
                    throw "Running Unity process ID $processIdentifier could not be matched to exactly one CIM record."
                }
                continue
            }
            if (-not (Test-UpvUnityProcessStillRunning -ProcessId $processIdentifier)) { continue }
            $commandLine = [string]$cimMatches[0].CommandLine
            if ([string]::IsNullOrWhiteSpace($commandLine)) {
                throw "CommandLine was unavailable for running Unity process ID $processIdentifier."
            }
            $arguments = @(ConvertFrom-UpvWindowsCommandLine -CommandLine $commandLine)
            $projectPaths = New-Object 'System.Collections.Generic.List[string]'
            for ($argumentIndex = 0; $argumentIndex + 1 -lt $arguments.Count; $argumentIndex++) {
                if ([string]::Equals($arguments[$argumentIndex], '-projectPath', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $projectPaths.Add([string]$arguments[$argumentIndex + 1])
                    $argumentIndex++
                }
            }
            if ($projectPaths.Count -ne 1 -or [string]::IsNullOrWhiteSpace($projectPaths[0])) {
                throw "A single readable -projectPath argument was unavailable for running Unity process ID $processIdentifier."
            }
            if (-not [System.IO.Path]::IsPathRooted($projectPaths[0])) {
                throw "The -projectPath argument for running Unity process ID $processIdentifier was not absolute."
            }
            $observedProject = Get-UpvNormalizedPath -Path $projectPaths[0]
            if ($observedProject.Equals($script:NormalizedProjectRoot, $script:UpvPathComparison)) {
                [void]$sourceProcessIds.Add($processIdentifier)
            }
        }
        $script:Result.preflight.sourceEditorProcessIds = @($sourceProcessIds | Sort-Object -Unique)
        $script:Result.preflight.sourceEditorDetected = $sourceProcessIds.Count -gt 0
        if ($sourceProcessIds.Count -gt 0) {
            Add-UpvBlocker -Code 'SOURCE_PROJECT_OPEN_IN_UNITY' -Check 'sourceEditorPreflight' -Path $script:NormalizedProjectRoot -Message "The exact source project is open in Unity process ID(s): $([string]::Join(', ', [string[]]@($script:Result.preflight.sourceEditorProcessIds)))."
            return
        }
        Add-UpvEvidence -Check 'sourceEditorPreflight' -Status 'PASSED' -Source $script:NormalizedProjectRoot -Detail "Every one of the $($running.Count) observed Unity process(es) was safely associated with a different project or a confirmed exit race."
    } catch {
        $script:Result.preflight.sourceEditorCheckCompleted = $false
        $script:Result.preflight.sourceEditorDetected = $null
        $script:Result.preflight.sourceEditorProcessIds = @()
        Add-UpvBlocker -Code 'SOURCE_EDITOR_PREFLIGHT_UNAVAILABLE' -Check 'sourceEditorPreflight' -Path $script:NormalizedProjectRoot -Message $_.Exception.Message
    }
}

# Validates project-relative file package dependencies without following external paths.
function Get-UpvLocalPackageAssessment {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $assessment = [ordered]@{ accepted = $false; references = @(); errors = @() }
    $errors = New-Object System.Collections.ArrayList
    $references = New-Object System.Collections.ArrayList
    $manifestPath = Join-Path -Path $Root -ChildPath 'Packages\manifest.json'
    try {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw 'Packages/manifest.json is missing.'
        }
        $manifest = Read-UpvJsonFile -Path $manifestPath
        $dependencies = Get-UpvJsonProperty -InputObject $manifest -Name 'dependencies'
        foreach ($property in @($dependencies.PSObject.Properties)) {
            $reference = [string]$property.Value
            if (-not $reference.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $raw = $reference.Substring(5)
            for ($pass = 0; $pass -lt 4; $pass++) {
                $decoded = [System.Uri]::UnescapeDataString($raw)
                if ($decoded -eq $raw) { break }
                $raw = $decoded
            }
            $windowsPath = $raw.Replace('/', '\')
            if (
                [string]::IsNullOrWhiteSpace($windowsPath) -or
                $windowsPath.IndexOf([char]0) -ge 0 -or
                [System.IO.Path]::IsPathRooted($windowsPath) -or
                $windowsPath -match '^[^\\]+:' -or
                $windowsPath.StartsWith('\\', [System.StringComparison]::Ordinal)
            ) {
                throw "Local package $($property.Name) uses an unsafe path: $reference"
            }
            $resolved = Get-UpvNormalizedPath -Path (Join-Path -Path (Split-Path -Parent $manifestPath) -ChildPath $windowsPath)
            if (-not (Test-UpvPathWithinRoot -Path $resolved -Root $Root)) {
                throw "Local package $($property.Name) escapes the project: $reference"
            }
            $relative = $resolved.Substring((Get-UpvNormalizedPath -Path $Root).Length + 1).Replace('\', '/')
            if (Test-UnityCopyExcludedRelativePath -RelativePath $relative) {
                throw "Local package $($property.Name) resolves into excluded path $relative."
            }
            if ($null -ne (Get-UpvReparsePointOnPath -Path $resolved)) {
                throw "Local package $($property.Name) traverses a reparse point."
            }
            if (-not (Test-Path -LiteralPath $resolved)) {
                throw "Local package $($property.Name) does not exist at $relative."
            }
            [void]$references.Add([ordered]@{ name = $property.Name; reference = $reference; projectRelativePath = $relative })
        }
    } catch {
        [void]$errors.Add($_.Exception.Message)
    }
    $assessment.accepted = $errors.Count -eq 0
    $assessment.references = @($references)
    $assessment.errors = @($errors)
    return [pscustomobject]$assessment
}

# Resolves the exact approved Editor and enforces the source-specific Test Framework identity contract.
function Test-UpvCompatibilityAndEditor {
    if ([string]::IsNullOrWhiteSpace([string]$script:Result.compatibility.unityVersion)) {
        $message = 'The exact project Unity version is unavailable.'
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'UNITY_VERSION_UNAVAILABLE' -Check 'compatibility' -Path $script:NormalizedProjectRoot -Message $message
        return
    }

    $script:TestFrameworkProvenance = Get-UpvTestFrameworkProvenanceAssessment -ProjectRoot $script:NormalizedProjectRoot
    foreach ($property in @(
        'packageName', 'manifestPath', 'packagesLockPath', 'manifestDependency', 'declaredVersion',
        'resolvedVersion', 'packagesLockSource', 'packagesLockUrl', 'registryOrigin',
        'expectedRegistryOrigin', 'registryOriginMatched', 'allowedSourceKinds', 'sourcePolicyMatched', 'scopedRegistryInterceptors',
        'sourceEvidence', 'accepted', 'errors'
    )) {
        $script:Result.compatibility.provenance[$property] = $script:TestFrameworkProvenance.$property
    }
    $script:Result.compatibility.testFrameworkVersion = $script:TestFrameworkProvenance.resolvedVersion
    $script:Result.compatibility.testFrameworkSource = $script:TestFrameworkProvenance.packagesLockSource
    if (-not $script:TestFrameworkProvenance.accepted) {
        $message = [string]::Join(' ', [string[]]@($script:TestFrameworkProvenance.errors))
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'TEST_FRAMEWORK_PROVENANCE_REJECTED' -Check 'compatibility' -Path $script:TestFrameworkProvenance.packagesLockPath -Message $message
        return
    }

    $script:CompatibilityAssessment = Get-UpvCompatibilityAssessment `
        -RegistryPath $script:CompatibilityRegistryPath `
        -UnityVersion $script:Result.compatibility.unityVersion `
        -TestFrameworkVersion $script:TestFrameworkProvenance.resolvedVersion
    $compatibility = $script:CompatibilityAssessment
    foreach ($property in @(
        'registrySchemaVersion', 'entryFound', 'entryStatus', 'allowedSourceKind', 'registryOrigin',
        'unityExecutableSha256', 'packageTreeSha256', 'hashCanonicalization', 'evidencePath', 'approved'
    )) {
        $script:Result.compatibility[$property] = $compatibility.$property
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$compatibility.error)) {
        Set-UpvCompatibilityBlocked -Reason $compatibility.error
        Add-UpvBlocker -Code 'COMPATIBILITY_REGISTRY_INVALID' -Check 'compatibility' -Path $script:CompatibilityRegistryPath -Message $compatibility.error
        return
    }
    if (-not $compatibility.entryFound) {
        $message = "Unity $($compatibility.unityVersion) with Test Framework $($compatibility.testFrameworkVersion) is not registered."
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'UNITY_TEST_FRAMEWORK_PAIR_UNKNOWN' -Check 'compatibility' -Path $script:CompatibilityRegistryPath -Message $message
        return
    }
    if (-not $compatibility.approved) {
        $message = "The exact compatibility pair is $($compatibility.entryStatus), not APPROVED."
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'UNITY_TEST_FRAMEWORK_PAIR_NOT_APPROVED' -Check 'compatibility' -Path $compatibility.evidencePath -Message $message
        return
    }
    $script:TestFrameworkProvenance = Get-UpvTestFrameworkProvenanceAssessment `
        -ProjectRoot $script:NormalizedProjectRoot `
        -AllowedSourceKinds ([string[]]@($compatibility.allowedSourceKind))
    foreach ($property in @(
        'packageName', 'manifestPath', 'packagesLockPath', 'manifestDependency', 'declaredVersion',
        'resolvedVersion', 'packagesLockSource', 'packagesLockUrl', 'registryOrigin',
        'expectedRegistryOrigin', 'registryOriginMatched', 'allowedSourceKinds', 'sourcePolicyMatched', 'scopedRegistryInterceptors',
        'sourceEvidence', 'accepted', 'errors'
    )) {
        $script:Result.compatibility.provenance[$property] = $script:TestFrameworkProvenance.$property
    }
    $originMatched = if ($compatibility.allowedSourceKind -ceq 'registry') {
        [string]$compatibility.registryOrigin -ceq [string]$script:TestFrameworkProvenance.registryOrigin
    } else {
        $null -eq $compatibility.registryOrigin -and $null -eq $script:TestFrameworkProvenance.registryOrigin
    }
    if (
        -not $script:TestFrameworkProvenance.accepted -or
        $compatibility.allowedSourceKind -cne [string]$script:TestFrameworkProvenance.packagesLockSource -or
        -not $originMatched
    ) {
        $message = 'Test Framework preflight provenance does not match the approved source-specific compatibility contract.'
        if (@($script:TestFrameworkProvenance.errors).Count -gt 0) {
            $message += ' ' + [string]::Join(' ', [string[]]@($script:TestFrameworkProvenance.errors))
        }
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'TEST_FRAMEWORK_PROVENANCE_MISMATCH' -Check 'compatibility' -Path $script:TestFrameworkProvenance.packagesLockPath -Message $message
        return
    }

    $resolution = Resolve-OrchestrationUnityExecutable `
        -RequiredVersion $script:Result.compatibility.unityVersion `
        -UnityExecutableOverride $UnityExecutable `
        -UnityEditorPath ([Environment]::GetEnvironmentVariable('UNITY_EDITOR_PATH', 'Process')) `
        -UnityHubEditorRoot ([Environment]::GetEnvironmentVariable('UNITY_HUB_EDITOR_ROOT', 'Process')) `
        -ProgramFilesRoot ([Environment]::GetEnvironmentVariable('ProgramFiles', 'Process')) `
        -ProgramFilesX86Root ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)', 'Process'))
    $script:Result.unity.resolutionStatus = $resolution.status
    $script:Result.unity.resolutionSource = $resolution.selectedSource
    $script:Result.unity.candidates = @($resolution.candidates)
    if ([string]::IsNullOrWhiteSpace([string]$resolution.selectedPath)) {
        $message = "Exact Unity $($resolution.requiredVersion) was not found."
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'UNITY_EXECUTABLE_NOT_FOUND' -Check 'unityExecutable' -Path $null -Message $message
        return
    }

    try {
        $path = Get-UpvNormalizedPath -Path $resolution.selectedPath
        $script:Result.unity.executablePath = $path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw 'Selected Unity executable does not exist.'
        }
        if ([System.IO.Path]::GetFileName($path) -ine 'Unity.exe') {
            throw 'Selected executable must be named Unity.exe.'
        }
        $reparsePoint = Get-UpvReparsePointOnPath -Path $path
        if ($null -ne $reparsePoint) {
            throw "Selected Unity path traverses reparse point $reparsePoint."
        }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        $script:Result.unity.executableSha256 = Get-UpvFileSha256 -Path $path
        $script:Result.unity.fileVersion = [string]$item.VersionInfo.FileVersion
        $script:Result.unity.productVersion = [string]$item.VersionInfo.ProductVersion
        $match = [regex]::Match($script:Result.unity.productVersion, '^(?<version>\d+\.\d+\.\d+[abfp]\d+)(?:_|$|\s)')
        if ($match.Success) {
            $script:Result.unity.detectedExecutableVersion = $match.Groups['version'].Value
        }
        $script:Result.unity.executableVersionMatched = (
            $match.Success -and
            $script:Result.unity.detectedExecutableVersion -ceq $script:Result.compatibility.unityVersion
        )
        $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        $script:Result.unity.signatureStatus = [string]$signature.Status
        if ($null -ne $signature.SignerCertificate) {
            $script:Result.unity.signerSubject = [string]$signature.SignerCertificate.Subject
            $script:Result.unity.certificateThumbprint = [string]$signature.SignerCertificate.Thumbprint
        }
        $script:Result.unity.publisherMatched = (
            $script:Result.unity.signatureStatus -ceq 'Valid' -and
            [regex]::IsMatch([string]$script:Result.unity.signerSubject, '(?i)\bUnity Technologies\b')
        )
        if (-not $script:Result.unity.executableVersionMatched) { throw 'Unity.exe ProductVersion does not match the exact project version.' }
        if ($script:Result.unity.signatureStatus -cne 'Valid') { throw "Unity.exe signature status is $($script:Result.unity.signatureStatus), not Valid." }
        if (-not $script:Result.unity.publisherMatched) { throw 'Unity.exe signer does not identify Unity Technologies.' }
        if ($script:Result.unity.executableSha256 -cne $compatibility.unityExecutableSha256) { throw 'Unity.exe SHA-256 does not match the approved compatibility identity.' }
        $script:Result.compatibility.reason = 'Preflight provenance and signed Unity are accepted; resolved package content identity is pending.'
        Add-UpvEvidence -Check 'compatibilityPreflight' -Status 'PASSED' -Source $script:CompatibilityRegistryPath -Detail "Approved Unity $($compatibility.unityVersion), Test Framework $($compatibility.testFrameworkVersion), and $($compatibility.allowedSourceKind) provenance were selected."
        Add-UpvEvidence -Check 'unityExecutable' -Status 'PASSED' -Source $path -Detail 'Exact ProductVersion, approved executable SHA-256, and a valid Unity Technologies Authenticode signature were confirmed.'
    } catch {
        Set-UpvCompatibilityBlocked -Reason $_.Exception.Message
        Add-UpvBlocker -Code 'UNITY_EXECUTABLE_REJECTED' -Check 'unityExecutable' -Path $script:Result.unity.executablePath -Message $_.Exception.Message
    }
}

# Copies the immutable Doctor copy-set and verifies every copied file digest.
function Copy-UpvProjectToIsolation {
    if ($null -eq $script:OriginalFingerprintBefore) {
        Add-UpvBlocker -Code 'SOURCE_SNAPSHOT_UNAVAILABLE' -Check 'isolation' -Path $script:NormalizedProjectRoot -Message 'No source snapshot is available for isolation.'
        return
    }
    try {
        $destination = $script:Result.isolation.projectCopyPath
        $budget = Get-UnityIsolationPathBudgetAssessment -Snapshot $script:OriginalFingerprintBefore.snapshot -Destination $destination
        if (-not $budget.accepted) {
            foreach ($violation in @($budget.violations)) {
                Add-UpvBlocker -Code $violation.code -Check $violation.check -Path $violation.path -Message $violation.message
            }
            return
        }
        [void][System.IO.Directory]::CreateDirectory($destination)
        foreach ($relativeDirectory in @($script:OriginalFingerprintBefore.snapshot.directories)) {
            $path = Get-UnityIsolationDestinationPath -DestinationRoot $destination -RelativePath $relativeDirectory
            [void][System.IO.Directory]::CreateDirectory($path)
            $script:Result.isolation.copiedDirectoryCount++
        }
        foreach ($file in @($script:OriginalFingerprintBefore.snapshot.files)) {
            $sourcePath = Join-Path -Path $script:NormalizedProjectRoot -ChildPath ([string]$file.path).Replace('/', '\')
            $destinationPath = Get-UnityIsolationDestinationPath -DestinationRoot $destination -RelativePath ([string]$file.path)
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $destinationPath))
            [System.IO.File]::Copy($sourcePath, $destinationPath, $false)
            $copied = Get-Item -LiteralPath $destinationPath -Force -ErrorAction Stop
            if ([long]$copied.Length -ne [long]$file.length -or (Get-UpvFileSha256 -Path $destinationPath) -cne [string]$file.sha256) {
                throw "Copied file does not match source snapshot: $($file.path)"
            }
            $script:Result.isolation.copiedFileCount++
        }
        foreach ($required in @('Assets', 'Packages', 'ProjectSettings', 'ProjectSettings\ProjectVersion.txt')) {
            if (-not (Test-Path -LiteralPath (Join-Path $destination $required))) {
                throw "Isolated copy is missing required Unity path: $required"
            }
        }
        $copyFingerprint = Get-StableUnityCopySetFingerprint -ProjectRoot $destination
        $script:Result.isolation.baseCopyFingerprint = $copyFingerprint.treeSha256
        $script:Result.isolation.baseCopyMatched = $copyFingerprint.treeSha256 -ceq $script:OriginalFingerprintBefore.treeSha256
        if (-not $script:Result.isolation.baseCopyMatched) {
            throw 'Isolated base copy fingerprint does not match the source snapshot.'
        }
        $script:Result.isolation.status = 'COPIED'
        Add-UpvEvidence -Check 'isolation' -Status 'PASSED' -Source $destination -Detail 'The external base copy matches the fresh source fingerprint byte-for-byte.'
    } catch {
        $script:Result.isolation.status = 'FAILED'
        Add-UpvBlocker -Code 'ISOLATION_COPY_FAILED' -Check 'isolation' -Path $script:Result.isolation.projectCopyPath -Message $_.Exception.Message
    }
}

# Calculates a deterministic hash for the bundled scenario harness sources.
function Get-UpvHarnessFingerprint {
    $files = @(Get-UpvBundleFileInventory -BundleRoot $script:HarnessRoot)
    $canonical = foreach ($file in $files) {
        "F|$($script:Utf8NoBom.GetByteCount([string]$file.path))|$($file.path)|$($file.length)|$($file.sha256)"
    }
    return [pscustomobject][ordered]@{
        files = $files
        treeSha256 = Get-UpvTextSha256 -Text ([string]::Join([char]10, [string[]]@($canonical)))
    }
}

# Copies one validated source-only file inventory into a reserved isolated directory.
function Copy-UpvVerifiedInventory {
    param(
        [Parameter(Mandatory = $true)][object[]]$Files,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    foreach ($file in $Files) {
        $destination = Get-UnityIsolationDestinationPath -DestinationRoot $DestinationRoot -RelativePath ([string]$file.path)
        if ($destination.Length -ge 260) {
            throw "Overlay destination exceeds the conservative file path boundary: $destination"
        }
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        [System.IO.File]::Copy([string]$file.sourcePath, $destination, $false)
        if ((Get-UpvFileSha256 -Path $destination) -cne [string]$file.sha256) {
            throw "Overlay copy hash mismatch: $($file.path)"
        }
    }
}

# Validates and injects the harness and project-specific scenario only into the isolated copy.
function Add-UpvScenarioOverlay {
    if ([string]::IsNullOrWhiteSpace($ScenarioBundlePath)) {
        return
    }
    try {
        $script:ScenarioBundle = Get-UpvScenarioBundleAssessment `
            -BundlePath $ScenarioBundlePath `
            -ProjectRoot $script:NormalizedProjectRoot `
            -ProcessTimeoutSeconds $TimeoutSeconds
        foreach ($property in @(
            'bundlePath', 'manifestPath', 'schemaVersion', 'scenarioId', 'displayName',
            'testFilter', 'timeoutSeconds', 'requiresGraphics', 'expectedScenes',
            'expectedAssertionIds', 'screenshotIds', 'files', 'fileCount', 'treeSha256'
        )) {
            $script:Result.scenario[$property] = $script:ScenarioBundle.$property
        }
        $script:Result.scenario.bundleAccepted = [bool]$script:ScenarioBundle.accepted
        $script:Result.scenario.bundleErrors = @($script:ScenarioBundle.errors)
        $script:Result.selection.scenarioId = $script:ScenarioBundle.scenarioId
        if (-not $script:ScenarioBundle.accepted) {
            throw ([string]::Join(' ', [string[]]@($script:ScenarioBundle.errors)))
        }

        $reservedAssessment = Get-UpvReservedScenarioOverlayAssessment -ProjectCopyPath $script:Result.isolation.projectCopyPath
        $reservedRoot = $reservedAssessment.path
        if (-not $reservedAssessment.accepted) {
            throw $reservedAssessment.error
        }
        $harnessDestination = Join-Path -Path $reservedRoot -ChildPath 'Harness'
        $scenarioDestination = Join-Path -Path $reservedRoot -ChildPath 'Scenario'
        $harness = Get-UpvHarnessFingerprint
        $scenarioFiles = @(Get-UpvBundleFileInventory -BundleRoot $script:ScenarioBundle.bundlePath)
        $scenarioCanonical = foreach ($file in @($scenarioFiles | Sort-Object -Property path)) {
            "F|$($script:Utf8NoBom.GetByteCount([string]$file.path))|$($file.path)|$($file.length)|$($file.sha256)"
        }
        $copyTimeScenarioHash = Get-UpvTextSha256 -Text ([string]::Join([char]10, [string[]]@($scenarioCanonical)))
        if ($copyTimeScenarioHash -cne [string]$script:ScenarioBundle.treeSha256) {
            throw 'Scenario bundle changed after validation and before isolated overlay copy.'
        }
        Copy-UpvVerifiedInventory -Files $harness.files -DestinationRoot $harnessDestination
        Copy-UpvVerifiedInventory -Files $scenarioFiles -DestinationRoot $scenarioDestination
        $script:Result.isolation.overlayInjected = $true
        $script:Result.isolation.overlayPath = $reservedRoot
        $script:Result.isolation.scenarioBundleSha256 = $script:ScenarioBundle.treeSha256
        $script:Result.isolation.harnessSha256 = $harness.treeSha256
        $script:Result.isolation.status = 'OVERLAY_INJECTED'
        Add-UpvEvidence -Check 'scenarioOverlay' -Status 'PASSED' -Source $reservedRoot -Detail 'Validated source-only scenario and bundled harness were injected into the isolated copy only.'
    } catch {
        Add-UpvBlocker -Code 'SCENARIO_BUNDLE_REJECTED' -Check 'scenarioOverlay' -Path $ScenarioBundlePath -Message $_.Exception.Message
    }
}

# Builds the fixed Unity Test Framework argument list without shell interpolation.
function New-UpvUnityArguments {
    if ($script:Result.selection.mode -eq 'SCENARIO_OVERLAY') {
        return New-UpvUnityTestArguments `
            -ProjectPath $script:Result.isolation.projectCopyPath `
            -TestResultsPath $script:Result.artifacts.testResultsPath `
            -EditorLogPath $script:Result.artifacts.editorLogPath `
            -UpmLogPath $script:Result.artifacts.upmLogPath `
            -Mode 'SCENARIO_OVERLAY' `
            -TestFilter $script:ScenarioBundle.testFilter `
            -ScenarioId $script:ScenarioBundle.scenarioId `
            -ScenarioResultPath $script:Result.artifacts.scenarioResultPath `
            -ScreenshotRoot $script:Result.artifacts.screenshotRoot `
            -ScenarioTimeoutSeconds ([int]$script:ScenarioBundle.timeoutSeconds)
    }
    return New-UpvUnityTestArguments `
        -ProjectPath $script:Result.isolation.projectCopyPath `
        -TestResultsPath $script:Result.artifacts.testResultsPath `
        -EditorLogPath $script:Result.artifacts.editorLogPath `
        -UpmLogPath $script:Result.artifacts.upmLogPath `
        -Mode 'PROJECT_PLAYMODE_TESTS' `
        -TestFilter $TestFilter `
        -TestCategory $TestCategory `
        -AssemblyNames $AssemblyNames
}

# Starts the trusted Unity editor in a kill-on-close Job Object and records process evidence.
function Invoke-UpvUnity {
    $arguments = New-UpvUnityArguments
    $script:Result.unity.arguments = $arguments
    foreach ($argument in $arguments) {
        if ([string]$argument -ceq $script:NormalizedProjectRoot) {
            $script:Result.unity.commandLineContainsOriginalProject = $true
            Add-UpvBlocker -Code 'ORIGINAL_PROJECT_IN_UNITY_ARGUMENTS' -Check 'unityArguments' -Path $script:NormalizedProjectRoot -Message 'Unity argument list contains the original project root.'
            return
        }
    }
    $script:Result.unity.commandLineContainsOriginalProject = $false
    foreach ($forbidden in @('-quit', '-nographics', '-runSynchronously', '-executeMethod', '-accept-apiupdate', '-ignorecompilererrors')) {
        if ($arguments -contains $forbidden) {
            Add-UpvBlocker -Code 'FORBIDDEN_UNITY_ARGUMENT' -Check 'unityArguments' -Path $null -Message "Forbidden Unity argument is present: $forbidden"
            return
        }
    }

    $process = Invoke-UnityProcessInJob `
        -ExecutablePath $script:Result.unity.executablePath `
        -Arguments $arguments `
        -WorkingDirectory $script:SessionRoot `
        -StandardOutputPath $script:Result.artifacts.standardOutputPath `
        -StandardErrorPath $script:Result.artifacts.standardErrorPath `
        -TimeoutSeconds $TimeoutSeconds `
        -TreeExitGraceMilliseconds 15000
    $script:Result.unity.processStarted = $process.processStarted
    $script:Result.unity.timedOut = $process.timedOut
    $script:Result.unity.exitCode = $process.exitCode
    foreach ($property in @(
        'rootProcessId', 'jobObjectCreated', 'killOnJobCloseConfigured', 'processAssignedToJob',
        'terminationRequested', 'terminationReason', 'terminationApiSucceeded', 'rootProcessExited',
        'processTreeExitVerified', 'activeProcessCountAfterWait', 'treeExitWaitMilliseconds', 'controlError'
    )) {
        $script:Result.processControl[$property] = $process.$property
    }
    if ($process.processStarted) {
        Add-UpvEvidence -Check 'unityProcess' -Status 'OBSERVED' -Source $script:Result.unity.executablePath -Detail 'The exact signed Unity.exe started against only the isolated project.'
    }
    $jobSetupFailed = (
        -not $process.jobObjectCreated -or
        -not $process.killOnJobCloseConfigured -or
        ($process.processStarted -and -not $process.processAssignedToJob)
    )
    if ($jobSetupFailed) {
        Add-UpvBlocker -Code 'UNITY_JOB_OBJECT_CONTROL_FAILED' -Check 'unityProcess' -Path $script:Result.unity.executablePath -Message "Unity process control failed: $($process.controlError)"
    }
    if (-not $jobSetupFailed -and -not [string]::IsNullOrWhiteSpace([string]$process.controlError)) {
        $controlledTerminationCompleted = (
            $process.processTreeExitVerified -and
            [int]$process.activeProcessCountAfterWait -eq 0 -and
            $process.terminationRequested -and
            $process.terminationApiSucceeded -and
            $null -ne $process.exitCode -and
            [long]$process.exitCode -ne 0
        )
        if ($controlledTerminationCompleted) {
            Add-UpvWarning -Code 'UNITY_DESCENDANTS_TERMINATED' -Check 'unityProcess' -Path $script:Result.unity.executablePath -Message "Job Object termination reached zero active processes after: $($process.controlError)"
        } else {
            Add-UpvBlocker -Code 'UNITY_JOB_OBJECT_CONTROL_FAILED' -Check 'unityProcess' -Path $script:Result.unity.executablePath -Message "Unity process control failed: $($process.controlError)"
        }
    }
    if ($process.processStarted -and -not $process.processTreeExitVerified) {
        Add-UpvBlocker -Code 'UNITY_PROCESS_TREE_EXIT_UNPROVEN' -Check 'unityProcess' -Path $script:Result.unity.executablePath -Message 'The verifier could not prove that Unity and all assigned descendants exited.'
    } elseif ($process.processStarted) {
        Add-UpvEvidence -Check 'unityProcessTree' -Status 'PASSED' -Source $script:Result.unity.executablePath -Detail 'Job Object accounting reached zero active processes.'
    }
}

# Verifies the exact resolved Test Framework package tree after the isolated Unity process has exited.
function Set-UpvResolvedTestFrameworkIdentity {
    if (
        -not $script:Result.unity.processStarted -or
        $script:Result.unity.timedOut -or
        -not $script:Result.processControl.processTreeExitVerified
    ) {
        $message = 'Resolved Test Framework identity cannot be inspected without a completed, terminated Unity process tree.'
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'TEST_FRAMEWORK_IDENTITY_UNAVAILABLE' -Check 'compatibility' -Path $script:Result.isolation.projectCopyPath -Message $message
        return
    }
    if ($null -eq $script:TestFrameworkProvenance -or $null -eq $script:CompatibilityAssessment) {
        $message = 'Test Framework provenance or approved identity metadata is unavailable after Unity execution.'
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'TEST_FRAMEWORK_IDENTITY_UNAVAILABLE' -Check 'compatibility' -Path $script:Result.isolation.projectCopyPath -Message $message
        return
    }

    $postRunProvenance = Get-UpvTestFrameworkProvenanceAssessment `
        -ProjectRoot $script:Result.isolation.projectCopyPath `
        -AllowedSourceKinds ([string[]]@($script:CompatibilityAssessment.allowedSourceKind))
    foreach ($property in @(
        'packageName', 'manifestPath', 'packagesLockPath', 'manifestDependency', 'declaredVersion',
        'resolvedVersion', 'packagesLockSource', 'packagesLockUrl', 'registryOrigin',
        'expectedRegistryOrigin', 'registryOriginMatched', 'allowedSourceKinds', 'sourcePolicyMatched', 'scopedRegistryInterceptors',
        'sourceEvidence', 'accepted', 'errors'
    )) {
        $script:Result.compatibility.postRunProvenance[$property] = $postRunProvenance.$property
    }
    if (-not $postRunProvenance.accepted) {
        $message = 'Post-run isolated Test Framework provenance was rejected: ' + [string]::Join(' ', [string[]]@($postRunProvenance.errors))
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'TEST_FRAMEWORK_POST_RUN_PROVENANCE_REJECTED' -Check 'compatibility' -Path $postRunProvenance.packagesLockPath -Message $message
        return
    }
    foreach ($property in @('declaredVersion', 'resolvedVersion', 'packagesLockSource', 'registryOrigin')) {
        if ([string]$postRunProvenance.$property -cne [string]$script:TestFrameworkProvenance.$property) {
            $message = "Post-run isolated Test Framework provenance changed property '$property'."
            Set-UpvCompatibilityBlocked -Reason $message
            Add-UpvBlocker -Code 'TEST_FRAMEWORK_PROVENANCE_CHANGED' -Check 'compatibility' -Path $postRunProvenance.packagesLockPath -Message $message
            return
        }
    }

    $identity = Get-UpvResolvedTestFrameworkIdentityAssessment `
        -ProjectRoot $script:Result.isolation.projectCopyPath `
        -Provenance $postRunProvenance `
        -ExpectedVersion $script:CompatibilityAssessment.testFrameworkVersion `
        -ExpectedSourceKind $script:CompatibilityAssessment.allowedSourceKind `
        -ExpectedRegistryOrigin $script:CompatibilityAssessment.registryOrigin `
        -ExpectedTreeSha256 $script:CompatibilityAssessment.packageTreeSha256 `
        -ExpectedCanonicalization $script:CompatibilityAssessment.hashCanonicalization
    foreach ($property in @(
        'packageName', 'declaredVersion', 'resolvedVersion', 'packagesLockSource', 'registryOrigin',
        'expectedSourceKind', 'expectedRegistryOrigin', 'sourceEvidence', 'packageCacheRoot', 'resolvedPackagePath', 'candidateCount', 'fileCount',
        'snapshotAttempts', 'hashCanonicalization', 'treeSha256', 'expectedTreeSha256', 'identityMatched', 'accepted', 'errors'
    )) {
        $script:Result.compatibility.packageIdentity[$property] = $identity.$property
    }
    if (-not $identity.accepted) {
        $message = [string]::Join(' ', [string[]]@($identity.errors))
        Set-UpvCompatibilityBlocked -Reason $message
        Add-UpvBlocker -Code 'TEST_FRAMEWORK_PACKAGE_IDENTITY_REJECTED' -Check 'compatibility' -Path $identity.resolvedPackagePath -Message $message
        return
    }

    $script:Result.compatibility.verificationStatus = 'VERIFIED_SUCCESS'
    $script:Result.compatibility.reason = 'Preflight and post-run source-specific provenance, signed Editor identity, and the resolved Test Framework package tree match the approved compatibility entry.'
    Add-UpvEvidence -Check 'testFrameworkPackageIdentity' -Status 'PASSED' -Source $identity.resolvedPackagePath -Detail "Resolved $($identity.packageName) $($identity.resolvedVersion) matched tree SHA-256 $($identity.treeSha256)."
}

# Maps process, log, NUnit, scenario, and screenshot evidence to verification scopes.
function Set-UpvVerificationEvidence {
    $script:Result.editorLog = Get-UpvEditorLogAnalysis `
        -Path $script:Result.artifacts.editorLogPath `
        -ExpectedUnityVersion $script:Result.compatibility.unityVersion `
        -ExpectedProjectPath $script:Result.isolation.projectCopyPath
    $script:Result.nunit = Get-UpvNUnitAnalysis -Path $script:Result.artifacts.testResultsPath

    if (-not $script:Result.unity.processStarted) {
        Add-UpvBlocker -Code 'UNITY_PROCESS_NOT_STARTED' -Check 'unityProcess' -Path $script:Result.unity.executablePath -Message 'Unity did not start.'
        return
    }
    if ($script:Result.unity.timedOut) {
        $script:Result.verification.scriptCompilation.status = 'BLOCKED'
        $script:Result.verification.scriptCompilation.reason = 'Unity timed out before complete compilation evidence was available.'
        $script:Result.verification.editorPlayMode.status = 'BLOCKED'
        $script:Result.verification.editorPlayMode.reason = 'Unity timed out before Editor PlayMode completion was proven.'
        $script:Result.verification.playModeTests.status = 'BLOCKED'
        $script:Result.verification.playModeTests.reason = 'Unity timed out before a complete PlayMode result was available.'
        Add-UpvBlocker -Code 'UNITY_PROCESS_TIMEOUT' -Check 'unityProcess' -Path $script:Result.unity.executablePath -Message "Unity exceeded the $TimeoutSeconds second process timeout."
        return
    }

    $baseScopes = Get-UpvBaseVerificationScopeAssessment `
        -EditorLog $script:Result.editorLog `
        -NUnit $script:Result.nunit `
        -ExitCode $script:Result.unity.exitCode
    foreach ($scopeName in @('scriptCompilation', 'editorPlayMode', 'playModeTests')) {
        $script:Result.verification[$scopeName].status = $baseScopes.$scopeName.status
        $script:Result.verification[$scopeName].reason = $baseScopes.$scopeName.reason
    }

    $concreteLogFailure = $script:Result.editorLog.classification -eq 'FAILURE'
    if ($concreteLogFailure) {
        $script:Result.verification.scriptCompilation.status = 'VERIFIED_FAILURE'
        $script:Result.verification.scriptCompilation.reason = 'Editor.log contains concrete compilation, package, fatal, crash, or nonzero-exit evidence.'
        Add-UpvFailure -Code 'UNITY_EDITOR_LOG_FAILURE' -Check 'scriptCompilation' -Path $script:Result.artifacts.editorLogPath -Message $script:Result.verification.scriptCompilation.reason
    } elseif ($script:Result.editorLog.classification -eq 'INCONCLUSIVE') {
        $script:Result.verification.scriptCompilation.status = 'BLOCKED'
        $script:Result.verification.scriptCompilation.reason = 'Editor.log is missing required markers, so compilation evidence is incomplete.'
        Add-UpvBlocker -Code 'EDITOR_LOG_INCONCLUSIVE' -Check 'editorLog' -Path $script:Result.artifacts.editorLogPath -Message "Editor.log is missing required markers: $([string]::Join(', ', [string[]]@($script:Result.editorLog.missingRequiredMarkers)))"
    } elseif (-not $script:Result.editorLog.exists) {
        $script:Result.verification.scriptCompilation.status = 'BLOCKED'
        $script:Result.verification.scriptCompilation.reason = 'Editor.log is missing, so compilation evidence is unavailable.'
        Add-UpvBlocker -Code 'EDITOR_LOG_MISSING' -Check 'editorLog' -Path $script:Result.artifacts.editorLogPath -Message 'Unity did not create Editor.log.'
    }

    if ($script:Result.nunit.classification -eq 'INVALID' -or $script:Result.nunit.classification -eq 'NOT_ANALYZED') {
        if (-not $concreteLogFailure) {
            $script:Result.verification.scriptCompilation.status = 'BLOCKED'
            $script:Result.verification.scriptCompilation.reason = 'A well-formed NUnit result is required to complete compilation evidence.'
            $script:Result.verification.playModeTests.status = 'BLOCKED'
            $script:Result.verification.playModeTests.reason = 'The NUnit result is missing or malformed.'
            Add-UpvBlocker -Code 'NUNIT_RESULT_INVALID' -Check 'playModeTests' -Path $script:Result.artifacts.testResultsPath -Message ([string]$script:Result.nunit.error)
        }
    } elseif ($script:Result.nunit.classification -eq 'ZERO_TESTS') {
        $script:Result.verification.playModeTests.status = 'BLOCKED'
        $script:Result.verification.playModeTests.reason = 'The selected PlayMode run contained zero tests.'
        Add-UpvBlocker -Code 'NO_PLAYMODE_TESTS_EXECUTED' -Check 'playModeTests' -Path $script:Result.artifacts.testResultsPath -Message 'The selected PlayMode test run contained zero tests.'
    } elseif ($script:Result.nunit.classification -eq 'INCOMPLETE' -or $script:Result.nunit.classification -eq 'INCONCLUSIVE') {
        $script:Result.verification.playModeTests.status = 'BLOCKED'
        $script:Result.verification.playModeTests.reason = 'Skipped or inconclusive tests prevent complete PlayMode evidence.'
        Add-UpvBlocker -Code 'PLAYMODE_TEST_RUN_INCOMPLETE' -Check 'playModeTests' -Path $script:Result.artifacts.testResultsPath -Message "Strict verification rejects skipped or inconclusive tests (skipped=$($script:Result.nunit.skipped), inconclusive=$($script:Result.nunit.inconclusive))."
    } elseif ($script:Result.nunit.classification -eq 'FAILED') {
        $script:Result.verification.playModeTests.status = 'VERIFIED_FAILURE'
        $script:Result.verification.playModeTests.reason = "$($script:Result.nunit.failed) selected PlayMode test(s) failed."
        Add-UpvFailure -Code 'PLAYMODE_TESTS_FAILED' -Check 'playModeTests' -Path $script:Result.artifacts.testResultsPath -Message $script:Result.verification.playModeTests.reason
    }

    if ($null -ne $script:Result.unity.exitCode -and [long]$script:Result.unity.exitCode -ne 0) {
        if ($script:Result.nunit.classification -eq 'FAILED' -or $concreteLogFailure) {
            Add-UpvFailure -Code 'UNITY_NONZERO_EXIT' -Check 'unityProcess' -Path $script:Result.unity.executablePath -Message "Unity exited with concrete nonzero code $($script:Result.unity.exitCode)."
        } else {
            Add-UpvBlocker -Code 'UNITY_NONZERO_EXIT_INCONCLUSIVE' -Check 'unityProcess' -Path $script:Result.unity.executablePath -Message "Unity exited with code $($script:Result.unity.exitCode) without a complete failure result."
        }
    }

    if (
        $script:Result.editorLog.classification -eq 'SAFE' -and
        $script:Result.nunit.classification -in @('PASSED', 'FAILED', 'ZERO_TESTS', 'INCOMPLETE')
    ) {
        $script:Result.verification.scriptCompilation.status = 'VERIFIED_SUCCESS'
        $script:Result.verification.scriptCompilation.reason = 'Editor.log is safe and Unity emitted a well-formed test result after project compilation.'
    }
    if ($script:Result.nunit.total -gt 0 -and $script:Result.nunit.classification -in @('PASSED', 'FAILED')) {
        $script:Result.verification.editorPlayMode.status = 'VERIFIED_SUCCESS'
        $script:Result.verification.editorPlayMode.reason = 'Unity Test Framework executed selected tests with testPlatform PlayMode in the Editor.'
    }
    if (
        $script:Result.nunit.classification -eq 'PASSED' -and
        $script:Result.editorLog.classification -eq 'SAFE' -and
        [long]$script:Result.unity.exitCode -eq 0
    ) {
        $script:Result.verification.playModeTests.status = 'VERIFIED_SUCCESS'
        $script:Result.verification.playModeTests.reason = "All $($script:Result.nunit.total) selected Editor PlayMode tests executed and passed without skips or inconclusive results."
        Add-UpvEvidence -Check 'playModeTests' -Status 'PASSED' -Source $script:Result.artifacts.testResultsPath -Detail $script:Result.verification.playModeTests.reason
    }

    if ($script:Result.selection.mode -eq 'SCENARIO_OVERLAY') {
        if ($script:Result.nunit.classification -eq 'FAILED') {
            $script:Result.verification.scenarioBehavior.status = 'VERIFIED_FAILURE'
            $script:Result.verification.scenarioBehavior.reason = 'The scenario PlayMode test produced a concrete failed NUnit result.'
        } elseif ($script:Result.nunit.classification -eq 'PASSED') {
            $receipt = Get-UpvScenarioReceiptAssessment `
                -ReceiptPath $script:Result.artifacts.scenarioResultPath `
                -ScreenshotRoot $script:Result.artifacts.screenshotRoot `
                -Bundle $script:ScenarioBundle
            $script:Result.scenario.receiptExists = $receipt.exists
            $script:Result.scenario.receiptSha256 = $receipt.sha256
            $script:Result.scenario.receiptCompleted = $receipt.completed
            $script:Result.scenario.receiptError = $receipt.error
            $script:Result.scenario.observedScenes = @($receipt.scenes)
            $script:Result.scenario.assertions = @($receipt.assertions)
            $script:Result.scenario.captureReceipts = @($receipt.captureReceipts)
            $script:Result.scenario.screenshots = @($receipt.screenshots)
            $script:Result.scenario.receiptAccepted = $receipt.accepted
            $script:Result.scenario.receiptErrors = @($receipt.errors)
            if ($receipt.accepted) {
                $script:Result.verification.scenarioBehavior.status = 'VERIFIED_SUCCESS'
                $script:Result.verification.scenarioBehavior.reason = "Scenario $($script:ScenarioBundle.scenarioId) completed with the exact expected assertion set."
                if ($script:ScenarioBundle.screenshotIds.Count -gt 0) {
                    $script:Result.verification.visualEvidence.status = 'VERIFIED_SUCCESS'
                    $script:Result.verification.visualEvidence.reason = 'Every requested PNG exists and is hashed; image content was not judged.'
                }
                Add-UpvEvidence -Check 'scenarioBehavior' -Status 'PASSED' -Source $script:Result.artifacts.scenarioResultPath -Detail $script:Result.verification.scenarioBehavior.reason
            } else {
                $script:Result.verification.scenarioBehavior.status = 'BLOCKED'
                $script:Result.verification.scenarioBehavior.reason = 'The scenario receipt or required assertion evidence is incomplete.'
                if ($script:ScenarioBundle.screenshotIds.Count -gt 0) {
                    $script:Result.verification.visualEvidence.status = 'BLOCKED'
                    $script:Result.verification.visualEvidence.reason = 'One or more requested screenshot artifacts are missing or invalid.'
                }
                Add-UpvBlocker -Code 'SCENARIO_RECEIPT_REJECTED' -Check 'scenarioBehavior' -Path $script:Result.artifacts.scenarioResultPath -Message ([string]::Join(' ', [string[]]@($receipt.errors)))
            }
        }
    }
}

# Recomputes original content and Git metadata after all dynamic activity.
function Complete-UpvOriginalIntegrity {
    if ($null -ne $script:OriginalFingerprintBefore) {
        try {
            $script:OriginalFingerprintAfter = Get-StableUnityCopySetFingerprint -ProjectRoot $script:NormalizedProjectRoot
            $script:Result.originalProjectIntegrity.afterDirectoryCount = $script:OriginalFingerprintAfter.directoryCount
            $script:Result.originalProjectIntegrity.afterFileCount = $script:OriginalFingerprintAfter.fileCount
            $script:Result.originalProjectIntegrity.afterTreeSha256 = $script:OriginalFingerprintAfter.treeSha256
            $unchanged = (
                $script:OriginalFingerprintBefore.directoryCount -eq $script:OriginalFingerprintAfter.directoryCount -and
                $script:OriginalFingerprintBefore.fileCount -eq $script:OriginalFingerprintAfter.fileCount -and
                $script:OriginalFingerprintBefore.treeSha256 -ceq $script:OriginalFingerprintAfter.treeSha256
            )
            $script:Result.originalProjectIntegrity.unchanged = $unchanged
            $script:Result.originalProjectIntegrity.status = if ($unchanged) { 'UNCHANGED' } else { 'CHANGED' }
            Add-UpvEvidence -Check 'originalProjectIntegrity' -Status $script:Result.originalProjectIntegrity.status -Source $script:NormalizedProjectRoot -Detail 'Original project copy-set fingerprints were compared before and after Play verification.'
        } catch {
            Add-UpvBlocker -Code 'ORIGINAL_INTEGRITY_UNPROVEN' -Check 'originalProjectIntegrity' -Path $script:NormalizedProjectRoot -Message $_.Exception.Message
        }
    }

    if ($null -ne $script:GitSnapshotBefore) {
        try {
            $script:GitSnapshotAfter = Get-BaselineGitMetadataSnapshot -ProjectRoot $script:NormalizedProjectRoot
            $assessment = Get-BaselineGitMetadataAssessment -Before $script:GitSnapshotBefore -After $script:GitSnapshotAfter
            $script:Result.gitMetadataIntegrity.presentAfter = [bool]$script:GitSnapshotAfter.present
            $script:Result.gitMetadataIntegrity.afterTreeSha256 = [string]$script:GitSnapshotAfter.treeSha256
            $script:Result.gitMetadataIntegrity.status = [string]$assessment.status
            $script:Result.gitMetadataIntegrity.unchanged = [bool]$assessment.unchanged
            $script:Result.gitMetadataIntegrity.ambientChangesAllowed = [bool]$assessment.ambientChangesAllowed
            foreach ($property in @('addedDirectories', 'removedDirectories', 'addedFiles', 'removedFiles', 'changedFiles')) {
                $script:Result.gitMetadataIntegrity[$property] = @($assessment.$property)
            }
            Add-UpvEvidence -Check 'gitMetadataIntegrity' -Status $assessment.status -Source $script:NormalizedProjectRoot -Detail 'In-project Git metadata was compared independently; only new Codex checkpoint entries may be ambient.'
        } catch {
            Add-UpvBlocker -Code 'GIT_METADATA_INTEGRITY_UNPROVEN' -Check 'gitMetadataIntegrity' -Path $script:NormalizedProjectRoot -Message $_.Exception.Message
        }
    }
}

# Applies final-status precedence without promoting incomplete evidence.
function Complete-UpvResult {
    $requiredScopes = @('scriptCompilation', 'editorPlayMode', 'playModeTests')
    if ($script:Result.selection.mode -eq 'SCENARIO_OVERLAY') {
        $requiredScopes += 'scenarioBehavior'
    }
    $requiredStatuses = [string[]]@($requiredScopes | ForEach-Object { [string]$script:Result.verification[$_].status })
    $script:Result.finalStatus = Get-UpvFinalStatusAssessment `
        -OriginalIntegrityStatus ([string]$script:Result.originalProjectIntegrity.status) `
        -GitIntegrityStatus ([string]$script:Result.gitMetadataIntegrity.status) `
        -BlockerCount $script:Blockers.Count `
        -FailureCount $script:Failures.Count `
        -CompatibilityStatus ([string]$script:Result.compatibility.verificationStatus) `
        -RequiredScopeStatuses $requiredStatuses
    if (
        $script:Result.finalStatus -eq 'VERIFICATION_BLOCKED' -and
        $script:Blockers.Count -eq 0 -and
        $script:Result.compatibility.verificationStatus -cne 'VERIFIED_SUCCESS'
    ) {
        Add-UpvBlocker -Code 'REQUIRED_COMPATIBILITY_NOT_VERIFIED' -Check 'compatibility' -Path $script:CompatibilityRegistryPath -Message 'Test Framework provenance and resolved content identity lack positive success evidence.'
    } elseif ($script:Result.finalStatus -eq 'VERIFICATION_BLOCKED' -and $script:Blockers.Count -eq 0) {
        Add-UpvBlocker -Code 'REQUIRED_SCOPE_NOT_VERIFIED' -Check 'finalStatus' -Path $null -Message 'One or more required Play verification scopes lack positive success evidence.'
    }
    $script:Result.warnings = @($script:Warnings)
    $script:Result.failures = @($script:Failures)
    $script:Result.blockers = @($script:Blockers)
    $script:Result.evidence = @($script:Evidence)
}

# Serializes one compact or pretty JSON document and persists the identical result artifact.
function Write-UpvResult {
    Complete-UpvResult
    if (-not [string]::IsNullOrWhiteSpace([string]$script:Result.artifacts.resultPath)) {
        $script:Result.artifacts.resultWritten = $true
    }
    $json = if ($Pretty) {
        ConvertTo-Json -InputObject $script:Result -Depth 50
    } else {
        ConvertTo-Json -InputObject $script:Result -Depth 50 -Compress
    }
    if ($script:Result.artifacts.resultWritten) {
        try {
            Write-UpvText -Path $script:Result.artifacts.resultPath -Content $json
        } catch {
            $script:Result.artifacts.resultWritten = $false
            Add-UpvBlocker -Code 'RESULT_ARTIFACT_WRITE_FAILED' -Check 'artifacts' -Path $script:Result.artifacts.resultPath -Message $_.Exception.Message
            Complete-UpvResult
            $json = if ($Pretty) { ConvertTo-Json -InputObject $script:Result -Depth 50 } else { ConvertTo-Json -InputObject $script:Result -Depth 50 -Compress }
        }
    }
    [Console]::Out.WriteLine($json)
}

try {
    try {
        $script:NormalizedProjectRoot = Get-UpvNormalizedPath -Path $ProjectRoot
        $script:Result.projectRoot = $script:NormalizedProjectRoot
        if (-not (Test-Path -LiteralPath $script:NormalizedProjectRoot -PathType Container)) {
            throw 'ProjectRoot is not an existing directory.'
        }
        $rootReparsePoint = Get-UpvReparsePointOnPath -Path $script:NormalizedProjectRoot
        if ($null -ne $rootReparsePoint) {
            throw "ProjectRoot traverses reparse point $rootReparsePoint."
        }
        foreach ($marker in @('Assets', 'Packages', 'ProjectSettings', 'ProjectSettings\ProjectVersion.txt')) {
            if (-not (Test-Path -LiteralPath (Join-Path $script:NormalizedProjectRoot $marker))) {
                throw "ProjectRoot is missing Unity marker $marker."
            }
        }
    } catch {
        Add-UpvBlocker -Code 'PROJECT_ROOT_REJECTED' -Check 'projectRoot' -Path $ProjectRoot -Message $_.Exception.Message
    }

    foreach ($selectorName in @('TestFilter', 'TestCategory', 'AssemblyNames')) {
        $value = Get-Variable -Name $selectorName -ValueOnly
        $assessment = Test-UpvSelectorValue -Value $value -Name $selectorName
        if (-not $assessment.accepted) {
            Add-UpvBlocker -Code 'TEST_SELECTOR_REJECTED' -Check 'selection' -Path $null -Message $assessment.error
        }
    }
    if (
        -not [string]::IsNullOrWhiteSpace($ScenarioBundlePath) -and
        (-not [string]::IsNullOrWhiteSpace($TestFilter) -or -not [string]::IsNullOrWhiteSpace($TestCategory) -or -not [string]::IsNullOrWhiteSpace($AssemblyNames))
    ) {
        Add-UpvBlocker -Code 'SCENARIO_SELECTION_CONFLICT' -Check 'selection' -Path $ScenarioBundlePath -Message 'ScenarioBundlePath cannot be combined with TestFilter, TestCategory, or AssemblyNames.'
    }

    if ($null -ne $script:NormalizedProjectRoot -and $script:Blockers.Count -eq 0) {
        $requestedArtifactsRoot = if ([string]::IsNullOrWhiteSpace($ArtifactsRoot)) {
            Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'upv'
        } else {
            $ArtifactsRoot
        }
        try {
            Initialize-UpvArtifactSession -RequestedRoot $requestedArtifactsRoot
        } catch {
            Add-UpvBlocker -Code 'ARTIFACT_ROOT_REJECTED' -Check 'artifactBoundary' -Path $requestedArtifactsRoot -Message $_.Exception.Message
        }
    }

    if ($script:Blockers.Count -eq 0) { Initialize-UpvOriginalIntegrity }
    if ($script:Blockers.Count -eq 0) { Invoke-UpvDoctorPreflight }
    if ($script:Blockers.Count -eq 0) { Test-UpvSourceProjectNotOpen }

    if ($script:Blockers.Count -eq 0) {
        $sourcePackages = Get-UpvLocalPackageAssessment -Root $script:NormalizedProjectRoot
        $script:Result.preflight.localPackagesSafe = $sourcePackages.accepted
        $script:Result.isolation.localPackageReferences = @($sourcePackages.references)
        if (-not $sourcePackages.accepted) {
            Add-UpvBlocker -Code 'LOCAL_PACKAGE_SAFETY_REJECTED' -Check 'localPackages' -Path (Join-Path $script:NormalizedProjectRoot 'Packages\manifest.json') -Message ([string]::Join(' ', [string[]]@($sourcePackages.errors)))
        }
    }
    if ($script:Blockers.Count -eq 0) { Test-UpvCompatibilityAndEditor }
    if ($script:Blockers.Count -eq 0) { Copy-UpvProjectToIsolation }

    if ($script:Blockers.Count -eq 0) {
        $isolatedPackages = Get-UpvLocalPackageAssessment -Root $script:Result.isolation.projectCopyPath
        $script:Result.preflight.isolatedLocalPackagesSafe = $isolatedPackages.accepted
        if (-not $isolatedPackages.accepted) {
            Add-UpvBlocker -Code 'ISOLATED_LOCAL_PACKAGE_SAFETY_REJECTED' -Check 'localPackages' -Path (Join-Path $script:Result.isolation.projectCopyPath 'Packages\manifest.json') -Message ([string]::Join(' ', [string[]]@($isolatedPackages.errors)))
        }
    }
    if ($script:Blockers.Count -eq 0) { Add-UpvScenarioOverlay }
    if ($script:Blockers.Count -eq 0) { Invoke-UpvUnity }
    if ($script:Result.unity.processStarted) { Set-UpvResolvedTestFrameworkIdentity }
    if ($script:Result.unity.processStarted) { Set-UpvVerificationEvidence }
} catch {
    Add-UpvBlocker -Code 'UNEXPECTED_VERIFIER_ERROR' -Check 'verifier' -Path $script:Result.projectRoot -Message $_.Exception.Message
} finally {
    if ($null -ne $script:NormalizedProjectRoot -and (Test-Path -LiteralPath $script:NormalizedProjectRoot -PathType Container)) {
        Complete-UpvOriginalIntegrity
    }
    Write-UpvResult
}
