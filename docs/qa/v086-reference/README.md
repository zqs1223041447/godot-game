# v086 主动探索 F8 有限更新

基线`eb487876`。只新增一个`exploration_maps`数据段，替换F8当前四图卡与地图装置卡，新增一张探索规则/未来机制边界卡；历史样本和历史QA保持原范围。

## 来源与执行

- `ExplorationMapLayout`提供当前描述、墙体、入口、三组根怪、首领和路标；`WorldView`提供实际3600×2400世界边界
- `ExplorationMapPlan`提供四图I档、空地图词缀、种子861073的脱离当前运行态示例。导出只建立候选，不提交到游戏，不设置角色装备，不修改存档，不重跑Main或战斗
- 正式三档的固定地图等级、费用、完成奖励与特殊词缀门槛来自原`MapCompiler`；首领动作定义仍来自`MapBossProfiles`
- 450唤醒距离取自Main常量；当前Schema50、Source49、Equipment46取自原权威常量
- Main组合验收、原始245项结果、10项输入窄补与独立Plan测试证据只读，导出写入其路径和SHA256；独立Plan的输入清单逐项匹配当前测试和实际Plan依赖源码。Main组合验收必须ok=true、Plan执行必须exit0且无记录错误，之后才允许导出
- 当前F8可见描述读取探索片段；原`MapCatalog`描述与历史编译profile仍在旧JSON段中原字节保留，不进入当前四图卡

主任务完成共享import、实际Main与独立Plan验证并确认源码稳定后，依次执行一次：

```sh
python3 docs/qa/v086-reference/run-reference-checks.py export --main-report=docs/qa/v086-gameplay/acceptance.json
python3 docs/qa/v086-reference/run-reference-checks.py merge
python3 docs/qa/v086-reference/run-reference-checks.py build
python3 docs/qa/v086-reference/run-reference-checks.py verify
```

实际Main路径以`exploration-fragment-result.json`所记录命令环境及片段证据为准；命令如使用不同路径会在最终结果记录中说明。导出与结果文件独占创建，已有输出不静默覆盖。导出一次，静态结构/来源/保全核对一次；不调用全量`tools/export_reference.gd`、不重新生成图片和源coverage。

每阶段记录命令、退出码、耗时、错误行、输入SHA256、运行中源码是否变化，以及旧PNG/源coverage的内容与mtime是否保持。`check-reference.py`在同一次静态校验中检查HTML生成一致性，无需另跑全量构建验证。

## 保全与静态核对

`merge-fragment.py`从基线catalog原字节插入新片段，只将基线中仍为0.83.0的顶层`game_version`更新为0.86.0；`save_version`与所有旧顶层字段保持原始token。`catalog-format-preservation.json`列出原始段保全情况。

静态检查核对四图全部初始实体、独立根身份、stable spawn key、标准奖励路线、墙体足印、入口、路标、世界边界与三档经济；可见地图卡不得再包含靠近木牌才出生或清完根怪后才生成首领的旧规则。所有旧锚点与本地链接继续有效。地图以外的旧卡逐字节比较；只因当前游戏版本标签变化的卡单独列出，不笼统宣称全部旧卡不变。

`preservation.json`列出实际替换卡、原卡保全数、版本标签差异、旧资源与PNG数量、Main/Plan证据指纹和四图静态布局数量。除catalog/index外的全部旧`docs/reference`文件按基线字节比较，不新增PNG。

## 结果与范围

- 一次有限Godot导出：`exploration-fragment-result.json`，3.229秒、exit0、零错误
- 一次原字节合并：`merge-result.json`，1.135秒、exit0
- 一次HTML生成：`build-result.json`，1.011秒、exit0
- 一次静态/来源/结构/保全检查：`focused-reference-result.json`，4.951秒、exit0、零错误
- 83个旧catalog顶层段原始token保全；12个正式持久profile逐项等于历史导出；Schema50/Source49/Equipment46未变
- 3772张旧卡逐字节不变；22张仅当前游戏版本标签变化；5张当前地图/地图装置卡替换；新增1张探索规则卡
- 3844个原锚点保留，所有本地链接有效；77个旧reference资源、其中71张PNG与源coverage原字节保全，没有新增PNG，各阶段PNG/coverage的mtime也未变
- 同源图检查4个3600×2400世界、9处墙体、136个真实初始实体、16块路标与4处入口，所有初始点满足850入口净距
- 所有当前卡扫描延迟出生和首领后置门槛措辞。剩余“据点”命中仅为雾羽按组物种名额、源怪物移动current编排入口，语义仍适用，无需扩写其他历史卡

Main来源为[组合验收](../v086-gameplay/acceptance.json)：[原Main结果](../v086-gameplay/main-result.json)245项，244项首轮通过，唯一合成鼠标坐标夹具失败原样保留；[10项输入窄补](../v086-gameplay/input-result.json)全部通过，生产源码与首轮输入指纹一致。复用原244项并补证唯一失败，不记成255个独立场景，不把原failures=1改为0。四图实际入场记录在片段中逐字段对应原报告，原报告原件SHA256严格保留。

独立Plan采用`plan-attempt02-result.json`与其输入清单，247项、0失败、4.555秒。资料检查逐项匹配测试及实际Plan依赖源码，导出未重跑该套测试。

独立Plan示例是静态候选数据，不是玩家自然战斗或装备取舍结论。实际Main测试覆盖以其报告为准。本批资料校验不包含600秒稳定性、原生F8视觉验收、安装包或Release，不重写旧批次验证结论。
