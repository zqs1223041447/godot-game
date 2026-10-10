# 连锁伏击：新交付机制与有限回归

基线 `95a6460296d416d552ed0079da8b1d0cfbb93edd`。先完成[共享瞄准真实输入流程](../aim-input-flow/README.md)：71检查、0失败；未更改该修复。随后明确规则并实现原先拒绝的连锁闪电＋既有伏击辅助，不是只追加构筑说明。

## 范围与实现

放置原脚下符印，0.35秒布防、70触发距离计入体型、12秒寿命、所有技能组共享3枚；首跳命中实际触发者，后续复用原最近未命中可见活敌规则。保留5／7跳、220／286续跳距离及伤害包，主命中×0.85、魔力×1.25、冷却不变。放置冻结一次暴击与完整后续配方，触发不再次收费或抽样。沿用原标签、感电准入、交易、清理与schema61；没有新增trap属性消费者。

生产只改三文件：原伏击兼容表、原符印载体的有界连锁载荷，以及Main提取并复用原直接连锁循环。原新星／陨星载荷逐字节保持。Compiler、伤害解析器、投射物运行时、辅助程序、地形、瞄准、schema与库存事务不变；659个其他生产／资产文件与基线字节一致。无新素材、模型或独立替代施放路径。

## 拥有权与验证

复用已提交 `docs/qa/chain-shock-build/owned.json`，原夹具拥有连锁、远链、感电和40碎片；不把它描述成本批赚取。通过正式商人报价／执行购买伏击4碎片，余额40→36，生成 `item_000011` 入背包，装入原 `group_000006`，主石仍为 `migration_gem_000006`。重复确认拒绝且状态不变，严格保存重载保留UID、装配与整个编译结果。`owned.json` 是本次进入地图前的实际保存，SHA256 `b1ca65aba2490c1c8399ecba7a85391e12426d5f296c684e45ba6c4909d64dce`。

- `attempt-01.log` 保留首次测试变量推断的解析失败；随后改成显式Dictionary类型。
- `attempt-02.log/json`：492检查、0失败。最终补充原两种范围载体完整字节对照、混合共享容量与真实完整地图结算清理后，`final.log/json`：**555检查、0失败**，含**162组旧编译完整字节对照**，覆盖全部10技能、旧空链／单辅、两个伤害快照。新连锁伏击组合在基线明确拒绝；新版本接受，并检验五槽顺序无关、原包／配方／冷却与一次倍率、畸形载荷原子拒绝。
- 实际Main从原地图实体上施放，受控设置站位、高生命、防御、计时与资源以隔离机制。基础伏击5跳、伏击＋远链＋感电5跳、再加延链＋节能7跳；放置时无伤害，0.349秒仍未触发，布防后从符印开始。实际卸下所有辅助、角色移开1200／600后仍沿冻结配方依次命中；逐跳核原标签、真实来源、伤害、感电与不二次收费／抽样。
- 三枚容量满额拒绝不改魔力、冷却、随机状态、施放ID和载体；12秒无触发过期不命中。破碎遗迹实墙阻止近处目标触发，出生保护不触发，可见目标触发后墙仍阻止续跳。通过原伤害结算完成地图全部目标及待生实体，确认地图实际完成并取消未触发符印。
- 原直接连锁 `chain_shock_build_test.gd`：**426检查、0失败**，`direct-chain.log/json`。该测试的独立原拥有权快照保留为 `direct-owned.json`，SHA256 `b880b00526c1e35201879d106c156143dd9e6e23b2ddfa804745b52a6647f1db`；不是本批已购买伏击的快照。
- 原伏击规则／载体：**195检查、0失败**，`old-rules.log`。原伏击实战脚本：**440检查、1失败**，`old-gameplay.log`，不宣称全通过。失败在旧夹具只设置boss_defeated就期望地图完成，未满足现行完整地图账本；前面兼容矩阵、冻结、原子性、几何、顺序目标、原事件优先及其余奖励／取消断言均通过。
- 将基线Main、载体与原实战脚本抽出，仅选择 `rewards_and_cancellation`，同一断言仍失败：**31检查、1失败**，`old-completion-baseline.log`，源文件哈希与仅改依赖／场景路径的说明见 `legacy-baseline.json`。未修改该历史脚本或计数。原脚本因上述失败未运行的 `unchanged_direct_area` 用薄包装单独调用：**15检查、0失败**，`direct-area.log`。新机制的实际完整地图清理另在555项专项中通过。

## 中文F8与边界

生产同源限定导出，追加28条连锁技能示例、3组连锁伏击前后对照；原catalog示例全部保持。区分触发半径、续跳距离及逐跳伤害；原始最低存档42与当前schema61明确分开。只变化连锁、伏击辅助、伏击规则三张卡，其他3815张卡字节一致，21568个内部链接有效，新增运行中文无原字体缺字，合并幂等且HTML与模板同步。证据为 `reference-verification.json`。整理catalog时保留旧示例书写顺序，HTML顺序校验曾提示过期，保留 `reference-check-before-order-rebuild.log`；重新生成后最终 `reference-check.log` 通过。

全部检查有限、headless、隔离用户目录；没有原生F8点击、自然战斗录像、长期平衡或性能验收。旧总览性能问题仍未解决，未重复性能测量。没有600秒检测、全套测试、Windows导出或封包。

## 复现

```bash
python3 docs/qa/tornado-swift/prepare_baseline.py \
  --base 95a6460296d416d552ed0079da8b1d0cfbb93edd \
  --out /tmp/godot-chain-ambush-baseline \
  --dependency ambush_support_rules --dependency player_trap_runtime \
  --report /tmp/chain-ambush-baseline.json
XDG_DATA_HOME=/tmp/godot-m1-chain-ambush-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
AMBUSH_REPORT=/tmp/chain-ambush-review.json \
timeout 45 godot --headless --path . --script res://tests/chain_ambush_test.gd
XDG_DATA_HOME=/tmp/godot-m1-v066-direct-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
timeout 30 godot --headless --path . --script res://docs/qa/chain-ambush/direct-area-regression.gd
python3 tools/verify_chain_ambush_reference.py
python3 tools/build_reference.py --check
```

使用全新用户目录。新机制与原直接连锁测试都会在报告相邻目录写 `owned.json`，复跑时必须用各自独立输出目录。manifest绑定本批代码、资料、拥有权快照和全部原始日志，不修改历史manifest。
