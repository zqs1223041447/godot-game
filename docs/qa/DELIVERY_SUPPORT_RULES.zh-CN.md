# 投射、控制与连锁辅助：纯程序契约与专项验证

实现：`scripts/combat/delivery_support_rules.gd`。专项：`tests/delivery_support_rules_test.gd`。

此模块只编译声明式辅助程序。技能编译器负责把结果应用到已验证的本次施放配方，再交给真实战斗；模块本身不改变基础配方、伤害包、运行中投射物或存档。

## 五个固定辅助

| ID | 名称 / 类别 | 技能 | 配方变化 | 主命中 MORE | 魔力 |
| --- | --- | --- | --- | --- | --- |
| `swift_projectiles` | 疾速投射辅助 / `delivery` | 飞弹、冰霜 | 速度 ×1.35 | 不变 | ×1.10 |
| `heavy_projectiles` | 缓速强击辅助 / `delivery` | 飞弹、冰霜 | 速度 ×0.75 | +20% | ×1.15 |
| `lingering_chill` | 寒意延长辅助 / `control` | 冰霜 | 现有减速时间 ×1.50 | −10% | ×1.10 |
| `chain_extension` | 连锁延展辅助 / `chain` | 连锁闪电 | 总目标数 +2 | −20% | ×1.30 |
| `chain_reach` | 远链辅助 / `chain` | 连锁闪电 | 后续寻敌距离 ×1.30 | −10% | ×1.15 |

所有冷却倍率保持 1。龙卷不接受这批飞行辅助：其母子分裂、射程和寿命语义没有在此批扩展。普攻、新星、陨星、位移和护盾技能也不在五个辅助的适配列表中。

## 配方边界

- 飞弹基础速度 780，疾速后 1053，缓速后 585；冰霜基础速度 520，对应 702 / 390。只返回 `projectile_speed_multiplier`，不改穿透、初始数量、展开角度、射程、寿命或伤害系数
- 寒意延长只返回 `slow_duration_multiplier=1.5`，把冰霜既有的 `slow=3.0` 秒变成 4.5 秒。沿用现有减速计时与强度，没有新增异常状态、减速层数、伤害阈值或新的触发事件
- 当前 `bounce_count=5` 表示总共至多命中五个不同目标，索引 0–4。`chain_extra_targets=2` 应把总目标预算变成 7，索引 0–6；不是首个目标之外再跳七次
- 连锁原始系数与外加效用都是 `2.2 − 索引 ×0.2`。目标数增加不改这个递减公式，新增两个位置分别仍为 1.2 和 1.0，再由同一个有技能和标签范围的 MORE 处理
- `chain_followup_range_multiplier=1.3` 只作用于后续目标的 220 距离，使其成为 286；首次从玩家处寻找目标仍使用 600
- 独立爆炸用自己的 `hit/area/secondary/explosion` 标签，不接收主命中 MORE。主命中范围通过共享 `SupportProgram.primary_modifier` 生成，绑定具体技能和完整 `hit/spell/projectile` 或 `hit/spell/chain` 标签

## 两槽组合

每个技能的完整辅助选择仍由全局注册表限制为两个槽位；本模块接收自己的子集，也拒绝超过两个、重复、未知 ID 和错误类型。所有在同一技能上适配的不同辅助都能组合，先按 ID 排序，再计算乘积或整数和，不因装配顺序产生浮点或字典插入顺序差异。

| 组合 | 技能 | 合并效果 | 主命中倍率 | 魔力倍率 |
| --- | --- | --- | --- | --- |
| 疾速 + 缓速强击 | 飞弹、冰霜 | 速度 ×1.0125；实际 789.75 / 526.5 | ×1.20 | ×1.265 |
| 疾速 + 寒意延长 | 冰霜 | 速度 ×1.35；减速 4.5 秒 | ×0.90 | ×1.21 |
| 缓速强击 + 寒意延长 | 冰霜 | 速度 ×0.75；减速 4.5 秒 | ×1.08 | ×1.265 |
| 连锁延展 + 远链 | 连锁闪电 | 总目标 7；后续距离 286；首次仍 600 | ×0.72 | ×1.495 |

连锁延展两条新增命中使用原来的逐次递减。仅把每个位置的固定系数相加，基础五目标为 9.0，延展七目标为 11.2 ×0.8 = 8.96；这不是实战 DPS，仍需足够的存活目标、位置与合法连锁路径。

## API 与失败原子性

- `SUPPORTS` 是五个辅助的可执行元数据来源。每项恰好含 `name`、`description`、`skills`、`requires`、`operations`、`family`
- `get_definition(id)` 返回深拷贝；未知 ID 返回空字典
- `definition_error(value)` 拒绝缺键、多键、错误类型、未知类别、技能/能力与类别不匹配、缺少代价、重复或未知操作、NaN / Inf、零效果和错误取舍方向。每个辅助恰好有一种配方变换
- `compile_program(skill_id, support_ids)` 始终返回共享五字段信封：`error`、`modifiers`、`mana_multiplier`、`cooldown_multiplier`、`recipe_factors`
- 已知技能和空子集返回空程序；失败也返回空程序，仅填写错误原因。不会返回前半段成功的倍率、修饰符或配方变换
- `recipe_factors` 只包含当前选择实际涉及的键。没有辅助时返回 `{}`；不填零增量、无意义的倍率 1 或未知键
- 程序不读取或消耗 RNG，不重排调用方数组，不修改基础目录或调用方数据。返回的元数据、修饰符、范围标签与因子都是独立容器

## 已执行验证

2026-10-03 使用 Godot `4.6.3.stable.official.7d41c59c4`，在独立 `/tmp/godot-v019-delivery-*` 的 XDG 数据、配置和缓存目录执行：

```sh
qa_root=$(mktemp -d /tmp/godot-v019-delivery-XXXXXX)
mkdir -p "$qa_root/data" "$qa_root/config" "$qa_root/cache/fontconfig"
XDG_DATA_HOME="$qa_root/data" XDG_CONFIG_HOME="$qa_root/config" XDG_CACHE_HOME="$qa_root/cache" \
  godot --headless --path . --script res://tests/delivery_support_rules_test.gd
```

结果：**2,547 项检查，0 失败**，退出码 0，无脚本错误。覆盖所有单项与合法两项的数值矩阵、全部技能/辅助和有序两项适配矩阵、畸形定义与输入、失败零副作用、字节级规范顺序、深拷贝、全局 RNG 不变，以及真实既有投射/连锁伤害包的每种分量、抗性、主命中与独立爆炸边界。

本记录仅证明纯程序模块。全局注册、schema13 存档、编译配方实际应用、七目标包生成、战斗寻敌和界面展示属于上层整合验收；这里没有运行完整长时回归，也没有把纯程序测试当作这些整合步骤的通过证据。
