# v0.7 有类型的附加伤害

## 范围与兼容承诺

本版本只增加固定点数的「攻击附加物理／火焰」「法术附加冰霜／闪电」伤害。点数来自原创装备词缀已经生成并保存的掷值；一次命中不再掷伤害区间。

旧版 damage（界面「伤害 +N」）仍是所有既有技能共用的固有基础 B。没有将旧装备、被动或珠宝的 damage 重新解释成武器局部伤害。新增点数为零时，所有旧命中和独立爆炸的数值保持不变。此版本不实现武器局部词缀层、端点区间、命中随机、暴击、持续伤害、异常状态或伤害转换。

## 唯一组装公式

对每个实际伤害类型 t：

```text
intrinsic[t] = B × intrinsic_distribution[t] × base_coefficient
added[t]     = applicable_added[t] × added_effectiveness
raw[t]       = intrinsic[t] + added[t]
```

base_coefficient 和 added_effectiveness 是独立字段。当前大多数技能的原创默认值恰好相同，但两者不能从另一字段推算。DamageBaseCompiler 只负责这一步；DamageResolver 仍负责按实际类型与事件标签累计 increased、连乘 more，再读取命中当时目标的减伤。附加元素伤害加入完整原始伤害包后，同样接受相应元素、法术、攻击元素、投射物与辅助增减伤。

龙卷的「物理 60%、火焰 40%」是固有伤害分布，不是物理转火焰。分布只作用于 B。攻击附加物理完整加入物理分量，不能再拆成 60/40。

## 实际事件与原创默认值

| 事件 | 固有分布 | 基础系数 | 附加效用 | 命中标签 |
| --- | --- | ---: | ---: | --- |
| 普攻投射物 | 物理 100% | 1 | 1 | hit / projectile / attack |
| 龙卷母箭 | 物理 60%、火焰 40% | 1 | 1 | hit / attack / projectile |
| 龙卷子箭 | 物理 60%、火焰 40% | 0.7 | 0.7 | hit / attack / projectile |
| 奥术飞弹 | 闪电 100% | 1.6 | 1.6 | hit / projectile / spell |
| 冰霜脉冲 | 冰霜 100% | 0.85 | 0.85 | hit / projectile / spell |
| 奥能新星 | 闪电 100% | 2.7 | 2.7 | hit / spell / area |
| 陨星坠落 | 火焰 100% | 4.3 | 4.3 | hit / spell / area |
| 连锁闪电第 i 跳，i=0…4 | 闪电 100% | 2.2 − 0.2i | 2.2 − 0.2i | hit / spell / chain |
| 独立终焰爆炸 | 火焰 100% | 0.9 | 0 | hit / area / secondary / explosion |

附加点数必须匹配实际 hit + attack 或 hit + spell 事件。终焰爆炸由普攻、龙卷、飞弹或冰弹携带时，都没有 attack、spell 或 projectile 标签，都不继承附加点数、投射物辅助 more 或法术增伤。它保留原载体的 skill_id 供来源追踪使用。自然结束、分裂、返回、碰撞消耗与取消的触发顺序保持既有规则。

闪光冲刺与守护结界没有伤害包。普攻可组装攻击伤害，但没有新增支持槽位或技能支持资格。

## 数据权威

- CombatData.TORNADO：母／子箭移动参数、各自 coefficient 和 added_effectiveness，以及独立爆炸配方
- GameData.SKILLS.bolt/frost.projectile_recipe：已有发射参数和固有 damage_type、coefficient，新增独立 added_effectiveness；其他位置不重复定义飞弹系数
- GameData.SKILLS.nova/meteor.hit_recipe：base_coefficient、added_effectiveness 和 damage_type
- GameData.SKILLS.chain.hit_recipe：上述字段、bounce_count，以及彼此独立的 base_coefficient_loss_per_bounce 与 added_effectiveness_loss_per_bounce
- BuildState：汇总装备固定点数并构建攻击／法术作用域数据；所有旧 damage 规则不变

## 快照与编译接口

CombatData.snapshot(stats, effects) 总是增加 detached 的零默认映射：

```text
added_damage = {
  attack: {physical: attack_added_physical, fire: attack_added_fire},
  spell: {cold: spell_added_cold, lightning: spell_added_lightning}
}
```

可选 added_damage_sources 是每件已装备词缀的原始固定点数来源记录数组，每条严格为：

```text
{item_id, affix_id, stat, scope, damage_type, value}
```

stat 只允许上述四个键，scope 与 damage_type 必须和该键一致。value 必须为有限非负数。来源是解释数据，不会再参与一次求和；伤害计算以 added_damage 映射为准。组装记录只保留匹配实际攻击／法术事件的来源，独立爆炸不带攻击／法术来源。所有嵌套来源均深拷贝。

公开接口：

```text
DamageBaseCompiler.assemble(base_damage, recipe, added_damage = {}, added_damage_sources = [])
CombatData.event_packet(snapshot, skill_id, role = "direct", index = 0)
CombatData.secondary_packet(snapshot, skill_id)
CombatData.tornado_packet(snapshot, role)  # 兼容旧接口；explosion 等同 secondary
SkillCompiler.compile_skill(skill_id, snapshot, support_ids)
```

DamageBaseCompiler 的 recipe 严格包含七个字段：stage="hit_base"、intrinsic_distribution、base_coefficient、added_effectiveness、tags、skill_id、role。类型分布必须非负且总和为 1。当前阶段不接受 local_weapon、conversion 或其他执行阶段。

成功编译保留原有 recipe、initial_count、mana、cooldown、support_ids，并新增 packets。快照带 compiled_skill_id 和与顶层 packets 相互独立的 compiled_packets：

- tornado：parent、child、secondary
- bolt / frost：projectile、secondary
- nova / meteor：direct
- chain：bounces，为五个完整 Dictionary 组成的数组
- dash / ward：空 Dictionary

非投射物技能的 recipe 仍为空。所有已编译快照都拒绝再次编译，防止双重辅助应用；即使移除 initial_count，任一 compiled_packets／compiled_skill_id 标记或 support: 修饰器仍阻止重入。

伤害包继续提供 base、tags、skill_id，新增 role 与 assembly。assembly 包含 stage、intrinsic、added、base_coefficient、added_effectiveness，以及可选匹配来源。这里的 intrinsic / added 是各阶段已乘相应系数的点数，便于逐类型复核。

ProjectileRuntime 使用快照中冻结的母箭、子箭及独立爆炸包。既有直接测试调用者没有编译标记时，才使用已经深拷贝的施放快照通过统一组装器生成子箭／爆炸。若编译标记、伤害包或来源技能不合法，则返回空包，不绕过验证重新生成。自然结束函数不再自行重建标量火焰爆炸。

## 失败关闭

任何非法组装都返回空 Dictionary，不返回半个伤害包。编译失败维持 {ok:false,error:…} 约定。

检查包含：未知阶段、类型、作用域或事件标签；重复标签；负数、NaN、无穷及非数值点数；错误分布；无 hit 的事件；同时具有 attack 与 spell 的事件；非零独立爆炸附加效用；越界连锁索引；非法来源字段或 stat/type/scope 组合；冻结记录与 base 不一致；编译后的跨技能复用。负 more 仍是已有合法减伤操作，与「负附加点数」不同。

## 可复算样例

B=100，攻击附加物理10／火焰20，法术附加冰霜30／闪电40，未加 increased／more：

| 事件 | 原始结果 |
| --- | --- |
| 普攻 | 物理110、火焰20 |
| 龙卷母箭 | 物理70、火焰60 |
| 龙卷子箭 | 物理49、火焰42 |
| 飞弹 | 冰霜48、闪电224 |
| 冰霜脉冲 | 冰霜110.5、闪电34 |
| 新星 | 冰霜81、闪电378 |
| 陨星 | 火焰430、冰霜129、闪电172 |
| 连锁首跳 | 冰霜66、闪电308 |
| 任一载体的独立爆炸 | 仅火焰90 |

这些是本项目原创参数。tests/damage_base_test.gd 覆盖公式、独立两系数、全部技能、增伤作用域、辅助对完整分量的作用、零附加兼容、嵌套冻结与来源过滤、运行时子箭／爆炸和畸形输入。既有 tests/combat_pipeline_test.gd 继续验证旧行为。

## 研究来源与边界

设计语义参考官方资料对不同作用域词缀及 Damage Effectiveness 的区分：

- [Path of Exile 官方 modifier catalog](https://www.pathofexile.com/item-data/mods)
- [Path of Exile 官方 3.17.0 更新说明](https://www.pathofexile.com/forum/view-thread/3229187)

引用用于术语和阶段边界研究，不代表本项目实现这些游戏的完整结算规则。所有本页技能系数、效用、词缀值与装备内容均为本项目原创；没有将外部源码、完整词缀库或数值表导入运行时。
