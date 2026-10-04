# v0.39 暴击合同

当前玩家新增基础暴击几率 5%、基础暴击伤害 150%，这是明确的平衡变化。普通自然敌人继续零基础暴击。本游戏沿用已有确定性命中/闪避判定；攻击未命中不造成暴击伤害，不增加第二次命中确认。

- 玩家普通攻击和八种伤害主动技能在施放获准后冻结一次主命中结果。同次范围命中、连锁、母/子弹体及返回共享它；换装备/退点不追溯改变已在飞行的快照。闪步、护盾技能不抽取暴击。
- 每次真实自然飞行结束产生的独立爆炸另抽取一次，仅采用冻结时的全局暴击属性；同一爆炸内所有目标共用。碰墙/分裂消耗/命中消耗/取消不产生爆炸或额外抽取。
- 暴击几率为基础几率 × (1 + 全局与匹配作用域的增加之和)，限制 0–100%；倍率为基础倍率 + 匹配的倍率百分点。九种支持源句式的真实原值进入同一规则。条件、武器限定、幸运、触发及伤害持续效果仍锁定。
- 倍率在伤害加成之后、抗性与按命中大小结算的护甲之前应用。护盾→生命顺序不变。UI命中预估明确为非暴击，不假装平均伤害/DPS。
- 暴击使用独立随机流；初始化读取主随机流的seed值而不抽取该流。0%或100%不需要随机数；0%/缺失旧配方不增加结果字段或改变原浮点运算。失败施放在抽取前拒绝，龙卷发射意外失败还原独立流检查点。
- 缓存中的编译结果只有概率/倍率；运行中已决结果放入分离的施放快照，不能反向写入构筑/存档。schema24只开放相应完整源节点；v23与更旧输入仍按自己的词汇表验证，再原字节备份与迁移。

## 稳定接口

`compiled.critical.primary` 与可选 `secondary` 均为 `{chance, multiplier}`。`chance=0.05` 表示5%，`multiplier=1.5`表示150%。无伤害技能不含该字段。`compiled.snapshot.critical`是同源冻结副本。实际施放生成 `snapshot.critical_roll={critical,multiplier,chance}`；未暴击的运行倍率为1。

基础统计：`crit_base_chance`, `crit_base_multiplier`；增加统计：`crit_chance_increased`, `attack_crit_chance_increased`, `spell_crit_chance_increased`, `melee_crit_chance_increased`, `projectile_attack_crit_chance_increased`；倍率统计：`crit_multiplier_add`, `spell_crit_multiplier_add`, `melee_crit_multiplier_add`, `projectile_attack_crit_multiplier_add`。

本批不增加暴击特效、暴击触发、幸运、武器局部暴击、毒或异常机制，也不改技能/行囊布局。
