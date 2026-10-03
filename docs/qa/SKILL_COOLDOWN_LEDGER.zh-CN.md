# 技能冷却运行态账本

本专项基于 `codex/restructure-m1` 基线 `54298e02cb665223517042ec3810337150c55d96`。只新增 `scripts/combat/skill_cooldown_ledger.gd`、`tests/skill_cooldown_ledger_test.gd` 和本文；不接入 `main.gd`，不修改技能编译器、扣费、存档或其他模块。

## API 与身份规则

`SkillCooldownLedger` 是 `RefCounted` 纯运行态对象。它保存两张倒计时表：稳定技能组 ID → 组债务、主宝石 UID → 宝石债务。API 为：

| 方法 | 行为 |
| --- | --- |
| `remaining(group_id, main_uid) -> float` | 返回两项债务的最大值，表示当前这组技能与主宝石均需等待多久。ID 无效时返回 `0.0`，不创建键。 |
| `begin(group_id, main_uid, duration) -> bool` | 仅当两项债务都已到期且输入合法时，在两张表记入相同 duration；被锁定或输入无效时返回 `false` 且不改变账本。 |
| `advance(delta) -> bool` | 对所有债务递减 delta；到期项立即移除。非法 delta 返回 `false` 且不改变账本。 |
| `reset() -> void` | 清空两张运行态表。 |
| `snapshot() -> Dictionary` | 返回含 `group_debts` 和 `main_uid_debts` 的深副本；修改返回值不会改动账本。 |

组 ID 与 UID 完全遵守 `ItemLocationRules` 的稳定 ID 协议：必须是 1–128 字符的真正字符串，首尾 trim 不改变，UTF-8 字节中不能含小于 32 或等于 127 的控制字符。实现直接调用 `ItemLocationRules._stable_id`，避免另造一套边界。

duration 和 delta 只接受真正的整数或浮点数，且必须有限、非负；布尔值、字符串、NaN、正负无穷和负值均拒绝。零是有效输入：零 duration 的 `begin` 成功但不会留下债务，因此可以立即再次施放；零 delta 是无副作用的成功空操作。递减到零或以下时键会移除，所以剩余时间恰好被扣完的边界已可再次施放。有限的大 delta 会清除所有已有债务。

## 双重锁定语义

施放成功后，债务同时归属稳定 `group_id` 和当时主宝石的稳定 UID。之后查询取二者最大值：即使主宝石换到另一组，旧 UID 仍锁定；即使原组换入另一主宝石，组债务仍锁定。更改快捷键或显示行顺序不能改变组 ID。相同技能定义的两个主宝石实例使用不同 UID，不共享宝石债务；不同组配不同 UID 时互不影响。

每次 `begin` 需要组与 UID 两项都就绪，且会将同一个 duration 写入两者。对任一仍有债务的身份，重复施放、换组或换主宝石尝试都不能覆盖已有值或重新起算。账本不推断技能名称，不以数组下标、快捷键或背包位置作为冷却身份。

## 上层接入边界

该模块不执行施放、编译、扣费或随机逻辑。上层只能在一次真实施放已成功后调用 `begin`；编译失败、未通过冷却检查、资源不足或施放失败时不得调用。运行者死亡和开新局时应调用 `reset()`。账本与 `snapshot()` 都是瞬时运行态，不能写入存档。本专项未编辑 `main.gd`，因此这些调用点目前尚未接线；不能据此声称游戏施放流程已经应用此账本。

## 定向测试

脚本：`tests/skill_cooldown_ledger_test.gd`。覆盖组/UID 双重锁定、不同 UID 的同名技能独立、最大债务计算、重复 `begin`、移组/换主宝石、到期边界、大 delta、零时长/零 delta、重置、快照隔离、ItemLocationRules 稳定 ID 正反例、非法数值输入无副作用及全局 RNG 序列不变。

```sh
QA_ROOT="$(mktemp -d /tmp/godot-cooldown-ledger-XXXXXX)"
export XDG_DATA_HOME="$QA_ROOT/data"
export XDG_CONFIG_HOME="$QA_ROOT/config"
export XDG_CACHE_HOME="$QA_ROOT/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
godot --headless --path . --script res://tests/skill_cooldown_ledger_test.gd
```

2026-10-03 UTC，Godot `4.6.3.stable.official.7d41c59c4`：**168 项检查，0 失败，退出码 0**。XDG 数据、配置和缓存目录均隔离在 `/tmp/godot-cooldown-ledger-*`。此处仅运行新增账本的定向测试，不重复项目整体回归、施放集成、窗口验收或发布验证。

## 仓库说明检查

已检查基线工作树、可读父级以及 `/workspace/.agents`；未发现 `AGENTS.md` 或 `.agents/skills` 文件，工作区 `.agents` 目录为空。本模块接口参考了 `docs/RESTRUCTURE_PROTOCOL.zh-CN.md` 的冷却按稳定组身份规则，以及 `docs/qa/ITEM_LOCATIONS.zh-CN.md` / `ItemLocationRules` 的 ID 约束。
