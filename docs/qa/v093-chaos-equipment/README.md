# v0.93 指环混沌抗性供给与 schema51 存档

## 交付范围

- 现有 `nine_slot_etched_ring` 新增一个 `ring_voidward` 后缀，stat/group 均为 `chaos_resistance`，仅此底材可用。T1/T2/T3 整数百分比 ticks 为 8–12 / 13–18 / 19–25，物品等级门槛为 1/8/16，权重为 100/60/30。
- 所有 ticks 只经 `Catalog.affix_stat_value()` 的 percent 路径除以100一次；装备提供原始抗性，不提供最大混抗加值。现有两枚指环最多提供50%原始混抗，机制上限75%由 Defense 单独处理。
- `build_nine_slot_v51` 只在既有五底材、十五family之后追加新family；`canonical_v51` 只替换原30%九槽池。旧命名池、旧词汇1–50及原metadata顺序保留。
- 新掉落和当前主动制作使用51词汇。既有回收、校准、附魔、升格、增补、重铸及四个定向目标保持原操作和经济；未增加槽位或扩张旧family的eligible范围。
- `_stats_for()` 仅在实际装备含 `chaos_resistance` 时累加该字段，最后脱下时回到旧完整stats形状。`get_chaos_resistance_profile()` 使用最终stats调用统一Defense入口。
- schema50先完整冻结验证，再备份原字节，原子提交schema51。迁移仅改变version，不重掷装备，不赠材料、物品或天赋点；源天赋执行策略仍为49。
- `FourthMapMigration` 固定为49→50并以 `reason_v50()` 验证，内置默认构筑继续走完整旧迁移链至51。

## 本次验证

Godot 4.6.3，根线程统一完成首次import后，只执行以下两份定向测试；每份使用独立 `/tmp/godot-m1-v093-equipment-*` XDG目录。

| 测试 | 检查 | 失败 | 本次耗时 |
|---|---:|---:|---:|
| chaos_resistance_equipment_test.gd | 3961 | 0 | 4.849s |
| chaos_resistance_migration_test.gd | 198 | 0 | 24.458s |

纯规则测试包含652组旧物品和后续RNG状态对照、500组显式旧制作计划对照；检查每个旧base/family/pool/loot profile的完整序列化metadata顺序。冻结oracle来自897dbfc，四个文件仅移除全局class_name并重定向相互preload；原始文件SHA256见 `tests/fixtures/chaos_v50_frozen/provenance.json`。

装备供给覆盖六个等级边界、三个tier自然见证、当前掉落dispatch、四类主动制作获得新family、校准保留family/tier、装备约束、非法ticks/跨底材/重复group、魔法单后缀及稀有三后缀容量。

存档使用已落盘真实Main v091 schema50存档 `docs/qa/v091-root-ui/main-after-reforge.json`，验证原字节备份、仅version变化、旧模型stats/施法/装备/钱包保持、当前重开无写入。新family不能混入旧schema；恶意类型、未知字段、非法旅程/天赋/位置/绑定/账本都在callback和写盘之前拒绝。备份失败、备份冲突、外部改写、写盘失败均保持内存与源文件，并覆盖安全重试及49→50→51单次写入链。

真实模型以受控测试夹具放入两枚25%指环，走实际穿戴、落盘、重开、脱下流程：0→25→50→25→0%，最后stats与原始基线完全一致且不含空混抗字段。六项既有制作逐一检查取消不扣费、写盘失败不扣费、同报价重试只提交一次、再确认不能重复扣费和落盘重开一致。

这份证据只覆盖装备、存档和模型经济；真实Main战斗、地图遭遇、UI及可视效果由其他v093定向报告负责。未宣称全历史回归或发布验收。

## 可复用测试夹具

`tests/chaos_resistance_equipment_test.gd` 提供 `static legal_ring(uid, tier=3, value=25)` 和 `static legal_rare_ring(uid)`。前者返回合法魔法单后缀指环；后者返回合法三前缀、混沌/火/冰三后缀的六词缀指环，不赠送材料、不改变生产奖励。

## 证据

- `run-result.json`：exit code、耗时和隔离目录
- `chaos_resistance_equipment_test.json`：统计及各等级自然生成见证
- `chaos_resistance_migration_test.json`：迁移统计及真实源存档摘要
- 对应 `.log`：完整运行输出
- `tested-inputs.json`：本责任范围生产、测试、冻结oracle和源存档SHA256

## 收口增补：冻结旧存档的特殊遭遇词汇

读审发现旧schema50的旅程验证会使用当前MapCatalog，新增 `chaos_patrol` 因而也可能被伪造旧档借用。`Rules._reason()` 现在先保留原有旅程验证及错误顺序，再对schema≤50的非空active_run明确拒绝此新增ID；当前schema51仍可保存该遭遇。源天赋49、旧装备词汇46和既有合法旧档都不变。

仅运行新增的 `chaos_resistance_legacy_journey_gate_test.gd`：22项检查、0失败，10.103秒，未重复import或重跑上述4159项。短测验证霜纹/雷纹的合法schema50进行中地图仍原值迁移、旧档蚀影巡逻在decode/migration/callback及写盘之前拒绝、原字节与活内存不变，当前51蚀影巡逻可无改写重开。

`tested-inputs.json` 保留初次4159项的实际输入快照；最终Rules门禁及本短测输入哈希在 `legacy-journey-gate-tested-inputs.json`，结果和完整日志分别为 `legacy-journey-gate-result.json`、`legacy-journey-gate.json`、`legacy-journey-gate.log`。
