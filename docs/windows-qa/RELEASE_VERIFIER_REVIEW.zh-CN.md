# Windows 发布验证器短审查

审查日期：2026-10-02（UTC）。对象：`codex/windows-release-verifier-20261002` 的提交 `e3a0881dd73ef7db9aa0394934ca0865964582e0`。开始时通过 `git ls-remote` 确认远端分支正好指向该提交。

范围仅为 `tools/windows/verify_release.ps1`、`tests/windows/release_verifier_test.ps1` 及其说明文档。**发现两项有具体反例的静态缺陷，均为 P2。** 没有修改验证器、生产代码或 fixture；本次仅新增本文。

当前 Linux 环境的 PATH 中没有 `pwsh` 或 `powershell`。**没有实跑验证器或原有 69 个 fixture，也没有 Windows/浏览器实测。** 下述“可通过检查”指按该提交的代码逐步推导，没有冒充运行结果。只用自写 Python 在内存中核对区间算术；未安装工具、运行包内 EXE/网页脚本、读取凭据、下载发行包或重跑游戏测试。

## 1. HTML 重复属性采用末项，能漏掉浏览器实际使用的逃逸链接

证据：[verify_release.ps1:474–475](../../tools/windows/verify_release.ps1#L474) 将每个属性写入同一哈希表，重复键会被后一个值覆盖；[485–488](../../tools/windows/verify_release.ps1#L485) 只检查覆盖后的值。HTML 的重复属性处理保留先出现的属性，因此两种解析结果不同。

最小反例：在 `New-Fixture` 原有 `index.html` 中追加下面的标签，保留现有 `id="top"`、图片和其他有效内容：

```html
<a href="../../../escaped-payload.txt" href="#top">逃逸链接</a>
```

从 `docs/reference/index.html` 出发，首个 `href` 的第三次 `..` 会越出 ZIP 发布根目录；若单独交给 `Resolve-LocalReference`，会在 [543](../../tools/windows/verify_release.ps1#L543) 被拒绝。但扫描器仅留下第二个 `href="#top"`，检查现存本页锚点，完全不检查首个链接。重建清单和 ZIP SHA 后，其他检查不受此追加标签影响。

影响：检查报告可以漏掉普通 HTML 标签中的包外文件引用。只读验证器本身不会访问包外文件；缺陷发生在静态验收结果与实际 HTML 链接的差异。受限静态扫描器的范围说明不能消除这项已采集属性的解析差异。

最小 fixture 建议（仅建议，未写入测试文件）：

```powershell
$files = New-Fixture
$files['docs/reference/index.html'] = Bytes (([Text.Encoding]::UTF8.GetString($files['docs/reference/index.html'])) + '<a href="../../../escaped-payload.txt" href="#top">逃逸链接</a>')
Case '重复href首项逃逸' $files -Code 'REFERENCE_INVALID'
```

该负例在当前代码下没有对应的 `REFERENCE_INVALID` 来源。修复时可以拒绝重复属性并调整断言错误码，或按 HTML 首项语义检查；不应继续静默覆盖首项。现有百分号穿越负例（[fixture:311–312](../../tests/windows/release_verifier_test.ps1#L311)）只有一个 `href`，不能覆盖此问题。

## 2. PCK 包头重叠保护只覆盖 40 字节，漏掉 v3 保留区

证据：现有 `New-Exe` 写入 40 字节字段后，再写 64 字节保留区，目录位于相对偏移 104（[fixture:97–100](../../tests/windows/release_verifier_test.ps1#L97)）。验证器却只要求目录偏移至少 40（[359](../../tools/windows/verify_release.ps1#L359)），并只拒绝资源起点早于 `packStart + 40`（[398–402](../../tools/windows/verify_release.ps1#L398)）。资源的 MD5 和容器范围检查不能补足包头重叠检查。

最小 fixture 构造建议：

1. 在 `New-Resources` 中追加 `header-alias.bin`，内容为单个零字节，再调用原有 `New-Exe`。七项资源的原始 `dataBase` 为 564，`packStart` 为 512。
2. 将 PCK 的 `dataBase` 字段改为 40。对其他六项目录记录，把偏移改为 `564 + 原偏移 - 40`，保持它们的实际资源位置、大小及 MD5 不变。
3. 将 `header-alias.bin` 的记录偏移改为 0，大小仍为 1，MD5 仍为零字节的 `93b885adfe0da089cdf634904fd59f71`。实际指向保留区中的零字节。
4. 经 `New-TestZip` 重建 SHA 清单并计算匹配的外层 SHA，断言应拒绝这项包头重叠，建议错误码 `PCK_INVALID`。

该资源区间为 `[552, 553)`；v3 包头区间为 `[512, 616)`；目录区间为 `[616, 1076)`。因此资源确实位于包头内，但当前两项重叠条件分别是 `552 < 552` 和 `553 > 616`，都为假。它也满足读取长度、资源累计量及 MD5 检查，不触发导入映射或版本检查。内存算术核对得到相同数值；没有 PowerShell 实跑结果。

影响：`embedded_pck=passed` 无法兑现现有“资源不与包头重叠”的检查意图。此例不导致越界读、代码执行或写盘，也不证明游戏能加载该畸形包。最低修复范围应覆盖支持格式的完整包头区间，并相应约束目录偏移；本文没有实施修复。

## 其他指定边界的审查结果

| 边界 | 静态结论与证据 |
| --- | --- |
| Windows 大小写及 ZIP 完全重复名 | `OrdinalIgnoreCase` 字典加 NFC 规范化后检查重复（验证器 23、111、183–185）；现有 fixture 325–328 覆盖完全重复、大小写重复及 Unicode 规范重复。未发现绕过。 |
| ZIP 绝对路径、`../`、反斜杠 | 验证器 94–111 拒绝绝对/盘符/UNC、反斜杠、空段、点段、尾部点/空格及设备名；fixture 322–324 有对应负例。未发现绕过。 |
| ZIP 数量及大小安全门 | 166–200 拒绝超过 10000 项、单项超过 256 MiB、展开总量超过 512 MiB、压缩比超过 1000；679 才允许读取负载。文本上限为 16 MiB，读取时再核对实际展开长度（129–134、152）。原 fixture 345–351 只覆盖单项声明超限，缺少数量、累计量和压缩比的边界用例。 |
| PE/PCK 整数溢出 | PE 的 32 位偏移先转 `long` 并验范围；PCK 的 U64 超过 `Int64.MaxValue` 即拒绝，随后受包长限制，资源长度和累计量也先检查（268–283、330–338、349–389）。有效负载已受 256 MiB 上限限制，未发现可通过这些门的偏移/长度加法溢出。 |
| 普通图鉴路径逃逸 | 单次 URL 百分号解码、反斜杠转斜杠后逐段解析；`rootDepth` 拒绝越出显式包根，绝对路径及不支持协议拒绝（513–548）。合法 `../notes/` 在包内被允许。未发现单属性路径解析绕过；重复属性缺陷见第 1 项。 |

数量/大小最小补充 fixture 建议：以零长度条目构造 10000/10001 项边界；只修改多个中央目录记录的展开长度，使每项不超 256 MiB 而总量达到/超过 512 MiB；修改声明的压缩/展开长度使比例达到/超过 1000；对文本添加 16 MiB/16 MiB+1 边界。以上均应仅使用内存或临时人工 ZIP，不必生成或展开数百 MiB 的真实负载。临界值只验证相应安全门，不代表其他发布检查必然通过。

范围限制：`Archive.Entries.Count` 在获取 .NET 条目集合后才应用数量门，不能据此声称 ZIP 元数据解析本身具有 10000 项的预分配硬限制。PE 只检查整个 EXE 内的头/节表基本边界，未验收节的原始数据区间或 PE/PCK 的交叉布局；这不等价于 Windows loader 验收。PCK 资源之间也没有两两区间重叠检查；本次未证明共享资源区间一定违反支持格式，因此没有把单纯共享区间另列为缺陷。

本次审查到此收口。没有 merge，没有生产或验证器改动；尚缺 PowerShell 环境中的上述最小回归反例实跑。
