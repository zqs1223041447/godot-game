# 与自然合一与当前56：F8最小同步

已合入实现基线：`dbfbbf42457fe3f49a50fe232b5411c1e37c9f72`。独立文档分支 `codex/one-with-nature-reference`，本提交供审查，未合并main。

从现有 `Exporter.source_tree_reference/source_tree_localization_reference` 与 `Coverage.build_report` 读取当前节点/中文/执行状态/普通拓扑可达，有限只读进程最多40秒，使用独立 `/tmp/godot-one-with-nature-reference.*` XDG，不读取玩家存档、不执行事务或战斗验证。`fragment.json`和`export.log`记录同源导出；既有JSON结构定位工具仅合并精确相关字段，不重导整份运行时catalog。

修改范围：

- 节点15842卡片名称“与自然合一”，完整24%攻击元素INC已实装；说明与12%及装备同属性加算，之后乘独立MORE，保留原8%三抗及24%攻击暴击提高。原始英语、源数值、邻接、位置及其他效果保持。
- 15842开放后，原12%节点18670可沿它达到；只移除已过时的“不能普通连线分配”说明，仍明确合法连接/点数/位置资格。18670和30894的邻接链接显示新名称。37504等未实装邻居仍灰锁，其他词缀没有开放。
- 当前存档/源政策55→56的八张规则卡同步版本；其中 `rules-source_tree`补旧55完整验证、`.v55-backup.json`原字节备份、仅改版本、失败不发布、冲突备份不覆盖和人工回退边界。其他七张规则卡仅当前版本标注变更。
- 迁移保留分配、点数、物品、技能和旅程字段，不赠物/点；进行中地图字段保全不等于恢复整场战斗，怪物/弹体/状态计时不由迁移重建，启动离场仍按原规则。旧55程序拒绝56，原55备份不含升级后进度；保存前外部修改检查不承诺涵盖任意并发时序或断电级持久性。

`canonical.save_version=47`及既有历史章节/快照保留。源码树原始SHA、坐标、连线、起点和点数不改；未新增卡片或图像。

`verification.json`静态一致性结果：**1张目标卡＋2张直接关联卡＋8张当前规则卡；其余3805张卡逐字相同，250个相关本地链接有效**。覆盖报告仅节点15842执行记录和派生effect/class可达变化；每个职业普通拓扑可达713→715，新增ID严格为15842/18670。此统计不应用点数预算，不声明所有职业当前存档均能立即分配。所有其他覆盖节点记录相同。

限定校验同时核对生成HTML、局部merge幂等、原抗性/暴击grants、未实装邻居、历史canonical及628份已跟踪运行时/素材/场景/项目文件字节保持。仅文档、导出合并工具和相关卡片模板变化；原361/0事务/战斗验证未重跑，无浏览器或鼠标验收声明，不导出游戏。

复现：独立XDG下运行只读 `tools/one_with_nature_reference.gd`，传入fragment和coverage输出路径；然后运行 `tools/merge_one_with_nature_reference.py`。使用原 `tools/build_reference.py::build` 和现有art manifest生成index（不重导图片），最后 `python tools/verify_one_with_nature_reference.py`。验证以固定实现基线比较，报告包括生成文件及工具SHA256。
