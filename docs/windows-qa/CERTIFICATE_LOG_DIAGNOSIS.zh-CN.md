# Windows Godot 根证书启动日志诊断

本次在受限 Windows 账号下，官方 Godot 4.6.3 启动**无项目脚本的空场景**也复现了根证书错误。项目配置及离线模型执行产生相同错误，进程均返回 `0`，详细日志均显示回退到内置 CA。因此这条错误不依赖项目网络请求，不能据此认定项目脚本失败，也不能把严格日志结果判为通过。

## 实测环境与原始错误

- 时间：`2026-10-02T16:42:44Z` 至 `16:42:49Z`。
- 项目基线：远端 `main` 的 `a4a306a6d8c14320fce383dccf6ad7ca40836757`（v0.13.0）。
- 身份：`DESKTOP-FBRTNR7\CodexSandboxOffline`；令牌 `has_restrictions=true`、`elevated=false`、`app_container=false`。
- 使用已有安装，版本输出：`4.6.3.stable.official.7d41c59c4`；脚本报告完整 build hash：`7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3`。
- 控制台入口：`C:\Users\ZQS\Documents\Codex\2026-10-02\task-3\runtime\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe`，SHA-256 为 `63B3B2208819714C9677FBFDD8217C5B7DEE8ECF5F383502E826BC9E2227FF5A`。
- `OS.get_executable_path()` 报告同目录的 `Godot_v4.6.3-stable_win64.exe`，SHA-256 为 `EF90E929BA1A6A4322860285D97F40F4AA349C90329A91B0E8B55B8DF0F4CB00`。控制台文件是入口包装器，两个哈希对应不同文件。

五次完整启动的 stderr 原文完全相同：

```text
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2570)
```

这五份 stderr 的 SHA-256 均为 `FF360BB922D2C4DADFA558A268704E943910E27D07FDAC118CE15359C13CECA9`。分别保存 stdout、stderr，没有删行、改级别或合并流后猜测跨流时间顺序。

## 对照结果

| 步骤 | 实际运行内容 | 进程退出码 | 根证书 ERROR | 内置 CA 日志 |
| --- | --- | --- | --- | --- |
| 01-readonly-store | Windows 只读 ROOT 库与令牌审计 | 0 | 无 | 不适用 |
| 02-version | 已有 EXE 的 `--version` | 0 | 无 | 无 |
| 03-empty-probe | 空工程，独立 userdata 路径探针 | 0 | 1 条 | 有 |
| 04-empty-scene | 同一空工程，仅无脚本的 `Node` 场景，`--quit` | 0 | 1 条 | 有 |
| 05-alternate-appdata | 另一全新 APPDATA 目录，账号和令牌不变 | 0 | 1 条 | 有 |
| 06-project-config | 原项目配置副本，独立路径探针替代主场景 | 0 | 1 条 | 有 |
| 07-project-model | 同一配置，隔离验证后加载原 BuildState 依赖闭包 | 0 | 1 条 | 有 |

模型成功实例化，读取到 26 项属性、`max_health=120`、`damage=26`；未调用存档读写方法或网络方法。这里的项目对照覆盖配置及离线模型，不代表完整游戏、资源导入、GUI 或所有 SCRIPT 检查都已重新验证。

各脚本探针同时核验实际 `res://`、`OS.get_user_data_dir()` 和 `user://`，均位于本次新建 sandbox。空场景在对应隔离探针通过后启动。APPDATA、LOCALAPPDATA、TEMP、TMP 仅设置在子进程环境；USERPROFILE、HOME 与当前 Windows 身份未改写。源资源哈希及父进程环境复核均未变化。引擎自身若生成日志，也留在隔离 userdata 内。

诊断收集完成：`diagnostic_completed=true`、`error=null`；严格结果：`strict_log_clean=false`，**整个诊断脚本返回 1**。没有证书错误白名单；所有捕获的 Godot ERROR 都保留并参与失败判定。此诊断没有修改现有验证工具的 strict 判定。

## 来源、权限与影响范围

**引擎启动入口。** 官方源码中的游戏启动路径加载默认 CA；Windows 实现通过 `CertOpenSystemStoreA(0, "ROOT")` 打开证书库，句柄为空时输出上述错误。它发生于引擎证书初始化，无脚本空场景已独立复现。[Godot 启动源码](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/main/main.cpp)、[Windows 证书入口](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/platform/windows/os_windows.cpp)。本次原始二进制日志行号是 `2570`；在线 tag 页面行号与之不同，且未取得按完整 build hash 固定的源码副本，不能用网页行号替换原日志定位。

**只读访问实际可用。** 独立审计没有直接调用缺少只读参数的 `CertOpenSystemStoreA`，而是使用 `CertOpenStore` 的 `READONLY | OPEN_EXISTING`：CurrentUser 标志 `0x0001C000`，LocalMachine 标志 `0x0002C000`。两个逻辑 ROOT 库均打开成功、完整枚举 68 个证书并关闭。枚举尾码 `0x80092004` 是 `CRYPT_E_NOT_FOUND`，表示列表已结束，不是本次打开失败。[枚举 API 定义](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-certenumcertificatesinstore)。探针仅记录数量，不导出证书内容，也不调用添加、删除或设置属性 API。

只读读取注册表物理 `ROOT\Certificates` 得到 HKCU 子项 0、HKLM 子项 21；不能用这些物理子项数代替逻辑库数量。CurrentUser ROOT 可继承机器库内容，所以 HKCU 没有个人子项不代表没有可用根证书。[用户和机器证书库](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/local-machine-and-current-user-certificate-stores)。

**最符合证据的解释仍是权限与打开方式之间的差异。** `CertOpenSystemStoreA` 面向当前用户库；它与本次显式只读打开不是相同参数组合。微软说明，注册表证书提供程序在只读标志下请求读取权限，未指定该标志时可请求更高访问权限。受限令牌、只读打开成功而引擎入口失败，与这种差异相符；这是推断，不能把它写成已捕获的 Windows `ERROR_ACCESS_DENIED=5`。[系统库 API](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-certopensystemstorea)、[CertOpenStore 标志](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-certopenstore)。Godot 原日志没有记录 `GetLastError()`，本次也没有进行非只读 API 重放、改变令牌或普通账号引擎对照，因此尚未证明唯一的底层原因。

两个新 APPDATA 目录都复现，说明更换 userdata 位置没有消除问题；它并不会更换进程身份或证书库对应的 HKCU。该账号的结果不能外推为用户 `ZQS` 普通交互会话也必定失败。Git 曾出现的 Schannel `SEC_E_NO_CREDENTIALS (0x8009030E)` 属于另一个调用栈，不能拿来充当 Godot 此次证书库调用的 Windows 错误码。

**离线功能与 TLS 信任。** 五份启动 stdout 均实际包含 `Loaded builtin CA certificates`。官方 MbedTLS 实现在系统证书不可用时可加载编译内置 CA；本轮日志确认了这一分支。[Godot CA 回退源码](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/modules/mbedtls/crypto_mbedtls.cpp)。这说明错误之后仍可完成本轮离线启动和模型读取，不能证明任意 HTTPS 连接都成功。内置 CA 也不能保证包含用户或企业额外信任的根。

基线的 `scripts/`、`scenes/` 和 `project.godot` 检索未发现 HTTPRequest、HTTPClient、WebSocket、WebRTC、ENet、PacketPeer、StreamPeer、TLSOptions 或 X509Certificate 的运行时调用；出现的外部 URL 是规则来源元数据或文档链接。项目没有设置 `network/tls/certificate_bundle_override`，探针读取值也是空字符串。扫描是静态证据，不是网络抓包；本轮没有执行在线 TLS 握手，也没有测试发行版 EXE。因此已确认的影响是启动错误日志与严格验收失败，当前离线模型读取未被阻断；在线信任兼容性和普通用户会话仍未验证。

## 最小复现与证据位置

在仓库根目录、Windows PowerShell 7 中运行：

```powershell
& .\tests\windows\certificate_diagnosis.ps1 `
  -GodotBin 'C:\Users\ZQS\Documents\Codex\2026-10-02\task-3\runtime\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe' `
  -SandboxParent 'C:\Users\ZQS\Documents\Codex\2026-10-03\task'
```

运行器自行建立全新 sandbox；本次权限环境下预期最终退出码为 `1`。它不下载引擎、启动编辑器或发起网络请求。若在用户醒来后的普通会话执行同一命令，可比较报告中的实际 identity、令牌信息、03/04 日志；无需改证书或启动管理员会话。

核心最小案例是步骤 04：`project.godot` 只有名称、主场景和隔离 userdata 设置，`empty.tscn` 只有一个无脚本 `Node`，引擎参数为 `--headless --verbose --path <sandbox>/empty/project --quit`。运行器已在子进程上配置隔离 APPDATA 并先验证实际 userdata；不要省略这部分隔离后直接复用该命令。

本次保留完整证据目录：

```text
C:\Users\ZQS\Documents\Codex\2026-10-03\task\godot-certificate-qa-45a2a89c3f3e4da88494c5ffeee34730\
  report.json
  logs\01-readonly-store.stdout.txt
  logs\02-version.stdout.txt
  logs\03-empty-probe.stdout.txt / .stderr.txt
  logs\04-empty-scene.stdout.txt / .stderr.txt
  logs\05-alternate-appdata.stdout.txt / .stderr.txt
  logs\06-project-config.stdout.txt / .stderr.txt
  logs\07-project-model.stdout.txt / .stderr.txt
```

每个步骤都有独立 stdout、stderr 文件及其 SHA-256，完整命令参数和实际退出码写在报告中。`report.json` SHA-256：`D5134285ED6F951AA8F09C9873FC18C4921B3A2D4BBE76D9630DB1BCC46B86B2`。原始证据留在本机，仓库只新增此说明及三个 `tests/windows/certificate_*` 探针文件。

本次没有修改 Windows 证书库、ACL、安全策略或信任列表，没有禁用 TLS 校验，没有改引擎安装目录、存档与发行工具，也没有通过 GUI 操作解锁会话。保留的未验证项是普通账号对照、引擎调用的具体 Windows 错误码，以及真实在线 TLS 兼容性。
