# v056 实际普攻消费者短验收

范围：真实 `scenes/main.tscn`、当前权威 `CanonicalGameState`、真实物品 UID 的装备/卸下、现有技能组、Godot Input 注入。只新增测试与本目录证据；不修改生产、UI、翻译或冻结 v055 源，不执行 import。

## 最终结果

- `20261005T180426362554Z-gameplay`：**193 checks / 0 failures，exit 0，3.0223 秒**。运行前后记录的 main/state/compiler/combat/weapon/test SHA-256 未变。完整命令、哈希、隔离用户目录见同名 `.attempt.json`，完整输出见 `.log.txt`。
- 冻结 v055 的实际 main：`20261005T180205498605Z-baseline`，**20 checks / 0 failures，exit 0，2.7726 秒**。使用已导入的 `v055-final-source-snapshot`，通过外部脚本运行，没有修改旧源。
- 新旧均运行无武器、白蜡长弓、稀有符木法器、固定棱光长弓四种真实装备状态，每种 **24 个 1/60 秒 process 步**。96 帧观察流精确字节相等，包含敌人、弹体完整冻结快照、伤害/弹体/命中准入轨迹、事件、资源、计时、朝向、位置、射击计数、原 RNG、独立暴击 RNG、cast/projectile ID、偷取、技能组冷却、完整 canonical state 和真实保存文件字节。
- 最终报告记录默认 **20 力量、20 智力**，白剑普通攻击 raw `B18 + W4 = 22`，默认力量处理后 `22 × 1.04 = 22.88`。全 T3 本地剑的普通攻击 raw `18 + (4 + 6) × 1.30 = 31`；真实全局暴击为 7% / 165%。不把 raw 与实际含属性结算混用。

## 已验证的实际入口与边界

1. `get_basic_cast()` 只产生 direct，tags 精确为 hit/attack/melee，不含 area/projectile；radius 60、full angle 90、单目标。轻量 profile 与编译一致、对外副本隔离、缓存重读与真实装备切换/reload 保持正确。
2. 自动普攻从 `_update_auto_attack()` 进入：近/远、背后近目标自动转向、大体积半径擦边、同距原数组次序、最近目标、出生保护、死亡目标、墙后目标、可见候选替代。没有合格目标时零计时债、零暴击抽样；命中与空挥均零魔耗。
3. 手动使用 `Input.parse_input_event` + 显式 flush，再由 main 的 `_aim_direction()` 读取真实输入状态：空挥、冷却中再次点击、前后/锥外、大体积扇形边缘的内外点、同距单目标、墙后空挥。每次输入先断言真实 world mouse 方向；每个真实起手恰好一次暴击事件/随机抽样，空挥也占用原 attack interval。
4. 闪避走旧 accuracy/evasion/entropy 消费者；选中者闪避不会穿到第二目标，仍消费一次暴击与计时。MAX_PROJECTILES 满时剑可起手且不修改已存弹体。
5. 实际装备归航披风与终焰护符后，直接剑击没有返回或自然飞行终了爆炸，也没有飞行载体；临时装备随后按真实 canonical slot 卸下，断言 effects 已清空，避免污染后面的源树段。
6. 普攻单目标与裂刃斩独立并行；裂刃仍 radius 95 / full angle 180 / 280% / 12 mana / 1.4 s，沿现有技能组施放。互不冲掉攻击债或技能债，各自一次暴击事件。剑↔弓切换不重置 attack_timer；既有箭完整字节冻结并以旧 projectile tag/旧伤害/旧暴击落地。
7. 合法完整源树 fixture 让近战暴击节点参与真实统计/编译，全局与近战加成各处理一次；独立真实职业选择、XP 保存、逐节点双偷取分配使 life/mana 各 0.4%。实际剑击含暴击、护甲、护盾先结算、双持续偷取，恢复通过 main 推进，不瞬回、不改存档。最终 canonical 校验通过。
8. inventory 暂停、死亡、恢复后实际 `_process()`、真实返城后的 auto/held mouse 阻断；完整保存/reload 恢复相同 UID/源树/编译和 profile，schema 仍 34。

## 输入与验收边界

这是 **headless Godot 输入注入与实际 main 消费者验收**，不是物理鼠标、渲染像素、Windows 打包或硬件帧率验收。Input 注入必须把 world 经原生 camera 转成逻辑坐标，再乘 viewport screen transform 得到物理像素；沿用已有 `density_integration_test.gd` 的同一输入惯例。没有替换 `_aim_direction`、注入假 stats 或更改期望值来掩盖输入失败。

敌人位置/生命/体积/闪避是受控战斗 fixture；高等级近战暴击 fixture 先通过完整 canonical validation 后采用其真实 source tree 计算。双资源偷取节点则全部通过真实分配事务。不是自然游玩录像、完整地图平衡或实战 DPS 结论。

## 保留的失败和修正

每次尝试均保留独立日志、exit、耗时、测试/生产 SHA-256；没有删除失败。

- `180109566012Z-baseline`：exit 1，测试脚本动态变量需要显式 Dictionary 类型，0.515 秒，未进入测试。
- `180133761594Z-baseline`：exit 1，20 checks / 5 failures。测试把 main 指向任意保存路径，正式地图边界按设计拒绝，因此后续自动攻击没有发生。改为真实 `enter_town_test`，使用现有独立测试档；失败 `.bin` 保留，明确不可作为有效比较基线。
- `180218540309Z-gameplay`：exit 1，190 checks / 15 failures。所有失败集中于 headless mouse world direction 与依赖方向的断言；自动、源树、偷取、装备切换和旧字节比较均通过。
- `180253894098Z-gameplay`：exit 1，同上。额外 Viewport.push_input 不解决物理像素/viewport stretch 不匹配；日志保留实际偏移 `(20707.69, 9361.538)`，未把它替换为 expected。
- `180319697466Z-gameplay`：exit 0，190/190。正确 screen transform 修复真实鼠标方向，原扇形/墙/空挥期望全部通过。
- `180426362554Z-gameplay`：exit 0，最终193/193。只增补临时固定效果装备的 canonical slot 清理与清空断言；保留旧冻结基线，没有重复 import 或重拍旧结果。

## 重现

在父任务已经完成统一 import 的目录运行：

```sh
python docs/qa/v056-consumers/run_gameplay.py gameplay docs/qa/v056-consumers/20261005T180205498605Z-baseline.bin
```

首次建立新冻结比较时可运行 `run_gameplay.py baseline`。它只使用已存在的同级冻结 v055 源，不做导入或写旧源。每次创建全新的 `/tmp/godot-m1-v056-consumers-*` 用户/缓存目录，150秒只是故障超时上限，正常全部约3秒。除发生相关代码变化、失败或新增明确覆盖，不需要重复运行。
