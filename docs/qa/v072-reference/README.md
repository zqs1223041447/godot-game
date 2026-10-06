# v0.72 精瞄手套与三抗戒指 F8 资料验证

基线为 `bf794d05f2468ccda22bb170a643839b5aba880e`。本批增加一张紧凑规则卡、四张沿用原模板的词缀卡，并在既有织纹手套与纹刻指环卡片交叉链接；没有新图像、底材、源节点、CSS或JS。

## 同源输入

[实际Main通过收据](../v072-gameplay/acceptance.json)锁定五份原构筑与五份完整预期：精准技艺命中等于生命、超过生命、精瞄与源命中提高、双戒胸甲默认抗性上限、真实源路线83%上限。导出器按SHA256查验并严格解码完整schema46，在内存中重建Canonical；最终stats、抗性profile与普通攻击/裂刃/龙卷三种完整cast逐项与原预期比较，采用相同JSON精度。文件和模型不写盘，不重跑Main，也不另造参考装备。

83%上限例子保留真实73点源路线及其全部原始抗性，不能误写成纯装备90/75/75。只改上限的隔离边界对照留在Main报告，不伪装成可获得套装。四新族和阶级端点直接读目录，六个A284对闪避1600的命中端点调用真实AttackHitRules，不复制公式到HTML。

旧v0.70精准技艺的三份通过文件仍是schema45原字节。导出先调用冻结decode_v45，再migrate_v45，仅允许内存version变化；原stats与9个完整cast仍必须匹配旧Main预期。旧历史固定版本检查仍是对应版本收据，不修改它们的意义或重跑全历史；本批[集中检查](check-reference.py)明确审计这些旧门禁并以完整catalog的精确投影取代当前版本误判。

## 允许变化与保全

[定向检查](check-reference.py)从旧catalog重建允许变化：新四族与新章节、旧词族新增的词池关联、仅手套/戒指的资格扩展、当前装备词汇及schema元数据、新同五底材九槽池，以及canonical_v46的原30%入口替换。其他历史例子、默认构筑数值与技能、旧池/profile、词族元数据、雾羽怪物子树均须整体相等，不允许随意放行整个历史章节。

源政策仍45，source-tree-coverage.json保持原字节。完整原始数据与中文映射、63张运行时PNG、70张F8 PNG、CSS、JS和图片清单也保持原字节。各运行收据另核对覆盖JSON与F8 PNG的mtime，避免相同内容被无意义重写。字体由父任务确认1661字及原字节保全，本步骤不生成新字体或图片。

[运行入口](run-reference-checks.py)只使用父任务已完成的共享导入，分别记录输入哈希、输出、退出码、错误行、运行期间源码变化和保全文件状态。执行范围为一次Godot导出、HTML构建、确定性检查与集中定向检查；失败只修受影响步骤，不额外导入或再跑Main。

## 结果与受影响重试

[Godot完整导出](godot-export-result.json)首轮29.004秒、exit0；输入执行期间未变，无错误行。初次HTML构建/确定性0.569/0.584秒通过。Python集中检查先发现检查器把affected_skills、other_consumers这两个导出派生字段误当原始族元数据，修正过滤后，第二次发现原最大抗性章节的当前冰、电来源列表合法增加ring_rimeward、ring_stormward。只允许这两个确切路径，并把该章节将所有当前来源写成“v0.60新增”的旧文字改为分清v0.60胸甲与v0.72戒指。

因此只复验受影响的Python步骤：[最终HTML构建](wording-build-result.json)0.597秒、[确定性检查](wording-build-check-result.json)0.563秒、[最终定向检查](final-focused-reference-result.json)4.162秒全部exit0；没有第二次Godot导出、共享导入或Main运行。前两份失败收据保留，错误均限于检查器投影假设；最终导出数据与原Main预期始终匹配。

[完整保全收据](v071-preservation.json)确认65个权威数值与显示标签、全部旧3826锚点、五个新锚点与所有本地链接通过；67条catalog精确变化路径均被逐项重建。新Main五份构筑/15个完整cast、旧v0.70三份构筑/9个完整cast匹配，源覆盖与全部133张PNG原字节保持，各步骤覆盖及F8图片mtime也保持。

Main最终去重1588项来自首轮七段加仅accuracy段补强复验；十份fixture/expected SHA256均未变。本F8导出收据保留当时的acceptance输入哈希，不把之后的计数补强冒充重跑整批，更不因此重复Main或导出。

这些记录验证源码资料与静态页面，不等同于浏览器实际渲染/点击、原生或Windows启动、PCK/ZIP/tag/Release验收。

[手套与戒指合同](../../GLOVE_RING_AFFIXES.zh-CN.md)
