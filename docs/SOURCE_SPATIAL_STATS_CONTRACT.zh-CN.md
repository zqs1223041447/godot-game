# v0.32 源天赋范围面积与投射速度

基线v31为75f48cc91d2f82c3b5c9a8f9e0ae756b11c82f37。两类现有源文本执行覆盖同批接入，不增加装备空词缀。原范围伤害area_increased与现16辅助含义保持。root独占必要技能/属性摘要与DamagePreview文字，后端拥有解析、编译、运行接点、schema20迁移和定向验收。

## 统计与范围

- area_size_increased：无条件全局范围面积increased，按0.10=10%累加
- spell_area_size_increased / melee_area_size_increased：完整“Spell Skills have … increased Area of Effect”或“Melee Skills have … increased Area of Effect”格式，依真实技能标签
- projectile_speed_increased：全局投射速度increased为正、reduced为负，先相加再乘辅助more倍率

光环/诅咒/近期/武器条件等不在本批；整个节点所有效果支持才可分配。节点源原值不更改，不增点数或改邻接。全局范围影响新星、陨星、裂刃斩和实际独立爆炸；独立爆炸没有spell/melee标签，只接全局面积。不是更改珠宝半径、拾取半径、怪物预警或角色体型。

半径=基础半径×sqrt((1+适用面积增幅总和)×辅助面积乘积)。投射速度=原速度×(1+速度increased/reduced总和)×现辅助速度乘积。速度覆盖普通攻击640、龙卷母/子/返回和飞弹/冰霜/蚀影；射程/寿命/弹数/伤害不因此改变，继续哪一条终止边界先到先执行。

## 编译合同

原配方recipe.radius/base_radius/area_multiplier给最终值；有新加成时补source_area_multiplier。投射recipe.speed给最终值，有新加成时补base_speed/speed_multiplier/source_speed_multiplier；龙卷字段位于recipe.parent/child。snapshot.tornado_recipe复制编译后母子配方，生成子箭/返回不重乘；snapshot.explosion_recipe.radius给最终范围，必要时补base_radius/area_multiplier。

基础快照只在存在非零空间增幅时加入原始spatial_modifiers，以保持旧零增幅快照字节。新Compiler.compile_basic(snapshot)收口原普通攻击包与640速度，无主动辅助。已编译快照仍拒绝重入，实际投射物保存施放时完整副本；换装备/天赋只影响后续施放。

UI路径：ui/canonical_skill_panel.gd的summary与combat/damage_preview.gd的details。可显示最终半径/速度与独立爆炸半径，并明确面积不等于半径、速度不等于距离；不要增加长篇常驻解释。C属性仅必要时显示非零统计。

## 保存边界

当前版本升schema20，旧v19及更早使用冻结旧解析列表校验，新增空间格式只在20开放。SourceTree行/节点/构筑分析缓存须分版本，防v20支持结论误用于v19。HotkeyMigration固定输出19，再由独立19→20步骤处理；旧原字节先备份，失败或冲突不改内存/源文件。

保留全部UID、配置、已分配旧节点/预算和原v021目录/测试隔离。v19伪装注入新解锁节点必须拒绝，而合法v20该节点实际生效。无新道具或持久字段，仅版本词汇门槛。

## 验收

先从冻结v31导出literal v19与旧零增幅编译基线。新批次定向验证合法路径/退款/读写、旧字节备份与新节点注入拒绝、零增幅旧编译结果、面积平方根/辅助乘积、全投射物速度消费者、母子与活跃快照不重乘、距离寿命/墙事件顺序保持。两类一次交付，不运行600秒或历史全量。
