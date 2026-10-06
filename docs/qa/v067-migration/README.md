# v0.67 schema42 → schema43 宝石迁移与供应 QA

聚焦迁移与真实供应 **320 checks / 0 failures**，16.002秒，exit 0，零 SCRIPT ERROR / ERROR；记录的全部输入在该次运行前后哈希一致。仅执行本批测试，没有历史全量、重复 import、Windows 导出、打包探针、ZIP 或 Release。

- [320项日志](20261006T045942121006Z-migration.log.txt)
- [结果与观测](20261006T045942121006Z-migration-checks.json)
- [命令、独立XDG目录、全部输入前后哈希](20261006T045942121006Z-migration-attempt.json)
- [聚焦测试](../../../tests/inward_pull_gem_migration_test.gd)
- [迁移消息4项日志](20261006T050038374609Z-messages.log.txt)与[运行记录](20261006T050038374609Z-messages-attempt.json)：1.879秒，exit 0，零错误，输入前后一致

## 保存边界

当前 schema43 仅新增 `support:inward_pull` 的宝石准入。源天赋执行策略仍为41，装备词汇仍为39。`decode_v42` / `reason_v42` 先执行完整原生42校验；可选 callback 只能追加限制。原 Ambush 41→42 迁移明确停在冻结 `reason_v42`，之后由新的42→43迁移开放牵引辅助。

合法迁移深拷贝后仅修改 version。items、locations、next_item_serial、revision、skill_groups、bindings、talents、progress、crafting、migration_ledger、journey 逐字段严格相等；原生完整 stats、输入与全局随机序列不变。不赠宝石、碎片、点数或新装备 roll。既有伏击辅助的 recovery 所有权和陨星链接保持。

## 独立原生42夹具

从冻结 v0.66 生产 Store 序列化一次，不是用户存档，也不是将当前43输出改成42。捕获前对照 commit `8d51ac6`，177个生产文件（脚本与 project.godot）逐字节一致，见[冻结发布证明](frozen-release-evidence.json)。捕获2.181秒，exit 0，零错误，输入前后一致；没有再次捕获。

- [IR原生42](fixtures/v42-ir-frozen-v066.json)：20,581字节，52物品，SHA-256 `5a4e5b63d1bbfa501f38055894b7a57b884c9d9fe5a05cc8f5adf64cbd96d6a4`
- [ZO原生42](fixtures/v42-zo-frozen-v066.json)：20,714字节，52物品，SHA-256 `94a7ba6f5d24cc60ffc122f7445f008d71f58ee13d6b55faae9179b38e7a5999`
- [原生stats、52个奖励ordinal与全部既有宝石最低schema](fixtures/v42-oracle.json)、[manifest](fixtures/manifest.json)、[捕获脚本](capture-frozen42.gd)、[原始捕获日志](20261006T045718225698Z-capture42.log.txt)

两个夹具均含十个既有装备池实例、带 ironhide / mistweave 与三抗后缀的词汇39胸甲、73碎片、level37/xp9、revision17、crafting revision3、Sunwell最佳tier2、两颗原生伏击辅助。分别使用真实 IR / ZO 分配路线。迁移前后原生 stats 严格相等；与旧 JSON oracle 比较时使用同样的 JSON 序列化/解析边界，避免把 JSON 浮点边界差异误判为机制变化。

## 验证、备份与事务

schema42 recovery 和 nova 链接注入牵引宝石，虽在43合法，仍在42的 reason / decode / migrate callback前拒绝。schema41注入也不能借旧迁移绕过。覆盖20类坏信封：非法修订、额外/缺少字段、journey、UID、节点重复/未知、源版本、点数、roll/affix、位置、serial、绑定、ledger，以及错误根类型、损坏JSON与未来44。

非法源文件不写备份、不改字节、不发布内存或通知，后续save不能覆盖受保护文件。合法42先生成原字节 `.v42-backup.json`，再一次原子提交和一次通知；重开43不重写。覆盖备份失败、冲突备份、备份期间外部修改、真实临时目录碰撞；失败不发布候选，原始备份保持，移除碰撞后可以安全重试。失败的旧42迁移不会替换已有合法43状态和磁盘凭据。

实际41→42→43链只提交一次，仅备份原始41。当前43的牵引gem在recovery或nova链接均可保存重开，payload严格为level1/quality0，禁止加入牵引距离、目标或runtime owner状态。

## 真实获取方式与冻结奖励

[逐字节合同证明](unchanged-contract-evidence.json)确认 NormalJourneyState、EquipmentCatalog、GemTradeRules、SourceTreeRuntime 四个模块与冻结v66相同。正常 schema26 的26项 `GEM_DEFINITIONS` 数组整体保持；52个旧奖励ordinal逐项相等，全部既有宝石最低schema不变。

实际动态 GemCatalog / GemTradeRules 只增加一个牵引辅助条目，正式价格4碎片。真实正式档 quote 不改变状态，execute扣4并创建一颗gem，重复handle不能二次扣费；原生重开保留物品。真实测试商人动态供应恰有一条该gem，`town_claim_offer` 免费放入背包，不改碎片；旧revision不能重复领取，正式存档不能调用免费供应，测试档原生重开保持物品。现有随机gem路径以seed21也能选到新gem，未引入新经济分支。

真实普通旅程30根怪物奖励领取仍为旧oracle首项 `support:efficiency`，不变成新石。最新迁移提示实测包含“牵引辅助”“原字节备份”“不额外赠物或赠点”；重开当前43以及失败载入都不宣告完成迁移。

## 复验入口与证据范围

`python3 docs/qa/v067-migration/run-focused.py` 默认复用已有原生42夹具，只执行本批320项；`--messages-only` 仅执行4项消息验证。runner从不import，使用官方 `/usr/local/bin/godot` 4.6.3及独立 `/tmp/godot-m1-v067-migration-*` data/config/cache，不接触默认用户存档。单次55秒上限，非零退出、SCRIPT ERROR、ERROR或运行期间输入变化均失败。

320项及4项消息测试通过时，`scripts/combat/skill_compiler.gd` 的 SHA-256 均为 `3141e2c7b91b373d00d3742bc76de1053fd81592e4cb1b11712d6af923ca4d60`。之后该文件调整为 `dd3055d341968ca6ba96f72bec8527065cde9cf8e2cedf245e6290920bcb2906`：`_snapshot_error` 在原有reserved分支中新增拒绝 `area_impulse_policy` / `area_impulse_profile` 注入，沿用原错误返回。最终编译器行为由对应定向测试与旧编译oracle负责；本目录不将该运行后改动计作已测试输入，也不为这个边界拒绝变更重跑迁移。迁移与供应生产文件在此次通过后未再修改。
