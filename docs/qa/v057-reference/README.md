# v0.57 天赋可见文本同源图鉴验收

结论：F8离线图鉴的天赋展示接线完成，集中资料检查通过。唯一一次Godot导出14.628秒、exit0、无错误行，导出前后生产来源指纹一致；HTML构建、确定性构建、最终聚焦回归及JS语法检查通过。

## 展示来源与范围

- 新增独立 `catalog.source_tree_localization` 展示键。Godot直接调用共用 `SourceTreeLocalization.node_name`、`display_lines`、`line_status` 与正式分区的 `partition_label`；Python只组装已导出的显示文本，不重写源词句解析、消费者或逐句实现判断
- 3389个有名称记录使用唯一中文映射。第3390个 `root` 是无坐标、不在标准分配图中的空名结构哨兵，保留共用适配器的“节点名称缺失”返回；不造源名、不更改字典，也不把它算作玩家可分配节点
- 2974条独立源句逐一对应唯一映射：388条当前有解析与真实消费者，2586条由共用适配器追加“（暂未实装）”。所有1837处精通选项也逐条使用同一结果
- 39个可见分区包括37个同源升华名和游戏现有的“标准主树”“扩展珠宝分区 · 仅浏览”两个界面枚举；节点类别仍显示中文，包含精通
- 天赋卡片、相邻天赋链接，以及火焰持续伤害、加速燃烧、空间、充能、魔力成本、药剂和暴击规则卡中的天赋名称或原句改为上述中文展示。其他资料中的英文、数值、规则说明和布局保持
- 英文名称、分区和原始词句只保留于权威catalog及隐藏搜索数据；中文名称/说明与英文别名都能检索。固定ID及引用链接保持
- 48823、19686各只标记未实现的那一句，另一句保持已实现；精通36313的加成句与未实现持续时间句分别标记；12738两句已实现但升华节点仍研究/不可分配。逐句标记不放宽完整节点、精通或分区分配门槛

## 旧资料完整保护

`capture-v056-baseline.py`从提供的冻结v0.56最终源码快照读取原catalog、HTML、覆盖报告和图片，不用新生产逻辑重建基线。`v056-reference-baseline.json`保留完整目录及64个旧顶层段的语义指纹、原卡片ID、非本批卡片字节指纹、布局模板与68张PNG指纹。

对完整旧catalog唯一允许的变化为 `game_version: 0.56.0 → 0.57.0`，另允许一个新展示键 `source_tree_localization`。移除新键并还原版本后，直接读取的两个完整Python对象相等，完整目录hash及全部64段hash也相等。因此原 `source_tree` 的英文、ID、几何、连边、精通、execution及其他玩法导出数据全部保持，没有豁免整个源树或火焰/加速燃烧段。

HTML共3416张卡片变化：3390个源天赋展示、7张引用源天赋的规则卡、19张辅助卡的既有自动运行版本句。辅助卡仅精确投影“本游戏原创；运行版本 0.57.0”为旧版本句后比较，其余字节保持。全部3763张旧卡ID、3808锚点和20028链接核对通过；所有素材本地有效，68张原PNG、CSS、JS及 `source-tree-coverage.json` 字节相同。

精确差异见 `catalog-diff-review.json`。

## 命令与记录

```sh
python3 docs/qa/v057-reference/capture-v056-baseline.py /path/to/frozen-v056/docs/reference
python3 docs/qa/v057-reference/run-reference-checks.py --export
python3 docs/qa/v057-reference/run-reference-checks.py
python3 tests/passive_localization_reference_test.py
```

唯一导出及来源指纹见 `godot-export-result.json`、`godot-export.*.log`、`export-source-sha256.json`。初次集中结果见 `python-validation-results.json`；最终四项结果见 `final-python-validation-results.json` 与 `final-*.log`；交付指纹见 `final-artifact-sha256.json`。

聚焦回归最初有两次测试假设修正，失败日志完整保留：首次未允许19张辅助卡自动版本文案；第二次将原本空名的结构root误当成应有非空字典名称。只修测试的精确版本投影与root例外，未为此改生产输出、字典或再次导出。最后把加速燃烧门槛文案中的显示枚举 `partial` 改为“部分执行”，不动权威catalog，再进行一轮短构建/确定性/聚焦/JS检查，四项均通过；最终聚焦回归1.782秒、exit0。

未执行历史全量、600秒、再次工程导入、截图或Windows验收；这里的HTML静态链接/搜索数据检查不替代真实浏览器交互验收。玩法与UI兼容性由本版本各自验收负责。
