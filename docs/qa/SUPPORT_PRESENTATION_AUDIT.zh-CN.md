# 16 项辅助说明静态审计

基线：`2ac7c8bb71fb0d1fea0a23c7125b1b438f0c3676`。本审计只新增检查器、最小变异夹具和本文档；不重建离线 catalog，不改游戏数据、注册器、图鉴或已有测试。

## 数据来源与界面文字

- 16 项定义来自六个运行时提供器：`support_catalog.gd`、`projectile_support_rules.gd`、`area_support_rules.gd`、`resource_support_rules.gd`、`element_support_rules.gd`、`delivery_support_rules.gd`。`SupportRegistry` 汇总这些定义，并按 `saved_links_reason` 的分支应用存档版本门槛。
- 技能资格由提供器显式 `skills` 列表，或旧式定义的 `requires` 能力与 `GameData.SKILLS.capabilities` 决定。离线 `docs/reference/catalog.json` 保存 `supports`、每个技能的 `compatible_supports`，以及从编译器导出的 `support_program_examples`。
- 游戏面板把定义的 `description` 显示为 `SupportDescription_<id>` 标签；“添加辅助”按钮的 `tooltip_text` 是当前兼容原因或操作提示，没有另一份逐辅助 tooltip 文本。本检查将实际显示的 description 当作辅助说明文字核对，并确认面板及离线 HTML 构建器仍读取该字段。

## 自动检查范围

运行时静态元数据与已有 JSON catalog 的 16 个 ID、字段和值逐项相等；同时从运行时技能能力推导资格集合，并与 catalog 的技能反向链接和编译示例技能集合比较。检查器解析说明文字中稳定、带数字的字段：魔力倍率、显式冷却倍率/不变、主命中/投射物命中/范围命中的伤害方向与百分比、投射速度、投射物数、贯穿数、连锁目标数与续跳距离、面积倍率和半径倍率。面积只用几何关系 `半径倍率 = √面积倍率` 校对，不推导或重写伤害公式。

检查器还比较 catalog 已有的 42 行单辅助编译示例：魔力与冷却倍率，以及投射物数、贯穿、速度、减速时长、范围半径/面积倍率和连锁参数。伤害示例数值来自既有 catalog，本检查不复算伤害。

版本门槛从运行时代码的 `SupportRegistry` 路由、各提供器和 `AreaSupportRules.SAVE_VERSIONS` 解析，并确认每个门槛不高于 catalog 的全局 `save_version`。catalog 当前只有全局版本，没有逐辅助的最低存档版本；说明文字也没有版本门槛，所以这两处之间无法逐项自动比对。检查器将这一覆盖缺口列入人工复核。

检查器只解析上述明确模式，不证明自然语言整体语义正确。兼容对象省略、独立爆炸/普攻排除条件、规则边界等仍需人工阅读；任何无法机读的项目都会出现在命令输出的复核清单里。

## 运行

```sh
python tools/check_support_presentation.py
python -m unittest discover -s tests -p 'test_support_presentation.py' -v
```

六个内嵌的最小变异用例分别验证：source 常量引用解析、JSON description 不一致、文字魔力倍率错误、面积/半径换算错误、伤害作用域错误，以及门槛高于 catalog 存档版本时失败。夹具只在内存中改动，不写工作树。

## 基线结果

在未修改的运行时源与 `catalog.json` 上，静态检查找到 16/16 个定义、16/16 个 catalog 条目及 42 行编译示例；source 与 catalog 元数据一致，自动检查 **0 错误**。门槛分布为：v1 两项、v10 一项、v12 一项、v13 十二项。六个变异用例全部通过，说明对应的不一致会被捕获。

基线人工复核项：`efficiency`、`focus`、`quickcast`、`volley` 的说明未枚举全部适用技能；`focus`、`volley`、`pierce`、`swift_projectiles`、`heavy_projectiles`、`lingering_chill`、`chain_extension`、`chain_reach` 未明确写出冷却是否不变；14 项带历史门槛的辅助在 JSON 中没有逐 ID 门槛字段。完整清单由检查器输出。
