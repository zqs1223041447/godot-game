# 事务隔离回归运行器

`tools/run_transaction_regressions.py` 用 Python 3 标准库顺序运行事务、启动恢复、灼烧正确性与当前 UI 契约的聚焦测试。它不修改生产逻辑，不安装依赖，不导入资源、不启动编辑器、不导出程序，也不运行全仓库历史测试。

## 使用

在已经完成 Godot 资源导入的 Linux dot 工作区执行：

```sh
python3 tools/run_transaction_regressions.py --list
python3 tools/run_transaction_regressions.py --godot /path/to/godot
python3 tools/run_transaction_regressions.py --mode full --godot /path/to/godot
python3 -m unittest discover -s tests -p test_transaction_regression_runner.py -v
```

`--godot` 接收可执行文件路径或 PATH 中的名称，不接收 shell 命令。默认是 `godot`。项目根目录从运行器文件位置确定，不依赖调用者的当前目录。`--timeout` 默认 90 秒，可缩短，不能超过 90 秒；拒绝零值、负值和非有限值。`--list` 只打印用例与基准断言数量，不启动 Godot、不建立存档。

## 覆盖与时间预算

默认 quick 共 15 次独立启动：

- 技能原子事务 108、UI 反馈恢复 19
- 当前 group cast 35、support UI 368、owned gem picker 39
- canonical store 40、gem catalog 598、binding 57
- 返城 free/second_clear 22、paid/second_retry 21、affixed/control 22
- F6 bound/第一次写失败 17、unbound/第二次写失败 17
- 启动恢复 start 27、completed_test 24

显式 full 共 53 次启动：以上八个基础套件，加三种地图夹具 × 六个返城场景（18 次，387 断言），两种绑定状态 × 四个故障边界与无故障控制（10 次，163 断言），以及 safe exit（120 断言）和六个启动恢复场景（152 断言）：start 27、leave 26、test 26、completed_start 25、completed_leave 24、completed_test 24；另有灼烧状态拷贝等价性（892 断言）和结算等价性（58593 断言），以及当前 Help 契约（165 断言）与遭遇 UI 集成（88 断言），再加遭遇独立组件（3918 断言）、暂停菜单键盘滚动（1070 断言）和设置菜单键盘滚动（1025 断言），另加技能绑定焦点默认10行（3303断言）与真实装备11行（3629断言），以及天赋详情焦点（5219断言），这十项仅在 full 中运行。quick/full 预期累计断言为 1414/79988。

quick 是代表性检查，不能替代完整故障矩阵。90 秒是每个子进程的硬上限，15/53 个用例分别最多占用约 1350/4770 秒子进程等待时间，另有启动、读日志和写报告开销；它不是整个 quick 的耗时承诺。不并发抢占资源，不调用旧的全仓库 600 秒套件。已有其他 Godot 性能测量运行时应先协调，避免污染测量。

## 隔离与判定

每次测试通过 `tempfile` 在 `/tmp` 新建专属目录；data/config/cache 均独立。目录前缀遵循真实测试保护契约，包括 `godot-m1-`、`godot-ui-feedback.`、`godot-owned-gem-picker-`、`godot-skill-binding-`、安全退出的 `godot-m1-v099-`、启动恢复的 `godot-startup-recovery.`，以及灼烧两例的 `godot-m1-v050-` / `godot-m1-v063-`。当前 Help 与遭遇 UI 的真实保护条件均为 Linux 且 `OS.get_data_dir()` 以 `/tmp/godot-` 开头，因此复用运行器默认 `godot-m1-transactions-` 前缀，并为每例创建全新的 XDG 目录。暂停与设置键盘滚动测试同样要求 Linux 且数据目录以 `/tmp/godot-` 开头；遭遇独立组件测试没有自己的路径拒绝保护，运行器仍以每次 fresh XDG 隔离其实际存档写入，三例均使用默认前缀。技能绑定两例使用其真实保护条件要求的 `godot-skill-focus-` 前缀；天赋详情使用 `godot-talent-focus-` 前缀。用例结束只删除自己创建的临时存档目录；不接收、更不删除用户指定的存档目录。

每次启动清除上次可能遗留的返城、F6、binding baseline、safe exit 子组开关及报告/截图目的地，以及 `STARTUP_CASE` / `STARTUP_RED_CONTROL` / `BURN_EVIDENCE_DIR`，再显式指定当前场景与报告路径。启动恢复每例明确设置 `STARTUP_CASE`；外层负向控制 `STARTUP_RED_CONTROL=skip_recovery` 不得泄漏到正向验收。暂停与设置的负向控制来自 Godot 显式用户参数 `-- --disable-follow-focus`，不是环境变量；正向运行器不传入该用户参数或分隔符，不添加虚构的环境变量清理。技能绑定与天赋详情也使用同一负向用户参数；正向运行器始终不传 `--disable-follow-focus`。新增每例 `user_args` 默认空元组，仅容量11例设置 `("--capacity11",)`，运行器只在参数非空时追加 `--` 分隔符和参数；容量10和天赋不带分隔符，不通过环境变量选择容量。原进程环境不被修改。测试始终 `--headless`，picker 自身负责当前夹具所需的窗口大小和弹窗设置。

仅结算等价性用例显式设置 `BURN_EVIDENCE_DIR` 为保留证据目录下的 `burn_settlement_equivalence-evidence`；运行器不预建该子目录，由测试原子创建并拒绝已存在的目标。生成的 `results.json` 与日志一起保留，不随 XDG 清理。其他用例不继承该变量；外层进程环境不变。重用同一输出目录会被结算测试拒绝，不覆盖先前的 JSON。

每个用例必须同时满足：

1. 在限制时间内退出，退出码为 0
2. 合并 stdout/stderr 日志没有 `SCRIPT ERROR` 或 `ERROR` 标记
3. 只有一条匹配本套件及场景的结束摘要，摘要可以正确解析
4. 断言数量与上述已验收基准严格一致，失败数为零

`WARNING` 单独收集到每个用例的 `warnings` 字段供审查，不自动作为失败。

因此，输出成功摘要后挂起、返回保护码 78、退出码 0 但出现脚本错误、没有摘要或断言数量下降，都不能通过。数量上升也需要显式核对并更新基准，不能静默接受覆盖变化。超时会终止该次子进程组；随后继续其余独立用例。中断操作会终止正在运行的子进程组并向上传播中断。

## 结果与限制

每轮创建新的 `/tmp/transaction-regressions-*` 证据目录，开始时打印路径。目录保留每个用例的独立 `.log`、测试自身 JSON 输出（如有）、汇总 `report.json`。每完成一个用例即刷新报告，记录场景、实际命令、隔离路径、退出码、耗时、观察到的断言数、通过状态和失败原因。临时存档会被清理，日志中的路径仅供追踪，不承诺可重新读取该存档。

汇总按每个独立用例的唯一摘要累计一次，矩阵之间可能验证相同业务断言，不宣称这些是互不重复的独立需求。`observed_checks` 包括失败进程打印的数量；`accepted_checks` 只累计完全通过的进程，避免把保护拒绝或超时前打印的断言算作验收。报告内 `cases` 是实际完成记录的数量；中断后的部分报告不能当作整轮完成。最终进程在任何一个用例失败时返回 1，全通过返回 0。无法启动 Godot 被记为失败，不会冒充已执行。

运行器的 Python 单元测试只使用小型伪可执行文件，涵盖正常退出、环境隔离、重复运行、错误日志、78、超时、非零退出、可执行文件缺失、摘要缺失/重复/错误计数、JSON 摘要、矩阵总数及启动场景和负向控制的环境污染；这些测试本身不是游戏验收。

基准来源：`docs/qa/20261015-skill-transaction-fix.md`、`20261015-ui-feedback-fix.md`、`20261015-return-fix.md`、`20261015-test-contracts.md`、`20261015-scene-test-recovery.md`、`20261015-picker-test-recovery.md`。本运行器不声称覆盖 Windows 实机画面、FPS、全地图/全词缀或所有历史测试。

## 原始基线验收（2026-10-15 UTC）

当前 dot 工作区、Godot 4.6.3 headless，生产代码恢复为已验收基线后顺序执行：

- quick：13/13 用例通过，1363 次累计断言，子进程累计 64.508 秒
- full：37/37 用例通过，1934 次累计断言，子进程累计 189.931 秒；其中完整返城矩阵 387、F6 矩阵 163、安全退出 120
- 两轮退出码均为 0，所有用例退出码为 0；错误、警告、保护拒绝、超时均为 0
- Python 单元测试 14/14 通过，包含复审新增的负数、分数后缀、额外尾随文本及无摘要保护码诊断
- 独立复审验证了超时会清理伪进程的子进程，没有遗留执行；无需运行真实游戏完成这一验证

完整运行期间复审收紧了摘要语法并调整失败原因优先级，没有改变命令、隔离或等待行为。执行结束后，使用最终版本解析器重新读取全部 50 份日志，逐一核对本用例精确断言数量及零失败，全部通过；不将其称为额外的 50 次游戏执行。

本地原始证据位于 `/tmp/transaction-regressions-nj2mfpze/`（quick）和 `/tmp/transaction-regressions-vycdqcaw/`（full），各含 `report.json`、`final-parser-verification.json` 和逐例日志。临时路径不是远端永久附件；本段保留可复现命令、覆盖及实际结论，不把临时文件的存在当作已提交产物。

## 启动恢复扩展验收（2026-10-15 UTC）

本次只通过运行器的 `cases("full")` 筛选 `startup_` 用例，逐例调用同一 `run_case`，实际新增执行六个 Godot 4.6.3 headless 进程。每例独立 fresh XDG，仍执行严格摘要、精确断言数、错误日志和 90 秒超时校验：

- 六例全部通过，分别为 27 / 26 / 26 / 25 / 24 / 24 项，共 152 次累计断言；子进程累计 23.913 秒
- 外层刻意设置 `STARTUP_CASE=contaminated`、`STARTUP_RED_CONTROL=skip_recovery`；正向场景仍全部通过，证明运行器清除污染后显式指定场景
- 六例退出码均为 0；错误、警告、保护拒绝、超时均为 0
- Python 单元测试 15/15 通过，涵盖非启动用例清除两项启动开关，以及六个启动场景覆盖、目录前缀、精确计数、外层环境保持不变
- 使用当前运行器重新解析原 quick 13 份与 full 37 份日志，共 50 份，逐例匹配原计数、零失败、零退出码和无错误；这是历史证据复核，不是重新运行这 50 个游戏进程

当时 quick/full 矩阵为 15/43 例，预期累计断言数为 1414/2086。新增六例与历史证据联合支持配置基准，但本次未重跑完整 15/43 矩阵，也未重验其他并行修改或 Windows 画面，不把历史日志复核描述为当前生产源码的全量验收。

本地证据：`/tmp/transaction-regressions-startup-a6v7jza4/` 包含新六例日志、`report.json` 与 `historical-log-reparse.json`。这些临时文件不作为远端永久交付物。启动恢复业务夹具详见 `docs/qa/20261015-startup-recovery.md`。

## 灼烧正确性扩展验收（2026-10-15 UTC）

本次仅从 `cases("full")` 筛选两项 `burn_` 用例，使用同一 `run_case` 实际运行两个 Godot 4.6.3 headless 进程：

- 状态拷贝：892 断言、零失败，0.717 秒
- 结算等价性：58593 断言、零失败，5.932 秒
- 两例退出码均为 0，错误、警告、超时均为零；合计 59485 次累计断言
- 外层刻意设置污染的 `BURN_EVIDENCE_DIR`；实际结算报告写入本轮独立持久子目录，清理 XDG 后 JSON 仍存在
- Python 单元测试 17/17 通过；新增 full-only 配置、精确基准、报告目的地隔离、JSON 保留及拒绝已存在目录的检查，保留原有 15 项测试
- 当前解析器复核历史 quick 13、full 37、启动恢复 6 份日志，共 56 份，计数、零失败、原退出码及错误日志校验均通过；这是历史证据复核，没有重新执行这 56 个游戏进程

该次扩展后的 quick/full 配置为 15/45 例，预期累计断言为 1414/61571。本次没有重跑完整 quick 或 full，不把历史日志复核当作当前源码的全矩阵验收。结算测试内置纯规则微基准，但这里仅验收正确性，不作生产性能、帧率或 Windows 实机结论；未运行生产性能基准。

本地证据：`/tmp/transaction-regressions-burn-hxrk2t_p/`，包括两份日志、`report.json`、`historical-log-reparse.json` 及 `burn_settlement_equivalence-evidence/results.json`。临时路径不作为远端永久附件。报告输出保护的独立验收见 `docs/qa/20261015-burn-evidence-isolation.md`。

## 当前 UI 契约扩展验收（2026-10-15 UTC）

本次仅从 `cases("full")` 筛选 `current_help_contract` 和 `encounter_ui_integration`，通过同一 `run_case` 顺序执行两个 Godot 4.6.3 headless 进程，没有资源导入、编辑器启动或性能测量：

- 当前 Help 契约：165 断言、零失败，6.536 秒；唯一摘要前缀为 `Current Help contract:`
- 遭遇 UI 集成：88 断言、零失败，5.081 秒；唯一摘要前缀为 `Encounter UI integration:`
- 两例均使用独立 fresh Linux `/tmp/godot-m1-transactions-*` XDG 目录，退出码 0；错误、警告、保护拒绝、超时均为零，共 253 次累计断言
- 保留原有退出码、错误日志、唯一摘要、精确计数和 90 秒超时规则；遭遇套件自身另有 60 秒失败看门狗，不替代运行器外层硬限制
- Python 单元测试 18/18 通过；新增两例 full-only、脚本/摘要/精确基准、fresh XDG，以及断言数量减少或增加均拒绝的检查，保留原有 17 项测试
- 当前解析器复核历史 quick 13、full 37、启动恢复 6、灼烧 2 份日志，共 58 份；精确计数、零失败、原退出码及无错误校验均通过。这是历史证据复核，没有再次执行这 58 个游戏进程

该次扩展后的 quick/full 配置为 15/47 例，预期累计断言为 1414/61824。本次没有重跑完整 quick 或 full，不把历史日志复核当作当前源码的全矩阵验收。两项 UI 用例验证 headless 信号路径及逻辑布局，不代表 Windows 实机视觉、帧率或性能验收。

本地证据：`/tmp/transaction-regressions-current-ui-yfidjzvd/`，包括两份日志、`report.json` 和 `historical-log-reparse.json`。临时路径不作为远端永久附件。


## 组件与菜单键盘滚动扩展验收（2026-10-15 UTC）

本次仅从 `cases("full")` 筛选新增的三例，通过同一 `run_case` 顺序运行 Godot 4.6.3 headless；没有资源导入、编辑器启动或性能测量：

- `encounter_controls`：3918 断言、零失败，28.261 秒；唯一摘要前缀 `Encounter controls:`
- `pause_keyboard_scroll`：1070 断言、零失败，28.306 秒；唯一摘要前缀 `Pause keyboard scroll:`
- `settings_keyboard_scroll`：1025 断言、零失败，15.916 秒；唯一摘要前缀 `Settings keyboard scroll:`
- 三例均在独立 fresh `/tmp/godot-m1-transactions-*` XDG 目录中运行，退出码均为 0，错误、警告、保护拒绝、超时均为零；共 6013 次累计断言、72.483 秒子进程累计时间
- 保留原有退出码、错误日志、唯一摘要、精确计数与 90 秒超时规则，未更改 `run_case`；套件内组件 70 秒、暂停/设置 75 秒看门狗不替代外层限制
- Python 单元测试 19/19 通过；新增三例 full-only、脚本/摘要/精确计数、fresh XDG 与重复运行隔离、错误计数拒绝，以及正向命令不携带 `--disable-follow-focus` 或 `--` 用户参数分隔符的检查，保留原有 18 项测试

当前 quick/full 配置为 15/50 例，预期累计断言为 1414/67837。本次只实际运行这三个新增游戏用例与 Python 单元测试，未重跑完整 quick/full，也未重跑负向控制或复核历史日志。新增用例覆盖 headless 组件交互、真实菜单输入与逻辑裁剪，不代表 Windows 实机视觉、帧率或性能验收。

本地证据：`/tmp/transaction-regressions-controls-scroll-7jert6xk/`，包含三份日志和 `report.json`；临时 XDG 已清理。这些临时路径不作为远端永久附件。本次运行器集成仅完成本地修改与验收，未提交或发布。


## 技能与天赋焦点扩展验收（2026-10-15 UTC）

仅从 full 配置筛选新增三例，以相同 `run_case`、fresh XDG 和每例90秒限制顺序执行：技能10行3303项（12.718秒）、技能11行3629项（12.962秒）、天赋详情5219项（26.264秒）全部通过；退出码均为0，错误、警告、超时、保护拒绝均为零，共12151次累计断言。Python单元测试20/20通过，新增检查覆盖参数、前缀、精确计数、重复隔离与非零/78假成功拒绝。

当前quick/full配置为15/53例、1414/79988预期断言。本批实际仅执行上述三例，没有完整quick/full重跑或负向Godot控制重跑，不将配置数量当作全套通过。新增每例 `user_args` 默认空，只有容量11追加 `-- --capacity11`，正向不携带负向开关；脚本真实保护前缀分别为 `godot-skill-focus-` 和 `godot-talent-focus-`。

持久核验记录与必要日志见 `docs/qa/focus-runner-20261015/README.zh-CN.md`；原始输出使用fresh临时目录，临时XDG已清理。仅本地修改和验收，未提交或发布；不代表Windows、原生2K、画面像素或性能验收。
