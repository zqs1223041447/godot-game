# v0.35 药剂构筑三项闭环

源字段flask_life_recovery_increased、flask_mana_recovery_increased、flask_charges_gained_increased均为源百分数/100的非负有限加值。本批接无条件生命/魔力恢复量、两者共同恢复量、获得充能；含持续时间、定时/命中回充、压制或持续伤害减伤的节点仍整项锁定。标准普通节点有10个新增完整候选，无新增完整标准精通。

每次仍消耗10/最大30充能，持续仍3秒。用瓶瞬间总回复=原35%×对应起手最大资源×(1+相应增幅)，随后固定rate与总量，换装/退款不改已经开始的回复；每次advance仍以当前资源上限clamp。同资源不能叠加；满资源、正在恢复、充能不足或坏输入不扣费。

每个合法奖励根怪增加1×(1+gain)充能，只作用当时装备的各唯一UID。内部以1,000,000微充能=1整点累积当前源整百分数，避免浮点临界漏整点；这不是新材料或存档钱包。满30时，在本次合法奖励统一丢弃余量/超额，不允许存满后再银行式取出。移动槽位/背包保UID与余量，丢弃移除所有权才清该UID余量；后代、重复死亡及演示怪沿原奖励门零充能，旧RNG不变。

Runtime.snapshot只有确实非零余量才出现charge_remainders_micro。全零增幅路径保持既有charges_by_uid/active_by_resource字段与计算字节；余量不持久化，重开、回城和切档沿原药剂生命周期reset。

Model.get_flask_profile(uid)返回ok/reason/resource/duration/cost/max_charges/base_recovery_fraction/recovery_multiplier/recovery_fraction/recovery_total/charges_per_root，root统一药剂悬停仅消费此投影。FlaskRuntime.use新增可选stats第4参数，charge_rewarded_kill新增可选stats第2参数；status原接口不变，main传已有缓存_stats。后台不更改UI布局。

schema23先严格旧22校验与原字节备份，再仅变版本；旧22注入新药剂节点拒绝，19/20/21/22中间输出及分析缓存按原门槛锁定。不赠物赠点，保UID/组/键位/点数/revision及240格与测试隔离。

定向验收包含冻结v34零增幅23步轨迹、三属性纯规则/微充能临界、实际分配与使用/换槽/死亡奖励门、原字节迁移、root同源悬停和图鉴；无600秒/历史全量。
