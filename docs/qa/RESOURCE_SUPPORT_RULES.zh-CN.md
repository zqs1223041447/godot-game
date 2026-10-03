# 资源辅助纯规则验收

## 固定行为

本批新增 `efficiency`（节能辅助）与 `quickcast`（疾咏辅助），由 `ResourceSupportRules` 提供纯编译程序。

| 辅助 | 魔力消耗倍率 | 冷却时间倍率 |
| --- | ---: | ---: |
| 节能辅助 | 0.80 | 1.15 |
| 疾咏辅助 | 1.40 | 0.80 |
| 同时装配 | 1.12 | 0.92 |

适配技能固定为龙卷、飞弹、冰霜、新星、冲刺、结界、陨星和闪电，对应 `tornado`、`bolt`、`frost`、`nova`、`dash`、`ward`、`meteor`、`chain`。未来新增技能不会自动获得兼容性。普攻与未知技能被拒绝，空辅助列表也不能绕过技能校验。

每份定义恰有 `name`、`description`、`skills`、`requires`、`operations`、`family` 六个字段；`family` 为 `resource`，`requires` 为空。操作仅允许各一次的 `mana_multiplier` 与 `cooldown_multiplier`，值必须为有限数字，范围为大于零且不超过 10。布尔值不按数字接收。两个倍率必须体现相反取舍，拒绝双向获益、双向惩罚及缺少取舍的定义。

## 输出与边界

`compile_program(skill_id, support_ids)` 始终返回 `SupportProgram` 的五字段结构：`error`、`modifiers`、`mana_multiplier`、`cooldown_multiplier`、`recipe_factors`。失败时保留非空错误说明，两个倍率回到 1.0。成功与失败的 `modifiers` 恒为空数组，`recipe_factors` 恒为空字典。

因此本提供器不产生命中伤害、护盾回复、无敌时长、冲刺距离、投射物数量/速度/穿透等效果。它不修改技能原始数据，不读取或写入构筑/存档，也不使用随机数。返回的定义及程序均与常量、调用者列表、其他调用结果分离。

选择最多两个辅助，拒绝重复、未知、非字符串 ID 和非数组输入。先完整验证，再对输入副本按 ID 排序并计算，避免部分结果或改变调用者顺序。两个辅助的顺序不影响结果。

## 定向验证

脚本：`tests/resource_support_rules_test.gd`。

覆盖八技能的空装、各单辅助、双辅助与逆序；验证精确程序结构、倍率及实际基础消耗/冷却乘积。包含输入类型、重复、超槽、未知/未来技能、元数据字段/分类/白名单损坏、未授权效果、重复操作、倍率零值/负值/越界/NaN/Infinity/布尔值，以及返回值深层分离、无 RNG 消耗和原始技能数据不变。

Linux 定向运行（Godot 4.6.3）：

```sh
RESOURCE_QA_ROOT="$(mktemp -d /tmp/godot-v019-resource-XXXXXX)"
export XDG_DATA_HOME="$RESOURCE_QA_ROOT/data"
export XDG_CONFIG_HOME="$RESOURCE_QA_ROOT/config"
export XDG_CACHE_HOME="$RESOURCE_QA_ROOT/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
godot --headless --path . --script res://tests/resource_support_rules_test.gd
```

2026-10-03 定向结果：Godot `4.6.3.stable.official.7d41c59c4`，2,443 项检查、0 失败，退出码 0，日志无 `SCRIPT ERROR:` 或 `ERROR:`。隔离路径使用 `/tmp/godot-v019-resource-*`。

本文件只记录资源提供器的独立契约，不替代本批统一的注册表、编译器、真实施放、存档版本 13、界面及完整发布验收。
