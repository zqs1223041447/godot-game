# v0.76 源护盾提高与回复：独立怪物供给

当前共28条机制：23条历史定义和3条既有源绑定原样保留，新增 `source_aegis_capacity`、`source_aegis_recovery`。只有普通三物种的当前五槽词池切换到 `source_shield_v3`；历史入口、显式特殊模板、首领和死亡后代保持。

## 精确来源与原子复苏

| 新机制 | 固定源条目（索引从0计数） | 原始行 | 类型化授予 |
| --- | --- | --- | --- |
| `source_aegis_capacity` | `58218:0` | `8% increased maximum Energy Shield` | `max_shield / increased / 0.08` |
| `source_aegis_recovery`（第一条） | `21929:1` | `4% increased maximum Energy Shield` | `max_shield / increased / 0.04` |
| `source_aegis_recovery`（第二条） | `6949:1` | `10% increased Energy Shield Recharge Rate` | `shield_recharge_rate_increased / increased / 0.10` |

玩家和怪物均由当前 `SourceTreeRuntime.line_effect` 取得同样的类型化授予，生产对象系数1.0。储盾仅绑定58218的第一行，不附带其生命或混沌抗性；复苏仅绑定21929与6949各自第二行，不附带护甲或另一条6%护盾提高。两种新身份都不授予更快开始回复、整节点、升华资格或玩家固定护盾/回复。

复苏是一个不可拆分的双行原子包。`source_refs` 与 `source_entries` 均保留两条完整来源，`typed_grants` 保留两种授予，`source_line` 以换行连接两条原文。为单条展示保留的 `source_entry` 仅等于第一条，`source_entry_scope = first_entry_only` 明确其范围；不能用它代替完整双来源。F8的新机制卡与规则章均展示两条来源。

版本、hash、commit、节点/行索引、原始行和当前执行政策共同参与缓存校验；最多缓存五个明确身份。复苏任一条来源或授予失效即拒绝整个包并清除该ID缓存，不接受部分结果或旧值回退。既有三个源定义的字段、原始行、预算与授予结构保持原样。

## 源百分比与怪物固定供给分开

源授予没有固定护盾或固定回复；护盾提高经 `capacity_increased.max_shield` 消费，回复提高经 `stats.shield_recharge_rate_increased` 消费。以下固定值是本项目独立原创怪物预算，定义于 `MonsterCatalog.ShieldSupply` 对应的 `scripts/monsters/source_shield_budget.gd`，政策为 `monster-shield-supply-v1`，不是PoE源词条的固定效果，也不发给玩家。

| 身份 | 独立基础护盾 | 独立基础回复/秒 | 源容量提高 | 源回复率提高 |
| --- | ---: | ---: | ---: | ---: |
| 储盾 | 3.12 | 0 | 8% | 0 |
| 复苏 | 1.56 | 0.4225 | 4% | 10% |
| 两者 | 4.68 | 0.4225 | 12% | 10% |

出生时：

- 最大护盾＝（旧固定护盾＋独立怪物基础护盾之和）×（1＋容量提高之和）
- 每秒回复＝（旧固定回复＋独立怪物基础回复之和）×（1＋回复率提高之和）
- 默认开始回复延迟＝4秒；本批没有更快开始回复

同类提高先加算，再乘一次。储盾平原护盾 `3.12 × 1.08 = 3.3696`，回复0；复苏为 `1.56 × 1.04 = 1.6224`，回复 `0.4225 × 1.10 = 0.46475/秒`；双词缀为 `4.68 × 1.12 = 5.2416`，回复仍0.46475/秒。单条储盾即使从地图获得更多护盾，仍不会凭空获得回复。

角色的 `source_shield_profile` 冻结 `budget_policy`、逐项 `supplies`、原固定基础值、合并基础护盾/回复、`capacity_increased` 和 `capacity_multiplier = 1 + I`。模拟与地图使用出生快照，每帧不重新解析源树。

## 护幕地图的有意变化

令 `S` 为已完成源提高的canonical护盾，`M = 0.20 × canonical最大生命`；这里生命取“强健”地图倍率之前。带新护盾身份的怪物，当前和最大护盾都只加 `M × frozen_capacity_multiplier`：

`地图最大护盾 = S + M × (1 + I)`

原 `S` 不再乘一次，当前与最大护盾同加一笔，因此缺失护盾量保持。强健同时出现时只放大生命，不改变M。没有新身份的怪物继续原加法 `S + M`，包括旧辉壁机制与历史特殊模板。此变化有意改变新身份的地图预算，不能声称新旧地图等价。

为保持历史已编译配置的身份与校验，`EncounterCatalog` 的定义、描述和资源政策逐字节保留；条件分支在新规则章、共享机制卡、新身份卡和本合同中解释。旧图鉴的护幕例子仍是其历史输入，不用新路径重算。

## 实际工厂与地图编译预算

下表分别使用第2波金色巡游体（canonical生命110.2，M22.04）和第10波金色重壳体（生命579.5，M115.9）。七组样本均由 `MonsterCatalog.make_enemy` 生成，地图列由 `EncounterCompiler.compile/apply_to_enemy` 生成，非手工构造怪物。两种金色样本都允许双词缀。

| 词缀 | 平原护盾 | 基础回复/秒 | 实际回复/秒 | 延迟秒 | 巡游体护幕后护盾 | 重壳体护幕后护盾 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 无 | 0 | 0 | 0 | 4 | 22.04 | 115.9 |
| 旧储盾 | 3.12 | 0 | 0 | 4 | 25.16 | 119.02 |
| 源储盾 | 3.3696 | 0 | 0 | 4 | 27.1728 | 128.5416 |
| 旧复苏 | 1.56 | 0.4225 | 0.4225 | 4 | 23.6 | 117.46 |
| 源复苏 | 1.6224 | 0.4225 | 0.46475 | 4 | 24.544 | 122.1584 |
| 旧双辉壁 | 4.68 | 0.4225 | 0.4225 | 4 | 26.72 | 120.58 |
| 源双辉壁 | 5.2416 | 0.4225 | 0.46475 | 4 | 29.9264 | 135.0496 |

例如低档新双辉壁为 `5.2416 + 22.04 × 1.12 = 29.9264`，高档为 `5.2416 + 115.9 × 1.12 = 135.0496`。强健＋护幕的生命分别为132.24和695.4，护盾与单护幕相同。另对每个样本先扣最多1点护盾再应用地图，验证原缺失量不变。

以上是代表性工厂预算、回复profile及地图顺序对照，不是自然生成分布、DPS或全局平衡证明。回复数值是延迟结束后的每秒值，并非持续无条件回血。

## 四代普通抽签入口

| 入口 / 政策 | 五槽词池 |
| --- | --- |
| `ordinary_roll` / `legacy_flat_v1` | ember_power → gale_stride → grove_vitality → aegis_capacity → aegis_recovery |
| `ordinary_roll_source_stride` / `source_stride_v1` | ember_power → source_gale_stride → grove_vitality → aegis_capacity → aegis_recovery |
| `ordinary_roll_source_damage_life` / `source_damage_life_v2` | source_ember_power → source_gale_stride → source_grove_vitality → aegis_capacity → aegis_recovery |
| `ordinary_roll_current` / `source_shield_v3` | source_ember_power → source_gale_stride → source_grove_vitality → source_aegis_capacity → source_aegis_recovery |

对应政策常量为 `LEGACY_ROLL_POLICY`、`STRIDE_ROLL_POLICY`、`DAMAGE_LIFE_ROLL_POLICY`、`CURRENT_ROLL_POLICY`；词池常量为 `AFFIX_POOL`、`STRIDE_AFFIX_POOL`、`DAMAGE_LIFE_AFFIX_POOL`、`CURRENT_AFFIX_POOL`。v3仅重映射普通巡游体、掠行体、重壳体最后两槽，不增加槽位、抽签次数、RNG消耗、稀有度、名额或奖励。所有历史别名与旧入口保持；既有固定特殊、首领及后代不自动升级。

## F8与资料保全

F8保留23条历史定义和3条既有源定义，以及v0.74移动12组和v0.75伤害/生命12组预算原值；只更新旧章节的当前数量、池身份、缓存说明及交叉链接。新增两机制卡及一个规则章，共3个锚点。原PNG、字体、CSS/JS、源数据、源覆盖JSON、旧文档和旧QA文件保持。

存档结构仍为47，权威字段为 `Canonical.Rules.VERSION`，不是历史 `Build.SAVE_VERSION`；装备词汇46，源执行政策45。资料导出采用窄runtime片段，只导出新章及必要元数据，再合并到精确的 `76c9cab` 基线；不完整导出catalog，不让旧JSON经过Godot解析与重新序列化。

验证方法与收据见 [v076 F8资料验证](qa/v076-reference/README.md)。历史合同分别见 [v074源移动](SOURCE_MONSTER_MOVEMENT.zh-CN.md) 与 [v075源伤害/生命](SOURCE_MONSTER_DAMAGE_LIFE.zh-CN.md)；它们记载各自版本当时的当前政策，本版以这里的四代入口为准。
