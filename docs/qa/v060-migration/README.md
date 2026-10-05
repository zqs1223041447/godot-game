# v060：严格 schema36→37 装备词汇迁移

首次集中检查通过：211 checks / 0 failures，12.038 秒，退出码 0。没有 SCRIPT ERROR 或引擎 ERROR，运行前后输入 SHA256 一致。本目录只检查本次迁移、相邻版本链和持久化故障，不重跑历史全套，也不把它代替装备规则、战斗消费者或 UI 检查。

- 测试：`tests/elemental_defense_affix_migration_test.gd`
- 原始日志：`20261005T203957633536Z.log.txt`
- 命令、退出码、耗时、隔离目录、所有生产 GDScript 与实际数据/fixture 输入前后哈希：`20261005T203957633536Z-attempt.json`
- 断言计数、旧输入 SHA256、新物品 payload：`20261005T203957633536Z-checks.json`
- 有界执行器：`run-focused.py`，45 秒上限，独立 `/tmp/godot-m1-v060-migration-*` data/config/cache；必须在父任务统一完成 import 后运行，不自行 import

## 发布旧档来源

`fixtures/v36-released.json` 逐字节来自已发布提交 `0816322e4c9a53d264bce9c5223810a93ead2348` 的 `docs/qa/v059-consumers/20261005T200917792922Z-v059.save`。共 12,178 字节，SHA256 `d2b6b42e33fead6e6a57f002dcf276a2c1b7b19d1e8a3cf3143c4c9f483a9db3`。来源与大小记录在 `fixtures/manifest.json`；没有重新序列化，也没有把手工换版本的数据称作旧客户端产物。

35 与 34 版本链直接复用既有 fixture，SHA256 写入检查结果。8 个旧装备池、完整最大抗性分配路线与新的双抗灰烬皮甲为测试候选，明确区别于发布原字节。

## 覆盖范围

1. 当前存档版本和装备词汇为 37，源树执行版本仍为 36；schema35/36 显式映射到设备词汇 34。设备 Catalog 的显式词汇参数 35/36 继续拒绝，旧计划调用语义不变。
2. `decode_v36` / `reason_v36` 完整冻结旧装备与原生天赋校验。当前正缓存、宽松 callback 都不能向旧36/35注入冰霜或闪电后缀，不能绕过未知节点、重复节点、预算或源版本错误；附加 callback 仍可收紧规则。
3. 迁移只深复制并将 version 改为 37。所有旧字段、UID 顺序、位置、装备 payload、roll、序号、货币、点数、成长、journey、revision 原样保留；无赠物、补词缀、重掷或 RNG 消耗。
4. 8 个历史池 `legacy`、`nine_slot`、`runewood`、`defense`、`local_weapon`、`build_legacy_v27`、`build_nine_slot_v27`、`forgeblade_v34` 全部在35/36严格有效，并经过真实迁移保存保持 payload。
5. 74 个分配节点的旧36最大抗性路线在37合法，全部原始与最终 stats 相等；没有扩大源树 stat、节点或图范围。
6. 真正旧36原字节先备份、再原子提交、再发布内存，成功一次；重复 load 和独立 reopen 不再重写。旧35→36→37、旧34剩余链与内置历史全链均到37，单次提交，只备份原始版本文件。
7. 覆盖损坏 JSON、坏36结构/天赋/装备值、未来38；拒绝后原文与 live state 不变，无备份、提交或通知，并保护后续 save。
8. 覆盖备份失败、备份冲突、备份期间外部修改、真实 `.tmp` 写入冲突、相同备份下恢复重试。已有 current37 内存和磁盘 receipt 在旧档失败或损坏时保持不变。
9. 真正包含 `rimeward` 与 `stormward` 的稀有灰烬皮甲在37保存/reload，roll 均为整数 ticks；物品真实移包失败保持全部数据、原文与通知，移除故障后一次提交；外部改盘后 receipt 阻止覆盖。

这是首次通过的集中运行，没有为生成报告重复执行。新运行必须使用执行器生成的新时间戳，保留之前的 attempt 与原始日志。
