#requires -Version 7.0
<#
.SYNOPSIS
Collects an offline Windows Godot certificate-startup comparison.
.DESCRIPTION
Uses an existing official Godot 4.6.3 executable and fresh disposable projects.
Preserves separate stdout/stderr files and actual exit codes. Any ERROR keeps
the final strict result failed, even if collection and project model execution
complete successfully. Does not run the editor, save tests, game, or networking.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotBin,
    [string]$SandboxParent = [IO.Path]::GetTempPath(),
    [ValidateRange(5, 60)][int]$TimeoutSeconds = 30
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This diagnostic requires Windows.' }
$utf8 = [Text.UTF8Encoding]::new($false)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))

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
function Assert-Inside([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd([char]92, [char]47) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escaped diagnostic root: $full" }
    Assert-NoReparse $full
    return $full
}
function Write-Utf8([string]$Path, [string]$Value) { [IO.File]::WriteAllText($Path, $Value, $utf8) }

Assert-NoReparse $repoRoot
$resolvedGodot = (Get-Item -LiteralPath $GodotBin -Force).FullName
Assert-NoReparse $resolvedGodot
if ([IO.Path]::GetExtension($resolvedGodot) -ine '.exe') { throw 'GodotBin must be an existing executable path.' }
$parentRoot = [IO.Path]::GetFullPath($SandboxParent)
Assert-NoReparse $parentRoot
$sandboxRoot = Join-Path $parentRoot ('godot-certificate-qa-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $sandboxRoot) { throw 'Refusing to reuse a diagnostic sandbox.' }
[void][IO.Directory]::CreateDirectory($sandboxRoot)
$logRoot = Assert-Inside (Join-Path $sandboxRoot 'logs') $sandboxRoot
[void][IO.Directory]::CreateDirectory($logRoot)
$reportPath = Join-Path $sandboxRoot 'report.json'
$environmentBefore = @{}
foreach ($name in @('HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP')) {
    $environmentBefore[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$steps = [Collections.Generic.List[object]]::new()
$manifest = [Collections.Generic.List[object]]::new()
$report = [ordered]@{
    schema = 1
    started_at_utc = [DateTime]::UtcNow.ToString('o')
    identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    sandbox = $sandboxRoot
    godot_binary = $resolvedGodot
    godot_sha256 = (Get-FileHash -LiteralPath $resolvedGodot -Algorithm SHA256).Hash
    version = $null
    diagnostic_completed = $false
    strict_log_clean = $false
    parent_environment_unchanged = $false
    source_resources_unchanged = $false
    native_audit = $null
    error = $null
    steps = $steps
    copied_resources = $manifest
}
function Write-Report { Write-Utf8 $reportPath ($report | ConvertTo-Json -Depth 16) }

function Copy-Resource([string]$Relative, [string]$DestinationRoot) {
    $source = Assert-Inside (Join-Path $repoRoot $Relative) $repoRoot
    $destination = Assert-Inside (Join-Path $DestinationRoot $Relative) $DestinationRoot
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    [IO.File]::Copy($source, $destination, $false)
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -cne $hash) { throw "Copy changed: $Relative" }
    $manifest.Add(@{ path = $Relative; sha256 = $hash })
}
function Copy-Model([string]$DestinationRoot) {
    $queue = [Collections.Generic.Queue[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $queue.Enqueue('scripts/build_state.gd')
    while ($queue.Count -gt 0) {
        $relative = $queue.Dequeue()
        if (-not $seen.Add($relative)) { continue }
        Copy-Resource $relative $DestinationRoot
        $source = Join-Path $repoRoot $relative
        if ([IO.Path]::GetExtension($source) -eq '.gd') {
            if (Test-Path -LiteralPath ($source + '.uid')) { Copy-Resource ($relative + '.uid') $DestinationRoot }
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($source, $utf8), 'res://([^"''\r\n]+)')) {
                $dependency = $match.Groups[1].Value
                if ($dependency.Contains(':') -or $dependency -match '(^|[\\/])\.\.([\\/]|$)') { throw "Escaping dependency: $dependency" }
                $queue.Enqueue($dependency)
            }
        }
    }
}
function New-Case([string]$Name, [switch]$ProjectConfig) {
    $caseRoot = Assert-Inside (Join-Path $sandboxRoot $Name) $sandboxRoot
    $project = Join-Path $caseRoot 'project'
    $roaming = Join-Path $caseRoot 'roaming'
    $userdata = Join-Path $roaming 'certificate-userdata'
    $local = Join-Path $caseRoot 'local'
    $temp = Join-Path $caseRoot 'temp'
    foreach ($path in @($project, $roaming, $userdata, $local, $temp)) {
        $null = Assert-Inside $path $sandboxRoot
        [void][IO.Directory]::CreateDirectory($path)
    }
    if ($ProjectConfig) {
        Copy-Resource 'project.godot' $project
        $configText = [IO.File]::ReadAllText((Join-Path $project 'project.godot'), $utf8)
    } else {
        $configText = 'config_version=5' + "`n[application]`nconfig/name=`"Certificate Empty`"`nrun/main_scene=`"res://empty.tscn`"`n"
        Write-Utf8 (Join-Path $project 'empty.tscn') "[gd_scene format=3]`n`n[node name=`"Empty`" type=`"Node`"]`n"
    }
    # Change only disposable userdata destinations; retain TLS and logging settings.
    $configText += "`n[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"certificate-userdata`"`n"
    Write-Utf8 (Join-Path $project 'project.godot') $configText
    Copy-Resource 'tests/windows/certificate_probe.gd' $project
    return @{ project = $project; userdata = $userdata; roaming = $roaming; local = $local; temp = $temp }
}
function Invoke-Captured([string]$Name, [string]$Executable, [string[]]$Arguments, [hashtable]$Case, [string]$Mode = 'bootstrap') {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.WorkingDirectory = $Case.project
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    foreach ($entry in @{
        APPDATA = $Case.roaming; LOCALAPPDATA = $Case.local; TEMP = $Case.temp; TMP = $Case.temp
        GODOT_CERTIFICATE_ROOT = $sandboxRoot; GODOT_CERTIFICATE_PROJECT = $Case.project
        GODOT_CERTIFICATE_USERDATA = $Case.userdata; GODOT_CERTIFICATE_MODE = $Mode
    }.GetEnumerator()) { $info.Environment[$entry.Key] = $entry.Value }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    try {
        if (-not $process.Start()) { throw "Could not start $Name" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $timedOut = $true; $process.Kill($true) }
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $outPath = Join-Path $logRoot ($Name + '.stdout.txt')
        $errPath = Join-Path $logRoot ($Name + '.stderr.txt')
        Write-Utf8 $outPath $stdout
        Write-Utf8 $errPath $stderr
        $step = [ordered]@{
            name = $Name; executable = $Executable; arguments = $Arguments; mode = $Mode
            exit_code = $process.ExitCode; timed_out = $timedOut; elapsed_ms = $watch.ElapsedMilliseconds
            stdout_path = $outPath; stderr_path = $errPath
            stdout_sha256 = (Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash
            stderr_sha256 = (Get-FileHash -LiteralPath $errPath -Algorithm SHA256).Hash
            error_lines = @([regex]::Matches($stdout + "`n" + $stderr, '(?m)^[\t ]*(?:ERROR:|SCRIPT ERROR:|Parse Error:)[^\r\n]*') | ForEach-Object { $_.Value })
            probe = $null; model = $null
        }
        $steps.Add($step)
        Write-Report
        if ($timedOut) { throw "$Name timed out; logs retained." }
        return @{ step = $step; stdout = $stdout; stderr = $stderr }
    } finally { $process.Dispose() }
}
function Read-Marker($Run, [string]$Marker) {
    $lines = @($Run.stdout -split '[\r\n]+' | Where-Object { $_.StartsWith($Marker, [StringComparison]::Ordinal) })
    if ($lines.Count -ne 1) { throw "Expected one $Marker marker in $($Run.step.name)." }
    return $lines[0].Substring($Marker.Length) | ConvertFrom-Json
}
function Invoke-Probe([string]$Name, [hashtable]$Case, [string]$Mode = 'bootstrap') {
    $run = Invoke-Captured $Name $resolvedGodot @('--headless', '--verbose', '--path', $Case.project, '--script', 'res://tests/windows/certificate_probe.gd') $Case $Mode
    $probe = Read-Marker $run 'CERTIFICATE_PROBE '
    $run.step.probe = $probe
    $null = Assert-Inside $probe.project $sandboxRoot
    $null = Assert-Inside $probe.user_data_dir $sandboxRoot
    if (-not $probe.isolated -or [IO.Path]::GetFullPath($probe.project) -ine $Case.project -or
        [IO.Path]::GetFullPath($probe.user_data_dir) -ine $Case.userdata -or $run.step.exit_code -ne 0) {
        throw "Isolation or execution failed: $Name"
    }
    if ($Mode -eq 'model') { $run.step.model = Read-Marker $run 'CERTIFICATE_MODEL ' }
    Write-Report
}

Write-Host "Certificate diagnostic sandbox: $sandboxRoot"
Write-Report
try {
    $empty = New-Case 'empty'
    $audit = Invoke-Captured '01-readonly-store' (Join-Path $PSHOME 'pwsh.exe') @('-NoLogo', '-NoProfile', '-File', (Join-Path $PSScriptRoot 'certificate_store_probe.ps1')) $empty
    $report.native_audit = Read-Marker $audit 'CERTIFICATE_STORE '
    if ($audit.step.exit_code -ne 0) { throw 'Read-only audit failed.' }
    $version = Invoke-Captured '02-version' $resolvedGodot @('--headless', '--path', $empty.project, '--version') $empty
    $report.version = $version.stdout.Trim()
    if ($version.step.exit_code -ne 0 -or $report.version -notmatch '^4\.6\.3\.stable\.official\.') { throw 'Expected existing official Godot 4.6.3.' }
    Invoke-Probe '03-empty-probe' $empty
    # Same isolated settings and environment, now no GDScript or project code.
    $scene = Invoke-Captured '04-empty-scene' $resolvedGodot @('--headless', '--verbose', '--path', $empty.project, '--quit') $empty
    if ($scene.step.exit_code -ne 0) { throw 'Empty scene startup did not exit successfully.' }
    $alternate = New-Case 'alternate-profile'
    Invoke-Probe '05-alternate-appdata' $alternate
    $project = New-Case 'project-config' -ProjectConfig
    Invoke-Probe '06-project-config' $project
    Copy-Model $project.project
    Invoke-Probe '07-project-model' $project 'model'
    $report.diagnostic_completed = $true
} catch { $report.error = $_.Exception.Message }
finally {
    $sourceUnchanged = $true
    foreach ($entry in $manifest) {
        try {
            if ((Get-FileHash -LiteralPath (Join-Path $repoRoot $entry.path) -Algorithm SHA256).Hash -cne $entry.sha256) { $sourceUnchanged = $false }
        } catch { $sourceUnchanged = $false }
    }
    $report.source_resources_unchanged = $sourceUnchanged
    $report.parent_environment_unchanged = $true
    foreach ($entry in $environmentBefore.GetEnumerator()) {
        if ([Environment]::GetEnvironmentVariable($entry.Key, 'Process') -cne $entry.Value) { $report.parent_environment_unchanged = $false }
    }
    $report.strict_log_clean = @($steps | Where-Object { $_.error_lines.Count -gt 0 -or $_.exit_code -ne 0 -or $_.timed_out }).Count -eq 0
    $report.finished_at_utc = [DateTime]::UtcNow.ToString('o')
    Write-Report
    Write-Host "Report retained: $reportPath"
    Write-Host "Collection completed: $($report.diagnostic_completed); strict logs clean: $($report.strict_log_clean)"
    if ($report.error) { Write-Host $report.error }
}
if (-not $report.diagnostic_completed -or -not $report.strict_log_clean -or
    -not $report.source_resources_unchanged -or -not $report.parent_environment_unchanged) { exit 1 }
exit 0
