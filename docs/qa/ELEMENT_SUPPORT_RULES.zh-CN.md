# 物理与元素专注辅助：纯规则与定向验收

## 本批规则

`ElementSupportRules` 只生成辅助程序，不读取构筑、装备或存档，不修改技能配方，不消耗随机数。四个稳定 ID 如下：

| ID | 名称 | 总增 20% 的主命中分量 | 固定适配技能 |
| --- | --- | --- | --- |
| `physical_focus` | 物理专注辅助 | 物理 | 龙卷 |
| `fire_focus` | 火焰专注辅助 | 火焰 | 龙卷、陨星 |
| `cold_focus` | 冰霜专注辅助 | 冰霜 | 冰霜 |
| `lightning_focus` | 闪电专注辅助 | 闪电 | 飞弹、新星、连锁闪电 |

每枚辅助同时使主命中的其余全部伤害类型总降 20%，包括混沌；魔力消耗乘 1.15，冷却不变。适配取决于技能原生伤害类型白名单，装备后来加入点伤不会开放新槽位。已有技能即使通过装备同时含有全部五种分量，仍只允许表内对应辅助。

作用范围由 `SupportProgram.primary_modifier` 统一生成，必须同时满足对应技能 ID、命中、攻击或法术，以及投射物／范围／连锁标签。因此龙卷母箭和子箭、连锁的每次弹跳都适用；普攻、独立爆炸和另一技能的伤害包保持不变。伤害不转换类型，原始伤害包与组装来源记录保持不变。龙卷武器局部物理与外部附加物理先完成原有组装，再接受物理分量倍率。

允许两个不同且都适配该技能的专注辅助共存。例如龙卷装配物理与火焰专注后：物理、火焰分别乘 `1.2 × 0.8 = 0.96`；冰霜、闪电、混沌分别乘 `0.8 × 0.8 = 0.64`；魔力乘 `1.15² = 1.3225`。没有额外的元素家族互斥条件。编译按辅助 ID 排序，输入顺序不影响完整输出。

## 接口与边界

- `get_definition(id)`：返回深复制元数据；未知 ID 返回空字典
- `definition_error(value)`：校验恰好六项元数据 `name / description / skills / requires / operations / family`；`family` 固定为 `element`，`requires` 固定为空数组，技能名单与原生伤害类型一致
- `compile_program(skill_id, support_ids)`：返回共享五项信封 `error / modifiers / mana_multiplier / cooldown_multiplier / recipe_factors`
- 三种声明式操作为 `primary_component_more`、`other_components_more`、`mana_multiplier`；两个伤害操作声明相同目标 `damage_type`，倍率固定为本批的 `+0.20 / -0.20 / 1.15`
- 非有限数、布尔值冒充数值、错误类型、重复或未知操作、缺失／多余字段以及错误白名单均被拒绝；未知、重复、不适配或超过两个辅助的选择返回带原因的空效果信封
- 空选择对已知技能返回空效果信封；失败也不泄露部分修饰器、魔力倍率或配方改动；始终不生成 `recipe_factors`

四个新 ID 的版本 13 门槛与整批注册、编译器和界面接线由上层集成负责；本文件不改变这些模块。

## 定向测试

`tests/element_support_rules_test.gd` 使用真实 `CombatData`、`DamageBaseCompiler`、`WeaponLocalRules` 与 `DamageResolver`，不复刻伤害解析器。覆盖：

1. 四个 ID、名称、完整元数据、JSON 往返、操作重排与畸形元数据拒绝
2. 所有技能与辅助组合的白名单、空选择、未知／重复／超过两槽以及失败原子性
3. 真实装备式附加点伤覆盖五种分量后，适配名单仍固定
4. 100 基伤龙卷：物理专注为 104，火焰专注为 96，同时装配为 96；双辅助魔力为 1.3225
5. 武器局部物理 `(4 + 2) × 1.2 = 7.2`、攻击附加点伤、母箭与 70% 子箭，以及双辅助 `.96 / .64` 分量乘积
6. 六种伤害技能的所有主命中类型与连锁全部弹跳，既有 increased、额外伤害与抗性共同结算时，专注的 MORE 每个分量恰好匹配一次
7. 真实普攻、全部独立爆炸、其他技能包完全不受影响
8. 调用方数组、快照、原始包、元数据、输出修饰器与权威目录互不污染；全局和自定义 RNG 状态不变

Linux 定向运行方法，必须使用一次性的 XDG 根目录：

```sh
ELEMENT_QA_ROOT="$(mktemp -d /tmp/godot-v019-element-XXXXXX)"
export XDG_DATA_HOME="$ELEMENT_QA_ROOT/data"
export XDG_CONFIG_HOME="$ELEMENT_QA_ROOT/config"
export XDG_CACHE_HOME="$ELEMENT_QA_ROOT/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
godot4 --headless --path . --script res://tests/element_support_rules_test.gd 2>&1 | tee "$ELEMENT_QA_ROOT/test.log"
# 同时检查退出码和日志中的 SCRIPT ERROR / ERROR。
```

2026-10-03：Godot 4.6.3 定向测试 **695 项，0 失败**，无脚本或引擎错误。此结果仅覆盖本纯规则模块；最终整批套件、600 秒组合模拟、界面、发布与导出由上层统一验收。
