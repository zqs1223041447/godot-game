# v0.42 构筑词缀纯数据验证

`BuildAffixProfile` 是独立的四族词缀数据，提供 `AFFIXES`、有序 `AFFIX_IDS`、`ALLOWED_BASE_IDS` 和 `MIN_SAVE_VERSION = 27`，以及返回分离副本的三个访问函数。数据不依赖装备目录、存档、场景、图标或随机数。

本表为**初始可调原型，不是平衡性证明**。本次数据验证不证明实战收益、掉落频率或养成节奏合理。

| ID | 名称 / 类型 | 消费属性 | 存储单位 | T1 | T2 | T3 |
| --- | --- | --- | --- | --- | --- | --- |
| `attack_life_leech` | 血汲 / 前缀 | `attack_life_leech` | `basis_points` | 20–30 | 31–45 | 46–60 |
| `attack_mana_leech` | 灵汲 / 前缀 | `attack_mana_leech` | `basis_points` | 10–15 | 16–25 | 26–35 |
| `global_critical_chance` | 锐察 / 后缀 | `crit_chance_increased` | `percent` | 15–20 | 21–30 | 31–40 |
| `global_critical_multiplier` | 重创 / 后缀 | `crit_multiplier_add` | `percent` | 5–7 | 8–11 | 12–15 |

各族 T1/T2/T3 的物品等级门槛固定为 1/8/16，权重固定为 100/60/30。各族排斥组等于自身稳定 ID；同族全部阶级继承同一个组，四族之间互不冲突。完整组合占两个前缀和两个后缀。

四族都明确允许 `charm`、`ring`、`gloves`，并逐族记录完全相同的底材白名单，顺序为：

1. `wayglass_token`
2. `pulse_seed`
3. `nine_slot_etched_ring`
4. `nine_slot_threaded_gloves`

此数据不增加底材或图标。白名单必须与槽位同时用于消费侧资格检查，不能把槽位视为允许未来所有同类底材的授权。

`basis_points` 的整数除以 10000 后得到属性值：生命偷取总范围为 0.20%–0.60%，魔力偷取为 0.10%–0.35%。`percent` 沿用整数除以 100 的现有含义：暴击几率提高为 15%–40%，倍率加成为 0.05–0.15。倍率族另有 `display_unit = "percentage_points"`，供界面显示为 +5 至 +15 个百分点，不能将其描述为相对倍率提高。

## 验证结果与边界

Godot `4.6.3.stable.official.7d41c59c4`，Linux headless，独立 `/tmp/godot-v042-profile.*` XDG data/config/cache；执行 `tests/build_affix_profile_test.gd`，**180 项检查，0 失败，进程退出码 0**。原始输出见 [profile-test.log.txt](profile-test.log.txt)。不需要启动编辑器或导入场景资源。

检查覆盖精确 ID 与顺序、版本门槛、名称/标签/消费属性/单位、逐族白名单、全部阶级整数边界/门槛/权重、四族独立排斥组，以及重复添加/删除/清空/深层修改返回数据后的隔离性。多次读取与跨族数组也保持独立。

可复现命令：

```sh
PROFILE_QA_DIR=$(mktemp -d /tmp/godot-v042-profile.XXXXXX)
mkdir -p "$PROFILE_QA_DIR/data" "$PROFILE_QA_DIR/config" "$PROFILE_QA_DIR/cache/fontconfig"
XDG_DATA_HOME="$PROFILE_QA_DIR/data" \
XDG_CONFIG_HOME="$PROFILE_QA_DIR/config" \
XDG_CACHE_HOME="$PROFILE_QA_DIR/cache" \
timeout 45s godot --headless --path . --script res://tests/build_affix_profile_test.gd
```

这是纯数据契约验证。实际稀有物品合法性、27 版新旧生成池、换算、展示、存档迁移与实战消费由集成测试验证；本报告不将它们计为已通过。本次未执行 600 秒模拟或历史全量测试。
