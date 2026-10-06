# v0.82 冰霜异常时长：实际 Main 与零源短对照

本批仅验证 `14209` 的无条件 `20% increased Duration of Cold Ailments`。正式生产/UI代码不由本验证修改。入口为 [cold_ailment_duration_gameplay_test.gd](../../../tests/cold_ailment_duration_gameplay_test.gd)，只预载旧树已有类；零源分支可以用完全同一文件运行已导入的 v0.81、v0.82 项目。

[acceptance.json](acceptance.json)为42项只读收据核对，0失败。实际 Main 集中运行283项、0失败、9.128秒；v0.81/v0.82零源观察各74项、0失败，分别7.652/7.411秒。计数包含最终报告文件成功打开这一项；原始JSON在打开前构造，因此其checks分别为282/73/73，最终日志为283/74/74，收据已明确核对这一个差值。

## 实际 Main 覆盖

- 复用 [cold_ailment_duration_fixture.gd](../../../tests/fixtures/v082/cold_ailment_duration_fixture.gd) 的 `prepare(model,path,allocate_target,3)`。真实level4、8点预算；Witch原路径 `54447 → 57226 → 21678 → 32210 → 8948 → 27659 → 37671 → 27415 → 14209`，每个付费节点都经过真实allocate、save-first命令，没有注入duration stat
- 清空真实恢复栏后，把当前辅助UID移回合法背包位置；用 `award_gem` 取得新owned gem，立即 `move_item` 进入对应group的support槽。没有手写装备、重复引用gem、无效原始位置表或超额点数
- 原plain Frost `3 → 3.6`；寒意延长 `4.5 → 5.4`，实际顺序 `3 × 1.5 × 1.2`；实际载体命中保留这些值。全部packet、解析伤害、法力、冷却、数量和其余配方字段不变
- 普通/魔法/稀有/首领实际Main冻结 `0.72 / 0.72 / 0.42 / 0.24` 秒，正冰霜护盾实损仍可触发。冻结使用当前结算边界而非更早的扫掠接触时刻
- 实际投射物在0.25结算，普通怪冻结至0.97；0.5秒全冻结后再过0.4秒，仅0.18秒攻击/自主移动恢复，原0.36减速移动倍率不变，slow自身时钟持续流逝
- 两组不同owned主宝石、不同group与cast身份共用同一个目标状态：同刻与冻结中不刷新，解冻精确边界进入保护；保护到期前一个float步长仍不能冻结，到期精确边界才重新冻结。保护固定1.5秒
- 飞行中真实分配或退款14209，再把合法owned ember_wand换为swift_blade：所有旧载体字节不变；旧命中使用原slow、freeze policy和原critical快照，新实际cast读取新时长和新武器
- 原Nova与伏击Nova实际命中仍为0.6秒通用slow，不获得冻结
- `DamagePreview.details`直接读取上述真实 `get_group_cast` 的recipe与freeze_profile，显示3.60/5.40与0.72/0.42/0.24、固定1.50；读取只读且重复结果一致。实际分配、退款保存后均重新加载验证

没有重跑既有100目标容量测试、全历史战斗、600秒压力、原生图形或Windows打包。纯规则和迁移验证由本批对应报告负责。

## 零源逐字对照

旧基线为父任务提供的 `a57a9c0c` 已导入 v0.81 树。两边都从合法level4 Witch起点、没有14209，实际装配并运行 plain Frost、寒意延长Frost、霜锁Frost、Nova、伏击Nova。每例保留完整compiled cast和preview，以及施法前、施法后、首次实际命中、短后续tick、真实稀有怪死亡掉落后的五份观察。

观察包括所有投射物、冻结内部状态及活动UI投影、damage/combat/trap/telegraph/incoming/attack-admission事件、敌人、资源、冷却、cast/projectile身份、critical RNG、战斗/掉落共用RNG、全局RNG后续抽样、owned items/locations、成长与journey。稀有怪真实死亡保证实际生成一次owned装备，覆盖原掉落随机消耗。

[v081-zero-result.combat.bin](v081-zero-result.combat.bin) 与 [v082-zero-result.combat.bin](v082-zero-result.combat.bin) 均为原始 `var_to_bytes(records)`，各619,724字节，逐字一致。SHA-256：

`f0df2381f8fc605d9b76097682c1f0c18407f32b75cfab2b026141e1bdd90ecb`

**没有删掉、归一化或投影任何战斗字段。** schema48→49和完整最终canonical model分别保存在原始JSON顶层与 `zero_source_final_model`，不混进战斗观察流，也不声称完整存档跨schema逐字相等。两份原始JSON、二进制和执行日志全部保留。

## 最短复验

在已经完成父任务统一import的v0.82根目录，三个入口各运行一次即可；脚本自动分配独立 `/tmp/godot-m1-v082-cold-*` XDG目录、限定90秒，并保留命令、耗时、退出码、日志和测试SHA。v0.81位置为同级 `v081-map-device-refresh`，不复制旧树、不再次import。

```sh
python docs/qa/v082-gameplay/run_checks.py main
python docs/qa/v082-gameplay/run_checks.py v081-zero
python docs/qa/v082-gameplay/run_checks.py v082-zero
python docs/qa/v082-gameplay/verify_receipts.py
```

只需审核现有结果时，运行最后一条即可，不启动Godot。若后续只修改一个section，runner支持 `main --sections actual_hit_and_partial_thaw --suffix=-affected`，保留完整原始通过记录。

首次三个入口在执行任何section前遇到测试自身条件表达式返回普通Array、赋给Array[Callable]的类型错误。已停止这三个进程，保留 `*-initial-entry-failure.log`；只把测试局部声明改为Array后重启尚未执行的三个入口。没有修改生产实现，也没有重新import。

## F8同源只读入口

[fixtures/compiled-preview.json](fixtures/compiled-preview.json)包含十份真实Main导出的stats、完整cast和preview。对应 `before/after-{plain-frost,lingering-frost,frost-lock,nova,ambush-nova}.json` 均为完整合法model；before有1点剩余，after完整8点已用，pending恢复栏为空。用[主报告](main-result.json)的 `failures == 0` 和compiled section通过作为前置，直接读取这份结果即可，不需要再创建近似装备或手写gem布局。

需要独立只读重编译单份Frost样例时，可运行 [export_fixture.gd](export_fixture.gd)：

```sh
COLD_DURATION_EXPORT_SOURCE="$PWD/docs/qa/v082-gameplay/fixtures/after-frost-lock.json" \
COLD_DURATION_EXPORT_DESTINATION=/tmp/v082-frost-lock-preview.json \
godot --headless --path "$PWD" --script res://docs/qa/v082-gameplay/export_fixture.gd
```

该入口仅 `load_build → get_skill_cast("frost") → DamagePreview.details`，验证model及pending，并核对读取前后原fixture字节不变；不建立Main、不分配源、不授予物品、不导出词典。本批没有为此额外执行一次Godot；F8资料任务可自行单次批量复用这些已通过原件。
