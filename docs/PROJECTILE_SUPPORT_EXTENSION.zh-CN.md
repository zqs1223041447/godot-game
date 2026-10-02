# 贯穿辅助扩展：独立模块与接入契约

本分支提供可测试、可接入的纯数据扩展，**尚未接入游戏的 K 列表、施放入口或版本存档**。它不代表贯穿辅助已在游戏中上线；不包含合并或发布。

基线为远端 `main` 的 v0.13 源码提交 `a4a306a6d8c14320fce383dccf6ad7ca40836757`，并在 v0.12 源码提交 `35df85d12aab52cd6371ad5f9f860d2181e5bbf2` 上验证独立套件兼容。v0.13 在开始实现前已到达，因此直接从该提交建立独立分支，无需事后 rebase。

交付仅有三个新增文件：

- `scripts/combat/projectile_support_rules.gd`：纯扩展、元数据、校验。
- `tests/projectile_support_rules_test.gd`：独立测试及真实运行时夹具。
- 本文：主集成接入契约、验证方式及边界。

没有修改 `SupportCatalog`、`SkillCompiler`、`GameData`、`BuildState`、`main.gd`、`project.godot`、既有 UI、图鉴生成器或 `tools/validate.sh`。导入及运行测试均在临时验证副本内进行；生成的 `.uid` 不属于本次三个文件的交付。

## 同源元数据与数值

稳定 ID 为 **`pierce`**，名称为“贯穿辅助”。后续图标资源可按统一约定使用 `pierce.png`；本模块不包含或加载该图标。

`ProjectileSupportRules.SUPPORTS.pierce` 同时是执行操作与元数据读取的来源。主集成应调用 `get_definition("pierce")` 获取深复制的 `name`、`description`、`skills`、`requires`、`operations`，不在 UI 或图鉴中另写一份数值。`supports_for_skill(skill_id)` 返回通过实际配方校验的扩展 ID；未知技能、普攻、龙卷与其他技能返回空列表。`definition_error(value)` 可纯校验元数据，适合导出校验及损坏测试。

| 操作 | 执行意义 | 边界 |
| --- | --- | --- |
| `add_pierce: 2` | 当前配方 `pierce + 2` | 仅飞弹 `bolt`、冰霜 `frost` 的有限穿透 |
| `projectile_hit_more: -0.15` | 命中伤害独立乘 `0.85` | 同时匹配 `hit`、`projectile` 与施放技能 ID |
| `mana_multiplier: 1.20` | 已有辅助编译后的魔力消耗再乘 `1.20` | 不取整，不修改冷却 |

现有 `ProjectileRuntime` 的 `pierce` 是**首次命中后还能穿过的次数**。有限载体的命中容量为 `recipe.pierce + 1`，不是固定三次：

| 配方 | 基础 pierce | 应用贯穿后 | 单枚最大命中容量 |
| --- | --- | --- | --- |
| 飞弹 | 1 | 3 | 2 → 4 |
| 冰霜 | 2 | 4 | 3 → 5 |
| 龙卷母箭、子箭 | -1（无限） | 拒绝适配 | 原行为不变 |

这里是单枚载体的容量，不是每次施放总命中数，也不保证有足够敌人、射程或寿命让容量用尽。初始发射数量、扇形间距、伤害系数、附加伤害效用、减速和速度全部保持原配方值。非默认有限值也按实际配方加二；本模块不写死最终命中数。

## API

```gdscript
static func compile_extension(skill_id: Variant, recipe: Variant, support_ids: Variant) -> Dictionary
```

调用约定：

1. `skill_id` 仅接受 `bolt` 或 `frost`。其他技能（包括空辅助的调用）不属于此扩展入口；继续走原编译器。
2. `recipe` 是本次新生成的飞弹/冰霜发射配方，通常来自原 `SkillCompiler.compile_skill(...).recipe`；不是运行中的 projectile，也不是已经应用扩展的配方。
3. `support_ids` 是该技能的**完整辅助列表**，可包含原辅助 `volley`、`focus` 及扩展 `pierce`。检查共用的两个槽位上限、重复、未知 ID、元数据、兼容性和全部配方字段之后，才返回效果。不能先过滤掉未知 ID 再传入此 API。
4. 原辅助由原编译器处理；本 API 只校验这些 ID，**不再次产生原辅助的数量、伤害或耗魔效果**。

成功返回四个固定字段：

```gdscript
{
    "recipe": <独立深复制的配方>,
    "modifiers": [
        {"id": "support:pierce", "mode": "more", "value": -0.15,
         "all_tags": ["hit", "projectile"], "skills": [skill_id], "damage_types": []}
    ],
    "mana_multiplier": 1.20,
    "error": ""
}
```

没有 `pierce` 的合法列表返回配方副本、空 `modifiers` 和倍率 `1.0`。不额外提供 `ok` 字段，以 `error.is_empty()` 判断成功。

应用 `pierce` 后，返回配方另含内部字段 `_projectile_support_ids: ["pierce"]`。任何再次带此字段的输入都会失败，包括伪造为 `null`、`false` 或空数组的情况。不要删除标记来重复编译；每次从基础构筑重新生成原编译器结果。此字段不是存档字段，不加入伤害事件标签，也不写入公共技能元数据。

失败始终返回：

```gdscript
{"recipe": {}, "modifiers": [], "mana_multiplier": 1.0, "error": "具体错误原因"}
```

失败不返回部分加穿透配方或部分伤害修饰器，调用方不能忽略 `error` 后继续支付或施放。空辅助也会检查配方。数字拒绝布尔、字符串、NaN、无穷、非法小数穿透等；整数值的 JSON 浮点数沿用原编译器语义。有限穿透上限为原配方协议的 `100`，应用后越界直接失败，不静默截断。基础 `pierce = -1` 的无扩展输入可按原样深复制；装配贯穿时明确拒绝无限穿透。

## 后续主集成顺序

下面是接缝示例，**本分支没有把它写入现有编译器或施放入口**。主集成应在统一编译路径实现此组合，让预览与真实施放共用一个结果；所有编译校验先于扣魔力、启动冷却、分配 cast/projectile ID 和创建载体。

```gdscript
# Compiler = 原 SkillCompiler；Legacy = 原 SupportCatalog；Rules = 本扩展。
func compile_with_projectile_extension(skill_id: String, snapshot: Dictionary,
        all_ids: Variant) -> Dictionary:
    if not all_ids is Array:
        return {"ok": false, "error": "辅助列表必须是数组"}
    if not skill_id in ["bolt", "frost"]:
        return Compiler.compile_skill(skill_id, snapshot, all_ids)

    var legacy_ids: Array = []
    for id: Variant in all_ids:
        if id is String and Legacy.SUPPORTS.has(id):
            legacy_ids.append(id)
    # 原编译器本身是纯编译，没有付费、冷却或发射副作用。
    var base: Dictionary = Compiler.compile_skill(skill_id, snapshot, legacy_ids)
    if not base.ok:
        return base
    # 保留完整列表，因此未知 ID/第三个槽位不会被上面的路由吞掉。
    var extension: Dictionary = Rules.compile_extension(skill_id, base.recipe, all_ids)
    if not extension.error.is_empty():
        return {"ok": false, "error": extension.error}

    base.recipe = extension.recipe
    base.snapshot.modifiers.append_array(extension.modifiers)
    base.mana *= float(extension.mana_multiplier)
    base.support_ids = all_ids.duplicate()
    base.support_ids.sort()
    return base
```

将 `base.recipe.pierce` 传给现有 `_shoot` / `ProjectileRuntime.make_projectile`，并传入装好扩展修饰器的 `base.snapshot`。不要改 `base.packets` 的原始伤害点数，避免 `DamageResolver` 再乘一次时重复减伤。原编译器的 `compiled_packets` / `compiled_skill_id` 标记继续保护快照重入；扩展的配方标记保护独立配方重入。

| 完整列表 | 穿透变化 | 初始数量变化 | 命中独立倍率 | 耗魔倍率 |
| --- | --- | --- | --- | --- |
| `pierce` | +2 | 无 | 0.85 | 1.20 |
| `volley, pierce` | +2 | 由原 volley 增加 2 | 0.80 × 0.85 = 0.68 | 1.30 × 1.20 = 1.56 |
| `focus, pierce` | +2 | 无 | 1.25 × 0.85 = 1.0625 | 1.20 × 1.20 = 1.44 |
| `volley, focus, pierce` | 拒绝 | 拒绝 | 拒绝 | 超过两个槽位，不产生编译效果 |

`requires` 中的 `finite_projectile_pierce` 是扩展资格描述，**不是**新增伤害标签。现有 `SupportCatalog.definition_error` 尚不认识这个能力或 `add_pierce`，不能直接把扩展元数据塞入原目录而声称完成集成。后续应统一资格查询和支持列表验证入口，再接 K 列表；列表保存仍使用稳定 ID `pierce`，由主集成负责存档版本、迁移与保护策略。本模块既不提升版本也不读写存档。

主集成可由单向 `SupportRegistry` 包装原 `SupportCatalog` 与本扩展，再按上面的顺序先编译旧辅助、后追加扩展。`ProjectileSupportRules` 已经 preload 原目录作为 `Legacy`，因此原 `SupportCatalog` 不应反向 preload 注册表或本扩展，避免加载循环。原辅助的 mana/more 只由 `SkillCompiler` 产生，扩展返回的 mana/more 只追加一次；带 `_projectile_support_ids` 的配方及带编译标记的快照不得重新送入编译入口。

## 运行时边界

- 同一载体对同一怪物每个相位只命中一次；跨帧持续重叠不会重复命中或消耗穿透。
- 回程保留尚余贯穿次数，不补满。去程命中过的怪物可在回程再命中一次，仍消耗剩余预算。
- 命中耗尽（`hit_consumed`）直接终止，不触发自然飞行结束爆炸。最后一击恰好位于射程终点时，命中耗尽优先于返回和爆炸。
- 自然射程结束或原始寿命到期可按原装备效果产生一次独立爆炸。寿命与射程同刻时寿命优先，寿命截止点上的接触不算命中；取消载体不爆炸。
- 贯穿修饰器只匹配本技能的 `hit + projectile`。同技能独立爆炸拥有自身 `hit + area + secondary + explosion` 标签，因此伤害不变。普攻、其他技能及龙卷的无限穿透、分裂、伤害均不受影响。

## 独立验证与证据

验证引擎：`4.6.3.stable.official.7d41c59c4`。在独立 Linux XDG 目录下运行，避免接触玩家的存档和设置。独立套件使用真实 `SkillCompiler`、`DamageResolver`、`ProjectileRuntime`，不使用替身来计数碰撞。

```bash
validation_dir="$(mktemp -d /tmp/projectile-support-test.XXXXXX)"
export XDG_DATA_HOME="$validation_dir/data"
export XDG_CONFIG_HOME="$validation_dir/config"
export XDG_CACHE_HOME="$validation_dir/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
godot --headless --path . --script res://tests/projectile_support_rules_test.gd \
  > "$validation_dir/test.log" 2>&1
result=$?
cat "$validation_dir/test.log"
test "$result" -eq 0 && ! rg '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$validation_dir/test.log"
```

Godot 可能输出脚本错误却返回退出码 0，因此同时检查日志。需要进行完整项目导入时，请在临时 checkout 中运行 `godot --headless --editor --import`；运行现有完整回归使用 `bash tools/validate.sh`。原 `validate.sh` 未注册新套件，主集成后应补上测试入口。

前次交付已执行的独立套件结果：

| 基线 | 结果 |
| --- | --- |
| v0.13 `a4a306a` + 本扩展 | `Projectile support extension: 998 checks, 0 failures` |
| v0.12 `35df85d` + 同一模块/测试 | `Projectile support extension: 998 checks, 0 failures` |

覆盖元数据深复制、所有字段完整校验、未知/重复/超槽位辅助、非法类型/非有限数/越界、无限穿透拒绝、配方重入、失败不产生部分效果、原辅助组合顺序无关，以及真实串列敌人命中次数。串列夹具使用实际默认速度、射程 `650`、寿命 `1.7`、半径 `5.5`，同时跑空间索引和全扫描、单帧和分帧；精确相位与终点测试使用显式固定速度和零半径来构造可核算的边界。另验证活动载体冻结快照、普攻、龙卷分裂及独立爆炸。

2026-10-02 本轮独立审查从已 fetch 并核验的 `61af145e5b05601c36119731799a87eec74a48ab` 继续，未发现需要修改扩展实现的缺陷。仅补充全局 RNG 流保持不变的边界检查，覆盖整套成功、失败、组合与真实运行时夹具；在临时副本中向扩展入口注入一次 `randi()` 后，该检查按预期成为唯一失败，恢复原实现后通过。飞弹/冰霜的真实基础穿透加二、投射物命中总降 15%、独立爆炸和普攻排除、龙卷无限穿透拒绝、完整列表验证、重入及旧辅助 mana/more 不重复应用均由原有夹具复核。

| 本轮针对性验证 | 结果 |
| --- | --- |
| 修改前扩展基线 | `998 checks, 0 failures` |
| 补充 RNG 检查后扩展 | `999 checks, 0 failures` |
| 原 `skill_compiler_test.gd` | `319 checks, 0 failures` |

通过的套件均核验退出码和日志，无 `SCRIPT ERROR:` 或 `ERROR:`。本轮仅在临时验证副本和隔离 XDG 目录运行；日志保存在本轮云环境 `/tmp/projectile-review.L1ZE4n/baseline.log`、`/tmp/projectile-review.L1ZE4n/final-extension.log`、`/tmp/projectile-review.L1ZE4n/skill-compiler.log`，预期失败的 RNG 负对照单独保存为 `/tmp/projectile-review.L1ZE4n/rng-negative-control.log`。

此前完整回归**未完成**：已通过运行到 `skill_support_ui_test.gd` 的检查（含原辅助集成 733 项、原辅助 UI 186 项），随后按停止指令在 `equipment_soak_test.gd` 运行期间终止长回归，余下检查未跑。前次完整日志保存在当时的云环境 `/tmp/projectile-full-validation.log`；独立套件日志为 `/tmp/projectile-extension-test.log` 和 `/tmp/projectile-v012-test.log`。本轮没有重跑完整导入或长回归，留待统一主集成；没有进行游戏中的贯穿 K 列表交互、存档迁移或发布验证，因为这些入口尚未接入，不应把独立运行时测试称为游戏集成已完成。

本轮执行配置的**请求值**为 `model=gpt-6.1-sol`、`reasoning_effort=max`、标准速度、禁用 Fast；平台未暴露实际主执行模型、服务路由或速度遥测，不能将请求值当成后端证明。本轮未派发模型子任务，也没有执行额度购买或模型套餐变更操作。
