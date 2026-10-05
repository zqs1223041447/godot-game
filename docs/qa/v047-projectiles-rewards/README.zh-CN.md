# v0.47 真实龙卷与燃烧奖励补测

2026-10-05 UTC，Godot 4.6.3 headless 首跑完成：**97 checks，0 failures，退出码 0，2.157 秒**。无 SCRIPT ERROR、无断言挂起、无失败重跑；没有启动 GUI 或执行整套历史测试。

新增测试为 `tests/ember_projectile_rewards_test.gd`（141 行）及对应 UID。生产文件未修改。本测试只补 `ember_gameplay_test.gd` 已覆盖之外的真实投射物交付与奖励路径。

## 真实投射物交付

- 实例化 `scenes/main.tscn`，经 `_execute_compiled` 扣费并发射原有三支母箭
- 经 main 的 `_update_projectiles` 调用原 `projectile_runtime.advance`：三次实际范围分裂生成九支子箭；九次自然飞行结束生成九个独立爆炸事件
- 母箭、子箭各命中存活目标，核对不同角色的实际燃烧 DPS、gen0、命中 projectile/cast/phase 来源，以及真实接触时刻加三秒的原始期限；未人工注入投射物或状态
- 不在任何飞行路径上的两个目标分别被实际独立次级爆炸打伤、击杀；其火焰预算仍为 90，未套用主命中的 0.75 惩罚。存活目标不附燃，爆炸击杀不向附近未命中目标扩散

## 正式奖励与原有裂殖限制

- 使用隔离正式 schema29 存档，真实使用两瓶药剂腾出充能空间
- 经 `_spawn_monster` 生成真实 splitter 根，主命中附余烬燃烧，DOT 完成死亡：配置 XP、normal_root_kills、reward_kills 各结算一次，两瓶各加一充能
- 原根尸体与死亡前复制出的同身份尸体均无法重复领取；实际排队及刷新产生原有三只后代，保留出生保护、root_id、generation1、零 XP/奖励资格
- 实际后代再次由新余烬燃烧收尾，重复尸体回调也不增加 XP、正式根击杀、充能、存档写入或更多后代
- 原 Catalog 验证通过的六裂殖分支 fixture 仅替换本测试 runtime 的模板输入；未改生产模板或预算。实际根 DOT 死亡接着六只 splitter DOT 死亡，仍只允许两组三只孙代，四支返回 lineage_budget；原根加十二后代终止，无额外奖励

fixture 只控制隔离场景中的怪物生命、防御、出生保护、速度、位置和范围，保证无移动/随机命中干扰。模板预算 fixture 沿用现有 `monster_system_test.gd` 的合法六分支结构。后代燃烧使用真实 `_apply_damage_packet`，其死亡使用真实 `_advance_monster_burns`、`_finish_enemy_death`、`process_death` 和 `_flush_monster_spawns`。

## 可复现命令与证据

```bash
XDG_DATA_HOME=/tmp/godot-m1-v047-extra/run1/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v047-extra/run1/config \
XDG_CACHE_HOME=/tmp/godot-m1-v047-extra/run1/cache \
GODOT_SILENCE_ROOT_WARNING=1 \
godot --headless --path . --script res://tests/ember_projectile_rewards_test.gd
```

复现请用新建的隔离目录，避免重复使用已有正常进度。实际运行外层监督在日志出现 `SCRIPT ERROR` 时立即终止该进程，并设置 60 秒兜底；本次自然退出。

- `run1.log.txt`：全部 Godot 日志与三个路径完成标记
- `run1.json`：命令、隔离目录、退出码、耗时、终止原因、测试源码 SHA-256
- `tested-files.json`：测试、main、compiler、投射物、燃烧、奖励/裂殖相关 13 文件的 SHA-256；所有文件修改时间均早于本次测试开始

本补测没有重复编译器纯配方、分帧一致性、近同刻排序、墙体、购买装配与主 UI 检查；这些属于各自已有定向证据。
