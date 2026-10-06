# v0.66 F8 符印伏击资料验证

本批只新增符印伏击元数据、9组生产Compiler代表状态、可见说明与交叉链接。旧技能零至双辅助示例不纳入伏击穷举。未重新运行历史战斗套件或另造展示世界。

执行入口：`python3 docs/qa/v066-reference/run-reference-checks.py export`、`build`、`verify`。每阶段保留命令、退出码、耗时、错误行、执行前SHA256与期间输入变化。导出使用临时独立XDG，已完成导入的项目直接运行，不重新导入，也不读取或写入玩家存档。

代表状态使用新建Canonical模型的真实战斗快照，逐行仅改变辅助选择，通过生产`Compiler.compile_group`得到最终trap、burn、shock和critical配置。每行同时导出不含伏击的对应状态，表内魔力、冷却、范围与命中直接读取结果。

聚焦检查校验新章节的数据与可见标签、内部锚点及本地文件链接；旧catalog允许新章节、新辅助元数据和获取入口、两技能兼容列表、当前schema字段变化，其余语义必须保持。覆盖报告、CSS、JS、图片清单与旧61＋68张PNG须保持原字节，新增F8符印PNG须逐字节等于运行素材。

本批不重新验证历史机制，也不把编译预览当成实际战斗、自然截图或Windows性能结果。完整功能合同见[符印伏击规则](../../AMBUSH_SUPPORT_RULES.zh-CN.md)。

## 最终结果

- 同源Godot导出23.578秒、HTML构建0.512秒、确定性重建0.510秒、聚焦检查2.803秒，全部exit0，无错误行或输入漂移
- 9组生产Compiler前后状态、102个HTML权威数值及实际可见文字精度通过；全部内部锚点和本地文件链接有效
- 相对b2bd4a1，旧catalog只允许29处新章节、辅助元数据/获取入口、技能兼容列表与当前版本字段变化，既有技能示例与辅助program全部保持
- 源执行覆盖JSON、冻结26枚里程碑奖励身份、所有旧装备/词缀/掉落数据保持
- 旧61张运行时PNG与68张图鉴PNG逐字节保持；新增后为62与69，F8符印副本逐字节等于原图；CSS、JS和图像清单保持

[聚焦结果](focused-reference.stdout.log.txt) · [保全收据](v065-preservation.json) · [导出记录](godot-export-result.json) · [构建记录](build-result.json) · [确定性检查](build-check-result.json) · [聚焦执行记录](focused-reference-result.json)。

导出完成后另有字体补字工作；字体不参与此导出数值和页面模板输入。本批未修改生产UI、运行时、字体、工程版本、项目README或CHANGELOG，也未提交或推送。
