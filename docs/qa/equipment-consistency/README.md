# v103历史依赖隔离与装备检查边界

本批基线：`6db84d01f5ba7c8fffdb8bb3a7a941cc2609eb2c`。完成已确认的测试依赖修复；没有宣称找到或修复新的装备玩法缺陷。

## 两项失败来自此前依赖漂移

原始失败保留于[上批48项、2失败日志](../armour-targeted-reforge/historical-integrity-blocked.log)。原v103冻结基线为`b7d98c5b94c2c39f6f258835b28cfc32c4cd34d9`。

| 文件 | 原冻结SHA256 | a071697与6db84d0共同SHA256 |
|---|---|---|
| scripts/combat/damage_resolver.gd | `720dc69a7446334e8aec3ac15bdf7c1717fa7b96db5657e0c9622513121a4e23` | `51a3c503c2cae7b7ec1513976de1ed03f41c3677b892b8b55ab47bdb0b2ef6e5` |
| scripts/mechanics/defense_rules.gd | `a4d88c005dfd27fe6408e86ea9b96a34fe01c786c24c8965113dd20498224226` | `a2efd774c9a8e2e07d485f30ffb2427e8d74b75196c8677a864067d4ae715e9e` |

DamageResolver变化来自铁握持`47f31d0aeab2651f19a3590dbe6031ffb4a60830`；DefenseRules变化来自混沌防护`384b2b7f2b2daf8d7bcc8a8e4169f136575f4e25`及纯净的血肉`a5d21226161bf568bfb715ea8302c0bd213478a0`。护甲定向重铸没有改动这两文件。精确三组ref/哈希见[dependency-origin.json](dependency-origin.json)。

## 最小测试隔离

旧规则文件原本仍通过当前EquipmentCatalog间接预加载当前DefenseRules和DamageResolver，因而不再是冻结的依赖图。新测试加载器先验证原清单的全部13个依赖哈希及两个冻结规则哈希，再在隔离的`user://v103-isolated-oracle/`中生成六份私有脚本；转换仅删除全局class_name和重连这些脚本的preload。

- DamageResolver复用已经存在的`tests/fixtures/chaos_v92_frozen/damage_resolver.gd`，补回被移除的class_name后，精确匹配原b7哈希。
- DefenseRules从精确b7提交提取，原字节保存在`tests/fixtures/v103_dependency_isolation/defense_rules.txt`；哈希仍为原`a4d88c00…`。
- 其余11个共享依赖继续验证实际当前文件与原清单完全一致。
- 旧Targeted、Craft、Catalog、Expansion及两项历史依赖重连；实时生产模块继续原预加载路径。新增断言证明旧规则共用私有Catalog，且旧Catalog/Defense/Damage脚本对象均不同于实时对象。

**原冻结清单、冻结规则文件、预期哈希、旧报价/计划的`var_to_bytes`整份比较、种子及数量断言均保留。** 没有更新旧哈希迁就当前文件，没有删掉失败检查，也没有复制一套生产系统。

原完整`tests/resistance_targeted_reforge_test.gd`有限执行 **20270项、0失败，exit0，约9.8秒**：480次当前报价、448次当前计划；96次旧定向报价、768次旧定向计划；24次旧六工艺报价、192次计划，另含原历史词汇门槛和隔离身份检查。见[v103-isolated.json](v103-isolated.json)、[日志](v103-isolated.log)。这次是原完整针对性脚本的通过，不再只报告元数据部分。

```bash
XDG_DATA_HOME=/tmp/godot-m1-v103-isolation-fresh XDG_CACHE_HOME=/tmp/godot-m1-v103-isolation-fresh-cache V103_RESISTANCE_RULES_REPORT=/tmp/v103-isolation-fresh.json timeout 45 godot --headless --path . --script res://tests/resistance_targeted_reforge_test.gd
```

## 装备实际问题仍未定位

静态核对了当前39词缀家族的池/等级资格、掉落与商店入口、原制造规则、局部武器伤害与附加伤害消费者、普通攻击攻速、魔力/护盾恢复、额外技能行、装备缓存及奖励入包的保存调用链。现有正常掉落经Main的进度批处理，不能把测试直接调用内部奖励方法造成的忙状态保存提示当成正式掉落缺陷。

在这些检查中没有建立可复现的新不一致，因此**第二项“实际装备问题修复”尚未完成**。没有以新定向选项、纯UI改动或臆测性玩法修改代替它；也不声称全装备无缺陷。这是本次交付的明确剩余事项。

没有生产脚本、schema61、装备词汇51或内容规则变化；F8目录/HTML逐字节保留，并在[verification.json](verification.json)记录哈希。中文说明仅同步本次测试修复与检查边界，未制造需要内容库展示的新玩法。没有完整core、600秒检测、模型修改、Windows导出或封包。
