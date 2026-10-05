# v058：真实 main 的魔力代伤验收

完成：最终玩法脚本 **187 检查、0 失败，exit 0，2.628 秒**。独立已发布 v57 整项目与 v58 的无节点实际 main 各执行一次固定 90 tick / 1.5 秒夹具；显式投影后完整观察字节一致。没有生产/UI 修改、导入、commit、截图、历史全集或长时耐久测试。

## 结果与输入

- `20261005T191855132996Z-gameplay.log.txt`：最终 187/0，脚本 SHA-256 `33596f23dca8c42fa3deadc6bc5bf1a7d2059f051e36eada6e6308a4e8085fa1`
- `20261005T191628613335Z-gameplay.log.txt`：补充换装下一击前的 181/0，2.634 秒
- `20261005T191505783054Z-legacy-old.log.txt` / `legacy-new.log.txt`：278/0 与 368/0，各 2.794 / 2.517 秒；检查数差异来自新版每帧额外断言新增派生 stat 确为 float 0
- `20261005T191505783054Z-legacy-comparison.json`：完整比较、原始存档 hash、明确投影及可无损解压的观察档案
- `final-evidence-manifest.json`：所有玩法运行与已通过 v58 oracle 之间的生产输入差异均为空，支持复用已取得的 90 tick 证据；未重跑模拟
- 各次 `*-results.json` 保留命令、退出码、耗时、隔离 user 目录、生产资源运行前后 SHA-256 与测试脚本 SHA-256。全部生产输入运行前后稳定

## 独立旧版本 oracle

基线是发布 v57 `3718d746` 的完整 `/workspace/scratch/a51485f153de/v057-final-source-snapshot`。两个独立 Godot 进程分别以旧项目与新项目为 `--path`，使用同一绝对路径测试入口，其 `res://` 加载各自整套真实 main、Defense、Model、Compiler、保存和运行时依赖。未用新版减去新字段的公式替代旧执行器，也没有只换旧 main 却共用新版依赖。

唯一允许的比较投影：

1. 模型及已解析保存 JSON 的顶层 `version`：断言旧 34、新 35，然后删除该字段
2. 新版派生 stats 的 `damage_taken_from_mana_before_life`：断言值的类型是 float 且恰为 0.0，然后删除。旧版本不存在此字段

项目版本 `0.57.0` / `0.58.0` 独立保留在报告中；没有声称版本相同。原始存档各 12,178 字节但 hash 不同，解析后仅顶层 version 有差异。投影存档 12,162 字节逐字相等，SHA-256 `06b1135dfcb57c7337e50e0c6060ea597ea4641f9cc053abeb17b3a64cf3f26a`。

完整观察流每侧 11,251,260 字节，SHA-256 `ce46b7579e4696f089bbb297e6fdccfff887bb20389affa4e9dd745151935504`。逐帧内容包括完整敌人/投射物、怪物队列和根奖励状态、RNG、投影后的完整模型与派生 stats、三资源、命中/战斗/burn/感电轨迹、技能冷却、药剂、暴击 RNG、偷取、浮字反馈、粒子、拾取物、保存次数和投影后的完整磁盘 JSON。两边均有 2 次接受施法、3 次真实根死亡及奖励，累计 damage 为 892.612500000015，最终 RNG 为 -3596901892221400320。

`inspect_observations.gd` 仅解码已有 `.bin.gz`，没有实例化 main 或重新模拟。按目标、起止时刻、DPS、provenance 去重后的 531 个 burn 段在两边完全一致：玩家实际 life 损失 11.8，怪物实际 life 损失 188.662500000001。见 `*-burn-deduplicated.json`、对应日志和运行记录。初始 legacy JSON 中 `*_burn_trace_positive_loss` 是重复观察到的累计 trace 量，**不是实际累计伤害**；只读去重报告提供正确实际数值。解码进程有非致命 fontconfig 缓存提示，exit 0，不影响字节解码。

## 真实 source 夹具与覆盖

合法女巫 level 3、7 个赚取点，真实事务逐个分配：

`54447 → 57264 → 37569 → 36542 → 4397 → 31875 → 60398 → 34098`

34098 通过正式 model 分配入口获得，未直接给 runtime 填 0.4。model 只读 profile 的 fraction=0.4、返回脱离缓存、读档重建均有断言。伤害边界夹具仅固定现有资源和防御数值以得到可手算结果。

- 真正 `main.hit_player_components`：减免后 100 无盾时 40 mana / 60 life；25 shield 时 25 shield / 30 mana / 45 life；100 shield 时不花 mana；mana 只有 10 时 10 mana / 90 life
- 混合 physical/fire/cold/lightning/chaos：旧版支持的 armour 和元素抗性先结算，Shock ×1.15 一次，护盾再扣，剩余只分摊一次。旧版 source 防御不消费 chaos_resistance，因此 chaos 保持未减免
- 主场景写回 remaining_mana；mana_spent 不冒充 health_lost；实际浮字反馈只有 shield_spent + health_lost；入伤不产生偷取或 RNG/保存变化
- 无敌、确定性闪避、负值/NaN/bool/未知分量、错误分摊比例拒绝。闪避仅推进已有命中 entropy/记录，三资源不动
- 真正入伤耗尽 mana 后，拥有的真实技能组因魔力不足拒绝：mana/cooldown、投射物、model、两个 RNG 流均不变
- 真正玩家 burn runtime → main burn 入口同样按 shield→mana→life 结算；0.32 秒免疫窗口正确裁去而不延期；抗性生效，armour/Shock 不放大 DOT；mana 不足致死、overkill 和原有死亡一次保存/清理正确，死后不重复支付
- 自然生成怪物没有 mana/玩家分摊字段，玩家 source 不保护怪物；真实输出攻击仍按实际盾血损失产生偷取。偷取、正常 regen、已装备 mana 药剂都恢复同一当前资源，后续入伤可立即使用已恢复 mana
- 实际 azure_charm 移到背包使最大 mana 降低且当前值夹紧；换装后的真实下一击花 4 mana；重新装备只增加容量，不凭空补回资源，不叠加 34098
- 正在持续 burn 时真实退款，后续段立刻全额扣 life；再次分配恢复未来伤害分摊。真正保存/读档、新 run、正式一级地图进入/受伤/返回保持 source，临时资源和效果不存档

最终各主要分区：source 17、hit/feedback 50、原子拒绝/cast 28、burn/死亡 38、恢复/怪物 13、换装/退款/读档/地图 40，另初始化保存 1。`equipment_and_next_hit=12` 是最后一个大分区中的子集，不能再次加总。

## 保留的失败与修正

首次 `20261005T191505783054Z-gameplay.log.txt` 有 3 个混合伤害期待失败并在 45 秒上限退出 124，均为夹具错误：误假设未实现的 chaos_resistance 有效；禁用 HUD 自动 process 后，死亡锁无法靠循环 close_panel 解除。仅修正测试手算基线，以及清场时调用既有 HUD `_process(0.0)` 完成普通下一帧的复活清理。随后 181/0，无生产修改。

补充换装下一击时原计划只运行 equipment 窄子集，但 runner 最后一条分派误写固定 `['gameplay']`，导致实际执行一次 187 项玩法集合，2.628 秒通过；日志按实际 `suite=gameplay` 保留，没有包装成只跑子集。已将分派修为 `[args.suite]`，未再启动模拟。最终玩法脚本与 187 项通过时完全相同；最后只修了 runner 的选择分派。旧 90 tick 未重复。

## 复现入口

正常统一导入完成后可选运行：

- `python3 docs/qa/v058-consumers/run_consumers.py --suite gameplay`
- `python3 docs/qa/v058-consumers/run_consumers.py --suite equipment`：只含合法 source 前置与换装后下一击
- `python3 docs/qa/v058-consumers/run_consumers.py --suite legacy`：完整旧/新项目 90 tick 比较

默认 `all` 按旧 oracle→新 oracle→玩法串行运行。每进程 45 秒硬上限，隔离 `/tmp/godot-m1-v058-consumers-*`；不做 import。版本迁移 backup 与纯 Defense 旧 typed 返回测试由各自独立验收包负责，本包不重复。
