# v0.84 防御保护时长：定向 Main 验证

入口：[utility_protection_duration_test.gd](../../../tests/utility_protection_duration_test.gd)。首次集中运行 **66项检查、0失败，exit0，4.237秒**，无脚本或测试错误。只运行这份实际Main集合一次，复用不变的旧消费者，不重跑历史套件、不导出Windows包。

测试通过真实 `main.tscn → leave_normal_town → cast_group` 进入竞技练习，使用默认已有的冲刺、结界宝石和当前编译消耗/冷却。没有赠送或修改装备、宝石、天赋、正式地图解锁及存档结构。为了确定性观察，测试停止自动 process、清空练习怪物、暂停自然生成，并控制玩家位置、运行时资源及保护计时；这不是自然游玩录像或性能基准。

覆盖以下同一缺陷的实际消费者：

- 单次冲刺0.6秒、结界0.8秒，以及原175距离、75%最大护盾回复、充能等待、耗魔及技能组冷却
- 结界→冲刺、冲刺→结界；保留较长剩余时间，既不缩短也不累加
- 已有1.5秒保护、保护流逝后的连续施放，以及较短剩余被新技能延长
- 缺魔、真实技能组冷却、暂停HUD阻塞拒绝，不改变已有保护或施放效果
- 真实 incoming hit 在保护内拒绝，在0.8秒精确截止后结算并保留原0.32秒受击保护
- 已附燃烧在保护内不扣伤，但寿命继续流逝；0.9秒整步和0.4+0.4+0.1秒分步只结算截止后的0.1秒，不补扣免疫期间伤害
- 成功辅助技能和燃烧不增加共享RNG或暴击RNG抽样；所有场景保留完整默认构筑及已保存字节

命中边界使用0.4+0.4秒分段，避免将0.8−0.7−0.1的浮点残余误当作规则失败。燃烧测试调用公开 `tick`，保留真实帧首 `_burn_immunity_until` 捕获和结算裁剪，不以直接 `_tick` 调用绕开该边界。

执行时为 `XDG_DATA_HOME`、`XDG_CONFIG_HOME`、`XDG_CACHE_HOME` 提供独立的 `/tmp/godot-m1-*` 目录，然后在项目根目录运行父任务已准备的 Godot：

```sh
godot --headless --path . --script res://tests/utility_protection_duration_test.gd
```

脚本输出总检查数、失败数与 `UTILITY_PROTECTION_RESULT` JSON，并以失败数决定退出码。生产变更限 `main.gd` 的两处 `maxf(existing, grant)`；不修改燃烧时钟、技能配方、地图、数值预算或存档迁移。

## 实际结果与证据

- [main-attempt01.log.txt](main-attempt01.log.txt) 与 [main-attempt01-result.json](main-attempt01-result.json)：唯一Main运行的原始输出、命令、隔离目录、4.237秒、退出码和结果
- 保护截止后的整步／分步结果均为原始燃烧10、生命130、护盾81.8、剩余燃烧2.1秒；没有补扣保护期伤害。时间和数值近似断言使用绝对误差小于1e-6，完整构筑和保存文件另作严格相等检查
- [tested-inputs.json](tested-inputs.json)：本次实际测试脚本及关键消费者哈希
- [production-boundary.json](production-boundary.json)：基线50a6eac到本批main精确只有两行替换；11个编译、运行时、模型、版本、字体、F8输入字节保持
- [import-result.json](import-result.json)：新工作树唯一首次资源导入26.609秒、exit0；该导入不计入66项检查

只核当前保护覆盖缺陷，不宣称扩展其他异常或提高性能。版本号与schema保持，不新增视觉素材和截图门槛。
