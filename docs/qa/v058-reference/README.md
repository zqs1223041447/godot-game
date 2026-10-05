# v058 图鉴集中验证

结论：F8“心灵升华与魔力先承伤”规则卡及源天赋关联完成，集中资料检查通过。唯一一次 Godot 导出 14.242 秒、exit0、无脚本或引擎错误行；生产来源指纹在导出前后及最终检查时均一致。初次和最终 Python 构建、确定性 `--check`、新增聚焦测试及 JS 语法检查均通过。

## 生产导出与显示

- `catalog.mana_guard` 来自实际 `SourceTree.node_effect`、`CanonicalGameState.get_mana_guard_profile` 和 `Defense.incoming_source_hit / incoming_burn / settle_with_mana`。Python 仅读取结果生成 HTML，不重新实现结算
- 6种独立初始资源状态分别执行 hit / burn，共12条。防御后100：无盾足魔40魔60血、仅10魔10魔90血、30盾后28魔42血；另含全盾、空魔和致死/过量
- 混合伤害用实际护甲、三抗封顶与15%感电之后分摊：258.75损伤→50盾、83.5魔力、125.25生命
- 三个旧入口比较省略与显式0参数的完整 Godot Variant 字节；均不添加新魔力字段。冻结v57全输入/失败优先级矩阵由 [纯共享防御证据](../v058-rules/README.md) 另外证明
- 七职业受支持最短路线均通过完整构筑候选验证，并由模型导出40%权威profile；贵族11、野蛮人17、游侠25、女巫7、决斗者21、圣堂武僧7、暗影17点。该导出不调用逐点分配、不写档；实际分配/退还与严格旧档保护属于 [迁移集中证据](../v058-migration/README.md)
- 源34098唯一新增完整普通节点；42144/922的8%/10%句可逐条执行，混合节点仍整体锁定且在未开放分区。完整源覆盖报告 `integrity.ok=true`，七职业普通可达数均689
- 124个带 `data-mana-guard-value` 的可见数值逐个与生产导出核对。卡片明确静态资源预算不是实战DPS，魔力不足落生命，魔耗不混入生命损失或浮字，schema35新文件不冒称旧34原字节
- 源天赋34098、42144、922均链接新规则卡；通用防御及战斗浮字说明同步交代可选魔力分摊。没有新增图像

实际场景接线不在本参考导出中重复运行；证据见 [消费者最终证据清单](../v058-consumers/final-evidence-manifest.json)。本目录不把别处运行的场景、分配或原生界面检查称作自己的测试。

## 冻结v57精确投影

基线为冻结发布提交 `3718d74691f3a7f9e2280fc26419c093b26ee4ac` 的 `docs/reference/catalog.json`，源文件SHA256与所有顶层分段的规范JSON SHA256均保存于 `v057-reference-baseline.json`。

审查后允许的完整差异如下：

- 新增顶层 `mana_guard` 生产证据分支
- 14处派生统计新增默认0的 `damage_taken_from_mana_before_life`；仅允许键名匹配且值严格为0
- 20处运行/保存显示版本由v0.57→v0.58或34→35
- 10处源执行叶组仅属于34098、42144、922的grants/status/supported/unsupported
- 17处显示metadata：三条8/10/40%句的支持状态及中文文本、三个节点显示文本、34098中文名“心灵升华”、雷纹巡逻已有1秒15%感电的文字纠正

移除明确新增键、还原逐项列明的前后值后，全部旧顶层分段和整份目录规范JSON哈希与冻结v57精确相等。旧伤害包、旧技能/辅助数值、装备词池/词缀/掉落、物品、地图、奖励和旧源结构没有其他漂移。新版本文件本身不宣称字节一致；新节点真实战斗行为也不声称与未分配旧构筑等价。

捕获脚本对版本、指定三节点、指定三句、固定显示文案设有窄范围白名单，遇到其他机械或结构差异直接拒绝。完整差异见 `catalog-diff-raw.json`；分类计数见 `projection-summary.json`。

## 静态交付保护

- 61张源素材、68张图鉴PNG逐路径与冻结v57 SHA256完全相等
- 全部旧article保留，无重复ID，站内锚点/本地证据链接/素材路径有效，没有网络依赖图片或脚本
- `tools/build_reference.py --check` 确认HTML与最终模板/运行时数据一致
- `node --check docs/reference/reference.js` 通过；未宣称浏览器交互或新截图验证
- `git diff --check` 通过

## 运行证据

- 唯一导出：`godot-export-result.json`、`godot-export.stdout.log.txt`、`godot-export.stderr.log.txt`
- 导出输入：`export-source-sha256.json`
- 首次四项：`python-validation-results.json` 和对应 `.log.txt`
- 最后补充通用防御/浮字的交叉说明后，最终四项：`final-python-validation-results.json` 和 `final-*.log.txt`。仅重建/检查Python和JS，没有重复Godot导出
- 最終交付文件：`final-artifact-sha256.json`

复查命令：`python3 tests/mana_guard_reference_test.py`、`python3 tools/build_reference.py --check`、`node --check docs/reference/reference.js`。不运行全历史集合、600秒基准、额外import或截图。
