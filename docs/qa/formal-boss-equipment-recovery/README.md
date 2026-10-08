# 正式首领稀有装备满包保留

基线：`813170c83ea8915df95514b5d6a32429226d3b04`。
审查分支：`codex/formal-boss-equipment-recovery`；本工作不合并或推送 main。

运行时代码仅改 `scripts/main.gd` 与 `scripts/canonical_game_state.gd`。正式地图已登记的首领根怪经原 once-only 死亡账本领取原稀有装备：沿用原池、等级、UID 分配与第一次词缀掷骰，有空间入包，满包进入原 recovery。已有待安置物品不会被替换；有空位仍优先入包。普通掉落、测试奖励、首领珠宝及经济来源沿用原路径。

## schema55 依据

`CanonicalBuildMigration.paged_location_context()` 继承 `allow_recovery=true`。
`ItemLocationRules` 的既有 recovery 校验允许装备，要求独立非负 index 且低于物品总量。追加 index 使用加入新装备后的 `items.size()-1`，高于所有既有合法 index，因此不覆盖旧队列位置。仍经过统一装备注册表验证、元数据、完整 `Rules.reason`，以及原 serial/revision/item-count 上限。

既有 `CanonicalInventoryPanel` 的待安置按钮调用 `first_bag_position → move_item → _commit`，直接支持取回；未新建库存、奖励队列、界面或存档字段。版本仍为55，历史迁移及历史合法性规则逐字未改，见 `scope.json`。

## 保存语义

沿用 Main 的死亡奖励批处理。成功时完整候选包含击杀进度、XP 和装备，再一次保存。写入失败时旧磁盘字节不变，完整新内存及原 UID/词缀保持 dirty，显式重试保存同一候选；死亡账本不重发奖励。这不是对整次死亡的回滚，也不是独立提前落盘首领奖励。待安置取回沿用既有 `_commit`：保存失败时内存、位置和磁盘全部不变。

## 有限验证

Godot `4.6.3.stable.official.7d41c59c4`，Linux headless，各写测试使用独立 `/tmp` XDG；各进程最多45秒。

- `tests/formal_boss_equipment_recovery_test.gd`：**169 / 0**，见 `targeted.log`、`report.json`。实际 Main/HUD、正式 Old Garden I 登记首领及伤害/死亡路径；容量、已有 recovery、写入故障使用明确防御夹具；不注入费用或结算奖励。
- 正常入包、满两页、已有待安置、已有待安置但有空位：比对原生成器首次结果和 RNG，完整保留旧物品/位置；不重掷。
- 原待安置按钮满包拒绝、合法丢弃容量夹具腾出矩形、按钮移动写入失败、同 UID/全词缀成功取回；精确 canonical 重载。
- 死亡批保存失败、旧存档精确重载、失败重试、成功保存同一候选；实际 Main 重载按原规则放弃未完成地图而保留全部物品，不赠送结算或退款。
- 原死对象重复调用及同身份去除 `death_processed` 的副本：无新增奖励、serial、RNG、保存。实际完整25根怪地图仍仅一首领装备决策，原解锁、四碎片待领、领用及付费 tier-II 入图成立。
- 测试城镇/地图满包首领仍按原规则拒绝，正式存档字节不变；普通路径与 demo 不新增 recovery。正式 API 校验 active run/profile、注册池及合法上限，拒绝恢复 RNG。
- `tests/safe_map_exit_test.gd` 仅 `completion_recovery` 组：**35 / 0**，见 `safe-exit-completion.log/json`；未改旧测试。
- 旧 `reward_batch_equivalence_v38_test.gd` 仅 `--check-only`：继承接口静态解析通过，见 `reward-override-parse.log`；未运行冻结历史期望或全套测试。
- `git diff --check` 通过。

复跑：`FORMAL_BOSS_RECOVERY_REPORT=/absolute/report.json bash tools/validate_formal_boss_equipment_recovery.sh`。报告包含逐项证据、实际装备实例、位置及源码 SHA256。

静态解析首次漏设 XDG，Godot 在不可写的默认日志目录初始化时退出；隔离目录重跑通过。最终日志均无脚本/引擎错误。

## 未覆盖边界

未做原生图形截图、Windows 导出、600秒检测、长期全套、模型或 F8 资料更新。实际地图验证限 Old Garden I 及其原 tier-II 收费入口，没有逐张清完全部地图/词缀组合；底层生成与目录均未改。

达到既有 `V17_MAX_ITEMS=1025`、serial/revision 上限时仍拒绝新增，不能保证该边界下保留新掉落；没有扩大容量或绕过校验。进程在尚未成功保存的整批奖励期间退出/崩溃仍遵循原未落盘语义，不提供新 WAL 或持久化死亡账本。原子写实测覆盖 `_write_bytes` 返回错误，不模拟机器断电或文件系统损坏。普通怪、珠宝等满包保留不在本次范围内。
