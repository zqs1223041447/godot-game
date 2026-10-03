# M1 物品悬停卡

## 组件范围

`scripts/ui/item_hover_card.gd` 是独立的只读 `Control`，不连接游戏入口，也不读取模型、钱包、词缀目录或库存。它只显示主控组装好的物品视图；主控继续负责悬停生命周期、Shift 状态、比较目标及装备槽选择。双戒指比较时，传入主物品和最多两个已装备目标，最多显示三张并排卡。

组件保留 `description`、`requirements`、`base_lines`、`affix_lines` 和 `effect_lines` 旧字段，也接受下列可选结构化字段。它不改写输入字典、不解析说明文本、不结算数值。空字段隐藏对应分区；长段落自动换行，长详情在卡片内纵向滚动。视觉沿用 `VisualTheme`、`MaterialFrame` 和项目羊皮纸/皮革资源，不新增主题资源或外部美术。

## 调用接口

```gdscript
var card := ItemHoverCard.new()
overlay_control.add_child(card) # overlay_control 是全屏普通 Control，覆盖在 HUD 上层
card.font_scale = preferences.font_scale
card.present(view, comparison_views, item_rect, viewport_bounds, compare)

# 指针离开物品与卡片交互区域后，由主控关闭：
card.dismiss()
```

`view` 形状：

```gdscript
{
    "uid": String,
    "name": String,
    "kind_label": String,
    "rarity_label": String,
    "description": String,
    "requirements": Array[String],
    "base_lines": Array[String],
    "affix_lines": Array[String],
    "effect_lines": Array[String],
    "tags": Array[String],
    "function": String,
    "base_stats": Array[Dictionary], # 每项 {"label": String, "value": String}
    "modifiers": Array[Dictionary], # 每项 {"label": String, "value": String, "polarity": String}
    "preview_lines": Array[String],
}
```

`tags` 作为紧凑标签显示；`function` 单独作为功能正文；`base_stats` 用两列键值布局；`modifiers` 按 `polarity` 显示增益、代价或中性标记。`polarity` 接受 `"benefit"`、`"cost"`、`"neutral"`。当前组合施放信息使用独立的 `preview_lines` 区块；为空时仍显示旧 `effect_lines`。同一文本同时出现在 `function` 和 `description` 时，只呈现一次。

`present(view, comparison_views: Array, anchor: Rect2, viewport_bounds: Rect2, compare: bool = false)` 每次以新快照刷新。`compare=false` 时只显示主物品；开启时从 `comparison_views` 读取前两个字典，其余忽略。`dismiss()` 隐藏控件，之后仍可再次 `present()`。

## 坐标、缩放与输入

- 将组件挂到全屏普通 `Control` 叠层；不要挂进会重新分配子项矩形的 `Container`。卡片相对锚点弹出，并在屏幕边界内自动选边或钳位位置。
- `anchor`、`viewport_bounds` 和组件父级必须使用同一局部坐标系。`anchor` 是物品矩形，`viewport_bounds` 是可见视口矩形；父级若像 HUD 一样按 UI 缩放，应传入对应缩放后的本地矩形。组件不会自行猜测世界坐标或做 CanvasLayer 坐标转换。
- UI 110% 由父级布局/变换负责；将当前字体偏好赋给 `font_scale`，120% 字体通过 `VisualTheme.apply_font_scale` 放大。宽度按列数与视口收缩，单列最大宽 360 个父级局部单位、最大高 680，长内容滚动。
- 绘制卡面与详情区对指针穿透；滚轮在指针所在的详情卡内滚动，不拦截下层物品的点击、拖动与放置。`NOTIFICATION_DRAG_BEGIN/END` 会隐藏并锁定卡片；外部拖拽系统也可调用 `set_drag_active(true/false)`。解锁不恢复旧卡，下一次悬停须再次调用 `present()`。此控件不读取 Shift，也不改变比较目标。

## 定向验收

执行：

```sh
godot --headless --editor --path . --import # 新检出且尚无 .godot 导入缓存时先运行一次
godot --headless --path . --script res://tests/item_hover_card_test.gd
```

定向测试覆盖 1920×1080 与 2560×1440、100%/110% UI 父级缩放、120% 字体、角落及左右三分之一锚点、三卡边界、双戒指上限、长词缀滚动、滚轮交互、输入字典不变、单卡模式及显隐。它检查 Godot 控件布局/边界与输入路由，不将 headless 几何断言称为像素验收。

在可用的桌面渲染会话中可保存布局截图：

```sh
ITEM_HOVER_CARD_CAPTURE_DIR=/tmp/item-hover-card-captures \
  godot --path . --script res://tests/item_hover_card_test.gd
```

该截图选项从运行中的根视口抓取 1080p/1440p 比较场景，不额外修改仓库文件。若运行环境没有桌面渲染设备/显示服务器，只能记录定向布局与输入测试结果；不能据此宣称已完成人眼像素验收。

## 本次执行记录

- Godot `4.6.3`：`tests/item_hover_card_test.gd` 为 **262 项、0 失败**；覆盖 1920×1080 / 2560×1440、四角锚点、100% / 110% 父级 UI 缩放、120% 字体、三卡限宽、滚动输入和字典只读。
- 既有 `tests/material_frame_test.gd` 为 **158 项、0 失败**，确认复用的材料样式回归通过。
- 已尝试非 headless 运行截图；该环境没有 X11 显示，Wayland 也无法连接，未安装 Xvfb/Weston。Godot 无法创建显示服务器，headless 渲染器也没有可抓取的 viewport texture。因此本次没有真实截图或像素验收证据；262 项结果只代表控件布局/边界和输入路由检查。

## 主集成原生补验（2026-10-03）

云桌面真实X11/llvmpipe运行发现原测试将物理窗口尺寸当逻辑视口，开启项目stretch后卡片会被摆到屏幕外；组件契约要求父级局部坐标，现夹具使用root.get_visible_rect，并对每张卡的真实输出像素取样。4张1080p/1440p、100/110%UI、120%字体原生图完成，288检查零失败。另修正空视图不显示、dismiss后修改字号不重新出现，并复制present输入避免后续外部变动影响旧悬停。证据在docs/qa/m1，不宣称Windows硬件或真实物理鼠标验收。

## v21 组件补验（2026-10-03）

- `tests/item_hover_card_test.gd`：197 项、0 失败。它额外从可见卡片覆盖下的物品槽发起 Viewport GUI 拖动，检查 `Control._get_drag_data`、下层放置目标和拖动锁；另测无卡快速拖放。此环境使用 headless Viewport 输入事件，能验证 GUI 路由，不等于物理鼠标验收。
- `tests/gem_icon_test.gd`：26 项、0 失败；覆盖宽/高纹理 aspect-fit、空纹理占位、主动/辅助标记角色与父槽拖放。
- `tests/unified_item_presentation_test.gd`：26 项、0 失败；覆盖 Catalog 能力、编译配方标签、SupportRegistry 家族/适用性与操作、静态基础属性和模型施放预览的分离、重复悬停缓存及只读快照。
- 本执行环境没有 `DISPLAY`、`WAYLAND_DISPLAY` 或 Xvfb，因此未生成真实渲染图，也未进行像素验收。用户提供的两张 Library 截图在授权 materialize 流程中未返回本地文件，按流程仅重试一次后仍不可读；已检查仓库中的羊皮纸与技能/宝石参考资源，但没有将它们当成用户截图。

## v21 输入路由复核（2026-10-03）

- 最新 `tests/item_hover_card_test.gd`：213 项、0 失败。用真实 `Viewport.push_input` 鼠标移动/按下/拖动/释放事件，在场景树顺序上先添加可拖动来源和放置目标，再把可见卡片添加到最前层；断言实际 hovered control、`_get_drag_data` 返回 UID、拖动期间卡片隐藏、目标收到了相同 UID，并捕获最终释放点 `(352, 204)` 落在目标矩形内。
- 测试包含负对照：把卡片 `ItemDetails` 临时改成 `MOUSE_FILTER_PASS`，实际 hover 落在其上，来源未产生 drag UID；恢复为 `MOUSE_FILTER_IGNORE` 后，同样的源点实际 hover 到下层来源，拖放成功。卡片中的容器、详情、基础属性 Grid、内部 ScrollContainer 与引擎生成的滚动条都断言为 IGNORE。此证明使用注入到 Viewport 的 GUI 事件，不代表物理鼠标验收。
- 卡片和底层库存 ScrollContainer 同时有溢出内容；指针位于卡片详情区时，滚轮只增加卡片的 `scroll_vertical`，并确认底层仍为 0。卡片在 `_input` 中移动详情滚动量后调用 `set_input_as_handled()`，阻止同一滚轮继续滚动底层。
- 拖放回调中的 `_drop_data(at_position)` 局部坐标在 headless 测试下与全局释放点不一致；测试使用目标当前矩形、`gui_get_hovered_control()` 和收到的 Viewport 鼠标释放坐标验证目标命中，没有将该局部回调坐标当作物理鼠标读数。
- 同轮 `tests/gem_icon_test.gd` 为 26 项、0 失败；`tests/unified_item_presentation_test.gd` 为 78 项、0 失败。
- 执行环境没有 `DISPLAY`、`WAYLAND_DISPLAY` 或 Xvfb，未生成本轮真实渲染图或像素验收结果。

## v21 标签芯片原生复核修正（2026-10-03）

- `ItemMetadata` 和 `ItemTags` 使用 `HFlowContainer`，在芯片之间换行。芯片文本宽度以现有主题字体及当前 `font_scale` 实测；面板内部用定宽单行标签，空间不足时显示省略号，完整标签保存在 tooltip 中，避免中文或长词被拆成窄列竖排。
- `tests/item_hover_card_test.gd` 最新结果：231 项、0 失败。专项夹具在 1920×1080、UI 110%、字体 120%、360 本地单位卡宽下检查“主动宝石”“等级 1 · 品质 0”及中文短标签实际测量宽度和单行行高；长 TAG 超出行宽时在标签间换行，并验证省略 chip、完整 tooltip 和卡片/视口边界。输入 PASS 负对照、IGNORE 拖放和卡片滚轮隔离也包含在本次通过结果中。
- 执行环境没有图形显示服务器，未生成像素截图；此修正提供布局几何和文本度量证据，仍由原生 owner 进行最终实际画面复审。
