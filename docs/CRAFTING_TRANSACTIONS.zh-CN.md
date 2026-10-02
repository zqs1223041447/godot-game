# 工艺事务规划器：报价、权威重算与候选状态

本独立分支基于 `codex/crafting-rules-v013` 的 `f23dcc4d9267a098301b07574390d5077b95867b`，只新增 [规划器](../scripts/items/crafting_transaction_planner.gd)、[专项测试](../tests/crafting_transaction_planner_test.gd) 和本文档。**尚未接入主游戏、UI、材料存档或实际提交；未合并或发布。** 没有修改 Craft 规则、BuildState 或核心界面，也没有加载 BuildState。

规则来源为 [CraftingRules](../scripts/items/crafting_rules.gd)，实例校验和底材元数据来源为 [EquipmentCatalog](../scripts/items/equipment_catalog.gd)，固定物品识别来源为 [GameData](../scripts/game_data.gd)。费用和收益只读取实际 Craft API 的结果，不复制经济参数表或重写校准/武器伤害公式。

## 上下文契约

两个 API 都只接受包含以下七个字段的 `Dictionary`。不得传入完整 BuildState 存档、额外标志、预先生成的替换实例或调用方 RNG。

| 字段 | 形态及约束 |
|---|---|
| `revision` | Godot 实际 `int`，范围 `0..9223372036854775807`；代表主集成维护的权威修订号 |
| `inventory` | 唯一字符串 ID 数组；沿用实际库存语义，**包括已穿戴物品**；允许现有固定物品和持有的生成实例 |
| `equipment_instances` | ID → 规范五字段实例；全部实例必须通过当前目录验证、表键等于实例 ID，并存在于 `inventory` |
| `equipped` | `weapon/armor/charm` → 持有的物品 ID；槽位必须与固定物品或底材元数据相符；未穿戴槽位可省略 |
| `backpack_positions` | `item:<id>` / `jewel:<id>` → 非负 `Vector2i` 或两项有限整值坐标数组；所有未穿戴装备必须有位置，已穿戴装备不能有背包位置 |
| `materials` | 恰好 `{ "calibration_shard": int余额 }`，范围 `0..9223372036854775807`；零余额也必须显式提供，不补默认值、不接受其他材料 |
| `save_writable` | 实际 `bool`；由主集成根据当前目标路径的存档保护状态提供，`false` 时拒绝操作 |

位置支持实际运行时 `Vector2i` 和 `_snapshot()` 使用的 `[x, y]` 形态。整值浮点坐标及目录允许的 JSON 整值实例仍可接受；材料、修订号和 seed 必须为实际整数类型，不能用 `true`、`1.0` 或字符串代替。输出保持输入位置形态和未修改字段的数值表示。

这里只检查上下文形态、装备所有权和装备位置关系；**不验证格子尺寸、越界、重叠、全体物品回包容量、珠宝所属位置、天赋图、`next_equipment_id` 与实例序号的关系或完整存档 schema**。珠宝位置会深复制保留，其所有权无法从这七个字段确定。上述约束必须由主集成对完整候选执行既有校验，不能把本模块成功当成 BuildState 校验成功。

## API 与报价

```gdscript
const Transactions = preload("res://scripts/items/crafting_transaction_planner.gd")

var quoted: Dictionary = Transactions.quote(context, "recalibrate", item_id)
if quoted.ok:
    # 展示 quoted.cost / quoted.materials，不生成供玩家挑选的随机结果。
    var result: Dictionary = Transactions.plan(current_authoritative_context, quoted, 20261002)
    if result.ok:
        var candidate: Dictionary = result.candidate
        # 候选尚未提交：主集成仍需构造和验证完整 BuildState 候选。
```

`quote(context, operation, item_id)` 的 operation 为 `salvage` 或 `recalibrate`。成功时只有下列字段，不包含 seed、随机替换实例、派生属性或候选：

| 字段 | 含义 |
|---|---|
| `ok/code/reason` | `true`、空错误码、空原因 |
| `operation/item_id` | 操作和被操作实例的 ID |
| `revision/rules_version` | 权威修订号和 `Craft.RULES_VERSION` |
| `source_instance` | 原实例的完整深复制，用于绑定源状态；其中是原值，不是未来掷值 |
| `cost/materials` | 待扣材料和待获得材料的独立深复制；表示经济变动，不表示余额 |
| `consumes_item` | 回收为 `true`，校准为 `false` |

报价同时检查当前存档权限、持有/穿戴/固定物品限制、规则资格、支付能力、材料溢出及下一次修订号是否可用。报价不会预留余额或消耗物品。现有 Craft API 没有独立校准费用查询，因此校准报价调用 `Craft.recalibrate_plan(source, 0)` 读取费用，随即舍弃其替换实例和派生属性。该调用使用 Craft 的局部 RNG，不涉及全局或掉落 RNG，也不是下一次确认的 seed。

## 规划、重放和原子候选

`plan(context, quoted, seed_value)` 接受实际整数 seed，支持零、负数及有符号 64 位两端；回收也检查 seed 类型，但不使用其数值。

1. 检查报价字段集合及绑定标识。从**当前权威上下文**重新调用 `quote`，重新检查所有操作资格、余额、写保护和溢出条件。
2. 检查源实例、revision 和规则版本；任一变化拒绝为 `stale_quote`。再逐字段与重算报价作类型严格、字典键序无关的比较；改价、增加收益、改变消耗标志、添加随机结果或其他字段等拒绝为 `invalid_quote`。
3. 只有通过上述检查才以本次 seed 调用 Craft 生成校准实例，再核对规则结果与重算经济数据一致。没有手写掷值、族/档位变更或本地武器伤害缓存。
4. 深复制整个七字段上下文。回收一起删除 `inventory` 中的 ID、实例表记录和 `item:<id>` 位置，并加入材料。校准一起扣材料、以原 ID 替换实例，保留当前位置。两者都使 revision 加一。
5. 返回 `{ "ok": true, "code": "", "reason": "", "candidate": 完整七字段深复制候选 }`。所有成功和失败都不修改输入；不同候选之间、候选与报价、报价与目录常量之间不共享可变字典/数组。

材料先检查余额是否足够，再比较 `收益 <= MAX_MATERIAL_COUNT - 扣费后余额`，之后才相加；revision 在加一前拒绝最大值。因此既不出现负余额，也不会让有符号整数回绕。

所有失败统一只返回 `{ "ok": false, "code": 错误码, "reason": 中文原因 }`，没有候选、源实例、扣款、收益或部分替换结果。当前权威条件失败可优先于过期报价错误，例如物品已经回收会返回 `not_owned`，存档变成只读会返回 `save_read_only`。

| 错误码 | 条件 |
|---|---|
| `invalid_operation/invalid_item_id` | 操作或 ID 的值/类型不合法 |
| `invalid_context/invalid_revision/invalid_materials` | 七字段上下文、身份/位置关系或严格整数输入不合法 |
| `save_read_only/not_owned/fixed_item/item_equipped` | 权威操作资格不满足 |
| `insufficient_materials/material_overflow/revision_overflow` | 余额不足或下一步运算超界 |
| `invalid_quote/stale_quote/invalid_seed` | 报价被改动、绑定状态过期或 seed 类型错误 |
| `invalid_rule_result` | Craft 返回的经济数量或计划一致性检查失败 |
| Craft 原始拒绝码 | 如目录合法但无词缀的普通装备返回 `no_affixes`；规则错误保留其原因 |

校准可能得到完全相同的值，也会正常扣费和 revision 加一。**提交后的权威 revision** 使旧报价失效，不能只用实例内容变化判定是否执行过。规划器无内部账本；同一个尚未提交的权威上下文、报价和 seed 可以重复得到相同候选，这不是重复提交防护。重算能拒绝不一致的伪造数据，不能证明一份完全等同于合法报价的数据曾由服务端签发；若需要签发证明、请求身份或防重放操作 ID，主集成须另持有报价/nonce。

## 主集成提交契约与限制

后续接入必须在统一事务边界内从可信模型构造上下文，调用规划器，然后把投影更新合入**完整 BuildState 深复制候选**，保留序号、珠宝、技能、天赋、进度等其余字段。完整候选及新材料/修订号 schema 全部校验通过后，才一次性提交材料、装备、位置和 revision；随后统一发变化通知、刷新派生属性并经既有持久化流程尝试保存一次。不得在 UI 中先扣款、逐字段直接应用候选或省略完整校验。

主集成必须保证 revision 单调推进，至少覆盖影响报价/提交的库存、实例、穿戴、位置、材料、存档权限变化；不能在重载、回滚或并发请求之间回退/复用修订号。读上下文、校验和提交之间不能放入允许其他状态写入的等待点。当前 `save_writable` 只是可信调用方提供的权限事实，无法预先保证实际 I/O 成功；保存失败的回滚/重试、通知、崩溃恢复及幂等提交仍需该层明确实现和测试。

现有 v9 存档尚无这些材料和修订号字段，且严格拒绝额外字段；本次没有修改迁移或持久化。64 位极值是在内存整数域验证的：JSON 浮点不能可靠保存全部 64 位整数，主集成应选可精确表示的持久化上界或另用严格解析的十进制字符串，不能直接将 JSON 解码浮点余额当成合法上下文。模块不选择、保存或防止玩家挑选 seed；seed 必须由主集成在确认事务中选择并持有。同输入/seed 的复现沿用 Craft 和当前引擎 RNG 契约，不承诺跨引擎 RNG 算法版本一致。

## 专项验收

在仓库根运行独立测试，不依赖或改动 `tools/validate.sh`：

```bash
mkdir -p /tmp/crafting-transactions-test/{data,config,cache/fontconfig}
XDG_DATA_HOME=/tmp/crafting-transactions-test/data \
XDG_CONFIG_HOME=/tmp/crafting-transactions-test/config \
XDG_CACHE_HOME=/tmp/crafting-transactions-test/cache \
godot --headless --path . --script res://tests/crafting_transaction_planner_test.gd
```

2026-10-02 在 Godot `4.6.3.stable.official.7d41c59c4` 独立运行：**9 个实际底材、91 个适用底材/族组合、581 个物品用例、14,155 项检查，0 失败，退出 0；日志无 `SCRIPT ERROR:` / `ERROR:`。** 包含所有族/档位的输入上下端点、各底材 4/5/6 词缀稀有实例、普通无词缀拒绝，以及符木法器、灰烬皮甲和白蜡长弓；校准候选逐件与真实 Craft 输出比对。

重点验证了同值重掷仍扣费并推进 revision、旧 revision/规则/实例报价重放、报价字段篡改、确认前穿戴/余额/写保护变化、零与最大材料余额、最大 revision 前一值、整数 seed 极值、非法数值类型、输入字节不变、所有嵌套候选隔离、目录常量不变、全局与调用方 RNG 不变，以及运行时/序列化位置与 JSON 实例兼容性。

同时针对现有依赖运行 `tests/crafting_rules_test.gd`：2,415 份规则计划、91,707 项检查，0 失败，退出 0，日志无脚本错误。两个套件的运行日志在本次工作环境的 `/tmp/crafting-transactions-check/transactions.log` 与 `rules.log`；日志不加入仓库。

这是规划器专项验收；没有重复运行约 600 秒全量验收，也没有进行主游戏交互、真实材料存档、故障提交/恢复、Windows 原生运行或发布包验收。以上成功候选不代表已经进入主游戏。
