# Canonical 龙卷分裂、返回、自然终止爆炸与取消

基线 main：`41a540d891b9f635605fc2ee5009c103aa9cb9ab`；分支 `codex/canonical-tornado-cue-chain`。本批仅新增测试与QA，没有修改生产代码、模型、战斗规则、schema或素材。

## 实际入口与夹具

`tests/canonical_tornado_cue_chain_test.gd` 复用现有正式破碎遗迹I构造器：真实 canonical 模型、37个已注册原生敌人、原地图几何和入图空旷区域，关闭自动攻击与AI整步推进。通过现有装备事务装备初始包中已有的棱光长弓、返回衣和爆炸护符，通过已有宝石装配事务绑定龙卷；无新造物品、修改词条或注入战斗效果。编译结果保持5母箭、每母箭3子箭。

用测试派生类记录真实 `Main._settle_projectile_events` 执行后的事件与真实 `CombatCues.emit_cue` 接受的特效；都调用原实现，无stub/no-op替代结算。源事件保留projectile_id/parent_id/root_id/cast_id/sequence；cue本身没有投射物来源字段，因此通过真实发射顺序、位置与半径关联，不把cue.id误称为projectile_id。

## 三个有限场景

1. **自然链路**：真实 `cast_group` 施放，随后以1/60秒调用实际 `_update_projectiles` 和 `_update_effects`，最多150步（2.5秒模拟时间）。保留地形和敌人，验证入图区没有实际碰撞或伤害干扰。5母箭各发出一次split并以split_consumed结束，不发生返回或自然终止爆炸；15子箭保留真实父/根身份和代数，各返回一次，仍于原1.7秒寿命结束，再各产生一次唯一的自然终止爆炸。验证return→flight_ended→explosion顺序、effect_id、35个机制特效与事件的位置/半径/顺序，以及cast之后连续的cue ID。
2. **出射母箭取消**：在实际施放后调用真实 `restart_run`，5个母箭引用均成为inactive/run_reset，列表清空。重开按原机制重置暴击计数；取消和随后空投射物更新没有生成自然结束或爆炸特效。
3. **返回子箭取消**：推进到15个子箭均返回，再通过实际 `hit_player_components` 造成玩家死亡；15个子箭引用均成为inactive/owner_death，真实死亡流程清空列表。没有自然结束/爆炸、没有多余次级暴击事件，剩余已接受特效随后正常过期。

自然链路另验证游戏RNG无额外变化，15个真实爆炸继续各接受一次原次级暴击事件；模型和存档不变。所有场景检查后续空更新不能重复特效。无需保持瞬时所有特效存活：记录器在发射时抓取，仍照常运行原过期逻辑。

## 结果与边界

Godot 4.6.3 Linux headless，最终 `results-02.json` / `.log`：**224项、0失败，exit0，无引擎/脚本错误**。保存三个场景的完整精简事件、已发射特效及最终计数。未发现本链路的生产缺陷。

首轮 `results-01` 为224项/1失败：测试错误地期待restart保留暴击计数，而生产 `Main.restart_run` 明确执行reset。仅修正断言为“死亡保留计数、重开重置为0且不生成次级事件”，原战斗逻辑未改。首轮证据保留，不把两轮计数相加。此前legacy集成启动失败证据仍原样保留于 `docs/qa/combat-cues-min-priority/`。

覆盖真实施放、投射物推进、事件结算、特效发射和过期，但本场景不推动AI、玩家位移、近战、命中/伤害、障碍碰撞、容量拒绝或所有辅助组合；不宣称完整自然战斗或渲染验收。不是性能测试，没有长时间全矩阵、Windows导出或封包。

## 复现

使用新的隔离临时用户目录与项目导入缓存：

```bash
timeout 30s env XDG_DATA_HOME=/tmp/godot-exploration-diagnostic-tornado-cues-review XDG_CACHE_HOME=/tmp/godot-exploration-diagnostic-tornado-cues-review-cache TORNADO_CUES_OUT=/tmp/tornado-cues-review.json godot --headless --path . --script res://tests/canonical_tornado_cue_chain_test.gd
```

仅读写隔离夹具存档，未触碰原玩家数据。`verification.json` 保存源指纹及结果摘要。

## 下一项实际游戏问题

地图装置没有呈现已存在的地图玩法说明：`Main.map_options()` 已将 `ExplorationLayout.description()` 的当前布局/敌人数/首领预警说明交给UI，但 `TownServicePanel._build_map()` 只把地图名称和ID放进下拉框；准备摘要/选择预览只显示名称、词缀与费用。地图数据的description没有被选图控件消费，玩家选图前看不到这些既有玩法信息。

下一小批次优先在现有地图装置样式内显示当前所选地图说明，并随选择刷新；直接复用已有正式说明，覆盖未准备/已准备/重新选择，不新增模型、地图、美术或战斗规则。此项为静态调用链确认的UI内容缺口，本批未实施；实施时再做一次真实UI核验，避免连续只堆测试。
