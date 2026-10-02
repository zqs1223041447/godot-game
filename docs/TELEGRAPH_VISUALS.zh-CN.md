# 重击地面预警：独立绘制组件

组件初次交付基线为 `codex/telegraphed-area-runtime` 的 `6bf5cf3b8d5e2d02bc4e6d5dc716f6cc928e7c79`。本次独立复核从 `codex/telegraph-renderer` 的 `60743b6452ced85531de903d9b08d0074dacc447` 起步，改动限于 `scripts/visuals/telegraph_renderer.gd`、`tests/telegraph_renderer_test.gd` 与本文档，提供可独立检查的绘制组件和接点说明。**尚未接入游戏主流程，也不是已上线的游戏功能。** `ArenaVisuals`、`main.gd`、运行时、怪物目录、UI、存档、图鉴及发布配置均保持基线。

## 状态来自实际运行时

输入是 `TelegraphedAreaRuntime.state_for(source_id)` 返回的隔离字典组成的数组。组件仅读取 `source_id`、`center`、`phase`、`elapsed` 和 `profile` 中的 `radius`、`windup_seconds`、`recovery_seconds`，不查看 `packet`、来源位置、玩家位置、伤害或随机数。

| 输入 | 绘制含义 |
| --- | --- |
| `center` | 开始时锁定的真实世界圆心，后续不追踪来源或玩家。 |
| `profile.radius` | 完整危险边界的世界半径；蓄力、特效级别、UI/字体缩放与恢复都不改变它。 |
| `phase = windup` | `clamp(elapsed / windup_seconds, 0, 1)` 控制土色底染和中心符文的逐笔完成。范围从第一帧就是完整大小。 |
| `phase = recovery` | `clamp((elapsed - windup_seconds) / recovery_seconds, 0, 1)` 控制恢复进度；所有笔触按剩余比例平方原地消退，边界角色变为 `recovery_boundary`。 |
| `{}`、已取消或已删除状态 | 当次输出为空，不保留上一帧的预警，不产生终止爆炸。 |

`elapsed` 是整次攻击的累计时间，恢复时不能直接用 `elapsed / recovery_seconds`。阶段以运行时的 `phase` 为准；渲染器没有自己的计时器，不推进状态，不发出命中事件。暂停时保持同一快照即保持同一画面；恢复中仍由调度器负责死亡/取消/重置。

配置范围直接读取既有 `TelegraphProfiles.LIMITS`，不另设屏幕半径上限或默认时长。非有限/非数值标量、非法圆心、缺失配置、未知阶段、非正整数身份、明显不一致的阶段时间及已到总时长的副本不绘制。阶段边界允许与运行时一致的 `1e-9` 秒容差。没有把异常输入改写成有效攻击的兜底。

运行时在 `elapsed + 1e-9 >= windup_seconds` 时已进入恢复，因此 `windup` 副本必须满足严格的相反条件；不能仍以 `elapsed > windup_seconds + 1e-9` 拒绝。这次修复该校验遗漏：原提交会在恢复截止边界接受被误写为 `windup` 的副本，继续输出 `danger_boundary`。新增测试以实际运行时判定阶段，在 0.001、0.25、0.7、60 秒蓄力及非对称恢复配置下覆盖截止前后和总时长过期容差；原提交产生 12 个失败，修复后全部通过。有效运行时副本的视觉表现不变。

## 美术与图层

沿用既有日光石庭、暖皮革、石粉与旧符文的经典魔法世界风格：透明暖土色底染、深土色细底笔、赭金色石粉边界、中心折笔符文与少量不均匀石痕。符文按笔迹长度逐渐完成，不用旋转钟面、科技准星、加法发光材质、粒子、全屏闪光或逐渐扩大的危险圈。恢复变成低饱和灰土色，范围不移动、不外扩。

`VisualSettings.effects_level` 只控制额外石痕数量：低 0 条、中 1 条、高 3 条。三档始终保留完全相同的完整危险边界、底染和蓄力信息。无额外装饰运动，因此 `motion = false` 不冻结必要的蓄力/恢复提示；UI、字号、伤害数字开关均不参与世界几何计算。

所有来源的底染先画，随后画所有边界，再画符文与石痕，避免后一个来源的半透明底染覆盖前一个危险边界。组件应画在地面层、角色及怪物之前，复用现有世界相机；不做 `draw_set_transform`，不手动乘除 `WorldView.DEFAULT_ZOOM`，不移动 HUD。

## 可测试 API 与硬上限

```gdscript
const TelegraphArt = preload("res://scripts/visuals/telegraph_renderer.gd")

# canvas 的 _draw() 回调内调用；states 是最新 state_for 副本数组。
TelegraphArt.draw(canvas, states, preferences)

# 无需 CanvasItem 或真实窗口，即可检查相同的一组绘制命令。
var commands: Array[Dictionary] = TelegraphArt.primitives(states, preferences)
```

`draw(canvas: CanvasItem, states: Variant, settings: VisualSettings = null)` 只将 `primitives` 的新输出提交到 Godot 绘图接口；空 canvas 安全返回。缺省设置等价于高特效。`primitives` 无持久池、历史、信号、RNG、游戏事件或状态写入，其返回值可由测试方修改，不影响输入或下一次输出。

| 预算 | 硬上限 |
| --- | ---: |
| 输入数组长度 / 接纳来源数 | 100 / 100，来自 `TelegraphProfiles.MAX_ACTIVE` |
| 每来源图元（低 / 中 / 高） | 5 / 6 / 8；蓄力起点尚无已完成笔迹时少 1 个 |
| 全局图元（低 / 中 / 高） | 500 / 600 / 800 |
| 每折线点数 | 6 |
| 每来源圆形命令 | 3：一个填充、两个同半径边界笔触 |

这里的图元预算是 Godot 绘制命令条数；圆的原生细分由 Godot 处理，不将此数字当作 GPU 三角形数或硬件帧率保证。无按半径、时间步长或历史长度增长的脚本循环。

非数组或超过 100 条的数组整体拒绝，避免扫描无限输入或截断后假装范围集合完整。数组内无效项跳过；相同来源保留第一条有效副本，不能重复叠加。有效来源按 `source_id` 升序输出，让来源数组重排不改变透明笔触顺序。宿主应每帧每来源只提供一个最新副本。

每个命令带 `kind`、`role`、`source_id`、`phase`、`color`、`width`。`circle` 另外带世界 `center`、`radius`、`filled`，`polyline` 带新建 `PackedVector2Array points`。`danger_boundary` 与 `recovery_boundary` 区分未结算危险和已消退的地面印迹；命令分类本身不用于伤害判定。

## 预留绘制接点（本次未应用）

前提是后续主流程已按[运行时接入契约](TELEGRAPHED_ATTACKS.zh-CN.md)持有、调度和取消 `TelegraphedAreaRuntime`。当前 `main.gd` 没有该实例；本文不偷偷引入字段或怪物技能分配。

后续宿主在绘制前从现有、最多 100 个来源取得当前状态：

```gdscript
# 未来宿主中的适配示例；不写回 runtime 或 enemy。
var snapshots: Array[Dictionary] = []
for enemy: Dictionary in enemies:
    var copied: Dictionary = telegraphs.state_for(int(enemy.id))
    if not copied.is_empty():
        snapshots.append(copied)
```

在 `ArenaVisuals.draw_scene` 的地面提示之后、`ActorArt.draw_enemy` 的排序/绘制之前调用：

```gdscript
# 未来绘制接点；arena、snapshots、preferences 都由宿主明确提供。
TelegraphArt.draw(arena, snapshots, preferences)
```

需要使用每帧最新的 `state_for`，不能长期保存 `start()` 的入场副本，也不能继续渲染已取消来源的旧副本。命中范围及玩家半径沿用既有伤害接入契约，不能从符文、底染 alpha 或恢复图元触发结算。重开、试验场切换和死亡由宿主清空调度器并重建快照，组件无需单独重置。

## 验证入口与证据

使用环境已有的官方 Godot 4.6.3，在项目根目录执行：

```sh
godot --headless --path . --script res://tests/telegraph_renderer_test.gd
godot --headless --path . --script res://tests/telegraphed_area_test.gd
godot --headless --path . --script res://tests/combat_cues_test.gd
```

独立测试覆盖运行时真实副本、非对称时长、阶段/过期容差、配置半径上下界、单调符文/恢复、取消/重置、畸形与非有限数据、输出隔离、RNG 不变、低特效保留边界、100 来源三档图元预算/几何边界/重复构建/顺序稳定，以及实际 CanvasItem 绘制回调。额外验证 `1e308` 标量的拒绝、最多约 `3e38` 的有限圆心仍输出有限且有界的图元、百万条数组在读取元素前被整体拒绝。720p/2K 下相机分别使用 0.35、0.65、1.3 倍缩放，世界半径只经当前相机变换一次。所有运行使用独立 XDG 设置、缓存和存档目录。`tools/validate.sh` 按文件隔离要求保持原样，本次没有重跑 600 秒全量验证。

同一测试文件提供可选截图入口，要求实际显示和渲染后端；headless 模式明确失败，不导出空白截图冒充视觉验收：

```sh
godot --path . --display-driver x11 --rendering-method gl_compatibility \
  --rendering-driver opengl3 --audio-driver Dummy \
  --script res://tests/telegraph_renderer_test.gd -- --capture /absolute/evidence/directory
```

该入口从实际 `MonsterCatalog` 生成来源，用实际 `TelegraphedAreaRuntime` 推进后读取副本，并复用既有石庭、怪物与 0.65 倍世界相机，在 1280×720、2560×1440 各导出高特效阶段图、低特效阶段图和默认 90 世界单位半径的 100 来源低特效图。它是独立绘制夹具，不是主场景中的自然遭遇或玩家躲避验收。

本次独立复核实测：官方 Godot `4.6.3.stable.official.7d41c59c4` 导入无脚本错误；修复后 headless 渲染组件测试 **12,525 项 / 0 失败 / 18 次绘制回调**，既有运行时回归 **882 项 / 0 失败**，既有战斗提示回归 **1,032 项 / 0 失败**，世界视图回归 **300 项 / 0 失败**。X11 + OpenGL 4.5 / Mesa 25.0.7 llvmpipe 软件渲染下含截图测试 **12,745 项 / 0 失败 / 18 次绘制回调**，实际保存 6 张 PNG。仅出现驱动不支持更改 V-Sync 的警告，无 Godot `SCRIPT ERROR` 或 `ERROR`。

原生测试还在独立透明 512×512 `SubViewport` 中调用同一个 `Renderer.draw`，读取真实渲染像素：22 / 90 世界单位半径 × 0.35 / 0.65 / 1.3 相机缩放 × 低 / 高特效共 **12 组**。像素包围盒按真实半径及边界半笔宽推导，允许 2 像素光栅/抗锯齿误差，并检查四个方向的危险边界可见；低特效各组与高特效一致。headless/dummy 后端跳过此像素检查，并明确报告 `0 native radius cases`，不以坐标计算冒充像素验证。

本次工作区证据目录为 `/workspace/scratch/telegraph-audit-evidence/`，日志为 `import.log`、`phase-boundary-before-fix.log`、`final-renderer-headless.log`、`final-renderer-native.log` 与 `baseline-{telegraphed_area_test,combat_cues_test,world_view_test}.log`；截图在 `final-captures/`，名称为 `telegraph-{high,low,100-low}-{1280x720,2560x1440}.png`。六张 PNG 均与同环境重绘的 `60743b6` 基线截图逐字节一致，哈希及日志错误检查记录在 `evidence-manifest.json`。证据保存在仓库外，以保持提交仅改动规定的三个文件。上面的命令可在其他具备真实显示后端的环境重新生成证据。

已人工查看阶段图和百来源图：低特效保持完整边界与中央符文，恢复逐渐消退且石庭可见；100 个默认半径的重叠边界较密，不能把该压力图当作实战可读性已验收。软件渲染截图不代表目标 GPU 性能或 Windows 原生效果。

主流程接入、选怪/发动策略、完整战斗中的可读性、玩家移动与范围结算、Windows 原生显示及目标硬件帧率仍需后续接入后验证。本次仅交付和验证独立渲染组件。
