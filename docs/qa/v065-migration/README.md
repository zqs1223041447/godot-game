# v0.65 schema40 → schema41 迁移 QA

聚焦检查：**201 checks / 0 failures，exit 0，0 SCRIPT ERROR，0 ERROR**，耗时12.998秒。记录的全部生产代码、源数据及新夹具前后哈希一致。未运行历史全量集合，未重新import。

- [检查结果](20261006T031027879959Z-migration-checks.json)
- [完整日志](20261006T031027879959Z-migration.log.txt)
- [命令、独立XDG目录、耗时和输入哈希](20261006T031027879959Z-migration-attempt.json)
- [聚焦测试](../../../tests/source_zealots_oath_migration_test.gd)

## 生产边界

schema40完整信封冻结为source policy40、装备词汇39。`decode_v40`与`reason_v40`必须先执行完整原生验证，可选callback只能追加限制，无法放行63425或其他非法输入。旧Iron Reflexes迁移39→40的链尾明确固定到`reason_v40`，再执行新的40→41迁移。

合法40→41深拷贝后仅改变version。items、locations、next_item_serial、revision、skill_groups、bindings、talents、progress、crafting、migration_ledger与journey逐字段相等，原输入和全局随机状态不变。未分配63425时，`zealots_oath`和`shield_regeneration_rate`字段仍不存在；旧IR构筑的完整聚合stats等于v64原生oracle。没有赠点、赠物、重掷、替换UID、递增修订或改变进度。

装备词汇仍严格为39，显式装备词汇40与41均无效。[全部20个items模块](unchanged-equipment-evidence.json)与冻结v64逐字节相同，含装备池和roll定义。

## 独立冻结40夹具

[fixture](fixtures/v40-frozen-v064.json)由已冻结v64项目的原生生产Store序列化；不是将当前41存档改版本号，也不是用户存档。捕获前对照发布commit `23983fe`验证全部170个生产脚本与project.godot，共171个文件完全相同，见[冻结发布证明](frozen-release-evidence.json)。只导出小夹具与stats oracle，未复制项目大树。

- 20,088字节、50个物品；SHA-256：`8baa30904f56487d05606a956d1f580caa2ec874d287d2c8835af920206dcbb5`
- 覆盖全部十个既有装备池实例；穿戴一件带ironhide/mistweave及三抗后缀的防具
- class4真实12点Iron Reflexes路线，旧引擎原生armour585、evasion0；73个碎片
- level37/xp9、29剩余普通点、revision17、crafting revision3、Sunwell最佳tier2
- [manifest](fixtures/manifest.json)、[完整旧stats oracle](fixtures/v40-stats-oracle.json)、[捕获脚本](capture-frozen40.gd)、[捕获日志](20261006T031002268173Z-capture40.log.txt)、[捕获输入哈希](20261006T031002268173Z-capture40-attempt.json)

## 拒绝、备份与原子性

先证明Marauder23点的63425完整连通路线在41合法，再将version改40。冻结reason/decode/migrate全部拒绝，宽松callback调用次数为0；非法文件无备份、无写入、无内存发布或事件，后续save亦不能覆盖受保护文件。

另覆盖20类坏信封：分数/布尔/NaN修订、额外字段、缺少/非法journey、UID不符、未知/重复/错误类型节点、额外天赋stat、超额点数、错误源版本、NaN专精、分数roll、未知词缀、缺少位置、复用serial、非法绑定及迁移ledger。错误根类型、损坏JSON和未来42均拒绝。

真实40文件加载先备份原始字节，再原子提交一次并通知一次。重开41不重写、备份不变。备份失败、已有冲突备份、备份后外部写入、实际临时文件目录碰撞均不会发布新状态；写失败保留原字节备份，移除故障后同备份可安全重试并只成功提交一次。已有合法41内存与磁盘receipt在下一次旧40迁移失败时完整保留。

实际39→40→41加载只提交一次、只备份原始39；前一段迁移仍明确停在40。全默认链最终得到合法41，无碎片或keystone赠送。

当前41实用路线保存重开后仍为23点，包含10点/秒flat与1.8%生命再生来源、4%ES容量增幅及63425。最终max_shield64.8，生命再生0，ES再生11.1664/秒，即10＋0.018×64.8。实际战斗节拍与UI由其他本批聚焦测试负责。

## 执行

`python3 docs/qa/v065-migration/run-focused.py`使用已核实的官方`/usr/local/bin/godot`（4.6.3），每次创建独立`/tmp/godot-m1-v065-migration-*` XDG data/config/cache。默认复用捕获夹具，`--refresh-capture`才重捕获；`--capture-only`仅捕获。runner不import，也不访问默认用户存档。
