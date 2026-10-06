# v0.75 源伤害与生命 F8资料验证

以 `f2427f3` 的v0.74资料为基线。新章节只增加13219:0的伤害提高与52282:0的最大生命提高两条绑定；保留23条历史定义与既有源移动定义。当前共26条定义，3条源绑定，五槽当前政策为 `source_damage_life_v2`。

## 范围与方法

[v074基线](v074-baseline.json)记录79个catalog章节、24条既有定义、3835个旧HTML锚点及186个保全文件散列。135张PNG、字体、CSS/JS、来源文件、旧fixture与源覆盖JSON纳入保全。

Godot只[导出新片段](source-fragment.json)，没有完整catalog导出，没有把旧14 MB JSON读回Godot。Python [窄合并](merge-fragment.py)从逐字节验证的Git基线插入两条新机制、新规则章，并更新移动章节的当前数量、当前池和三代政策信息；旧移动预算、旧Gale单条定义与其他历史字段原样保留。[格式保全收据](catalog-format-preservation.json)列出全部改动字段。

## 真实工厂与显示检查

导出器核对来源身份、原始行和当前解析器的唯一类型化授予，验证玩家/怪物数据相同。最大生命的提高模式单独由capacity_increased消费，不混为固定+0.05。旧poe_global_damage对怪物仍拒绝。

12组实际工厂对照覆盖第1/6/10/15波的三种基础物种；第1波蓝色，其余金色。每行的生命与伤害分别采用独立单词缀，不把蓝怪当作两词缀样本。另有两项“先固定后提高”的金色显式组合验证。数值和边界见 [完整合同](../../SOURCE_MONSTER_DAMAGE_LIFE.zh-CN.md)。这是地图倍率前的工厂预算，不能解释为自然阵容分布、DPS或全局平衡结论。

## 执行记录

使用父任务已完成的共享导入，本资料任务没有重复导入。第一次窄导出在GDScript不支持的格式符处停止，2.241秒、exit−15，失败收据保留在 [source-fragment-result.json](source-fragment-result.json)。修正格式符后，[窄导出](corrected-source-fragment-result.json)2.289秒、exit0，无错误或运行期间源码变化；原PNG与源覆盖JSON的内容和mtime保持。没有重新导出完整历史资料。

后续窄合并、HTML构建、确定性检查及集中保全结果分别见 [merge-result.json](merge-result.json)、[build-result.json](build-result.json)、[build-check-result.json](build-check-result.json)、[focused-reference-result.json](focused-reference-result.json)。最终集中报告见 [v074-preservation.json](v074-preservation.json)。

最终窄合并1.529秒、HTML构建0.628秒、确定性检查0.664秒、集中验证1.806秒，全部exit0。集中验证通过88个HTML权威数值与标签、12组真实工厂预算、两项固定后提高组合、76个完整历史章节、全部23条历史定义及旧Gale定义；移动章节旧字段除当前池/总数外保持，原12组预算不变。3835个旧锚点全部保留，仅新增两机制与一规则共3个锚点，全部锚点及本地文件链接有效。135张PNG与186个保全文件保持，没有新美术，源覆盖JSON原字节保持。

存档结构47、装备词汇46、源执行政策45保持。检查只覆盖本批F8资料的来源、数值、格式、链接与保全；没有重跑历史战斗全套、Main、浏览器渲染/点击、原生或Windows启动，也没有美术生成、PCK、ZIP、tag或Release。生产运行时与纯规则验收由父任务的独立收据负责。
