# 灰烬守卫蓄力火纹可读性

基线：`b4bbb2502dc85a7ba26b699534890b315a4ca668`。本批只优化既有稀有灰烬守卫 `ember_guard` 的 `locked_circle / ember_burn` 预警，不继续装备词缀审计。

## 发现与验收目标

原实现已有真实伤害圆、随蓄力逐渐完成的火纹以及命中后燃烧反馈，并非缺失攻击预警。原生截图显示火纹在圆心上方，角色站在锁定圆心时容易被身体和头顶文字遮挡。目标是让低特效下的火纹与蓄力进展清楚可见，同时保留完整伤害圆，不遮挡角色、不增加图元。

## 最小实现

只改 `scripts/visuals/telegraph_renderer.gd`：把现有五点火纹移至圆内下方，适度放大，并以较粗深色底线承托米色描线。仍使用原蓄力进度与恢复期消退；落击后仍变灰。火纹不是缩小的伤害区，圆周始终表示完整范围。无模型改动、霓虹光效、新粒子、独立时钟或新伤害规则。

## 原生截图检查

全部是当前 Main 场景、1280×720、Godot 4.6.3 / X11 / Mesa llvmpipe 的原始截图。

| 状态 | 修改前 | 修改后 |
| --- | --- | --- |
| 低特效，蓄力 15% | [原图](baseline/low-early.png) | [原图](after/low-early.png) |
| 低特效，蓄力 85% | [原图](baseline/low-late.png) | [原图](after/low-late.png) |
| 完整特效，蓄力 85% | [原图](baseline/full-late.png) | [原图](after/full-late.png) |
| 原攻击落击 | [原图](baseline/impact.png) | [原图](after/impact.png) |

人工看图结论：修改后火纹在脚下可见，早期深色底纹与后期逐渐完成的亮线可区分；圈界和战场主体保持清楚。落击截图保留原护盾损失、燃烧反馈和灰色恢复提示。

## 有限验证与边界

- [基线日志](baseline.log)：29 检查、0 失败；[最终日志](after.log)：358 检查、0 失败。最终额外包含图元与其他图案对照检查，两个数字不作为等量测试比较。
- 正式旧花园入场后，以受控夹具生成一个现有稀有灰烬守卫，调用现有 Main 攻击启动和结算路径；不是自然刷怪长时间游玩记录。
- 验证真实命中一次并附加原燃烧、恢复期不重复命中、离开锁定圆后躲避成功；冻结时钟、出生保护、来源死亡/移除、重开均正确取消或清理。
- 四组截图的攻击状态与事件在修改前后完全一致，所有非火纹图元相同；绘制不改变存档、模型快照、随机数或战斗状态。详见 [范围核对](preservation.json) 与两组 `report.json`。
- 63 组其他图案×元素×特效组合的图元字节完全一致；原 100 来源 / 800 图元上限和超限整组拒绝保持。没有新增绘制调用或怪群扫描；本批不作帧率提升结论。
- 其他 661 个运行时文件和资源、图鉴目录数据保持字节一致。F8 仅补充 `monster_attacks-locked_circle` 一张说明卡，其余 3817 张不变，21808 个内部链接有效，生成结果检查通过。
- 初次夹具误用 BurnRuntime API 的失败日志保留于 [fixture-attempt-01.log](fixture-attempt-01.log)，已更正夹具后重新完整执行上述有限检查。原生驱动不支持设置 VSync 的警告不影响截图及检查结果。

## 复验入口

`tests/ember_warning_readability_test.gd` 复用现有正式地图夹具。运行需可用 X11 显示，隔离的 `XDG_DATA_HOME=/tmp/godot-ember-warning-<本次名称>`，以及 `EMBER_WARNING_OUT` 输出目录；以 `timeout 45 godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/ember_warning_readability_test.gd` 执行。已完成的本批不重复运行。

`baseline_renderer.gd` 是上述基线绘制文件移除 `class_name` 后的只读测试对照，由 `.gdignore` 隔离，不接入生产。范围核对脚本为 `verify_scope.py`，图鉴检查为 `python3 tools/build_reference.py --check`。`manifest.json` 记录本批交付文件的 SHA-256。
