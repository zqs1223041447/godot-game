# 回收与数值校准预算核算

本报告由 `tools/export_crafting_budget.gd` 从 `EquipmentCatalog` 与 `CraftingRules` 生成；规则版本：`original-crafting-prototype-v1`，装备目录词汇版本：`9`，游戏版本：`0.19.0`。这是现有原型规则的核算，不实现或定价任何新工艺。

## 覆盖范围与证明口径

- 完整矩阵枚举 **9 个底材 × 30 个物品等级（1–30）× 3 种稀有度 = 810 行**；普通、魔法、稀有各覆盖全部底材和等级。
- 底材/词族全配对矩阵有 **171 行**（9 × 19）；其中当前目录与生成池同时允许的实际适用组合为 **91 对**，其余行明确标记不适用。记录还给出可出现稀有度、等级段和每个 tier 的解锁等级。
- 魔法/稀有预算按实际 tier 解锁等级派生的 3 个等级段（1–7、8–15、16–30），对每段每种合法词族集合做完整子集枚举；枚举 122826 个集合位掩码、21321 个合法族集合及其 2326684 种可用 tier 指派。合法见证逐个通过目录验证，再由 `CraftingRules.salvage_quote()` 取回收量、`recalibrate_plan()` 取校准成本。
- 数值上下界对每个合法族集合按现有可用 tier 的独立加和规则解析；全部端点见证均经真实规则报价。词缀掷值不参与回收或校准数量，因此没有枚举掷值组合，也没有用随机种子证明边界。
- 两个固定种子样例只用于复现具体校准输出；不代表概率、期望收益或经济上界。普通白装在完整 270 项底材/等级矩阵中逐项验证，现有规则均以 `no_affixes` 拒绝回收和校准。

## 当前规则

- 材料：`calibration_shard`（校准碎片）。回收消耗物品、只产出该材料；数值校准不消耗物品、只扣材料。
- 精确公式来自当前元数据：回收 `rarity_units + sum(tier) * salvage_units_per_tier`；校准 `salvage_yield * recalibrate_cost_multiplier`。实际费率全部从 `CraftingRules.BALANCE` 读取，未另抄平衡表。
- 只支持有词缀的魔法与稀有实例。回收不看掷值；校准保留底材、等级、稀有度、族、阶级和顺序，只重掷已有整数值，可能下降或不变。

## 每个底材的完整等级段预算区间

每段对应当前装备目录的 tier 可用集合：物品等级 1–7、8–15、16–30。区间覆盖该段全部合法词族组合与各可用阶级；校准成本端点直接由相同源实例的 `recalibrate_plan()` 取得。完整 810 行与逐行见证在 [JSON 矩阵](crafting-budget.json)。

| 底材 | 等级段 | 魔法回收量 | 魔法校准成本 | 稀有回收量 | 稀有校准成本 |
|---|---:|---:|---:|---:|---:|
| 烬芦杖 (`cinder_reed`) | 1–7 | 2–3 | 4–6 | 7–9 | 14–18 |
| 烬芦杖 (`cinder_reed`) | 8–15 | 2–5 | 4–10 | 7–15 | 14–30 |
| 烬芦杖 (`cinder_reed`) | 16–30 | 2–7 | 4–14 | 7–21 | 14–42 |
| 岚纺刃 (`gale_spindle`) | 1–7 | 2–3 | 4–6 | 7–9 | 14–18 |
| 岚纺刃 (`gale_spindle`) | 8–15 | 2–5 | 4–10 | 7–15 | 14–30 |
| 岚纺刃 (`gale_spindle`) | 16–30 | 2–7 | 4–14 | 7–21 | 14–42 |
| 绳垒衣 (`woven_bastion`) | 1–7 | 2–3 | 4–6 | 7–9 | 14–18 |
| 绳垒衣 (`woven_bastion`) | 8–15 | 2–5 | 4–10 | 7–15 | 14–30 |
| 绳垒衣 (`woven_bastion`) | 16–30 | 2–7 | 4–14 | 7–21 | 14–42 |
| 潮缄袍 (`tidebound_coat`) | 1–7 | 2–3 | 4–6 | 7–9 | 14–18 |
| 潮缄袍 (`tidebound_coat`) | 8–15 | 2–5 | 4–10 | 7–15 | 14–30 |
| 潮缄袍 (`tidebound_coat`) | 16–30 | 2–7 | 4–14 | 7–21 | 14–42 |
| 途镜坠 (`wayglass_token`) | 1–7 | 2–3 | 4–6 | 7–9 | 14–18 |
| 途镜坠 (`wayglass_token`) | 8–15 | 2–5 | 4–10 | 7–15 | 14–30 |
| 途镜坠 (`wayglass_token`) | 16–30 | 2–7 | 4–14 | 7–21 | 14–42 |
| 脉籽符 (`pulse_seed`) | 1–7 | 2–3 | 4–6 | 7–9 | 14–18 |
| 脉籽符 (`pulse_seed`) | 8–15 | 2–5 | 4–10 | 7–15 | 14–30 |
| 脉籽符 (`pulse_seed`) | 16–30 | 2–7 | 4–14 | 7–21 | 14–42 |
| 符木法器 (`runewood_focus`) | 1–7 | 2–3 | 4–6 | 7–9 | 14–18 |
| 符木法器 (`runewood_focus`) | 8–15 | 2–5 | 4–10 | 7–15 | 14–30 |
| 符木法器 (`runewood_focus`) | 16–30 | 2–7 | 4–14 | 7–21 | 14–42 |
| 灰烬皮甲 (`emberhide_vest`) | 1–7 | 2–3 | 4–6 | 7–9 | 14–18 |
| 灰烬皮甲 (`emberhide_vest`) | 8–15 | 2–5 | 4–10 | 7–15 | 14–30 |
| 灰烬皮甲 (`emberhide_vest`) | 16–30 | 2–7 | 4–14 | 7–21 | 14–42 |
| 白蜡长弓 (`ashwood_bow`) | 1–7 | 2–3 | 4–6 | 7–9 | 14–18 |
| 白蜡长弓 (`ashwood_bow`) | 8–15 | 2–5 | 4–10 | 7–15 | 14–30 |
| 白蜡长弓 (`ashwood_bow`) | 16–30 | 2–7 | 4–14 | 7–21 | 14–42 |

### 各底材稀有装备回收上限

| 底材 | 物品等级 | 回收上限 | 同件校准成本 |
|---|---:|---:|---:|
| 烬芦杖 (`cinder_reed`) | 16 | 21 | 42 |
| 岚纺刃 (`gale_spindle`) | 16 | 21 | 42 |
| 绳垒衣 (`woven_bastion`) | 16 | 21 | 42 |
| 潮缄袍 (`tidebound_coat`) | 16 | 21 | 42 |
| 途镜坠 (`wayglass_token`) | 16 | 21 | 42 |
| 脉籽符 (`pulse_seed`) | 16 | 21 | 42 |
| 符木法器 (`runewood_focus`) | 16 | 21 | 42 |
| 灰烬皮甲 (`emberhide_vest`) | 16 | 21 | 42 |
| 白蜡长弓 (`ashwood_bow`) | 16 | 21 | 42 |

全目录稀有回收上界为 **21 枚**（`cinder_reed`，物品等级 16）；按当前规则，同件数值校准扣 **42 枚**。这是已枚举合法物品域内的精确上限，不是样本估计。

## 底材可用词族

下表仅列能在当前生成池和底材资格中进入合法物品的族。每项后的 `T1/T2/T3@等级` 来自目录原始档位；是否能出现在魔法/稀有完整实例按当前稀有度词缀数与前后缀上限另行穷举，逐族等级见 JSON。

| 底材 | 可出现词族（ID：T1/T2/T3 解锁等级） |
|---|---|
| 烬芦杖 (`cinder_reed`) | `deepwell`（T1@1/T2@8/T3@16）、`runesong`（T1@1/T2@8/T3@16）、`prismedge`（T1@1/T2@8/T3@16）、`farweave`（T1@1/T2@8/T3@16）、`coalglow`（T1@1/T2@8/T3@16）、`rimeecho`（T1@1/T2@8/T3@16）、`sparkthread`（T1@1/T2@8/T3@16）、`wellturn`（T1@1/T2@8/T3@16）、`beatlink`（T1@1/T2@8/T3@16） |
| 岚纺刃 (`gale_spindle`) | `deepwell`（T1@1/T2@8/T3@16）、`runesong`（T1@1/T2@8/T3@16）、`prismedge`（T1@1/T2@8/T3@16）、`farweave`（T1@1/T2@8/T3@16）、`coalglow`（T1@1/T2@8/T3@16）、`rimeecho`（T1@1/T2@8/T3@16）、`sparkthread`（T1@1/T2@8/T3@16）、`wellturn`（T1@1/T2@8/T3@16）、`beatlink`（T1@1/T2@8/T3@16） |
| 绳垒衣 (`woven_bastion`) | `rootwell`（T1@1/T2@8/T3@16）、`deepwell`（T1@1/T2@8/T3@16）、`lanternveil`（T1@1/T2@8/T3@16）、`coalglow`（T1@1/T2@8/T3@16）、`rimeecho`（T1@1/T2@8/T3@16）、`sparkthread`（T1@1/T2@8/T3@16）、`wellturn`（T1@1/T2@8/T3@16）、`trailstep`（T1@1/T2@8/T3@16） |
| 潮缄袍 (`tidebound_coat`) | `rootwell`（T1@1/T2@8/T3@16）、`deepwell`（T1@1/T2@8/T3@16）、`lanternveil`（T1@1/T2@8/T3@16）、`coalglow`（T1@1/T2@8/T3@16）、`rimeecho`（T1@1/T2@8/T3@16）、`sparkthread`（T1@1/T2@8/T3@16）、`wellturn`（T1@1/T2@8/T3@16）、`trailstep`（T1@1/T2@8/T3@16） |
| 途镜坠 (`wayglass_token`) | `rootwell`（T1@1/T2@8/T3@16）、`deepwell`（T1@1/T2@8/T3@16）、`lanternveil`（T1@1/T2@8/T3@16）、`runesong`（T1@1/T2@8/T3@16）、`prismedge`（T1@1/T2@8/T3@16）、`farweave`（T1@1/T2@8/T3@16）、`coalglow`（T1@1/T2@8/T3@16）、`rimeecho`（T1@1/T2@8/T3@16）、`sparkthread`（T1@1/T2@8/T3@16）、`wellturn`（T1@1/T2@8/T3@16）、`trailstep`（T1@1/T2@8/T3@16）、`beatlink`（T1@1/T2@8/T3@16） |
| 脉籽符 (`pulse_seed`) | `rootwell`（T1@1/T2@8/T3@16）、`deepwell`（T1@1/T2@8/T3@16）、`lanternveil`（T1@1/T2@8/T3@16）、`runesong`（T1@1/T2@8/T3@16）、`prismedge`（T1@1/T2@8/T3@16）、`farweave`（T1@1/T2@8/T3@16）、`coalglow`（T1@1/T2@8/T3@16）、`rimeecho`（T1@1/T2@8/T3@16）、`sparkthread`（T1@1/T2@8/T3@16）、`wellturn`（T1@1/T2@8/T3@16）、`trailstep`（T1@1/T2@8/T3@16）、`beatlink`（T1@1/T2@8/T3@16） |
| 符木法器 (`runewood_focus`) | `deepwell`（T1@1/T2@8/T3@16）、`runesong`（T1@1/T2@8/T3@16）、`prismedge`（T1@1/T2@8/T3@16）、`farweave`（T1@1/T2@8/T3@16）、`coalglow`（T1@1/T2@8/T3@16）、`rimeecho`（T1@1/T2@8/T3@16）、`sparkthread`（T1@1/T2@8/T3@16）、`wellturn`（T1@1/T2@8/T3@16）、`beatlink`（T1@1/T2@8/T3@16）、`attack_added_physical`（T1@1/T2@8/T3@16）、`attack_added_fire`（T1@1/T2@8/T3@16）、`spell_added_cold`（T1@1/T2@8/T3@16）、`spell_added_lightning`（T1@1/T2@8/T3@16） |
| 灰烬皮甲 (`emberhide_vest`) | `rootwell`（T1@1/T2@8/T3@16）、`deepwell`（T1@1/T2@8/T3@16）、`lanternveil`（T1@1/T2@8/T3@16）、`coalglow`（T1@1/T2@8/T3@16）、`rimeecho`（T1@1/T2@8/T3@16）、`sparkthread`（T1@1/T2@8/T3@16）、`wellturn`（T1@1/T2@8/T3@16）、`trailstep`（T1@1/T2@8/T3@16）、`emberward`（T1@1/T2@8/T3@16） |
| 白蜡长弓 (`ashwood_bow`) | `deepwell`（T1@1/T2@8/T3@16）、`runesong`（T1@1/T2@8/T3@16）、`prismedge`（T1@1/T2@8/T3@16）、`farweave`（T1@1/T2@8/T3@16）、`coalglow`（T1@1/T2@8/T3@16）、`rimeecho`（T1@1/T2@8/T3@16）、`sparkthread`（T1@1/T2@8/T3@16）、`wellturn`（T1@1/T2@8/T3@16）、`beatlink`（T1@1/T2@8/T3@16）、`whetstone_edge`（T1@1/T2@8/T3@16）、`tempered_edge`（T1@1/T2@8/T3@16） |

## 可重现样例

- 普通白装：`cinder_reed`，等级 1，目录合法；回收与校准都由规则返回 `no_affixes`：普通无词缀装备不支持回收或数值校准。
- `global_minimum_yield`：输入 `cinder_reed`（magic / ilvl 1 / 1 条词缀）→ 回收 2 枚；校准种子 `20261003`、消耗 4 枚，结果 `{"affixes":[{"id":"deepwell","tier":1,"value":5}],"base_id":"cinder_reed","id":"gear_000001","item_level":1,"rarity":"magic"}`。
- `global_maximum_yield`：输入 `cinder_reed`（rare / ilvl 16 / 6 条词缀）→ 回收 21 枚；校准种子 `20261004`、消耗 42 枚，结果 `{"affixes":[{"id":"deepwell","tier":3,"value":17},{"id":"runesong","tier":3,"value":15},{"id":"prismedge","tier":3,"value":15},{"id":"coalglow","tier":3,"value":16},{"id":"rimeecho","tier":3,"value":18},{"id":"sparkthread","tier":3,"value":17}],"base_id":"cinder_reed","id":"gear_000001","item_level":16,"rarity":"rare"}`。

样例的输入、完整输出与固定种子均记录在 JSON `examples` 字段中。当前无新工艺实现；此交付只给后续定价提供既有规则回收上界与资格矩阵。
