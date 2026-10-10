# K空孔：选择已有且兼容的行囊宝石

基线main：`75266eddc78a8ee07b6545cef939cf6e4c1e0884`；分支 `codex/owned-gem-slot-picker`。

## 玩家价值与边界

现有技能组只有拖放装配入口，空孔左键无操作；行囊中宝石右键仅提示去K界面。本批为原空孔增加点击选择入口，让玩家直接看到已有的可用构筑组件。

生产仅改 `skill_group_rows.gd` 与 `canonical_skill_panel.gd`。原槽位发出带当前revision与位置的空孔请求；控制器只遍历bag中的对应种类，并逐个调用现有 `can_move_item`。当前组合的兼容性、重复辅助和最终保存仍由原 `move_item` 与Canonical规则决定，不复制一套装备规则。条目保留准确UID，只填空孔，不从已装备行或待安置区搬运。

候选只存在于当前打开的菜单；模型变更、面板隐藏、重新setup、取消或确认消费都会清除。成功操作刷新原编译预览。未装主宝石时辅助菜单提示先装主孔；没有候选时明确显示空状态。原拖放、右键取回和已占用孔行为保持。

## 最终验证

- `tests/owned_gem_picker_test.gd`：X11实际渲染 **42项、0失败，exit0**。复用合法40物理碎片夹具，经原正式购买事务取得1颗主动、2颗节能、1颗缓速强击、1颗霜锁，共5个真实UID；不是自然赚钱验收，也没有给生产新增赠送。
- 真实鼠标点击空孔，使用原生菜单Enter确认：主孔仅列bag主动；飞弹辅助列出两个独立节能和缓速强击，排除仅适用于冰霜的霜锁；装上一个节能后另一颗被原重复规则过滤。选择移动准确UID且保存一次，物品字典/序号不变，重复回调无副作用。
- 覆盖取消只读、缺主宝石、无候选、独立revision变化后的陈旧信号、强制写失败保持内存/磁盘、关闭带有效候选的菜单、已占用孔不替换、重新加载原UID/位置。原右键取回与拖放都继续经过同一移动事务。
- 装入节能后原预览即时更新；进入原免费旧庭I档，实际V键通过Main施放本组，耗魔等于当前编译结果且低于装配前。仅验证一次实际施放，不声称命中、自然清图或全套辅助矩阵。
- 既有 `skill_group_rows_test.gd` **55项、0失败，exit0**，原测试不改。覆盖原拖放、陈旧快照、绑定和布局。
- 新增运行时中文字体cmap覆盖完整，没有字体或美术修改。Godot4.6.3，1280×720，Xorg dummy/Mesa llvmpipe；实际查看下方截图，菜单可读、贴近目标孔，并在屏幕底部自动约束位置。不宣称其他分辨率或Windows验收。

当前schema59、物品/商店/保存/伤害/地图代码未改。只有操作入口变化，没有新宝石效果或执行状态，因此内容数据库不添加虚构条目；中文操作提示及[用户说明](../../OWNED_GEM_PICKER.zh-CN.md)已更新。没有模型、封包、全套或长检测。

## 迭代记录

- `main-01`40项/8失败：真实缺陷是原生PopupMenu在`id_pressed`之前自动隐藏，取消回调清除了待选UID，导致确认没有移动。菜单现在关闭原生选择自动隐藏，由确认函数先取走UID/revision，再显式关闭并提交；取消路径仍立即清理。没有放宽原事务检查。
- `main-02`40项/0失败。实际截图发现分隔标题白字不清晰，改为使用既有深色禁用项作为标题；同时将关闭菜单检查改成真实有效候选，并补上实际施放的两项检查，最终`main-03`42/0。
- 两轮旧截图保存在`attempt-01/`与`attempt-02/`；不累计通过数。最终日志只有虚拟显示器VSync警告，无脚本错误。

## 截图

- [主动宝石选择](active-choice.png)
- [辅助宝石筛选](support-choice.png)
- [无可用宝石](no-compatible-gems.png)：底部保存失败提示来自本测试前一步主动注入的写失败，用于验证原反馈和回滚，并非最终运行脚本错误。

## 复现

使用新的隔离目录及实际可用的DISPLAY；截图目录须存在。

```bash
timeout 45s env DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 XDG_DATA_HOME=/tmp/godot-owned-gem-picker-review XDG_CACHE_HOME=/tmp/godot-owned-gem-picker-review-cache GEM_PICKER_REPORT=/tmp/owned-gem-picker.json GEM_PICKER_CAPTURE_DIR=/tmp godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/owned_gem_picker_test.gd
timeout 30s env XDG_DATA_HOME=/tmp/godot-owned-gem-picker-rows-review XDG_CACHE_HOME=/tmp/godot-owned-gem-picker-rows-review-cache godot --headless --path . --script res://tests/skill_group_rows_test.gd
```

最终输入、报告和截图指纹见 `verification.json`。
