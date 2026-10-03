# 九槽装备纯数据 profile 原型与定向验证

基线：`2ac7c8bb71fb0d1fea0a23c7125b1b438f0c3676`（v0.19）。本批仅新增纯数据脚本、定向测试与本说明。脚本不接入 `EquipmentCatalog`、`BuildState`、掉落、背包/UI 或旧池，也不生成或消费物品。

## Profile 契约

`NineSlotEquipmentProfile.bases()`、`affixes()` 和 `pool_profile()` 分别返回深副本。底材仍遵循现有目录的 `name / slot / size / description / stats` 结构；词缀仍遵循 `name / kind / group / stat / unit / label / slots / tiers`，tier 为 `tier / level / weight / min / max`。池 ID 列表只包含带 `nine_slot_` 前缀的新稳定 ID，`min_save_version` 为 14。

底材 `slot` 类别为 `ring / boots / belt / gloves / helmet`，分别采用 1×1、2×2、2×1、2×2、2×2 背包格。所有底材基础属性都来自已有角色属性名：`max_health / max_mana / max_shield / mana_regen / move_speed`。

| 类别 | 底材 ID | 原型基础属性 |
|---|---|---|
| ring | `nine_slot_etched_ring` | 生命 +4，魔力 +2 |
| boots | `nine_slot_trail_boots` | 生命 +3，移动速度 +1 |
| belt | `nine_slot_folded_belt` | 生命 +4，护盾 +2 |
| gloves | `nine_slot_threaded_gloves` | 魔力 +2，魔力恢复 +0.1 / 秒 |
| helmet | `nine_slot_slate_helmet` | 生命 +4，护盾 +2 |

## 原型数值依据

目前六种旧底材给出的相近基础量级包括：`woven_bastion` 生命 +12 / 护盾 +5、`tidebound_coat` 护盾 +10、`wayglass_token` 魔力 +6 / 魔力恢复 +0.3、`pulse_seed` 生命 +8 / 移动速度 +3；法器底材还有魔力 +8 / 恢复 +0.25。新底材取这些已有值的约三分之一到二分之一，目的是给新部位留下偏小的可读原型量级，不是最终预算或平衡结论。

共有三前缀与三种常规后缀。各 tier 的正权重沿用目录的 100 / 60 / 30 和物品等级门槛 1 / 8 / 16；数值仅是原型整数点/百分比刻度：

| 家族 | 属性 / 单位 | T1 | T2 | T3 |
|---|---|---:|---:|---:|
| `nine_slot_prefix_vitality` | 最大生命，点数 | 4–6 | 7–9 | 10–12 |
| `nine_slot_prefix_clarity` | 最大魔力，点数 | 3–4 | 5–7 | 8–10 |
| `nine_slot_prefix_aegis` | 最大护盾，点数 | 2–3 | 4–6 | 7–9 |
| `nine_slot_suffix_endurance` | 最大生命，点数 | 2–3 | 4–5 | 6–7 |
| `nine_slot_suffix_mana_flow` | 魔力恢复速度提高，百分比刻度 | 2–3 | 4–5 | 6–8 |
| `nine_slot_suffix_stride` | 移动速度提高，百分比刻度 | 1–2 | 3–4 | 5–6 |

前缀生命与后缀耐守会累加到同一属性，但 group 不同；这是有意保留的两个独立槽位家族。额外后缀 `nine_slot_suffix_skill_row` 只允许 `belt / helmet`，三个 tier 都只能掷出 `additional_skill_slots +1`。它仅描述将来可接入的语义，目前没有运行时消费者。

## 验证范围与限制

运行定向测试：

```sh
godot --headless --path . --script res://tests/nine_slot_equipment_profile_test.gd
```

测试检查新 profile 的字段形状、类别/尺寸/属性、tier 门槛、整数范围、正权重、组互斥，以及全部五种底材在 ilvl 1/8/16 的 3 前缀 + 3 后缀合法组合见证；也检查深副本和技能槽后缀的类别/+1 限制。为保护旧内容，它核对旧目录与既有冻结 fixture，并重放全部 432 个旧装备生成样本及 RNG 状态。

本次 Godot 4.6.3 定向运行通过：1,114 项断言，0 失败；容器运行时使用独立 `/tmp` XDG 数据/配置/字体缓存目录。

这不是掉落或实机平衡测试。实际 nine-slot 装备消费者、属性聚合、额外技能行、存档升级/回滚、获取来源、UI 表现与经济预算仍由主分支所有者集成和验证。当前 `EquipmentCatalog` 尚无 `nine_slot` profile；本文件不会让这些新 ID 出现在现有生成器中。
