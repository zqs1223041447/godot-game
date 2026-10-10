# 满池最低优先级特效跳过无结果扫描

基线 main：`fabeeb3af1f8336ead5b49eac4bd40c1f216d37c`。工作分支：`codex/combat-cues-min-priority`。

唯一生产改动是 `scripts/visuals/combat_cues.gd`：满池且传入优先级为目录下界0时，跳过不可能命中的“寻找更低优先级”扫描，继续原有同优先级替换。`impact` / `death` 属于该下界；1、2级仍先选数组中第一个**严格更低**项，无此项才找第一个相等项，不能合并成一次“小于等于”搜索。

保留原数组删除/追加次序、存活项顺序、输入校验、拒绝时不消耗ID、`dropped`含义和过期过滤。新增目录下界常量及测试约束：所有可发射种类必须有优先级，目录最小值必须等于0。没有改模型、schema、存档、数值、RNG、伤害或绘制代码。

恢复环境的旧检出引用已消失的临时Git对象库，无法完整读取基线。本批在 `/workspace/godot-cues-scan` 新建隔离检出，未修写旧检出或原环境WIP。仓库及上级未发现适用的 AGENTS.md / .agents/skills。

## 有限语义验证

- `tests/combat_cues_min_priority_test.gd`：**1237项，0失败**。动态执行逐字保存的基线源码 `baseline.gd.txt` 与候选源码，比较返回ID及 `[cues,next_id,dropped]` 序列化字节。覆盖7种满池布局×13种目录类型、低于容量/到达容量/溢出、非法输入、重置及无效/边界/完全过期时间；另明确断言高优先级选择第一个严格更低项，保留更早相等项和更晚低项。
- 原有 `tests/combat_cues_test.gd`：**1046项，0失败**。原测试未修改。
- 原有 `tests/combat_cues_integration_test.gd` **未完成通过**：其显式 legacy `BuildState` 在当前 Main 启动时缺少 `normal_journey` / `normal_pending_rewards`，后续首次有效施放断言失败并访问空特效数组。候选运行由30秒上限结束；临时恢复逐字基线特效源码后以10秒上限复核，两个完整日志逐字相同，均exit124。候选源码随后原样恢复。保留两份日志，不把此失败计入成功、不为本批改动模型或扩修旧夹具。

## 正式地图交替对照

`tools/diagnostics/combat_cues_min_priority_profile.gd` 复用现有 `projectile_trace_copy_profile` 的正式地图构造和相同 Main 计时包装。在同一 Main 中分别放入基线/候选特效池，各自的 `emit_cue` 使用完全相同的计时包装。既有 `exploration_density_profile.observe()` 的全部战斗/RNG观察保持，并在本工具覆盖方法中**增加完整 visual_cues.cues、next_id、dropped**；没有修改旧工具的历史观察格式。

场景仍为正式破碎遗迹I：37个原生敌人、每步180个受控近接触龙卷carrier、24×1/60秒，两轮独立初始状态；每步交替执行顺序，第二轮反转首个顺序。保留原地图碰撞和AI，玩家受保护，移除夹具出生保护，关闭自动施放，无辅助/状态伤害/击杀/奖励。这不是自然玩家吞吐。计时排除carrier构造、观察序列化、HUD与绘制；嵌套阶段不可相加。

**48/48对逐步观察字节相同，0失败**，每轮4224次满池最低优先级调用，两侧调用次数完全一致。四份最终BIN均为1,156,840字节，SHA256：`5bcb991fb8d8595153ce1c40065fb7f1ee5342a1a151a8df4ed12882133012c3`，用确定性gzip保存，解压字节不变。最终每侧4320次hit、0击杀、伤害323.99999999997374、96条cue、next_id4321、dropped4224；RNG state为2562738993602066876，critical state2380781706045169222且draws/events均0。

运行环境：Godot 4.6.3 stable，Linux headless；CPU型号见 `paired.json`。

| 24步均值，ms/步 | 前 | 后 | 配对结果 |
|---|---:|---:|---|
| 轮1：emit_cue累计 | 4.543 | 1.499 | 24/24下降，节省中位数3.004ms |
| 轮2：emit_cue累计 | 4.474 | 1.506 | 24/24下降，节省中位数3.005ms |
| 轮1：整步tick | 32.049 | 30.029 | 含其他未修改阶段和环境波动 |
| 轮2：整步tick | 31.929 | 28.709 | 含其他未修改阶段和环境波动 |

特效入池阶段两轮分别减少约67.0%、66.3%，为可重复局部收益。该指标包含整个emit_cue及计时包装，不是单行指令耗时；新旧包装相同。整步尤其受尖峰影响，不把均值差全归因于此优化，不承诺Windows FPS收益。不运行600秒检测、全套回归、Windows导出或封包。

## 复现

在导入缓存就绪的项目中使用新的隔离临时目录：

```bash
timeout 30s env XDG_DATA_HOME=/tmp/godot-cues-review-unit XDG_CACHE_HOME=/tmp/godot-cues-review-unit-cache CUES_TEST_OUT=/tmp/cues-review-unit.json godot --headless --path . --script res://tests/combat_cues_min_priority_test.gd
timeout 30s env XDG_DATA_HOME=/tmp/godot-cues-review-existing XDG_CACHE_HOME=/tmp/godot-cues-review-existing-cache godot --headless --path . --script res://tests/combat_cues_test.gd
timeout 45s env XDG_DATA_HOME=/tmp/godot-exploration-diagnostic-cues-review XDG_CACHE_HOME=/tmp/godot-exploration-diagnostic-cues-review-cache DENSITY_PROFILE_OUT=/tmp/cues-review-paired.json godot --headless --path . --script res://tools/diagnostics/combat_cues_min_priority_profile.gd
```

正式地图工具沿用受保护的 `/tmp/godot-exploration-diagnostic-` 前缀及canonical临时存档夹具，不读写真实玩家存档。源指纹、逐步时间、完整状态哈希、调用数在 `paired.json` / `verification.json`。

## 后续授权的 canonical 集成补证

`tests/canonical_combat_cues_integration_test.gd`：**37项，0失败**，Godot退出0，无引擎/脚本错误，详见 `canonical-integration-02.json` / `.log`。复用现有正式地图构造器及关闭计时的 Main 包装，真实 canonical 模型在正式破碎遗迹I中持有37个注册敌人；从已有技能组选择可编译的投射物宝石，不赠送或新建技能。

- 实际 `cast_group` 检查魔力不足、背包阻塞、冷却和满投射物容量拒绝。逐字节对照战斗状态、RNG、资源、冷却、存档/保存计数和完整特效池/ID/丢弃计数；合法施放产生一次对应技能/位置的cast特效，并支付编译所得魔力及冷却。
- 实际 `hit_player_components` 验证生命及全护盾承伤各产生一次hurt，以及无敌期间拒绝不新增特效。实际敌人结算验证shielded/unshielded impact和真实target_id。
- 在地图中选取已注册normal稀有度根敌人，通过实际伤害/进度事务击杀，验证根击杀进度、奖励击杀和impact→death顺序；重复尸体伤害/死亡结算不新增特效、奖励、随机消耗或保存。
- 实际 `_update_effects` 先过期短寿命impact并保留death，再全部清空；next_id与dropped不变，资源、模型、磁盘、RNG和冷却不变。

资源、目标血盾和容量为显式受控夹具；满容量使用已合法创建投射物的副本，重复ID期间不执行模拟。伤害消费者测试使用已有 `_damage_enemy` 已结算伤害入口，不宣称完整技能伤害/命中计算覆盖。首轮 `canonical-integration-01` 把稀有度条件误写为生成上下文 `ordinary`，未找到目标；改为目录值 `normal` 后通过。保留该轮25项/1失败及旧legacy失败记录，不合并成通过数量。本次补证只改测试与QA，优化生产代码保持 `7424524` 原样。

复现：

```bash
timeout 30s env XDG_DATA_HOME=/tmp/godot-exploration-diagnostic-canonical-cues-review XDG_CACHE_HOME=/tmp/godot-exploration-diagnostic-canonical-cues-review-cache CUES_CANONICAL_OUT=/tmp/canonical-cues-review.json godot --headless --path . --script res://tests/canonical_combat_cues_integration_test.gd
```

## 下一项可执行非模型缺口

本批尚未补回真实龙卷投射物的split→return→explosion特效集成链。旧 `combat_cues_integration_test.gd` 中对应断言仍被legacy启动失败阻断，新增37项不包含这一链路。下一项可用当前canonical合法技能/装备夹具运行真实投射物推进，检查分裂/返回/自然终止爆炸的特效数量、来源ID和顺序，以及取消投射物不伪造自然终止爆炸。限定测试/QA，不改模型、伤害或视觉实现；本批不夹带该实现。
