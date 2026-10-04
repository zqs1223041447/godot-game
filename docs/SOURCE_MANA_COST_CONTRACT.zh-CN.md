# v0.34 全局技能魔力成本取舍

仅接无条件全局“increased Mana Cost Efficiency”和“increased Mana Cost of Skills”。标准源7效率节点、2成本增加节点的其他效果已有消费者；不接法术限定、诅咒/链接/印记或生命转费，不把效率当线性reduced。完整节点所有效果仍需实现才可分配。

- mana_cost_efficiency_increased：源百分数/100相加，非负有限
- mana_cost_increased：源百分数/100相加，非负有限
- 施放快照仅非零时有resource_modifiers；零值缺省不改变旧快照或编译输出字段
- 十主动最终mana = 原辅助后mana × (1 + 成本增加) / (1 + 成本效率)。保原辅助浮点相乘顺序，最后一次应用本公式；全零直接返回旧数值。保持当前浮点扣费，不引入整数舍入
- 非零编译结果可带cost_factors：support_mana/increased_cost/increased_efficiency/numerator/denominator/final_mana；K永久摘要与tooltip仍直接读最终compiled.mana

这是明确的本游戏资源公式，不声称完整PoE公式。基本自动攻击仍免费，成本不改伤害/半径/弹速/护盾即时效果/冷却债务。坏字段、布尔/负值/非有限、分母不合法或中间结果溢出拒绝；无空间/冷却/法力不足的施放不扣费。取消/换选沿现有权限事务。

schema22：严格旧21验证和原字节备份后仅改版本；19/20/21执行词汇门槛与对应迁移输出锁定，旧21注入新成本节点拒绝。保UID、进度、物品、辅助组/键位、点数与revision，无赠物赠点。

本批冻结412份旧零/单/双辅配方以及2普通攻击编译结果；十主动真入口与所有合法双辅的成本组合/顺序/边界集中验证。新增数据同源进入图鉴，原字体/贴图能复用则按哈希复用。不做600秒或历史全量。
