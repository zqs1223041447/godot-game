# v0.31 四普通词缀同批合同

在原强健/迅行同源表增加四项，普通槽仍最多2。两图与现有特殊槽上限不变：6普通的空/一/二项共有22组合，旧庭3个特殊选择（含空）、断垣4个，共154合法配置，最终按实际目录枚举核对。

| ID | 名称 | 原型预算 | 实际消费者 |
|---|---|---|---|
| enemy_damage_115 | 凶猛 | 标准damage ×1.15 | 原接触分量与锁点攻击基底 |
| enemy_attack_speed_110 | 疾攻 | 标准attack_speed ×1.10 | 接触间隔、预警后恢复；预警时长保持 |
| enemy_shield_from_health_20 | 护幕 | 标准max_health ×0.20额外盾 | 增加max_shield/current shield相同量，原缺失盾量保持 |
| enemy_armour_80 | 铁肤 | 标准armour +80 | 原命中大小相关物理护甲结算 |

护幕基准是本次工厂生成、未施加任何普通词缀的max_health；不因强健选在前后变成乘积，不从父怪最终资源继承到子代。所有词缀仅入场应用一次；根怪/首领/子代均用原原子Admission。地图特殊元素庇护在普通词缀之后用原共享防御模块。物品/存档、RNG/身份/稀有度/目标/奖励保持，没有收益倍率。

`EncounterCatalog.get_definition()` 保留 id/name/field/description，新增 `operation`（multiply/add_base_health_fraction/add_flat）、`value`；`risk.label` 为可直接显示的短风险文字。倍率项保留multiplier/relative_increase兼容字段，加值项不能把relative_increase当有效百分比。

profile.multipliers 含 max_health/speed/damage/attack_speed；profile.additions 含 shield_from_base_health/armour。最终actor.damage、attack_speed、max_shield/shield、armour为实际值，UI可直接解释，不写另一套预算。source before记录固定基准与应用结果来源。定义与政策修订提升，旧运行选择不持久化，schema19不变。

root独占EncounterControls/地图菜单/F7确认等UI。后端只改真实目录、编译器、共享消费者接点、图鉴和定向测试。此同一词缀目录会在F7现有试验入口出现，正常未选挑战仍不改变。

统一定向验收：全部154合法选择及非法/互斥边界、输入顺序无关、护幕固定基准、后代一次、凶猛接触/重击伤害、疾攻预警不缩/恢复缩、盾后生命、铁肤仅物理且依命中大小；原子失败/容量/RNG身份保持。四项一起交付，不为每项运行长测试、旧全量或独立发布。初版预算可调整，不宣称已完成终局平衡。
