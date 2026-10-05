# Schema29 余烬扩散迁移验收

新增 `support:ember_proliferation` 仅允许出现在 schema29；原 `support:ignite` 最低版本仍为28。装备词汇版本仍为27，源天赋执行版本仍为25。此次迁移只将合法旧28存档的 `version` 改为29，不分配物品、不改变 UID/序号、不改奖励序列、经济、技能组、天赋、货币或普通旅程。

## 实现边界

- `CanonicalBuildRules.decode_v28()` / `reason_v28()` 以冻结版本28执行既有严格边界校验，包含背包和已连接宝石的版本词汇检查；已预热当前 metadata 缓存也不能接纳注入旧28的新宝石。
- `EmberGemMigration.migrate_v28()` 先验旧28，深拷贝，仅改版本，再验当前29。
- `IgniteGemMigration.migrate_v27()` 的历史输出锁定 `reason_v28()`，避免 current29 破坏27→28历史链。
- Store 默认初始化与旧存档加载尾端追加28→29；只备份原文件的实际旧版本，不生成中间版本备份。
- 沿用原备份、原子写和 receipt 防外改流程。旧存档校验与原字节备份全部成功后才写新存档；成功写入后才接纳内存。备份冲突、备份失败、写失败、外部改写均不覆盖原先应保护的数据。
- `CanonicalGameState.load_build()` 对旧28显示余烬已开放购买且不赠物的提示。

## 独立旧版本样本

`ember-migration-capture.gd` 通过 `--main-pack` 直接运行保留的 v0.46.0 发布 PCK。脚本先断言 schema28 与应用版本0.46.0，再使用该旧包真实的地图、击杀经验、奖励、装备、键位、工艺、宝石购买及连接 API。未载入修改后的源码，未通过当前快照降版本制造旧样本。

旧包 SHA-256：`3fe35502889fec4954f986413a346339175174a2a67cac21f46c19a04fd1b5fd`。

`fixtures/` 包含四份冻结 JSON，全部保留 CRLF、头部空格和尾部制表符：

- `v28-default.json`：原发布默认构筑
- `v28-ignite-bag.json`：真实付费购买的点燃仍在背包，有装备、工艺修订、绑定改动及已领取奖励序号
- `v28-active.json`：同一已购点燃 UID 连接陨石，付费 T2 进行中；90 根怪、level4/xp6、已领宝石2/药剂1，尚有应得宝石序号
- `v28-pending.json`：同一 T2 已完成、12 碎片仍待领取

同一旧包输出 `v28-vocabulary-oracle.json`，包含冻结26种普通里程碑宝石、128个确定序号结果及27个旧宝石最低版本。`fixtures/manifest.json` 记录全部原字节长度与 SHA-256、捕获脚本和旧包校验值。

`NormalJourneyState` 源码保持原字节 SHA-256 `10b2ba7db25764a0ad34f447ed71acb4a876a49e26bd6fa824056d1e1fee0f89`。

## 定向检查结果

`tests/ember_gem_migration_test.gd`：1026 checks，0 failures，退出0，无 SCRIPT ERROR / ERROR。日志见 `ember-migration-test.log.txt`，源文件签名与隔离命令见 `ember-migration-tested-files.json`。

覆盖：

- 四份旧28逐字段保持，源输入不可变，仅版本28→29；纯迁移不消耗全局 RNG
- 原字节备份、一次写入/通知、准确 receipt、新实例重开/重复读取零重写
- schema29 新宝石在背包及合法独立连接中可读；旧28无论背包/连接、热缓存、回调 validator 均拒绝新词汇；旧25/26/27不能洗入新 ID
- 布尔/小数/字符串/空值等非法 payload、别名、StringName 身份、额外运行字段与未来版本的拒绝且不写备份/原文件
- 已存在不同备份不覆盖、模拟备份失败、模拟写失败及同备份重试、备份期间外部改写、真实临时文件目录冲突与重试
- 已载入当前存档后，再加载旧档失败时保留旧 receipt；迁移完成后外部改写仍受保护
- 字面历史14–27各 canonical 分支与原 legacy 默认完整链到29；25→26、26→27、27→28保持各自历史输出；只备份实际输入版本
- 冻结26种奖励及128个旧序号、所有旧 gem 最低版本、无默认新辅助赠送，商店28种当前报价与8/4/1经济常量

本测试作为 schema29 当前入口覆盖历史迁移边界；`tests/ignite_gem_migration_test.gd` 是以 current28 为前提的历史验收，未将它的固定当前版本断言改写成新验收。未重跑历史全量、未运行600秒检测，且无 Windows 实机结论。
