# 人物面板：明确显示混沌免疫

基线 `384b2b7f2b2daf8d7bcc8a8e4169f136575f4e25`，独立分支 `codex/chaos-immunity-character-display`。显示改动 `a803a6f24f81e6d33916748fd780fbd06489dea5` 已通过独立只读审核；以下保留原验收及合入前的信号刷新补证。

唯一生产改动为 `scripts/ui/canonical_character_panel.gd`：从已经取得的 `model.get_stats()` 读取派生 `chaos_inoculation` 标记。启用时，原混沌抗性栏显示“免疫”，提示为：

> 混沌防护：最大生命为1，免疫混沌伤害。
> 原始混沌抗性 X.X% · 当前上限 75%

生命上限栏继续显示原派生 `max_health`，不另算生命。未启用和退款后沿用原百分比、原提示，逐字保持。抗性资料无效仍显示“—”。现有卡片、字号、字体、主题、布局与样式未改；没有新绘制。模型接口、抗性、伤害、schema59及F8均未改。

## 有限验收

`tests/chaos_immunity_character_display_test.gd` 在 Godot 4.6.3 headless 中创建真实 Main/HUD，通过 `open_panel("character")` 打开实际属性页。

- 两个完整校验的女巫10点前置、余1点夹具：无混抗，以及使用已有合法25%混抗指环。指环复用既有测试构造器，不是新增物品或自然掉落/成长证明。
- 每种数据执行未分配→实际分配11455→实际退款，以及隐藏时分配后重开、隐藏时退款后重开。
- 检查生命上限1、明确免疫文案、原始抗性/上限资料、退款后原百分比及提示精确恢复，确认普通混抗资料未改变。
- 打开/刷新前后比较模型快照、存档字节、保存计数、生命/魔力/护盾、RNG/暴击检查点及药剂运行状态；观察不产生修改。分配/退款本身只产生预期天赋/修订变化和一次保存，不把合法事务写盘误记为观察副作用。
- 测试中的当前生命设为0.5，用于分离UI观察与原机制容量钳制，避免把实际分配从高生命钳到1视为UI副作用。

原验收 `results-02.log` / `results-02.json`：**99 checks，0 failures**，exit0，无引擎/脚本错误。原文件逐字保留，JSON保存10个实际显示状态的文字。这些显示断言前主动调用了 `refresh()`，不能单独证明自动刷新。仅此有限UI检查，没有全套检测、游戏导出、模型工作或完整美术验收；未另行截图。

首次 `results-01` 失败源于测试把既有装备槽误写为 `ring1`（正确为 `ring_1`），被完整校验拒绝，另有日志字符串百分号转义笔误。修正夹具/日志后重跑通过，生产UI代码未因此更改；首轮记录保留，不计为通过。

## 合入前补证：真实信号自动刷新

`results-03.log` / `results-03.json`：**175 checks，0 failures**，exit0，无引擎/脚本错误；由重跑原99项及新增76项组成，不把历次运行累加为通过数量。

- 复用同一真实 Main/HUD 面板及两种合法抗性夹具；新增 `signal_flow()` / `signal_display_check()` 在分配、退款、隐藏期间分配后重开、隐藏期间退款后重开，共8个状态直接读取标签、完整提示和生命上限，不在断言前主动调用 `refresh()`。
- 模型变化由实际分配/退款事务发出 `changed`；连接计数器确认每次发出一次，等待一帧后检查刷新代数推进及显示结果。原有生产信号连接不修改、不手动发射信号。
- 为排除 HUD `open_panel()` / `_build_character_dock()` 的显式刷新，补证阶段关闭菜单路由后直接显隐已创建的左侧 HUD 容器。隐藏时确认刷新代数不变，重新显示后确认面板收到继承可见性变化的 `visibility_changed`，等待一帧再检查自动刷新。原99项仍覆盖正式菜单入口。
- 每次事务继续验证预期天赋/修订变化及恰好一次保存；重新显示和直接读取均检查模型、存档、保存计数、资源及运行状态不变。`signal_rows` 单列新增8个显示状态。

本次仅新增测试与QA证据，生产刷新逻辑、存档实现、模型及schema均未改；未运行全套回归、截图或封包。

## 复现

使用全新的隔离临时目录：

```bash
timeout 45s env XDG_DATA_HOME=/tmp/godot-ci-display-review XDG_CACHE_HOME=/tmp/godot-ci-display-review-cache CI_DISPLAY_REPORT=/tmp/ci-display-review.json godot --headless --path . --script res://tests/chaos_immunity_character_display_test.gd
```

分配、退款和保存均限于隔离夹具，没有读取真实玩家存档。`verification.json` 记录生产改动范围及交付文件指纹。
