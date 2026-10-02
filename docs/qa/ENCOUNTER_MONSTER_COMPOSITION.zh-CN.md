# 遭遇挑战 × 怪物组合专项 QA

## 范围和基线

基于 `codex/encounter-modifiers-v013` 最终提交 `9f553d68277b88b1bde18e5b4fc2d3333a17bde1`，独立分支为 `codex/encounter-monster-composition-v013`。仅新增本说明和 `tests/encounter_monster_composition_test.gd`，不修改现有目录、runtime、compiler、main 或统一验证脚本。

专项直接调用现有 `MonsterCatalog`、`MonsterRuntime`、`EncounterCompiler`、`MechanicRegistry`、`PassiveData`、`DefenseRules` 和装备生成器。测试加载 main 脚本以读取常量，不实例化场景；没有替换生产执行器或自行重写死亡事务。自定义图仅使用现有模板 ID/物种，在独立深副本中修改死亡目标，并通过真实目录校验。

**本结果是接入前的模块组合证据。遭遇挑战仍未接入自然地图、挑战选择、UI、存档或奖励流程，不能据此宣称这些游戏功能已完成。** 主接点和配置验证时机继续遵循[遭遇模块契约](../ENCOUNTER_MODIFIERS.zh-CN.md)。

## 参数来源

| 约束 | 运行时读取来源 | 本次值 |
| --- | --- | --- |
| 生命/移速挑战 | `EncounterCatalog` → 实际编译 profile | 最大生命 ×1.20，当前生命同比例；速度 ×1.10 |
| 场上 admission 上限及场地 | `main.gd` 的实际脚本常量 | `MAX_ENEMIES = 100`，实际 `ARENA` |
| 根怪后的最大代数 | `MonsterRuntime.MAX_GENERATION` | 3 |
| 每条谱系累计后代 | `MonsterRuntime.MAX_DESCENDANTS` | 12 |
| 待生成队列 | `MonsterRuntime.MAX_QUEUE` | 64 |
| 单次死亡整组上限 | `MonsterRuntime.MAX_CHILDREN_PER_DEATH` | 6 |

测试根据实际参数计算队列填充量、谱系预算及有限循环次数。仅保留“当前游戏确实支持 100 根怪”和用户要求的两项倍率作为验收目标断言，未另建一套运行时上限。

## 组合覆盖

1. **共享机制与稀有度**：逐一检查全部当前怪物可执行机制，比较玩家解析、怪物解析和真实天赋节点解析；真实工厂保存同一共享 ID/数值/版本。所有现有模板覆盖波次 1/8/23；白、蓝、金分别应用空选择、单挑战和双挑战。别名归一化保留；橙色仅通过显式关卡/地图 boss 上下文，普通模板升 boss 和黑色预留均拒绝。玩家专用包整体拒绝。
2. **每个演员只乘一次**：根怪先 `create_root`，子怪先 `drain`，随后对各自标准字典应用 profile。子怪来源标记记录自己的原始生命、护盾和速度，不复制父怪的已乘数值。逐字段复原比较，只允许生命、最大生命、速度和来源标记变化；源输入、profile、谱系账本和队列不被 apply 修改。相同配置及空配置的重复应用均原子拒绝；null/空字典来源标记也拒绝。
3. **特殊 A 和普通 A**：真实裂殖体生成普通 A ×2、B ×1；普通 A 默认终止。真实孵化体生成裂殖体，再生成终端后代，合计 9 个演员、1 次奖励资格。配置普通白 A → 终端 B ×2，合计 3 个演员、1 次奖励资格，证明有限分裂可由现有模块表达。无奖励 demo 谱系保持全程无奖励。所有后代保留目标模板稀有度、机制和死亡行为，不继承母体这些状态。
4. **预算与队列**：真实校验通过的无环链到第 3 代后拒绝下一代；六路分支累计达到 12 后代，后续整组拒绝。通过真实根怪死亡填满 64 个请求，再拒绝真实孵化体的整组请求，不花部分预算。零/负空位不出队，逐帧以不同空位数 FIFO 补齐。取消队列不返还已预留预算；回收/重置不复用身份，旧尸体不重新结算。
5. **伤害、防御与资源**：使用真实灰烬守卫模板及共享护盾/恢复包，先制造部分生命与部分护盾，再应用挑战。五类伤害及致死伤害经原有 `DefenseRules` 结算，原始/最终伤害分量、火抗、护盾消耗、接触伤害和回复字段精确保留；只有新增生命影响生命损失/溢出量。倍率没有重复作用到伤害、抗性或护盾。专项验证出生保护字段保留，不模拟 AI 时钟或出生保护到期行为。
6. **百怪死亡差分**：两套真实 runtime 分别运行原怪物和挑战怪物。先放入孵化体，再放入足够真实裂殖体以保证队列溢出，其余使用实际普通刷怪 RNG。每个演员通过真实伤害结算后死亡；重复传原尸体、尸体深副本及死亡前复制的过期快照均拒绝。逐次比较死亡结果、队列、账本和有界 trace；杀当前批次时不插入新生怪，之后按空位数延迟出队，子怪重新从标准模板应用一次挑战。有限阶段内完成全部谱系回收。
7. **独立 RNG**：使用区别于旧验收的种子 `261002/261103/261207`，刷怪 RNG 与装备 RNG 分开，装备种子分别加 `900000`。每个随机刷怪结果、每个奖励资格对应的装备探针结果和后续 32 项随机序列均与独立参考实例完全相同；另用全局 seed `261309` 对照 16 项序列，覆盖编译成功/拒绝、apply/重入拒绝、死亡和出队。

奖励断言基于真实死亡结果的 `reward`、`reward_eligible` 和 `xp_reward`，后代不得有奖励或经验。装备探针在每次根怪奖励资格后调用现有装备生成器以对照 RNG 和合法物品；没有模拟实际游戏掉落频率，也没有写成长存档。场上上限在本专项编排中使用实际 main 常量作为 `drain` 空位预算；真实场景 admission 与移动仍由原遭遇验收覆盖。

## 可复现的拒绝用例

| 输入或事件 | 真实模块结果 |
| --- | --- |
| 普通 A 自指死亡目标；普通 A → 裂殖体 → 普通 A | 目录/runtime 在创建演员前拒绝直接/间接环 |
| 合法无环图要求第 4 代 | `generation_budget`，入队 0 |
| 六路裂殖分支在累计 12 后代后继续死亡 | `lineage_budget`，整组入队 0，无后代奖励 |
| 真实死亡队列已 64 满，再杀孵化体 | `queue_capacity`，旧请求不变，新谱系预留仍为 0；根怪保留唯一奖励资格 |
| 已应用演员再次 apply，包括空 profile | 返回失败，无半成品 enemy，输入不变 |
| 已处理死亡的过期副本仍带 `death_processed = false` | 谱系已处理账本拒绝，奖励 false、入队 0 |

上述是调用真实模块产生的边界反例，并非发现的生产漏洞。本次未发现需要保留红测试或修改生产代码的阻塞缺陷；未来若本专项出现真实缺陷，应保留失败断言并报告负责集成者，不能通过改 runtime/compiler/main 把本分支变绿。

## 复跑

从仓库根目录执行。临时导出项目使 Godot 自动生成的缓存、UID 和用户数据都留在临时目录；工作树仍只新增指定两文件。

```bash
set -euo pipefail
composition_dir=$(mktemp -d /tmp/godot-composition.XXXXXX)
mkdir -p "$composition_dir/project" "$composition_dir/data" "$composition_dir/config" "$composition_dir/cache/fontconfig"
git archive HEAD | tar -x -C "$composition_dir/project"
cp tests/encounter_monster_composition_test.gd "$composition_dir/project/tests/"
export XDG_DATA_HOME="$composition_dir/data"
export XDG_CONFIG_HOME="$composition_dir/config"
export XDG_CACHE_HOME="$composition_dir/cache"
timeout 120 godot --headless --path "$composition_dir/project" --editor --import 2>&1 | tee "$composition_dir/import.log"
if rg -n 'SCRIPT ERROR:|ERROR:' "$composition_dir/import.log"; then exit 1; fi
timeout 120 godot --headless --path "$composition_dir/project" --script res://tests/encounter_monster_composition_test.gd 2>&1 | tee "$composition_dir/composition.log"
if rg -n 'SCRIPT ERROR:|ERROR:' "$composition_dir/composition.log"; then exit 1; fi
```

按相同隔离方式可单独运行 `res://tests/encounter_compiler_test.gd` 和 `res://tests/monster_system_test.gd`。

## 2026-10-02 验证结果

Linux 执行环境，Godot `4.6.3.stable.official.7d41c59c4`。已检查仓库、可读父目录及工作区 `.agents/.codex`，未发现适用的 `AGENTS.md` 或本地 skill 指令。

| 验证 | 检查数 | 失败数 | 退出码 |
| --- | --- | --- | --- |
| 新组合专项 | 19,301 | 0 | 0 |
| 原遭遇编译验收 | 5,145 | 0 | 0 |
| 原怪物模型验收 | 266 | 0 | 0 |

| 刷怪 seed | 根怪 | 死亡处理 | 奖励资格 | 整组拒绝次数 |
| --- | --- | --- | --- | --- |
| 261002 | 100 | 176 | 100 | 21 |
| 261103 | 100 | 176 | 100 | 23 |
| 261207 | 100 | 176 | 100 | 14 |

导入、新专项和两项原验收日志均扫描无 `SCRIPT ERROR:` / `ERROR:`。百怪根奖励资格合计 300，后代奖励资格为 0。未运行 600 秒全量回归、GUI、Windows 实机或长期耐久；这些结果不承担 FPS 或自然地图完整接入结论。

交付只提交并推送本独立分支，核对远端分支 SHA；不合并 main，不发布版本。本专项没有额外模型子代理、购买或额度重置。
