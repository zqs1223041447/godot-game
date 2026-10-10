# 58218 纯净的血肉：实际构筑接入

基线 `9b6d28d1831cf9b34ea469e439e88807f4598227`；分支 `codex/purity-of-flesh`。

原节点 Purity of Flesh 的三个源词条为最大能量护盾提高8%、最大生命提高10%、混沌抗性+8%。此前前两项已经解析，第三项缺少消费者接入，整个节点处于 partial，原分配验证器拒绝购买。本批补齐该节点的最后一项，使其可以通过原 T 天赋树付点分配，并在实际受击时生效。

只解析原完整句 `+8% to Chaos Resistance`，统计汇总同时限定完整节点58218。全树及精通效果比较确认，只有58218的执行结果变化；不开放其他数值、条件、中毒、召唤物、最大混沌抗性。原始源数据、图、点数预算、装备词缀池和伤害结算公式未改。

## 合法路径与可见结果

圣堂武僧 class5：`61525 → 63965 → 14151 → 27564 → 17735 → 58402 → 6764 → 14057 → 9386 → 5743 → 58218`，起点不消耗点数，总计10点。逐边来自锁定源图，沿途节点均完整实装。测试使用合法 level6、10点预算夹具，经原分配命令逐点购买；不是自然升级所得的声明。

- [可分配截图](available.png)：1点可用，原详情完整显示三个效果，原资源预览生命150.65→163.75、护盾107.1→114.3。
- [已分配截图](allocated.png)：0点可用，原退款按钮可用，无“暂未实装”后缀。
- 实际鼠标点击原 T 分配/退点按钮，各支付/退还1点且各保存一次。上升的容量不会免费补满生命或护盾。
- 原主场景100点混沌命中：节点单独供给8%抗性，结算92；原有合法25%抗性戒指与节点相加为33%，结算67；退点后保留戒指25%，结算75。继续沿用护盾先承伤。
- 75%封顶用纯函数边界夹具验证；当前两枚戒指最多50%，加该节点为58%，不声称实际合法装备已经达到75%。非混沌命中的结算不变，完整防御元数据如实增加混沌抗性。

## 保存边界

沿用已有逐版本冻结政策，增加59→60最小迁移。原59解码与全领域验证、原字节备份、并发文件检查、原子写入和一次发布继续使用原实现。迁移仅改变 version，所有其他保存字段保持，不赠物、不赠点；59及更早仍拒绝58218。旧58→59步骤改为验证冻结59终态，然后串接60，避免旧步骤跳版本。

在改动生产代码前运行 `capture-schema59.gd`，保存合法城镇/活动旅程夹具和旧编译统计、伤害结果、全树效果指纹。捕获脚本须在基线59运行，不能在60直接重捕获。fixture来源、文件哈希和旧效果指纹见 `schema59-oracle.json`。装备词汇保持51。

## 有限验证与限制

Godot4.6.3，Linux隔离XDG；每个进程30或45秒上限，无完整core、600秒测试、模型修改、导出或封包。

| 检查 | 结果 | 证据 |
|---|---:|---|
| 59→60迁移、58链式迁移、城镇/活动旅程、原字节备份及失败原子性 | 77/0，exit0 | migration.json / migration.log |
| 最终机制、全树冻结指纹、合法路径、实际分配/退款/保存/受击、装备叠加 | 97/0，exit0 | headless.json / headless.log |
| 原生X11实际点击与截图 | 98/0，exit0 | native.json / native.log |
| 原中文消费者审计 | 38246/0，exit0 | localization.log |
| 原天赋按钮展示 | 13/0，exit0 | presentation.log |

原生验证在最后的纯说明同步之前运行；此后只将 `chaos_resistance_metadata` 的过时“来源天赋未开放”说明限定为58218已开放，并同步对应断言。最终headless增加1条该元数据断言，原生的98包含2条截图断言。实际公式与界面代码没有后续变化。截图已实际查看；Mesa llvmpipe / dummy Xorg的结果不代表硬件帧率或Windows验收。

首轮机制测试95/7：一个断言错误地要求完整抗性元数据不变；退款测试没有等待原界面延迟刷新，导致退款和下游断言连锁失败。修正测试比较范围并等待两帧后96/0，随后说明断言版97/0；失败记录 `mechanism-attempt01.*` 保留，不累计迭代通过数。

旧 `chaos_resistance_rules_test.gd` 回归 **未通过，exit1**：用例执行前的旧冻结依赖哈希检查要求 damage_resolver 为 `720dc69a…`，而基线main及本批均为 `51a3c503c2cae7b7ec1513976de1ed03f41c3677b892b8b55ab47bdb0b2ef6e5`。未放宽该守卫，也未把它计为通过。失败日志 `historical-defense-blocked.log` 保留。本批新增测试独立覆盖真实混沌结算、旧未分配构筑oracle、叠加和封顶。

F8离线图鉴没有重新全量生成；实时T树与当前运行时消费者说明已更新。

复现新增验证（分别使用全新XDG目录；PURITY_OUTPUT目录须存在）：

```bash
XDG_DATA_HOME=/tmp/godot-purity-review-migration XDG_CACHE_HOME=/tmp/godot-purity-review-cache PURITY_MIGRATION_REPORT=/tmp/purity-migration.json timeout 30 godot --headless --path . --script res://tests/purity_of_flesh_migration_test.gd
XDG_DATA_HOME=/tmp/godot-purity-review-mechanism XDG_CACHE_HOME=/tmp/godot-purity-review-cache PURITY_OUTPUT=/tmp timeout 45 godot --headless --path . --script res://tests/purity_of_flesh_test.gd
```
