# v0.60 F8、供给预算与字体验收

基线：v0.59提交 `0816322e4c9a53d264bce9c5223810a93ead2348`。本目录只覆盖本批资料投影与字体；不代替规则、迁移、消费者验收，不声称历史战斗全量、600秒压力或新增原生画面验收。

## 结果

- `corrected-godot-export-result.json`：生产目录、合法角色与防御规则导出通过，15.616秒，exit 0，无SCRIPT ERROR与输入漂移
- `corrected-build-result.json`、`corrected-build-check-result.json`、`corrected-javascript-syntax-result.json`：最终HTML生成、一致性及既有JavaScript语法通过
- `focused-reference-result.json`、`v059-projection-preservation.json`：56个HTML权威数值、3813个唯一ID、全部内部锚点与本地资源链接通过；48处明确允许的新增/append/版本投影还原后与v59目录语义完全一致
- `font-coverage-result.json`：既有字体checker运行一次，通过，89.774秒，检查173个runtime文件、1650个所需码点，其中汉字1528；missing/lost_baseline/empty_han/errors均为空
- 61张既有assets PNG、68张既有reference PNG、字体二进制、coverage manifest与source-tree-coverage JSON逐字节保持；未调用字体subset工具

现有两个声明过的fallback符号为U+2301与U+25C8，保持历史状态；不是新增汉字缺字。F8使用系统字体，其文案和QA文本不属于游戏字体runtime扫描范围，不据此强制增大subset。

## 首轮问题与局部修复

首轮 `godot-export-*` 全部保留。导出器新夹具在默认已穿 `guardian_robe` 的模型中直接加入第二件胸甲，触发三个完整构筑断言及后续缺definition错误。Godot进程返回0仍被runner按SCRIPT ERROR正确拒绝。只修导出夹具：先将原胸甲移动到真实可用背包位置，再构造并验证新胸甲的合法装备位置，无写档。

首轮导出输入扫描还把 `docs/reference/catalog.json` 输出路径误列为输入，因此记录该文件变化。runner已明确区分该文件及source-tree-coverage输出，保留实际代码、数据与见证输入；修正后无输入漂移。首轮失败没有被删除或改写，也没有忽略任何真实runtime输入变化。

首轮HTML生成本身通过，但静态锚点检查发现新增链接 `crafting-crafting_rules` 不存在；改为既有 `crafting-calibration_shard`，并为当前胸甲标签、冷电词缀补上三抗规则关联后重建。初版build输入列表误写了不存在的 `assets/art/items/forgeblade.png`，最终build/check记录已修为实际 `assets/art/equipment/forgeblade.png`，且原图/派生图哈希另有完整检查。原首轮build记录保留，最终结果使用 `corrected-*`。

本批总计两次Godot参考导出：第一次失败，局部修正后一次成功。字体checker只运行一次。没有因资料夹具失败重跑玩法消费者，也未改动生产脚本、版本、翻译字典或原图。

## 同源边界

`elemental_defense_affixes` 的档位、资格与formatter直接来自EquipmentCatalog；三组装备先过完整Canonical构筑验证，再读Model的当前resistance profile，三种100点独立命中调用Defense。普通重铸seed 3由真实CraftingRules.operation_plan得出三抗后缀结果；不是掉落概率或每次成功保证。

正式三地图III的物品等级通过实际 `Main._award_kill_equipment` 获取（仅HUD通知换成无副作用桩，未启动场景/写档），分别为旧庭15、断垣17、晴泉19，候选T1/T2/T3资格继续来自目录。白底供应也由Town实际构造，保持15%/0%/0%。Python只排版和验收，不重新实现生产抗性支持。

旧全部目录观测经有界投影复原，新增自然池分布明确改变；资料检查没有把 `canonical_v37` 或其后续随机状态说成旧v34相同。天赋源policy36、完整源树与覆盖JSON保持。

## 复验命令

输出记录使用独占创建模式；重复检查需使用新prefix，以保留已有证据。

```sh
python3 docs/qa/v060-reference/run-reference-checks.py export --prefix replay-
python3 docs/qa/v060-reference/run-reference-checks.py build --prefix replay-
python3 docs/qa/v060-reference/run-reference-checks.py font --prefix replay-
```

`check-reference.py` 验收当前生成物及v59边界，最终已执行并保存报告。它的结果文件同样不覆盖；重验时应保留现有报告并在独立副本或新的结果目标运行。不要为例行复验重写现有证据。
