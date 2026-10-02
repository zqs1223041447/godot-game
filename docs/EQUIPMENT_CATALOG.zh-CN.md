# v0.5 原创随机装备目录

## 运行时与参考数据的边界

运行时唯一目录为 `scripts/items/equipment_catalog.gd`。它包含 6 个原创底材、12 个原创词缀家族、每族 3 个原创阶级；不读取 `data/reference/poe_affixes/`，不导入 PoE 词缀名称、游戏文本、数值、装备底材或掉落权重，也不授予未实现的技能或机制。

语义审查依据为仓库中固定的 `data/reference/poe_affixes/design/godot_mapping.json` 和 `source_manifest.json`。参考导出版本标注为 PoE 1 `3.29.3.3`，导出仓库固定提交 `a77305840b4cc8555eeeea144eac3eeddeff134b`，解析器说明参考提交 `1c72e40a99aa8c8f70e9a3526155f455d5eedd43`。这只是语义研究证据，不是本游戏内容来源、平衡背书或源游戏完整实现声明。旧映射文档以 v0.3.0 为基准；v0.5 的支持程度必须由本游戏运行时与测试确认。

## 六种底材

| ID | 名称 | 槽位 / 格数 | 固有角色加值 |
|---|---|---|---|
| cinder_reed | 烬芦杖 | weapon / 1×3 | 通用基础伤害 +3、魔力恢复 +0.25/秒 |
| gale_spindle | 岚纺刃 | weapon / 1×3 | 通用基础伤害 +2、攻击速度 +0.08/秒 |
| woven_bastion | 绳垒衣 | armor / 2×3 | 最大生命 +12、最大护盾 +5 |
| tidebound_coat | 潮缄袍 | armor / 2×3 | 最大护盾 +10、护盾恢复 +0.6/秒 |
| wayglass_token | 途镜坠 | charm / 1×1 | 最大魔力 +6、魔力恢复 +0.3/秒 |
| pulse_seed | 脉籽符 | charm / 1×1 | 最大生命 +8、移动速度 +3 |

这里的 `damage` 是现有角色伤害标量加值，不是武器本地物理伤害，也没有新增本地武器伤害阶段。底材和词缀的 `max_shield` 都是本游戏角色全局护盾容量加值，不是 PoE 本地能量护盾防具数值。

## 十二族与完整整数范围

T1/T2/T3 是原创进阶编号，依次在物品等级 1/8/16 解锁；T3 最强。它们不是源游戏的官方阶级编号。表中端点均包含在内，步长统一为整数 1。

| 家族 / 显示名 | 类别 | 运行时属性 | T1 / T2 / T3 原始范围 | 可用槽位 |
|---|---|---|---|---|
| rootwell / 根泉 | 前缀 | max_health | 8–14 / 15–22 / 23–32 点 | armor、charm |
| deepwell / 深汲 | 前缀 | max_mana | 5–9 / 10–15 / 16–22 点 | weapon、armor、charm |
| lanternveil / 灯帷 | 前缀 | max_shield | 5–9 / 10–15 / 16–22 点 | armor、charm |
| runesong / 符歌 | 前缀 | spell_increased | 4–7 / 8–12 / 13–18 % | weapon、charm |
| prismedge / 折辉 | 前缀 | attack_elemental_increased | 4–7 / 8–12 / 13–18 % | weapon、charm |
| farweave / 远织 | 前缀 | projectile_increased | 4–7 / 8–12 / 13–18 % | weapon、charm |
| coalglow / 藏炭 | 后缀 | fire_increased | 5–8 / 9–14 / 15–20 % | weapon、armor、charm |
| rimeecho / 霜回 | 后缀 | cold_increased | 5–8 / 9–14 / 15–20 % | weapon、armor、charm |
| sparkthread / 引霆 | 后缀 | lightning_increased | 5–8 / 9–14 / 15–20 % | weapon、armor、charm |
| wellturn / 泉旋 | 后缀 | mana_regen_increased | 3–5 / 6–9 / 10–14 % | weapon、armor、charm |
| trailstep / 循迹 | 后缀 | move_speed_increased | 1–2 / 3–4 / 5–6 % | armor、charm |
| beatlink / 连拍 | 后缀 | attack_speed_increased | 2–3 / 4–6 / 7–9 % | weapon、charm |

所有百分比存储为整数百分点，聚合到运行时才除以 100；例如 `value: 18` → `0.18`，绝不写成 `attack_speed: 18` 或 `mana_regen: 18`。生命、魔力、护盾保持原始点数。

### 作用域契约

- `spell_increased` 只匹配 `spell` 伤害事件；装备在法杖上并不使其成为武器本地伤害
- `fire/cold/lightning_increased` 只匹配对应伤害分量；它们与同一分量适用的其他 `increased` 相加
- `attack_elemental_increased` 同时要求 `attack` 标签和火/冰/雷分量；不泛化为全局元素伤害，独立 `secondary` 爆炸不继承
- `projectile_increased` 是本游戏明确设计的投射物标签增伤，独立爆炸不继承；它不是把参考映射中的「弓技能伤害」直接泛化
- `mana_regen_increased`、`move_speed_increased`、`attack_speed_increased` 是各自角色恢复、移动、普通攻击频率的提高比率；旧的每秒/速度加值仍保留独立量纲，先聚合基础加值再使用对应比率
- 「连拍」显示为「普通攻击速度提高」，仅改变基础自动射击间隔，不缩短龙卷主动技能冷却。原创全局攻击速度词缀没有声称实现源游戏的本地武器攻速阶段，也不声称提高法术施放速度或恢复法术冷却
- 本目录只输出数据；上述作用域与最终数值必须由 v0.5 的角色聚合和伤害快照适配器执行

## 生成规则与平衡界限

物品等级只能是 1–30。普通为 0 词缀；魔法为 1–2 词缀、最多 1 前缀和 1 后缀；稀有为 4–6 词缀、最多 3 前缀和 3 后缀。所有底材均具有至少 3 个不同前缀家族和 3 个不同后缀家族，因此不会用不足数量的「稀有」物品掩盖词池不足。

未指定稀有度时，普通/魔法/稀有权重为 30/55/15。选定总词缀数后，在合法范围内选择前后缀数量，再从可用槽位、可用阶级的 `(家族, 阶级)` 条目中按权重抽取。各族 T1/T2/T3 权重分别为 100/60/30；较高物品等级仍可抽到较低阶级。选中后移除同族/同组所有阶级，禁止重复组。

初始平衡锚点为现有 9 件固定装备：余烬法杖 +8 伤害、疾风短刃 +0.5 攻速/秒和 +20 移速、生机轻甲 +50 生命、守护长袍 +30 护盾和 +3 回复/秒、湛蓝护符 +30 魔力和 +2 回复/秒、棱光长弓 +4 伤害和 40% 投射物提高（并额外母箭 +2）、风暴护符 +6 伤害和 +0.2 攻速/秒、归航披风 +15 护盾及返回机制、终焰护符 20% 全局和 30% 元素提高及爆炸机制。新普通底材明显较弱；单个 T3 加值也低于对应高价值固定属性，稀有装备以多条互补词缀获得成长空间而非直接复制强机制。原有返回、爆炸、额外母箭只由原装备提供；新目录 `effects` 永远为空。

这是一轮有界原创初始数值，不是已经通过完整游玩验证的最终掉落或经济平衡。

## 实例、API 与存档安全

唯一实例结构：

```json
{"id":"gear_000001","base_id":"cinder_reed","rarity":"magic","item_level":8,"affixes":[{"id":"runesong","tier":2,"value":10}]}
```

- `generate(rng, id, item_level, rarity = "") -> Dictionary`：仅使用传入 RNG；同种子同调用序列得到相同结果；无效参数返回 `{}`，且不消耗随机状态
- `validate_instance(value) -> bool`：精确检查根键与词缀键、规范 ID、底材、稀有度、等级、槽位资格、前后缀数量、家族/组唯一性、阶级解锁和对应掷值范围
- `get_stats(instance) -> Dictionary`：完整验证后才提供固有加值和词缀加值；无效实例不泄漏任何部分属性
- `definition(instance) -> Dictionary`：提供 `id/name/slot/size/description/stats/effects/rarity/item_level/affix_lines/base_name`，其中 `size` 是 `Vector2i`，`affix_lines` 是 `Array[String]`；非法实例返回 `{}`
- `serial_from_id(id) -> int`：规范形式为 `gear_%06d`，编号 1–999999999；非法形式返回 0

生成记录的等级、阶级、掷值为整数。Godot JSON 解码用浮点数表示 JSON 数字，因此验证也接受范围内、有限、严格无小数的浮点表示；布尔、字符串、NaN、Inf、微小非零小数一律拒绝。没有截断、四舍五入或容差掩盖。返回的运行时属性和展示结构为新字典/数组，不会修改目录或实例。

## 验证

隔离命令（XDG 目录必须可写）：

```sh
mkdir -p /tmp/equipment-catalog-test-home/{data,cache,config}
XDG_DATA_HOME=/tmp/equipment-catalog-test-home/data \
XDG_CACHE_HOME=/tmp/equipment-catalog-test-home/cache \
XDG_CONFIG_HOME=/tmp/equipment-catalog-test-home/config \
godot --headless --path . --script res://tests/equipment_catalog_test.gd
```

套件对等级 1、7、8、15、16、30 × 普通、魔法、稀有的每个组合各生成 5,000 个实例，另生成 5,000 个自动稀有度实例，共 95,000 个主样本；验证全部 36 个家族/阶级可达、精确边界、非法变异、无重复、JSON 往返、确定性、每个属性实际单位和全部 UI 元数据。该套件只验证目录本身；完整角色、伤害和存档集成由相应集成套件另外验证。
