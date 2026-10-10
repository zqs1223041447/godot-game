# 断垣试炼：内廊霜卫与灰烬

基线：`874038562875d5ac39300ed4c16425a102c44b8f`。只调整一处现有驻点的最终编排，复用原攻击、寒冷与墙体机制；不新增模型、属性、地图机制或schema字段。

## 证据与决定

当前探索布局的 `camp_north_2`（北侧据点·2）位于两道错位残墙之间，中心相对坐标 `(1790,1150)`，北组名额5–12，共8个根怪。原本没有该驻点专属的物种编排。

变更前只读检查见 `inspect.log`：正式II/III档seed7的八个模板依序为 `crawler, crawler, splitter, splitter, brute, crawler, splitter, ember_guard`，唯一普通重壳体为北组名额9；seed861073的普通重壳体在名额10。这些组合已有固定灰烬守卫，但没有寒冷控制，其他实体主要是接触追击与死亡后代。seed0已有霜纹守卫，因此不应再堆一名。

采用“内廊寒击与原灰烬守卫配合”：仅正式II/III档（wave5/9），先检查该八怪驻点是否已有 `frost_guard`；若没有，按原顺序将第一个普通、无机制 `brute` 替换为原 `frost_guard`。没有候选则不变。只处理北组名额5–12，不向别的驻点找替补。

- 保留I档、固定测试地图、其他地图和其他驻点。
- 先完成原有普通/元素/巡逻编排，再检查候选；不覆盖最终巡逻模板、稀有怪、裂殖、孵化或固定灰烬名额。
- 不增加实体或随机抽取；保持8怪驻点、36普通根怪+1首领、出生点、体型、稀有度、机制、根ID和后代/奖励合同。
- 霜卫使用原0.9秒、半径90锁点寒击。实际冰霜损失后减速25%持续1.2秒，不冻结；原灰烬守卫、墙体与绕墙路径不变。

## 有限验收

| 项目 | 结果 | 记录 |
|---|---|---|
| 已发布完整生成器对照 | 1480检查、0失败；265组中20组仅一个模板变化，245组类型保真全状态原样 | `generation-result.json`, `generation.log` |
| 优先权样例 | 已有霜卫14组不追加、无候选6组不替换；包含普通属性词缀与特殊巡逻 | 同上 |
| 全图生成与可达性 | I/II/III×3seed，9次全部实体/路线准入成功，37根实体及8怪归属保持 | 同上 |
| 实际Main | 286检查、0失败；II/III各一次完整正式入图、战斗和领奖 | `main-result.json`, `main.log` |
| F8精确边界 | 只改断垣地图卡，3817张卡原样，50条内部链接有效，历史示例不重抽 | `reference-verification.json` |
| 浏览器 | 搜索“内廊霜卫”、跳转原霜纹怪物卡；无pageerror | `browser.json`, `f8-corridor-frost.png` |

生成对照使用逐字冻结的8740385版 `MapCampState`（`map_camp_state_8740385.gd.txt`），SHA256为 `5b49600164356fa94fdbb10115d3b07b7d9193aa9212db6d85dbb0a79e86174b`。旧版依赖的怪物/其他地图编排代码未改。测试比较完整类型保真checkpoint，不只计怪物数量；覆盖相同seed重放与全局RNG不变，亦涵盖上一批银杏编排。复用上一批有限profile集合和Main的check/actor/kill辅助方法。

实际Main使用真实原生v49夹具经既有迁移加载；前置解锁通过原模型事务完成。明确控制RNG seed、高生命、其他实体静止、墙侧放置和必杀结算，不是自然通关录像。自然入图选中霜卫和同驻点固定灰烬守卫均保留原位置，配合探针只控制攻击起手顺序：寒击命中后，由灰烬守卫锁定后续火圈；角色原移速240，寒冷时实测180，按住向右移动在原预警结束前走出火圈，两档均获得“寒击命中、火击未命中”的真实事件。此结果仅证明该夹具与时序下可躲避，不泛化为全部构筑的难度结论。

同时验证单独寒击不提前命中、实际减速恰为25%、按键离开寒圈免伤、没有冻结，以及真实残墙在150触发距离内阻止霜卫起手。每图37根奖励只记一次；活后代阻止提前完成，后代不增加根奖励/XP；全清后按原8/12碎片结算，重复死亡与领奖不复制奖励。schema61仍合法。怪物、攻击、Main、掉落、保存及根/后代账目实现源码保持基线字节。

Main为headless实际场景检查。截图是本地Chromium中的生成F8 HTML，不声称原生F8按键或游戏画面截图；favicon404不影响页面功能。

## 探针过程记录

- 初版生成测试将返回void的检查方法用于条件判断，Godot解析失败；改为返回bool后，完整265组与9次生成完成。失败日志保留在 `generation-initial-parse-error.log`，不算通过。
- `main-solo.log`为配合探针前的268项单怪/清图检查；最终286项包含同驻点霜卫与灰烬守卫的真实配合。
- 首轮浏览器脚本的标题选择器误留“雷圈”字样，等待超时；改为实际“内廊霜卫与灰烬”后通过，原失败保留在 `browser-initial-selector-error.log`。

## 复核

在独立XDG目录运行，Main每次换新的 `/tmp/godot-ruins-frost-main-*` 路径：

```sh
XDG_DATA_HOME=/tmp/godot-ruins-frost-generation XDG_CACHE_HOME=/tmp/godot-ruins-frost-cache timeout 30 godot --headless --path . --script res://tests/ruins_corridor_frost_test.gd
XDG_DATA_HOME=/tmp/godot-ruins-frost-main-new XDG_CACHE_HOME=/tmp/godot-ruins-frost-cache timeout 45 godot --headless --path . --script res://tests/ruins_corridor_frost_main_test.gd
python3 tools/verify_ruins_corridor_frost_reference.py
python3 tools/build_reference.py --check
python3 docs/qa/ruins-corridor-frost/browser_check.py
```

`inspect.gd`已固定读取原版生成器，可复核变更前的组合。导出只读取本次规则，精确合并当前地图描述和一个独立规则对象。未执行全套、600秒检测、Windows导出封包或模型工作。
