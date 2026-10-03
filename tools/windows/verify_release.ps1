#Requires -Version 5.1
<#
.SYNOPSIS
只读验证 Windows 发布 ZIP；不解压、不启动 EXE、不执行网页脚本。
.EXAMPLE
powershell.exe -NoProfile -File tools/windows/verify_release.ps1 -ZipPath package.zip -ExpectedSha256 <64位SHA256> -ExpectedVersion v0.13.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [string]$PackageRoot = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:Issues = [Collections.Generic.List[object]]::new()
$script:Entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$script:Bytes = [Collections.Generic.Dictionary[string, byte[]]]::new([StringComparer]::OrdinalIgnoreCase)
$script:Texts = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:HtmlDocuments = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:MaxEntryBytes = 256MB
$script:MaxTotalBytes = 512MB
$script:MaxEntries = 10000
$script:MaxTextBytes = 16MB
$script:MaxRatio = 1000
$script:Report = [ordered]@{
    schema_version = 1
    status = 'failed'
    zip = $ZipPath
    expected_sha256 = $ExpectedSha256.ToLowerInvariant()
    actual_sha256 = $null
    expected_version = $ExpectedVersion
    package_root = $PackageRoot
    checks = [ordered]@{
        zip_sha256 = 'not_checked'; zip_structure = 'not_checked'
        file_sha256 = 'not_checked'; text_encoding = 'not_checked'
        pe_x64 = 'not_checked'; embedded_pck = 'not_checked'
        version = 'not_checked'; runtime_version = 'not_checked'; licenses = 'not_checked'
        reference_links = 'not_checked'; reference_art = 'not_checked'
    }
    counts = [ordered]@{
        zip_entries = 0; zip_files = 0; uncompressed_bytes = [long]0
        file_hashes = 0; utf8_files = 0; pck_files = 0; pck_md5 = 0
        pck_imports = 0; html_documents = 0; local_links = 0
        external_citations = 0; png_headers = 0; art_entries = 0
    }
    pe = $null
    pck = $null
    versions = [ordered]@{ catalog = $null; project_binary = $null }
    limits = [ordered]@{
        entries = $script:MaxEntries; entry_bytes = $script:MaxEntryBytes
        total_bytes = $script:MaxTotalBytes; text_bytes = $script:MaxTextBytes
        compression_ratio = $script:MaxRatio
    }
    safety = [ordered]@{
        extraction = 'none'; package_code_executed = $false
        game_user_data_accessed = $false; network_requests = 0
    }
    scope = @(
        '仅验证包内静态字节和声明的 HTML/CSS/图片引用。'
        '不验证 Authenticode、原生 GUI、浏览器交互或 JavaScript 动态生成的依赖。'
        '支持当前项目的 GodotGame.exe 内嵌未加密 PCK v3；其他格式明确失败。'
    )
    issues = @()
}

function Add-Failure([string]$Code, [string]$Path, [string]$Message) {
    $script:Issues.Add([pscustomobject]@{ code = $Code; path = $Path; message = $Message })
}

function Get-Property($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return ,$property.Value }
    return $null
}

function Get-NormalVersion([string]$Value) {
    if ($Value -notmatch '^[vV]?(\d+)\.(\d+)(?:\.(\d+))?$') {
        throw '版本必须是 0.13、0.13.0 或 v0.13.0 这样的数字版本。'
    }
    $patch = '0'
    if ($Matches[3]) { $patch = $Matches[3] }
    return ('{0}.{1}.{2}' -f [uint32]$Matches[1], [uint32]$Matches[2], [uint32]$patch)
}

function Get-SafeName([string]$Name) {
    if ([string]::IsNullOrEmpty($Name) -or $Name.Length -gt 1024) { throw '路径为空或超过 1024 字符。' }
    if ($Name -match '[\\\x00-\x1f\x7f<>:"|?*]' -or $Name.Contains([string][char]0xfffd)) {
        throw '路径含 Windows 非法字符、反斜杠或无法可靠解码的字符。'
    }
    if ($Name.StartsWith('/')) { throw '禁止绝对路径、UNC 或盘符路径。' }
    $trimmed = $Name
    if ($Name.EndsWith('/')) { $trimmed = $Name.Substring(0, $Name.Length - 1) }
    $parts = $trimmed.Split('/')
    if ($parts.Count -gt 64) { throw '路径层级超过 64。' }
    foreach ($part in $parts) {
        if ($part -eq '' -or $part -eq '.' -or $part -eq '..') { throw '禁止空目录段、点段或路径穿越。' }
        if ($part -match '[. ]$') { throw '禁止 Windows 会折叠的末尾点或空格。' }
        if ($part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(?:\.|$)') {
            throw '禁止 Windows 保留设备名。'
        }
    }
    return $trimmed.Normalize([Text.NormalizationForm]::FormC)
}

function Get-PackagePath([string]$Relative) {
    return ($script:RootPrefix + $Relative)
}

function Read-Entry([string]$Name) {
    if ($script:Bytes.ContainsKey($Name)) { return ,$script:Bytes[$Name] }
    if (-not $script:Entries.ContainsKey($Name) -or $script:Entries[$Name].is_directory) {
        throw "ZIP 中缺少文件：$Name"
    }
    $entry = $script:Entries[$Name].entry
    $entryStream = $entry.Open()
    $memory = [IO.MemoryStream]::new()
    try {
        $buffer = [byte[]]::new(65536)
        while (($read = $entryStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $read -gt $entry.Length -or $memory.Length + $read -gt $script:MaxEntryBytes) {
                throw '实际展开字节数超出 ZIP 声明或读取上限。'
            }
            $memory.Write($buffer, 0, $read)
        }
        if ($memory.Length -ne $entry.Length) { throw '实际展开字节数与 ZIP 声明不一致。' }
        $result = $memory.ToArray()
        $script:Bytes.Add($Name, $result)
        return ,$result
    }
    finally { $entryStream.Dispose(); $memory.Dispose() }
}

function Decode-Utf8([byte[]]$Data) {
    $value = $script:Utf8.GetString($Data)
    if ($value.Length -gt 0 -and $value[0] -eq [char]0xfeff) { $value = $value.Substring(1) }
    if ($value.IndexOf([char]0) -ge 0) { throw '文本含 NUL；要求 UTF-8 文本，不能使用 UTF-16。' }
    return $value
}

function Read-Text([string]$Name) {
    if ($script:Texts.ContainsKey($Name)) { return $script:Texts[$Name] }
    if (-not $script:Entries.ContainsKey($Name) -or $script:Entries[$Name].is_directory) { throw "ZIP 中缺少文件：$Name" }
    if ($script:Entries[$Name].entry.Length -gt $script:MaxTextBytes) { throw '文本超过 16 MiB 读取上限。' }
    $value = Decode-Utf8 (Read-Entry $Name)
    $script:Texts.Add($Name, $value)
    return $value
}

function Get-HexHash([byte[]]$Data, [string]$Algorithm) {
    $hasher = [Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    try { return [BitConverter]::ToString($hasher.ComputeHash($Data)).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}

function Test-ArchiveMetadata($Archive) {
    $before = $script:Issues.Count
    if ($Archive.Entries.Count -gt $script:MaxEntries) {
        Add-Failure 'ZIP_LIMIT' '' 'ZIP 条目数超过 10000；停止读取内容。'
        return $false
    }
    $script:Report.counts.zip_entries = $Archive.Entries.Count
    foreach ($entry in $Archive.Entries) {
        $name = $entry.FullName
        try { $safe = Get-SafeName $name }
        catch { Add-Failure 'ZIP_PATH_UNSAFE' $name $_.Exception.Message; continue }
        $directory = $name.EndsWith('/')
        $unixType = ($entry.ExternalAttributes -shr 16) -band 0xf000
        if ($unixType -notin @(0, 0x8000, 0x4000) -or ($entry.ExternalAttributes -band 0x400) -ne 0) {
            Add-Failure 'ZIP_SPECIAL_FILE' $name '禁止符号链接、设备文件或重解析条目。'
        }
        if ($unixType -eq 0x4000 -and -not $directory) {
            Add-Failure 'ZIP_DIRECTORY_TYPE' $name '目录属性与条目路径不一致。'
        }
        if ($script:Entries.ContainsKey($safe)) {
            Add-Failure 'ZIP_DUPLICATE_NAME' $name "路径重复或仅大小写/Unicode 规范形式不同：$($script:Entries[$safe].entry.FullName)"
            continue
        }
        $script:Entries.Add($safe, [pscustomobject]@{ entry = $entry; is_directory = $directory })
        if ($entry.Length -lt 0 -or $entry.Length -gt $script:MaxEntryBytes -or ($directory -and $entry.Length -ne 0)) {
            Add-Failure 'ZIP_LIMIT' $name '单条目过大、长度无效或目录含内容。'
        }
        if (-not $directory) {
            $script:Report.counts.zip_files++
            $script:Report.counts.uncompressed_bytes += $entry.Length
            if ($entry.Length -gt 0 -and ($entry.CompressedLength -le 0 -or $entry.Length / [double]$entry.CompressedLength -gt $script:MaxRatio)) {
                Add-Failure 'ZIP_LIMIT' $name '压缩比例超过 1000 或压缩长度无效。'
            }
        }
    }
    if ($script:Report.counts.uncompressed_bytes -gt $script:MaxTotalBytes) {
        Add-Failure 'ZIP_LIMIT' '' 'ZIP 展开总量超过 512 MiB；停止读取内容。'
    }
    foreach ($name in $script:Entries.Keys) {
        $parent = $name
        while ($parent.Contains('/')) {
            $parent = $parent.Substring(0, $parent.LastIndexOf('/'))
            if ($script:Entries.ContainsKey($parent) -and -not $script:Entries[$parent].is_directory) {
                Add-Failure 'ZIP_FILE_DIRECTORY_CONFLICT' $name "父路径是普通文件：$parent"
                break
            }
        }
    }
    return ($script:Issues.Count -eq $before)
}

function Test-FileHashes {
    $before = $script:Issues.Count
    $manifestName = Get-PackagePath 'SHA256SUMS.txt'
    $hashes = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        foreach ($line in ((Read-Text $manifestName) -split '\r?\n')) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -notmatch '^([0-9a-fA-F]{64}) [ *](.+)$') {
                Add-Failure 'FILE_HASH_MANIFEST' $manifestName 'SHA256SUMS 行格式无效；要求 sha256sum 格式。'
                continue
            }
            $digest = $Matches[1].ToLowerInvariant()
            $relative = $Matches[2]
            try { $safe = Get-SafeName $relative }
            catch { Add-Failure 'FILE_HASH_MANIFEST' $relative $_.Exception.Message; continue }
            $name = Get-PackagePath $safe
            if ($hashes.ContainsKey($name)) { Add-Failure 'FILE_HASH_DUPLICATE' $name 'SHA256SUMS 重复列出文件。'; continue }
            $hashes.Add($name, $digest)
            if (-not $script:Entries.ContainsKey($name) -or $script:Entries[$name].is_directory) {
                Add-Failure 'FILE_HASH_TARGET_MISSING' $name 'SHA256SUMS 所列文件不在 ZIP 中。'
                continue
            }
            try {
                if ((Get-HexHash (Read-Entry $name) 'SHA256') -ne $digest) {
                    Add-Failure 'FILE_SHA256_MISMATCH' $name '文件 SHA256 与 SHA256SUMS 不符。'
                } else { $script:Report.counts.file_hashes++ }
            }
            catch { Add-Failure 'ZIP_ENTRY_READ' $name $_.Exception.Message }
        }
        foreach ($name in $script:Entries.Keys) {
            if (-not $script:Entries[$name].is_directory -and $name -ne $manifestName -and -not $hashes.ContainsKey($name)) {
                Add-Failure 'FILE_HASH_UNLISTED' $name '文件未列入 SHA256SUMS；不能声称所有文件已校验。'
            }
        }
    }
    catch { Add-Failure 'FILE_HASH_MANIFEST' $manifestName $_.Exception.Message }
    $script:Report.checks.file_sha256 = $(if ($before -eq $script:Issues.Count) { 'passed' } else { 'failed' })
}

function Test-TextEncoding {
    $before = $script:Issues.Count
    foreach ($name in $script:Entries.Keys) {
        if ($script:Entries[$name].is_directory -or $name -notmatch '(?i)\.(md|txt|json|html?|css|js|gd|uid|gdignore)$') { continue }
        try {
            $value = Read-Text $name
            $script:Report.counts.utf8_files++
            if ($name -match '(?i)\.json$') { $null = ConvertFrom-Json -InputObject $value -ErrorAction Stop }
        }
        catch { Add-Failure 'TEXT_ENCODING_OR_JSON' $name $_.Exception.Message }
    }
    $script:Report.checks.text_encoding = $(if ($before -eq $script:Issues.Count) { 'passed' } else { 'failed' })
}

function Assert-Range([byte[]]$Data, [long]$Offset, [long]$Length, [long]$End) {
    if ($Offset -lt 0 -or $Length -lt 0 -or $End -gt $Data.LongLength -or $Offset -gt $End -or $Length -gt $End - $Offset) {
        throw '二进制偏移或长度超出容器边界。'
    }
}

function Read-U32([byte[]]$Data, [long]$Offset) {
    Assert-Range $Data $Offset 4 $Data.LongLength
    return [BitConverter]::ToUInt32($Data, [int]$Offset)
}

function Read-U64([byte[]]$Data, [long]$Offset) {
    Assert-Range $Data $Offset 8 $Data.LongLength
    $value = [BitConverter]::ToUInt64($Data, [int]$Offset)
    if ($value -gt [long]::MaxValue) { throw '64 位偏移或长度过大。' }
    return [long]$value
}

# 依据 Godot ProjectSettings ECFG 布局，仅解码版本的 STRING Variant；其余值只跳过字节。
function Read-ProjectVersion([byte[]]$Data, [long]$Start, [long]$Size) {
    $end = $Start + $Size
    Assert-Range $Data $Start 8 $end
    if ((Read-U32 $Data $Start) -ne 0x47464345) { throw 'project.binary 缺少 ECFG 签名。' }
    $count = Read-U32 $Data ($Start + 4)
    if ($count -gt $script:MaxEntries) { throw 'project.binary 设置项数超过上限。' }
    $position = $Start + 8
    $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $version = $null
    for ($index = 0; $index -lt $count; $index++) {
        Assert-Range $Data $position 4 $end
        $keyBytes = Read-U32 $Data $position
        $position += 4
        if ($keyBytes -lt 1 -or $keyBytes -gt 65535) { throw 'project.binary 设置名称长度无效。' }
        Assert-Range $Data $position ($keyBytes + 4) $end
        $key = $script:Utf8.GetString($Data, [int]$position, [int]$keyBytes)
        if ($key.IndexOf([char]0) -ge 0 -or -not $keys.Add($key)) { throw 'project.binary 设置名称含 NUL 或重复。' }
        $position += $keyBytes
        $valueBytes = Read-U32 $Data $position
        $position += 4
        Assert-Range $Data $position $valueBytes $end
        if ($key -ceq 'application/config/version') {
            if ($valueBytes -lt 8 -or (Read-U32 $Data $position) -ne 4) { throw 'application/config/version 不是支持的 STRING Variant。' }
            $stringBytes = Read-U32 $Data ($position + 4)
            if ($stringBytes -gt $valueBytes - 8 -or $valueBytes - 8 - $stringBytes -gt 3) { throw '版本字符串长度或对齐无效。' }
            $version = $script:Utf8.GetString($Data, [int]($position + 8), [int]$stringBytes)
            for ($padding = $position + 8 + $stringBytes; $padding -lt $position + $valueBytes; $padding++) {
                if ($Data[[int]$padding] -ne 0) { throw '版本 STRING 对齐字节不是零。' }
            }
        }
        $position += $valueBytes
    }
    if ($position -ne $end) { throw 'project.binary 含未识别的尾部字节。' }
    if ([string]::IsNullOrEmpty($version)) { throw 'project.binary 缺少 application/config/version；不能推断版本。' }
    return Get-NormalVersion $version
}

function Test-Executable {
    $name = Get-PackagePath 'GodotGame.exe'
    try {
        $data = Read-Entry $name
        Assert-Range $data 0 64 $data.LongLength
        if ($data[0] -ne 0x4d -or $data[1] -ne 0x5a) { throw '缺少 MZ 签名。' }
        $peOffset = [long](Read-U32 $data 0x3c)
        Assert-Range $data $peOffset 24 $data.LongLength
        if ($peOffset -lt 64 -or (Read-U32 $data $peOffset) -ne 0x00004550) { throw '缺少有效 PE\0\0 签名。' }
        $machine = [BitConverter]::ToUInt16($data, [int]($peOffset + 4))
        if ($machine -ne 0x8664) { throw ('PE Machine 为 0x{0:x4}，要求 AMD64 0x8664。' -f $machine) }
        $sections = [BitConverter]::ToUInt16($data, [int]($peOffset + 6))
        $optionalBytes = [BitConverter]::ToUInt16($data, [int]($peOffset + 20))
        if ($sections -lt 1 -or $sections -gt 96 -or $optionalBytes -lt 112) { throw 'PE 节数或可选头长度无效。' }
        Assert-Range $data ($peOffset + 24) ($optionalBytes + 40 * $sections) $data.LongLength
        if ([BitConverter]::ToUInt16($data, [int]($peOffset + 24)) -ne 0x20b) { throw '要求 PE32+ 可选头签名 0x020b。' }
        $script:Report.pe = [ordered]@{ path = $name; machine = '0x8664'; architecture = 'AMD64'; optional_header = 'PE32+'; authenticode = 'not_checked' }
        $script:Report.checks.pe_x64 = 'passed'
    }
    catch { Add-Failure 'PE_INVALID' $name $_.Exception.Message; $script:Report.checks.pe_x64 = 'failed'; return }

    try {
        $end = $data.LongLength - 12
        Assert-Range $data $end 12 $data.LongLength
        if ((Read-U32 $data ($data.LongLength - 4)) -ne 0x43504447) { throw '缺少内嵌 GDPC 尾标记；不猜测外置 PCK。' }
        $packBytes = Read-U64 $data $end
        $pckV3HeaderBytes = [long]104 # 固定字段 40 字节，加上 16 个 32 位保留字段。
        if ($packBytes -lt $pckV3HeaderBytes -or $packBytes -gt $end) { throw '内嵌 PCK 长度无效。' }
        $packStart = $end - $packBytes
        if ((Read-U32 $data $packStart) -ne 0x43504447) { throw '缺少 GDPC 包头签名。' }
        $packVersion = Read-U32 $data ($packStart + 4)
        if ($packVersion -ne 3) { throw "不支持 PCK 版本 $packVersion；当前仅验证 v3。" }
        $packFlags = Read-U32 $data ($packStart + 20)
        if (($packFlags -band 1) -ne 0) { throw '不支持加密 PCK 目录。' }
        $dataBase = Read-U64 $data ($packStart + 24)
        $directoryOffset = Read-U64 $data ($packStart + 32)
        if ($dataBase -gt $packBytes -or $directoryOffset -lt $pckV3HeaderBytes -or $directoryOffset -gt $packBytes - 4) { throw 'PCK 数据或目录基址无效。' }
        $position = $packStart + $directoryOffset
        $fileCount = Read-U32 $data $position
        $position += 4
        if ($fileCount -lt 1 -or $fileCount -gt $script:MaxEntries) { throw 'PCK 文件数量无效。' }
        $packEntries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        $md5 = [Security.Cryptography.MD5]::Create()
        $resourceBytes = [long]0
        try {
            for ($index = 0; $index -lt $fileCount; $index++) {
                Assert-Range $data $position 4 $end
                $nameBytes = Read-U32 $data $position
                $position += 4
                if ($nameBytes -lt 1 -or $nameBytes -gt 65535) { throw 'PCK 路径长度无效。' }
                Assert-Range $data $position ($nameBytes + 36) $end
                $rawName = $script:Utf8.GetString($data, [int]$position, [int]$nameBytes).TrimEnd([char]0)
                $logicalName = $rawName -creplace '^res://', ''
                $logicalName = Get-SafeName $logicalName
                if ($rawName.EndsWith('/') -or $packEntries.ContainsKey($logicalName)) { throw "PCK 目录或重复文件名无效：$rawName" }
                $position += $nameBytes
                $offset = Read-U64 $data $position
                $size = Read-U64 $data ($position + 8)
                if ($size -gt $script:MaxEntryBytes -or $resourceBytes -gt $script:MaxTotalBytes - $size) { throw 'PCK 资源总量超过读取上限。' }
                $resourceBytes += $size
                $expectedMd5 = [BitConverter]::ToString($data, [int]($position + 16), 16).Replace('-', '').ToLowerInvariant()
                $flags = Read-U32 $data ($position + 32)
                $position += 36
                if (($flags -band 1) -ne 0) { throw "不支持加密 PCK 资源：$logicalName" }
                if ($offset -gt $packBytes -or $size -gt $packBytes -or $offset -gt $packBytes - $dataBase) { throw "PCK 资源偏移无效：$logicalName" }
                $start = $packStart + $dataBase + $offset
                Assert-Range $data $start $size $end
                $actualMd5 = [BitConverter]::ToString($md5.ComputeHash($data, [int]$start, [int]$size)).Replace('-', '').ToLowerInvariant()
                if ($actualMd5 -ne $expectedMd5) { throw "PCK 资源 MD5 不符：$logicalName" }
                if ($logicalName -eq 'data/poe_passive_registry.json' -or $logicalName -match '^(data/reference|tests|tools|builds|docs)/') { throw "PCK 包含仅用于开发或研究的资源：$logicalName" }
                $packEntries.Add($logicalName, [pscustomobject]@{ start = $start; size = $size })
                $script:Report.counts.pck_md5++
            }
        }
        finally { $md5.Dispose() }
        foreach ($resource in $packEntries.Values) {
            if ($resource.start -lt $packStart + $pckV3HeaderBytes -or
                ($resource.start -lt $position -and $resource.start + $resource.size -gt $packStart + $directoryOffset)) {
                throw 'PCK 资源与包头或目录表重叠。'
            }
        }
        foreach ($required in @('project.binary', 'data/passive_balance.json')) {
            if (-not $packEntries.ContainsKey($required) -or $packEntries[$required].size -eq 0) { throw "PCK 缺少必要资源：$required" }
        }
        $fontCount = 0
        $textureCount = 0
        foreach ($resourceName in $packEntries.Keys) {
            if ($resourceName -notmatch '\.import$') { continue }
            $resource = $packEntries[$resourceName]
            if ($resource.size -gt $script:MaxTextBytes) { throw "PCK 导入映射文本过大：$resourceName" }
            # Godot 导出的 .import 文本有一个已验证的尾部 NUL 终止符。
            $importText = $script:Utf8.GetString($data, [int]$resource.start, [int]$resource.size)
            if ($importText.EndsWith([string][char]0)) { $importText = $importText.Substring(0, $importText.Length - 1) }
            if ($importText.IndexOf([char]0) -ge 0) { throw "PCK 导入映射不是 UTF-8 文本：$resourceName" }
            $paths = [regex]::Matches($importText, '(?m)^path="res://([^"\r\n]+)"\s*$')
            if ($paths.Count -ne 1) { throw "PCK 导入映射缺少唯一 path：$resourceName" }
            $target = Get-SafeName $paths[0].Groups[1].Value
            if (-not $packEntries.ContainsKey($target) -or $packEntries[$target].size -eq 0) { throw "PCK 导入映射目标缺失：$resourceName -> $target" }
            if ($resourceName -match '(?i)\.(otf|ttf)\.import$' -and $target -match '\.fontdata$') { $fontCount++ }
            if ($resourceName -match '(?i)\.png\.import$' -and $target -match '\.ctex$') { $textureCount++ }
            $script:Report.counts.pck_imports++
        }
        if ($fontCount -eq 0 -or $textureCount -eq 0) { throw 'PCK 缺少字体或 PNG 编译纹理的本地导入映射。' }
        $script:Report.counts.pck_files = $packEntries.Count
        $script:Report.pck = [ordered]@{ format = 3; offset = $packStart; bytes = $packBytes; engine_version = ('{0}.{1}.{2}' -f (Read-U32 $data ($packStart + 8)), (Read-U32 $data ($packStart + 12)), (Read-U32 $data ($packStart + 16))); font_imports = $fontCount; texture_imports = $textureCount }
        $script:Report.checks.embedded_pck = 'passed'
        try {
            $project = $packEntries['project.binary']
            $runtimeVersion = Read-ProjectVersion $data $project.start $project.size
            $script:Report.versions.project_binary = $runtimeVersion
            if ($runtimeVersion -ne $script:Report.expected_version) { throw "EXE 中的项目版本为 $runtimeVersion，与期望值不符。" }
            $script:Report.checks.runtime_version = 'passed'
        }
        catch { Add-Failure 'VERSION_RUNTIME_INVALID' ($name + ':project.binary') $_.Exception.Message; $script:Report.checks.runtime_version = 'failed' }
    }
    catch { Add-Failure 'PCK_INVALID' $name $_.Exception.Message; $script:Report.checks.embedded_pck = 'failed' }
}

function Test-Licenses {
    $before = $script:Issues.Count
    foreach ($relative in @('GodotEngine-LICENSE.txt', 'GodotEngine-THIRD-PARTY.txt', 'GodotEngine-THIRD-PARTY.json', 'OFL-NotoSansCJK.txt')) {
        $name = Get-PackagePath $relative
        try {
            if ([string]::IsNullOrWhiteSpace((Read-Text $name))) { throw '许可证/通知文件为空。' }
        }
        catch { Add-Failure 'LICENSE_MISSING_OR_INVALID' $name $_.Exception.Message }
    }
    $script:Report.checks.licenses = $(if ($before -eq $script:Issues.Count) { 'passed' } else { 'failed' })
}

# 只解析标签、属性和 CSS 声明，不创建浏览器/COM DOM，不求值 JavaScript。
function Get-HtmlDocument([string]$Name) {
    if ($script:HtmlDocuments.ContainsKey($Name)) { return $script:HtmlDocuments[$Name] }
    $html = Read-Text $Name
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $references = [Collections.Generic.List[object]]::new()
    $css = [Collections.Generic.List[string]]::new()
    $scripts = [Collections.Generic.List[string]]::new()
    $tagPattern = '(?is)<!--.*?-->|<(?<tag>[a-z][a-z0-9:-]*)(?<attrs>(?:[^"''<>]|"[^"]*"|''[^'']*'')*)>'
    $attributePattern = '(?is)(?<key>[a-z_:][a-z0-9_:.-]*)\s*=\s*(?:"(?<value>[^"]*)"|''(?<value>[^'']*)''|(?<value>[^\s"''=<>`]+))'
    $scanner = [regex]::new($tagPattern, [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(5))
    $position = 0
    $charsetFound = $false
    while ($position -lt $html.Length) {
        # 从当前位置查找，保持 script/style 内容不被误识别为 HTML 标签。
        $tag = $scanner.Match($html, $position)
        if (-not $tag.Success) { break }
        $position = $tag.Index + $tag.Length
        if (-not $tag.Groups['tag'].Success) { continue }
        $tagName = $tag.Groups['tag'].Value.ToLowerInvariant()
        $attrs = @{}
        foreach ($attribute in [regex]::Matches($tag.Groups['attrs'].Value, $attributePattern)) {
            $key = $attribute.Groups['key'].Value.ToLowerInvariant()
            # HTML 忽略同名属性的后续出现；保留首项以与浏览器的链接解析一致。
            if (-not $attrs.ContainsKey($key)) { $attrs[$key] = [Net.WebUtility]::HtmlDecode($attribute.Groups['value'].Value) }
        }
        if ($attrs.ContainsKey('id')) {
            if (-not $ids.Add($attrs['id'])) { Add-Failure 'HTML_DUPLICATE_ID' $Name "HTML id 重复：$($attrs['id'])" }
        }
        if ($tagName -eq 'a' -and $attrs.ContainsKey('name')) { [void]$ids.Add($attrs['name']) }
        if ($tagName -eq 'meta' -and $attrs.ContainsKey('charset')) {
            if ($attrs['charset'] -notmatch '^(?i:utf-8)$') { Add-Failure 'HTML_CHARSET' $Name 'HTML 声明的字符集不是 UTF-8。' }
            else { $charsetFound = $true }
        }
        foreach ($attributeName in @('href', 'src', 'poster')) {
            if (-not $attrs.ContainsKey($attributeName)) { continue }
            $dependency = ($attributeName -ne 'href' -or $tagName -ne 'a')
            $references.Add([pscustomobject]@{ url = $attrs[$attributeName]; dependency = $dependency })
        }
        if ($attrs.ContainsKey('srcset')) {
            foreach ($candidate in ($attrs['srcset'] -split ',')) {
                $url = ($candidate.Trim() -split '\s+')[0]
                $references.Add([pscustomobject]@{ url = $url; dependency = $true })
            }
        }
        if ($tagName -eq 'img' -and -not $attrs.ContainsKey('src') -and -not $attrs.ContainsKey('srcset')) { Add-Failure 'IMAGE_SOURCE_MISSING' $Name 'img 缺少 src/srcset。' }
        if ($attrs.ContainsKey('style')) { $css.Add($attrs['style']) }
        if ($tagName -in @('script', 'style')) {
            $close = [regex]::Match($html.Substring($position), ('(?is)</' + $tagName + '\s*>'))
            if (-not $close.Success) { throw "HTML 缺少 $tagName 结束标签。" }
            $body = $html.Substring($position, $close.Index)
            if ($tagName -eq 'style') { $css.Add($body) } else { $scripts.Add($body) }
            $position += $close.Index + $close.Length
        }
    }
    if (-not $charsetFound) { Add-Failure 'HTML_CHARSET' $Name 'HTML 缺少明确的 UTF-8 meta charset。' }
    $document = [pscustomobject]@{ ids = $ids; references = $references; css = $css; scripts = $scripts }
    $script:HtmlDocuments.Add($Name, $document)
    $script:Report.counts.html_documents++
    return $document
}

function Resolve-LocalReference([string]$Source, [string]$Url, [bool]$Dependency) {
    $urlValue = $Url.Trim()
    if ($urlValue -match '^(?i:https?://)') {
        if ($Dependency) { throw '离线资源引用 HTTP(S) 网络地址。' }
        $script:Report.counts.external_citations++
        return $null
    }
    if ($urlValue.StartsWith('//') -or $urlValue.StartsWith('\\')) { throw '禁止协议相对网络地址或 UNC 引用。' }
    if ($urlValue -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') { throw '不支持该 URI 协议；不读取包外文件或执行脚本。' }
    if ($urlValue -eq '' -and $Dependency) { throw '资源引用为空。' }
    if ($urlValue -match '%(?![0-9a-fA-F]{2})') { throw 'URL 百分号编码无效。' }
    $fragment = ''
    $hashIndex = $urlValue.IndexOf('#')
    if ($hashIndex -ge 0) {
        $fragment = [Uri]::UnescapeDataString($urlValue.Substring($hashIndex + 1))
        $urlValue = $urlValue.Substring(0, $hashIndex)
    }
    $queryIndex = $urlValue.IndexOf('?')
    if ($queryIndex -ge 0) { $urlValue = $urlValue.Substring(0, $queryIndex) }
    $decoded = [Uri]::UnescapeDataString($urlValue).Replace('\', '/')
    if ($decoded.StartsWith('/') -or $decoded -match '[\x00-\x1f\x7f<>:"|?*]') { throw '引用是绝对路径、盘符路径或含非法字符。' }
    if ($decoded -eq '') { return [pscustomobject]@{ path = $Source; fragment = $fragment } }
    $parts = [Collections.Generic.List[string]]::new()
    $slash = $Source.LastIndexOf('/')
    if ($slash -ge 0) { foreach ($part in $Source.Substring(0, $slash).Split('/')) { $parts.Add($part) } }
    $rootDepth = 0
    if ($script:RootPrefix) { $rootDepth = $script:RootPrefix.TrimEnd('/').Split('/').Count }
    foreach ($part in $decoded.Split('/')) {
        if ($part -eq '.' -or $part -eq '') { continue }
        if ($part -eq '..') {
            if ($parts.Count -le $rootDepth) { throw '相对引用越出发布包根目录。' }
            $parts.RemoveAt($parts.Count - 1)
        } else { $parts.Add($part) }
    }
    $resolved = Get-SafeName ($parts -join '/')
    return [pscustomobject]@{ path = $resolved; fragment = $fragment }
}

function Test-Png([string]$Name) {
    if ($script:VerifiedPng.Contains($Name)) { return }
    $data = Read-Entry $Name
    if ($data.Length -lt 45 -or [BitConverter]::ToString($data, 0, 8) -ne '89-50-4E-47-0D-0A-1A-0A' -or
        [BitConverter]::ToString($data, 8, 8) -ne '00-00-00-0D-49-48-44-52' -or
        [BitConverter]::ToString($data, $data.Length - 12, 8) -ne '00-00-00-00-49-45-4E-44') {
        throw 'PNG 签名、IHDR 或 IEND 边界无效；未执行图像解码/渲染。'
    }
    if (($data[16] -bor $data[17] -bor $data[18] -bor $data[19]) -eq 0 -or ($data[20] -bor $data[21] -bor $data[22] -bor $data[23]) -eq 0) { throw 'PNG 宽高为零。' }
    [void]$script:VerifiedPng.Add($Name)
    $script:Report.counts.png_headers++
}

function Test-Reference([string]$Source, [string]$Url, [bool]$Dependency) {
    try {
        $target = Resolve-LocalReference $Source $Url $Dependency
        if ($null -eq $target) { return }
        if (-not $script:Entries.ContainsKey($target.path) -or $script:Entries[$target.path].is_directory) { throw "本地引用文件缺失：$($target.path)" }
        $script:Report.counts.local_links++
        if ($target.path -match '(?i)\.png$') {
            Test-Png $target.path
            [void]$script:ReferencedImages.Add($target.path)
        }
        if ($target.fragment -ne '' -and $target.path -match '(?i)\.html?$') {
            $document = Get-HtmlDocument $target.path
            if (-not $document.ids.Contains($target.fragment)) { throw "HTML 锚点缺失：$($target.path)#$($target.fragment)" }
        }
    }
    catch { Add-Failure 'REFERENCE_INVALID' $Source ("引用 '$Url'：" + $_.Exception.Message) }
}

function Test-CssReferences([string]$Source, [string]$Css) {
    $clean = [regex]::Replace($Css, '(?s)/\*.*?\*/', '')
    foreach ($url in [regex]::Matches($clean, '(?is)url\(\s*(?:"(?<url>[^"]*)"|''(?<url>[^'']*)''|(?<url>[^)\s]+))\s*\)')) {
        Test-Reference $Source $url.Groups['url'].Value $true
    }
    foreach ($url in [regex]::Matches($clean, '(?is)@import\s+(?:"(?<url>[^"]+)"|''(?<url>[^'']+)'')')) {
        Test-Reference $Source $url.Groups['url'].Value $true
    }
}

function Test-OfflineReference {
    $before = $script:Issues.Count
    $referencePrefix = Get-PackagePath 'docs/reference/'
    foreach ($name in @($script:Entries.Keys)) {
        if ($script:Entries[$name].is_directory -or -not $name.StartsWith($referencePrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        try {
            if ($name -match '(?i)\.html?$') {
                $document = Get-HtmlDocument $name
                foreach ($reference in $document.references) { Test-Reference $name $reference.url $reference.dependency }
                foreach ($css in $document.css) { Test-CssReferences $name $css }
            } elseif ($name -match '(?i)\.css$') { Test-CssReferences $name (Read-Text $name) }
            elseif ($name -match '(?i)\.png$') { Test-Png $name }
        }
        catch { Add-Failure 'REFERENCE_INVALID' $name $_.Exception.Message }
    }
    $script:Report.checks.reference_links = $(if ($before -eq $script:Issues.Count) { 'passed' } else { 'failed' })

    $catalogName = Get-PackagePath 'docs/reference/catalog.json'
    try {
        $catalog = ConvertFrom-Json -InputObject (Read-Text $catalogName)
        $version = [string](Get-Property $catalog 'game_version')
        if ([string]::IsNullOrEmpty($version)) { throw 'catalog.json 缺少 game_version，不能推断游戏版本。' }
        $script:Report.versions.catalog = Get-NormalVersion $version
        if ((Get-NormalVersion $version) -ne $script:Report.expected_version) { throw "图鉴 game_version 为 $version，与期望版本不符。" }
        $script:Report.checks.version = 'passed'
    }
    catch { Add-Failure 'VERSION_INVALID' $catalogName $_.Exception.Message; $script:Report.checks.version = 'failed' }

    $before = $script:Issues.Count
    $artName = Get-PackagePath 'docs/reference/art/manifest.json'
    try {
        $art = ConvertFrom-Json -InputObject (Read-Text $artName)
        $rowsValue = Get-Property $art 'entries'
        if ($null -eq $rowsValue) { throw '图片清单缺少 entries。' }
        $rows = @($rowsValue)
        if ((Get-Property $art 'status') -ne 'complete' -or $rows.Count -eq 0 -or $rows.Count -ne (Get-Property $art 'written_images')) { throw '图片清单不是 complete，或 written_images 与 entries 数量不符。' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($row in $rows) {
            $relative = [string](Get-Property $row 'file')
            try {
                $relative = Get-SafeName $relative
                if (-not $seen.Add($relative)) { throw '图片清单路径重复。' }
                if ($relative -notmatch '(?i)\.png$') { throw '当前图鉴图片标准要求 PNG；其他格式未验证。' }
                $imageName = Get-PackagePath ('docs/reference/art/' + $relative)
                Test-Png $imageName
                if (-not $script:ReferencedImages.Contains($imageName)) { throw "图片未被 HTML/CSS 引用：$imageName" }
                $script:Report.counts.art_entries++
            }
            catch { Add-Failure 'ART_INVALID' $relative $_.Exception.Message }
        }
        $artPrefix = Get-PackagePath 'docs/reference/art/'
        foreach ($name in $script:Entries.Keys) {
            if ($name.StartsWith($artPrefix, [StringComparison]::OrdinalIgnoreCase) -and $name -match '(?i)\.png$' -and -not $seen.Contains($name.Substring($artPrefix.Length))) {
                Add-Failure 'ART_UNLISTED' $name '图鉴 PNG 未列入图片清单。'
            }
        }
    }
    catch { Add-Failure 'ART_INVALID' $artName $_.Exception.Message }
    $script:Report.checks.reference_art = $(if ($before -eq $script:Issues.Count) { 'passed' } else { 'failed' })
}

$fileStream = $null
$archive = $null
$script:VerifiedPng = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:ReferencedImages = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
try {
    $script:Report.expected_version = Get-NormalVersion $ExpectedVersion
    $script:RootPrefix = ''
    if ($PackageRoot -ne '') { $script:RootPrefix = (Get-SafeName $PackageRoot) + '/' }
    $script:Report.package_root = $script:RootPrefix
    $resolvedZip = (Resolve-Path -LiteralPath $ZipPath).ProviderPath
    $script:Report.zip = $resolvedZip
    # 同一个只读句柄完成 SHA 与 ZIP 读取；共享模式不允许并发写入或删除。
    $fileStream = [IO.File]::Open($resolvedZip, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $script:Report.actual_sha256 = [BitConverter]::ToString($sha.ComputeHash($fileStream)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $fileStream.Position = 0
    $shaMatches = $script:Report.actual_sha256 -eq $script:Report.expected_sha256
    $script:Report.checks.zip_sha256 = $(if ($shaMatches) { 'passed' } else { 'failed' })
    if (-not $shaMatches) { Add-Failure 'ZIP_SHA256_MISMATCH' $resolvedZip 'ZIP SHA256 与调用者提供的期望值不符。' }
    try {
        $archive = [IO.Compression.ZipArchive]::new($fileStream, [IO.Compression.ZipArchiveMode]::Read, $true, $script:Utf8)
        $metadataSafe = Test-ArchiveMetadata $archive
        $script:Report.checks.zip_structure = $(if ($metadataSafe) { 'passed' } else { 'failed' })
    }
    catch { Add-Failure 'ZIP_INVALID' $resolvedZip $_.Exception.Message; $metadataSafe = $false; $script:Report.checks.zip_structure = 'failed' }
    if ($metadataSafe -and $shaMatches) {
        foreach ($relative in @('GodotGame.exe', 'SHA256SUMS.txt', 'docs/reference/index.html', 'docs/reference/catalog.json', 'docs/reference/art/manifest.json')) {
            $name = Get-PackagePath $relative
            if (-not $script:Entries.ContainsKey($name) -or $script:Entries[$name].is_directory) { Add-Failure 'REQUIRED_FILE_MISSING' $name '发布标准要求该文件，ZIP 中不存在。' }
        }
        Test-FileHashes
        Test-TextEncoding
        Test-Executable
        Test-Licenses
        Test-OfflineReference
    }
}
catch { Add-Failure 'INPUT_OR_VERIFIER_ERROR' $ZipPath $_.Exception.Message }
finally {
    if ($null -ne $archive) { $archive.Dispose() }
    if ($null -ne $fileStream) { $fileStream.Dispose() }
}
$script:Report.issues = @($script:Issues.ToArray())
if ($script:Issues.Count -eq 0) { $script:Report.status = 'passed' }
$script:Report | ConvertTo-Json -Depth 10
if ($script:Issues.Count -gt 0) { exit 1 }
exit 0
