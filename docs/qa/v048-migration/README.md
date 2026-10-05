# Schema30 晴泉台地迁移验收

Schema30 将普通旅程的地图词汇扩为 `old_garden`、`broken_ruins`、`sunwell_terrace`。合法旧29只增加 `journey.best_tiers.sunwell_terrace = 0` 并更新版本30。原两图进度、进行中地图、待领奖励、累计击杀及已领宝石/药剂序号保持；不追补击杀、不赠送碎片或物品、不修改 UID、技能、天赋、工艺、绑定或物品位置。

## 边界

- `NormalJourneyState.empty_legacy/decode_legacy/reason_legacy` 严格冻结 schema26–29 的两地图结构；current 三地图结构单独校验，不容忍缺键、额外键或把新图混入旧版
- `CanonicalBuildRules.decode_v29/reason_v29` 校验旧29完整规范结构；所有旧26–29入口选择 legacy journey，current30选择新journey
- 历史25→26始终生成legacy空旅程；历史28→29终验固定 `reason_v29`，不随current版本漂移
- `ThirdMapMigration.migrate_v29` 先验完整旧29，再深拷贝，只变两个字段，再验current30；不得重复迁移或消耗RNG
- Store完整历史链尾端追加29→30，原文件实际版本原字节备份后原子写一次，成功写盘后才接受内存；不生成中间版本备份
- 备份冲突、备份IO失败、原子临时文件失败或备份期间外部改写，保留应保护的原文件、备份与内存；迁移失败仍保留之前接受的receipt
- 正式新图I初始可选；I/II/III沿用wave3/6/10、入图费用0/4/8、完成基础奖励4/8/12及既有最多+4词缀奖励；未完成本图不继承其他地图解锁

## 已发布旧包证据

`third-map-capture.gd` 以 `--main-pack /workspace/scratch/a51485f153de/v047-final-release/game.pck` 运行已发布v0.47.0包。脚本断言应用版本0.47.0与schema29，通过旧包实际装备掉落、绑定、地图开始/完成、击杀经验、奖励领取、工艺与宝石商人API构建样本。没有载入current源码，也没有用current存档降版本伪造旧样本。

四份原字节CRLF夹具位于 `fixtures/`：

- `v29-default.json`：已发布默认构筑
- `v29-ember-bag.json`：真实付费余烬辅助仍在背包，包含装备、工艺、键位、奖励序号改动
- `v29-active.json`：同一余烬UID连接陨星，旧庭II付费进行中，90根怪、已领宝石2/药剂1、尚有应得序号
- `v29-pending.json`：上述地图已完成，12碎片仍待领取

同包导出的 `v29-vocabulary-oracle.json` 冻结26种里程碑宝石及128个旧序号。`fixtures/manifest.json` 记录PCK、捕获脚本和每份原字节样本长度/SHA-256。捕获日志为 `third-map-capture.log.txt`。

## 定向测试

`tests/third_map_migration_test.gd` 覆盖四份literal保持、旧词汇拒绝、畸形输入、原字节备份、重复重开零写入、原子/备份失败、外改、receipt保留，以及独立旧25/26/27/28夹具通过完整现有链。默认Store构造同时覆盖更早历史迁移全链。

`tests/third_map_transactions_test.gd` 通过真实Model/API验证晴泉台地I初始入图、II/III准确扣费、词缀奖励、完成/领取只发生一次、失败回滚、放弃不退款、满240格仍保留待领、重开与腾一格后的真实货币入包。满包夹具只为隔离容量场景直接构造合法UID物品；地图与奖励操作全部沿正式API。

运行环境必须使用独立 `/tmp/godot-m1-v048-*` 的XDG目录。本批不跑600秒GUI测试，不重跑旧交易全量，不声称Windows硬件验证。最终结果及受测文件签名随测试日志记录。

## 最终结果

- `third-map-migration-test.log.txt`：331 checks，0 failures，退出0，无 SCRIPT ERROR / ERROR
- `third-map-transactions-test.log.txt`：29 checks，0 failures，退出0，无 SCRIPT ERROR / ERROR
- `third-map-tested-files.json`：命令、隔离路径、退出码、日志及受测生产/测试文件 SHA-256

测试脚本首次启动的局部变量类型推断错误已改为显式Dictionary后重跑通过；未因该问题修改生产代码。
