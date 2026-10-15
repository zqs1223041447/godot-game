# 事务隔离回归运行器

`tools/run_transaction_regressions.py` 用 Python 3 标准库顺序运行 PR #14 / #15 已验收的聚焦测试。它不修改生产逻辑，不安装依赖，不导入资源、不启动编辑器、不导出程序，也不运行全仓库历史测试。

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

默认 quick 共 13 次独立启动：

- 技能原子事务 108、UI 反馈恢复 19
- 当前 group cast 35、support UI 368、owned gem picker 39
- canonical store 40、gem catalog 598、binding 57
- 返城 free/second_clear 22、paid/second_retry 21、affixed/control 22
- F6 bound/第一次写失败 17、unbound/第二次写失败 17

显式 full 共 37 次启动：以上八个基础套件，加三种地图夹具 × 六个返城场景（18 次，387 断言），两种绑定状态 × 四个故障边界与无故障控制（10 次，163 断言），以及 safe exit（120 断言）。

quick 是代表性检查，不能替代完整故障矩阵。90 秒是每个子进程的硬上限，13/37 个用例分别最多占用约 1170/3330 秒子进程等待时间，另有启动、读日志和写报告开销；它不是整个 quick 的耗时承诺。不并发抢占资源，不调用旧的全仓库 600 秒套件。已有其他 Godot 性能测量运行时应先协调，避免污染测量。

## 隔离与判定

每次测试通过 `tempfile` 在 `/tmp` 新建专属目录；data/config/cache 均独立。目录前缀遵循真实测试保护契约，包括 `godot-m1-`、`godot-ui-feedback.`、`godot-owned-gem-picker-`、`godot-skill-binding-` 与安全退出的 `godot-m1-v099-`。用例结束只删除自己创建的临时存档目录；不接收、更不删除用户指定的存档目录。

每次启动清除上次可能遗留的返城、F6、binding baseline、safe exit 子组开关及报告/截图目的地，再显式指定当前场景与报告路径。原进程环境不被修改。测试始终 `--headless`，picker 自身负责当前夹具所需的窗口大小和弹窗设置。

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

运行器的 Python 单元测试只使用小型伪可执行文件，涵盖正常退出、环境隔离、重复运行、错误日志、78、超时、非零退出、可执行文件缺失、摘要缺失/重复/错误计数、JSON 摘要及矩阵总数；这些测试本身不是游戏验收。

基准来源：`docs/qa/20261015-skill-transaction-fix.md`、`20261015-ui-feedback-fix.md`、`20261015-return-fix.md`、`20261015-test-contracts.md`、`20261015-scene-test-recovery.md`、`20261015-picker-test-recovery.md`。本运行器不声称覆盖 Windows 实机画面、FPS、全地图/全词缀或所有历史测试。

## 本次验收（2026-10-15 UTC）

当前 dot 工作区、Godot 4.6.3 headless，生产代码恢复为已验收基线后顺序执行：

- quick：13/13 用例通过，1363 次累计断言，子进程累计 64.508 秒
- full：37/37 用例通过，1934 次累计断言，子进程累计 189.931 秒；其中完整返城矩阵 387、F6 矩阵 163、安全退出 120
- 两轮退出码均为 0，所有用例退出码为 0；错误、警告、保护拒绝、超时均为 0
- Python 单元测试 14/14 通过，包含复审新增的负数、分数后缀、额外尾随文本及无摘要保护码诊断
- 独立复审验证了超时会清理伪进程的子进程，没有遗留执行；无需运行真实游戏完成这一验证

完整运行期间复审收紧了摘要语法并调整失败原因优先级，没有改变命令、隔离或等待行为。执行结束后，使用最终版本解析器重新读取全部 50 份日志，逐一核对本用例精确断言数量及零失败，全部通过；不将其称为额外的 50 次游戏执行。

本地原始证据位于 `/tmp/transaction-regressions-nj2mfpze/`（quick）和 `/tmp/transaction-regressions-vycdqcaw/`（full），各含 `report.json`、`final-parser-verification.json` 和逐例日志。临时路径不是远端永久附件；本段保留可复现命令、覆盖及实际结论，不把临时文件的存在当作已提交产物。
