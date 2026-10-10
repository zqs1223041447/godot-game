# 银杏回廊西叶追击与雷圈

基线：`8ed6961ccc8a87793cbd1ae76c9afe8ae4d9b95a`。本批仅一处已有遭遇的内容变化，不新增怪物、攻击、模型、地图机制或存档字段。

## 原有组合与变更

- `GinkgoRosterRules.PATTERNS.camp_west` 前四个基础名额为 `skitter, crawler, skitter, crawler`；北、东组已使用 `frost_guard`、`storm_skitter`。原始随机稀有度、裂殖/孵化等固定模板仍有优先权，因此这不是所有seed都保证出现的四怪名单。
- 当前探索布局将西组前四个名额归入 `camp_west_1`（西叶据点·1），中心相对坐标 `(1290,2100)`；第三名额偏移 `(27,-40)`。四怪预算、位置和所属驻点不变。
- 仅正式II/III档（wave6/10），最终第三名额为普通、无机制 `skitter` 时改为已有 `storm_skitter`。在地图与巡逻映射后应用；不覆盖其他模板、稀有度或机制，不寻找替补候选，不消费额外随机数。
- 追击组合加入既有锁点雷圈：0.7秒预警、半径65；命中后1秒感电，后续命中承伤提高15%。体型仍为kind1，既有雷击与感电代码完全未改。
- 固定测试地图、I档、其他地图及其他名额保持原编排。schema61不变。

## 有限验收

| 项目 | 结果 | 证据 |
|---|---|---|
| 变更前编排采集 | 261组，5地图×可用档位/特殊词缀×3seed | `baseline.json`, `capture.log` |
| 完整编排对照与生成 | 1811检查，0失败；20组只改目标名额，241组原样；9次完整生成 | `generation-result.json`, `generation.log` |
| 真实Main II/III | 211检查，0失败；2次完整入图、战斗与清图领奖 | `main-result.json`, `main.log` |
| F8数据边界 | 仅1张银杏地图卡变化，3817张原样；49条内部链接有效 | `reference-verification.json` |
| 浏览器 | 搜索“西叶追击”、跳转既有雷纹怪物卡成功，无pageerror | `browser.json`, `f8-west-storm.png` |

基线记录每个完整驻点的类型保真序列化SHA256，以及原第三名额字节；恢复唯一允许变更的模板后，所有驻点指纹逐组吻合。验证相同seed完全重放、无全局RNG消耗；9次完整探索生成校验37个根实体、36个普通根怪账目、出生ID与驻点归属、实体尺寸及原几何路线通行。

Main使用原生v49真实夹具并经现有迁移加载；前置解锁由原正式模型事务完成。QA明确控制RNG seed、高玩家生命、其他实体静止、必杀结算，不声称自然通关录像。选中的是正式入图第三名额实体，未另造怪物。真实tick验证预警不提前伤害、留圈受雷击和15%感电、按住移动键离圈免伤。每图37个根怪各记一次奖励，后代无根奖励/XP；先杀根怪后活后代仍阻止完成，清完后原8/12碎片奖励可领取且不可重复领取。原掉落、奖励及战斗实现的源码字节保持基线一致。

本次Main为headless实际场景集成检查。截图是F8生成HTML的本地Chromium浏览器，不声称原生F8按键截图或新增游戏画面验收。favicon请求404不影响页面功能。

## 过程中的探针修正

- 最初基线采集使用旧竞技场尺寸，`MapCampState.begin`断言失败，30秒上限退出124。生产代码当时未改；采集改为当前3600×2400探索边界后成功，原断言失败不计入通过结果。
- 首轮Main脚本误用不存在的`ShockRuntime.state_for`接口，提前中断；`main-initial-interface-error.log`保留，`completed=0`使本轮失败而非误报成功。
- `main-intermediate.log`为改用现有查询接口后的中间记录；最终进一步断言`active`和增伤0.15，`main.log`与`main-result.json`才是最终结果。

## 复核命令

在独立XDG目录执行（每个Main复核使用新的`/tmp/godot-west-storm-main-*`目录）：

```sh
XDG_DATA_HOME=/tmp/godot-west-storm-generation XDG_CACHE_HOME=/tmp/godot-west-storm-cache timeout 45 godot --headless --path . --script res://tests/ginkgo_west_storm_test.gd
XDG_DATA_HOME=/tmp/godot-west-storm-main-new XDG_CACHE_HOME=/tmp/godot-west-storm-cache timeout 45 godot --headless --path . --script res://tests/ginkgo_west_storm_main_test.gd
python3 tools/verify_ginkgo_west_storm_reference.py
python3 tools/build_reference.py --check
python3 docs/qa/ginkgo-west-storm/browser_check.py
```

`capture_baseline.gd`仅用于原8ed6961源码；源码SHA守卫禁止在新实现上覆盖旧基线。导出使用`tools/ginkgo_west_storm_reference.gd`和专用精确合并器，只追加当前规则并更新银杏当前描述；原历史示例没有重抽或覆盖。未执行全套、600秒检测、Windows导出封包或模型工作。
