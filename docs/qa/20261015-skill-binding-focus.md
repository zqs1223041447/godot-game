# 技能绑定键盘焦点滚动核验（2026-10-15）

## 范围与结论

基线 `554ce88`，本地分支 `dot/20261015-skill-binding-focus`。生产修改仅在 `CanonicalSkillPanel._build()` 为技能行容器设置 `follow_focus = true`。使用 Godot 内建焦点跟随，不增加延迟滚动回调、不修改全局焦点策略，宝石孔仍为 `FOCUS_NONE`。

真实 Tab / Shift+Tab 原先能到达下方绑定下拉框，但滚动容器不跟随，导致焦点、文本和交互中心落在裁剪区外。修复后的 10 行和支持的 11 行夹具均通过全部矩阵；关闭跟随的负向对照仍稳定失败。

本记录为 Linux Godot 4.6.3 headless 的输入、逻辑几何和状态回归。不是 Windows 实机、原生像素截图或性能验收；未声称边框逐像素完整包围。本批进入本地提交保全；远端发布因 PUBLISH-001 暂停，未推送、创建 PR 或合并。

## 夹具与矩阵

- 实例化真实 `scenes/main.tscn`，使用 canonical model 与真实技能面板
- 10 行为默认容量；11 行通过独立 RNG seed `91414` 生成真实 rare/nine_slot 装备，并经 `move_item` 装备附带 `additional_skill_slots` 的物品；未伪造快照或手改容量
- 导航前持久化夹具，并冻结场景/HUD 更新；不把夹具初始化写入计入导航行为
- 物理窗口请求 1280×720、2560×1440；均断言实际逻辑视口仍为 1280×720（canvas_items）
- 字体比例 1.0/1.1/1.2 × UI 比例 0.9/1.0/1.1，每容量 18 个组合
- 每组合只设置初始滚动和第一项焦点；随后以真实 `InputEventKey` Tab 遍历到末项，Enter 打开末项绑定下拉框，Escape 经正确 window ID 的 `Input.parse_input_event` 真实关闭，确认不可见后才 Shift+Tab 逆序返回
- headless 显式嵌入子窗口；没有 `id_pressed` 伪成功、程序性隐藏冒充 Escape，或在弹窗未关闭时继续遍历
- 正反遍历每一步核对实际焦点顺序、滚动裁剪区和逻辑视口中的文本/内容区及交互中心；验证向下和向上确实产生滚动
- 每组合恢复原始 `follow_focus` 值，负向注入不会泄漏至下一组合

## 几何容差的含义

滚动偏移为整数，而 UI 变换可为小数。边框包围断言仅允许纵向一个本地整数滚动单位加浮点误差：

`abs(rows.get_global_transform().get_scale().y) + 0.001`

UI 1.1 下已观察到约 1.10004 个逻辑像素的残余边缘裁剪，因此不能用固定 1 像素断言，也不能宣称像素级边框全包围。横向仅保留 0.001 浮点误差。绑定样式上下文本内边距为 4 本地单位；测试另外从实际 normal StyleBox 内容边距计算文本/内容区域，对该区域和交互中心使用严格裁剪区及视口检查，不套用边框容差。未为此额外改变生产滚动行为。

## 已执行结果

| 运行 | 检查 | 失败 | 退出码 |
|---|---:|---:|---:|
| 最终测试，默认 10 行 | 3303 | 0 | 0 |
| 最终测试，真实装备 11 行 | 3629 | 0 | 0 |
| 10 行关闭 follow_focus 负向对照 | 3303 | 326（预期） | 1 |
| 11 行关闭 follow_focus 负向对照 | 3629 | 506（预期） | 1 |
| 既有 skill_group_rows_test | 55 | 0 | 0 |
| 既有 skill_support_ui_test | 368 | 0 | 0 |

负向对照中：10/11 行分别有 62/98 次边框检查失败、62/98 次内容区检查失败、58/94 次交互中心检查失败，另有逻辑视口与未发生滚动的失败；全部 18 个组合仍完成。没有焦点顺序、弹窗打开/关闭、状态守卫或恢复跟随标志的失败。证明测得的是滚动可见性回归，而非错误的弹窗输入导致后续遍历失效。

导航前后完整模型快照、canonical 与 practice 存档字节、设置文件字节、运行修订号、冷却账本、场景 RNG 和全局 RNG 保持一致。每组合的所有展示设置也保持不变。

## 复现

每个进程使用全新的 XDG 目录，外层 `timeout 90`，测试内部另有 75 秒 watchdog；不执行 editor/import。

```sh
D=$(mktemp -d /tmp/godot-skill-focus-recheck-XXXXXX)
XDG_DATA_HOME=$D/data XDG_CONFIG_HOME=$D/config XDG_CACHE_HOME=$D/cache \
  timeout 90 godot --headless --path . --script tests/skill_binding_focus_test.gd
```

另外分别在新目录进程运行以下用户参数：

- `-- --capacity11`
- `-- --disable-follow-focus`（预期退出 1）
- `-- --capacity11 --disable-follow-focus`（预期退出 1）

既有组件回归：`tests/skill_group_rows_test.gd`。当前集成回归 `tests/skill_support_ui_test.gd` 要求独立的 `/tmp/godot-m1-*` XDG 根；其他前缀会被隔离保护以退出码 78 拒绝，不能计为产品失败或通过。

## 独立复验与本地保全

独立复验报告见 [20261015-skill-binding-focus-review.md](20261015-skill-binding-focus-review.md)。复验时源码、测试与本记录的 SHA-256 均已核对一致；此后仅更新本记录的交付状态并补充本节，源码与测试未改变。正向 3303/3629 项通过，负向 326/506 项均为预期可见性/滚动失败，无阻塞发现。上述重复执行不累加为不同功能数量。

提交仅包含该一行生产修复、回归测试、两份 QA 记录及当前任务台账；生成的 `.uid` / `.import` 未纳入。增量 bundle 以本地最后核验的 `origin/main`（`14de6cd`）为前置，包含此前未发布提交；不会改写或 rebase 其历史。远端恢复需另获明确许可。
