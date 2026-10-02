#Requires -Version 5.1
<#
.SYNOPSIS
用人工小 ZIP 测试只读发布验证器；只启动 Windows PowerShell/pwsh，不启动包内程序。
#>
[CmdletBinding()]
param(
    [string]$PowerShellPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'),
    [string]$VerifierPath = ''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($VerifierPath -eq '') { $VerifierPath = Join-Path $PSScriptRoot '..\..\tools\windows\verify_release.ps1' }
$VerifierPath = (Resolve-Path -LiteralPath $VerifierPath).ProviderPath
$PowerShellPath = (Resolve-Path -LiteralPath $PowerShellPath).ProviderPath
if ([IO.Path]::GetFileName($PowerShellPath) -notmatch '^(?i:powershell|pwsh)\.exe$') { throw '只允许指定 PowerShell 引擎。' }
$enginePolicy = (& $PowerShellPath -NoLogo -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy' | Out-String).Trim()
if ($enginePolicy -in @('Restricted', 'AllSigned')) {
    [ordered]@{ status = 'blocked'; engine = $PowerShellPath; execution_policy = $enginePolicy; reason = '当前策略禁止运行本地未签名测试脚本；未更改策略。' } | ConvertTo-Json
    exit 2
}
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:Results = [Collections.Generic.List[object]]::new()
$script:FixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('godot-release-verifier-tests-' + [Guid]::NewGuid().ToString('N'))
$script:ZipFolder = Join-Path $script:FixtureRoot '人工 中文 空格'
$script:IsolatedAppData = Join-Path $script:FixtureRoot 'isolated-appdata'
$script:IsolatedLocalAppData = Join-Path $script:FixtureRoot 'isolated-localappdata'
$script:EscapeMarker = Join-Path $script:FixtureRoot 'escaped-payload.txt'
$script:ScriptMarker = Join-Path $script:FixtureRoot 'package-script-ran.txt'
foreach ($folder in @($script:ZipFolder, $script:IsolatedAppData, $script:IsolatedLocalAppData)) { [void][IO.Directory]::CreateDirectory($folder) }
$script:SaveSentinel = Join-Path $script:IsolatedAppData 'Godot\app_userdata\verifier-test-only\build_save.json'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:SaveSentinel))
[IO.File]::WriteAllText($script:SaveSentinel, '{"test_only":true,"untouched":"中文"}', $script:Utf8)
$script:SaveHash = (Get-FileHash -LiteralPath $script:SaveSentinel -Algorithm SHA256).Hash
$script:SourceHash = (Get-FileHash -LiteralPath $VerifierPath -Algorithm SHA256).Hash

function Bytes([string]$Text) { return ,$script:Utf8.GetBytes($Text) }
function Hash([byte[]]$Data, [string]$Algorithm = 'SHA256') {
    $hasher = [Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    try { return [BitConverter]::ToString($hasher.ComputeHash($Data)).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
function Put-Bytes([byte[]]$Target, [int]$Offset, [byte[]]$Value) { [Buffer]::BlockCopy($Value, 0, $Target, $Offset, $Value.Length) }

# 自造 ECFG，仅有一个版本 STRING；不使用任何真实存档或运行时生成器。
function New-ProjectBinary([string]$Version = '0.13.0', [switch]$NoVersion) {
    $memory = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($memory)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('ECFG'))
        if ($NoVersion) { $writer.Write([uint32]0) }
        else {
            $writer.Write([uint32]1)
            $key = Bytes 'application/config/version'
            $writer.Write([uint32]$key.Length); $writer.Write($key)
            $value = Bytes $Version
            $padding = (4 - ($value.Length % 4)) % 4
            $writer.Write([uint32](8 + $value.Length + $padding))
            $writer.Write([uint32]4); $writer.Write([uint32]$value.Length); $writer.Write($value)
            $writer.Write([byte[]]::new($padding))
        }
        $writer.Flush()
        return ,$memory.ToArray()
    }
    finally { $writer.Dispose(); $memory.Dispose() }
}

function New-Resources {
    $resources = [Collections.Generic.Dictionary[string, byte[]]]::new([StringComparer]::Ordinal)
    $resources.Add('project.binary', (New-ProjectBinary))
    $resources.Add('data/passive_balance.json', (Bytes '{"fixture":true}'))
    $resources.Add('assets/fonts/test.otf.import', (Bytes ("[remap]`npath=""res://.godot/imported/test.fontdata""`n" + [char]0)))
    $resources.Add('.godot/imported/test.fontdata', (Bytes 'fixture-font'))
    $resources.Add('assets/art/test.png.import', (Bytes ("[remap]`npath=""res://.godot/imported/test.ctex""`n" + [char]0)))
    $resources.Add('.godot/imported/test.ctex', (Bytes 'GST2-fixture-texture'))
    return ,$resources
}

# 人工 PE 头和 PCK v3。其内容不具备可执行程序含义，测试从不启动它。
function New-Exe($Resources = (New-Resources)) {
    $names = [Collections.Generic.Dictionary[string, byte[]]]::new([StringComparer]::Ordinal)
    $directoryEnd = 108
    foreach ($name in $Resources.Keys) {
        $nameBytes = Bytes $name
        $padding = (4 - ($nameBytes.Length % 4)) % 4
        $padded = [byte[]]::new($nameBytes.Length + $padding)
        Put-Bytes $padded 0 $nameBytes
        $names.Add($name, $padded)
        $directoryEnd += 4 + $padded.Length + 36
    }
    $memory = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($memory)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('GDPC'))
        foreach ($number in @(3, 4, 6, 3, 2)) { $writer.Write([uint32]$number) }
        $writer.Write([uint64]$directoryEnd); $writer.Write([uint64]104)
        $writer.Write([byte[]]::new(64)); $writer.Write([uint32]$Resources.Count)
        $offset = [long]0
        foreach ($name in $Resources.Keys) {
            $writer.Write([uint32]$names[$name].Length); $writer.Write($names[$name])
            $writer.Write([uint64]$offset); $writer.Write([uint64]$Resources[$name].Length)
            $md5 = [Security.Cryptography.MD5]::Create()
            try { $writer.Write($md5.ComputeHash($Resources[$name])) } finally { $md5.Dispose() }
            $writer.Write([uint32]0)
            $offset += $Resources[$name].Length
        }
        foreach ($name in $Resources.Keys) { $writer.Write($Resources[$name]) }
        $writer.Flush()
        $pck = $memory.ToArray()
    }
    finally { $writer.Dispose(); $memory.Dispose() }
    $pe = [byte[]]::new(512)
    $pe[0] = 0x4d; $pe[1] = 0x5a
    Put-Bytes $pe 0x3c ([BitConverter]::GetBytes([uint32]128))
    Put-Bytes $pe 128 ([byte[]]@(0x50, 0x45, 0, 0))
    Put-Bytes $pe 132 ([BitConverter]::GetBytes([uint16]0x8664))
    Put-Bytes $pe 134 ([BitConverter]::GetBytes([uint16]1))
    Put-Bytes $pe 148 ([BitConverter]::GetBytes([uint16]240))
    Put-Bytes $pe 152 ([BitConverter]::GetBytes([uint16]0x20b))
    $result = [byte[]]::new($pe.Length + $pck.Length + 12)
    Put-Bytes $result 0 $pe; Put-Bytes $result $pe.Length $pck
    Put-Bytes $result ($result.Length - 12) ([BitConverter]::GetBytes([uint64]$pck.Length))
    Put-Bytes $result ($result.Length - 4) ([Text.Encoding]::ASCII.GetBytes('GDPC'))
    return ,$result
}

function New-Fixture {
    $files = [Collections.Generic.Dictionary[string, byte[]]]::new([StringComparer]::Ordinal)
    $files.Add('GodotGame.exe', (New-Exe))
    $files.Add('GodotEngine-LICENSE.txt', (Bytes 'MIT fixture license'))
    $files.Add('GodotEngine-THIRD-PARTY.txt', (Bytes 'third-party fixture notices'))
    $files.Add('GodotEngine-THIRD-PARTY.json', (Bytes '{"fixture":true}'))
    $files.Add('OFL-NotoSansCJK.txt', (Bytes 'OFL fixture license'))
    $files.Add('docs/reference/catalog.json', (Bytes '{"game_version":"0.13.0"}'))
    $files.Add('docs/reference/art/manifest.json', (Bytes '{"status":"complete","written_images":1,"entries":[{"file":"图标 空格.png"}]}'))
    $files.Add('docs/reference/art/图标 空格.png', [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII='))
    $files.Add('docs/reference/index.html', (Bytes '<!doctype html><meta charset="utf-8"><body id="top"><a href="../notes/中文%20空格.md?x=1">说明</a><a href="pages/中文 空格.html#目标">目标</a><a href="#top">顶部</a><a href="https://example.invalid/citation">只读引用</a><img src="./art/图标 空格.png"><link rel="stylesheet" href="style.css"><script src="reference.js"></script><script>throw new Error("PACKAGE_SCRIPT_MUST_NOT_RUN");</script></body>'))
    $files.Add('docs/reference/pages/中文 空格.html', (Bytes '<meta charset=utf-8><p id="目标">中文</p>'))
    $files.Add('docs/notes/中文 空格.md', (Bytes '# 人工中文文件'))
    $files.Add('docs/reference/style.css', (Bytes 'body { background-image:url("art/图标%20空格.png"); }'))
    $files.Add('docs/reference/reference.js', (Bytes 'throw new Error("PACKAGE_SCRIPT_MUST_NOT_RUN");'))
    $files.Add('do-not-run.ps1', (Bytes ("[IO.File]::WriteAllText('" + $script:ScriptMarker.Replace("'", "''") + "','UNSAFE')")))
    return ,$files
}

function New-TestZip([string]$Path, $Files, [string]$Root = '', $Extra = @(), [scriptblock]$ManifestTransform, [switch]$OmitManifest) {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($name in $Files.Keys) { $lines.Add((Hash $Files[$name]) + '  ' + $name) }
    $manifest = ($lines -join "`n") + "`n"
    if ($null -ne $ManifestTransform) { $manifest = & $ManifestTransform $manifest }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true, $script:Utf8)
    try {
        foreach ($name in $Files.Keys) {
            $entry = $zip.CreateEntry($Root + $name)
            $output = $entry.Open()
            try { $output.Write($Files[$name], 0, $Files[$name].Length) } finally { $output.Dispose() }
        }
        if (-not $OmitManifest) {
            $entry = $zip.CreateEntry($Root + 'SHA256SUMS.txt')
            $output = $entry.Open(); $data = Bytes $manifest
            try { $output.Write($data, 0, $data.Length) } finally { $output.Dispose() }
        }
        foreach ($extraEntry in $Extra) {
            $entry = $zip.CreateEntry($extraEntry.name)
            if ($extraEntry.ContainsKey('attributes')) { $entry.ExternalAttributes = $extraEntry.attributes }
            $output = $entry.Open()
            try { $output.Write($extraEntry.bytes, 0, $extraEntry.bytes.Length) } finally { $output.Dispose() }
        }
    }
    finally { $zip.Dispose(); $stream.Dispose() }
}

function Directory-Snapshot {
    return ((Get-ChildItem -LiteralPath $script:FixtureRoot -Recurse -Force | ForEach-Object { $_.FullName }) -join "`n")
}

function Run-Case([string]$Name, [string]$Zip, [string]$ExpectedCode = '', [string]$ExpectedVersion = 'v0.13.0', [string]$Root = '', [switch]$WrongSha) {
    $beforeHash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash
    $expectedSha = $beforeHash
    if ($WrongSha) { $expectedSha = '0' * 64 }
    $beforeFiles = Directory-Snapshot
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $PowerShellPath
    # 直接启动引擎，Arguments 不交给 shell；这些路径均不含 Windows 非法引号。
    $info.Arguments = ('-NoLogo -NoProfile -NonInteractive -File "{0}" -ZipPath "{1}" -ExpectedSha256 "{2}" -ExpectedVersion "{3}" -PackageRoot "{4}"' -f $VerifierPath, $Zip, $expectedSha, $ExpectedVersion, $Root)
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    # 即使未来有人误加运行逻辑，子进程的 APPDATA 也只指向本轮人工隔离目录。
    $info.EnvironmentVariables['APPDATA'] = $script:IsolatedAppData
    $info.EnvironmentVariables['LOCALAPPDATA'] = $script:IsolatedLocalAppData
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) { $process.Kill(); throw '验证器超过 20 秒 fixture 超时上限。' }
        $report = ConvertFrom-Json -InputObject $stdout.Result -ErrorAction Stop
        if ($ExpectedCode -eq '') {
            if ($process.ExitCode -ne 0 -or $report.status -ne 'passed' -or @($report.issues).Count -ne 0) { throw ('期望通过，实际失败：' + $stdout.Result + $stderr.Result) }
            foreach ($check in $report.checks.PSObject.Properties) { if ($check.Value -ne 'passed') { throw "通过报告中仍有未通过项：$($check.Name)" } }
        }
        else {
            if ($process.ExitCode -ne 1 -or $report.status -ne 'failed' -or $ExpectedCode -notin @($report.issues | ForEach-Object { $_.code })) { throw ('缺少预期错误 ' + $ExpectedCode + '：' + $stdout.Result + $stderr.Result) }
        }
        if ($report.safety.extraction -ne 'none' -or $report.safety.package_code_executed -or $report.safety.game_user_data_accessed -or $report.safety.network_requests -ne 0) { throw '只读安全边界报告异常。' }
        if ($report.checks.zip_structure -eq 'failed' -or $report.checks.zip_sha256 -eq 'failed') {
            if ($report.counts.file_hashes -ne 0 -or $report.checks.pe_x64 -ne 'not_checked') { throw 'ZIP 安全门失败后仍读取了有效负载。' }
        }
        if ((Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash -ne $beforeHash) { throw '输入 ZIP 被修改。' }
        if ((Directory-Snapshot) -cne $beforeFiles) { throw '验证器在 fixture 沙箱中写入了文件或目录。' }
        if ((Get-FileHash -LiteralPath $script:SaveSentinel -Algorithm SHA256).Hash -ne $script:SaveHash) { throw '隔离存档 sentinel 被修改。' }
        if ((Get-FileHash -LiteralPath $VerifierPath -Algorithm SHA256).Hash -ne $script:SourceHash) { throw '验证器源文件被修改。' }
        if ((Test-Path -LiteralPath $script:EscapeMarker) -or (Test-Path -LiteralPath $script:ScriptMarker)) { throw '恶意路径或包内脚本产生了副作用。' }
        $script:Results.Add([pscustomobject]@{ name = $Name; passed = $true; expected_code = $ExpectedCode })
        Write-Host "通过：$Name"
    }
    catch {
        $script:Results.Add([pscustomobject]@{ name = $Name; passed = $false; expected_code = $ExpectedCode; error = $_.Exception.Message })
        Write-Host "失败：$Name — $($_.Exception.Message)"
    }
    finally { if ($process.Id -and -not $process.HasExited) { $process.Kill() }; $process.Dispose() }
}

function Case([string]$Name, $Files, [string]$Code = '', $Extra = @(), [string]$Root = '', [string]$Version = 'v0.13.0', [scriptblock]$ManifestTransform, [switch]$WrongSha, [switch]$OmitManifest) {
    $path = Join-Path $script:ZipFolder (('{0:d3}' -f $script:Results.Count) + '-' + $Name + '.zip')
    New-TestZip -Path $path -Files $Files -Root $Root -Extra $Extra -ManifestTransform $ManifestTransform -OmitManifest:$OmitManifest
    Run-Case -Name $Name -Zip $path -ExpectedCode $Code -ExpectedVersion $Version -Root $Root -WrongSha:$WrongSha
}

Case '合法相对链接与中文空格' (New-Fixture)
Case '明确指定包根目录' (New-Fixture) -Root '发布 中文/'
Case '两段版本规范化' (New-Fixture) -Version 'v0.13'
Case '外层SHA错误' (New-Fixture) -Code 'ZIP_SHA256_MISMATCH' -WrongSha
Case '期望版本不符' (New-Fixture) -Version 'v0.14.0' -Code 'VERSION_RUNTIME_INVALID'
Case '无效期望版本' (New-Fixture) -Version 'latest' -Code 'INPUT_OR_VERIFIER_ERROR'

foreach ($required in @('GodotGame.exe', 'docs/reference/index.html', 'docs/reference/catalog.json', 'docs/reference/art/manifest.json')) {
    $files = New-Fixture; [void]$files.Remove($required)
    Case ('缺必要文件-' + [IO.Path]::GetFileName($required)) $files -Code 'REQUIRED_FILE_MISSING'
}
foreach ($license in @('GodotEngine-LICENSE.txt', 'GodotEngine-THIRD-PARTY.txt', 'GodotEngine-THIRD-PARTY.json', 'OFL-NotoSansCJK.txt')) {
    $files = New-Fixture; [void]$files.Remove($license)
    Case ('缺许可证-' + $license) $files -Code 'LICENSE_MISSING_OR_INVALID'
}
$files = New-Fixture; $files['GodotEngine-LICENSE.txt'] = [byte[]]::new(0)
Case '空许可证' $files -Code 'LICENSE_MISSING_OR_INVALID'
$files = New-Fixture; $files['OFL-NotoSansCJK.txt'] = [byte[]]@(0xc3, 0x28)
Case '损坏UTF8' $files -Code 'TEXT_ENCODING_OR_JSON'
$files = New-Fixture; $files['docs/reference/index.html'] = [Text.Encoding]::Unicode.GetBytes('<meta charset="utf-8">中文')
Case 'UTF16冒充UTF8' $files -Code 'TEXT_ENCODING_OR_JSON'
$files = New-Fixture; $files['docs/reference/catalog.json'] = Bytes '{broken json'
Case '损坏JSON' $files -Code 'TEXT_ENCODING_OR_JSON'
$files = New-Fixture; $files['docs/reference/catalog.json'] = Bytes '{}'
Case '图鉴缺版本' $files -Code 'VERSION_INVALID'
$files = New-Fixture; $files['docs/reference/catalog.json'] = Bytes '{"game_version":"0.12.0"}'
Case '图鉴版本不符' $files -Code 'VERSION_INVALID'
$resources = New-Resources; $resources['project.binary'] = New-ProjectBinary '0.12.0'
$files = New-Fixture; $files['GodotGame.exe'] = New-Exe $resources
Case 'EXE与图鉴版本不一致' $files -Code 'VERSION_RUNTIME_INVALID'
$resources = New-Resources; $resources['project.binary'] = New-ProjectBinary -NoVersion
$files = New-Fixture; $files['GodotGame.exe'] = New-Exe $resources
Case 'EXE项目缺版本' $files -Code 'VERSION_RUNTIME_INVALID'

foreach ($mutation in @(
    @{ name = '缺MZ'; offset = 0; value = [byte[]]@(0) },
    @{ name = '缺PE签名'; offset = 128; value = [byte[]]@(0) },
    @{ name = 'x86机器类型'; offset = 132; value = [BitConverter]::GetBytes([uint16]0x14c) },
    @{ name = 'PE32非x64头'; offset = 152; value = [BitConverter]::GetBytes([uint16]0x10b) },
    @{ name = 'PE越界偏移'; offset = 0x3c; value = [BitConverter]::GetBytes([uint32]4294967294) }
)) {
    $files = New-Fixture; Put-Bytes $files['GodotGame.exe'] $mutation.offset $mutation.value
    Case $mutation.name $files -Code 'PE_INVALID'
}
$files = New-Fixture; $files['GodotGame.exe'] = [byte[]]@(0x4d, 0x5a)
Case '截断EXE' $files -Code 'PE_INVALID'
$files = New-Fixture; $files['GodotGame.exe'][$files['GodotGame.exe'].Length - 13] = 0
Case 'PCK资源MD5损坏' $files -Code 'PCK_INVALID'
$files = New-Fixture; Put-Bytes $files['GodotGame.exe'] 516 ([BitConverter]::GetBytes([uint32]4))
Case '不支持PCK版本' $files -Code 'PCK_INVALID'
$files = New-Fixture; Put-Bytes $files['GodotGame.exe'] 532 ([BitConverter]::GetBytes([uint32]1))
Case '加密PCK目录' $files -Code 'PCK_INVALID'
$resources = New-Resources; [void]$resources.Remove('data/passive_balance.json')
$files = New-Fixture; $files['GodotGame.exe'] = New-Exe $resources
Case 'PCK缺平衡资源' $files -Code 'PCK_INVALID'
$resources = New-Resources; [void]$resources.Remove('.godot/imported/test.ctex')
$files = New-Fixture; $files['GodotGame.exe'] = New-Exe $resources
Case 'PCK缺导入目标' $files -Code 'PCK_INVALID'
$resources = New-Resources; $resources.Add('../unsafe.txt', (Bytes 'unsafe'))
$files = New-Fixture; $files['GodotGame.exe'] = New-Exe $resources
Case 'PCK路径穿越' $files -Code 'PCK_INVALID'

$files = New-Fixture; [void]$files.Remove('docs/reference/art/图标 空格.png')
Case '缺图片' $files -Code 'ART_INVALID'
$files = New-Fixture; $files['docs/reference/art/图标 空格.png'][0] = 0
Case '损坏PNG头' $files -Code 'ART_INVALID'
$files = New-Fixture; $files['docs/reference/index.html'] = Bytes '<meta charset=utf-8><img src="art/图标 空格.png"><a href="#不存在">坏锚点</a>'
Case '缺本页锚点' $files -Code 'REFERENCE_INVALID'
$files = New-Fixture; $files['docs/reference/pages/中文 空格.html'] = Bytes '<meta charset=utf-8><p id="别的目标">中文</p>'
Case '缺跨页锚点' $files -Code 'REFERENCE_INVALID'
$files = New-Fixture; $files['docs/reference/style.css'] = Bytes 'body{background:url(https://example.invalid/image.png)}'
Case 'CSS网络依赖' $files -Code 'REFERENCE_INVALID'
$files = New-Fixture; [void]$files.Remove('docs/reference/reference.js')
Case '缺本地脚本但不执行' $files -Code 'REFERENCE_INVALID'
$files = New-Fixture; $files['docs/reference/style.css'] = Bytes '@import "missing.css";'
Case '缺CSS导入' $files -Code 'REFERENCE_INVALID'
$files = New-Fixture; $files['docs/reference/index.html'] = Bytes '<meta charset=utf-8><img src="art/图标 空格.png"><a href="..%2f..%2f..%2fescaped-payload.txt">穿越</a>'
Case '百分号编码链接穿越' $files -Code 'REFERENCE_INVALID'
$files = New-Fixture; $files['docs/reference/index.html'] = Bytes '<meta charset=utf-8><img src="art/图标 空格.png"><a href="file:///C:/outside.txt">外部文件</a>'
Case '拒绝file协议' $files -Code 'REFERENCE_INVALID'
$files = New-Fixture; $files['docs/reference/index.html'] = Bytes '<meta charset=utf-8><img src="art/图标 空格.png" srcset="missing.png 2x">'
Case 'srcset缺图片' $files -Code 'REFERENCE_INVALID'
$files = New-Fixture; $files['docs/reference/art/extra.png'] = $files['docs/reference/art/图标 空格.png']
Case '图片未纳入清单' $files -Code 'ART_UNLISTED'
$files = New-Fixture; $files['docs/reference/style.css'] = Bytes ''; $files['docs/reference/index.html'] = Bytes '<meta charset=utf-8><p>无图</p>'
Case '清单图片未引用' $files -Code 'ART_INVALID'

foreach ($unsafe in @('../escaped-payload.txt', '..\escaped-payload.txt', '/escaped-payload.txt', 'C:/escaped-payload.txt', '\\server\share\escaped.txt', 'a:stream', 'NUL.txt', 'trailing.', 'trailing ', 'folder//file.txt')) {
    Case ('恶意路径-' + $script:Results.Count) (New-Fixture) -Code 'ZIP_PATH_UNSAFE' -Extra @(@{ name = $unsafe; bytes = (Bytes 'unsafe') })
}
Case '完全重复文件名' (New-Fixture) -Code 'ZIP_DUPLICATE_NAME' -Extra @(@{ name = 'GodotGame.exe'; bytes = (Bytes 'duplicate') })
Case '仅大小写重复文件名' (New-Fixture) -Code 'ZIP_DUPLICATE_NAME' -Extra @(@{ name = 'godotgame.EXE'; bytes = (Bytes 'duplicate') })
Case '文件与目录冲突' (New-Fixture) -Code 'ZIP_FILE_DIRECTORY_CONFLICT' -Extra @(@{ name = 'docs/reference'; bytes = (Bytes 'file-not-directory') })
Case 'Unicode规范重复' (New-Fixture) -Code 'ZIP_DUPLICATE_NAME' -Extra @(@{ name = 'é.txt'; bytes = (Bytes 'first') }, @{ name = ("e" + [char]0x301 + '.txt'); bytes = (Bytes 'second') })
Case '符号链接条目' (New-Fixture) -Code 'ZIP_SPECIAL_FILE' -Extra @(@{ name = 'symbolic-link'; bytes = (Bytes '../escaped-payload.txt'); attributes = -1577123840 })

Case '文件SHA不符' (New-Fixture) -Code 'FILE_SHA256_MISMATCH' -ManifestTransform { param($value) [regex]::Replace($value, '^[0-9a-f]{64}', ('0' * 64)) }
Case '哈希清单未覆盖文件' (New-Fixture) -Code 'FILE_HASH_UNLISTED' -ManifestTransform { param($value) ($value -split "`n" | Select-Object -Skip 1) -join "`n" }
Case '哈希清单格式错误' (New-Fixture) -Code 'FILE_HASH_MANIFEST' -ManifestTransform { param($value) 'not a checksum manifest' }
Case '哈希清单重复项' (New-Fixture) -Code 'FILE_HASH_DUPLICATE' -ManifestTransform { param($value) $value + ($value -split "`n")[0] + "`n" }
Case '缺哈希清单' (New-Fixture) -Code 'REQUIRED_FILE_MISSING' -OmitManifest

$invalidZip = Join-Path $script:ZipFolder '非ZIP.zip'
[IO.File]::WriteAllBytes($invalidZip, (Bytes 'not a ZIP'))
Run-Case '非ZIP损坏容器' $invalidZip -ExpectedCode 'ZIP_INVALID'
$truncatedZip = Join-Path $script:ZipFolder '截断ZIP.zip'
New-TestZip $truncatedZip (New-Fixture)
$data = [IO.File]::ReadAllBytes($truncatedZip)
[IO.File]::WriteAllBytes($truncatedZip, [byte[]]$data[0..($data.Length - 23)])
Run-Case '截断中央目录' $truncatedZip -ExpectedCode 'ZIP_INVALID'
$oversizedZip = Join-Path $script:ZipFolder '超大声明ZIP.zip'
New-TestZip $oversizedZip (New-Fixture)
$data = [IO.File]::ReadAllBytes($oversizedZip)
$centralOffset = [BitConverter]::ToUInt32($data, $data.Length - 6)
Put-Bytes $data ([int]$centralOffset + 24) ([BitConverter]::GetBytes([uint32](256MB + 1)))
[IO.File]::WriteAllBytes($oversizedZip, $data)
Run-Case '单条目长度上限先于解压' $oversizedZip -ExpectedCode 'ZIP_LIMIT'

$failed = @($script:Results | Where-Object { -not $_.passed })
$summary = [ordered]@{
    total = $script:Results.Count; passed = $script:Results.Count - $failed.Count
    failed = $failed.Count; engine = $PowerShellPath
    fixture_root = $script:FixtureRoot; results = @($script:Results.ToArray())
    package_executed = $false; extraction = 'none'; real_user_data_accessed = $false
}
$summaryPath = Join-Path $script:FixtureRoot 'test-results.json'
[IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 8), $script:Utf8)
Write-Host ("{0}/{1} 通过；人工 fixture 与报告保留在：{2}" -f $summary.passed, $summary.total, $script:FixtureRoot)
if ($failed.Count -gt 0) { exit 1 }
exit 0
