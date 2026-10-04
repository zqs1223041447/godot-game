# v0.33 护盾充能源天赋闭环

基于冻结v32，保持原护盾基底、技能/装备/地图与正常奖励。范围仅完整无条件的“increased Energy Shield Recharge Rate”与“faster start of Energy Shield Recharge”；带压制、最大抗性、格挡、转生命或不中断等额外语义的节点仍整体锁定。

## 属性与共享计算

- shield_regen：原平面充能基底，含现有装备和共享机制加值，原义不改
- shield_recharge_rate_increased：源百分数除100后相加
- shield_recharge_start_faster：源百分数除100后相加
- get_stats().shield_recharge_rate：基底×(1+rate_increased)，实际每秒回复
- get_stats().shield_recharge_delay：4秒/(1+start_faster)，下一次有效损伤命中使用的等待

DefenseRules.recharge_profile(stats,actor)用于玩家与怪物，返回ok/reason/base_rate/rate/delay。未知actor、非有限、布尔、负值和结果溢出拒绝。正常怪无新属性时保持旧字段与字节；有共享新机制时保存最终派生rate/delay，运行时不逐帧重新解释源文本。

## 时序

有效结算伤害大于零才重新等待，盾吸收也属于有效伤害；玩家闪避/无敌/零伤害、怪物未命中不重置。原倒计时跨阈值只按本帧剩余delta回盾。命中时锁定当次等待，换装/退款更新后续每秒速率，等待配置从下一次有效命中使用，避免悄改已经进行的计时。护盾充满不超过当前上限。ward仍按原规则即时恢复并清等待，独立于持续充能速率。

此处沿本游戏平面基底与4秒等待，不声称采用PoE完整护盾基底。root独占C页实际每秒和等待配置显示；后台不改UI。

## 存档

schema21执行覆盖门槛；先用冻结v20完整校验和原字节备份，再仅改版本。v19空间属性门槛与更早阶段不变；旧版本注入新充能节点拒绝，缓存按19/20/21分区，不赠物或点数。当前UID、240格、技能组、键位、天赋预算、revision及测试档隔离保留。

## 针对性验收

旧20 literal/default与空间节点已分配档、原字节备份/失败回滚/注入拒绝；旧怪物全模板两波次字节基线；两属性纯公式与合法源路径；玩家和怪物实际命中/闪避/零伤害→等待→回盾、分段delta与换装速率；root两派生字段显示及同源图鉴。无600秒或历史全量。
