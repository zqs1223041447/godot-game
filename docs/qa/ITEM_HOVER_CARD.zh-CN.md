# M1 物品悬停卡

## 组件范围

`scripts/ui/item_hover_card.gd` 是独立的只读 `Control`，不连接游戏入口，也不读取模型、钱包、词缀目录或库存。它只显示主控组装好的物品视图；主控继续负责悬停生命周期、Shift 状态、比较目标及装备槽选择。双戒指比较时，传入主物品和最多两个已装备目标，最多显示三张并排卡。

组件逐字显示 `description`、`requirements`、`base_lines`、`affix_lines` 和 `effect_lines`，不改写输入字典、不结算数值。空字段隐藏对应分区；长段落自动换行，长详情在卡片内纵向滚动。视觉沿用 `VisualTheme`、`MaterialFrame` 和项目羊皮纸/皮革资源，不新增主题资源或外部美术。

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
}
```

`present(view, comparison_views: Array, anchor: Rect2, viewport_bounds: Rect2, compare: bool = false)` 每次以新快照刷新。`compare=false` 时只显示主物品；开启时从 `comparison_views` 读取前两个字典，其余忽略。`dismiss()` 隐藏控件，之后仍可再次 `present()`。

## 坐标、缩放与输入

- 将组件挂到全屏普通 `Control` 叠层；不要挂进会重新分配子项矩形的 `Container`。卡片相对锚点弹出，并在屏幕边角自动翻转/收拢。
- `anchor`、`viewport_bounds` 和组件父级必须使用同一局部坐标系。`anchor` 是物品矩形，`viewport_bounds` 是可见视口矩形；父级若像 HUD 一样按 UI 缩放，应传入对应缩放后的本地矩形。组件不会自行猜测世界坐标或做 CanvasLayer 坐标转换。
- UI 110% 由父级布局/变换负责；将当前字体偏好赋给 `font_scale`，120% 字体通过 `VisualTheme.apply_font_scale` 放大。宽度按列数与视口收缩，卡片最大宽 400 个父级局部单位、最大高 680，长内容滚动。
- 鼠标滚轮在指针所在的详情区域滚动该卡内容；滚动条可拖动。悬停所有者应允许指针从物品移入卡片，并在指针离开物品和卡片交互区域后再调用 `dismiss()`。此控件不读取 Shift，也不改变比较目标。

## 定向验收

执行：

```sh
godot --headless --path . --script res://tests/item_hover_card_test.gd
```

定向测试覆盖 1920×1080 与 2560×1440、100%/110% UI 父级缩放、120% 字体、四角锚点、三卡边界、双戒指上限、长词缀滚动、滚轮交互、输入字典不变、单卡模式及显隐。它检查 Godot 控件布局/边界与输入路由，不将 headless 几何断言称为像素验收。

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
