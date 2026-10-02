#requires -Version 7.0
<#
.SYNOPSIS
Validates v0.13 save contracts inside a fresh, probed Windows sandbox.
.DESCRIPTION
Requires an already installed Godot 4.6.3 executable. Never downloads Godot,
changes the caller's environment, launches the game, or touches a real save.
Keeps the disposable project, userdata, raw logs and JSON report for review.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotBin,
    [string]$SandboxParent = [IO.Path]::GetTempPath(),
    [ValidateRange(10, 600)][int]$TimeoutSeconds = 180,
    [switch]$StrictLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This runner requires Windows file sharing and rename semantics.' }
$utf8 = [Text.UTF8Encoding]::new($false)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$environmentBefore = @{}
foreach ($name in @('HOME', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'USERPROFILE')) {
    $environmentBefore[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Assert-NoReparsePoint([string]$Path) {
    $candidate = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($candidate)) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse points are not accepted in QA paths: $candidate"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($candidate)
        if ($parent -eq $candidate) { break }
        $candidate = $parent
    }
}

function Assert-Inside([string]$Path, [string]$Parent) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($Parent).TrimEnd([char]92, [char]47) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "QA path escaped its allowed root: $full"
    }
    Assert-NoReparsePoint $full
    return $full
}

function Write-Utf8([string]$Path, [string]$Value) {
    [IO.File]::WriteAllText($Path, $Value, $utf8)
}

Assert-NoReparsePoint $repoRoot
$resolvedGodot = (Get-Item -LiteralPath $GodotBin -Force).FullName
if ([IO.Path]::GetExtension($resolvedGodot) -ne '.exe' -or -not (Test-Path -LiteralPath $resolvedGodot -PathType Leaf)) {
    throw 'GodotBin must be the literal path to an existing Godot executable, not a shell command.'
}
Assert-NoReparsePoint $resolvedGodot
$sandboxParentFull = [IO.Path]::GetFullPath($SandboxParent)
Assert-NoReparsePoint $sandboxParentFull
$token = [Guid]::NewGuid().ToString('N')
$sandboxRoot = Join-Path $sandboxParentFull ('godot-save-qa-' + $token)
if (Test-Path -LiteralPath $sandboxRoot) { throw 'Refusing to reuse a pre-existing sandbox.' }
$projectRoot = Join-Path $sandboxRoot '中文 工程'
$roamingRoot = Join-Path $sandboxRoot 'roaming'
$localRoot = Join-Path $sandboxRoot 'local'
$tempRoot = Join-Path $sandboxRoot 'temp'
$logRoot = Join-Path $sandboxRoot 'logs'
$userdataRoot = Join-Path $roamingRoot ('存档 沙箱 ' + $token)
foreach ($path in @($projectRoot, $roamingRoot, $localRoot, $tempRoot, $logRoot, $userdataRoot)) {
    $null = Assert-Inside $path $sandboxRoot
    [void][IO.Directory]::CreateDirectory($path)
}
$reportPath = Join-Path $sandboxRoot 'report.json'
$steps = [Collections.Generic.List[object]]::new()
$manifest = [Collections.Generic.List[object]]::new()
$report = [ordered]@{
    schema = 1
    status = 'running'
    started_at_utc = [DateTime]::UtcNow.ToString('o')
    sandbox = $sandboxRoot
    project = $projectRoot
    user_data_dir = $userdataRoot
    godot_binary = $resolvedGodot
    godot_sha256 = (Get-FileHash -LiteralPath $resolvedGodot -Algorithm SHA256).Hash
    version = $null
    isolation_verified = $false
    mismatch_probe_rejected = $false
    parent_environment_unchanged = $false
    source_resources_unchanged = $false
    storage_checks_passed = $false
    baseline_checks_passed = $false
    strict_log_clean = $false
    strict_logs_requested = [bool]$StrictLogs
    checks = 0
    failures = 0
    system_errors = @()
    error = $null
    steps = $steps
    copied_resources = $manifest
}
$gateVerified = $false
$stepIndex = 0

function Write-Report {
    Write-Utf8 $reportPath ($report | ConvertTo-Json -Depth 16)
}

function Copy-QAResource([string]$RelativePath) {
    $source = Assert-Inside (Join-Path $repoRoot $RelativePath) $repoRoot
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required source resource is missing: $RelativePath" }
    $destination = Assert-Inside (Join-Path $projectRoot $RelativePath) $projectRoot
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    [IO.File]::Copy($source, $destination, $false)
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Copied resource differs from source.' }
    $manifest.Add(@{path=$RelativePath;sha256=$sourceHash})
}

function Copy-ModelClosure {
    # Copy only literal res:// dependencies reachable from BuildState.
    # The new project has no main scene, autoload, editor plugin or export preset.
    $queue = [Collections.Generic.Queue[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $queue.Enqueue('scripts/build_state.gd')
    $resourcePattern = 'res://([^"''\r\n]+)'
    while ($queue.Count -gt 0) {
        $relative = $queue.Dequeue()
        if (-not $seen.Add($relative)) { continue }
        Copy-QAResource $relative
        $source = Assert-Inside (Join-Path $repoRoot $relative) $repoRoot
        if ([IO.Path]::GetExtension($source) -eq '.gd') {
            if (Test-Path -LiteralPath ($source + '.uid')) { Copy-QAResource ($relative + '.uid') }
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($source, $utf8), $resourcePattern)) {
                $dependency = $match.Groups[1].Value
                if ($dependency -match '(^|[\\/])\.\.([\\/]|$)' -or $dependency.Contains(':')) {
                    throw "Nonliteral or escaping model dependency: $dependency"
                }
                $queue.Enqueue($dependency)
            }
        }
    }
}

function Copy-WindowsTestScript([string]$Name) {
    $relative = 'tests/windows/' + $Name
    Copy-QAResource $relative
    if (Test-Path -LiteralPath (Join-Path $repoRoot ($relative + '.uid')) -PathType Leaf) {
        Copy-QAResource ($relative + '.uid')
    }
}

function Invoke-Engine {
    param([string]$Name, [string[]]$EngineArguments, [hashtable]$EnvironmentOverride = @{}, [switch]$RequiresGate)
    if ($RequiresGate -and -not $gateVerified) { throw 'Refusing to execute tests before an actual OS userdata probe.' }
    $script:stepIndex += 1
    $logPath = Join-Path $logRoot ('{0:d2}-{1}.log' -f $stepIndex, $Name)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $resolvedGodot
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8
    # ProcessStartInfo owns a child-only environment copy. No $env: assignments,
    # registry writes, HOME override, or modification to the Godot installation.
    foreach ($entry in @{
        APPDATA=$roamingRoot; LOCALAPPDATA=$localRoot; TEMP=$tempRoot; TMP=$tempRoot
        GODOT_SAVE_QA_ROOT=$sandboxRoot; GODOT_SAVE_QA_PROJECT=$projectRoot
        GODOT_SAVE_QA_USERDATA=$userdataRoot; GODOT_SAVE_QA_TOKEN=$token
    }.GetEnumerator()) { $startInfo.Environment[$entry.Key] = $entry.Value }
    foreach ($entry in $EnvironmentOverride.GetEnumerator()) { $startInfo.Environment[$entry.Key] = $entry.Value }
    foreach ($argument in @('--headless', '--path', $projectRoot) + $EngineArguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "[$Name] $logPath"
    $step = [ordered]@{name=$Name;exit_code=$null;seconds=0;log=$logPath;system_errors=@();engine_errors=@();gate=$null;result=$null}
    $steps.Add($step)
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            Write-Utf8 $logPath ($stdoutTask.GetAwaiter().GetResult() + "`n" + $stderrTask.GetAwaiter().GetResult())
            throw "Godot timed out in $Name; only this runner's process tree was terminated."
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        Write-Utf8 $logPath ("[stdout]`n" + $stdout + "`n[stderr]`n" + $stderr)
        if ($stdout) { Write-Host $stdout.TrimEnd() }
        if ($stderr) { Write-Host $stderr.TrimEnd() }
        $step.exit_code = $process.ExitCode
        $allLines = ($stdout + "`n" + $stderr) -split '\r?\n'
        $step.system_errors = @($allLines | Where-Object { $_ -cmatch '^ERROR: Failed to read the root certificate store\.$' })
        $step.engine_errors = @($allLines | Where-Object { $_ -match '(^|\s)(SCRIPT ERROR:|ERROR:)' -and $_ -cnotmatch '^ERROR: Failed to read the root certificate store\.$' })
        $report.system_errors = @($report.system_errors) + @($step.system_errors | ForEach-Object { @{step=$Name;message=$_;log=$logPath} })
        return @{step=$step;stdout=$stdout;stderr=$stderr}
    } finally {
        $watch.Stop()
        $step.seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        $process.Dispose()
        Write-Report
    }
}

function Assert-EngineClean($Run, [int]$ExpectedExit = 0) {
    if ($Run.step.exit_code -ne $ExpectedExit -or $Run.step.engine_errors.Count -gt 0) {
        throw "Godot failed in $($Run.step.name): exit=$($Run.step.exit_code); see $($Run.step.log)"
    }
}

function Read-Marker($Run, [string]$Prefix) {
    $matches = @($Run.stdout -split '\r?\n' | Where-Object { $_.StartsWith($Prefix, [StringComparison]::Ordinal) })
    if ($matches.Count -ne 1) { throw "Expected exactly one $Prefix marker in $($Run.step.name)" }
    return $matches[0].Substring($Prefix.Length) | ConvertFrom-Json -AsHashtable
}

function Assert-Gate($Run, [bool]$ExpectedOk = $true) {
    $actual = Read-Marker $Run 'SAVE_QA_GATE '
    $Run.step.gate = $actual
    if ($actual.ok -ne $ExpectedOk -or $actual.token -ne $token) { throw 'Godot sandbox gate did not give the expected verdict.' }
    # Independently check actual OS.get_user_data_dir and user://, even when
    # checking that the deliberate expected-path mismatch was rejected.
    $null = Assert-Inside $actual.project $sandboxRoot
    $null = Assert-Inside $actual.user_data_dir $sandboxRoot
    if ([IO.Path]::GetFullPath($actual.project).TrimEnd([char]92, [char]47) -ine $projectRoot -or
        [IO.Path]::GetFullPath($actual.user_data_dir).TrimEnd([char]92, [char]47) -ine $userdataRoot -or
        [IO.Path]::GetFullPath($actual.user_alias).TrimEnd([char]92, [char]47) -ine $userdataRoot) {
        throw 'Independent PowerShell userdata verification failed.'
    }
}

function Test-Scene([string]$Name, [string]$ScriptPath, [string[]]$UserArguments = @()) {
    $arguments = @('--script', $ScriptPath)
    if ($UserArguments.Count -gt 0) { $arguments += @('--') + $UserArguments }
    $run = Invoke-Engine -Name $Name -EngineArguments $arguments -RequiresGate
    Assert-Gate $run
    $result = Read-Marker $run 'SAVE_QA_RESULT '
    $run.step.result = $result
    $report.checks += $result.checks
    $report.failures += $result.failures
    Write-Report
    Assert-EngineClean $run
    if (-not $result.completed -or $result.failures -ne 0 -or $result.checks -le 0 -or $result.case -ne $Name) {
        throw "Godot save assertions failed or did not complete: $Name"
    }
    if ($Name -eq 'save-contracts' -and ($result.migration_encodings -ne 32 -or $result.cases.Count -ne 5)) {
        throw 'Historical save matrix did not complete.'
    }
    Write-Report
}

Write-Host "Windows save QA sandbox: $sandboxRoot"
Write-Report
try {
    $projectText = @"
config_version=5

[application]
config/name="Windows Save QA $token"
config/use_custom_user_dir=true
config/custom_user_dir_name="存档 沙箱 $token"
config/features=PackedStringArray("4.6", "GL Compatibility")

[rendering]
renderer/rendering_method="gl_compatibility"

[debug]
file_logging/enable_logging=false
file_logging/enable_logging.pc=false
"@
    Write-Utf8 (Join-Path $projectRoot 'project.godot') $projectText
    Copy-WindowsTestScript 'save_sandbox.gd'
    Copy-WindowsTestScript 'save_probe.gd'
    $versionRun = Invoke-Engine -Name 'version' -EngineArguments @('--version')
    Assert-EngineClean $versionRun
    $report.version = $versionRun.stdout.Trim()
    if ($report.version -notmatch '^4\.6\.3\.stable\.official\.') { throw 'This runner requires official Godot 4.6.3 stable.' }
    $probe = Invoke-Engine -Name 'probe' -EngineArguments @('--script', 'res://tests/windows/save_probe.gd')
    Assert-EngineClean $probe
    Assert-Gate $probe
    $gateVerified = $true
    $report.isolation_verified = $true
    $negativeProbe = Invoke-Engine -Name 'probe-mismatch' -EngineArguments @('--script', 'res://tests/windows/save_probe.gd') -EnvironmentOverride @{GODOT_SAVE_QA_USERDATA=(Join-Path $userdataRoot 'mismatch')} -RequiresGate
    Assert-EngineClean $negativeProbe 78
    Assert-Gate $negativeProbe $false
    # Engine bootstrap logs can exist here; fixture/model writes cannot precede the probe.
    if (Test-Path -LiteralPath (Join-Path $userdataRoot '中文 存档')) { throw 'Save fixtures appeared before validation.' }
    $report.probe_userdata_entries = @(Get-ChildItem -LiteralPath $userdataRoot -Force | Select-Object -ExpandProperty Name)
    $report.mismatch_probe_rejected = $true
    Copy-ModelClosure
    foreach ($name in @('save_fixture.gd', 'save_compile_probe.gd', 'save_validation_test.gd', 'save_fault_test.gd', 'save_path_alias_test.gd')) { Copy-WindowsTestScript $name }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests/windows/save_fixtures') -File) {
        Copy-QAResource ('tests/windows/save_fixtures/' + $file.Name)
    }
    # Do not use editor/import: a portable _sc_ marker can redirect editor settings
    # into the supplied Godot installation despite child-only APPDATA isolation.
    # This model closure contains only GDScript and plain JSON, no imported assets.
    Test-Scene 'compile-model' 'res://tests/windows/save_compile_probe.gd'
    Test-Scene 'save-contracts' 'res://tests/windows/save_validation_test.gd'

    $saveDirectory = Assert-Inside (Join-Path $userdataRoot '中文 存档') $userdataRoot
    $literalV9 = [IO.File]::ReadAllText((Join-Path $projectRoot 'tests/windows/save_fixtures/save_v9.json'), $utf8).Replace("`r`n", "`n").Trim()
    $encodedV9 = "`r`n  " + $literalV9.Replace("`n", "`r`n") + "`r`n`r`n"
    [byte[]]$original = [byte[]](239, 187, 191) + $utf8.GetBytes($encodedV9)
    $tempSentinel = $utf8.GetBytes("another process owns this temporary file`r`n")
    foreach ($case in @('destination-lock', 'temporary-lock', 'rename-directory')) {
        $destination = Assert-Inside (Join-Path $saveDirectory ($case + ' 锁定.json')) $userdataRoot
        $temporary = Assert-Inside ($destination + '.tmp') $userdataRoot
        if ($case -eq 'rename-directory') {
            [void][IO.Directory]::CreateDirectory($destination)
            Write-Utf8 (Join-Path $destination 'sentinel.txt') "existing directory must survive`r`n"
            Test-Scene $case 'res://tests/windows/save_fault_test.gd' @($case)
            # Remove only the two exact sandbox objects created above, never a tree.
            [IO.File]::Delete((Assert-Inside (Join-Path $destination 'sentinel.txt') $userdataRoot))
            [IO.Directory]::Delete((Assert-Inside $destination $userdataRoot), $false)
        } else {
            [IO.File]::WriteAllBytes($destination, $original)
            $lockPath = $destination
            $sharing = [IO.FileShare]::Read
            if ($case -eq 'temporary-lock') {
                [IO.File]::WriteAllBytes($temporary, $tempSentinel)
                $lockPath = $temporary
                $sharing = [IO.FileShare]::None
            }
            $lock = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, $sharing)
            try { Test-Scene $case 'res://tests/windows/save_fault_test.gd' @($case) }
            finally { $lock.Dispose() }
            if ([BitConverter]::ToString([IO.File]::ReadAllBytes($destination)) -cne [BitConverter]::ToString($original)) { throw "$case altered the original target." }
            if ($case -eq 'temporary-lock') {
                if ([BitConverter]::ToString([IO.File]::ReadAllBytes($temporary)) -cne [BitConverter]::ToString($tempSentinel)) { throw 'Failed write changed another process temporary file.' }
                [IO.File]::Delete((Assert-Inside $temporary $userdataRoot))
            }
        }
        Test-Scene ('retry-' + $case) 'res://tests/windows/save_fault_test.gd' @('retry-' + $case)
    }
    $report.baseline_checks_passed = $true
    Write-Report
    Test-Scene 'save-path-aliases' 'res://tests/windows/save_path_alias_test.gd'
    foreach ($entry in $manifest) {
        if ((Get-FileHash -LiteralPath (Join-Path $repoRoot $entry.path) -Algorithm SHA256).Hash -ne $entry.sha256) {
            throw "Original source changed during validation: $($entry.path)"
        }
    }
    $report.storage_checks_passed = $true
    $report.strict_log_clean = $report.system_errors.Count -eq 0
    $report.status = if ($report.strict_log_clean) { 'passed' } else { 'passed-with-system-errors' }
    if ($StrictLogs -and -not $report.strict_log_clean) { throw 'Storage checks passed, but StrictLogs rejects the retained Windows certificate-store error.' }
} catch {
    $report.status = 'failed'
    $report.error = $_.Exception.Message
    Write-Host "Windows save QA FAILED: $($report.error)"
} finally {
    $sourceUnchanged = $true
    foreach ($entry in $manifest) {
        try {
            if ((Get-FileHash -LiteralPath (Join-Path $repoRoot $entry.path) -Algorithm SHA256).Hash -ne $entry.sha256) { $sourceUnchanged = $false }
        } catch { $sourceUnchanged = $false }
    }
    $report.source_resources_unchanged = $sourceUnchanged
    if (-not $sourceUnchanged) { $report.status = 'failed'; $report.error = 'Source resources changed during QA.' }
    $unchanged = $true
    foreach ($entry in $environmentBefore.GetEnumerator()) {
        if ([Environment]::GetEnvironmentVariable($entry.Key, 'Process') -cne $entry.Value) { $unchanged = $false }
    }
    $report.parent_environment_unchanged = $unchanged
    if (-not $unchanged) { $report.status = 'failed'; $report.error = 'Caller environment changed during QA.' }
    $report.passed_checks = $report.checks - $report.failures
    $report.strict_log_clean = @($steps | Where-Object { $_.system_errors.Count -gt 0 -or $_.engine_errors.Count -gt 0 }).Count -eq 0
    $report.finished_at_utc = [DateTime]::UtcNow.ToString('o')
    Write-Report
    Write-Host "Report retained: $reportPath"
}
if ($report.status -eq 'failed') { exit 1 }
Write-Host "Windows save QA $($report.status): $($report.checks) checks. Strict log clean: $($report.strict_log_clean)."
exit 0
