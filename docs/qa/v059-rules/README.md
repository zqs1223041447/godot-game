# v059 纯规则：最大元素抗性

## 权威合同

`DefenseRules.resistance_profile(stats: Dictionary, actor="player")` 返回只读完整资料：

```text
{ok, reason, base_cap: 0.75, safety_cap: 0.83,
 raw_resistances: {fire, cold, lightning},
 maximum_resistances: {fire, cold, lightning},
 effective_resistances: {fire, cold, lightning}}
```

三种元素各自读取 `fire_resistance` / `cold_resistance` / `lightning_resistance`，以及 `maximum_fire_resistance_add` / `maximum_cold_resistance_add` / `maximum_lightning_resistance_add`。原始抗性必须是有限数字；最大抗性加成必须是有限、非负数字，缺省为 `0.0`。布尔、字符串、空值、容器、NaN、无穷和负加成均不接受。小数百分点由来源相加后传入，例如 `0.01 + 0.02` 为提高 3 个百分点。

每个元素独立使用：

```text
maximum = min(0.83, 0.75 + bonus)
effective = clamp(raw, 0.0, maximum)
```

`raw=0.75, bonus=0.08` 的有效抗性仍为 75%；原始抗性至少达到 83% 才能用足 83% 最大抗性。单个元素的加成不会提高另外两个元素，也不改变物理或混沌。玩家和纯怪物 actor 共用规则，本文件不更改自然怪物资料。

`source_profile`、`incoming_source_hit` 的既有字段与字典顺序不变。最大抗性缺省或显式数字 `0` / `0.0` / `-0.0` 时，保持旧小循环、原 clamp 表达式和返回，不创建完整最大抗性字典；非零或非法加成进入权威 profile 验证。原 actor、原始抗性、armour 验证仍先执行。

`incoming_burn(raw_amount, fire_resistance, shield, health, actor="player", mana=0.0, ratio=0.0, max_fire_bonus=0.0)` 只尾追加一个可选参数。缺省或显式数字零保持旧计算和结果字节；非零使用同一权威 profile 的火抗。先完成全部旧参数校验及纯结算，旧失败直接返回，再验证新增加成，确保新参数不能掩盖旧伤害、actor、抗性、盾、生命、比例或魔力错误。合法非零会重新计算并纯结算，不更改输入或游戏状态。

旧 fire-only `defense_profile` / `incoming_hit` 的字段合法性和结构保持：它们仍不接受 `maximum_fire_resistance_add` 字段，包含显式零也保持旧拒绝结果。新增三元素资料和增量命中由 `resistance_profile` / `source_profile` 承担。仅旧 metadata 的描述文案补充默认 75%、安全 83% 与原始抗性独立；其余 metadata 字段与旧字节相同。

命中依次进行抗性与原护甲、命中专用感电、护盾、魔力先于生命、生命；burn 不加入护甲或感电。`DamageResolver` 原 `[-1, 0.9]` 兼容范围与 settlement 合同保持，外部已结算包不会再次套 83% 游戏资料安全顶。

## 冻结的独立 v58 基线

`v058-defense-rules.txt` 通过本地 `git show` 原字节保存自提交 `71f4863fda4b02d1afd17db4cfa958c85139491f:scripts/mechanics/defense_rules.gd`。

- 基线 SHA256：`7c84a7fedef8c7d978056d232889715d598264e447b05e0c9ce9d2705aee5476`
- 测试先校验该摘要，仅在内存移除全局 `class_name DefenseRules` 声明后独立编译基线，不由新代码生成旧期望
- 对照使用完整 `var_to_bytes`，包含值类型、字典插入顺序、嵌套明细、失败文字和字段集合；同时检查旧、新实现均不污染输入
- 基线原有 DamageResolver preload 路径保持。实际读取的 DamageResolver 与 v58 提交逐字节相同，SHA256 为 `37429d9754708d3bbbe9638f92bb8a038284326a4b9c422a70b7c2c4cfe3a1d5`

独立对照覆盖 source/fire-only profiles、两种 hit 入口、burn、原可选参数省略形式、有效/非法 actor、防御/伤害/资源/感电/魔力参数与错误优先级、显式三种数值零最大抗性、components 校验、settlement 与 mana settlement、命中感电 adapter。新规则覆盖 75%/83%、raw 不足/负值、加成饱和与最大有限数、三元素隔离、1 ULP 边界、非法 max、原参数失败优先、输入和输出隔离、命中和 burn 相同火抗与完整资源字节、五混伤、感电仅命中、盾→魔→生命与 overkill。

## 执行与实际结果

共享 import 完成后，只运行本新增纯规则单文件：

```sh
python3 docs/qa/v059-rules/run-focused.py
```

runner 不 import、不创建场景或状态，不读写存档；Linux XDG data/config/cache 位于唯一 `/tmp/godot-m1-v059-rules-*`，脚本再次检查隔离路径。60 秒是单进程故障保护，不运行 600 秒或历史全量套件。记录所有实际纯测试输入 SHA256、执行前后变化、退出码、耗时与引擎错误扫描。

2026-10-05 首轮且唯一一次执行：

- Godot 4.6.3，exit `0`，runner 记录 `0.689` 秒
- `17,893` 检查，`0` 失败，`7,224` 独立 v58 typed-byte 对照
- 无脚本/引擎错误，所有测试输入前后哈希保持，未自行 import
- 生产 Defense SHA256：`69ebfa9dc8a383591327953f4d6ab973a0059274c088db50df8fd11c7b2a398f`
- [机器证据](evidence-if1plsup.json)；[完整日志](rules-if1plsup.log.txt)

此证据仅证明共享纯规则及旧分支兼容；来源聚合、状态模型、存档迁移、实际场景消费者、UI 和发布使用各自独立证据。
