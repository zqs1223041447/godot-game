# v0.74 单条源移动绑定 F8资料验证

基线为 `a1dd1acf` 的v0.73 F8资料。新增当前 `source_gale_stride` 机制和单条源移动规则卡；23条历史定义保持。旧固定 `gale_stride` 与当前源绑定分别标注，共享规则卡明确仅有这一条当前源绑定。既有怪物、技能和构筑示例继续作为历史显式调用。

## 同源授予与预算

导出器读取真实 `SourceMonsterGrants.resolve`，以当前 `SourceTreeRuntime.line_effect` 核验玩家、怪物的相同类型化授予。来源身份、原始行 `4% increased Movement Speed`、节点63417、从0计数的行索引1和源执行政策45均可追溯。只授予移动速度提高，不带入护甲或升华资格。

12组速度对照在第1、6、10、15波通过实际 `MonsterCatalog.make_enemy` 生成，覆盖巡游体、掠行体和重壳体，均为同一蓝色稀有度。比较无移动词缀、旧固定+3.12和新源4%提高；不是自然生成或地图阵容分布。第1波重壳体仅是工厂预算，普通抽签第2波才允许该物种。完整数表见 [单条源移动合同](../../SOURCE_MONSTER_MOVEMENT.zh-CN.md)。

这12组相对旧投影的速度变化为−2.82828%至+1.44745%；第10波巡游体的新旧速度均为81.12。这里没有综合实战难度评分，也未改变奖励、地图经济或其他怪物数值。

## 精确保全

[v073基线快照](v073-baseline.json)在本批修改导出器前记录catalog全部章节散列、23条旧定义、3833个旧HTML锚点，以及184个PNG、字体、来源、历史fixture、CSS、JS和覆盖JSON文件的散列。

[最终集中保全](v073-preservation.json)确认76个旧catalog章节、23条旧定义完全保持；仅允许游戏版本、第24条机制和一个新源移动章节变化。68个HTML权威值及显示标签通过，3833个旧锚点全部保留，新增且仅新增 `mechanisms-source_gale_stride` 与 `rules-source_monster_movement` 两个锚点；所有本地链接有效。135张旧PNG全部保持，没有新图片或字体，源覆盖JSON保持原字节。

存档结构47、装备词汇46、源执行政策45保持；没有迁移、赠物或新的图鉴美术。

## 执行与受影响修正

使用父任务的统一导入。[唯一完整Godot导出](godot-export-result.json)29.002秒、exit0，无错误和运行期间源码变化，覆盖JSON与旧F8 PNG内容及mtime保持。首次HTML构建及确定性检查通过。

[第一次集中检查](focused-reference-result.json)发现新章节误引用历史 `Build.SAVE_VERSION=13`，当前全局实际结构仍为47。修正为 `Canonical.Rules.VERSION` 后，只[重新生成新章节](source-chapter-correction-result.json)，2.888秒、exit0，没有第二次完整导出。该窄修正经过Godot JSON解析再写入旧章节，使原整数标记变成浮点，[受影响构建](corrected-build-result.json)据此拒绝。随后[校验v073原文件SHA256并恢复全部历史JSON类型](json-number-restoration.json)，仅合入真实重新生成的新章节及新机制定义；未手抄预算值。故障脚本与日志仅供复核，不能脱离相应基线恢复步骤单独重跑。

[第二次集中检查](corrected-focused-reference-result.json)的全部数值和保全检查已通过，最后发现共享规则卡的后置覆盖仍显示旧文案。修正实际生效的卡片后，[最终HTML构建](final-build-result.json)0.591秒、[确定性检查](final-build-check-result.json)0.587秒及[最终集中检查](final-focused-reference-result.json)1.710秒全部exit0。失败收据保留，没有改写为成功。最后仅把报告执行范围明确为“一次完整导出＋一次新章节窄修正”，[范围说明后的集中复核](scope-final-focused-reference-result.json)1.804秒、exit0；之前成功收据另存保留。

上述检查没有重跑历史整套验收、Main、统一导入、浏览器渲染/点击、原生或Windows启动，也没有PCK/ZIP/tag/Release工作。生产Main和纯规则验证由父任务的独立收据负责。

最终仅以3处JSON值插入/替换保留旧catalog的原始数值与空对象格式，避免无关空白重排；有序类型化JSON与此前已通过结果完全一致，HTML字节及确定性检查通过。保留变更前收据，最终catalog哈希按此纯格式保全更新，未再次运行游戏或资料导出。见catalog-format-preservation.json。
