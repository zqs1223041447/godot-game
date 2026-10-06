# v0.69：源火焰专精与 schema43→44 聚焦验证

本批 **源树8640 checks / 0 failures**（5.321秒）与 **迁移343 checks / 0 failures**（14.178秒）均 exit0、零 SCRIPT ERROR / ERROR，记录的所有测试输入前后哈希一致。原生43夹具仅捕获一次（2.726秒，同样零错误、输入未变）。当前测试在统一import完成后运行；本runner不import、不启动编辑器，不执行历史全量、导出、PCK、ZIP或Release。

- [源树日志](20261006T053617523342Z-source.log.txt)、[结果与四条真实路线](20261006T053617523342Z-source-checks.json)、[命令与全部输入前后哈希](20261006T053617523342Z-source-attempt.json)
- [迁移日志](20261006T053628745948Z-migration.log.txt)、[结果](20261006T053628745948Z-migration-checks.json)、[命令与全部输入前后哈希](20261006T053628745948Z-migration-attempt.json)
- [源树测试](../../../tests/physical_fire_conversion_source_test.gd)、[迁移测试](../../../tests/physical_fire_conversion_migration_test.gd)

## 只开放原始65020的40%物理转火

解析器只接受完整原行 `40% of Physical Damage Converted to Fire Damage`，仅授予 `physical_to_fire_conversion = 0.4`。当前源消费者最低schema44；41、42、43仍精确执行源策略41。条件、空白/大小写/标点变体、其他数值或伤害类型、gain-as-extra以及火之化身均保持封闭。

独立原生43 oracle记录4224个标准树节点/专精选择的原生字节哈希。当前以旧43策略执行，4224项全部逐字节一致；当前44仅改变八个入口的同一65020选择，其余节点及所有选择逐字节不变。

八个Fire Mastery入口共享原有同效果唯一规则：11505、19749、34927、37911、38320、40271、48267、63268。当前可通过已完整实现显著点合法进入的只有：

- 11505，经29049 Holy Fire
- 63268，经24324
- 48267，经2550
- 34927，经11924

38320、37911、19749、40271仍因所属显著点组未完整实现而不可选。实际模型API逐点分配了四条原始图路线，随后各自选择65020、保存、原生重开、退点；一次选择消费一点且只有40%转换，退点恢复选择前完整stats和combat snapshot字节。另将两个合法显著点组同时连通，真实分配第二入口的65020在写盘前被拒绝；点数、磁盘字节和内存不变。退掉首入口后可从另一个入口重新选择，仍为40%。

## 独立真实43夹具，不重标当前存档

夹具从 `/workspace/scratch/a51485f153de/v068-inventory-first-open` 的真实生产代码原生序列化。捕获前对照commit `094c1d758f2b92ca27d42bb5207f1496b0c89768`，383项受跟踪scripts/data/project输入逐字节相同，见[来源证明](native-source-evidence.json)。该checkout不是冻结archive；没有用当前44输出改version来制造旧档。

- [原生43 IR](fixtures/v43-ir-native-v068.json)：21,084字节，54物品，SHA-256 `9f55ac4de5fba63c3edc11df156de8b850cc627049416ebe559379e160ab7b9f`
- [原生43 ZO](fixtures/v43-zo-native-v068.json)：21,217字节，54物品，SHA-256 `3535a225e2cd886faa76f01de42c149395c0039e45573800f6045c2289a78be2`
- [完整stats、combat snapshot与原生字节哈希、4224项源效果哈希、奖励及gem最低schema oracle](fixtures/v43-oracle.json)
- [manifest](fixtures/manifest.json)、[捕获脚本](capture-native43.gd)、[原生日志](20261006T053335563529Z-capture43.log.txt)、[捕获命令与输入哈希](20261006T053335563529Z-capture43-attempt.json)

两个夹具均含十个旧装备池实例、词汇39防御装备、73碎片、真实IR或ZO分配、level37/xp9、revision17、crafting revision3、Sunwell最佳tier2，并各有两颗伏击与两颗牵引辅助，分别处于recovery及真实技能链接。迁移前后完整stats和combat snapshot与旧生产代码捕获的原生字节SHA-256严格一致，没有新增零值conversion字段。

## 严格迁移与回滚

`decode_v43` / `reason_v43`强制完整原生43合法性，可选callback只能追加限制。旧Inward Pull42→43迁移固定结束于冻结43，新PhysicalFireConversion43→44迁移深拷贝后只更改version。items、locations、UID、serial、revision、bindings、skill_groups、talents、points、progress、crafting、ledger、journey逐字段不变，输入与全局随机序列不变，无赠物、赠点或装备重roll。

合法43文件先生成原字节 `.v43-backup.json`，再一次原子写入与一次通知；重开44不重写。真正44合法的65020分配注入43、甚至旧42链路时仍被严格拒绝。另覆盖20种坏信封、非法根类型、损坏JSON、未来45、额外runtime字段与callback拒绝。拒绝时无备份/写盘/通知，原字节和已有内存保持，后续save不能覆盖被拒文件。

备份失败、冲突备份、备份期间外部改写、真实 `.tmp`目录碰撞均不能发布候选；已产生的原字节备份保持。移除临时文件碰撞后可安全重试且只提交一次。旧43迁移写入失败不会替换先前打开的有效44状态及磁盘凭据。实际42→43→44只提交一次，只备份原始42。当前44选择可原生保存重开，再以真实API退点。

最新迁移消息同时实测包含“40%物理转火”“原字节备份”“不额外赠物或赠点”。

## 原始数据、装备与奖励合同

[逐字节不变证明](unchanged-contract-evidence.json)覆盖原始PoE JSON、运行图JSON、中文映射、EquipmentCatalog、GemCatalog、GemTradeRules、NormalJourneyState。装备词汇仍39，普通奖励数组仍26项、旧52个ordinal逐一不变，全部已有gem最低schema不变，没有新gem或经济支路。

## 复验

- `python3 docs/qa/v069-migration/run-focused.py --source-only`：源树及真实分配事务8640项
- `python3 docs/qa/v069-migration/run-focused.py`：43→44严格迁移343项

runner使用Godot4.6.3与独立 `/tmp/godot-m1-v069-migration-*` 的data/config/cache，不碰默认用户档。每次55秒上限，非零退出、SCRIPT ERROR、ERROR或输入变化均判失败。夹具已存在；`--capture-only`会拒绝重复捕获，复验应复用上述原始43字节。生产修改另由战斗规则、结算与实际游戏场景测试负责，本目录不宣称历史全量通过。
