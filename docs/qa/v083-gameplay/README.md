# v0.83 银杏回廊：实际 Main 短验

入口：[ginkgo_map_gameplay_test.gd](../../../tests/ginkgo_map_gameplay_test.gd)。只运行新图的正式 I、II 两条完整流程；不重跑历史地图套件。怪物全部经真实 `MapCampAdmission` 生成，每组12根、三组36根可同时在场；死亡使用真实 Main 结算路径的受控致命伤害。攻击场景暂停自动输入并受控布置玩家位置。**这是确定性集成夹具，不是自然战斗录像、难度体验或性能基准。**

正式 I 从独立默认存档开始；真实首通、返城、领取4碎片后，使用这些现有碎片支付正式 II。II 选择疾攻、凶猛与霜纹巡逻，真实 wave6、费用4、完成奖励12。覆盖初始 II/III 门禁、不同激活顺序、出生保护、重复触发、36根门禁、自然首领、首领四后代、37个有效根奖励、仅一次完成、待领奖励阻止新开、返城、真实领取与再次入图。不会手工修改正式解锁、钱或装备。

唯一集中执行已通过：**213项检查、0失败、两条完整Main地图，9.231秒、exit0**。保存报告时最后一次成功打开文件检查在JSON生成后计数，因此 `main-result.json` 为212，最终日志为213；只读收据明确核对这一个差值。没有失败重跑，也没有editor import或GUI。日志包含环境既有的 `Fontconfig error: No writable cache directories` 提示；无Godot脚本解析、运行或测试错误。

首领使用实际 `ginkgo_shelter_slam` 权限及共享单响 scheduler，检查起手 LOS、自身起手中心锁定、r240/1.4秒/1.2接触分量预算、攻速缩放原恢复、圈内无遮挡实伤与原防御护盾顺序、侧花坛后仍在圈内的遮挡、圈外安全、真实外力位移不拖圈、0.24秒冻结保留已走0.5秒与攻击身份、解冻后精确一次结算，以及源死亡取消。

冻结命中来自 [ginkgo_fixture.gd](ginkgo_fixture.gd) 的独立合法来源：复用 v0.82 的 level4/8点路线，真实分配14209，真实创建owned霜锁辅助并放入已有Frost组。完整model与cast会一起导出；这个来源不替换正式地图角色，也不为native视觉夹具发装备。用于证明现有Main冰冷命中→冻结→共享预警时钟集成，不声称测试角色在自然流程中取得过该构筑。

## 执行

等待父任务完成唯一 editor import 后：

```sh
python docs/qa/v083-gameplay/run_checks.py
```

runner分配 `/tmp/godot-m1-v083-ginkgo-*` 的独立存档目录，90秒限时，仅headless执行。完整日志、命令、脚本SHA、耗时、退出码、真实模型与攻击权限保留在 [results/](results/)。只审核已有通过证据可运行 `python docs/qa/v083-gameplay/verify_receipts.py`，不再启动Godot；结果与产物SHA在 [acceptance.json](acceptance.json)。

## 单窗口 native 夹具

[native_review.gd](native_review.gd) 只由root启动；本worker不打开GUI。真实 `main.tscn → enter_town_test → craft_map('ginkgo_arcade',[],[]) → start_map`，独立测试存档，正常入口与正式角色不变。

```sh
XDG_DATA_HOME=/tmp/v083-ginkgo-native-layout-UNIQUE \
godot --path . --script res://docs/qa/v083-gameplay/native_review.gd
```

默认停在新图入口，可查看真实墙、旗和三个据点。需要真实首领预警时，在root自己的同一个窗口流程中使用 `GINKGO_NATIVE_MODE=warning`；此模式先触发全部36根并受控清除，经过自然Boss门禁后由真实 `_start_enemy_telegraphs` 起手，将同一权限推进到0.7秒后暂停。

## F8 同源资料

优先读取已通过本入口的 `results/main-result.json`：`runs[].profile` 是实际正式入图profile，`attacks['1'/'2']` 是自然首领实例、真实锁定攻击与visual snapshot。`formal-tier1.json`、`formal-tier2.json` 是通过完整ownership规则的真实Main完成并领奖model；`freeze-source.json` 与 `freeze-cast.json` 是同源合法冻结示例。它们都来自实际调用，不需要另写稀有装备或近似物品位置。仅 `failures == 0` 且执行退出0后才作为通过证据使用。
