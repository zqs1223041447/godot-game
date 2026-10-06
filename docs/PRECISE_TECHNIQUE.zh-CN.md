# 精准技艺：严格命中条件与全局禁暴击

v0.70只开放原始源树节点63620的完整多行词条：

> 40% more Attack Damage if Accuracy Rating is higher than Maximum Life
> Never deal Critical Strikes

存档与源政策升级为45，装备词汇保持39。不是新天赋、新宝石或新装备；原始英文、节点身份、拓扑、中文映射文件、经济和素材保持。只支持完整原句，不拆出增伤半句或禁暴击半句单独开放。

## 条件与代价

A为装备、属性和天赋结算后的最终命中值，L为最终最大生命。仅A严格大于L时，符合条件的攻击伤害得到一条40% MORE，即在其他增伤完成后额外乘1.40。A等于L或低于L时不授予这一条MORE；比较不先取整，也不用近似相等判断。

这条伤害增益必须同时匹配hit与attack，不限技能或伤害类型。现有近战、投射普通攻击、裂刃、龙卷母箭、子箭和返回攻击按各自包的标签取得增益。原生火焰和物理转换火焰均可受益，但一条modifier记录只应用一次，不因physical/fire双来源重复乘1.40。法术、独立爆炸及燃烧tick不取得攻击MORE；既有燃烧从增强后的火焰命中取起始输入后，tick不会再套一次。

只要分配精准技艺，无论伤害条件是否成立，所有攻击、法术与独立爆炸均不能暴击。未满足条件时也仍承担禁暴击代价。原本合法的潜在暴击倍率可以保留供检查，最终暴击率为0；不能暴击的冻结路径不消耗私有暴击随机抽样。精准技艺不授予不能被闪避；只有另行分配的坚决技艺可提供其既有不能被闪避规则，两者禁暴击取并集。

## 生命、成长与早期取舍

判定读取最大生命，不读取当前剩余生命。受伤、喝药、再生或其他当前生命回复不会让同一构筑的精准技艺条件开关变化。增加最大生命的换装可能使A≤L；补充命中则可能重新满足严格条件。

游侠原起点的合法路线为50459→39821→52904→444→61306→60942→64709→3469→63620。起点免费，其余8点可在4级预算中支付；裸装前置属性A284、L141，早期较容易满足条件。这是已知强势入口，不能以“需要堆命中”淡化早期收益，也不据此声称长期平衡或最佳路线。生命继续成长会抬高门槛，暴击构筑则须权衡永久禁暴击的机会成本。

## 冻结合同与退款

原始stats仅以precise_technique=1表示已分配。施放快照的precise_technique只包含accuracy与max_health两个最终数值；编译后的precise_technique_profile公开：

- enabled、accuracy、max_health
- condition_met、attack_more
- cannot_deal_critical_strikes、attack_applies

attack_more表示严格条件对应的0或0.4；attack_applies另外判断当前命中是否属于攻击。例如已满足A>L的法术仍公开0.4的条件幅度，但attack_applies为false，法术没有增伤；禁暴击始终为true。

分配、退款、改变装备只改变之后的新施放。已发出的母箭、子箭、返回攻击与独立爆炸保持施放时的条件、modifier和暴击策略；退款不会重新掷已冻结的旧命中。未分配路径不增加空精准技艺字段或空profile，保持既有伤害与暴击行为。

## 三个实际场景快照

[F8精准技艺章节](reference/index.html#rules-precise_technique)直接读取本批实际Main已通过验证的三个构筑及其同场景stats/compiled预期：[已点且高于阈值](qa/v070-gameplay/fixtures/selected-above.json)、[已点且低于阈值](qa/v070-gameplay/fixtures/selected-below.json)、[已退款](qa/v070-gameplay/fixtures/refunded.json)。F8不重新设计装备、不猜稀有度或词缀、不另分配一条路线。

导出先用当前Canonical Rules.decode恢复JSON中的规范整数类型，再由Rules和SourceTree完整验证，只在内存重建Model。get_stats、get_basic_cast及已装配的裂刃/龙卷get_group_cast在同样的full-precision JSON边界上必须与同一次实际Main导出的预期完全一致，然后才展示真实DamageResolver数值和Preview文本。读取前后fixture SHA256保持，保存次数为0。

三个状态用于说明条件与代价：前两者使用实际生命装备改变阈值；已点高于阈值与退款状态使用同一短刃和相同已装备物品，可直接比较40%攻击MORE与暴击取舍。表格是零防御、成功且不暴击的一次命中，不是实战DPS；退款后的暴击率另列，不能把“非暴击值”当成包含暴击的平均值。物理转换的同源实际Main证据另见本批gameplay生命周期验证，不在F8另造转换装备示例。

## 迁移与验收范围

schema44→45先用旧44词汇完整验证并备份旧原字节，再只升级版本。不赠点、不赠物、不重掷，不变更已有UID、物品次序、奖励、技能或经济。显式历史源政策调用维持原语义。

旧F8默认构筑、技能示例和历史数值保持。旧坚决技艺章节明确标注v61/source38历史范围，并链接当前精准技艺，避免把过去未开放的状态误报为现状。当前源覆盖只允许63620完整执行变化及直接由它带来的可达统计变化；原始数据、旧图片、CSS和JS保持原字节。

[本批F8验证](qa/v070-reference/README.md)记录一次数值导出、HTML构建及窄范围保全；[实际Main证据](qa/v070-gameplay/README.md)与[纯规则证据](qa/v070-rules/README.md)分别负责实际消费者与规则边界。本批为源码阶段，未构建Windows、PCK或ZIP，未创建tag或Release，不把未运行的平台测试称为通过。
