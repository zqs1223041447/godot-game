# 物品位置纯校验器

`ItemLocationRules.validate(metadata_by_uid, locations, context)` 是物品实例位置的纯校验入口。调用方先解析物品元数据，再提交完整的 UID→位置映射；此函数只接受或拒绝整份候选映射，不执行移动、保存、生成或销毁，不自动寻找空位，也不消耗全局 RNG。

## 输入契约

`metadata_by_uid` 与 `locations` 都必须是对象，且两者 UID 键集合必须严格相同。UID 是非空稳定字符串。每项元数据只能有以下三个字段：

```gdscript
{ "kind": "equipment", "category": "weapon", "size": [2, 3] }
```

`kind` 仅可为 `equipment`、`jewel`、`skill_gem`、`support_gem`。装备类别仅可为 `weapon`、`body_armour`、`amulet`、`ring`、`boots`、`belt`、`gloves`、`helmet`；其他 kind 的 `category` 必须是空字符串。`size` 必须是恰有两个真正整数的数组 `[width, height]`，范围为 `1..12 × 1..8`。布尔值和浮点值即使数值相等也无效。

每个位置值都必须是只含对应字段的对象：

| `kind` | 精确字段 | 约束 |
| --- | --- | --- |
| `bag` | `kind, x, y` | 真正整数坐标；物品矩形必须完全落入 12×8 背包 |
| `equipment` | `kind, slot_id` | 仅 equipment；类别必须匹配目标槽 |
| `passive_socket` | `kind, node_id` | 仅 jewel；孔 ID 必须由 context 授权 |
| `skill_main` | `kind, group_id` | 仅 skill_gem；技能行 ID 必须由 context 授权 |
| `skill_support` | `kind, group_id, index` | 仅 support_gem；行 ID 有效，index 是 `0..4` 真正整数 |
| `recovery` | `kind, index` | 迁移暂存位置；`allow_recovery` 开启时可用，index 是真正整数且 `0 <= index < metadata_by_uid.size()` |

所有输入对象均拒绝缺字段、额外字段、错误字段类型与未知 kind。每个 UID 必须且只能出现一个位置。只有 `bag` 位置参与矩形占格；已穿戴、已镶嵌和技能配置中的物品不占背包格。

`context` 必须恰含 `columns`、`rows`、`equipment_slots`、`skill_group_ids`、`passive_socket_ids`、`allow_recovery` 六项。列行数必须分别是整数 12 和 8。装备目标映射固定为：

```gdscript
{
  "weapon": "weapon", "body_armour": "body_armour", "amulet": "amulet",
  "ring_1": "ring", "ring_2": "ring", "boots": "boots", "belt": "belt",
  "gloves": "gloves", "helmet": "helmet",
}
```

两个 ID 列表必须是唯一、非空稳定字符串数组。`skill_group_ids` 应传入稳定技能行 ID 的完整配置集合；即使技能行当前未激活或不显示，也应保留其 ID，不能借此删除其主技能或辅助宝石。珠宝孔 ID 应由上层解析后传入。`allow_recovery` 必须是真正布尔值；普通移动设为 `false`。迁移时，上层可在一次明确的安置事务中打开它。recovery 索引范围独立按本次候选物品总数计算，因此 6 件或 12 件待安置物品分别可以使用 `0..5` 或 `0..11`；同一索引仍只能放一件。满包回收卸装由上层原子拒绝，校验器不会挪动、丢弃或暂存物品。

## 结果与稳定占用键

每次调用都返回完全相同的五字段结构。以下是一个成功结果示例；空背包/目标集合会返回空对象：

```gdscript
{
  "ok": true,
  "error_code": "",
  "reason": "",
  "occupied_cells": { "bag:0:0": "gear_000001" },
  "occupied_targets": { "equipment:weapon": "gear_000002" },
}
```

失败时 `ok` 为 false，`error_code` 给机器处理，`reason` 给日志或诊断使用，并且 `occupied_cells`、`occupied_targets` 总是空对象，不暴露部分累积结果。成功时占用表是新建副本，按 UID 排序构建；校验不修改任何输入，也不读取或推进随机数状态。

成功的 `occupied_cells` 使用 `bag:<x>:<y>` → UID，例如 `bag:11:7`。成功的 `occupied_targets` 使用以下编码 → UID：

| 目标 | 键编码示例 |
| --- | --- |
| 装备槽 | `equipment:ring_1` |
| 天赋珠宝孔 | `passive_socket:node_10` |
| 技能主槽 | `skill_main:row_a` |
| 技能辅助槽 | `skill_support:row_a:0` |
| 迁移暂存 | `recovery:4` |

这些键是调用方可直接消费的占用索引。不同 UID 不能占据同一背包格或同一目标；双戒指是两个独立槽，辅助宝石按技能行和 index 分别占位。

常用 `error_code` 包括 `invalid_input`、`invalid_context`、`invalid_metadata`、`invalid_location`、`location_set_mismatch`、`out_of_bounds`、`bag_overlap`、`kind_mismatch`、`target_mismatch`、`duplicate_target`、`recovery_disabled`。机器逻辑应依赖错误码，不应依赖中文 `reason` 文案。

## 边界与职责

本校验器信任调用方已解析的 `metadata_by_uid`；不证明完整物品 payload 的真实性，也不负责珠宝树连通性、技能与辅助的实际适配、卸装回包事务或保存主控。这些检查与原子写入仍由上层负责。失败不触发修正动作，调用方应保留原状态。

## 回归验证

运行：

```sh
godot --headless --path . --script res://tests/item_location_rules_test.gd
```

测试覆盖精确协议字段、UID 集合一致性、九个装备目标、珠宝孔与技能目标类别、稳定行和孔白名单、重复占位、恢复暂存开关、真整数/边界、12×8 占格碰撞、96 格容量，以及成功/失败输入纯度与 RNG 不变。
