# v0.64 schema39 → schema40 迁移 QA

最终聚焦检查：**198 checks / 0 failures，exit 0，0 SCRIPT ERROR，0 ERROR**。耗时11.415秒，全部记录的生产代码、源数据和测试输入运行前后哈希一致。没有重跑历史全量集合。

- [最终检查结果](20261006T024235835781Z-migration-checks.json)
- [最终原始日志](20261006T024235835781Z-migration.log.txt)
- [命令、隔离路径、耗时和全部输入哈希](20261006T024235835781Z-migration-attempt.json)
- 测试：[`source_iron_reflexes_migration_test.gd`](../../../tests/source_iron_reflexes_migration_test.gd)

## 迁移边界

schema39完整验证冻结为源政策38、装备词汇39；`decode_v39`和`reason_v39`在调用可选额外validator之前执行原生完整验证。schema40只开放新源政策；装备词汇仍39，显式的装备词汇40无效。前一段38→39明确结束于`reason_v39`，再接39→40。

合法39→40深拷贝后只改变version。逐字段验证items、locations、next_item_serial、revision、skill_groups、bindings、talents、progress、crafting、migration_ledger和journey完全相等；原输入和全局随机数状态不变，现有Build的全部聚合stats不变。没有赠点、赠物、重掷、替换UID、递增修订或改动进度。

真实文件加载先保留原始39字节备份，再原子提交一次并发出一次通知。再次打开40不迁移、不重写，备份保持原样。直接38→39→40链只备份原始38文件并提交一次；新的默认完整链最终得到合法40。

## 独立旧版本夹具

[fixture](fixtures/v39-frozen-v063.json)由未改动的v0.63.0生产Store原生序列化生成；不是使用schema40序列化后改版本号，也不是用户存档。来源commit为`76e2abccf533cd31c20daea92c0e05b02c0980af`。

- 20,620字节，50个物品；SHA-256：`6c64f8498acbbe9fac490d6e012923a2588b0129b55e24fec3433ec796c9c056`
- 含全部十个已有装备池的实例、同一件装备上的ironhide/mistweave前缀与三种抗性后缀、73个碎片、已分配的Resolute Technique路线
- 见证值：level37/xp9、revision17、crafting revision3、Sunwell最佳tier2
- [来源manifest](fixtures/manifest.json)、[原生capture脚本](capture-frozen39.gd)、[capture日志](20261006T023946429171Z-capture39.log.txt)、[capture输入哈希](20261006T023946429171Z-capture39-attempt.json)
- [十个关键旧文件与发布commit的字节一致证明](frozen-release-evidence.json)
- [旧源词汇oracle](fixtures/v39-vocabulary-oracle.json)：源policy38、770个可执行普通节点
- [所有items模块与v63逐字节相同的证据](equipment-identity-evidence.json)，包含装备池顺序与装备词汇定义

## 拒绝与原子性

使用class4、level8、12点的真实连通10661路线，先验证其在40完全合法，再将version改39。严格reason/decode/migrate全部拒绝，而且宽松回调从未获机会绕过原生验证。无备份、无写入、无内存变化、无信号；之后直接save也不能覆盖遭保护的非法文件。

另检查20类完整信封破坏：分数/布尔/NaN修订、额外字段、缺少或非法journey、UID不符、未知/重复/错误类型节点、额外天赋stat、超额点数、错误源版本、NaN专精、分数roll、未知词缀、缺少位置、复用serial、非法绑定、非法迁移ledger。错误根类型、损坏JSON和未来41也拒绝。

备份失败、已有冲突备份、备份后外部写入、实际临时文件目录碰撞都不能发布内存或成功事件。原文件与冲突备份保持原样；写失败保留精确旧字节备份，去掉故障后允许同备份重试并只成功提交一次。已有合法40加载状态及其磁盘receipt在后续39迁移写失败时保持不变。

current40的10661分配保存后可独立重开，12点分配与物品保持相同，实际consumer启用且闪避值为0。战斗换算与UI详细验收由本批对应聚焦检查负责。

## 首轮结果与修正

[首次运行日志](20261006T024210249055Z-migration.log.txt)保留：引擎exit0、184 checks / 0断言失败，但有2个SCRIPT ERROR，因此runner明确判失败。原因是测试直接读取未启用时省略的`iron_reflexes`字段，导致literal和chain函数提前退出。仅将两处默认值检查改为`get(..., 0.0)`；未修改生产逻辑。随后重跑同一聚焦集，最终198项全部完成通过。

## 执行

统一首次import由主任务执行；本runner从不import。运行`python3 docs/qa/v064-migration/run-focused.py`，默认使用官方`/usr/local/bin/godot`，每次创建独立`/tmp/godot-m1-v064-migration-*` XDG data/config/cache，绝不触碰默认用户存档。提供`V064_FROZEN39_PROJECT`可指定已导入的v63原树；已有fixture会直接复用，只有显式`--refresh-capture`才重新捕获。
