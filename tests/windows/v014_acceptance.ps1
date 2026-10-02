#requires -Version 7.0
<#
.SYNOPSIS
Checks the exact v0.14 source SHA in disposable Windows projects and userdata.
.DESCRIPTION
Copies the existing verified Godot console/engine pair. All editor data, imports,
saves and raw logs remain in a new sandbox. No downloads or user setting changes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotBin,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedSourceSha,
    [string]$PythonBin = 'python',
    [string]$SandboxParent = [IO.Path]::GetTempPath(),
    [ValidateRange(10, 600)][int]$TimeoutSeconds = 180,
    [switch]$PrepareOnly,
    [switch]$FontOnly,
    [switch]$StrictLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows is required for actual case aliases and save semantics.' }
if ($PrepareOnly -and $FontOnly) { throw 'PrepareOnly and FontOnly are separate validation scopes.' }
$utf8 = [Text.UTF8Encoding]::new($false)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$environmentBefore = @{}
foreach ($name in @('HOME', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'USERPROFILE')) {
    $environmentBefore[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Assert-NoReparse([string]$Path) {
    $candidate = [IO.Path]::GetFullPath($Path)
    while ($candidate) {
        if (Test-Path -LiteralPath $candidate) {
            if (((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse points are not accepted: $candidate"
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
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escaped QA root: $full" }
    Assert-NoReparse $full
    return $full
}

function Write-Utf8([string]$Path, [string]$Value) { [IO.File]::WriteAllText($Path, $Value, $utf8) }

Assert-NoReparse $repoRoot
$actualSha = (& git -c core.excludesfile= -C $repoRoot rev-parse $ExpectedSourceSha).Trim()
if ($LASTEXITCODE -ne 0 -or $actualSha -cne $ExpectedSourceSha) { throw 'Expected source SHA is unavailable.' }
$changed = @(& git -c core.excludesfile= -C $repoRoot diff --name-only $ExpectedSourceSha --)
if ($LASTEXITCODE -ne 0) { throw 'Could not compare source SHA.' }
foreach ($path in $changed) {
    if ($path -notmatch '^tests/windows/v014_[^/]+$' -and $path -cne 'docs/windows-qa/V014_ACCEPTANCE.zh-CN.md') {
        throw "Checkout differs from exact production source SHA: $path"
    }
}
$untracked = @(& git -c core.excludesfile= -C $repoRoot ls-files --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate untracked resources.' }
foreach ($path in $untracked) {
    if ($path -notmatch '^tests/windows/v014_[^/]+$' -and $path -cne 'docs/windows-qa/V014_ACCEPTANCE.zh-CN.md') {
        throw "Unexpected untracked file could alter the copied project: $path"
    }
}
$resolvedGodot = (Get-Item -LiteralPath $GodotBin -Force).FullName
if ([IO.Path]::GetFileName($resolvedGodot) -cne 'Godot_v4.6.3-stable_win64_console.exe') { throw 'Use the verified Godot 4.6.3 console executable.' }
$pairedEngine = Join-Path ([IO.Path]::GetDirectoryName($resolvedGodot)) 'Godot_v4.6.3-stable_win64.exe'
Assert-NoReparse $resolvedGodot
Assert-NoReparse $pairedEngine
$resolvedPython = (Get-Command $PythonBin -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$sourceConfigHash = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'project.godot') -Algorithm SHA256).Hash.ToLowerInvariant()
$parentFull = [IO.Path]::GetFullPath($SandboxParent)
Assert-NoReparse $parentFull
$token = [Guid]::NewGuid().ToString('N')
$sandboxRoot = Join-Path $parentFull ('godot-v014-qa-' + $token)
if (Test-Path -LiteralPath $sandboxRoot) { throw 'Refusing to reuse a sandbox.' }
$projectRoot = Join-Path $sandboxRoot '中文 工程'
$runtimeRoot = Join-Path $sandboxRoot 'runtime'
$roamingRoot = Join-Path $sandboxRoot 'roaming'
$localRoot = Join-Path $sandboxRoot 'local'
$tempRoot = Join-Path $sandboxRoot 'temp'
$logRoot = Join-Path $sandboxRoot 'logs'
foreach ($path in @($projectRoot, $runtimeRoot, $roamingRoot, $localRoot, $tempRoot, $logRoot)) {
    $null = Assert-Inside $path $sandboxRoot
    [void][IO.Directory]::CreateDirectory($path)
}
$copiedGodot = Join-Path $runtimeRoot ([IO.Path]::GetFileName($resolvedGodot))
$runtimeManifest = @()
foreach ($source in @($resolvedGodot, $pairedEngine)) {
    $destination = Join-Path $runtimeRoot ([IO.Path]::GetFileName($source))
    [IO.File]::Copy($source, $destination, $false)
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -cne $hash) { throw 'Copied Godot binary hash mismatch.' }
    $runtimeManifest += @{name=[IO.Path]::GetFileName($source);source=$source;sha256=$hash}
}
# This new marker redirects editor data into the OWNED runtime, never the source installation.
Write-Utf8 (Join-Path $runtimeRoot '_sc_') ''
$manifest = [Collections.Generic.List[object]]::new()
$steps = [Collections.Generic.List[object]]::new()
$reportPath = Join-Path $sandboxRoot 'report.json'
$report = [ordered]@{
    schema=1;status='running';source_sha=$ExpectedSourceSha;started_at_utc=[DateTime]::UtcNow.ToString('o')
    validation_scope=if ($FontOnly) { 'font-only' } elseif ($PrepareOnly) { 'probe-only' } else { 'full-v014' }
    sandbox=$sandboxRoot;project=$projectRoot;runtime=$runtimeManifest;godot_version=$null
    isolation_verified=$false;mismatch_probe_rejected=$false;source_resources_unchanged=$false
    parent_environment_unchanged=$false;source_runtime_unchanged=$false;functional_checks_passed=$false;strict_log_clean=$false
    strict_logs_requested=[bool]$StrictLogs;checks=0;failures=0;font=$null;acceptance=$null
    system_errors=@();error=$null;runner_exit_code=$null;steps=$steps;copied_resources=$manifest
}
$stepIndex = 0
$gateVerified = $false
$activeName = ''
$userdataRoot = ''
$configurationBase = "config_version=5`n`n[application]`nconfig/name=`"Windows V014 Probe`"`nconfig/features=PackedStringArray(`"4.6`", `"GL Compatibility`")`n`n[rendering]`nrenderer/rendering_method=`"gl_compatibility`"`n"

function Write-Report { Write-Utf8 $reportPath ($report | ConvertTo-Json -Depth 30) }

function Copy-Resource([string]$Relative) {
    $source = Assert-Inside (Join-Path $repoRoot $Relative) $repoRoot
    $destination = Assert-Inside (Join-Path $projectRoot $Relative) $projectRoot
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source: $Relative" }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    [IO.File]::Copy($source, $destination, $true)
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -cne $hash) { throw "Copied resource mismatch: $Relative" }
    $manifest.Add(@{path=$Relative;sha256=$hash})
}

function Copy-Folder([string]$Relative) {
    $source = Assert-Inside (Join-Path $repoRoot $Relative) $repoRoot
    foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
        Assert-NoReparse $item.FullName
        if ($item.Name -in @('.git', '.godot', '__pycache__')) { continue }
        $child = $Relative + '/' + $item.Name
        if ($item.PSIsContainer) { Copy-Folder $child } else { Copy-Resource $child }
    }
}

function Set-Userdata([string]$CaseName) {
    if ($CaseName -notmatch '^[a-z0-9-]+$') { throw 'Invalid QA case name.' }
    $script:gateVerified = $false
    $script:activeName = '存档 沙箱 ' + $token + '-' + $CaseName
    $script:userdataRoot = Assert-Inside (Join-Path $roamingRoot $activeName) $sandboxRoot
    if (Test-Path -LiteralPath $userdataRoot) { throw 'Each QA group must get fresh userdata.' }
    [void][IO.Directory]::CreateDirectory($userdataRoot)
    $configuration = [regex]::Replace($configurationBase, '(?m)^config/(use_custom_user_dir|custom_user_dir_name)=.*\r?\n?', '')
    $configuration = $configuration.Replace('[application]', "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"$activeName`"")
    # File logging does not need to write even into isolated userdata.
    if ($configuration -match '(?m)^\[debug\]') { throw 'Unexpected debug section; review before changing QA configuration.' }
    $configuration += "`n[debug]`nfile_logging/enable_logging=false`nfile_logging/enable_logging.pc=false`n"
    Write-Utf8 (Join-Path $projectRoot 'project.godot') $configuration
}

function Invoke-Child {
    param([string]$Name, [string]$Executable=$copiedGodot, [string[]]$Arguments, [hashtable]$Overrides=@{}, [switch]$RequiresGate)
    if ($RequiresGate -and -not $gateVerified) { throw 'No production execution before an independent userdata probe.' }
    $script:stepIndex += 1
    $logPath = Join-Path $logRoot ('{0:d2}-{1}.log' -f $stepIndex, $Name)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName=$Executable
    $startInfo.WorkingDirectory=$projectRoot
    $startInfo.UseShellExecute=$false
    $startInfo.CreateNoWindow=$true
    $startInfo.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput=$true
    $startInfo.RedirectStandardError=$true
    $startInfo.StandardOutputEncoding=$utf8
    $startInfo.StandardErrorEncoding=$utf8
    foreach ($entry in @{
        APPDATA=$roamingRoot;LOCALAPPDATA=$localRoot;TEMP=$tempRoot;TMP=$tempRoot
        GODOT_V014_QA_ROOT=$sandboxRoot;GODOT_V014_QA_PROJECT=$projectRoot
        GODOT_V014_QA_USERDATA=$userdataRoot;GODOT_V014_QA_TOKEN=$token;GODOT_V014_QA_NAME=$activeName
        GODOT_V014_QA_SOURCE=$repoRoot;GODOT_V014_QA_CONFIG_SHA256=$sourceConfigHash
        PYTHONIOENCODING='utf-8';PYTHONDONTWRITEBYTECODE='1'
    }.GetEnumerator()) { $startInfo.Environment[$entry.Key]=$entry.Value }
    foreach ($entry in $Overrides.GetEnumerator()) { $startInfo.Environment[$entry.Key]=$entry.Value }
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$startInfo
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $step=[ordered]@{name=$Name;exit_code=$null;seconds=0;log=$logPath;userdata=$userdataRoot;system_errors=@();engine_errors=@();gate=$null;result=$null}
    $steps.Add($step)
    Write-Host "[$Name] $logPath"
    try {
        [void]$process.Start()
        $stdoutTask=$process.StandardOutput.ReadToEndAsync()
        $stderrTask=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds*1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            Write-Utf8 $logPath ($stdoutTask.GetAwaiter().GetResult()+"`n"+$stderrTask.GetAwaiter().GetResult())
            throw "Timeout in $Name; terminated only this owned process tree."
        }
        $stdout=$stdoutTask.GetAwaiter().GetResult()
        $stderr=$stderrTask.GetAwaiter().GetResult()
        Write-Utf8 $logPath ("[stdout]`n"+$stdout+"`n[stderr]`n"+$stderr)
        $step.exit_code=$process.ExitCode
        $lines=($stdout+"`n"+$stderr) -split '\r?\n'
        $step.system_errors=@($lines | Where-Object { $_ -cmatch '^ERROR: Failed to read the root certificate store\.$' })
        $step.engine_errors=@($lines | Where-Object { $_ -match '(^|\s)(SCRIPT ERROR:|ERROR:)' -and $_ -cnotmatch '^ERROR: Failed to read the root certificate store\.$' })
        $report.system_errors=@($report.system_errors)+@($step.system_errors | ForEach-Object { @{step=$Name;message=$_;log=$logPath} })
        return @{step=$step;stdout=$stdout;stderr=$stderr}
    } finally {
        $watch.Stop()
        $step.seconds=[Math]::Round($watch.Elapsed.TotalSeconds,3)
        $process.Dispose()
        Write-Report
    }
}

function Assert-Clean($Run, [int]$ExitCode=0) {
    if ($Run.step.exit_code -ne $ExitCode -or $Run.step.engine_errors.Count -gt 0) {
        throw "Step failed: $($Run.step.name), exit=$($Run.step.exit_code); inspect $($Run.step.log)"
    }
}

function Read-Marker($Run, [string]$Prefix) {
    $markers=@($Run.stdout -split '\r?\n' | Where-Object { $_.StartsWith($Prefix,[StringComparison]::Ordinal) })
    if ($markers.Count -ne 1) { throw "Expected exactly one $Prefix in $($Run.step.name)" }
    return $markers[0].Substring($Prefix.Length) | ConvertFrom-Json -AsHashtable
}

function Assert-Gate($Run, [bool]$ExpectedOk=$true) {
    $gate=Read-Marker $Run 'V014_QA_GATE '
    $Run.step.gate=$gate
    if ($gate.ok -ne $ExpectedOk -or $gate.token -cne $token) { throw 'Unexpected isolation verdict.' }
    foreach ($value in @($gate.project,$gate.user_data_dir,$gate.user_alias)) { $null=Assert-Inside $value $sandboxRoot }
    if ([IO.Path]::GetFullPath($gate.project).TrimEnd([char]92,[char]47) -ine $projectRoot -or
        [IO.Path]::GetFullPath($gate.user_data_dir).TrimEnd([char]92,[char]47) -ine $userdataRoot -or
        [IO.Path]::GetFullPath($gate.user_alias).TrimEnd([char]92,[char]47) -ine $userdataRoot) {
        throw 'Independent PowerShell check of actual OS userdata path failed.'
    }
}

function Probe-Userdata([string]$Name) {
    $run=Invoke-Child -Name $Name -Arguments @('--headless','--path',$projectRoot,'--script','res://tests/windows/v014_probe.gd')
    Assert-Clean $run
    Assert-Gate $run
    $script:gateVerified=$true
    return $run
}

Write-Host "v0.14 Windows sandbox: $sandboxRoot"
Write-Report
try {
    Copy-Resource 'tests/windows/v014_sandbox.gd'
    Copy-Resource 'tests/windows/v014_probe.gd'
    Set-Userdata 'primary'
    $versionRun=Invoke-Child -Name 'version' -Arguments @('--version')
    Assert-Clean $versionRun
    $report.godot_version=$versionRun.stdout.Trim()
    if ($report.godot_version -notmatch '^4\.6\.3\.stable\.official\.') { throw 'Unexpected Godot version.' }
    $null=Probe-Userdata 'minimal-probe'
    $report.isolation_verified=$true
    $negative=Invoke-Child -Name 'probe-mismatch' -Arguments @('--headless','--path',$projectRoot,'--script','res://tests/windows/v014_probe.gd') -Overrides @{GODOT_V014_QA_USERDATA=(Join-Path $userdataRoot 'mismatch')}
    Assert-Clean $negative 78
    Assert-Gate $negative $false
    $report.mismatch_probe_rejected=$true
    if (-not $PrepareOnly) {
        foreach ($folder in @('scripts','scenes','data','assets','tests')) { Copy-Folder $folder }
        Copy-Resource 'tools/check_font_coverage.py'
        Copy-Resource 'project.godot'
        $script:configurationBase=[IO.File]::ReadAllText((Join-Path $repoRoot 'project.godot'),$utf8)
        if ($configurationBase -match '(?m)^\[(autoload|editor_plugins)\]') { throw 'Unexpected bootstrap code; review before running.' }
        # Rebuild safety settings without changing any source file.
        $configuration=$configurationBase.Replace('[application]',"[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"$activeName`"")
        $configuration += "`n[debug]`nfile_logging/enable_logging=false`nfile_logging/enable_logging.pc=false`n"
        Write-Utf8 (Join-Path $projectRoot 'project.godot') $configuration
        $null=Probe-Userdata 'production-config-probe'
        $import=Invoke-Child -Name 'import' -Arguments @('--headless','--path',$projectRoot,'--editor','--import') -RequiresGate
        Assert-Clean $import
        $fontRun=Invoke-Child -Name 'font-coverage' -Executable $resolvedPython -Arguments @((Join-Path $projectRoot 'tests/windows/v014_font_check.py'),'--root',$projectRoot,'--source-project',(Join-Path $repoRoot 'project.godot')) -RequiresGate
        $font=Read-Marker $fontRun 'V014_FONT_RESULT '
        $fontRun.step.result=$font
        $report.font=$font
        Assert-Clean $fontRun
        if (-not $font.ok) { throw 'Independent bundled font coverage failed.' }
        $acceptanceArguments=@('--headless','--path',$projectRoot,'--script','res://tests/windows/v014_acceptance.gd')
        if ($FontOnly) { $acceptanceArguments+=@('--','--font-only') }
        $acceptanceName=if ($FontOnly) { 'v014-font-runtime' } else { 'v014-acceptance' }
        $acceptance=Invoke-Child -Name $acceptanceName -Arguments $acceptanceArguments -RequiresGate
        Assert-Gate $acceptance
        Assert-Clean $acceptance
        $result=Read-Marker $acceptance 'V014_QA_RESULT '
        $acceptance.step.result=$result
        $report.acceptance=$result
        $report.checks+=$result.checks
        $report.failures+=$result.failures
        if (-not $result.completed -or $result.failures -ne 0) { throw 'v0.14 acceptance failed or did not finish.' }
        if ($FontOnly) {
            if ($result.cases.Count -ne 1 -or $result.font.supported_chars -ne $font.mapped_codepoints -or $result.font.native_mappings -ne 2*$font.mapped_codepoints) { throw 'Native font-only acceptance is incomplete.' }
        } elseif ($result.cases.Count -ne 6 -or $result.migration_encodings -ne 16 -or $result.formulas.Count -ne 12) {
            throw 'v0.14 acceptance matrix is incomplete.'
        }
        $suites=if ($FontOnly) { @() } else { @('projectile_support_rules','skill_compiler','skill_support_state','skill_support_integration','local_weapon_compiler','local_weapon_state','local_weapon_integration','save_guard_integration','combat_pipeline','spatial_collision','projectile_schedule') }
        foreach ($suite in $suites) {
            $caseName=$suite.Replace('_','-')
            Set-Userdata $caseName
            $null=Probe-Userdata ('probe-'+$caseName)
            $run=Invoke-Child -Name $caseName -Arguments @('--headless','--path',$projectRoot,'--script',('res://tests/'+$suite+'_test.gd')) -RequiresGate
            Assert-Clean $run
            $summaries=[regex]::Matches($run.stdout,'(?<checks>\d+) checks,\s*(?<failures>\d+) failures')
            if ($summaries.Count -ne 1) { throw "Missing/ambiguous existing suite summary: $suite" }
            $suiteChecks=[int]$summaries[0].Groups['checks'].Value
            $suiteFailures=[int]$summaries[0].Groups['failures'].Value
            if ($suiteChecks -le 0 -or $suiteFailures -ne 0) { throw "Existing suite assertions failed: $suite" }
            $run.step.result=@{checks=$suiteChecks;failures=$suiteFailures}
            $report.checks+=$suiteChecks
            $report.failures+=$suiteFailures
            Write-Report
        }
        $report.functional_checks_passed=$true
        $report.status=if ($report.system_errors.Count -eq 0) { 'passed' } else { 'passed-with-system-errors' }
    } else {
        $report.status=if ($report.system_errors.Count -eq 0) { 'prepared' } else { 'prepared-with-system-errors' }
    }
} catch {
    $report.status='failed'
    $report.error=$_.Exception.Message
    Write-Host "v0.14 Windows QA failed: $($report.error)"
} finally {
    $sourceUnchanged=$true
    foreach ($entry in $manifest) {
        try { if ((Get-FileHash -LiteralPath (Join-Path $repoRoot $entry.path) -Algorithm SHA256).Hash -cne $entry.sha256) { $sourceUnchanged=$false } }
        catch { $sourceUnchanged=$false }
    }
    $report.source_resources_unchanged=$sourceUnchanged
    if (-not $sourceUnchanged) { $report.status='failed';$report.error='Source files changed during validation.' }
    $runtimeUnchanged=$true
    foreach ($entry in $runtimeManifest) {
        try { if ((Get-FileHash -LiteralPath $entry.source -Algorithm SHA256).Hash -cne $entry.sha256) { $runtimeUnchanged=$false } }
        catch { $runtimeUnchanged=$false }
    }
    $report.source_runtime_unchanged=$runtimeUnchanged
    if (-not $runtimeUnchanged) { $report.status='failed';$report.error='Original Godot runtime changed during validation.' }
    $unchanged=$true
    foreach ($entry in $environmentBefore.GetEnumerator()) {
        if ([Environment]::GetEnvironmentVariable($entry.Key,'Process') -cne $entry.Value) { $unchanged=$false }
    }
    $report.parent_environment_unchanged=$unchanged
    if (-not $unchanged) { $report.status='failed';$report.error='Caller environment changed during validation.' }
    $report.strict_log_clean=@($steps | Where-Object { $_.system_errors.Count -gt 0 -or $_.engine_errors.Count -gt 0 }).Count -eq 0
    $report.runner_exit_code=if ($report.status -eq 'failed') { 1 } elseif ($StrictLogs -and -not $report.strict_log_clean) { 3 } else { 0 }
    $report.finished_at_utc=[DateTime]::UtcNow.ToString('o')
    Write-Report
    Write-Host "Report retained: $reportPath"
}
if ($report.status -eq 'failed') { exit 1 }
if ($StrictLogs -and -not $report.strict_log_clean) {
    Write-Host 'Functional result is preserved, but StrictLogs rejects the retained Windows certificate-store error.'
    exit 3
}
Write-Host "v0.14 Windows QA $($report.status): $($report.checks) checks; strict log clean=$($report.strict_log_clean)."
exit 0
