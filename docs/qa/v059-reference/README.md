# v59 最大抗性同源图鉴、投影与字体证据

基线：v58 `71f4863fda4b02d1afd17db4cfa958c85139491f`。本目录只覆盖离线资料和字体复用；不替代其他工作项的规则、真实分配/退款、迁移与游戏消费者验收，也不重跑历史战斗或原生画面。

## 当前交付

- `tools/export_reference.gd`新增`elemental_resistance_caps`，使用当前`SourceTree`政策36、`Defense.resistance_profile`、真实命中/燃烧入口和`CanonicalGameState.get_resistance_profile`导出。
- 默认75%、安全83%，原始40/75/83/100与超安全加成边界有权威raw/current-cap/effective及独立100损伤示例。HTML只投影数值，不重新计算抗性或源词句支持标签。
- 恰好12个新完整标准节点；图外和混合节点继续使用完整效果与标准图准入门槛。34383、7137、61283、1727是精通效果ID，按宿主节点查找，不能当成普通节点ID。61283还与一个无关普通节点重名。
- 复用`v059-source/allocation-witness.json`，73点/69级候选通过生产完整构筑校验；原始火/冰/电91%/83%/83%，当前上限与有效值均83%，无写档。此处不重复真实逐点交互测试，也不宣称最省点。
- F8旧火抗演算明确标为默认上限示例；源三抗描述与地图庇护描述区分玩家可提高上限、自然怪仍无最大抗性加成。当前装备供给仍是灰烬皮甲15%+护火25%=40%原始火抗，无冷电装备供给。
- 更新`docs/ELEMENTAL_RESISTANCE_CAPS.zh-CN.md`。没有新增图片、字体、装备或资源。

## 执行与失败保留

所有命令从项目根目录运行。每个`*-result.json`保存实际命令、退出码、耗时、脚本错误与输入变化；对应输入SHA256、stdout/stderr不覆盖。

| 记录 | 实际结果 |
| --- | --- |
| `godot-export` | 进程exit0但有SCRIPT ERROR，明确失败；原因是把精通效果ID当成节点ID。原始错误完整保留 |
| `corrected-godot-export` | 修正查找后14.936秒，exit0、无错误、输入无变化 |
| `build` / `build-check` | HTML生成与逐字节再生成核对，均exit0 |
| `javascript-syntax` | 既有离线脚本Node语法检查exit0 |
| `focused-reference` | 检查器误把既有无src的内联script当成空资源，exit1；原检查器保存在`initial-check-reference.txt` |
| `corrected-focused-reference` | 排除内联脚本后2.632秒，exit0、无输入变化 |
| `font-coverage` | 实际字体工具89.647秒exit0，报告ok；宽范围包装器检测到两个非字体输入导出脚本并发变化，包装器exit1。按实际字体输入范围另行核对，见下文，不把它隐去或重写成全程无变化 |

重现生成命令为`python3 docs/qa/v059-reference/run-reference-checks.py export --prefix <新的唯一前缀>`；静态生成检查使用`build`阶段。本批已完成上述生成，不需要为了历史机制再次运行。证据禁止覆盖，复查须使用新前缀；独立投影检查也不覆盖已存在结果。

## 明确变化与旧数据保留

`v058-projection-preservation.json`记录233处经范围校验的差异：新增最大抗性section 1处、默认零stat 63处、版本20处、源执行89处、动态中文标签55处、显示文案5处。移除或还原这些精确路径后，完整catalog的规范化JSON SHA256与v58一致；不宣称当前完整catalog与旧版本原字节相同。

两侧都先用相同JSON解码方式（`parse_int=float, parse_float=float`）读取；规范化哈希排序对象键。数组顺序仍保留，不混淆整数/浮点表示或字典键序。

检查同时验证3390源记录的原文、图、精通等非execution字段完全保持，23个本批相关节点的执行变化只有最大抗性grant；12个标准节点新完整，6个混合节点仍partial，5个图外节点虽full仍不在标准图。4类精通效果仍unsupported。59个HTML权威数值逐项与导出相符，所有页内锚点、相对文档和本地资源路径存在。

`v058-art-baseline.json`冻结全部61张原图和68张图鉴PNG的路径与SHA256。当前129张全部原字节复用，未重绘、未重编码。

## 字体复用与准确范围

`tools/check_font_coverage.py --json`实际覆盖171个runtime文件与既有固定补充文本：1650个必需字符，1528个汉字；映射1655字符，原874基线字符全部保留。missing、lost_baseline、empty_han和errors均为空；两个既有同源符号回退U+2301/U+25C8保持。

`font-byte-reuse-and-input-reconciliation.json`核对：并发变化仅`tools/export_reference.gd`与`tools/build_reference.py`，二者不在该字体工具runtime扫描范围。实际已哈希输入未变；额外场景/资源/许可输入逐一匹配v58。字体、manifest与许可均原字节复用。

同源完整字体路径：`/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`，SC索引2，SHA256 `b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a`已验证。本批未运行subset，未换字体，未开GUI。

额外只读扫描新F8段落和说明文档也保留原始结果：如果强制使用游戏精简Arena字体，新F8段落中的✧、句、既、采未收录，说明文档中的句、宣、既、猜未收录。F8沿用系统中文字体CSS，不使用Arena字体；这些F8字符在v58图鉴中已存在，未新增运行时缺字。完整同源Noto覆盖这些汉字；✧为既有系统回退装饰。详细上下文见`font-extra-text-context.json`。未把文档覆盖误称为全部Arena覆盖，也未为不属于runtime的QA文档重复扫描。
