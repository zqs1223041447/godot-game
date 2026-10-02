# 锁点圆形蓄力攻击：独立运行时与接入契约

本模块基于已推送的 v0.13 源码 `a4a306a6d8c14320fce383dccf6ad7ca40836757`。它是可单独测试的纯数据状态机，**尚未接入游戏**：没有新增自然遭遇、怪物技能分配、预警视觉、图鉴条目或已发布内容。`main.gd`、`MonsterCatalog`、存档、既有 UI、视觉和图鉴生成器均不在本次修改范围内。

## 单一数据来源

`scripts/monsters/telegraph_profiles.gd` 的 `DEFAULTS`、`LIMITS` 与 `MAX_ACTIVE` 同时供运行时和 `metadata()` 使用。这是本游戏原创平衡，`origin = original`、`source_refs = []`，不是外部游戏规则复刻。配置 ID 为 `locked_circle`，schema 为 1，平衡版本为 `original-telegraphed-area-v1`。

| 字段 | 默认值 | 合法范围 |
| --- | ---: | ---: |
| `windup_seconds` | 0.7 秒 | 0.001–60 秒 |
| `recovery_seconds` | 1.2 秒 | 0.001–60 秒 |
| `radius` | 90 世界单位 | 0.001–4096 |
| `damage_multiplier` | 1.4 | 0–100 |

`resolve(overrides)` 返回 `{ok, reason, profile}`；未知字段、非数值、布尔值、NaN、无穷和超出范围的值均原子拒绝。`metadata(overrides)` 返回实际生效的 `profile`、默认值、安全范围、容量、事件/状态语义和 `standalone_not_integrated` 状态。参数、metadata 及事件中的 profile 均为隔离副本。没有怪物模板到 profile 的隐式映射；是否为某个实例启用由后续接入者明确决定。

## 状态和时间

`start` → `windup` → 发出一次 `circle_attack` → `recovery` → 删除状态。

- 开始时锁定目标**世界坐标**、配置以及 `MonsterCatalog.contact_components(enemy)` 的接触分量；每个分量乘配置倍率。之后来源移动、玩家移动、来源伤害或调用方配置改变都不会追踪/改写本次攻击。
- 默认在开始后的 0.7 秒产生一个圆形攻击事件，并恢复 1.2 秒。恢复阶段占用容量且拒绝同来源重启。总计 1.9 秒后归还槽位。
- 默认配置下，`advance(1.9, sources)` 或任意更大的有限步长仍只发出一次事件，并完成恢复。覆盖配置时跨过 `windup_seconds + recovery_seconds` 的步长也遵守这一规则；不会自动排队或补发下一次攻击。再次发动必须显式 `start`。
- 时钟保留跨阶段余量。数值比较使用 `1e-9` 秒容差，以消除拆分累积舍入误差；最多约 1 纳秒内可视为到达边界。
- 0、负数、NaN、无穷 delta 不推进活体时钟，仍执行来源存活/出生保护取消。暂停时不调用 `advance` 即可暂停计时。
- 同次返回按当前步内的命中截止时间排序，完全相同的截止时间按 `source_id` 升序排列。事件 `attack_age` 是从该次开始起的命中时间（默认 0.7），不是全局时间或当前帧偏移。

单次攻击的拆分等价性以相同开始快照和相同来源存活条件为前提。来源在大步内部何时死亡、玩家在步内部怎样移动，不在纯调度器输入中；调用方须在这些外部语义边界拆步。游戏已有 60 Hz 固定 tick 可提供采样点。

## API 与输入边界

```gdscript
const Telegraphs = preload("res://scripts/combat/telegraphed_area_runtime.gd")
var telegraphs = Telegraphs.new()

# enemy 为真实怪物字典；spawn 必须已由宿主管理为 0。
var admission: Dictionary = telegraphs.start(enemy, player_pos, {"radius": 90.0})
var events: Array[Dictionary] = telegraphs.advance(delta, enemies)
var copied_state: Dictionary = telegraphs.state_for(int(enemy.id))
telegraphs.cancel(int(enemy.id))
telegraphs.reset()
```

| 方法 | 契约 |
| --- | --- |
| `start(enemy, target_center, overrides = {})` | 成功返回 `{ok: true, reason: "", attack: copied_state}`；失败只返回 `{ok: false, reason}`，不部分入场、不消耗攻击编号、不挤掉现有攻击。 |
| `advance(delta, live_enemies)` | 返回深拷贝事件数组，不写调用方对象、生命、护盾、出生计时或其他计时器；不调用结算、不绘图、不发信号、不使用 RNG。 |
| `state_for(source_id)` | 返回隔离状态副本；没有状态时返回 `{}`。可供未来预警渲染器读取 `phase`、`elapsed`、`center`、`profile`。 |
| `active_count()` | 返回蓄力和恢复中状态的总数，至多 100。 |
| `cancel(source_id)` | 删除该来源状态；首次成功为 `true`，已不存在为 `false`，不会产生攻击事件。 |
| `reset()` | 清空全部状态；攻击编号不回卷。宿主同时丢弃自己保存的旧事件。 |

`enemy` 必须包含正整数 `id`、有限正数 `health`、恰为 0 的有限 `spawn`、有限非负 `damage`。可选 `death_processed` 必须为布尔且不能为 `true`。`contact_weights` 缺省为纯物理；提供时须通过既有 `DefenseRules.validate_components`，且权重总和约等于 1。支持伤害类型沿用 `DamageResolver.TYPES`，最多五项。倍率计算后再次校验数值及分量总和，防止溢出。

`advance` 的 `live_enemies` 是**完整、ID 唯一、最多 100 项的帧起始来源快照**；也可以包含死亡或出生保护中的怪物，它们将取消自己已有的攻击。活体快照只读取固定几个存活字段，不复制整个怪物或嵌套装备/机制数据。

- 缺失来源、`health <= 0`、`death_processed = true`、`spawn > 0`，以及非法存活字段，均先取消该来源，不留终止爆炸。
- 非数组、超过 100 项、非字典项、非法 ID 或重复 ID 使整个输入身份集合不可用，执行 `reset()` 并返回空数组。不会截断输入后猜测谁仍存活。调用者须把这类情况视为接入错误。
- 100 个状态、100 个事件/调用、五种分量、四个配置字段构成存储边界；没有事件历史、死亡墓碑、重试队列、计时器节点或按 delta 次数循环。每次工作量取决于至多 100 个来源及事件排序，不随大步长增长。
- ID 表示来源生命期；同 ID 的新字典是同一来源的下一帧快照。必须保持现有 `MonsterRuntime.next_id` 在重置后也不复用的规则。若接入者复用 ID，须先 `cancel`，不能依赖字典对象地址识别重生。

返回事件结构：

```gdscript
{
    "type": "circle_attack", "shape": "circle",
    "source_id": 1, "attack_id": 1,
    "center": Vector2(200, 100), "radius": 90.0, "attack_age": 0.7,
    "profile_id": "locked_circle", "schema_version": 1,
    "balance_version": "original-telegraphed-area-v1",
    "profile": {"windup_seconds": 0.7, "recovery_seconds": 1.2,
                "radius": 90.0, "damage_multiplier": 1.4},
    "packet": {"base": {"physical": 14.0, "fire": 14.0},
               "tags": ["attack", "area", "hit"], "skill_id": "locked_circle"}
}
```

示例对应总接触基伤 20、物理/火焰各半。`packet.base` 是防御前分量；事件不是伤血成功记录。运行时只保证每次开始返回至多一个事件；消费方必须立即且仅消费一次，不能跨重开保留或重放。已经返回给调用者的副本不能由后续 `cancel/reset` 追回。

## main 的预留接点（本次未改 main）

1. 在现有 `MonsterLifecycle` 实例旁创建独立 `TelegraphedAreaRuntime`。怪物成功入场只建立来源身份；出生保护尚未结束时不调用 `start`。
2. 在 `_tick` / `_update_enemies` 中，先以尚未递减 `enemy.spawn` 的完整来源集合推进**已存在**的预警攻击。当前 `_update_enemies` 会先执行 `enemy.spawn -= delta`；接点必须位于这个变化之前，防止同一帧新出生的来源被误认为可攻击。
3. 消费上一步事件后，再更新怪物的普通状态/出生计时。对明确启用该技能且无在途状态、仍存活且不在出生保护中的实例，在当前 tick 结束时按接入策略 `start(enemy, player_pos)`。新攻击不能回用这帧已经消耗的 delta，否则实际预警不足 0.7 秒。接入者须明确它与普通接触攻击的互斥/调度关系；本模块不暗中增加两次伤害。
4. 范围命中用**结算采样时玩家位置**与事件锁定圆心比较。沿用既有圆形碰撞约定，将玩家半径加到攻击半径，边界包含在内。之后调用现有玩家受击入口：

```gdscript
# 放在现有 main 上下文中的未来适配示例；本次没有应用此片段。
for event: Dictionary in events:
    if not alive:
        telegraphs.reset()
        break
    # 若 advance 与消费之间可能发生来源死亡/出生/移除，先重新验证该来源。
    var reach: float = float(event.radius) + PLAYER_RADIUS
    if Vector2(event.center).distance_squared_to(player_pos) <= reach * reach:
        hit_player_components(event.packet.base, int(event.source_id))
```

`hit_player_components` 负责现有玩家无敌帧和 `DefenseRules.incoming_hit`，后者调用 `DamageResolver` 后按抗性 → 护盾 → 生命结算。不要先减抗再把结果传入 `incoming_hit`，不要把 `event.packet.base` 当最终伤害直接扣血。若独立适配器选择 `DamageResolver.resolve`，就用 `DefenseRules.settle_resolved`，两条路径二选一。多个同帧圆形事件仍受现有 0.32 秒无敌逻辑影响。

5. 在 `_apply_enemy_settlement` 确认死亡、来源移除时 `cancel(enemy.id)`；即使漏掉该显式接点，下一次完整快照也会取消。`restart_run`、`start_monster_demo`、`start_density_demo` 以及玩家死亡路径均 `reset()`，并丢弃已取出但尚未消费的事件。恢复阶段也遵守这些取消规则。
6. 未来预警视觉可以读 `state_for` 和同源 `profile`，不把视觉生命周期反过来当伤害时钟。本次不创建绘制/粒子/提示接口，也不改 MonsterCatalog、UI 或图鉴导出。

## 验证

在项目根目录执行独立测试：

```sh
godot --headless --path . --script res://tests/telegraphed_area_test.gd
```

受限云环境可将 `XDG_DATA_HOME`、`XDG_CONFIG_HOME`、`XDG_CACHE_HOME` 指向临时可写目录。该测试是新增入口，按本任务文件隔离要求**没有写入 `tools/validate.sh`**，须单独运行。

Godot 4.6.3 下独立测试覆盖默认/可调配置、metadata 副本、精确阶段边界、190 次小步与大步等价、跨阶段余量、同帧事件顺序、死亡/重置/显式取消/重新出生、真实 catalog 出生保护、畸形/非有限/溢出输入、输入不变、事件深拷贝、RNG 不变、既有伤害/防御路径、100 个同时攻击的 100 轮循环（10,000 次攻击），以及 100 个独立 runtime 实例。边界复核还覆盖配置时长上下界与非对称恢复、错开发动后的剩余时间排序、失败入场不改变在途快照或消耗编号、混合存活快照的局部取消，以及恢复中的显式取消/重置。

这证明独立调度及分量适配契约。游戏场景中的预警可读性、实际选怪发动策略、玩家移动躲避与碰撞采样、主循环接点、无敌帧联动和视觉验收，仍需接入后另测；本次不将独立测试结果称为游戏功能已上线。
