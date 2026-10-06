# v0.62 护甲闪避图鉴验证

本批只扩展灰烬皮甲的全局护甲、闪避前缀及对应F8资料。基线为已发布v0.61 `d884caea7a2260f4535ba4da2d7e005e6df006d4`。

`catalog.json.defense_rating_affixes`直接调用当前EquipmentCatalog、CanonicalGameState、SourceTreeRuntime、AttackHitRules与DefenseRules。四个合法装备实例展示五选三取舍；42个职业/闪避端点组合读取真实角色最终值；四个地图攻击示例读取当前怪物、波次、首领与凶猛倍率。网页只展示导出的结果。

原三抗卡保留其资源/三抗预算和显式词汇37的制作见证，同时明确当前防御池39与五个可选前缀。原源树政策38、执行集合与覆盖保持；原61张运行时PNG和68张图鉴PNG以发布基线逐文件比较。

## 实际检查

- `run-reference-checks.py export`：Godot运行时导出与同次源树覆盖导出，保留输入SHA256、标准输出、退出码、耗时和输入漂移检查
- `run-reference-checks.py build`：HTML构建、确定性重建及既有JavaScript语法检查
- `run-reference-checks.py verify`：当前同源档位、合法取舍、真实统计、HTML数值、全部锚点/本地链接、旧内容精确投影及PNG字节检查
- `font-cmap-result.json`、`font-runtime-input-sha256.json`：实际collect_required输入清单与cmap；字体字节不变时沿用v61已验证的1656映射字形与度量证明，不重跑全量字形轮廓

各项机器结果与首次失败如有发生均保留在本目录；最终结果以对应`*-result.json`为准。未运行历史完整战斗、600秒性能或GUI截图验收。

## 结果

全部集中检查首次通过：Godot导出21.377秒，HTML构建0.510秒，确定性检查0.487秒，JS语法0.068秒，聚焦检查3.064秒，均exit0且无输入漂移或错误行。逐项核对168个页面权威数值、3817个唯一锚点及全部内部/本地资源链接。旧catalog仅接受72处明确变化，投影回v61语义SHA256 `55d88d14a8154bcb1a0155904750e6f1d51af4082bb07054d84ab4ba4186c943`；源树覆盖JSON逐字节相同，全部旧执行/中文投影与61/68张PNG保持。详见[v61完整投影证明](v061-projection-preservation.json)。

初始cmap发现唯一缺字“革”U+9769，旧结果保留于[初始字体发现](font-cmap-result.json)。随后同源补这一字，最终1657映射字符覆盖1652需求；[定向字体证明](../v062-integration/font-addition-preservation.json)在0.949秒验证原1656字形、度量、布局、家族与许可保留，以及177份运行时文本SHA未变化。新字体SHA256为`e0a3131d572b7f804e9beecf64dd0c9564af678815ebce1b40039c634b56580c`，导入exit0。此补字没有重跑完整文字收集、全量轮廓扫描、F8或历史战斗。
