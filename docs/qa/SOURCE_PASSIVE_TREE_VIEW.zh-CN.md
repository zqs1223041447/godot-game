# M3 只读源被动树拓扑视图

## 范围

新增 `SourcePassiveTreeView` 作为独立 `Control`。组件接收调用方整理的节点字典和无向边列表，只显示所给坐标、连接、节点类型及父级提供的状态。它不接入主控、树数据、分配器或存档；不判断可分配资格，不计算点数或效果。

此组件没有加载、复制或重绘上游图像。节点用原创几何线条绘制，配色沿用项目现有羊皮纸、黄铜、橄榄与酒红主题。节点位置始终来自输入 `position`；连线始终连接输入 `a`、`b` 的位置，不做圆环重排、布局推断、边过滤或拓扑修正。

## 接口

```gdscript
func set_tree(nodes: Dictionary, edges: Array, focus_id: String) -> bool
func set_allocation_state(state: Dictionary) -> void

signal node_clicked(id: String, button: int, double_click: bool)
signal node_hovered(id: String, anchor: Rect2)
signal hover_left
```

`nodes` 以 ID 为字典键；每个节点需含匹配的 `id`、`Vector2 position`、六种允许类型之一（`small`、`notable`、`keystone`、`mastery`、`socket`、`start`）以及字符串 `name`、`description`、`status`。`edges` 中每项需含字符串端点 `a`、`b`，且两端必须存在。验证在提交前完成；无效输入返回 `false`，当前图保持原样。空 `focus_id` 合法；非空时必须指向节点。

`set_allocation_state` 接收 `allocated`、`available`、`remote` 字符串数组，`socket_ranges`（中心、半径、激活标志）及 `selected_id`。组件只把这些值画出来，不推导分配状态。`node_hovered` 的锚点是经 Control 画布变换后的逻辑坐标矩形，不乘物理像素比例。

滚轮以指针下的树坐标为缩放锚点；空白处拖动平移。拖动阈值为 7 个逻辑坐标单位；节点点击与空白平移分别处理。`fit_tree()` 可按当前 Control 逻辑尺寸缩放以容纳输入坐标边界。`world_to_screen()` 和 `screen_to_world()` 供外层 UI 检查/复用相机变换。

可见节点通过建树时生成的世界网格筛选；边使用线段与视口矩形相交裁剪，因此两端都在屏外、但线段穿过视口时仍会绘制。建树成本为 O(V+E)，节点命中查询只检查邻近网格单元，绘制时边裁剪扫描 E 条输入边。只在输入、交互、分配状态或尺寸变化时请求重绘，不启用逐帧处理；绘制期间不复制完整图。仅更新名称/描述/状态而焦点和坐标不变时保留相机。

## 自动化验证

运行：

```sh
# 首次在此工作区运行时导入项目资源
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/source_passive_tree_view_test.gd
```

测试从 `data/passive_source/normalized_tree.json` 的 `standard_tree.default_allocation_graph` 构建真实夹具，逐项对照 2,387 个节点、2,697 条边及其端点顺序和原坐标。另覆盖未知端点拒绝与原子性、调用方输入不变、平移/缩放逆变换、鼠标命中/悬停/点击、锚点滚轮缩放、点击阈值和空白拖动、两端在屏外但穿过视口的连线，以及 1280×720 与 2560×1440 的逻辑坐标锚点。

## 验收边界

当前环境没有可供像素审阅的图形显示器。Godot headless 自动化可验证图数据、输入和几何裁剪行为，但**不构成像素级视觉验收**，也未验证 Windows 原生窗口、真实物理鼠标/DPI、不同显卡后端或游戏主场景集成。此交付仅新增视图、测试和本文档。

请求指定的 `codex/restructure-m1` 远端分支提交 SHA 写为 `af09b5f864a4a70ae3996a8bee8e959c45c5b8c1`；远端该分支实际指向 `af09b5f864a4a70ae3996a8bee8e959c45c5b8c8`，本分支从该远端引用提交建立。
