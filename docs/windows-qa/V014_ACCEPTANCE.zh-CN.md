# v0.14 Windows headless 综合验收

2026-10-02 在 Windows 上完成两次明确版本的实际运行：
核心综合验收对应 `0db7a1bd1d9d02ecb5db7df42fd475f8266ca650`，19,643 项断言、0 个功能失败；
最终 890 字体复测对应 `fdff527230cbab1b2e17f035a94f55efbd7d75c5`，5,103 项断言、0 个功能失败。
**两次功能结果均通过，严格日志验收均未通过。**
两版差异仅为 7 个字体、字体测试和说明文件；`scripts`、`scenes`、`data`、`project.godot` 的 Git diff 为空。
因此存档、路径与机制证据沿用确切核心 SHA，最新字体采用最终 SHA 的实际 Windows 结果。
本次新增内容仅为 `tests/windows/v014_*` 和本文；未修改生产代码或合并 main/release。

## 版本与实际结果

| 项目 | 结果 |
| --- | --- |
| 最新生产版本 | v0.14.0；存档 schema10；`fdff527230cbab1b2e17f035a94f55efbd7d75c5` |
| 核心综合证据版本 | `0db7a1bd1d9d02ecb5db7df42fd475f8266ca650` |
| 已集成路径修复 | `fed036e05c2972f456d6ccf6110f3086f411ace3` |
| 已集成字体修复 | `405ebf71efbe602524381baea01353b382fd4d90` |
| Godot | `4.6.3.stable.official.7d41c59c4`；复用已有 Windows console/engine 配对 |
| 核心综合运行 UTC | 2026-10-02 16:51:00.6656309Z 至 16:52:09.7087941Z |
| 最终字体运行 UTC | 2026-10-02 16:58:03.1270536Z 至 16:58:41.1324309Z |
| 功能结果 | `functional_checks_passed=true`；`status=passed-with-system-errors` |
| 本次综合脚本 | 5,134 项，0 失败；6 个用例全部完成 |
| 已有相关回归 | 14,509 项，0 失败；11 个套件全部完成 |
| 最终字体复测 | 5,103 项，0 失败；890 字符/769 汉字/1,780 原生映射 |
| 严格结果 | `strict_log_clean=false`；本次启用了 `-StrictLogs` |
| 严格出口 | 脚本 `runner_exit_code=3`；外层命令工具回报非零 1 |
| 代码/运行时/调用环境 | `source_resources_unchanged`、`source_runtime_unchanged`、`parent_environment_unchanged` 均为 true |

## 可复现入口与隔离证明

从仓库根目录使用 PowerShell 7 运行；需要现有 Godot 4.6.3、Python 3.9+ 和 fontTools。
入口不会下载或安装依赖。

```powershell
pwsh -NoProfile -File .\tests\windows\v014_acceptance.ps1 `
  -GodotBin 'C:\Users\ZQS\Documents\Codex\2026-10-02\task-3\runtime\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe' `
  -ExpectedSourceSha 0db7a1bd1d9d02ecb5db7df42fd475f8266ca650 `
  -SandboxParent 'C:\Users\ZQS\Documents\Codex\2026-10-03\task-2\qa-runs' `
  -StrictLogs
```

以上命令复现核心综合验收。以最新 SHA 运行以下范围，可只复测最终字体：

```powershell
pwsh -NoProfile -File .\tests\windows\v014_acceptance.ps1 `
  -GodotBin 'C:\Users\ZQS\Documents\Codex\2026-10-02\task-3\runtime\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe' `
  -ExpectedSourceSha fdff527230cbab1b2e17f035a94f55efbd7d75c5 `
  -SandboxParent 'C:\Users\ZQS\Documents\Codex\2026-10-03\task-2\qa-runs' `
  -FontOnly -StrictLogs
```

入口要求 checkout 的生产文件与对应 `ExpectedSourceSha` 相同。最新 checkout 直接运行旧 SHA 的命令会按设计拒绝；
如需重跑旧版，可在独立目录检出旧生产 SHA 并仅带入这些 QA 文件。
`-FontOnly` 的 `validation_scope=font-only`，不把字体验证宣称为最新版本的全量核心重跑；该模式在脚本中不加载 BuildState 或启动主场景。
`-PrepareOnly` 仅执行最小项目探针和负向探针。
不传 `-StrictLogs` 时，已知系统证书错误仍原样记录，功能通过可返回 0；严格模式保留同一功能结果并返回 3。
脚本或导入错误、断言失败、不完整用例、路径隔离失败均返回非零。

隔离流程：

1. 对照指定 SHA 检查所有生产文件；只容许规定的 QA 文件差异。拒绝路径中的 reparse point。
2. 在新的唯一根目录复制现有 console/engine 二进制，核对 SHA256，并仅在该复制目录创建 `_sc_`，使编辑器数据也位于沙箱。
3. 运行无生产 preload、无主场景、无 autoload 的最小项目。Godot 报告 `OS.get_user_data_dir()` 与 `user://`，PowerShell 独立解析路径并要求精确等于预期目录。
4. 将预期目录故意改成 `mismatch`；探针实际返回 78，门禁拒绝。此前没有复制或加载 BuildState。
5. 门禁通过后才复制生产资源。只在副本加入 custom userdata 与禁用文件日志的设置；再次探针后才导入和加载生产代码。
6. 每个已有回归套件使用新的 userdata，并在执行前重做实际探针。APPDATA/LOCALAPPDATA/TEMP/TMP 只写入子进程环境。

本次最小探针的实际唯一目录：

```text
C:/Users/ZQS/Documents/Codex/2026-10-03/task-2/qa-runs/godot-v014-qa-756eddcd14f34244a64b164c67e2b15e/roaming/存档 沙箱 756eddcd14f34244a64b164c67e2b15e-primary
```

实际中文项目目录为同一根下的 `中文 工程`；原始 Godot 安装目录已有的 `_sc_` 和编辑器目录未被使用或修改。
全部进程使用 headless/隐藏窗口；没有 GUI 输入、解锁或安全设置变更。

## 存档与路径结果

- 从既有真实历史 fixture `local_weapon_v8_scene.json`、`pierce_v9_build.json` 验证 v8/v9→v10，未用当前快照伪造历史版本。
- 2 个版本 × BOM 有/无 × LF/CRLF × 绝对大写/带 `子目录/.././` 的大写路径，共 16 组迁移。加载只更新内存；首次覆盖前保留完全相同的原始字节备份。
- 全量构筑对照原 fixture，仅规范版本与辅助排序；装备 ID/间隔/掷值、旧辅助、天赋、特殊珠宝、背包位置均保留。
- Save As 保留待备份源；后续 v10 保存/载入不重复迁移，且不改写第一份备份。
- 未来 v11 以及在旧 v8/v9 注入 `pierce` 的无效存档均拒绝加载且不改内存。`user://`、绝对、大写、点路径与反斜杠别名全部阻止覆盖，原字节不变且不产生 `.tmp` 或迁移备份。
- 成功通过大写别名加载外部恢复的有效存档，可清除同一源的保护。
- 已存在且字节不同的 v9 备份返回 `ERR_ALREADY_EXISTS`；加载后源被外部替换返回 `ERR_FILE_ALREADY_IN_USE`。大写/点路径别名不能绕过这两种保护。
- 真实 `main.tscn` 启动读取 BOM/CRLF v9；首次真实辅助事务自动保存 schema10，生成精确原字节备份，重新载入保留贯穿、原武器掷值与特殊珠宝。

## 保存后真实施法公式

12 组构筑均经真实辅助事务→schema10 保存→大写路径载入→主场景启动→`cast_skill`→碰撞结算。
两个双辅助组合均验证反向输入顺序。
裸构筑基础伤害为 18；期望值使用独立字面公式，误差要求小于 `0.0001`。

| 技能/辅助 | 实际法力消耗 | 实际初始弹体数 | 实际剩余穿透初值 | 单次目标扣血 |
| --- | ---: | ---: | ---: | ---: |
| bolt / 无 | 7 | 3 | 1 | 28.8 |
| bolt / pierce | 8.4 | 3 | 3 | 24.48 |
| bolt / pierce+volley | 10.92 | 5 | 3 | 19.584 |
| bolt / pierce+focus | 10.08 | 3 | 3 | 30.6 |
| frost / 无 | 16 | 5 | 2 | 15.3 |
| frost / pierce | 19.2 | 5 | 4 | 13.005 |
| frost / pierce+volley | 24.96 | 7 | 4 | 10.404 |
| frost / pierce+focus | 23.04 | 5 | 4 | 16.25625 |

`pierce` 使投射物命中伤害乘 0.85、法力乘 1.20、有限穿透 +2；volley/focus 各自只作用一次。
实际冷却仍为 bolt 0.8s、frost 4s；独立二次爆炸伤害仍为 `18 × 0.9`。
同一保存后载入的单辅助构筑面对 6 个顺序目标时，中心弹体实际结算 bolt 4 次、frost 5 次，之后以 `hit_consumed` 结束且穿透归零；超出预算的目标扣血为 0。

## 中文字体与已有回归

本节结果来自最终生产 SHA `fdff527230cbab1b2e17f035a94f55efbd7d75c5` 的 `-FontOnly -StrictLogs` 实际运行。
最终内置字体 SHA256：`8c522b1e7139e8a5768e5e88ea6a74dbd64ec7dbf31f1a83ca005840cb50aeac`，337,516 字节。
复用已集成的 `tools/check_font_coverage.py`，检查 48 个运行时文件及固定制作文案；QA 副本的项目设置用原始 `project.godot` 精确字节替换后再收集文字，避免把沙箱目录名算作游戏文案。

- 890 个映射；当前所需 872 个可打印字符，其中 769 个汉字；缺失汉字/其他要求字符、丢失基线、空汉字轮廓均为 0。
- 874 个已有基线字符的轮廓/进位与布局指标保持一致，字体家族、生成哈希和许可哈希通过。
- Godot 加载内置 FontFile 后关闭系统回退、清空备用字体并要求只有 1 个 RID。实际 `get_supported_chars()` 为 890；全部 890 字符分别在 16px/19px 验证原生 glyph index，共 1,780 个映射；769 个汉字在两种字号验证正的字符进位。
- `⌁ U+2301`、`◈ U+25C8` 仍是已记录的原字体符号缺口，不是汉字；本次没有宣称 strict-symbols 或 GUI 栅格视觉验收通过。
- headless 检查证明原生映射和度量；`visual_rendering_verified=false`。

此前 `0db7a1bd` 核心综合运行的字体为 874 映射、753 汉字、1,506 原生映射；该旧统计不作为最新字体结论。
核心报告记录当轮 QA 脚本的实际哈希；此后新增 `FontOnly` 范围并扩大原生映射检查到全部支持字符，存档与真实施法断言未改。
重跑当前入口时断言数可能随新增字体检查变化，不改变上述实际留存计数。

已有 11 个套件在各自隔离 userdata 中运行：

| 套件 | 通过断言 |
| --- | ---: |
| projectile_support_rules | 999 |
| skill_compiler | 319 |
| skill_support_state | 179 |
| skill_support_integration | 733 |
| local_weapon_compiler | 524 |
| local_weapon_state | 115 |
| local_weapon_integration | 1,242 |
| save_guard_integration | 11 |
| combat_pipeline | 305 |
| spatial_collision | 5,357 |
| projectile_schedule | 4,725 |

未重复 Linux 600 秒全量套件。

## 系统证书错误与留存证据

核心综合运行的 29 个步骤中，27 个 Godot 步骤各保留 1 条如下系统错误；
最终字体复测的 7 个步骤中，5 个 Godot 步骤各保留同一条错误。
两次的版本命令和 Python 字体检查没有该错误：

```text
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2570)
```

除该明确单列的系统错误外，脚本/导入/引擎错误为 0。
严格模式实际拒绝通过；本次没有更改证书、安全权限或诊断该系统问题。

核心综合机器报告与 29 份原始 stdout/stderr 日志保留于：

```text
C:\Users\ZQS\Documents\Codex\2026-10-03\task-2\qa-runs\godot-v014-qa-756eddcd14f34244a64b164c67e2b15e\report.json
同一目录下 logs\01-version.log 至 logs\29-projectile-schedule.log
```

核心 `report.json` SHA256：`e668b850105838af089aab6a60af2968361b792e8c97b69df8f4d44dba72c43b`。
最终字体报告与 7 份原始 stdout/stderr 日志保留于：

```text
C:\Users\ZQS\Documents\Codex\2026-10-03\task-2\qa-runs\godot-v014-qa-a32ca40cf4af4cb19fef40a096056159\report.json
同一目录下 logs\01-version.log 至 logs\07-v014-font-runtime.log
```

最终字体 `report.json` SHA256：`c94f14d52e5eaa7d893055d8e3e1185e9ac2a6da6388b06d76bca1eb9e91e21d`。
`validation_scope=font-only`；实际 `source_sha=fdff527230cbab1b2e17f035a94f55efbd7d75c5`。
报告记录每步实际退出码、探针门禁、完整公式、源文件哈希、系统错误列表和原始日志路径。
原始日志留在本地 QA 根目录，不提交到仓库。

现有 console SHA256 为 `63B3B2208819714C9677FBFDD8217C5B7DEE8ECF5F383502E826BC9E2227FF5A`，
配对 engine SHA256 为 `EF90E929BA1A6A4322860285D97F40F4AA349C90329A91B0E8B55B8DF0F4CB00`；副本与源均一致。
