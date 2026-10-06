# v0.78 三元素转换与穿透 F8 窄更新

基线 `07922581`。只新增统一转换/穿透章节，更新当前 game0.78、save48、source48、四句源效果对应的13条节点/选项执行状态与同源中文实装标记，以及五个当前怪物源定义的溯源metadata。历史数值章、默认构筑、旧技能例子、来源英文、拓扑、中文映射文件与旧图片保留。

## 实际来源与一次有用导出

读取 [Main 验收](../v078-gameplay/reference-acceptance.json) 明确通过1803项、0失败的 `zero`、`cold`、`cold-lightning`、`fire-cold-lightning` 四份完整构筑，逐份核对SHA256，再走当前 Canonical.Rules.decode、完整Rules/SourceTree校验与只读Model重建，编译普攻、裂刃、真实龙卷组，共12个cast。没有另造装备或路线，也没有声称Main曾保存逐字段cast期望JSON；导出重编译使用同一已验证快照。

四份都为同一合法稀有短刃。龙卷真实五辅是物理专注、火焰专注、点燃、专注、节能；不是单辅助隔离。短刃局部物理仅由普攻/裂刃消费，龙卷保留自身组装。`zero`仍含两前置notable的30%元素提高和6%穿透，剩余3点；三精通全选使用27点。Main矩阵切换武器会改变未装备武器的背包格位；F8对照的已装备位置、物品内容、技能绑定相同，聚焦验证只允许未装备物品在bag内移位。四份没有穿爆破护符，secondary只是已冻结纯火包对照，不会在当前装备触发，页面明确提示且不计入summary。

[导出入口](run-reference-checks.py)复用父任务的统一import，独立临时XDG，无用户存档接触。唯一成功的窄导出4.078秒，输出新章、13条当前执行状态与四句本地化状态、五条当前源定义，再用权威SourceCoverage.build_report产生当前完整覆盖。全部运行时输入SHA保持，无错误。原catalog不进入Godot，旧大全与历史实战未重跑。

## 原始JSON与历史保全

[窄合并](merge-fragment.py)从Git只读取得精确基线，只替换明确差异span并插入新章；未变的旧数字tokens、整数类型、顺序、空白原样保留。当前五个源定义只允许 `policy_version` 的45→48以及 `source_policy`、`source_save_version` 的45→48，共15项metadata。源授予数值无变化；旧章内actor快照仍为历史，不追溯改写。页面明确历史章中的“当前”是导出当时，不冒充现行政策。

初次合并在上述字符串型policy_version处按较窄的数字字段白名单停止，未写catalog；核对五定义差异确实只有这三类metadata后修正白名单。保留初次失败收据，只重跑受影响的Python合并，没有再导出。

源coverage完整文件来自同一当前SourceRuntime，完整保留源身份、3390记录、2387标准位置、2697内部边；只有两notable与6冷/5电精通选项的执行变化，以及相应统计和七职业可达前沿变化。当前每职业非起点可达707个；拓扑可达不代表能在123点内全取。

## 验证范围

[聚焦验证](check-reference.py)逐个校对HTML的权威数值路径和12位有效数字显示，确认防御前字段与含穿透零抗目标区分、四种抗性边界、每最终类型一条detail、转换来源、燃烧读取最终火焰一次、纯火冻结包保持、四份存档只读、原历史tokens、23条旧机制、数据/中文映射/PNG、旧锚点与本地链接。Python只消费运行时结果，不生产伤害值。

首次聚焦检查把整个背包位置也误当成必须相同，停在两件未装备武器的格位差异；核对它们只是Main正常换装后的bag内移位后，改为所有装备/技能位置保持、仅允许bag内位置变化，保留失败。另在链接检查前修正本章fixture相对路径，不动导出数字。第二次聚焦检查发现22张辅助卡与装备规则卡自动显示全局当前运行版本/存档版本；只把精确的0.76.0→0.78.0和47→48标签替换列入允许范围，其余卡内容仍逐字节检查，保留该次失败。

HTML由 `tools/build_reference.py` 生成并作一次确定性核对；后续只有“未装备护符，secondary当前不触发”的文案澄清，按影响范围重新生成HTML与检查。没有新图像、字体或UI；未跑浏览器、Windows或新native启动，不产生PCK、ZIP、tag或Release。

最终结果见 [数值与保全收据](v077-preservation.json)、[原tokens保全](catalog-format-preservation.json) 及各阶段结果JSON。完整新规则见 [三元素转换与命中穿透](../../ELEMENTAL_CONVERSION.zh-CN.md)。

## 最终结果

最终精确fixture检查3.470秒通过：4份Main真实构筑、12cast、20命中包、100组目标结算、24个转换部分、8个燃烧输入、440个HTML数值和显示标签。全部3841旧锚点保持，只新增统一转换章；3750张旧卡逐字节保持，另23张卡只改精确当前版本标签。76个历史catalog顶层片段原tokens保持，240个受保护文件及135张PNG原字节保持，所有内部锚点/本地链接有效。当前覆盖只改13节点/精通记录，七职业各新增8833与56716，非起点可达707。

[最终聚焦运行](exact-fixture-focused-reference-result.json) · [最终HTML构建](linked-build-result.json) · [最终确定性核对](linked-build-check-result.json) · [唯一运行时导出](elemental-fragment-result.json)。本轮之后只补充这份说明，没有再运行Godot。
