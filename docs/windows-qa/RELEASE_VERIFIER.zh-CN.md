# Windows 发布 ZIP 只读验证器

`tools/windows/verify_release.ps1` 使用 Windows PowerShell 5.1 自带的 PowerShell/.NET API，直接读取本地 ZIP。无需 Godot、Python、Node、浏览器或新增安装。它不解压文件，不启动 `GodotGame.exe`，不求值网页 JavaScript，不读取游戏 `user_data`，不请求网络。

此工具验证当前项目发布标准中的 **PE x64 容器、PCK 资源、包内版本和离线图鉴静态依赖**。通过结果不能替代 Windows 原生 GUI、浏览器渲染/交互或 Authenticode 验收。

## 使用

在仓库根目录运行，SHA 必须来自可信发布记录或调用者提供的期望值。工具不会自行下载包、信任文件名中的版本或从 README 猜测版本。

```powershell
$zip = 'C:\Downloads\GodotGame-v0.13.0-windows-x86_64.zip'
$sha = '2a6be5b3dd0db54fb4683de6f0751ba378e65e9b3c56f6a2f1d1c2139131fe73'
$json = & powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tools\windows\verify_release.ps1 -ZipPath $zip -ExpectedSha256 $sha -ExpectedVersion 'v0.13.0'
$resultCode = $LASTEXITCODE
$json | Set-Content -LiteralPath .\release-verification.json -Encoding UTF8
"验证退出码：$resultCode"
```

JSON 由 stdout 返回；上例中的报告文件由调用者写入，验证器本身不写文件。Windows PowerShell 5.1 的 `Set-Content -Encoding UTF8` 会写入 UTF-8 BOM，JSON 读取器可正常读取。

| 参数 | 含义 |
| --- | --- |
| `-ZipPath` | 本地 ZIP，按 LiteralPath 处理，支持中文、空格和方括号。 |
| `-ExpectedSha256` | 必填，64 位十六进制，大小写均可。 |
| `-ExpectedVersion` | 必填数字版本，例如 `0.13.0`、`v0.13.0`；`0.13` / `v0.13` 明确规范化为 `0.13.0`。 |
| `-PackageRoot` | 默认空字符串，即 ZIP 根目录。若包被放入外层目录，必须明确传入例如 `'发布 中文/'`；不自动搜索或猜测根目录。 |

验证成功退出 **0**；发现不匹配、缺失、不安全路径或不支持的格式退出 **1**，JSON 的 `issues` 给出错误代码、路径和原因。SHA 参数绑定失败等启动错误由 PowerShell 报告，此时不保证有 JSON。

工具不更改执行策略。如果现有策略阻止本地未签名脚本，保留该阻止结果；不要使用 Bypass 或修改组织策略。已有允许本地脚本的策略下可直接运行。

## 发布标准及检查范围

必须存在：

- `GodotGame.exe`，包含未加密的 Godot PCK v3；不猜测外置 PCK。
- `SHA256SUMS.txt`，采用 `sha256sum` 格式，覆盖所有普通文件，清单自身除外。
- `docs/reference/index.html`、`catalog.json`、`art/manifest.json`。
- `GodotEngine-LICENSE.txt`、`GodotEngine-THIRD-PARTY.txt`、`GodotEngine-THIRD-PARTY.json`、`OFL-NotoSansCJK.txt`。

| 检查 | 实际验证内容 |
| --- | --- |
| 外层 SHA256 | 在一个禁止并发写入/删除的只读文件句柄上计算，与期望值比较。 |
| ZIP 元数据 | 路径穿越、绝对/UNC/盘符路径、反斜杠、ADS、设备名、末尾点/空格、空路径段、大小写及 Unicode 规范形式重复名、文件/目录冲突、符号链接/特殊条目。 |
| 安全门 | 外层 SHA 不符或 ZIP 元数据失败时停止读取负载，后续检查标为 `not_checked`；不尝试修复、重命名或解压。 |
| 每文件 SHA256 | 清单行格式、重复项、缺少目标、未覆盖文件和实际摘要。清单不能替代外部提供的可信 ZIP SHA。 |
| 文本 | `.md/.txt/.json/.html/.htm/.css/.js/.gd/.uid/.gdignore` 严格 UTF-8（可有 UTF-8 BOM），拒绝 NUL/UTF-16；JSON 还须可解析。 |
| PE | `MZ`、`PE\0\0` 签名、AMD64 Machine `0x8664`、PE32+ `0x020b`、节表/可选头基本边界。不是完整 Windows loader 或数字签名检查。 |
| PCK | `GDPC` 包头/尾、格式 v3、目录/资源边界、加密拒绝、资源重复/不安全路径、逐项 MD5；禁止导出标准中排除的研究/开发资源。 |
| 必要资源 | `project.binary`、`data/passive_balance.json` 非空；所有 `.import` 的唯一 `path` 指向包内非空编译资源，至少有字体和 PNG 纹理映射。Godot 导出的单个尾部 NUL 终止符被明确支持，内部 NUL 仍拒绝。 |
| 两处版本 | ECFG `project.binary` 中的 `application/config/version` STRING，以及图鉴 `catalog.json` 的 `game_version`，分别与期望值比较；缺少版本直接失败。 |
| 许可证 | 四份标准许可证/通知必须存在、非空且为 UTF-8；JSON 通知须可解析。这是文件完整性检查，不是法律内容审查。 |
| 离线图鉴 | 扫描图鉴目录所有 HTML/CSS：`href/src/poster/srcset`、内联/外部 CSS `url()` / `@import`、相对文件及 HTML 锚点；URL 百分号编码和查询串分别处理。允许包内合法 `../` 链接，拒绝越出发布根目录。 |
| 网络依赖 | HTTP(S) 超链接可作为外部研究引用计数，工具不会请求它们；图片、脚本、样式等网络资源引用失败。`file:`、`javascript:`、协议相对地址及其他未支持协议失败。 |
| 图片 | 清单必须 `complete`，数量与 `written_images` 一致；PNG 必须存在、被 HTML/CSS 引用、纳入清单且具有有效签名、非零 IHDR 宽高和 IEND 边界。不解码像素、不验证 PNG chunk CRC 或实际渲染。 |

HTML/CSS 使用受限的静态扫描器，不能代替完整浏览器解析器。内联及外部 JavaScript 只作为文本/哈希读取；不会运行，也不会解析其动态 URL、网络调用或 DOM 操作。Markdown 等非 HTML 目标的片段不验证语义锚点。图鉴版本检查不复现游戏玩法测试，资源 MD5/导入映射检查不证明游戏可启动。

读取上限固定为：10000 个 ZIP/PCK 条目、单文件 256 MiB、ZIP 展开总量与 PCK 资源累计读取量分别 512 MiB、单文本 16 MiB、压缩比 1000、路径 1024 字符/64 层。读取过程还核对实际展开长度；超过标准直接报告，不通过安装依赖或扩大上限自动重试。

ECFG 版本字段的限定字节解析参考 [Godot 4.6.3 ProjectSettings 源码](https://github.com/godotengine/godot/blob/4.6.3-stable/core/config/project_settings.cpp) 和 [Variant 序列化源码](https://github.com/godotengine/godot/blob/4.6.3-stable/core/io/marshalls.cpp)。只解码版本 STRING；其他 Variant 只跳过其已验证的长度，不实例化对象。

## 人工 fixture 测试

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\windows\release_verifier_test.ps1
```

如机器已有 PowerShell 7，也可指定其已有安装路径，无需安装：

```powershell
pwsh.exe -NoLogo -NoProfile -NonInteractive -File .\tests\windows\release_verifier_test.ps1 -PowerShellPath (Get-Command pwsh.exe).Source
```

测试用内存字节自造小 PE/PCK、1 像素 PNG、UTF-8 图鉴和许可证。人工 EXE 只用于容器字节检查，不是可运行游戏。测试仅启动明确指定的 PowerShell 引擎；包内 EXE、JS 和带写盘标记的 PS1 都不执行。

每轮创建唯一 `%TEMP%\godot-release-verifier-tests-<GUID>\`，其 ZIP 目录有中文和空格。所有子进程 `APPDATA` / `LOCALAPPDATA` 指向该轮隔离目录。每例对照 ZIP SHA、验证器 SHA、目录快照、隔离存档 sentinel 和两个逃逸/脚本标记，要求验证器没有文件写入或解压副作用。没有读取真实玩家存档。

测试保留 fixture 与 `test-results.json` 供复查，不自动递归清理目录。69 例覆盖合法相对/百分号链接、明确包根、版本规范化、损坏 ZIP/EXE/PCK/PNG/JSON/UTF-8、缺文件/许可证/图片、版本不一致、锚点、CSS/脚本引用、网络依赖、路径穿越/绝对路径/ADS/设备名、重复名、Unicode 规范重复、文件目录冲突、符号链接、哈希清单和先于解压的长度限制。

测试成功退出 0，断言失败退出 1；发现引擎现有策略为 Restricted/AllSigned 时报告 `blocked` 并退出 2，不更改策略。若启动测试文件本身已被策略阻止，由 PowerShell 直接报告。

## 本次实际验证

2026-10-02 在 DESKTOP-FBRTNR7，基于源提交 `a4a306a6d8c14320fce383dccf6ad7ca40836757`，仅静态读取私有发布 [v0.13.0](https://github.com/zqs1223041447/godot-game/releases/tag/v0.13.0) 的原始 ZIP：

| 项目 | 实测结果 |
| --- | --- |
| 文件 | `GodotGame-v0.13.0-windows-x86_64.zip`，56892807 字节 |
| ZIP SHA256 | `2a6be5b3dd0db54fb4683de6f0751ba378e65e9b3c56f6a2f1d1c2139131fe73`，与期望值一致 |
| ZIP / 文件哈希 | 88 个文件，展开声明 134445292 字节；清单中的 87 个文件 SHA256 通过 |
| 文本 / PE | 44 份 UTF-8 文本通过；AMD64 / PE32+ 通过 |
| 内嵌资源 | PCK v3 / Godot 4.6.3；164 项 MD5、35 份导入映射通过（1 字体、34 PNG 纹理） |
| 版本 | `project.binary` 与图鉴均为 `0.13.0` |
| 图鉴 | 2634 次本地链接检查、7 个未请求的外部研究引用、39 张 PNG / 39 个图片清单条目通过 |
| Fixture | Windows PowerShell 5.1：69/69；PowerShell 7.6.5：69/69 |
| 原生 GUI / 浏览器交互 | **未运行、未验收**；未安装或启动 Godot，未更改发行包，未访问真实存档 |

受限执行环境最初无法读到用户的 PowerShell 5.1 策略。随后只读核实实际用户已有 `CurrentUser=RemoteSigned`，在该现有策略下正常完成测试和 ZIP 验证；没有修改策略或使用 Bypass。
