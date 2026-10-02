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
| Windows 大小写别名 | 大写绝对路径必须遵守未来版本 guard 和旧版原字节备份约束；当前 v0.13.0 的失败见下文 |

fixtures 在 Git 中保存为普通 UTF-8/LF JSON。`save_fixture.gd` 在沙箱中显式生成 BOM/CRLF 变体，避免 Git 行尾转换破坏预期原字节。比较独立 JSON 记录与模型时，会对两侧重新解析，以排除 JSON 数字 float 与模型 int 的类型差异；模型往返和原文件/备份仍分别做完整快照及原字节比较。

## 判定与日志

runner 同时要求进程退出码、唯一隔离 marker、唯一完成 marker、正检查数和零失败。任何 `SCRIPT ERROR:` 或未分类的 `ERROR:` 都失败，即使 Godot 自身退出 0；生产 bug 的断言错误也不会被忽略。

本机可稳定出现 `ERROR: Failed to read the root certificate store.`。仅这个完整、精确匹配的系统错误单独写入 `system_errors`，保留原始日志和 backtrace，并令 `strict_log_clean=false`。没有修改证书库、关闭 Godot 的错误打印或过滤原始日志。

所有存档检查通过但有该系统错误时，状态为 `passed-with-system-errors`，退出 0。加 `-StrictLogs` 时，全部存档检查完成后仍因系统错误返回失败。其他状态为 `passed` 或 `failed`。本轮由于下面的生产问题返回 `failed`，不是因为证书错误。

## 本机结果与最小生产复现

基线：main v0.13.0，`a4a306a`；Godot `4.6.3.stable.official.7d41c59c4`。2026-10-02 Windows headless 实测：基础存档及文件故障共 **1326 checks / 0 failures**；大小写别名 **14 checks / 3 failures**，共 **1340 checks / 3 failures**。正探针通过，反探针退出 78；调用者环境与源文件没有变化。

生产问题在 `tests/windows/save_path_alias_test.gd` 复现，只有人工 fixture 被写入唯一沙箱：

1. 写入合法结构的未来 v10 源；`load_build(path)` 返回 false，规范路径的 `save_block_reason(path)` 非空。
2. 确认 `ProjectSettings.globalize_path(path).to_upper()` 在 Windows 读取到同一份原字节。
3. 用该大写绝对别名 `save_build(alias)`：实际返回 **OK**，别名 guard 为空，v10 原字节被当前 v9 覆盖。预期为 `ERR_INVALID_DATA` 且原字节不变。
4. 对 v8 fixture 只读迁移后通过同样的大写别名保存：返回 **OK**，但 `.v8-backup.json` **没有创建**。预期在升级前创建原字节备份。

`BuildState` 用未经 Windows 文件身份归一化的 `ProjectSettings.globalize_path(path)` 字符串作为 guard key、迁移源比较值。实测 Windows 文件访问不区分这些路径的大小写，而这些字符串键/比较区分大小写。两种复现都保留在同一失败步骤的 `result.reproductions` 中；三个失败断言阻止 runner 把结果标为通过。

本分支只增加 runner、fixtures、回归测试与本说明，未修改 `scripts/build_state.gd` 或其他生产代码。需要父任务独立修复路径身份比较后，再运行完整 runner。窗口内的存档提示、真实成品 GUI 和人工解锁不属于这次 headless 结果，也未绕过锁屏。
