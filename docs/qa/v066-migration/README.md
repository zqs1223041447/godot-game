# v0.66 schema41 → schema42 宝石迁移 QA

聚焦检查：**298 checks / 0 failures，exit 0，0 SCRIPT ERROR，0 ERROR**，15.079秒。该次全部已记录生产脚本、源数据、project.godot、测试及夹具输入前后哈希相同。没有运行历史全量集合，没有重复import，没有重复捕获旧夹具。

- [通过日志](20261006T041529290117Z-migration.log.txt)
- [检查与关键观测](20261006T041529290117Z-migration-checks.json)
- [命令、独立XDG目录、耗时、全部输入哈希](20261006T041529290117Z-migration-attempt.json)
- [聚焦测试](../../../tests/ambush_gem_migration_test.gd)

## 生产边界

当前保存schema42只开放`support:ambush`。源天赋执行策略仍为41，装备词汇仍为39；没有新增源天赋消费者、点数、碎片、宝石、装备roll或进度。`decode_v41`与`reason_v41`先执行完整原生41验证，可选callback只能追加限制。旧Zealot's Oath迁移40→41明确结束于`reason_v41`，新迁移才打开42。

合法41→42深拷贝后只修改version。items、locations、next_item_serial、revision、skill_groups、bindings、talents、progress、crafting、migration_ledger与journey逐字段严格相等，输入与全局随机序列不变。纯迁移不赠伏击辅助。41文件注入新gem或新链接，即使在42完全合法，41 reason/decode/migrate仍在callback前全部拒绝。

## 独立原生41夹具

两份小夹具由冻结v65生产Store序列化；不是用户存档，也不是把当前42输出改成41。捕获前对照发布commit `b2bd4a1`验证172个生产脚本与project.godot，共173文件逐字节一致，见[冻结发布证明](frozen-release-evidence.json)。捕获只执行一次，2.4秒，零错误；原始日志与输入哈希保留。

- [IR夹具](fixtures/v41-ir-frozen-v065.json)：20,088字节，50物品；SHA-256 `8fb6643092d1aa4b2cca1a9a2458327700340bda6b6fa43d573cb82d90b1cd72`
- [ZO夹具](fixtures/v41-zo-frozen-v065.json)：20,221字节，50物品；SHA-256 `d4ec8d3d1c6d6a9adb0693485facbf0b8213d2b014bc5f71a91f80f02f4e5e2f`
- [原生stats、52个奖励ordinal、全部旧gem最低schema oracle](fixtures/v41-oracle.json)、[manifest](fixtures/manifest.json)、[捕获脚本](capture-frozen41.gd)、[捕获日志](20261006T034603265157Z-capture41.log.txt)

两者都含十个既有装备池实例、带ironhide/mistweave与三抗后缀的词汇39防具、73碎片、level37/xp9、revision17、crafting revision3和Sunwell最佳tier2。IR为class4真实12点路线，原生armour585/evasion0。ZO为class1真实23点路线并穿戴既有guardian robe，原生max_shield97.2、life_regen0、shield_regeneration_rate11.7496。两个旧构筑的迁移前后原生完整stats严格相等；新stats经过与旧JSON oracle相同的序列化/解析边界后也严格相等。

## 拒绝、备份、原子性与重开

覆盖20类坏信封，包括非法修订、额外/缺少字段、journey、UID、节点重复或未知、源版本、点数、roll/affix、位置、serial、绑定与ledger；另测错误根类型、损坏JSON及未来43。拒绝文件无备份、无写入、无内存或通知，随后save也无法覆盖受保护文件。

真实41载入先保留原始字节`.v41-backup.json`，再一次原子提交与一次通知。重开42无重写。备份失败、冲突备份、备份期间外部修改、真实临时目录碰撞均不发布候选内存。写入失败保留原始备份，移除碰撞后同备份可安全重试且只成功提交一次。已有合法42状态和磁盘receipt不会被失败的旧41迁移替换。

实际40→41→42链只提交一次，只备份原始40。当前42的伏击gem在recovery或链接nova时都能保存重开；gem只允许原固定level1/quality0，不能注入trap/arming/runtime owner字段。正常商店真实购买得到的bag gem也能原生重开。

## 获取方式与冻结奖励

[逐字节合同证明](unchanged-contract-evidence.json)确认NormalJourneyState、EquipmentCatalog、GemTradeRules与SourceTreeRuntime四个生产模块都与冻结v65相同。正常schema26的26项`GEM_DEFINITIONS`数组未改，52个旧oracle ordinal逐项相等，旧gem最低schema全部不变。

使用实际动态GemCatalog/GemTradeRules验证伏击仅出现一次，支持宝石价格仍为4碎片。真实正式存档quote不变更状态；execute扣4并创建一颗gem，重复handle不能再次扣费，保存重开保留该物品。测试档现有`award_random_gem`通过实际排序catalog、seed2命中伏击，无新增经济分支。一个真实普通旅程30根怪物奖励领取仍得到旧oracle第一项`support:efficiency`。

## 失败记录与复验范围

[首次运行](20261006T041410120884Z-migration.log.txt)为298检查/1失败：测试直接将原生浮点字典与JSON读回的ZO oracle比较。差别仅在0.018000000000000002与11.749600000000001的JSON解析精度，原生迁移前后stats相等。[诊断运行](20261006T041449593444Z-migration.log.txt)保留相同失败，且诊断输出用了Godot不支持的`%g`格式，产生4条格式错误。最终只修复测试边界和移除诊断格式；没有为此改动生产实现、原始oracle或旧夹具。

`python3 docs/qa/v066-migration/run-focused.py`默认复用旧夹具，使用已确认的官方`/usr/local/bin/godot`4.6.3与独立`/tmp/godot-m1-v066-migration-*` XDG data/config/cache。每个Godot运行55秒超时，非零退出、SCRIPT ERROR、ERROR或输入哈希变化均失败。runner不import、不访问默认用户存档。后续仅显示文案的GameState变更由独立窄验证负责，不扩大本次298项迁移测试的结论。
