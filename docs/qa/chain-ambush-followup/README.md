# 连锁伏击交付后的有限核查

基线 `18303a9b8012c28989b785c1809a03f4972641e4`。先读取上批证据，未重复执行已通过的完整伏击矩阵。

## 旧地图完成夹具

上批 [old-completion-baseline.log](../chain-ambush/old-completion-baseline.log) 已用修改前 `95a6460296d416d552ed0079da8b1d0cfbb93edd` 的Main／载体复现同一失败，31检查、1失败；源哈希见 [legacy-baseline.json](../chain-ambush/legacy-baseline.json)。当前MapRunState要求完整登记／死亡账本，旧夹具只把boss_defeated置真，缺少普通根实体与首领登记。

本批只修 `ambush_gameplay_test.gd` 的完成夹具：构建完整身份记录，调用原 `register_initial_group` 和 `record_death`。继续通过原 `_check_map_complete`，保留原“map_complete且trap_runtime为空”断言及原生产逻辑。这里是完成账本夹具，不冒充实际全图战斗；真实全图结算清理已在上批555项专项中通过。

薄包装仅调用 `rewards_and_cancellation`。`completion-fixed-first.log` 32检查通过；把账本登记与全部死亡的返回值作为明确检查后，最终 `completion-fixed.log` **33检查、0失败**。未重跑旧实战脚本全部场景，也未修改其历史计数。最终运行已包括本批新星代码，未装寒意延长的原新星符印保持原取消语义。

## 连锁缺失边界

原范围伏击已覆盖死亡重选、同距候选、暂停／死亡／重开／换档取消，见上批 `old-gameplay.log` 对应通过段。本批只给连锁新增路径补专项：`attempt-01.log/json` **44检查、0失败**。

复用上批已实际购买的 `owned.json` 与真实旧花园根实体，未购买或赠送。原伤害结算杀死候选后，尸体仍在容器时不触发；原 `_flush_monster_spawns` 移除后仍等待，随后真实活候选进入才消费一次。两个候选同帧、同距进入，逆转敌人存储顺序，首跳仍命中最小ID且等于符印选定的触发者。首跳杀死触发者后，从捕获的位置继续击杀续跳目标；第二枚符印读取当前死亡结果后保持待触发。随后真实 `restart_run` 取消该符印，之后观察不再命中、收费或抽样，物品UID与装配保持。

未发现连锁生产缺陷，不改连锁执行、选敌、触发或重开函数。所有位置、耐久与资源设置均为受控headless夹具，不是自然游玩录像。

```bash
XDG_DATA_HOME=/tmp/godot-m1-v066-completion-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
timeout 30 godot --headless --path . --script res://docs/qa/chain-ambush-followup/legacy-completion.gd
XDG_DATA_HOME=/tmp/godot-m1-chain-followup-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
FOLLOWUP_REPORT=/tmp/chain-followup-review.json \
timeout 40 godot --headless --path . --script res://tests/chain_ambush_followup_test.gd
```

每次使用全新隔离目录。证据由相邻 `nova-lingering/manifest.json` 共同绑定。
