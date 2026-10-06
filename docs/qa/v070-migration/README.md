# v0.70：精准技艺原始节点与 schema44→45 聚焦验证

统一 import 完成后，源树 **8552 checks / 0 failures**（3.413 秒），迁移 **384 checks / 0 failures**（15.921 秒）。两次均 exit0、零 SCRIPT ERROR / ERROR，记录的所有测试输入前后哈希一致。真实44夹具只捕获一次（3.301 秒），同样零错误、输入未变。本 runner 不 import、不启动编辑器、不跑历史全量、不导出 Windows/PCK/ZIP/Release。

- [源树日志](20261006T061019864029Z-source.log.txt)、[逐点分配结果](20261006T061019864029Z-source-checks.json)、[命令与输入哈希](20261006T061019864029Z-source-attempt.json)
- [迁移日志](20261006T061028415083Z-migration.log.txt)、[迁移结果](20261006T061028415083Z-migration-checks.json)、[命令与输入哈希](20261006T061028415083Z-migration-attempt.json)
- [源树测试](../../../tests/precise_technique_source_test.gd)、[迁移测试](../../../tests/precise_technique_migration_test.gd)

## 原始63620完整开放，其他源效果保持原样

只接受原始完整多行条目：

```text
40% more Attack Damage if Accuracy Rating is higher than Maximum Life
Never deal Critical Strikes
```

解析结果只有 `precise_technique = 1.0`。不拆开条件增伤与无条件禁暴击，不接受单独一行、其他数值、大小写/空白/标点/换行变体、非严格比较或其他伤害类型。只在 schema45、原始63620且完整实现时向 stats 添加该字段；未分配时不添加零值字段。中文映射未变，只补充指向真正 SourceTree、CombatData、PreciseTechniqueRules 和 CriticalStrikeRules 消费者的证据组。

独立真实44 oracle包含4224个标准节点/专精选择的原生字节摘要。当前旧44策略的4224项全部逐字节相同；当前45只有63620发生变化，其余项全部逐字节相同。44物理转火、41/42/43旧策略以及全部旧门槛保持冻结，其他未完整实现节点仍不能分配。

## 原始图路线与真实模型事务

两条路线均使用 `Game.allocate_passive` 沿原始边逐点分配，不赠点、不绕过连通规则：

- Ranger：level4，共8点，`50459 → 39821 → 52904 → 444 → 61306 → 60942 → 64709 → 3469 → 63620`
- Duelist：level5，共9点，`50986 → 39725 → 63649 → 49806 → 6580 → 19711 → 20010 → 23471 → 3469 → 63620`

分配后点数恰好为零，只新增一个不可拆分标记。断连分配与重复分配均在写盘和花点前被拒绝；真实保存、独立重开保留节点，退掉63620后恢复分配前完整 stats 与 combat snapshot 原生字节以及点数。物品和位置不变。

## 真正的旧44序列化夹具

从现存 `/workspace/scratch/a51485f153de/v069-physical-fire-conversion` checkout的真实生产代码原生序列化，未创建冻结 archive，也未将当前45存档改版本冒充旧档。捕获前，387个受跟踪 scripts/data/project 输入与commit `d25717c4485bf36688df36460f2c85ebb11b7623` 逐字节一致，见[来源证明](native-source-evidence.json)。

- [IR原生44](fixtures/v44-ir-native-v069.json)：21,084字节，54物品
- [ZO原生44](fixtures/v44-zo-native-v069.json)：21,217字节，54物品
- [65020激活原生44](fixtures/v44-conversion-native-v069.json)：21,066字节，54物品
- [原生 stats/snapshot 与字节摘要、4224项源效果摘要、奖励与宝石门槛 oracle](fixtures/v44-oracle.json)
- [完整SHA-256 manifest](fixtures/manifest.json)、[捕获脚本](capture-native44.gd)、[捕获日志](20261006T060231269466Z-capture44.log.txt)、[命令与全部输入哈希](20261006T060231269466Z-capture44-attempt.json)

三个夹具均有十个旧装备词池实例、防御词汇39装备、73碎片、level37/xp9、revision17、crafting revision3、Sunwell最佳tier2；各有两颗伏击和两颗牵引辅助，分别放在恢复区和真实技能链接。三组原生 stats 与 combat snapshot 均与旧44代码输出的字节SHA-256完全一致；65020仍保留原有40%转火，IR与ZO原效果不变，未得到精准技艺或其他新礼物。

## 严格迁移、原字节备份与失败回滚

`decode_v44` / `reason_v44` 强制完整原生44信封合法性，可选callback只能追加限制。当前45合法的63620路线注入旧44或旧43时，在任何callback、备份、写盘、通知之前被拒绝。另覆盖20种坏信封、错误根类型、损坏JSON、未来46、额外runtime字段和callback附加拒绝；失败不会污染已有内存或改写原始文件，后续save也不能覆盖被拒文件。

旧 PhysicalFireConversion43→44明确固定结束于冻结44；新 PreciseTechnique44→45只深拷贝并改变version。items、locations、UID、serial、revision、bindings、skill_groups、talents、points、progress、crafting、ledger、journey逐字段不变，输入与全局随机数序列不变。

合法44先保存原字节 `.v44-backup.json`，再一次原子提交、一次通知。重开45不重写。备份失败、冲突备份、备份期间外部改写、真实 `.tmp`目录碰撞均不能发布候选；已产生备份保持原字节，移除临时碰撞后可安全重试。失败迁移保留此前有效45状态及磁盘凭据。真实43→44→45链只提交一次、只备份原始43字节。真实Game加载检查最新提示包含“精准技艺”“原字节备份”“不额外赠物或赠点”。

## 装备、奖励和原始数据合同

[不变证据](unchanged-contract-evidence.json)确认原始PoE JSON、运行图JSON、中文映射、EquipmentCatalog、GemCatalog、GemTradeRules、NormalJourneyState与d25717c逐字节一致。装备词汇仍39；普通奖励仍26项、52个旧奖励ordinal逐项相同，所有已有宝石最低存档版本不变，没有新宝石或奖励支路。

## 复验

- `python3 docs/qa/v070-migration/run-focused.py --source-only`
- `python3 docs/qa/v070-migration/run-focused.py`

每次以独立 `/tmp/godot-m1-v070-migration-*` 的data/config/cache运行 Godot4.6.3，不碰默认用户档，55秒上限。非零退出、SCRIPT ERROR、ERROR或输入变化均判失败。原始44夹具已存在，`--capture-only`拒绝重复捕获，应复用已保存原字节。本目录负责源树与存档验证，战斗规则及实际场景结算由对应聚焦测试覆盖，不宣称历史全量通过。
