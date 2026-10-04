# v0.39 源天赋暴击词汇与 schema24

本批只新增 9 种完整英文词形，源数据仍固定为 3.29.1、SHA256 `7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122`。节点原值不改写；语句产生的增幅交给运行时消费者。本文和本批测试验证词汇、完整节点分配与保存边界，不代替战斗结算验证。

## 唯一新增词形

其中 N 为非负十进制数；所有正则均以 `^` 和 `$` 锚定，输入另行拒绝换行。值统一乘以 0.01。

|完整源词形|字段|mode|
|---|---|---|
|N% increased Critical Strike Chance|crit_chance_increased|increased|
|N% increased Spell Critical Strike Chance|spell_crit_chance_increased|increased|
|N% increased Melee Critical Strike Chance|melee_crit_chance_increased|increased|
|N% increased Critical Strike Chance for Attacks|attack_crit_chance_increased|increased|
|Projectile Attack Skills have N% increased Critical Strike Chance|projectile_attack_crit_chance_increased|increased|
|+N% to Critical Strike Multiplier|crit_multiplier_add|flat|
|+N% to Critical Strike Multiplier for Spell Damage|spell_crit_multiplier_add|flat|
|+N% to Melee Critical Strike Multiplier|melee_crit_multiplier_add|flat|
|Projectile Attack Skills have +N% to Critical Strike Multiplier|projectile_attack_crit_multiplier_add|flat|

`+25% to Critical Strike Multiplier` 是乘数加 0.25，不是乘数乘 1.25。新增词汇不包含固定基础暴击率、more/reduced、条件、武器限定、幸运、触发、召唤物、异常持续伤害、负值、多行或拼写/标点变体。整节点或所选整项精通中，只要有任意未实现语句，依然不能分配。

## 实际数据覆盖

- 新增完整标准普通节点：46 个；新增完整精通 distinct effect ID：0 个
- 七个职业起点分别都能通过完整支持的普通路径到达其中 45 个节点；每个职业可达普通非起点节点总数为 656
- 剩余节点 23439 自身词条完整，但其两个相邻节点 9015、39524 含未实现的异常持续伤害倍率；七个起点均无法只通过已支持普通边走到它。这里统计不借助特殊珠宝的断连分配
- 攻击专用几率词形目前只出现在仍有流血效果未实现的混合节点，例如 5632；它不会因此变成可分配的完整节点
- 现有完整精通仍为 3 个 distinct effect ID。Critical Mastery 的六个选项仍未完整支持；同名入口不重复算作多个独立效果
- 标准图非精通节点状态为 full 724、partial 225、unsupported 1123；full 含无词条起点/插槽等，不能当作全部可分配或可达数量

[机器可读覆盖报告](qa/v039/source-critical-coverage.json)列出全部 46 个源 ID、原词条、七职业可达集合和预算内路径信息。[示例最短路径](qa/v039/source-critical-example-paths.json)提供各可完整支持暴击字段的实际节点、职业、路径及该节点的全部 grants。

可达性通过 BFS 排除其它职业起点、代理、涂油专属节点、精通穿行和未完整支持节点，再把每个实际路径放入 canonical candidate；全部 45 × 7 条新节点路径均经过现有完整分配与 123 点预算校验。最远新节点的最短路径分别用掉 27、32、28、26、28、33、28 点。

## 版本与保存边界

`allow_critical` 是新增的解析开关。schema24 才能开启；旧的 spatial20、recharge21、resource22、flask23 开关和缓存分区全部保留。schema23 及更老来源不能通过新词汇获得分配许可。line、node 和 analyze 缓存分别覆盖新旧版本来回切换测试。

v23 JSON 先由 `decode_v23` 解码，再按 `reason_v23` 的旧词汇完整验证，之后 `SourceCriticalMigration.migrate_v23` 只改版本为 24。v22 的旧药剂迁移固定输出/验证 23，不能因当前版本上升而跳过中间版本门槛。默认构筑和 loader 整条链最终到 24。

全部其它字段保持，包括 UID、物品、位置、绑定、节点、精通、成长、点数、物品序号、保存修订和工艺修订。原文件只在验证、原字节备份和原子写入都成功后替换；备份冲突、备份后外部改写、未知未来版、注入新节点、非法结构和写入失败均保持原文件与内存安全边界。

## 固定基线与窄验证

`tests/fixtures/v039_critical/` 的两份 literal v23 文件在任何 schema24 源代码编辑前，使用未修改提交 `a4b13688c9bed0911b751854172d073e83935903` 实际导出。不是用新代码创建后把版本减一。一个为默认构筑，另一个含真实药剂节点、revision37、工艺 revision11、level119、xp17。文件带开头空白和 CRLF，字节长度及 SHA256 固定在 manifest。目录内 exporter 仅允许 schema23/应用0.38.0 运行，便于在原提交复现；所有 user:// 路径均隔离到 /tmp。

另从原提交捕获 policy19–23 的每版 4,224 个标准节点/精通结果 SHA256；当前门槛测试验证所有旧结果完全相同。

2026-10-04，Godot `4.6.3.stable.official.7d41c59c4`，独立 `/tmp/godot-m1-v039-*` XDG data/config/cache 环境：

- `source_critical_parser_test.gd`：325 项，0 失败
- `source_critical_gate_test.gd`：1936 项，0 失败
- `source_critical_migration_test.gd`：103 项，0 失败

合计 2364 项。迁移测试含 literal23 原字节备份、所有字段守恒、重读不重写、备份冲突、外部改写、失败后安全重试、非法/未来版/新节点注入保护、schema24 新节点保存失败原子性及重读、v18–22 发布 fixture 和完整13→24链。没有运行历史全量或600秒检测。

重跑仅本批：

```sh
tools/validate.sh res://tests/source_critical_parser_test.gd res://tests/source_critical_gate_test.gd res://tests/source_critical_migration_test.gd
```

可设置 `V039_CRITICAL_COVERAGE_REPORT=/tmp/v039-critical-coverage.json` 输出覆盖报告。战斗/编译/UI/主场景消费者由集成批次单独验证。
