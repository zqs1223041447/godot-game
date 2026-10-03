# 菜单路由状态模块验收

## 范围

`scripts/ui/menu_route_state.gd` 是纯状态模块：它把物理键码转换成一个独立菜单根视图的路由，并返回主控需要的暂停状态。模块不创建场景或控件，不读取 `InputMap`，也不修改 HUD、战斗或构筑数据。它尚未接入 `main.gd`，不代表现有菜单已改造。

每个路由都代表一个独立菜单根视图，而不是新标签页。任何时刻最多有一个根窗口；主控将路由标识映射到各自的独立场景：

| 来源 | 返回路由 |
| --- | --- |
| Escape（当前无窗口） | `pause` |
| 设置按钮调用 `request_window("settings")` | `settings` |
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

# 按钮回调可直接请求独立设置根窗口。
var settings_result: Dictionary = menu_route.request_window("settings")
```

`handle_key()`、`request_window()` 与 `current_state()` 返回新的字典，字段含义如下：

- `window`：当前唯一窗口的路由标识；空字符串表示没有菜单根视图。
- `paused`：当且仅当 `window` 非空时为 `true`，包括 `pause` 与 `settings` 根窗口。
- `action`：`open`、`switch`、`close` 或 `unchanged`，说明本次输入的状态动作。
- `changed`：本次输入是否改变了模块状态。

`request_window(id, toggle = false)` 接受 `pause`、`settings`、`inventory`、`passive_tree`、`skill_gems`、`debug_build` 和 `debug_monsters`。新 ID 替换当前根窗口；同 ID 且 `toggle = false` 返回未变化，同 ID 且 `toggle = true` 关闭该窗口。未知 ID 返回 `action = "unchanged"`。

快捷键打开相应根窗口，再次按同一入口关闭；切换时旧根由新根替代。Escape 在无根窗口时打开 `pause`；有任意根窗口时关闭当前根并返回 `window = ""`、`paused = false`。例如 `pause` → I 得到 `inventory`，再按 Escape 关闭窗口并恢复游戏。按键释放、echo 和未知键不改变快照。

## 验证

```sh
godot --headless --path . --script res://tests/menu_route_state_test.gd
```

该测试直接调用纯接口，不创建渲染节点，也不构造或派发键盘事件。它覆盖 I/B 同路由开关、T/K/F6/F7 切换、pause→inventory→Escape 回到游戏、代码请求 settings 后由 Escape 关闭、echo/释放/未知键，以及单根窗口和暂停返回状态。
