#requires -Version 7.0
<#+
Harmless runner contract tests. Compiles only export_smoke_fixture.cs locally.
No Godot game/template/archive is downloaded or executed. Evidence stays in TEMP.
#>
[CmdletBinding()]
param([string]$EvidenceParent = [IO.Path]::GetTempPath())

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'These tests require Windows Job Object semantics.' }
$runner = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\tools\windows\smoke_export.ps1'))
. $runner
Initialize-SmokeNative
$testRoot = New-SmokeSandbox $EvidenceParent
$fixtureFolder = Join-Path $testRoot "product\���� fixtures with spaces and 'quote'"
[void][IO.Directory]::CreateDirectory($fixtureFolder)
$fixture = Join-Path $fixtureFolder 'export smoke fixture.exe'
$compiler = Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The local .NET Framework C# compiler is required; no install attempted.' }
& $compiler /nologo /target:exe ("/out:" + $fixture) (Join-Path $PSScriptRoot 'export_smoke_fixture.cs')
if ($LASTEXITCODE -ne 0) { throw 'Harmless fixture compilation failed.' }
Add-Type -Path (Join-Path $PSScriptRoot 'export_smoke_fixture.cs')
$checks = [Collections.Generic.List[object]]::new()
$before = @{}
foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'HOME', 'USERPROFILE', 'TEMP', 'TMP')) { $before[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

function Check([string]$Name, [bool]$Condition) {
    $checks.Add(@{ name = $Name; passed = $Condition })
    if (-not $Condition) { throw "Check failed: $Name" }
}

function Expect-Refusal([string]$Name, [scriptblock]$Action) {
    $refused = $false
    try { & $Action | Out-Null } catch { $refused = $true }
    Check $Name $refused
}

function Invoke-Fixture([string]$Name, [string[]]$Arguments, [int]$Timeout = 5000) {
    $sandbox = New-SmokeSandbox $testRoot
    $environment = Get-SmokeChildEnvironment $sandbox
    $stdout = Join-Path $sandbox 'logs\stdout.log'
    $stderr = Join-Path $sandbox 'logs\stderr.log'
    $run = [ExportSmoke.Native]::Run($fixture, $Arguments, $fixtureFolder, $environment, $stdout, $stderr, $Timeout)
    [IO.File]::WriteAllText((Join-Path $sandbox 'owned-process.json'), ($run | ConvertTo-Json -Depth 4), $script:SmokeUtf8)
    Check ($Name + ': no native error') (-not $run.Error -and -not $run.CleanupError)
    Check ($Name + ': root resumed inside job') $run.Resumed
    Check ($Name + ': owned job emptied') ($run.ActiveAfterCleanup -eq 0)
    return @{ root = $sandbox; run = $run; stdout = $stdout; stderr = $stderr }
}

function Get-VariantString([string]$Value) {
    $encoded = $script:SmokeUtf8.GetBytes($Value)
    $bytes = [byte[]]::new(8 + $encoded.Length + ((4 - $encoded.Length % 4) % 4))
    [BitConverter]::GetBytes([uint32]4).CopyTo($bytes, 0)
    [BitConverter]::GetBytes([uint32]$encoded.Length).CopyTo($bytes, 4)
    $encoded.CopyTo($bytes, 8)
    return ,$bytes
}

function Get-SettingsFixture {
    return @{
        'application/config/name' = Get-VariantString 'godot��Ϸ��'
        'application/config/version' = Get-VariantString '0.14.0'
    }
}

function New-PackedSettingsFixture($Settings) {
    # Construct a synthetic PCK in memory, never a game executable or real save.
    $ecfg = [IO.MemoryStream]::new()
    $w = [IO.BinaryWriter]::new($ecfg)
    $w.Write([uint32]0x47464345); $w.Write([uint32]$Settings.Count)
    foreach ($key in $Settings.Keys) {
        $encoded = $script:SmokeUtf8.GetBytes($key)
        $w.Write([uint32]$encoded.Length); $w.Write($encoded)
        $w.Write([uint32]$Settings[$key].Length); $w.Write([byte[]]$Settings[$key])
    }
    $settingsBytes = $ecfg.ToArray(); $w.Dispose(); $ecfg.Dispose()
    $data = [IO.MemoryStream]::new(); $w = [IO.BinaryWriter]::new($data)
    $w.Write([uint32]0x43504447); $w.Write([uint32]3)
    $w.Write([uint32]4); $w.Write([uint32]6); $w.Write([uint32]3); $w.Write([uint32]2)
    $w.Write([uint64]104); $w.Write([uint64](104 + $settingsBytes.Length))
    $w.Write([byte[]]::new(64)); $w.Write($settingsBytes)
    $w.Write([uint32]1)
    $path = $script:SmokeUtf8.GetBytes('res://project.binary')
    $w.Write([uint32]$path.Length); $w.Write($path)
    $w.Write([uint64]0); $w.Write([uint64]$settingsBytes.Length)
    $w.Write([Security.Cryptography.MD5]::HashData($settingsBytes)); $w.Write([uint32]0)
    $w.Write([uint64]$data.Length); $w.Write([uint32]0x43504447)
    $bytes = $data.ToArray(); $w.Dispose(); $data.Dispose()
    return ,$bytes
}

$unrelated = $null
$testError = $null
try {
    $arguments = @('echo', 'space and ����', "apostrophe's", 'literal "double quote"', 'C:\trailing space\', '', '$(not-executed); & | %PATH%', "line`nbreak")
    $echo = Invoke-Fixture 'literal arguments' $arguments
    Check 'zero exit preserved' ($echo.run.ExitCode -eq 0 -and -not $echo.run.TimedOut)
    Check 'normal exit leaves no live owned helper after grace' ($echo.run.ActiveAfterRootExit -eq 0 -and -not $echo.run.TerminatedJob)
    $received = @([IO.File]::ReadAllLines($echo.stdout) | Where-Object { $_.StartsWith('FIXTURE_ARG:') } | ForEach-Object { $script:SmokeUtf8.GetString([Convert]::FromBase64String($_.Substring(12))) })
    Check 'all argument boundaries round-trip' ($received.Count -eq $arguments.Count)
    for ($i = 0; $i -lt $arguments.Count; $i++) { Check ("argument $i exact") ($received[$i] -ceq $arguments[$i]) }
    Check 'stderr retained separately' ([IO.File]::ReadAllText($echo.stderr).Contains('FIXTURE_STDERR:kept raw'))
    Check 'child APPDATA resolves inside fresh sandbox' (Test-Path -LiteralPath (Join-Path $echo.root 'roaming\Godot\app_userdata\Fixture data\fixture.txt'))
    $nonzero = Invoke-Fixture 'nonzero exit' @('exit7')
    Check 'exit code 7 is not normalized to success' ($nonzero.run.ExitCode -eq 7)
    $bulk = Invoke-Fixture 'bulk logs' @('bulk')
    Check 'large stdout and stderr do not deadlock or truncate' ((Get-Item -LiteralPath $bulk.stdout).Length -gt 262144 -and (Get-Item -LiteralPath $bulk.stderr).Length -gt 262144)
    $errors = Invoke-Fixture 'strict errors' @('errors')
    $issues = @(Get-SmokeLogErrors @($errors.stdout, $errors.stderr))
    Check 'certificate and script errors remain blocking' ($issues.Count -eq 2)
    Check 'certificate error text preserved verbatim' (@($issues | Where-Object text -CEQ 'ERROR: Failed to read the root certificate store.').Count -eq 1)
    $coloredLog = Join-Path $errors.root 'logs\colored-fixture.log'
    $coloredError = "$([char]27)[31mERROR$([char]27)[0m: certificate fixture sentinel"
    [IO.File]::WriteAllText($coloredLog, $coloredError, $script:SmokeUtf8)
    $coloredIssues = @(Get-SmokeLogErrors @($coloredLog))
    Check 'ANSI color cannot hide an error' ($coloredIssues.Count -eq 1 -and $coloredIssues[0].text -ceq $coloredError)

    $sentinelRoot = New-SmokeSandbox $testRoot
    $psi = [Diagnostics.ProcessStartInfo]::new($fixture)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.ArgumentList.Add('child')
    $environment = Get-SmokeChildEnvironment $sentinelRoot
    foreach ($key in $environment.Keys) { $psi.Environment[$key] = $environment[$key] }
    $unrelated = [Diagnostics.Process]::Start($psi)
    Check 'own unrelated fixture starts' (-not $unrelated.HasExited)
    $timeout = Invoke-Fixture 'timeout tree' @('timeout') 4000
    Check 'timeout is recorded' ($timeout.run.TimedOut -and $timeout.run.TerminatedJob)
    $childPid = [int][IO.File]::ReadAllText((Join-Path $timeout.root 'child-pid.txt'))
    Check 'timeout root belongs to owned job' ($timeout.run.PidsBeforeCleanup -contains $timeout.run.RootPid)
    Check 'timeout child belongs to owned job' ($timeout.run.PidsBeforeCleanup -contains $childPid)
    Check 'timed-out child is gone' ($null -eq (Get-Process -Id $childPid -ErrorAction SilentlyContinue))
    Check 'unrelated fixture survives timeout cleanup' (-not $unrelated.HasExited)
    $orphan = Invoke-Fixture 'early parent exit' @('orphan')
    Check 'parent exit zero preserves surviving-child failure evidence' ($orphan.run.ExitCode -eq 0 -and $orphan.run.ActiveAfterRootExit -gt 0 -and $orphan.run.TerminatedJob)
    $childPid = [int][IO.File]::ReadAllText((Join-Path $orphan.root 'child-pid.txt'))
    Check 'orphan child belongs to same job' ($orphan.run.PidsBeforeCleanup -contains $childPid)
    Check 'orphan child is gone' ($null -eq (Get-Process -Id $childPid -ErrorAction SilentlyContinue))
    Check 'unrelated fixture survives orphan cleanup' (-not $unrelated.HasExited)

    $settings = Get-SettingsFixture
    $packed = Get-SmokePackedSettings (New-PackedSettingsFixture $settings)
    Check 'settings are read from packed ECFG bytes' ((Get-SmokeUserDataRelative $packed.settings) -ceq 'Godot\app_userdata\godot��Ϸ��')
    $settings['application/config/version'] = Get-VariantString '0.13.0'
    Expect-Refusal 'old v0.13 export refused by packed version gate' { Get-SmokeUserDataRelative $settings }
    $settings = Get-SettingsFixture
    $settings['application/config/name.windows'] = Get-VariantString 'another name'
    Expect-Refusal 'feature-specific data path refused' { Get-SmokeUserDataRelative $settings }
    $settings = Get-SettingsFixture
    $settings['application/config/project_settings_override'] = Get-VariantString 'C:/external.cfg'
    Expect-Refusal 'external settings override refused' { Get-SmokeUserDataRelative $settings }
    $settings = Get-SettingsFixture
    $settings['application/config/use_custom_user_dir'] = [byte[]](1,0,0,0,1,0,0,0)
    $settings['application/config/custom_user_dir_name'] = Get-VariantString '../real-save'
    Expect-Refusal 'custom directory traversal refused' { Get-SmokeUserDataRelative $settings }
    $settings['application/config/custom_user_dir_name'] = Get-VariantString 'C:/real-save'
    Expect-Refusal 'absolute custom directory refused' { Get-SmokeUserDataRelative $settings }
    $settings['application/config/custom_user_dir_name'] = Get-VariantString 'Studio/Fixture data'
    Check 'canonical relative custom directory supported' ((Get-SmokeUserDataRelative $settings) -ceq 'Studio\Fixture data')
    $bytes = New-PackedSettingsFixture (Get-SettingsFixture)
    $bytes[20] = 3
    Expect-Refusal 'encrypted PCK directory refused' { Get-SmokePackedSettings $bytes }
    Expect-Refusal 'truncated PCK refused' { Get-SmokePackedSettings ([byte[]](1,2,3)) }
    Expect-Refusal 'unrelated PE cannot claim official template identity' { Assert-SmokeTemplate ([IO.File]::ReadAllBytes($fixture)) ([IO.File]::ReadAllBytes($fixture)) }
    $templateFixture = [ExportSmokeFixture]::PeFixture($false, $false, $false)
    $exportFixture = [ExportSmokeFixture]::PeFixture($true, $false, $false)
    Check 'read-only PE comparison accepts only known exporter header changes' (Assert-SmokeTemplate $exportFixture $templateFixture).full_engine_bytes_verified
    Expect-Refusal 'different code byte blocks isolation proof' { Assert-SmokeTemplate ([ExportSmokeFixture]::PeFixture($true, $true, $false)) $templateFixture }
    Expect-Refusal 'different PE permission blocks isolation proof' { Assert-SmokeTemplate ([ExportSmokeFixture]::PeFixture($true, $false, $true)) $templateFixture }
    Expect-Refusal 'path escape refused' { Assert-SmokeInside (Join-Path $testRoot '..\escape') $testRoot }
    $missingRoot = New-SmokeSandbox $testRoot
    $missingRun = [ExportSmoke.Native]::Run((Join-Path $missingRoot 'product\does-not-exist.exe'), [string[]]@(), (Join-Path $missingRoot 'product'), (Get-SmokeChildEnvironment $missingRoot), (Join-Path $missingRoot 'logs\stdout.log'), (Join-Path $missingRoot 'logs\stderr.log'), 1000)
    Check 'OS launch refusal is returned without a started process' (-not $missingRun.Created -and -not $missingRun.Resumed -and $missingRun.Error -and -not $missingRun.CleanupError -and $missingRun.ActiveAfterCleanup -eq 0)

    # Exercise the actual CLI gate with a harmless EXE and no isolation evidence.
    $cli = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $cli.UseShellExecute = $false; $cli.CreateNoWindow = $true
    $cli.RedirectStandardOutput = $true; $cli.RedirectStandardError = $true
    foreach ($value in @('-NoProfile', '-NonInteractive', '-File', $runner, '-Executable', $fixture, '-ExpectedSha256', (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash, '-ArtifactUrl', 'https://example.invalid/fixture-not-a-game', '-SandboxParent', $testRoot)) { $cli.ArgumentList.Add($value) }
    $process = [Diagnostics.Process]::Start($cli)
    try {
        $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) { $process.Kill($true); throw 'CLI gate fixture timed out.' }
        $output = $outTask.GetAwaiter().GetResult(); $cliError = $errTask.GetAwaiter().GetResult()
        Check 'missing template proof exits 78' ($process.ExitCode -eq 78)
        $refusedReport = ($output -split '\r?\n' | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
        Check 'no product process starts without isolation proof' (-not $refusedReport.process_started -and $null -eq $refusedReport.process -and -not $refusedReport.isolation_verified)
        Check 'specific isolation refusal is recorded' ($refusedReport.refusal_reason.Contains('original official 4.6.3 templates TPZ'))
        Check 'refusal does not claim a product pass' (-not $refusedReport.product_smoke_passed -and $refusedReport.status -eq 'refused')
        Check 'refusal retains parent environment and input bytes' ($refusedReport.parent_environment_unchanged -and $refusedReport.input_unchanged)
        Check 'refusal produces no product logs' (@(Get-ChildItem -LiteralPath (Join-Path $refusedReport.sandbox 'logs') -File).Count -eq 0)
        Check 'CLI gate produces no PowerShell errors' ([string]::IsNullOrWhiteSpace($cliError))
    } finally { $process.Dispose() }
    Set-Content -LiteralPath ($fixture + ':Zone.Identifier') -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ascii
    Expect-Refusal 'Mark-of-the-Web is refused without bypass' { Assert-SmokeSecurityMark $fixture }
    Check 'security mark retained' ((Get-Content -LiteralPath ($fixture + ':Zone.Identifier') -Raw).Contains('ZoneId=3'))
} catch { $testError = $_.Exception.Message }
finally {
    if ($unrelated) {
        # Only the process object created by this test; never names or shared PIDs.
        if (-not $unrelated.HasExited) { $unrelated.Kill(); [void]$unrelated.WaitForExit(5000) }
        $unrelated.Dispose()
    }
    foreach ($name in $before.Keys) { Check ("parent $name unchanged") ($before[$name] -ceq [Environment]::GetEnvironmentVariable($name, 'Process')) }
    $report = @{ schema = 1; kind = 'harmless fixtures only'; product_executed = $false; godot_isolation_runtime_proved = $false; tests = $checks.ToArray(); checks = $checks.Count; failures = @($checks | Where-Object passed -EQ $false).Count; error = $testError; evidence = $testRoot; at_utc = [DateTime]::UtcNow.ToString('o') }
    [IO.File]::WriteAllText((Join-Path $testRoot 'fixture-report.json'), ($report | ConvertTo-Json -Depth 8), $script:SmokeUtf8)
}
Write-Output ($report | ConvertTo-Json -Depth 8 -Compress)
if ($testError) { throw $testError }
