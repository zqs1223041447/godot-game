# GemIcon 宝石图标

## API

`scripts/ui/gem_icon.gd` 定义 `GemIcon`（`Control`）。创建后可通过导出字段或单一方法配置纹理、无障碍名称和主动/辅助宝石的角标：

```gdscript
var icon := GemIcon.new()
slot.add_child(icon)
icon.set_gem_icon(gem_texture, "奥术飞弹", "active")
# 辅助宝石用 "support"，显示相连节点角标。
icon.set_gem_icon(support_texture, "凝束辅助", "support")

# 空纹理也会显示中性宝石占位；父槽仍可处理自己的鼠标与拖放。
icon.set_gem_icon(null, "未配置宝石", "active")
```

- `texture: Texture2D`：原图；按比例缩放，不拉伸。空纹理会绘制中性宝石轮廓。
- `accessible_label: String`：无障碍名称输入，输出为该名称加“图标”。
- `gem_role: String`：`"active"` 或 `"support"`，分别显示交叉符文或相连节点角标。
- `set_gem_icon(source: Texture2D, label: String = "宝石", role: String = "active") -> void`：同时设置以上三项。
- `aspect_fit_rect(source_size: Vector2, bounds: Rect2) -> Rect2`：把纹理 aspect-fit 到给定矩形。
- `image_fit_rect(control_size: Vector2, source_size: Vector2) -> Rect2`：返回渲染实际使用的图像矩形，含居中方形图框与固定 6 个逻辑单位内距。
- `square_tile_rect(control_size: Vector2) -> Rect2`：返回控制矩形内居中的方形图框。

图框复用项目 `VisualTheme` / `MaterialFrame` 的羊皮纸和旧铜边框，另有细内框和角部刻线。组件及其绘制没有子 `Control`，`mouse_filter` 恒为 `MOUSE_FILTER_IGNORE`，因此父容器继续接收点击与拖放。

## 定向验收

执行：

```sh
godot --headless --editor --path . --import # 新检出且尚无 .godot 导入缓存时先运行一次
godot --headless --path . --script res://tests/gem_icon_test.gd
```

测试覆盖 null 与真实 `ImageTexture`、宽高比保持、居中内距、方形图框、角色标记配置、无障碍标签与真实 Viewport 拖放路由。headless 测试没有像素图像可供目视验收。

## v21 执行记录（2026-10-03）

Godot 4.6.3：26 项、0 失败。当前环境没有桌面显示服务器；本次检查几何和 GUI 事件路由，没有生成或声称完成真实屏幕像素验收。
