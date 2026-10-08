# 当前探索地图：短 CPU 诊断，未实施优化

基线为本地及远端 `refs/heads/main` 的 `dbdc846e21e70477c98516562bf18273b2ebcc95`。仓库 `/workspace/godot-flask-recovery` 保持干净。本目录位于仓库之外，仅包含诊断脚本、原始日志和证据；没有新增游戏逻辑、提交、推送或导出。

## 输入与范围

- 复用 `tools/diagnostics/latest_density_profile.gd` 的 Meter、TimedArena、summary、SHA 和固定弹幕配方；没有运行旧的多场景矩阵。
- 通过正式 `craft_normal_map` → `start_map` 进入 `broken_ruins` I：36 个普通根敌人和 1 个登记 Boss，保留原始位置、属性、身份、碰撞墙体、AI 和唤醒机制。地图为 exploration 模式、2 面墙。第一个采样步后 37 个敌人均被正常命中唤醒。
- RNG seed 500050；critical seed 500051。在隔离 `/tmp/godot-exploration-diagnostic-*` 用户目录中运行。玩家受保护，关闭自动攻击，夹具仅移除出生保护；不改敌人生命值或伤害结算。每步构造 180 个近接触龙卷母箭，伤害参数 0.075，无辅助。弹幕生成来自既有压力夹具，不代表玩家自然吞吐。
- 固定 24 步，每步 1/60 秒，合计 0.4 秒模拟。包含第一轮唤醒和冷路径图构建；未丢弃预热步。三次依次为插桩 A、无插桩 production 对照、插桩 B；均成功退出。每次有 45 秒外部上限，没有长跑。
- `probe.gd` 只以子类包装原函数计时。记录的是无渲染 `Main.tick()` 主线程阶段墙钟耗时，不包含弹幕构造、状态序列化、HUD 展示、绘制、GPU 或 Windows 帧率；期间没有击杀、掉落、状态伤害、自动保存。不能代表持续密集怪群、返回/分裂弹、传播燃烧或实际 Windows FPS。
- Godot 4.6.3 stable，Linux headless，INTEL XEON PLATINUM 8573C。A 日志存在 Fontconfig 无可写缓存警告，后两次设置隔离 XDG_CACHE_HOME；没有脚本错误。绝对时间明显波动，不应当作稳定性能基线。

## 当前版本结果

单位 ms/步。阶段是嵌套 inclusive 时间，不能纵向相加。

| 指标 | 插桩 A | 插桩 B |
|---|---:|---:|
| tick 平均 | 38.203 | 57.810 |
| tick p95 | 40.454 | 78.396 |
| 投射物阶段（总） | 34.079 | 51.261 |
| 事件结算 | 26.252（68.7% tick） | 39.020（67.5% tick） |
| 伤害包应用（结算子阶段） | 19.197 | 29.128 |
| 敌人资源/反馈（伤害子阶段） | 8.885 | 13.749 |
| 结算 self，排除伤害子阶段 | 7.055 | 9.892 |
| 投射物推进/调度 | 7.657 | 11.739 |
| 敌人 AI | 3.233 | 5.222 |
| 效果更新 | 0.239 | 0.350 |

无插桩对照平均 51.944 ms，p95 73.238 ms，最大 114.898 ms。它也受时间波动影响，不能拿它与插桩均值相减来估算插桩成本，也不能宣称本轮有性能改善。旧的 12.73→11.58 ms 不属于本次结果。

投射物事件结算稳定占约三分之二，是本输入下可信的首要热点。已有优化确实在工作：每步实际接触候选访问 400→343，而全扫描参考计数为 6660；24 步只排序 24 次，跳过 4296 次排序。`Main._settle_projectile_events` 已有每批命中查表，不应重复实现这些旧成果。路线构图只有 4 次（不同半径），不是持续的主要耗时。

## 行为及随机证据

三次的初始观察、全部 24 个逐步观察哈希以及最终 1,124,484 字节观察文件均完全一致。记录包括敌人、投射物、粒子、反馈、拾取物、模型存档状态、地图进度、伤害/战斗/燃烧记录、玩家资源、投射物身份计数及 RNG；这是所记录状态的等价证明，不声称覆盖未序列化的全部引擎内部状态。

- 命中事件：每次 4320；击杀 0；累计伤害 `323.99999999997374`。
- 最终 RNG state：`2562738993602066876`。
- critical checkpoint：draws 0、events 0、state `2380781706045169222`。
- 最终 SHA256：`910e4495e87635ed7a2d4eae74bf6d0abe35505b61c55f55e67ef0fe7f7fb811`。
- 机器可读核验见 `verification.json`；逐步数据见三个 JSON，原始状态见对应 BIN。

## 最小候选，等待下一步授权后再实施

仅考虑 `scripts/main.gd` 的 `_settle_projectile_events` 战斗记录拷贝：当前对每个完整事件执行 `event.duplicate(true)`，随后立即删除 `snapshot` 和 `payload`。候选是先排除这两个不写入记录的字段，再深复制真正保留的内容。保留字段顺序、嵌套容器的独立性、96 条裁剪规则，以及原事件不被修改的保证；不动伤害、反馈、命中顺序、RNG、寻路、存档或调度器。

收益依据是该逻辑每步执行 180 次，位于两次采样均占 17.1%–18.5% tick 的结算 self 阶段，且明确深复制后丢弃较大的技能结构。**未单独测量这几行，self 还包含事件遍历、计数和查表，因此 7.055–9.892 ms 不是可节省时间，收益尚待验证。** 大头伤害/反馈保持原样，选择这个候选是为了限制行为风险。

若批准下一轮：先在隔离工作分支做上述单点改动；用相同固定输入交替做短的修改前/后采样，并对比逐步完整观察与 RNG；补一组小的记录语义验证（hit、explosion、terrain、return、split、terminated、容量拒绝以及保留字段含嵌套容器），确保改动原事件后记录仍独立、字段及顺序完全一致。伤害/暴击及掉落不应增加或减少调用。只在 CPU 证据显示稳定收益且行为一致时保留；若收益淹没在当前波动中，报告无可信收益，不扩大优化范围。

## 复现

在本仓库既有导入缓存就绪时，从新的隔离用户目录运行：

```bash
timeout 45s env \
  XDG_DATA_HOME=/tmp/godot-exploration-diagnostic-fresh \
  XDG_CACHE_HOME=/tmp/godot-exploration-diagnostic-fresh-cache \
  DENSITY_INSTRUMENTED=1 \
  DENSITY_PROFILE_OUT=/workspace/exploration-cpu-diagnostic-dbdc846/fresh.json \
  godot --headless --path /workspace/godot-flask-recovery \
  --script /workspace/exploration-cpu-diagnostic-dbdc846/probe.gd
```

无插桩对照将 `DENSITY_INSTRUMENTED=0`，并使用另一个全新隔离用户目录。保持同一 HEAD。每次覆盖输出前先保留旧证据。
