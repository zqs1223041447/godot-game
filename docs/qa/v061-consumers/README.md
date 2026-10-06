# v061 实际消费者与冻结快照证据

最终实际 main 检验 **412 checks / 0 failures，进程 exit 0，2.576 秒**，见 `gameplay-06.log.txt`、`gameplay-06-run.json`、`gameplay-06.json`。没有修改生产代码、旧测试、UI 或版本，没有提交或推送。

## 通过范围

- 真正 level 7 / Marauder 起点，用 11 次 `allocate_passive` 事务分配到 31961：47175 → 31628 → 9511 → 23881 → 26523 → 6446 → 10221 → 50422 → 50570 → 29353 → 63282 → 31961。点数归零、当前 schema 保存/重载相同；真实已装备灰烬皮甲冷、电各 25% 保留。
- 未点编译快照没有新 flag/policy；已点源 stat/snapshot 为 1.0，compiled `hit_policy` 完整，两类 critical chance 均为零。policy 是 compiled 顶层展示字段，施放快照以单一 `resolute_technique` flag 冻结消费者。
- 真正短刃近战普攻、弓普攻、裂刃斩、龙卷父箭/子箭命中，以及 bolt/frost/shade_bolt/nova/meteor/chain 的真实 owned skill group 均执行实际 main，全部不能暴击。
- 1e9 evasion 下，原 cleave 确实 miss、entropy 13.25→18.25、无 leech；启用后恰一条 chance 1 / hit true 的真实 admission，entropy 保持 13.25。15 点实际盾血损失只产生 0.09 生命 / 0.0525 魔力 leech，不使用过量伤害。非 attack 法术/独立爆炸不虚构 attack trace。
- 原进攻 flag 不影响敌方攻击玩家。enabled 所有零暴击路径不抽私有 critical RNG；成对非致死成功命中 shared loot/particle RNG 相同。旧 critical 分支与 enabled 分支的私有 RNG 不同是预期，并未误报为回归。
- 真实墙体挡住近战、裂刃与已发射法术；basic/cleave 原范围保持。出生免疫、死亡、mana 不足、冷却、投射物容量等原拒绝保持；满容量仍允许不需要 carrier 的近战。
- 点前发出的真实弓箭，点后仍旧式 miss，并在后方可命中目标上保留真实旧暴击。启用后发出的弓箭，退款与换剑后仍按 enabled 冻结快照结算；换装和分配均不重置已有 attack timer。
- 原真实龙卷施放 → 父接触 → 分裂 → 子接触 → 退款及移除归航/武器装备 → 返回 → 自然到期爆炸，所有原载体保留快照，退款后的独立爆炸仍不暴击；原已移除的返回效果仍生效。另有一个从真实 compiled snapshot 建立的受控短寿 carrier，精确验证自然到期一次爆炸、两目标共享零暴击，以及第三个出生免疫目标不受伤。

## 独立旧版对照

旧项目 `/workspace/scratch/a51485f153de/v060-final-source-snapshot` 的 491 个全部 tracked scripts/scenes/data/assets/project/export 输入与 b389993ed7f7a90f4043c668704583d44b22f343 完全同 hash，详见 `legacy-v060-production-inputs.json`。未更改旧源目录。

同一个外部 harness 各执行 90 ticks（1.5 秒模拟），两边都 exit 0。都包含真实施放、13 次 projectile hit event、3 根击杀与奖励、incoming attack、保存；没有重新跑完整燃烧传播套件。

完整观察的 **8,607,900 字节相同**，SHA256：

`d4d43b4f211e52c4f1e01ba30bb9a65e4c98132b9373a326025f68e18b569ece`

观察含敌人、弹体及所有冻结快照、怪物队列/根、资源、完整模型、派生 stats、伤害/命中/incoming/event trace、攻击间隔/技能冷却、flask、burn/shock/leech 状态、feedback、particles、text、pickups、shared RNG、private critical checkpoint、每帧保存计数和磁盘 JSON。只投影 schema version 37→38 和经断言恰为 float 0.0 的新派生 stat。没有投影任何嵌套施放快照。

原 raw save **不逐字相同**：唯一 JSON 差异为 schema37→38，精确替换该版本 token 后原字节也相同。只去 version 的完整 projected-save.json 则字节相同。见 `legacy-comparison-01.json`。观察原字节以无损 gzip 保存，解压后 hash/长度如上。

## 输入与保留记录

- 最终实际执行 test（已完整另存 `gameplay-06-harness.gd`）SHA256：`8dfb40ed32165a990199f0e88248538230ae3d390d25ed2d96d8fb8b6804767e`
- 先前通过 396 检查时的原文件保存为 `gameplay-05-harness.gd`，与 `gameplay-05-run.json` 的 `2f7543fe...6074` 精确复核。新增 16 条仅覆盖真实原返回子箭自然到期爆炸、墙体与范围；新增运行先于父级“不重跑主套”的消息启动，之后未再跑主套。
- 旧 90-tick 的原外部脚本保存为 `legacy-01-harness.gd`，与两次 run metadata 的 `26874434...dec3` 精确复核。其非 legacy 分支是历史 fixture 版本；旧对照只执行 `RESOLUTE_LEGACY_OUTPUT` 分支。
- `gameplay-production-inputs.json` 保存最终生产输入 495 文件 hash；生成 manifest 时，没有生产文件在最终实际运行完成后被改过。
- 01–04 的失败日志和真实 exit 1 均保留。均为 fixture/断言问题：稀有皮甲少于 4 affixes；装备目标使用旧 `armor` 别名而非 canonical `body_armour`；误要求 policy 在 snapshot 中重复；重复 equip 已装备 UID 被正常拒为 no_change。没有把这些拒绝改为生产成功，也没有挂住等 35 秒超时。
- 05 与 06 为真实 exit 0。所有 main 运行 2.3–3.2 秒，旧对照各约 2.1–2.2 秒；脚本主动验证事务 ok/必要 keys，失败即结束本 section 并退出 1。

## 边界

这些是 headless 受控实际 main/model/装备事务消费者证据；不是新 UI 截图、物理输入、Windows 性能或自然地图长期运行验收。没有 600 秒运行。

当前 test 在最后执行后只修正一条成功标签与相邻注释：该流程仍装备终焰护符，卸下的是归航披风并更换武器。没有改断言、控制流、API 或 fixture 数据，没有重跑。当前文件 SHA256：`f83f4138025f77e52674e48201cf38111a6f819e9d49e7ed69e2ed35a92f5a89`。原实际执行字节已保留。
