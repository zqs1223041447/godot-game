# 探索地图总览专项取证

基线：`071189029b1fb3879aa8f240e1865d80694c2fef`。Godot 4.6.3，X11 dummy 显示、Mesa llvmpipe，1280×720。每次使用独立 `/tmp/godot-map-overview-*` 用户目录，单次上限 45 秒，无封包、模型改动或全套测试。

测试 `tests/exploration_map_overview_test.gd` 创建当前 schema59 的正常角色，走五张地图已有免费 I 阶草案和正式入场；遗迹使用现有原生地形准备入口。通过真实 Tab / Esc / K / 数字技能键输入，验证总览开关、菜单焦点、施法、原始移动 tick、死亡、返回确认、重试以及地图完成后的显示。控制击杀通过现有防御和死亡结算完成；不是自然游玩、自然赚取或性能基准的声明。

只读比较包含原测试已有的 Main、角色、几何及战斗运行时字段，实际保存字节、RNG、怪物、队列与地图状态。有限后代清理最多五轮，验证根怪死亡但后代排队时驻点仍未清理，后代清完后才变绿。现有 `cleanup_hint_hud_test.gd` 作为相关方向提示回归。

最终 `report.json`：**171 项，0 失败**。原余敌提示 HUD 回归：**22 项，0 失败**。真实截图另外断言玩家及首领标记的实际像素，界面缩放沿用原 HUD 的局部尺寸。

第一轮 94/0；检查截图后调整取证，让 HUD 的原有开场提示计时结束并更新信息栏，避免冻结测试保留提示条。补查阶段曾遗漏主循环全清结算检查、以及返城后原有领奖步骤，分别得到 159/1 和 119/1；补齐原流程后最终通过。单图诊断的一个临时类型错误已修正。生产视图缓存背景样式并使用独立显示层，便于阅读时不被普通提示条覆盖。

图像查看阶段曾疑似缺少入口、玩家和首领标记；随后直接核对最早和最终 PNG 的像素，标记均完整。这不计为已证明的游戏绘制缺陷；不以图像查看工具的呈现差异声称修复引擎问题。

另运行的旧 `docked_menu_state_test.gd` 断言 C 不属于菜单键；当前文件和基线 `0711890` 独立最小项目均为同样 4 项失败（40 项）。该测试只预载未改动的菜单状态类，未修改历史断言或扩大本批范围。原始对照日志保留。

截图：

- [断垣试炼：两个实际长墙与驻点](broken_ruins.png)
- [遗迹庭园：真实多边形障碍](ruins_garden.png)
- [实际清理一个驻点后变绿](cleared-outpost.png)
- [实际全清后各驻点与首领状态](map-complete.png)
- [旧庭](old_garden.png)、[泉庭](sunwell_terrace.png)、[银杏](ginkgo_arcade.png)

运行：

```sh
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 \
XDG_DATA_HOME=/tmp/godot-map-overview-ui-final \
XDG_CACHE_HOME=/tmp/godot-map-overview-cache \
OVERVIEW_OUTPUT=/workspace/godot-cues-scan/docs/qa/exploration-map-overview \
timeout 45 godot --path . --rendering-method gl_compatibility \
  --audio-driver Dummy --script tests/exploration_map_overview_test.gd
```

显示驱动报告不支持 V-Sync 是该 dummy 显示环境提示；不构成游戏逻辑失败。界面截图由 Godot 原生渲染直接保存，无后期合成。未覆盖长期运行或密集燃烧性能，原性能待办保持独立。
