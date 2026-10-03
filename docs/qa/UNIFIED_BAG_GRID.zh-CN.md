# Unified UID 背包格控件

## 范围

`scripts/ui/unified_bag_grid.gd` 是仅负责显示与输入转译的 `Control`。父级提供当前背包条目、revision 和投放校验，并接收移动请求；控件不读取 `BuildState`、不判断物品实际状态、不保存，也不改接旧背包、主场景、HUD 或主题。`set_items(entries, revision)` 的 `entries` 必须只含背包条目；已装备或已镶嵌记录应由父级排除。

每项使用 `{uid:String, kind:String, size:Vector2i, cell:Vector2i, art:Dictionary, icon:Texture2D|null, accent:Color, short_name:String}`。`kind` 只接受 `equipment`、`jewel`、`skill_gem`、`support_gem`；未知类型会被拒绝，不会回退绘成装备。字典、数组及嵌套美术数据在 `set_items` 时深拷贝；纹理作为 Resource 引用保留。无效结构、重复 UID 和越出 12×8 的占格不会展示。装备/珠宝复用 `EquipmentArt.draw_item(art)`；主动技能宝石和辅助宝石必须提供真实 `Texture2D` 并走 icon 绘制分支。

## 格子与悬停坐标

逻辑格固定为 12 列 × 8 行，默认每格 42 个逻辑像素，外缘至少留 8 个逻辑像素。控件空间缩小时按宽高限制选择同一格距并居中缩小棋盘；控件变大不会把默认格子放大。格子绘制、坐标转换、命中、抓取偏移、落点与物品占格都使用同一个计算出的格距。

`cell_at_position(point)` 与 `cell_rect(cell)` 使用控件本地逻辑坐标，外缘留白不属于可命中的格子。`item_rect(uid)` 返回物品完整占格矩形。`item_hovered(uid, anchor)` 的 `anchor` 是 `get_global_transform() * item_rect(uid)` 得出的 canvas 逻辑坐标矩形；悬停层应使用自己的全局变换逆变换为局部坐标。不要乘以 2K 物理窗口比例。

## 信号和拖放

- 左键发出 `item_selected(uid)`；双击或右键发出 `item_activated(uid)`。控件不决定装备、使用或详情行为。
- 悬停目标变化时发出 `item_hovered(uid, anchor)`；离开条目发出 `hover_left()`。
- 拖动 payload 严格为 `{type:"unified_item", uid:String, revision:int, grab_offset:Vector2i}`。拒绝多字段、缺字段或错误类型。
- 父级通过 `set_drop_validator(Callable)` 提供 `(uid, destination, revision) -> bool`。destination 固定为 `{kind:"bag", x:int, y:int}`。越界占格、无效偏移、revision 过期、缺少校验器或校验器拒绝都会使预览为红色且不发移动请求；有效预览为绿色。
- `move_requested(uid, destination, revision)` 只在通过重新校验的有效投放时发出一次。刷新到新 revision 会使进行中的旧 payload 失效；父级仍需在事务层复核 UID 和目标。

## 验证

首次运行时先让 Godot 导入项目资源，再运行独立契约/输入路由测试：

```sh
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/unified_bag_grid_test.gd
```

测试覆盖输入快照深拷贝、四种合法 kind 与两种宝石 Texture2D 绘制分支、无 icon 宝石及未知 kind 拒绝、96 格中心与边缘映射、缩小格距后的坐标一致性、多格抓取偏移、严格 payload、校验器拒绝、越界、一次性信号、旧 revision 拒绝，以及通过 `Input.parse_input_event` 和 `Viewport.push_input` 进入 Godot GUI 路由的选择、激活、悬停和原生 Control 拖放流程。

headless 路由测试只证明引擎输入分发与几何契约；它没有真实显示器，也不读取渲染像素，因此不作为外观或 2K 像素验收。需要用真实图形窗口检查材质对比、标题/图标可读性、不同窗口尺寸下的格子观感和父级悬停层定位。`.agents/skills` 在本次基线仓库中为空。
