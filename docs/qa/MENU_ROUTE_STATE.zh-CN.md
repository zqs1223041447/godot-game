# 菜单路由状态模块验收

## 范围

`scripts/ui/menu_route_state.gd` 是纯状态模块：它把物理键码转换成一个独立菜单根视图的路由，并返回主控需要的暂停状态。模块不创建场景或控件，不读取 `InputMap`，也不修改 HUD、战斗或构筑数据。它尚未接入 `main.gd`，不代表现有菜单已改造。

每个路由都代表一个独立菜单根视图，而不是新标签页。主控将路由标识映射到各自的独立场景：

| 快捷键 | 返回路由 |
| --- | --- |
| I / B | `inventory` |
| T | `passive_tree` |
| K | `skill_gems` |
| F6 | `debug_build` |
| F7 | `debug_monsters` |

## 纯接口

主控预载模块并创建实例，再将 `InputEventKey.physical_keycode`、`pressed` 和 `echo` 传给：

```gdscript
const MenuRouteState = preload("res://scripts/ui/menu_route_state.gd")
var menu_route = MenuRouteState.new()

var result: Dictionary = menu_route.handle_key(event.physical_keycode, event.pressed, event.echo)
```

`handle_key()` 与 `current_state()` 返回新的字典，字段含义如下：

- `window`：当前唯一窗口的路由标识；空字符串表示没有菜单根视图。
- `paused`：主控应暂停游戏模拟时为 `true`。任一菜单窗口打开时为 `true`；空窗口也可处于暂停状态。
- `action`：`open`、`switch`、`close`、`pause`、`resume` 或 `unchanged`，说明本次输入的状态动作。
- `changed`：本次输入是否改变了模块状态。

路由键打开窗口、切换窗口或再次按同一入口关闭窗口。切换时旧路由已由新路由替代，因此至多有一个窗口。按键释放、echo 和未知键返回 `action = "unchanged"`，不改变当前快照。

Escape 有窗口时关闭窗口；没有窗口时切换“仅暂停”状态。首次空窗口 Escape 返回 `window = ""`、`paused = true`、`action = "pause"`；再次按下返回 `paused = false`、`action = "resume"`。打开菜单会继续报告 `paused = true`；关闭后恢复之前的仅暂停状态。若此前没有仅暂停状态，关闭窗口后 `paused` 为 `false`。主控可据此分别处理独立根视图的创建/销毁和游戏暂停。

## 验证

```sh
godot --headless --path . --script res://tests/menu_route_state_test.gd
```

该测试直接调用纯接口，不创建渲染节点，也不构造或派发键盘事件。它覆盖 I/B 同路由开关、T/K/F6/F7 路由切换、echo 与释放、未知键、Escape 关闭窗口、空窗口暂停与恢复，以及返回字典中的窗口/暂停状态。
