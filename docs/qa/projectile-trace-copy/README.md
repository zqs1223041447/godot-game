# 避免深复制战斗记录最终丢弃的事件数据

每个投射物事件写入 `combat_trace` 时，旧实现先深复制完整事件，再删除顶层 `snapshot`、`payload`。正式探索地图的受控采样确认事件结算是 CPU 热点。本次只把记录拷贝改为：浅复制事件字典，删除副本中的这两个字段，再深复制保留内容。完整原始事件继续用于伤害结算。

基线：`dbdc846e21e70477c98516562bf18273b2ebcc95`。独立分支：`codex/projectile-trace-copy`，待审，不合入 main。生产改动仅 `scripts/main.gd`，没有修改 schema、数值、模型、存档、调度、伤害或随机调用。

## 实际调用链及边界

`Main.tick`（627 行）→ `_tick` → `_update_projectiles`（1523 行）→ `ProjectileRuntime.advance` → `_settle_projectile_events`（1534 行）→ 写入 `combat_trace`（1567 行附近）。随后仍以原始事件的 `payload`、`snapshot` 和事件本体调用 `_apply_damage_packet`。

顶层事件不被修改，记录字段、插入顺序、嵌套容器隔离和最近 96 条的裁剪规则均保持原样。不会递归删除嵌套数据中同名的 `snapshot` 或 `payload`。本次未触及已存在的每批命中查表、空间索引、工作队列排序跳过等优化。

## 已保存的原始诊断

`baseline/` 原样保存优化前的报告、原始脚本、三份日志、JSON 和核验证据；BIN 仅用确定性 gzip 压缩，解压字节未变。该目录的 README 是当时的历史结论（“尚未实施、等待授权”），本文件说明随后获授权的实现与结果。

原始基准是当前正式破碎遗迹 I，37 个原生敌人（36 普通根敌人＋1 Boss）、180 个受控近接触龙卷母箭/步、24×1/60 秒。保留原始地图位置、两面碰撞墙和 AI；玩家受保护、出生保护由夹具移除，关闭自动攻击，无辅助/状态伤害/击杀/奖励。seed 为 500050 和 500051。受控弹幕不是自然玩家吞吐。本次复用同一输入，不增加场景矩阵。

## 有限验证

- `tests/projectile_trace_copy_test.gd`：**159 checks，0 failures**。执行真实 `_settle_projectile_events`，隔离下游副作用来检查 hit/explosion/terrain_hit/return_started/split/terminated/spawn_rejected/evaded 的记录边界；每种类型都与旧拷贝算法逐字节及键顺序比较，检查输入不变、双向嵌套修改隔离、PackedArray、仅排除顶层字段，以及缺失字段和 110 个事件裁剪到 96 条。hit 还检查原始事件、payload、snapshot 对象身份传给下游。
- 既有 `tests/projectile_hit_lookup_test.gd`：**10 checks，0 failures**，覆盖重复/缺失 ID、数组替换、增员和实时目标引用。
- `tools/diagnostics/projectile_trace_copy_profile.gd`：在同一进程加载修改前及修改后完整 Main 源码，仅添加相同计时包装。两轮独立初始状态，每轮 24 步，逐步交错 before/after 顺序，第二轮反转首个顺序；总计 48 对，**0 failures**。原伤害函数、事件顺序和模型全部真实执行。
- 全部 48 对观察文件逐字节相等，两侧各步哈希也全部等于此前独立无插桩生产基准的对应步。四份最终观察文件解压后全部逐字节等于 `baseline/control.bin.gz`。
- 最终观察 1,124,484 字节，SHA256 `910e4495e87635ed7a2d4eae74bf6d0abe35505b61c55f55e67ef0fe7f7fb811`。每次 4320 命中、0 击杀、伤害 `323.99999999997374`；RNG state `2562738993602066876`；critical draws/events 均 0、state `2380781706045169222`。
- 观察覆盖敌人、投射物、粒子、反馈、拾取物、模型存档状态、地图进度、伤害/战斗/燃烧记录、玩家资源和身份计数。它不是所有引擎内部状态的序列化。

`paired.json` 提供逐步数据、源文件 SHA256、计时与最终状态；`verification.json` 给出逐轮统计及核验结果。比较源 SHA256：before `6850f5c58400f599878b241979a708b66f983ebd80507ed9d180d5c1fa3d873a`，after `710bb8e280abc3331c3caed4dcb0616c20f2063bbe0757c47c3110b561910beb`。

## 测得收益与波动

Godot 4.6.3 stable，Linux headless，INTEL XEON PLATINUM 8573C。测量是主线程脚本阶段墙钟耗时，排除弹幕构造、状态序列化、HUD 展示与绘制。阶段 inclusive 时间相互嵌套，不可相加。

| 指标，ms/步 | 前 | 后 | 说明 |
|---|---:|---:|---|
| 轮 1：结算 self 平均 | 8.215 | 3.703 | 23/24 对下降；配对差中位数 4.620 ms |
| 轮 2：结算 self 平均 | 10.897 | 3.723 | 24/24 对下降；配对差中位数 5.009 ms |
| 合并：结算 self 平均 | 9.556 | 3.713 | 47/48 对下降；平均降低 61.1% |
| 合并：结算 inclusive 平均 | 33.198 | 25.669 | 包含未修改的伤害阶段 |
| 合并：伤害阶段平均 | 23.642 | 21.956 | 未修改；差异包含环境波动 |
| 合并：敌人 AI 平均 | 2.970 | 3.060 | 未修改 |
| 轮 1：tick 平均 | 40.267 | 38.030 | 降低 5.6% |
| 轮 2：tick 平均 | 53.209 | 37.719 | 降低 29.1%，波动较大 |
| 合并：tick 平均 | 46.738 | 37.874 | 不作为稳定总体加速承诺 |
| 合并：tick p95 | 79.600 | 55.645 | 小样本且存在明显尖峰 |

结算 self 排除伤害包子阶段，仍包括记录遍历/计数/查表等开销，因此不是某一行指令的独立微基准。不过只有记录拷贝逻辑发生变化，两轮 self 及其配对差均下降，提供了可重复的局部收益证据。其他未修改阶段也出现时间差，说明环境波动不能忽略。保留这一仅改变拷贝顺序的实现，不把整步均值差全部归因于优化，不宣称实际 Windows FPS 提升，不使用历史 12.73→11.58 ms。

验证没有自然持续生成、返回/分裂弹整条链、燃烧传播、掉落或渲染负载；不同事件的记录语义由上述窄测试覆盖。潜在回归风险主要是意外改动顶层原事件、丢失保留字段、浅共享嵌套数据或改变字段顺序，均有针对性检查。

## 复现

在当前仓库既有 Godot 导入缓存就绪时，先从精确基线取出 Main，然后执行一个有 45 秒上限的交错采样。使用新的临时用户目录；输出路径可改到 `/tmp`。

```bash
git show dbdc846e21e70477c98516562bf18273b2ebcc95:scripts/main.gd > /tmp/trace-copy-baseline-main.gd
timeout 45s env \
  XDG_DATA_HOME=/tmp/godot-exploration-diagnostic-review \
  XDG_CACHE_HOME=/tmp/godot-exploration-diagnostic-review-cache \
  TRACE_COPY_BASELINE_MAIN=/tmp/trace-copy-baseline-main.gd \
  DENSITY_PROFILE_OUT=/tmp/trace-copy-review.json \
  godot --headless --path . --script res://tools/diagnostics/projectile_trace_copy_profile.gd
```

正式进图要求 canonical `user://build_save.json`。脚本只在前缀受保护的隔离 `/tmp` 用户目录内重置自己的夹具文件；两侧初始磁盘内容相同，测量无击杀的 0.4 秒期间不触发保存。不会读取或修改真实玩家存档。

窄测试分别使用独立 `XDG_DATA_HOME` / `XDG_CACHE_HOME` 和 `timeout 30s`，脚本为 `res://tests/projectile_trace_copy_test.gd`、`res://tests/projectile_hit_lookup_test.gd`。

## 被保留的夹具失败记录

`attempt-01/` 中两个窄测试最初未设置隔离 XDG，默认数据目录不可写，Godot 在测试前退出；改为可写隔离目录后通过。该目录还保存交错脚本共用已绑定文件时被已有保存保护拒绝的记录。`attempt-02/` 保存改用不同文件名后被正式进图路径校验拒绝的记录。最终仅在隔离目录重置 canonical 夹具存档，保持所有生产保护原样，成功完成全部对照。两个失败采样均由 45 秒上限终止，未产生有效性能结果，不计入上述统计。
