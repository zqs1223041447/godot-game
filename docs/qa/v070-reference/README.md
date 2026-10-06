# v0.70 精准技艺 F8 资料验证

基线为`d25717c4485bf36688df36460f2c85ebb11b7623`。本批只新增精准技艺章节、当前版本元数据与63620的当前执行/可达状态，并纠正旧坚决技艺章节中未标明年代的“尚未开放”说明。旧数值、构筑、技能示例、原始源数据、中文映射文件和图片须保持。

## 同源夹具与只读生成

F8直接使用[实际Main验收](../v070-gameplay/acceptance.json)确认SHA256的三对fixture：selected-above、selected-below、refunded。已点高于阈值与退款后使用同一短刃及相同已装备物品；已点低于阈值来自实际生命装备切换。最终A/L分别为284/141、284/358、284/141。

每个原始JSON经过当前Canonical Rules和SourceTree完整校验，在内存Model重建。先经当前Rules.decode恢复规范整数类型，get_stats和basic/cleave/tornado三种实际cast再以与实际Main相同的full-precision JSON边界比较，必须与同场景期望JSON完全相同。导出不创建装备、不重选词缀、不另造路线；保存次数为0，fixture前后SHA256保持。来源是已通过实际Main的切片，F8未重跑Main或完整历史套件。

[运行入口](run-reference-checks.py)分别以`export`、`build`、`verify`记录命令、退出码、耗时、输入SHA256、错误行与运行中输入变化。使用父任务已完成的统一Godot导入，独立临时XDG，完成一次成功的完整数值导出；构建同时做一次确定性检查。导出先验证所有内容，再打开输出，避免失败时清空既有catalog。

## 窄范围验证

[检查程序](check-reference.py)验证三组真实fixture、九个重编译cast、全部命中包与最终暴击率、已点/退款同装备攻击分量的1.40倍及独立爆炸保持、HTML权威数值与实际显示精度、旧锚点与全部本地链接。

保全按完整基线catalog重建明确获准路径后做整体相等比较，不泛化放行历史章节。仅允许新增本章、44→45当前保存及源政策字段、63620当前执行与对应中文未实装后缀。历史坚决技艺blocked例子固定source38，原数据保持。

源覆盖只允许63620由unsupported→full一项，相关三组统计各加减1；七职业可达集合各新增63620，并从各自blocked frontier删除这个叶节点。其他记录、路径、节点、边、精通、覆盖与排序保持。旧运行时/F8 PNG、数据文件、CSS、JS和图片清单逐文件SHA256必须与基线完全相同。

## 执行与初次读入器修正

首次完整收集在新fixture读入器处停止，未写catalog：Godot JSON把所有数值读为float，而Canonical Rules要求规范schema整数。改用现有Rules.decode，未另造转换器、物品或路线。随后只运行三fixture局部预检；默认JSON.stringify对mana_regen舍入与Main的full-precision预期不同，改为完全相同的full-precision序列化边界后通过。没有放宽数值容差或改动实际Main预期。

[首次失败](godot-export-result.json)、[局部预检失败](rehydration-probe-result.json)、[差异定位](rehydration-diagnostic.stdout.log.txt)与[修正预检](rehydration-corrected-result.json)均完整保留；[旧catalog保全证明](pre-export-preserved.json)确认失败后原catalog字节完全未动。修正预检2.571秒通过三构筑/九cast后，才再次执行完整导出。全过程没有重新导入、重跑Main或历史数值套件。

## 结果

[最终完整导出](final-godot-export-result.json)28.304秒、[HTML构建](final-build-result.json)0.519秒与[确定性检查](final-build-check-result.json)0.537秒，全部exit0，无错误行及运行中输入变化。[最终聚焦保全](final-focused-reference-result.json)4.561秒通过，无错误或输入变化；[完整数值及保全收据](v069-preservation.json)和[易读结果](final-focused-reference.stdout.log.txt)保留全部证据。

- 三个已通过实际Main的构筑、九个精确重编译cast、十五次命中和91个HTML权威数值及显示标签全部通过
- 旧3824个锚点全部保留，新增精准技艺后共3825个唯一锚点；全部内部锚点和本地链接有效
- 完整旧catalog只允许39处明确列出的路径变化；源覆盖只允许66处变化，恰为63620一项完整执行和七职业可达集合各新增这个叶节点
- 旧默认构筑和技能数值保持；63张运行时PNG、70张F8 PNG、所有旧数据文件、中文映射、CSS、JS、图片清单均保持原字节，无新增图片
- catalog为13,714,417字节，SHA256为`6ab11d9016a6a117f926d6165b0215377540251a738a1db09553c809d546e820`

同短刃与同装备的成功非暴击普通攻击为已点52.948、退款37.82，恰为1.40倍；暴击率分别0和5%，潜在倍率1.5保持。已点生命装备状态A284/L358，攻击MORE为0而暴击率仍为0。该状态另有装备差异，不能把其31.62直接归因于精准技艺开关。

以上只证明源码资料导出与定向保全，不是Windows、PCK、ZIP、tag或Release验收。

完整规则与早期强势取舍见[精准技艺合同](../../PRECISE_TECHNIQUE.zh-CN.md)。
