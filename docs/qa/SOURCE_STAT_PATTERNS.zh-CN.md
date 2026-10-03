# M3 源词缀纯解析前置

本文件描述 `scripts/passives/source_stat_patterns.gd` 的封闭式单行解析契约。它只从原始英文 stat 行提取一个候选 `{stat, value, mode}`；不分配天赋、不改角色统计、不执行伤害，也不连接任何消费者。

## 固定来源与标签

正例来自 `data/passive_source/data.json` 中的 `nodes.<node_id>.stats`。该文件由 `data/passive_source/source_manifest.json` 固定为 Path of Exile 1 `skilltree-export` 3.29.1、提交 `8bd138b32ea2631455cac5935bfab089f826094f`、SHA-256 `7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122`。测试按节点 ID 从原始数据中动态抽取英文行并核对预期标签、数值和 mode；节点 ID 是可复核出处。

下表逐条列出当前支持的完整行格式、运行时已有 stat key、mode 和源例行。所有匹配都区分大小写并完整锚定；`N` 只能是非负十进制数（整数或带小数点的数）。表中的源例位置也是测试样本出处。

| 完整格式 | stat | mode | 固定源节点 ID |
| --- | --- | --- | --- |
| `+N to maximum Life` | `max_health` | `flat` | `35448` |
| `+N to maximum Mana` | `max_mana` | `flat` | `35724` |
| `+N to maximum Energy Shield` | `max_shield` | `flat` | `27929` |
| `N% increased Damage` | `global_increased` | `increased` | `49254` |
| `N% increased Projectile Damage` | `projectile_increased` | `increased` | `62103` |
| `N% increased Spell Damage` | `spell_increased` | `increased` | `54694` |
| `N% increased Fire Damage` | `fire_increased` | `increased` | `14996` |
| `N% increased Cold Damage` | `cold_increased` | `increased` | `34977` |
| `N% increased Lightning Damage` | `lightning_increased` | `increased` | `35069` |
| `N% increased Elemental Damage` | `elemental_increased` | `increased` | `43193` |
| `N% increased Area Damage` | `area_increased` | `increased` | `59728` |
| `N% increased Attack Speed` | `attack_speed_increased` | `increased` | `63673` |
| `N% increased Movement Speed` | `move_speed_increased` | `increased` | `63417` |
| `N% increased Mana Regeneration Rate` | `mana_regen_increased` | `increased` | `44797` |
| `N% increased maximum Life` | `max_health` | `increased` | `48836` |
| `N% increased maximum Mana` | `max_mana` | `increased` | `29994` |
| `N% increased maximum Energy Shield` | `max_shield` | `increased` | `32992` |

这些 stat key 已出现在 `scripts/passive_data.gd` 的显示映射及 `scripts/mechanics/mechanic_registry.gd` 的玩家统计允许集合中。`flat` 保留原始点数；`increased` 统一把源百分数除以 100，例如 `15%` 输出 `0.15`。百分比最大容量仍使用现有容量 key，并以 `mode: increased` 保留它和固定点数的语义区别。

## 调用与拒绝边界

`parse_line(raw_line)` 接受原始 String，不裁剪、不改写输入。成功返回 `{supported: true, grants: [{stat, value, mode}], reason: ""}`，且目前每行恰有一个 grant。失败返回 `{supported: false, grants: [], reason: "..."}`，不会留下部分结果。

只有表中完整、无条件的单行格式会成功。下列内容一律拒绝：条件行、武器/技能/事件限定、while/recently、Damage over Time、Minion、组合/多行内容、未知 stat、未列出的同义词、额外前后缀、负值、空格变体及标点变体。多行、空行和可识别的负值有专门原因；其余不匹配项说明没有命中受支持的完整格式。解析器不以 substring、前缀或近似匹配接受任何行。

## 覆盖说明

这里测量的是这 17 种原文格式的**解析覆盖**。它不代表这些源词缀能被构筑、最终统计聚合、角色/怪物消费者或战斗执行；本任务没有接入这些系统。任何新增格式都需要单独给出原始源行、标签和 mode，并更新该纯解析契约及其负例。
