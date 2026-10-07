# v0.96 燃烧死亡预测纯规则验收

一次独立、短时、无性能采样的 Godot 纯规则运行通过：**87,778 项检查、0 失败、退出码 0**；运行耗时 6.925292 秒，标准错误为空，未发现引擎或脚本错误。Godot 4.6.3-stable (official)，仅使用已复制的 `.godot` 缓存，未导入工程，未运行历史验证入口或微基准。这个耗时只记录验收执行，不表示优化效果。

## 性能门槛未通过，生产候选已撤回

随后的独立性能验收中，全部 28 组帧/最终状态/存档保持一致，但 `no_burn` 对照回退约 +10.9%、`ordinary_ignite` 对照回退约 +11.3%，未通过预先约定的门槛。协调者因此已恢复生产 `Main` 和 `DefenseRules`，本页的纯规则通过结果不能解释为优化已发布或性能通过。

本次实际运行的脚本原始字节保留于 `test-as-executed.gd.txt`，当时它直接加载候选生产 `DefenseRules`。当前 `tests/burn_prediction_equivalence_test.gd` 仅做两处归档维护：`Current` 改为加载 `docs/qa/v096-prediction/candidate_defense.gd`，未来报告路径改为 `user://v096-archived-candidate-results.json`。候选源原始字节保留于 `candidate-defense-source.gd.txt`；归档脚本仅移除 `class_name DefenseRules` 行。这两处维护没有再次执行 Godot，也没有改写历史日志、结果或执行脚本快照。

前后哈希、生产函数变化与 `Main` 单调用替换的源证明只对应记录中的候选运行时点；恢复后的当前生产文件以及调整后的当前测试文件不再匹配当时输入哈希。历史证据以 `test-as-executed.gd.txt` 和该次运行记录为准，归档候选不表示当前生产行为。

## 本次检查

- `tests/burn_prediction_equivalence_test.gd` 使用当前生产 `DefenseRules`，对照既有 v095 冻结原始实现；保留旧测试所有向量和帮助函数原文，并在同一次批处理中完成全部原有类型字节检查。
- 6,958 个新预测向量比较 `monster_burn_prediction(raw, fire)` 与旧 `incoming_burn(raw, fire, 0.0, 1.0, "monster")`：`ok`、`reason`、完整拒绝字典和成功投影三字段的类型/序列化字节；`damage_total` 额外逐个比较八字节 IEEE-754 编码。
- 覆盖整数与浮点、负零、最小次正规数、正常数边界、最大有限值、上溢为无穷、下溢到零、抗性上限相邻一 ULP、6,000 个固定种子的随机浮点位模式及原始伤害先于抗性的错误顺序。
- 620 个死亡时刻比较保留原始先加护盾/生命、除伤害率、再加时间的顺序；有限结果在前一 ULP、相等、后一 ULP 处比较死亡事件是否纳入。显式检查正生存时间下溢、巨大时钟加法舍入，以及恰好推进一个时钟 ULP 的补偿。
- 原有完整真实结算回执向量包含 18,000 个双角色魔力分担/最大火抗回退组合、17,745 个双错误优先级组合、6,000 个浮点位模式、完整 typed `Array[Dictionary]` 与 `StringName` 键/插入顺序检查，以及跨调用嵌套字典与数组的独立性、公开结算和普通命中适配器。
- 所有被保留的 v095 向量和帮助函数在运行前后均与原测试逐函数原文比对。没有重跑已通过子集。

## 原始实现和依赖证明

冻结源是 `eaf298a8cbd22c8387da28da118a15afdcd2afb5` 的 `DefenseRules`，与 v0.95 发布基线 `031ff92fab6383461a2688e3be85331655f05351` 的该文件完全相同。原始 SHA-256 为 `a4d88c005dfd27fe6408e86ea9b96a34fe01c786c24c8965113dd20498224226`，冻结脚本 SHA-256 为 `ad19ef28346ee4c03e2d60cb92004ac0740de0e3230b04728bdc32cb861dc04b`。唯一冻结转换是移除 `class_name DefenseRules` 行。

这不是独立冻结的完整依赖树：冻结 `DefenseRules` 仍加载生产 `DamageResolver`。Python 验收器递归遍历全部字面 `preload`/`load` 引用，证明整个四文件依赖闭包均与两个基线逐字节相同；Godot 自身又在批处理前后核对冻结源及共享依赖 SHA-256。所有输入的前后 SHA-256 完全相同。

| 共享依赖 | SHA-256 |
| --- | --- |
| `scripts/combat/damage_base_compiler.gd` | `7c12ba22cc623c87a805a903a957e5841b4f8c0b26cb3b0ca8dae60cf8c9de8d` |
| `scripts/combat/damage_resolver.gd` | `720dc69a7446334e8aec3ac15bdf7c1717fa7b96db5657e0c9622513121a4e23` |
| `scripts/combat/hit_penetration_rules.gd` | `6b0733c563548a9034cd5169b1736287cbffc4b40a14cdf71f37a729c377fc88` |
| `scripts/items/weapon_local_rules.gd` | `73e4308828e856a741ef00386d33150a008bdb3f07ef31a031a204d71fe93b8d` |

源检查同时证明：已有 `DefenseRules` 函数仅 `incoming_burn` 改动，而且两处乘法都只是提取为 `_burn_after_resistance(raw, resistance)`，帮助函数仍严格执行 `raw * (1.0 - resistance)`；其余已有函数不变。`Main` 与 v0.95 基线相比，仅将唯一的预测调用替换为 `monster_burn_prediction`；原 `death_at` 表达式、零率跳过和一 ULP 补偿均原文保留。

## 运行证据

- `run.py`：单次验收器，已有 `run-start.json` 时拒绝覆盖重跑；固定 `/usr/local/bin/godot`，隔离的 `/tmp/godot-m1-v096-rules-*` 五种 XDG 路径
- `run-start.json`、`run-record.json`：准确命令、时间、隔离目录、退出码、错误判定及前后源验证
- `results.json`：检查计数、分类计数及显式浮点字节样本
- `stdout.log.txt`、`stderr.log.txt`：本次运行原始输出
- `input-sha256-before.json`、`input-sha256-after.json`：全部输入哈希
- `test-as-executed.gd.txt`：实际运行测试脚本快照

只证明本次纯规则等价及源/依赖完整性，不代替 gameplay 交互、奖励顺序或性能验收。
