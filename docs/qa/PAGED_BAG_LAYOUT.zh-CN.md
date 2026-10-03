# 两页行囊布局规划器

## 范围

`scripts/items/paged_bag_layout.gd` 是不写状态的页面布局规划器：背包总容量为 **96 格**，拆为两页，每页 8 列 × 6 行。单件物品只能完整放在一页内，不旋转、不跨页。它不生成或销毁物品、不发奖励、不调用随机数、不写存档，也不修改传入的 metadata、locations 或物品 payload。

Canonical 模型当前仍使用旧的 12 × 8 `ItemLocationRules`。`plan` 的输入因此是旧 location 格式；输出 page location 尚不能直接交给当前模型、Store 或 HUD 提交。schema 15 的备份、原子迁移、位置校验与界面接入由主 owner 完成。

## 字段协议

旧输入 bag location 由现行 `ItemLocationRules` 校验，形如：

```gdscript
{"kind": "bag", "x": 0, "y": 0}
```

规划输出的新 bag location 必须精确包含以下四个字段，不接受别名或额外字段：

```gdscript
{"kind": "bag", "page": 0, "x": 0, "y": 0}
```

`page` 只能是整数 0 或 1；`x` 是 0..7；`y` 是 0..5。坐标、页码、尺寸及 recovery index 都拒绝布尔值与浮点值，即使浮点值恰好为整数。metadata 仍由旧规则严格限定为 `{kind, category, size}`，其中 size 为 `[width, height]`。旧系统可容纳但大于 8 × 6 的物品不能进页内格子，会进入可见 recovery。

## API

所有方法均为静态纯函数，成功和失败返回新字典，不保留调用方传入的可变容器引用。

| 方法 | 输入与用途 |
| --- | --- |
| `plan(metadata_by_uid, legacy_locations, context)` | 先用现行 `ItemLocationRules.validate` 完整验证旧表，再把所有旧 bag 物品按稳定顺序重排。非 bag 位置与已有 recovery 位置保持原值。 |
| `arrange(metadata_by_uid, paged_locations, context)` | 对已采用 page 坐标的有效表重新整理；已有 recovery 项保留。新放不下的 bag 项会进 recovery。 |
| `inspect_layout(metadata_by_uid, paged_locations, context)` | 严格检查 page 位置、物品种类、非 bag 目标和占用；只返回 detached 快照。 |
| `find_space(size, occupied_cells)` | 查询首个空位，不预留格子；按页 0 到页 1、逐行再逐列扫描。 |
| `check_placement(uid, size, location, occupied_cells)` | 检查单次候选放置；成功时返回含新 footprint 的 detached `occupied_cells`，失败不修改输入。 |

`context` 沿用 `ItemLocationRules` 六字段协议，`columns=12`、`rows=8`，并提供完整装备目标、技能行、珠宝孔 allowlist 与 `allow_recovery`。需要产生或保留 recovery 的调用必须允许 recovery。metadata/locations 的 UID 集合必须一一对应。

`find_space` / `check_placement` 的占用表以 `bag:<page>:<x>:<y>` 为键，以稳定 UID 为值。例如 `bag:1:7:5`。新掉落或卸下时，主控可先调用 `inspect_layout` 得到现有占用，再 `find_space` 取候选，最后 `check_placement` 验证完整 footprint；事务 owner 仍需把唯一 location 候选送过最终 schema 校验和持久化边界。整理操作可调用 `arrange`。

## 排序与 recovery

规划不采用旧坐标的截断或线性折算。先按面积降序、长边降序、宽度降序、UID 字典序升序排列 bag 项，再使用 page 0 优先的 row-major first-fit 搜位。物品尺寸固定，不尝试旋转。此顺序只依赖输入内容，不依赖 Dictionary 插入顺序。

大于单页尺寸的物品以 `item_exceeds_page` 原因进入 recovery；尺寸可放入单页但当前布局没有连续空间时，以 `no_paged_space` 进入 recovery。原有 recovery 位置与 index 不改，新项依次使用小于物品总数的最小空闲非负 index，不与已有 index 冲突。结果的 `recovery` 是按 index、UID 排序的审计数组，每项 `{uid, index, reason}`。规划不会因格子不足丢弃 UID 或 payload。

`plan`、`arrange`、`inspect_layout` 的成功结果包含：

- `locations`：完整 UID 到位置表。
- `recovery`：已有及新建待安置项的审计记录。
- `occupied_cells`：页内每格的唯一 UID。
- `occupied_targets`：装备、珠宝孔、技能槽与 recovery 的唯一目标表。
- `ok=true`、空 `error_code` 和空 `reason`。

失败时 `ok=false`、`error_code`/`reason` 明确，且 `locations`、`recovery`、两种 occupancy 均为空；不会暴露半成品。单项寻位 API 单独返回 `location` 与 detached 占用快照。

## 专项验证

运行：

```sh
godot --headless --path . --script res://tests/paged_bag_layout_test.gd
```

专项测试覆盖 96 个单格、旧边缘多格重排、单页边界、超宽 item 的 recovery、已有 recovery index 与冲突、非 bag 目标/UID 保持、输入深快照、字典顺序确定性、两页满包拒绝、严格整数/尺寸/字段、检查与整理 API 以及 RNG 不变。此记录不代表全项目 suite、schema 15 存档迁移或 HUD 已验收。
