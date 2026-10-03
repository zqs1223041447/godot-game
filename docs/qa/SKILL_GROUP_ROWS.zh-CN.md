# K 技能配置只读行控件

## 范围与调用

`scripts/ui/skill_group_rows.gd` 是独立的 `ScrollContainer`。调用方通过 `set_rows(rows, revision)` 传入只读快照，并用 `set_drop_validator(Callable(uid, destination, revision) -> bool)` 提供最终拖放校验。控件不连接主模型或 HUD，不写配置/存档，不计算法力、冷却或技能编译结果；`preview` 和 `preview_tooltip` 原样显示调用方给出的内容。

每行必须恰有以下字段；结构不合规的行会跳过，重复 `group_id` 不会产生歧义行，最多显示64行：

```gdscript
{
    "group_id": String,
    "name": String,
    "active": bool,
    "main": Dictionary,
    "supports": Array, # 恰有5个 Dictionary，按 index 0..4
    "preview": String,
    "preview_tooltip": String,
    "binding_keycode": int,
}
```

槽内容只能是空字典 `{}`，或 `{ "uid": String, "definition_id": String, "icon": Texture2D }`。输入快照的嵌套 Dictionary/Array 会深复制；同名技能按 `group_id` 和宝石 UID 区分。未激活行以灰色和“未激活”标记显示，宝石、绑定与位置数据仍保留，宝石槽仍可拖放整理。

目标地址只会是：

```gdscript
{"kind": "skill_main", "group_id": group_id}
{"kind": "skill_support", "group_id": group_id, "index": 0} # 0..4
```

来源 drag payload 严格为 `{ "type": "unified_item", "uid": uid, "revision": revision, "grab_offset": Vector2i }`。目标预检与放下时都重新调用父级 validator；当前修订不匹配、目标形状不合法、目标行已刷新或 validator 不接受时，不发 `move_requested(uid, destination, revision)`。右键非空宝石槽只发 `return_requested(uid, revision)`。宝石 hover 发 `item_hovered(uid, anchor: Rect2)`，其中 anchor 由 `get_global_transform_with_canvas()` 得到，使用 canvas 逻辑坐标；离开非空宝石槽发 `hover_left`。

绑定菜单包含“未绑定”(keycode `0`)、数字键0–9、F1–F5、F9–F12 和 E/F/G/H/J/L/Z/X/C/V/N/M。数字键0使用 Godot 的 `KEY_0`，与未绑定的整数0分开。选择动作只发 `binding_requested(group_id, keycode, revision)`；同一快照下重复选择同一目标会合并为一个请求。下拉框继续显示收到的快照，只有父级用新修订再次调用 `set_rows` 后才显示被接受的绑定。字体可通过 `font_scale` 设为0.8–1.6，默认继承现有主题并沿用 `VisualTheme` 羊皮纸控件样式。控件最小高度按10行计算，视口更高时可显示约12行；更多行纵向滚动。

## 定向接口测试

```sh
godot --headless --path . --script res://tests/skill_group_rows_test.gd
```

测试覆盖输入深副本、同名不同 UID、重复刷新/选择、精确 drag payload、revision 过期、父级拒绝、第五辅助槽地址、右键回收、hover 逻辑坐标、绑定选项的数字0/未绑定区分、未激活整理、窄宽120%字体与64行上限。Headless 结果验证控件接口、布局边界和事件，不等同于真实渲染像素验收。

## 本次执行记录

Godot 4.6.3 headless 定向接口/布局测试为 **49 项、0 失败**。尚未完成人眼像素验收；该结果不覆盖 K 父级接线或真实窗口绘制。集成到 K 界面后应在实际视口与最大 UI/字体比例补做渲染检查。
