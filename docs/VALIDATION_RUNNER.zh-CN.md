# v0.13 完整校验的受限并行入口

`tools/validate_parallel.py` 是 Linux 上的可选入口。它读取并审计现有
`tools/validate.sh`，执行同一批 **54 项检查**：一次导入、51 个 GDScript
测试、离线参考目录 Python 测试和完整 300 帧启动。没有修改原入口、游戏
内容或任何检查的随机种子、矩阵、循环次数和启动参数。

## 使用

需要 Python 3.10+、Godot **4.6.3** 标准版和 Linux CPU affinity 支持。默认
两路执行，需要两个允许使用、互不共享 SMT 核心的 CPU。先检查本机允许的
编号；这里的 `0,1` 只是本次云机实际可用的示例。

```bash
python3 -c 'import os; print(sorted(os.sched_getaffinity(0)))'
python3 tools/validate_parallel.py --print-plan
python3 tools/validate_parallel.py --jobs 2 --cpu-set 0,1
python3 tools/validate_parallel.py --jobs 1 --cpu-set 0
python3 -m unittest discover -s tests -p test_validation_runner.py -v
```

`GODOT_BIN` 或 `--godot /absolute/path/to/godot` 可指定引擎。`--project-dir`
可指定工程根目录。`--log-dir /absolute/path/to/log-parent` 指定保存位置的
父目录；每次仍创建唯一子目录，默认放在系统临时目录。一次运行的路径会
打印到终端，runner 不会自动删除日志和隔离存档。

原 `validate.sh` **没有声明进程超时**。计划中的
`declared_timeout_seconds` 均为 `null`；默认执行也不增加超时。需要限制
挂起进程时，可显式传 `--timeout-seconds 900`，其值必须为有限正数，作用
于版本探测和每项检查，报告另存 `effective_timeout_seconds`。这只是运行
截止时间，不会减少样本；被截止的检查记为失败，绝不视为完成或通过。

## 计划审计与执行顺序

已审计基线是 main / `v0.13.0` 的
`a4a306a6d8c14320fce383dccf6ad7ca40836757`，原入口 SHA-256 为
`681a081732260423792a246cfdbcfe3dace43ef8d722e4798e703ce9591959da`。

解析器先核验 shell 初始化、`run_check` 函数、版本命令和成功结尾的已审计
哈希，再逐行解析整个检查区域。只接受本版本实际存在的四种命令形状：
导入、`res://tests/*_test.gd`、固定 Python 参考检查和 `--quit-after 300`。
解析出的检查必须与独立的完整 v0.13 清单逐项计数匹配，而且对应源文件必须
存在并位于工程内。重复、遗漏、未知命令、管道、条件/循环、额外参数、修改
后的 timeout 包装或变化的 shell 函数，都会在启动引擎前拒绝。

`--print-plan` 输出实际源行号、参数、顺序和超时声明，不执行 shell，不把
正则匹配到的一部分脚本当成完整计划。允许完整清单内普通检查重新排序，
执行时采用源文件的新顺序；导入仍必须第一项，300 帧启动必须最后一项。
未来版本或未知脚本结构需先重新审计，当前版本没有自动退回、跳过或强制
执行开关。

版本探测独占执行。之后按原计划顺序启动检查；普通检查最多两个并发，
完成顺序可以不同，最终报告始终按源计划排序。下列检查是**两侧屏障**：
先等待全部前项结束，自身独占运行，结束后才启动后项。

| 序号 | 检查 | 保留的工作与串行原因 |
| --- | --- | --- |
| 1 | `--editor --import` | 导入和生成工程缓存必须先完成 |
| 12 | `local_weapon_budget_test.gd` | 完整合法武器矩阵、92,580 次评估及耗时测量 |
| 26 | `equipment_soak_test.gd` | 36,000 次 tick，600 **模拟秒**，并非 600 秒超时 |
| 38 | `spatial_collision_test.gd` | 原扫描/空间索引完整差分及计时 |
| 39 | `projectile_schedule_test.gd` | 原排序/缓存排序完整差分及计时 |
| 54 | `--quit-after 300` | 完整 300 帧启动 |

同一清单中的源测试若出现直接 `Time.get_ticks_*` 测量，也会保守串行化。
`density_benchmark.gd` 和 `progress_batch_benchmark.gd` 没有出现在原入口，
不计入这次 54 项对照。没有新增按文件名搜索测试、`--only`、跳测或缩样本
模式。

## 存档与 CPU 隔离

每个检查以及版本探测都有不同的绝对路径 `XDG_DATA_HOME`、
`XDG_CONFIG_HOME`、`XDG_CACHE_HOME`，并建立独立 fontconfig 缓存目录。
三个路径仅传给该子进程；不改调用者环境，也不改 `HOME`、`APPDATA`。
Godot 在 Linux 上通过这些变量选择项目数据、编辑器设置和缓存路径，见
[Godot 4.6 数据路径说明](https://docs.godotengine.org/en/4.6/tutorials/io/data_paths.html)。

执行前核验已审计 `project.godot` 的完整哈希，拒绝 `override.cfg`，并拒绝
引擎目录下的 `._sc_` / `_sc_` 自包含模式标记，防止配置绕过 XDG 隔离。
所有检查仍使用同一工程；共享的 `.godot` 导入缓存由第一项串行准备。

每个检查及其线程、后代进程继承单一 CPU affinity。两个普通工作进程使用
不同且非 SMT 同核的 CPU；所有串行计时项使用第一个 CPU。没有设置线程
数、模拟速率或其他会改变检查内容的参数。无法读取 SMT 拓扑时也拒绝两路
执行。`summary.json` 记录使用的 CPU、
线程兄弟拓扑、前后负载、逐 CPU user/system/idle/steal ticks 和 cgroup
CPU 配额/节流计数。亲和性约束自己的校验工作；它不预留宿主 CPU，不能
排除共享云机、宿主调度、工具活动或 cgroup 配额造成的实际干扰。

**Windows 和 macOS 执行均明确拒绝，发生在任何引擎进程启动前。** Windows
尚无经过审计的唯一 userdata 工程隔离，当前版本不使用玩家默认 `user://`，
不重写 `HOME` / `APPDATA`，也没有跨平台强行执行开关。只读
`--print-plan` 可以查看计划。Windows 实机、安全提示和其他需要人工操作
的步骤应由用户醒后处理；本入口不涉及桌面解锁。

## 失败、取消和证据

每项检查分别保存合并 stdout/stderr 的 `check.log`。Godot 检查必须同时满足
**进程退出码为 0**且日志不匹配原入口的
`(^|\s)(SCRIPT ERROR:|ERROR:)` 才通过；Python 参考检查沿用原入口的退出码
门槛。保留 `raw_returncode` 和最终 `exit_code`，不会让零退出码掩盖脚本错误。

普通检查失败或超时后继续执行完整剩余清单，所有失败集中报告。导入失败
时依赖检查全部标为 `not_run`，不声称全量完成。超时先向独立 POSIX 进程组
发送 SIGTERM，0.3 秒后仍存活则 SIGKILL；超时最终码为 124，同时保留原始
进程退出码。SIGINT/SIGTERM 停止新增检查、终止全部在跑进程组，并将剩余
项标为 `not_run`，最终码分别为 130/143。即使引擎先退出，也清理其留存的
后代进程。

`summary.json` 包含完整检查清单、源文件哈希、命令、源行号、CPU、隔离目录、
日志路径、原始/最终退出码、错误日志命中、开始/结束时间、总 wallclock、
失败项和 `complete`。取消或导入失败留下的未执行项同样保留，不用“通过数”
掩盖缺测。一般失败返回源计划中第一项失败的最终码；无失败返回 0；审计或
配置拒绝返回 2。

伪引擎测试以真实子进程覆盖完整清单、最大两进程并发、串行屏障、1 路模式、
独立 data/config/cache 路径和 CPU、正/负退出码、零退出码脚本错误、普通
失败继续、导入/版本失败、超时及后代强杀、SIGINT/SIGTERM 取消、缺失检查
或源文件拒绝、未知 shell 结构、非法上限、Windows/配置/自包含模式拒绝。

## 本次同机全量对照

2026-10-02 UTC，Linux 云机，Godot 4.6.3 官方标准版、Python 3.12.14，CPU
标识为 Intel Xeon Platinum 8573C。允许 CPU 为 0–4；选用 CPU 0、1，已核验
互不共享 SMT 核心。cgroup `cpu.max` 为 `400000 100000`（合计四核配额）。

先以独立 XDG 目录串行预热一次导入，再运行一次未修改的
`validate.sh`（CPU 0），随后运行一次
新入口（CPU 0、1）。原入口通过临时只读观测包装记录每项参数、日志、退出码
和计时；包装不改变检查内容或隔离变量，包装及原 tee 的开销计入原入口
wallclock。新入口时间取自身从 Runner 初始化到全清单完成的单调时钟记录，
不含 CLI 参数/源计划预检的少量开销。两次运行不重叠，不添加测试参数或
减少原有采样；版本探测均单独执行，不计入 54 项。

| 指标 | 原入口 | 新入口，两路 |
| --- | ---: | ---: |
| 全量检查通过 | 54 / 54 | 54 / 54 |
| 最终退出码 | 0 | 0 |
| 49 组日志可提取的断言计数 | 1,933,516 | 1,933,516 |
| 总 wallclock，秒 | 918.128 | 877.406 |
| 完整武器预算回放，秒 | 126.200 | 119.378 |
| 完整 600 秒模拟，秒 | 584.667 | 577.962 |
| 空间差分计时组，秒 | 6.867 | 6.078 |
| 投射物排序计时组，秒 | 5.894 | 5.573 |
| cgroup 节流次数增量 | 0 | 0 |
| cgroup 节流微秒增量 | 0 | 0 |
| CPU 0 steal 增量，ticks | 15,550 | 14,152 |
| CPU 1 steal 增量，ticks | 506 | 2,560 |

完整 54 项名称、启动顺序、检查参数、原始退出码、错误日志门槛和逐项可提取
断言计数均一致。新入口实际峰值为两项检查进程；所有串行项的开始/结束区间
均已核对，与任何其他项无重叠。版本探测加 54 项的三个 XDG 路径全部唯一；
53 个真实 Godot 检查均在各自的 data 路径下生成了项目 userdata 目录，Python
检查也有独立的三个 XDG 路径。

600 秒模拟两次都报告 **186 checks、0 failures、3912 eligible kills、118
issued gear、peak owned 14、peak live 71**，完整武器回放两次都是 340,691
checks、0 failures，未缩减评估矩阵。最终伪引擎测试 **15 项全部通过，无
跳过**，用时 21.791 秒；包括未知 CPU 拓扑拒绝及正常退出后清理留存后代。

steal 的 `SC_CLK_TCK` 为 100：CPU 0 的区间累计 steal 分别为 155.50 秒和
141.52 秒，CPU 1 为 5.06 秒和 25.60 秒。它们是整个 CPU 观察区间的计数，
不能等同于某一检查独占损失的时间。两轮 1/5/15 分钟负载分别从
`0.593/0.142/0.043` 到 `0.953/0.969/0.676`、从
`0.953/0.969/0.676` 到 `1.655/1.250/1.025`。
**宿主 steal 明显非零，计时环境并非独占**；进程亲和性只隔离了本 runner
的校验工作。单次观察、原入口观测开销和上述实际干扰不支持固定提速或
游戏性能提升结论，尤其不能把串行组本身的计时差归因于并行调度。

完整原始证据保存在本次执行环境的 `/tmp/godot-v013-validation-evidence/`：

- `comparison.json`：全量集合、参数、结果与计数对照，CPU 干扰和屏障核验。
- `original-summary.json`、`original/*/check.log`：原入口逐项证据。
- `parallel/validate-parallel-_4osi7un/summary.json` 及各项 `check.log`：新入口证据。
- `unit-tests.log`：最终 15 项伪引擎测试报告。

这些是本次云机的临时保留路径；仓库仅新增 runner、测试和本文件，未把运行
产物提交到仓库。复跑时以终端打印的新目录为准。
