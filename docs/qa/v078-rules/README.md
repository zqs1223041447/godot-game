# v078 纯伤害规则验证

2026-10-06，Godot 4.6.3，Linux headless。固定兼容基线为 `07922581e2924dbb6fbadd1fb51242ae87a16293`。最终生产规则与 `604c76b` 相同。

## 结果

- `tests/elemental_conversion_penetration_rules_test.gd`：**2032 checks，0 failures**，退出码 0，无脚本错误
- 最终日志：`elemental_conversion_penetration_rules_test.log.txt`
- 首次日志：`elemental_conversion_penetration_rules_test.initial-fixture-failure.log.txt`，1989 checks / 2 failures，完整保留
- `git diff --check` 通过
- 复用主任务已经完成的首次项目导入；本验证没有再次导入或运行历史全量套件

两个首次失败都来自同一个测试夹具：Godot 将源码中的 `5e-324` 字面量解析成位模式 0，因此测试实际传入合法的零余量。独立诊断确认，`PackedByteArray.encode_u64(0, 1)` 后 `decode_double(0)` 可构造位模式 1 的真实最小正数，它不等于零。测试改为通过位表示构造；生产代码未因该失败修改。修正后的最小正数也进入已有“全部转换子集”循环，新增 43 项有效非零来源检查，故最终总数为 2032。最终单文件执行约 0.208 秒。

## 覆盖

1. 直接使用 `git show` 读取固定基线的三个旧生产脚本，在内存中编译；去除全局类名、将旧模块间的 preload 引用绑定到同批旧脚本。保留旧公式与逻辑，不以当前脚本冒充历史基线。对旧单火、零转换、非法火比例、旧包非法字段、错误先后次序和不同暴击值比较 `var_to_bytes` 完整结果
2. 全部 8 种转换来源子集与 9 种来源基数，包括真实最小正数、极小值、正常小数与极大值；固定 fire/cold/lightning 顺序；二转各 40%，三转各 `0.4 / (0.4 + 0.4 + 0.4)`；三转余量为显式浮点零，无物理组件或回执
3. 原生与转换部分分离、原生在先；`[physical, target]` lineage；全域、物理、元素、标签、技能条件按条目只应用一次；increased 相加、独立 MORE 相乘、同 ID 条目不合并；physical_focus 对转换部分为 0.96，fire_focus 对转冷/电仅应用一次 0.8
4. v2 描述符精确字段和地图键、有限数值、只允许 40% 来源、禁止重复转换、DOT、溢出与伪造；请求比例、有效比例、转换基数和来源基数的单 ULP 篡改全部拒绝。总量恰好守恒也不能授权不同分配
5. 冰/电穿透只允许 6%，零或缺失省略；仅最终类型有正基础伤害时附加；纯火与独立火爆炸保留原包字节；转换前谱系不让其他类型获取穿透；非法穿透图、非有限值、DOT 和错误元素均拒绝
6. 抗性先限制到 [-1, 0.9]，再减 0.06，最后只应用 -1 下限。100 点冰伤在 90%、0%、-100% 抗性下分别结算为 16、106、200；到达下限时仍保留本次配置 penetration=0.06 与 effective_resistance=-1，最终 resistance=-1
7. `Damage.resolve → Defense.apply_armour → Defense.settle_with_mana` 真实公共链；每最终类型仅一条回执；原始 before_defense 不被穿透提高；护甲仅作用剩余物理；护盾、魔力、生命按原顺序结算；负抗性保留实际增伤，没有二次抵抗结算
8. 原参数、原组装记录、snapshot、modifier、目标防御保持字节不变；各级结果深拷贝；重复结算确定性；全过程不额外消耗全局 RNG

## 浮点守恒边界

新描述符的比例、来源、余量、每种转换基数首先以构造时的同一表达式严格重算比较，不使用近似容差。此后独立总量守恒检查允许最多四个来源 ULP，以涵盖最多四个非负分量的乘法和顺序相加舍入。ULP 从来源浮点数的 IEEE 指数计算；这个边界只用于已经严格匹配的派生数值，不允许伪造比率或分量利用近似容差通过。

## 复现

```sh
mkdir -p /tmp/godot-m1-v078-rules/{data,config,cache}
XDG_DATA_HOME=/tmp/godot-m1-v078-rules/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v078-rules/config \
XDG_CACHE_HOME=/tmp/godot-m1-v078-rules/cache \
/usr/local/bin/godot --headless --path . \
  --script res://tests/elemental_conversion_penetration_rules_test.gd
```

此脚本需要可读取包含固定基线对象的 Git checkout。它只读 Git，不写索引、分支或提交。此证据是纯规则与公共防御接口验证，不替代技能编译、来源树、存档、真实 Main 场景或原生平台图形验证。

## 已验证源码 SHA-256

```text
77d5729f7c4904c2ae6ed2b0c79abb5ae9cf4627357cc4e9e55e52ea14de0326  scripts/combat/physical_fire_conversion_rules.gd
720dc69a7446334e8aec3ac15bdf7c1717fa7b96db5657e0c9622513121a4e23  scripts/combat/damage_resolver.gd
7c12ba22cc623c87a805a903a957e5841b4f8c0b26cb3b0ca8dae60cf8c9de8d  scripts/combat/damage_base_compiler.gd
6b0733c563548a9034cd5169b1736287cbffc4b40a14cdf71f37a729c377fc88  scripts/combat/hit_penetration_rules.gd
2f6cf5861aa07bb82abb862f61bd0d534506b2e8041ea9aadb439260ca7c78e7  tests/elemental_conversion_penetration_rules_test.gd
```
