# v095：燃烧防御 profile 短诊断

严格同源验收通过。20 帧 ember 中，`incoming_burn` 内的 `defense_profile`
调用共 76,781 次；函数体窄计时合计 298.180 ms，原调用表达式的宽计时合计
434.022 ms。最高帧仍是零死亡的 frame 0：342 次命中、100 个燃烧、100 个敌人，
却调用了 18,526 次 profile。不能把最高帧归因于死亡。

profile 是可见的部分成本，但本次数据不支持把它说成整个高密度停顿的主要来源。
没有实施候选优化，没有任何生产性能改善结论。

## 绝对耗时与调用数

基线 `eaf298a8cbd22c8387da28da118a15afdcd2afb5`。这些是旁路计时副本中的
`Time.get_ticks_usec()` 窗口，含调度与计时扰动，不是操作系统独占 CPU 时间。
各阶段是包含关系，不能相加。

| ember 20 帧阶段 | 耗时 ms | 次数 |
|---|---:|---:|
| 完整传播燃烧推进 `_advance_proliferating_burns` | 3,719.432 | 943 |
| 完整实结算 `_settle_burn_segments` | 1,839.198 | 1,878 |
| planning `incoming_burn` | 585.016 | 38,382 |
| settlement `incoming_burn` | 611.507 | 38,399 |
| planning profile 函数体窄窗口 | 142.233 | 38,382 |
| settlement profile 函数体窄窗口 | 155.947 | 38,399 |
| planning profile 原调用宽窗口 | 208.051 | 38,382 |
| settlement profile 原调用宽窗口 | 225.971 | 38,399 |
| trace 构造/append/限长 | 242.666 | 38,382 |

所有 76,781 次都是 ordinary monster、数值零 ratio 和 max-fire-bonus 支路。
planning 与 settlement 的 profile 次数分别与该阶段 `incoming_burn` 次数完全相同。
实结算多出的 17 次与死亡边界浮点余量的再次结算路径一致：frame 16 多 12 次、
frame 17 多 5 次。无燃烧 4 帧的上述计数和耗时全为零。

| 事件帧 | clean tick ms | instrumented tick ms | hit | kill | enemy / burn | profile 次数 | profile 窄 / 宽 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0，两边最高帧 | 831.212 | 1,008.622 | 342 | 0 | 100 / 100 | 18,526 | 68.760 / 102.844 |
| 16 | 325.963 | 390.531 | 59 | 13 | 87 / 87 | 6,636 | 26.569 / 36.880 |
| 17 | 184.527 | 219.619 | 36 | 7 | 80 / 80 | 3,299 | 12.199 / 17.511 |

clean ember 总 tick 3,590.827 ms，instrumented 为 4,688.015 ms。clean no-burn
4 帧总 tick 310.748 ms，instrumented 为 313.319 ms。这是同状态测量包装明显增加
CPU 工作后的两个进程，差值不能当作生产改善或精确的固定包装成本。

## profile 占比的边界

- 在 instrumented ember 总 tick 中，窄窗口占 6.36%，宽窗口占 9.26%
- 在 instrumented `incoming_burn` 中，窄窗口占 24.92%，宽窗口占 36.27%
- frame 0 的窄/宽窗口分别占 instrumented tick 的 6.82% / 10.20%
- 若把宽窗口全部当作潜在预算，再除以 clean tick，20 帧为 12.09%，frame 0
  为 12.37%；这只是刻意宽松的归因预算，包含包装开销，不能承诺这种收益
- 生产可得收益的严格下界仍为 0。本次扰动测量无法建立可保证的生产收益上界，
  更无法把窄窗口视为删除字典后必然省下的时间

窄窗口围住原 `defense_profile` 函数体调用，包含验证、返回字典构造与调用/返回，
但不包含调用者构造 `{"fire_resistance": fire_resistance}`。宽窗口围住这条原始
调用表达式，额外包含输入小字典、profile 包装分派、窄窗口的计时与旁路计数。
它也不是单独的分配器采样；不能把全部 profile 时间都称为字典分配时间。

## 保真、范围与故障记录

复用了 `burn_settlement_profile.gd` 的 100 真实目录怪物/180 carrier 夹具、20 次
初始 meteor、固定 RNG、AI/攻击、奖励、玩家保护和 preseed 残留 rings 清理。
所有现有 trait 及功能代码保持启用；本短夹具没有声称覆盖每一种新机制的触发。

生产 Main/Defense 文件未改。QA 副本仅改 Defense preload、加入独立 static Meter
和计时包装；生成器移除包装后能逐字节恢复两份生产源。原表达式、原返回字段和
原函数体均保留。Main 按 planning/settlement 设置计数阶段，Meter 不进入模拟
状态。全部观察捕获、序列化、hash、文件写入都在 tick 计时之外。

保留旧 observe 的每个字段，并补充 freeze/chill/trap、telegraph、feedback
observation 队列/ID、shock/leech/flask 内部时钟、burn 标志、projectile/monster
ID、player/progress/world/map 队列。没有排除路径字段掩盖差异。

| 严格字节比较 | ember | no-burn |
|---|---:|---:|
| 逐帧完整观察集合 | 30,888,452 bytes，相同 | 5,324,164 bytes，相同 |
| 最终保存后完整观察 | 1,491,432 bytes，相同 | 1,331,232 bytes，相同 |
| 最终磁盘存档 | 13,693 bytes，相同 | 12,200 bytes，相同 |

逐帧 SHA-256 也全部一致。二进制比较使用完整 `var_to_bytes` 结果，而非字段投影
或舍入。完整 hash 位于 `verification.json`。

首轮 clean ember 20 帧和最终保存已完成，但同进程第二个 fresh Model 保存同一
路径被当前生产保护拒绝。首次 `ERROR` 即杀进程，instrumented 当时未启动。
经主线程批准，仅为每个 mode 隔离进程/XDG，保持原 `user://build_save.json`，
核验并复用已完成 clean ember，补跑 clean no-burn、instrumented ember 和
instrumented no-burn。三个补充进程均正常结束且没有 ERROR。未重跑 clean ember，
未做 editor import、长样本、完整测试、候选优化、提交或 push。

## 证据与复现工具

- `attribution.json`：逐帧事件、所有阶段绝对耗时/次数、比例边界
- `verification.json`：六份完整二进制/存档的严格比较与 hash
- `clean_completed.json`、`instrumented_completed.json`：合并后的 20+4 帧样本
- `generation_manifest.json`：源文件 hash、原函数体逆变换验证
- `run_manifest.json`：全部进程命令、隔离 XDG、帧范围、退出状态
- `first_attempt_*`、原 `clean.*`：首次失败及已完成 ember 的原始证据
- `main_profiled.gd`、`defense_profiled.gd`、`meter.gd`：诊断实现
- `tools/diagnostics/generate_v095_burn_profile_audit.py`：生成透明副本
- `tools/diagnostics/run_v095_burn_profile_audit.py`：此次经批准的断点续跑；拒绝重复运行
- `tools/diagnostics/summarize_v095_burn_profile_audit.py`：不启动 Godot 的结果汇总

本结果仅适用于当前 headless 短受控场景，不是 Windows 实机帧率验收，也不与旧
v63 的 565 ms 样本直接作性能回归比较。
