# 九目标装备槽目录

本批只增加纯目录 `scripts/items/equipment_slots.gd`、定向测试和本说明。它提供九个装备目标与八个物品类别之间的静态映射，不持有背包或装备状态，不实现装备提交、物品生成或数值平衡。

## 固定词汇

| 目标槽 ID | 类别 |
| --- | --- |
| `weapon` | `weapon` |
| `body_armour` | `body_armour` |
| `amulet` | `amulet` |
| `ring_1` | `ring` |
| `ring_2` | `ring` |
| `boots` | `boots` |
| `belt` | `belt` |
| `gloves` | `gloves` |
| `helmet` | `helmet` |

槽位目标是九项固定、有序的 ID。戒指类别有两个独立目标，按 `ring_1`、`ring_2` 排列。目录只认表内的精确字符串；例如 `armor`、`charm` 和类别名 `ring` 都不是规范槽位 ID。

## API 契约

- `all_slots() -> Array[String]`：按上表顺序返回全部九个目标。
- `category_for_slot(id) -> String`：返回规范目标所属类别；未知值或非字符串返回空字符串。
- `targets_for_category(category) -> Array[String]`：返回该类别可用目标；未知类别或非字符串返回空数组。
- `legacy_slot(id) -> String`：规范目标 ID 原样返回；仅迁移 `armor` → `body_armour`、`charm` → `amulet`。其他未知值返回空字符串。此迁移不会由其他 API 隐式执行。
- `target_reason(category, target) -> String`：有效组合返回空字符串；无效组合返回稳定错误码。验证顺序先类别、再规范目标、最后类别匹配。

`target_reason()` 的错误码如下：

| 错误码 | 含义 |
| --- | --- |
| `unknown_category` | 类别未知或不是字符串 |
| `unknown_slot` | 目标未知或不是字符串 |
| `category_mismatch` | 类别和目标各自有效，但目标不属于该类别 |

所有数组查询都返回副本。调用方修改返回数组不会改变后续目录结果。`target_reason()` 不接受迁移别名作为目标：例如 `target_reason("body_armour", "armor")` 返回 `unknown_slot`；调用方需要迁移时应显式调用 `legacy_slot()`。

## 定向测试

`tests/equipment_slots_test.gd` 检查九个目标及类别、双戒指映射、两个旧名的迁移边界、未知/非字符串输入、稳定错误码和返回数组隔离。测试不读取或写入游戏存档，也不调用装备/UI/战斗流程。

在 Linux 仓库根目录执行：

```sh
QA_ROOT="$(mktemp -d /tmp/godot-equipment-slots-XXXXXX)"
export XDG_DATA_HOME="$QA_ROOT/data"
export XDG_CONFIG_HOME="$QA_ROOT/config"
export XDG_CACHE_HOME="$QA_ROOT/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
godot --headless --path . --script res://tests/equipment_slots_test.gd
```

本测试只证明目录 API 契约，不代表主场景、存档迁移、穿脱事务或游戏平衡已集成。
