# v0.73 霜锁辅助 F8 资料验证

基线为 `70b75bc255c3f54c8365f959c046934e61759f6e`。本批增加一张紧凑冻结规则卡、一张霜锁辅助卡，以及冰霜脉冲、寒意延长和商人的关联入口；复用原卡片、CSS与JS。新增F8图标由原构建器按字节复制现有霜锁源图，不重新生成美术。

## 同源构筑与时间

[实际Main通过收据](../v073-gameplay/acceptance-summary.json)的328项检查与两份冻结文件是输入依据：[合法schema47构筑](../v073-gameplay/fixtures/selected.json)和[完整预期](../v073-gameplay/fixtures/selected-casts.json)。导出先核验SHA256并严格解码完整存档，再只读重建Canonical；stats及普通攻击、霜锁冰霜、同快照无辅助冰霜的三个完整cast必须逐项匹配。没有另造装备、改写文件、存盘或重跑Main。

卡片显示原五弹、两次穿透、3秒移动减缓及4秒冷却保持，单次非暴击、无防御主命中从22.1变为16.575，魔力从16变为19.2。这不是DPS。普通/魔法0.60秒、稀有0.35秒、首领0.20秒及解冻后1.50秒免疫直接取冻结策略。四种状态与跨解冻帧示例调用FreezeRuntime：普通敌人0秒准入，0.50至0.75秒这一帧只有后0.15秒推进局部行为。

说明明确区分当前elapsed结算准入、下一敌方阶段暂停与不撤销已结算攻击；自主移动、接触攻击、预警/恢复/双响暂停，原圆心、蓄力和pulse接续。外力、分离、燃烧/感电及护盾恢复继续，冻结不刷新、不叠加。卡片还列出100目标上限、死亡和场景清理、快照、寒意延长互斥、4碎片购买和无赠物迁移。

## 精确保全

旧v0.70三份schema45构筑先经冻结decode_v45验证，再依生产迁移45→46→47；旧v0.72五份schema46构筑使用decode_v46和46→47。全部只在内存改变version，原文件、stats、抗性和24个完整cast保持。旧固定版本检查仍是历史收据，不能改成“当前版本”后宣称历史整批重跑。

[集中检查](check-reference.py)从v0.72完整catalog仅重建28条明确变化路径：新辅助、同源例子、图鉴章节、正式与测试供应，以及当前schema标签。其他旧技能例子、默认装备、历史章节、源树、怪物、掉落和制作内容须整体相等；装备词汇仍46、源政策仍45、正式奖励身份数仍26，默认构筑没有新石。

[完整保全收据](v072-preservation.json)确认32个权威数值及标签、全部3831个旧HTML锚点、两个新锚点和所有本地链接有效。133张旧PNG、原字体、完整data来源、旧fixture/expected、CSS、JS与图片清单保持原字节。source-tree-coverage.json的SHA256仍为 `32491261ca5e67d7cb479b6dac1ed327b428adaf7d691ba566b2baa695d1c6de`；运行器同时核验它和旧F8图片的mtime，均未改写。

新图仅为运行时源图和一份F8原字节副本：1254×1254 RGBA，SHA256为 `dad5f51c2f10b2ca932ba0fe5a4f3ed608e94eea41c30e6392af964b4450e673`。512上限和mipmap导入配置由父任务验证，本步骤不另行导入或改图。

## 运行与受影响重试

[运行入口](run-reference-checks.py)使用已有共享导入，记录输入哈希、输出、退出码、错误行及运行期间源码变化。[唯一Godot导出](godot-export-result.json)29.308秒、exit0；[HTML构建](build-result.json)0.576秒和[确定性检查](build-check-result.json)0.521秒均通过。输入执行期间未变，覆盖JSON和所有旧F8 PNG的内容与mtime保持。

[初次Python集中检查](focused-reference-result.json)发现检查器漏掉既有商人preview中的空category字段；修正预期后，仅重试[Python集中检查](corrected-focused-reference-result.json)，4.111秒、exit0。初次失败日志保留；没有第二次Godot导出、HTML修改、Main或共享导入。

这些收据验证源码资料与静态页面，不等同于浏览器实际渲染/点击、原生或Windows启动、PCK/ZIP/tag/Release验收。

[霜锁辅助说明](../../FROST_LOCK_SUPPORT.zh-CN.md) · [冻结合同](../../FROST_LOCK_CONTRACT.zh-CN.md)
