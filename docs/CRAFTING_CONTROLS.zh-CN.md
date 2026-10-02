# 制作操作行

> v0.15已接入游戏的回收/校准与持久化，见[制作集成](CRAFTING_INTEGRATION.zh-CN.md)。下文保留独立组件交付时的接口边界；不能把纯组件说明当作完整游戏事务。

[crafting_controls.gd](../scripts/ui/crafting_controls.gd) 是一个 `VBoxContainer`，内部只有一行：`校准碎片 N`、`回收`、`校准`。按钮使用现有 `VisualTheme.panel()` 的手绘纸面、棕色墨迹与焦点描边，字号基准为 13。可通过现有 `VisualTheme.apply_font_scale()` 缩放文字；刷新上下文不会重建按钮或重置字号。超长余额可省略显示，完整数值保留在 tooltip 中。

基线为制作分支提交 `f23dcc4d9267a098301b07574390d5077b95867b`。本分支仅新增控件、独立测试和本文档。实际挂载位置、`InventoryPanel` 接入、制作事务与持久化由统一接入方完成。

## 上下文与请求

```gdscript
const CraftingRow = preload("res://scripts/ui/crafting_controls.gd")

var controls := CraftingRow.new()
controls.craft_requested.connect(_on_craft_requested)
detail_container.add_child(controls)

# 参数由上层读取、校验并报价；可在 add_child 前设置上下文。
controls.set_context(item_id, source_instance, material_balance,
    salvage_quote, recalibrate_quote, disabled_reason)

func _on_craft_requested(operation: String, item_id: String, source_instance_copy: Dictionary) -> void:
    # 将 operation、ID 和原快照交给制作事务边界。
    # 接入方须重新核对所有权、当前实例、穿戴状态、余额与存档保护状态。
    pass
```

完整接口：

```gdscript
set_context(item_id: String, source_instance: Dictionary, material_balance: int,
    salvage_quote: Dictionary, recalibrate_quote: Dictionary,
    disabled_reason: String = "") -> void

signal craft_requested(operation: String, item_id: String, source_instance_copy: Dictionary)
```

`source_instance` 与两份报价均在传入时深复制。每次信号再提供独立的原实例副本；订阅方修改该副本不会影响后续点击。操作标识为 `salvage` 与 `recalibrate`。

真实鼠标或键盘按下时冻结请求的 ID 与原实例。按下至松开之间切换到另一件可制作物品，仍发送原快照，上层据此拒绝陈旧事务；切换到禁用状态立即取消动作。拖出按钮取消的手势会清理待发送快照。重复调用 `set_context()` 不增加信号连接，每次有效点击只发出一次请求。

控件不调用 `BuildState`、`Craft` 或随机数 API，不执行扣款、物品替换、回收删除、属性刷新或存档。发出请求后，显示余额保持原值，直到上层提供新上下文。

## 报价字段与禁用规则

报价结构直接遵循现有 [CraftingRules](CRAFTING_RULES.zh-CN.md)：

| 字段 | 控件行为 |
| --- | --- |
| `ok` | 必须为 `true`；失败报价禁用对应操作 |
| `reason` | 失败 tooltip 原样显示；空原因使用通用不可用提示 |
| `materials.calibration_shard` | 回收 tooltip 展示实际获得的碎片数量 |
| `cost.calibration_shard` | 校准 tooltip 展示实际成本；余额小于成本时禁用校准 |

数量必须是非负整数。缺字段、空报价、布尔值、字符串、负数和非整数成本均失败关闭。余额不足只影响校准，回收无需余额。控件直接比较传入成本，不根据回收收益推导价格，也不硬编码当前原型的经济公式。

上层通过 `disabled_reason` 禁用两个动作，例如空选择、固定装备、穿戴中或原存档受保护。该原因优先于报价失败及余额不足，tooltip 原样显示。未提供选择时，控件也保持禁用；控件不会自行读取装备栏或存档保护信息。

当前 Craft 提供 `salvage_quote(instance)` 与 `recalibrate_plan(instance, seed_value)`。上层可把实际返回结构交给控件；控件仅读取上述字段，忽略 `instance`、`definition`、`source_instance`、`seed` 及其他结果字段。校准界面只展示成本和数值可能不变或降低的说明，不展示预先生成的随机结果、派生属性或 seed。正式接入方负责报价与提交时机。

## 独立测试

[crafting_controls_test.gd](../tests/crafting_controls_test.gd) 不加载主场景或模型。测试从真实 `EquipmentCatalog` 构造合法实例，并调用实际 Craft 生成报价，覆盖全部 9 种底材、失败原因、余额边界、上层禁用原因、深复制、陈旧点击、取消手势、每次点击信号数量及全局 RNG 不受影响。

布局检查覆盖宽度 220 / 280、字体 100% / 120%，验证根控件不撑宽、同一行不重叠、五位余额完整可见、极长余额 tooltip 完整、按钮各状态沿用手绘边框。

测试要求设置 `GODOT_CRAFTING_TEST_ROOT`，且运行时实际 `OS.get_user_data_dir()` 必须位于该目录之内，否则直接失败。Windows 应为该进程隔离 `APPDATA` 与 `LOCALAPPDATA`；Linux 应隔离 `XDG_DATA_HOME`、`XDG_CONFIG_HOME` 与 `XDG_CACHE_HOME`。编辑器便携模式的 `_sc_` 仅用于隔离编辑器数据，仍须实际核验 `user://`。不要直接运行未隔离的主工程。

在已证明隔离的工程副本上执行：

```text
Godot --headless --path <独立工程副本> --editor --import
Godot --headless --path <独立工程副本> --script res://tests/crafting_controls_test.gd
Godot --headless --path <独立工程副本> --script res://tests/crafting_rules_test.gd
```

本次在 Windows 官方便携版 `4.6.3.stable.official.7d41c59c4` 的独立工程副本中实际执行：

- 隔离探针与控件测试均确认 `user://` 位于任务的独立 `roaming/Godot/app_userdata/` 下。
- 控件测试：228 项检查、0 失败；包含实际鼠标按下/松开与四组宽度、字号检查。
- 原制作规则测试：9 底材、19 词缀族、91 合法配对、57 家族阶级、2415 个计划；91707 项检查、0 失败。
- 两份测试的 Godot 进程退出码均为 0；启动另有 `ERROR: Failed to read the root certificate store.`。严格日志检查因此返回失败，不能把整次运行记作无错误通过；未更改权限或绕过该读取限制。
- 现有 `arena_sans.otf` 的 cmap 缺少新增文字“价、报、收、校、片、碎”。统一接入方应使用现有 `tools/subset_font.py` 将这些文字补入字体子集，保证显示不依赖系统字体回退。本分支按限定范围未修改字体资产。

未执行主场景接入、真实游戏存档、完整回归及人工画面/实际 tooltip 弹窗检查。当前 tooltip 验证针对文本内容与控件尺寸。
