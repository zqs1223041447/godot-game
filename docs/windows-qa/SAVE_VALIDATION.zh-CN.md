# Windows 存档验证：v0.13.0 / schema9

`tools/validate_windows.ps1` 在全新临时工程中验证真实 `BuildState` 存档代码。先以 `OS.get_user_data_dir()` 的实际结果证明隔离，再写入人工 fixtures。原工程、真实存档、调用者环境和 Godot 安装目录均不作为输出位置。

## 运行

需要 Windows、PowerShell 7 和已获准下载的官方 Godot 4.6.3 stable 便携可执行文件。runner 不负责下载、安装或更改系统设置。

```powershell
pwsh -NoProfile -File .\tools\validate_windows.ps1 `
  -GodotBin 'C:\已批准的便携目录\Godot_v4.6.3-stable_win64_console.exe'
```

可选 `-SandboxParent 'C:\独立测试目录'` 指定沙箱的父目录，`-TimeoutSeconds 180` 指定每个进程的超时。每次仍会创建新的 `godot-save-qa-<GUID>`，拒绝复用既有沙箱。未指定父目录时使用当前进程的临时目录。

不要直接在原游戏工程运行这些 GDScript，也不要在 Windows 直接运行 Linux `validate.sh`。GDScript 的隔离 guard 在环境或实际路径不匹配时返回 78；runner 的正、反探针会核验该行为。

## 隔离与证据

1. 创建唯一沙箱、`中文 工程` 和 `roaming/存档 沙箱 <GUID>`。检查路径祖先，拒绝 junction/symlink 等 reparse points。
2. 写入无主场景、无 autoload、无 editor plugin 的最小 `project.godot`。它使用唯一工程名、`use_custom_user_dir=true` 和唯一相对 userdata 名。
3. 仅在 `ProcessStartInfo.Environment` 的子进程环境副本中指定 APPDATA、LOCALAPPDATA、TEMP、TMP。没有 `$env:` 赋值、注册表更改或 HOME/USERPROFILE 覆盖。
4. 先运行不依赖生产模型、不读写存档的 `save_probe.gd`，输出实际 `OS.get_user_data_dir()`、`user://`、`res://`、token。GDScript 与 PowerShell 分别检查精确期望路径及沙箱边界；不匹配时不运行存档测试。
5. 在实际路径仍位于同一沙箱时，故意改变期望 userdata，确认反探针返回 78。随后才复制 BuildState 的字面量 `res://` 依赖闭包、只读 JSON 数据和 tests。
6. 以非 editor 的 `save_compile_probe.gd` 加载生产模型。该闭包只有 GDScript 和 JSON，不需要 asset import。**不运行 `--editor` 或 `--import`**：便携 Godot 的 `_sc_` 标记可能把编辑器设置定位到安装目录，即使 APPDATA 已隔离。
7. 每个测试进程再次输出隔离 guard 证据。保存 stdout、stderr、退出码、耗时、完成标记及源文件 SHA256；结束时再次核验源文件和调用者环境。

所有进程均为 headless、隐藏窗口，不依赖已解锁桌面。runner 保留完整沙箱和 `report.json`，便于父任务复核失败源文件、备份和日志；不会递归清理目录。文件锁在 `finally` 中释放。目录冲突只删除本轮创建的两个精确对象，以验证解除故障后的重试。

路径配置依据：[Godot userdata 设置](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-application-config-custom-user-dir-name)、[Windows 4.6.3 路径实现](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/windows/os_windows.cpp)。配置不能代替实际探针证据。

## 覆盖范围

| 场景 | 验证 |
|---|---|
| 中文与空格 | 工程目录、userdata 目录、存档文件名均实际包含中文和空格，参数通过 `ArgumentList` 传递 |
| 历史 v1–v8 | 每版分别运行有/无 UTF-8 BOM × LF/CRLF，共 32 组；fixture 为独立字面量历史结构 |
| 迁移 | 只读加载、一次 changed 信号、历史身份/roll/support/宝石/布局保留、v1 点数返还及 v1/v2 的既定补发 |
| 原字节备份 | Save As 不消耗原源保护；原路径及精确绝对别名升级前保留 BOM、CRLF、空白和原字节；反复保存不重写备份 |
| v9 roundtrip | 16 字段、带四词缀的稀有本地弓、旧装备、火抗装备、特殊宝石远程分配、支持技能与序列间隙全部往返 |
| 拒绝源 | 未来 v10、损坏 JSON、超限文件不得部分提交；保护 user 路径及精确绝对路径，允许另存并保持 guard；恢复有效源后解锁 |
| 备份冲突 | 相同 JSON 内容但 BOM/换行不同仍拒绝；字节完全相同的已有备份可复用；明确解除冲突后可重试 |
| 并发修改 | 从加载到保存间的源字节变更不能覆写，也不能生成错误标记的旧版备份 |
| 目标文件锁 | PowerShell 持有允许读、禁止写/delete 的真实 Windows 句柄；rename 失败保留原文件，清除本次 `.tmp`，解锁后保存成功 |
| 临时文件锁 | `.tmp` 由 FileShare.None 句柄持有；打开写入失败，原文件及其他进程临时文件的哨兵字节保留；解除后重试 |
| rename 目录冲突 | 目标同名目录及内部哨兵保留，本次 `.tmp` 清除；移除本轮冲突后重试 |
| Windows 路径别名 | `user://`↔绝对路径、`..`/`.`、反斜线、大小写与组合别名；v1–v8 × 6 别名共 48 组迁移，未来版本、冲突、外部改写、删除后的保护、同文件恢复解锁与独立副本 |

fixtures 在 Git 中保存为普通 UTF-8/LF JSON。`save_fixture.gd` 在沙箱中显式生成 BOM/CRLF 变体，避免 Git 行尾转换破坏预期原字节。比较独立 JSON 记录与模型时，会对两侧重新解析，以排除 JSON 数字 float 与模型 int 的类型差异；模型往返和原文件/备份仍分别做完整快照及原字节比较。

## 判定与日志

runner 同时要求进程退出码、唯一隔离 marker、唯一完成 marker、正检查数和零失败。任何 `SCRIPT ERROR:` 或未分类的 `ERROR:` 都失败，即使 Godot 自身退出 0；生产 bug 的断言错误也不会被忽略。

本机可稳定出现 `ERROR: Failed to read the root certificate store.`。仅这个完整、精确匹配的系统错误单独写入 `system_errors`，保留原始日志和 backtrace，并令 `strict_log_clean=false`。没有修改证书库、关闭 Godot 的错误打印或过滤原始日志。

所有存档检查通过但有该系统错误时，状态为 `passed-with-system-errors`，退出 0。加 `-StrictLogs` 时，全部存档检查完成后仍因系统错误返回失败。其他状态为 `passed` 或 `failed`。本轮由于下面的生产问题返回 `failed`，不是因为证书错误。

## 修复前复现与修复后结果

基线：main v0.13.0，`a4a306a`；Godot `4.6.3.stable.official.7d41c59c4`。2026-10-02 Windows headless 实测：基础存档及文件故障共 **1326 checks / 0 failures**；大小写别名 **14 checks / 3 failures**，共 **1340 checks / 3 failures**。正探针通过，反探针退出 78；调用者环境与源文件没有变化。

生产问题在 `tests/windows/save_path_alias_test.gd` 复现，只有人工 fixture 被写入唯一沙箱：

1. 写入合法结构的未来 v10 源；`load_build(path)` 返回 false，规范路径的 `save_block_reason(path)` 非空。
2. 确认 `ProjectSettings.globalize_path(path).to_upper()` 在 Windows 读取到同一份原字节。
3. 用该大写绝对别名 `save_build(alias)`：实际返回 **OK**，别名 guard 为空，v10 原字节被当前 v9 覆盖。预期为 `ERR_INVALID_DATA` 且原字节不变。
4. 对 v8 fixture 只读迁移后通过同样的大写别名保存：返回 **OK**，但 `.v8-backup.json` **没有创建**。预期在升级前创建原字节备份。

`BuildState` 用未经 Windows 文件身份归一化的 `ProjectSettings.globalize_path(path)` 字符串作为 guard key、迁移源比较值。实测 Windows 文件访问不区分这些路径的大小写，而这些字符串键/比较区分大小写。两种复现都保留在同一失败步骤的 `result.reproductions` 中；三个失败断言阻止 runner 把结果标为通过。

后续独立修复分支 `codex/windows-save-path-identity-fix-20261002` 经授权只修改 `BuildState` 的保存路径判断与解锁：新增 `_save_paths_match`，用于保护查询、成功加载解锁和迁移保存前后比较。先使用 `DirAccess.is_equivalent` 查询文件身份；文件锁或删除使查询不可用时，先确认父目录身份，再按该目录的 `is_case_sensitive` 规则比较文件名。没有跨平台无条件转小写。迁移保留原加载路径，备份从该源读取，保留正常 `user://` 备份诊断路径及精确字节检查。[Godot DirAccess 身份与目录大小写 API](https://docs.godotengine.org/en/4.6/classes/class_diraccess.html#class-diraccess-method-is-equivalent)

扩展回归在未修复代码上为 **2058 checks / 162 failures**，其中原 **1326 项基线全部通过**；只应用上述补丁后为 **2058 checks / 0 failures**（1326 基线 + 732 别名回归）。原先 14 项中的三处失败全部转绿。每次均使用新的临时工程和 userdata；正探针通过、负探针返回 78、源资源及调用者环境未变。

| 2026-10-02 本机证据 | 沙箱 token | 结果 |
|---|---|---|
| v0.13 扩展红色回归 | `10d493f5696f459aa981e61d350f1694` | 2058 / 162；基线 1326 / 0 |
| v0.13 最小补丁后 | `e23cb9373efd49f38039eb62d4e4220e` | 2058 / 0 |
| v0.14 原始集成副本 | `67768d94e28244588cbfff61c400604b` | 76 / 18 |
| v0.14 仅应用路径补丁的副本 | `b559f002f779413ea49d982871266c4e` | 76 / 0 |

报告及原始 stdout/stderr 保存在各沙箱 `report.json` 与 `logs/`，未把人工失败日志或存档混入仓库。通过项仍为 `passed-with-system-errors`，证书存储错误与 `strict_log_clean=false` 保留；没有改动日志判定、系统证书或安全设置。

## v0.14 集成兼容补测

基线为 `codex/v014-pierce-integration` 的 `59f173c533ba3d9ff79fdcee7ac665a15d80a67c`。只读提取源码，在分别经 userdata 探针验证的新沙箱里运行 `save_v14_alias_test.gd`；没有改写或合并该分支。补丁副本只替换 `save_build`、`save_block_reason`，添加 `_save_paths_match`，以及 `load_build` 的保护清除和迁移源路径两处语句；schema10、v9→v10 迁移与 SupportRegistry 保留。主集成应应用这些局部改动，避免整份 v0.13 `BuildState` 覆盖 v0.14。

76 项覆盖未来 v11 的大写别名保护、v8/v9 的大写及带 `..` 大写别名迁移、BOM/CRLF 原字节备份、schema10 roundtrip、冲突备份及外部改写拒绝。该额外脚本面向 schema10，不加入 schema9 runner 的默认入口；同样必须先复制独立最小工程、用 `save_probe.gd` 实证 userdata 并由宿主复核，才能动态加载模型。

## Linux 兼容回归入口与待办

`save_linux_identity_test.gd` 提供原生 Linux 定向回归：case-sensitive 文件系统上的 `Case.json` 与 `case.json` 独立保护/Save As、缺失源保护、dot/绝对别名解锁、历史版本原字节备份，以及字节相同但不同大小写的独立旧版副本。先执行 `--script res://tests/windows/save_linux_identity_test.gd -- probe`，此阶段不加载 `BuildState` 或写 fixture；宿主复核唯一 `SAVE_QA_GATE`、退出码和实际 `OS.get_user_data_dir()` 后，才能给后续子进程设置 `GODOT_SAVE_QA_PROBE_VERIFIED=<token>` 并运行不带 `probe` 的测试。

必须使用全新 Linux 工程与唯一 sandbox，项目名 `Linux Save QA <token>`、`use_custom_user_dir=true`、`custom_user_dir_name="存档 沙箱 <token>"`；子进程的 XDG_DATA_HOME、XDG_CONFIG_HOME、XDG_CACHE_HOME 都位于该 sandbox。环境元数据 `GODOT_SAVE_QA_ROOT`、`GODOT_SAVE_QA_PROJECT`、`GODOT_SAVE_QA_USERDATA`、`GODOT_SAVE_QA_TOKEN` 必须与实测路径完全相符。保留 HOME，源模型及 JSON 依赖只复制进最小工程，禁用 autoload、plugin 和 editor/import。测试 userdata 应在原生大小写敏感文件系统，而非未经证实的 Windows 挂载位置；检查全部异常日志和完成标记。

本机 WSL Ubuntu 未找到已安装 Linux Godot，未额外下载或安装。该脚本已用 Godot 4.6.3 编译并证实在 Windows 上返回 78、在加载模型前拒绝执行；**Linux 原生运行尚未完成**，需由主集成复用已有 Linux 运行时完成，不能把 Windows 的平台拒绝当作 Linux 通过证据。

游戏内的存档提示、真实成品 GUI 验收仍需人工解锁后的人工操作；本 headless 任务没有执行也未绕过锁屏。
