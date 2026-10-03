# 停靠菜单状态验收

本改动新增独立的纯状态对象，不创建控件，也不改现有路由、HUD、人物模型、存档或输入映射。状态对象只记录：左侧内容 `left`（空、`skills`、`character`）、右侧行囊 `right_inventory`、单一全屏层 `overlay`（空、`talents`、`pause`、`settings`、`death`、`combat`、`monsters`）、停靠栏打开顺序，以及死亡锁定标志。

## 布局契约

- 左侧技能与角色属性共用左侧三分之一；两者互斥。请求当前左侧内容会关闭左栏，请求另一种内容会在左栏内切换。
- 行囊固定在右侧三分之一。左侧栏与右侧行囊可以同时打开。
- 天赋是覆盖左右栏的全屏层。打开和关闭天赋只改变 `overlay`，保留当时的左栏内容、行囊开关和停靠栏打开顺序。
- 任一停靠栏或覆盖层存在时 `paused` 为 `true`。死亡锁定即使在主控显式关闭死亡画面后仍保持暂停。

这里定义状态语义，不负责渲染或调整窗口尺寸；实际布局接线属于后续 UI 路由工作。

## API

文件：`scripts/ui/docked_menu_state.gd`。通过 `preload("res://scripts/ui/docked_menu_state.gd").new()` 创建；不读写游戏数据或用户文件，也不读取 Godot 的全局 `Input` 状态。

- `request(name: String) -> Dictionary`：UI 请求 `inventory`、`skills`、`character`、`talents`、`pause`、`settings`、`death`、`combat` 或 `monsters`。行囊、技能、角色和天赋采用明确的 toggle 语义；`pause` / `settings` / `combat` / `monsters` 请求打开或切换到对应层。
- `handle_key(key: String, echo: bool = false) -> Dictionary`：只路由 `I` / `B`（行囊）、`K`（技能）、`T`（天赋）、`F6`（战斗调试层）、`F7`（怪物调试层）和 `Escape`。调用者把键名与 `InputEventKey.echo` 显式传入。自动重复事件会被识别但不会再切换状态。字符 `C` 和其余按键不由此对象处理，原有技能键/快捷键可继续由宿主路由。
- `close(target: String = "escape") -> Dictionary`：默认按 Escape 顺序处理：先关普通覆盖层，再关闭最近打开的停靠栏，均无菜单时打开暂停层。也可指定 `left`、`inventory` / `right`、`overlay` 或 `death` 进行定向关闭。
- `snapshot() -> Dictionary`：返回可安全修改的深副本，不会通过返回值反向更改对象。

`request`、`handle_key` 与 `close` 返回 `{accepted, changed, state}`。未知请求/按键返回 `accepted=false` 且不改变状态；被覆盖层挡住或死亡锁定拒绝的已知请求同样不改状态。`state` 含 `left`、`right_inventory`、`overlay`、`paused`、`death_latched` 和从早到晚的 `open_order`。

F6 与 F7 共用同一个 `overlay` 字段：F6 选择 `combat`，F7 选择 `monsters`；按相同键可关闭当前调试层，两键也可直接相互切换。Escape 关闭调试层后恢复原有的左右栏状态及顺序。这里仅选择 UI 状态，不调用怪物生成；F7 面板已有的“进入 / 重置试验场”和“100 怪视距试验”按钮仍由主控的 `start_monster_demo()` / `start_density_demo()` 处理，主控决定何时生成怪物。

Escape 在死亡锁定期间是已消费的无操作。`close("overlay")` 不会关闭死亡画面；主控可显式调用 `close("death")` 隐藏它，但 `death_latched` 与 `paused` 会保留，因而不会复活或恢复战斗。状态对象不提供游戏重开逻辑；只有主控完成实际的重开流程后，才应以新实例替换旧实例。

## 自动化覆盖

`tests/docked_menu_state_test.gd` 覆盖左右停靠栏并开、左栏互斥、T 前后保留两栏和顺序、F6/F7 调试层互切与关闭、UI `combat` / `monsters` 请求、Escape 恢复两栏、最近栏关闭、无菜单时进入暂停、键盘 echo、未知请求、C 键保持未接管、快照深副本，以及死亡锁定和显式关死亡画面的边界。

另跑既有 v0.21 入口用例：`menu_route_state_test.gd` 124 项、`independent_menus_test.gd` 33 项、`monster_integration_test.gd` 87 项、`density_integration_test.gd` 2025 项，均通过。它们验证真实 F6/F7 根窗口和主控“进入 / 重置试验场”“100 怪视距试验”按钮路径；这些生成入口仍由主控调用。

运行：

```sh
godot --headless --path . --script res://tests/docked_menu_state_test.gd
```
