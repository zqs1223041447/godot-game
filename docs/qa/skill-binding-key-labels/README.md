# K技能组：显示的按键与实际施放一致

基线main：`d4af6874b1b52c3e786b8295c8a96e63efb50aa0`。分支：`codex/skill-binding-key-labels`。

## 目标和实际缺口

先核过现有装备对比、天赋分配/退款提示、技能组装配和地图余敌方向；这些功能已经存在。本批选择一个直接影响构筑操作的实际错误，不新增相似地图词缀。

技能组下拉的键码表已经移除保留键C，但独立文字表仍保留C，导致末尾错位：玩家看到C实际绑定V，看到V实际绑定N，看到N实际绑定M，M不显示。修复前在实际Main的K界面复现：34项检查中4项失败；`baseline.json`记录准确键码86/78/77及缺失M。没有用历史待办推测缺口。

唯一生产文件为 `scripts/ui/skill_group_rows.gd`：删除独立标签表，直接由实际键码生成文字，键码0仍独立显示“未绑定”。可绑定键集合、原绑定事务、键冲突转移、保存和冷却逻辑均不变。已有存档仍按原保存键码执行；不擅自猜测玩家当时意图并重写绑定，界面现在准确显示实际生效的键。C继续打开角色属性。

## 验收

- `tests/skill_binding_keys_test.gd`最终X11 **58项、0失败，exit0**。实际K键打开原技能面板；弹出原下拉、定位可见V/N/M条目，以真实Enter事件确认；真实V/N/M输入分别通过Main施放飞弹、冰霜和新星，按各自编译成本扣魔力并建立冷却。
- 原保存路径每次变更保存一次，不增加UID；重复选择无操作；占用键沿原语义转移到新组且旧组显示未绑定；注入保存失败后旧绑定/磁盘字节保持，控件恢复原显示；V/N/M重载不迁移或改写文件。
- 真实C键仍只打开属性面板，不施放；冷却中改绑Z保持原债务，实际Z输入不能绕过冷却。当前schema59不变。测试使用新建合法角色和原免费旧庭I档，没有购买、赠送或修改货币/物品夹具，不运行AI或自然清图。
- 既有 `skill_group_rows_test.gd` **55项、0失败，exit0**。仅将已过期的32选项断言修正为当前31项：未绑定+30个合法键；新集成检查另行与Canonical规则的完整合法键列表比对。原拖放、失效快照、去重和布局检查沿用。
- 自主查看[下拉按键](picker.png)和[绑定后的三行](bound.png)：V/N/M可见、顺序正确，原羊皮纸样式和滚动列表保留。Godot4.6.3，1280×720，隔离Xorg dummy与Mesa llvmpipe；日志仅含虚拟显示器VSync警告，无脚本错误。不宣称Windows或其他键盘布局实机验收。

首次测试脚本的局部变量缺少显式Dictionary类型，解析失败记录保存在`parse-01.log`；修正后才执行修复前基线及修复后流程。保留基线真实失败，不累加测试轮次。

只修复已有玩法入口，没有新增技能效果，不需要内容数据库增加条目；原C保留键合同已经正确。混沌庇护相关文件、schema、模型、美术和封包均未改。没有执行全套或长检测。

## 复现

使用新的隔离目录和实际可用的X11 DISPLAY；截图目录须存在。

```bash
timeout 45s env DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 XDG_DATA_HOME=/tmp/godot-skill-binding-review XDG_CACHE_HOME=/tmp/godot-skill-binding-review-cache BINDING_REPORT=/tmp/skill-binding-review.json BINDING_CAPTURE_DIR=/tmp godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/skill_binding_keys_test.gd
timeout 30s env XDG_DATA_HOME=/tmp/godot-skill-binding-rows-review XDG_CACHE_HOME=/tmp/godot-skill-binding-rows-review-cache godot --headless --path . --script res://tests/skill_group_rows_test.gd
```

`verification.json`保存最终源码、报告和截图指纹。生产修复无保存格式或键码变化；如果玩家曾按旧误标配置，当前界面会显示原来真正保存的键，需要按本人意图重新选择。
