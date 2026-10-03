# 有限遭遇挑战：独立模块与接入契约

> 当前状态：v0.17已接入暂停选择与真实根/子怪入场，规则和新验收见[本轮挑战接入](ENCOUNTER_INTEGRATION.zh-CN.md)。下文保留独立组件的历史交付边界；当时的“未接入”不是当前版本状态。

本模块以 v0.13 远端源码 `a4a306a6d8c14320fce383dccf6ad7ca40836757` 为基线。它提供目录、纯编译器和独立验收，**尚未接入常规游戏、UI、图鉴、存档或奖励流程**。测试内临时将编译后的怪物放入现有场景，不等于游戏已开放挑战选择。

本次仅新增：

- `scripts/encounters/encounter_catalog.gd`
- `scripts/encounters/encounter_compiler.gd`
- `tests/encounter_compiler_test.gd`
- `docs/ENCOUNTER_MODIFIERS.zh-CN.md`

## 内容及唯一数值来源

| ID | 显示名 | 应用到标准怪物的最终字段 |
| --- | --- | --- |
| `enemy_max_health_120` | 强健 | `max_health ×1.20`，同时按比例调整 `health` |
| `enemy_move_speed_110` | 迅行 | `speed ×1.10` |

`EncounterCatalog.MODIFIERS` 是唯一数值定义；名称、描述、风险参数与编译倍率都由它生成。不是 PoE 抄录参数，不修改共享天赋包。先由 `MonsterCatalog` 计算物种、波次、稀有度及机制的标准怪物，再对最终生命或移动速度应用一次挑战倍率。

允许 0、1、2 条不同挑战。拒绝重复 ID、未知 ID、第三条、非数组及非字符串项；不做别名猜测、数值强制转换或部分成功。输入顺序不影响结果，编译按 ID 排序。

`EncounterCatalog.metadata()` 和 `get_definition(id)` 返回独立副本，供未来预览、UI 或图鉴接入。现有 UI 和图鉴生成器没有修改。metadata 包含：

- 目录路径、schema、定义 revision、政策 version、`original_game_balance` 来源，以及实际 `MonsterCatalog.SCHEMA_VERSION`。
- 两条定义的稳定 `encounter:<id>` 来源标识、最终字段、倍率和由倍率推导的风险参数。`assessment = parameter_only` 表示尚非实战难度评分；生命与移速影响不合并成伪精确的总难度分数。
- 资源比例政策。
- 可选奖励预算占位：`status = metadata_only`、`enabled = false`、`proposed_bonus_fraction = null`。`null` 意味着没有提出或平衡过任何额外奖励预算。`grants_rewards` 和 `creates_map_items` 均为 `false`。

奖励 metadata 没有执行器，不参与经验、装备、掉落率、奖励资格或 RNG。不得通过修改冻结配置启用奖励；任何未来预算与奖励实现需另行设计和验收。

## API

```gdscript
const Encounters = preload("res://scripts/encounters/encounter_compiler.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")

var compiled: Dictionary = Encounters.compile([
    "enemy_max_health_120", "enemy_move_speed_110",
])
if not compiled.ok:
    push_error(compiled.error)
    return

# 示例来源。真实主集成应保留 MonsterRuntime.create_root / drain 的身份与谱系管理。
var canonical: Dictionary = Monsters.make_enemy(1, "crawler", 3, Vector2(300, 300))
var applied: Dictionary = Encounters.apply_to_enemy(canonical, compiled.profile)
if not applied.ok:
    push_error(applied.error)
    return
var enemy: Dictionary = applied.enemy
```

`compile(ids)` 成功返回 `{ok: true, error: "", profile: ...}`；失败只返回 `{ok: false, error: ...}`，没有可误用的半成品 profile。`profile` 内全部字典和数组递归只读：ID、源版本、完整定义快照、倍率、风险参数、资源政策及奖励预算均冻结。外层结果信封不是配置本身，不能将 `compiled` 直接传作 profile。

`profile_error(profile)` 重新由当前目录构造预期快照并比较全部内容，拒绝未知字段、过期版本、伪造来源、改写倍率、政策或奖励 metadata。精确的深复制配置也可使用；不强制调用方保留同一个字典对象。当前只支持本版本配置，不承诺跨版本存档兼容。

`apply_to_enemy(canonical_enemy, profile)` 成功返回 `{ok: true, error: "", enemy: ...}`。`enemy` 是可继续被战斗逻辑修改的独立深副本，额外持有只读 `encounter_source`。标记包含冻结的完整 profile、标准怪物身份和机制版本、应用前的生命/护盾/速度值。

输入来自当前内置 `MonsterCatalog` 或 `MonsterRuntime`。编译器检查模板、物种/首领稀有度匹配、来源字段、谱系标记及资源边界，不会代替工厂生成怪物，也不会重算其天赋、身份或奖励资格。它不持有原始生成 context，所以橙色首领的 `level_boss` / `map_boss` 准入限制仍由工厂负责；不得用手写字典绕过工厂。自定义模板不在本版范围。

标记存在即拒绝再次应用，包括空挑战、换一套挑战、深复制后的怪物，以及值为 `null`/空字典的损坏标记。成功和失败都不修改输入。不能删掉标记然后叠乘；这是进程内的调用契约，不是签名或反作弊认证。更换挑战时必须从尚未应用挑战的标准数据重建；不要从活跃敌人反向除倍率，也不要每帧执行。

## 生命、护盾与其他字段政策

| 字段或状态 | 行为 |
| --- | --- |
| 最大生命 | 强健选中时乘 1.20；不取整 |
| 当前生命 | 同时乘 1.20，保持 `health / max_health`；满血仍满血，半血仍半血，零血不复活 |
| 最大护盾、当前护盾 | 数值均原样保留；非零上限时护盾百分比自然不变，零上限要求当前值也为零 |
| 护盾回复及受伤延迟 | 不变；不会随生命上限同比放大护盾或刷新回复计时 |
| 移动速度 | 迅行选中时最终 `speed ×1.10`；攻速、减速状态、出生保护、击退保持原值 |
| 其他字段 | 所有值深复制保留；仅额外添加来源标记 |

最大生命须大于零；当前生命和护盾须在各自上限内。速度、当前/最大资源须为有限非负 `int` 或 `float`。拒绝字符串、bool、NaN、无穷大、超上限、负值及乘法溢出，不静默裁剪错误数据。已死亡但资源合法的标准快照可被转换，零生命仍为零，`death_processed` 不变；实际接入应在加入模拟之前完成。

生命挑战增加原有剩余生命的绝对值，同时保持损伤比例；它不是恢复满血。精度沿用 Godot 浮点运算，没有整数舍入、额外 clamp 或二次属性结算。

明确保留 `damage`、`contact_weights`、`defense_stats`、`resistances`、`radius`、`attack_speed`、`equipment_pool`、`xp_reward`、`reward_eligible`、`root_id`、`parent_id`、`generation`、`death_spawns`、`death_processed`、机制快照及未知扩展字段。不发奖励、不造地图物品、不调用随机函数。

## 后续主集成的自然入口

以下是接入说明，并非本分支已完成的主流程变更：

1. 在遭遇边界由已选择的 ID 编译一次，只有成功才允许后续准入；保留本遭遇冻结 profile。无挑战分支可继续沿用旧流程，或显式应用空配置，不能混用后再重复应用。
2. 根怪入口在 `main.gd::_spawn_monster()` 的 `monster_runtime.create_root(...)` 成功后、`enemies.append(...)` 前。使用返回的 `applied.enemy` 替换局部变量；不能假定原字典已经被就地修改。该入口覆盖普通刷怪、自然灰烬守卫和显式首领，原有工厂准入限制与奖励上下文保持不变。
3. 子怪入口在 `main.gd::_flush_monster_spawns()` 的 `monster_runtime.drain(...)` 返回之后、每个 `enemies.append(child)` 前。子怪必须先由 runtime 赋好 `root_id`、`generation`、`parent_id`、`reward_eligible = false`、`xp_reward = 0`，再应用同一遭遇 profile。不得复制父怪已变换的生命或来源标记。
4. 不在死亡回调、受伤回调、每帧 `_update_enemies()`、`MonsterCatalog.ordinary_roll()` 或装备生成函数里应用挑战。原有场上 100 怪上限、队列 FIFO、谱系预算与一次性死亡事务仍由已有 runtime 管理。
5. 在任何 RNG 抽取或 runtime 创建身份前校验 profile；生成后若意外应用失败，应将此次准入视为失败并由主集成处理已申请身份/谱系的事务清理，不能回退为未加挑战的怪物或留下孤立 roots。本纯函数不持有也不修改 runtime。
6. 本版没有对活跃遭遇中途切换挑战的迁移逻辑。后续若支持切换，必须明确根怪/待生成子怪所属的遭遇配置以及队列取消或重建策略，不能让一个谱系在不明规则下混用不同 profile。

## 验证方法

独立入口未加入现有 `tools/validate.sh`。Linux 下从仓库根目录运行，日志扫描不可省略：Godot 可能在脚本错误后仍返回零退出码。

```bash
set -euo pipefail
ENCOUNTER_TEST_DIR="$(mktemp -d /tmp/godot-encounter.XXXXXX)"
export XDG_DATA_HOME="$ENCOUNTER_TEST_DIR/data"
export XDG_CONFIG_HOME="$ENCOUNTER_TEST_DIR/config"
export XDG_CACHE_HOME="$ENCOUNTER_TEST_DIR/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
godot --headless --path . --editor --import 2>&1 | tee "$ENCOUNTER_TEST_DIR/import.log"
godot --headless --path . --script res://tests/encounter_compiler_test.gd 2>&1 | tee "$ENCOUNTER_TEST_DIR/encounter.log"
if rg -n '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$ENCOUNTER_TEST_DIR"/*.log; then
    exit 1
fi
bash tools/validate.sh
```

临时 XDG 目录隔离存档、设置和缓存，不以用户数据作样本。Godot 导入会生成本地 `.godot/` 缓存和脚本 UID sidecar；本次授权的源码提交只有上述四个新文件，通过 `res://` 路径 preload。

独立验收覆盖：

- 全部当前模板 × 五类目录稀有度 × 普通/子怪/演示/两类首领上下文，在波次 1 和 40 上验证合法组合与工厂拒绝组合；另外测试每个模板的原生机制组合。所有合法组合覆盖空、两种单挑战及双挑战。
- 同源 metadata、递归冻结、输入顺序无关、无别名深复制；未知/重复/超量 ID、损坏/过期/改写 profile、资源类型/上限/溢出及全部 16 种前后配置重入组合。
- 满血、半血、受损、零血；零盾、半盾、满盾；盾上限、回复和延迟保留；灰烬守卫的原生火抗与混合接触伤害保留。
- 真实 brood runtime 的根怪、子怪、孙代死亡对照：总共 9 个怪、仅根怪一次奖励资格、同源 FIFO/预算/trace、不因复制尸体重入而重复结算。
- 100 轮同 seed 普通生成及 v0.13 当前掉落、所有已有装备池真实有效物品对照、调用后 RNG 状态一致，另校验全局 RNG 未推进。
- 真实场景生成 100 怪后在测试内应用挑战，逐个拒绝重入，实际 AI 消费加成速度、真实受伤路径扣血、101 怪被原准入上限拒绝；角色构筑、装备、成长与谱系不变。

百怪循环输出的微秒数包含断言与重入检查，只作诊断，不是 FPS、渲染或五小时耐久性能结论。未声明 Windows 实机运行或人工视觉验收。

## 本次执行记录

基线与环境：远端 main 的 v0.13 源码 `a4a306a6d8c14320fce383dccf6ad7ca40836757`；Linux 云 checkout；Godot `4.6.3.stable.official.7d41c59c4`。仓库和可读父目录中未发现 `AGENTS.md` 或 `.agents/skills`。

独立验收通过：`Encounter compiler: 5111 checks, 0 failures`，退出码 0，日志无 `SCRIPT ERROR` / `ERROR`。并行只读审查独立复跑同样通过，未发现阻塞性缺陷。

原有 `bash tools/validate.sh` 已启动，用户随后要求停止扩展工作、降低额度消耗，因此中止尚未结束的完整回归；**不宣称完整回归通过**。中止前已通过装备、火抗规则、武器编译/目录/状态/集成，以及 v0.13 武器预算穷举（340691 checks，0 failures）。后续可直接复跑上述完整验证命令，无需重新实现模块。Windows 实机、人工视觉、长期耐久未跑。

未合并 main、未发布版本、未接入主流程。模型/服务档位缺少运行遥测：只读审查的可见调度请求是 `gpt-6-astra / xhigh`，不能据此确认实际模型或 Fast。后续要求的 `gpt-6.1-sol / max / Fast 关闭` 需由调度方重新启动，不声称本轮已切换。

## 2026-10-02 独立复审记录

已 fetch 并核验 `codex/encounter-modifiers-v013` 起点为 `84fe8c911438dd146bb654b56acd4e45649d7161`。仓库及可读父目录中仍未发现 `AGENTS.md` 或 `.agents/skills`。先读取既有实现、工厂、runtime 和本接入契约，再独立复跑原验收：`5111 checks, 0 failures`。

审查未发现实现缺陷。本轮仅补足测试中的 34 项边界断言及本记录：

- 配置倍率仅改动 `1e-12`、schema 从整数 `1` 换为浮点 `1.0` 时仍拒绝，快照比较没有近似接受或类型转换。
- 对只读、`death_processed = true`、整数资源、零生命/速度/护盾的合法标准快照，四种选择都成功返回可变的独立怪物；不复活、不开启移动、不重新开放死亡事务，输入与其他字段保持不变。
- `1.7e308` 的有限生命或速度在对应挑战未选中时原样保留；选中造成溢出时不返回半成品怪物，也不改输入。

使用从该起点导出的临时项目和隔离 XDG 目录，Godot `4.6.3.stable.official.7d41c59c4` 导入成功。补测后的独立验收为 `Encounter compiler: 5145 checks, 0 failures`，退出码 0；导入及两次验收日志均扫描确认无 `SCRIPT ERROR` / `ERROR`。原有模板/稀有度、血盾比例、冻结来源、防重复叠乘、真实谱系、奖励资格、装备掉落及 RNG 对照继续通过。

按本轮范围要求，600 秒全量回归留给统一集成；Windows 实机、人工视觉和长期耐久未测。主集成仍使用上文的根怪 `create_root` 后、子怪 `drain` 后且各自加入 `enemies` 前两个接点，并在任何 RNG 或身份创建前验证 profile。本轮调度请求值为 `gpt-6.1-sol / max / 标准速度 / Fast 禁用`，没有实际模型、推理档位或速度的运行遥测。
