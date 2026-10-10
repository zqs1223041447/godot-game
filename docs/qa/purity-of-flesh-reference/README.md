# 58218 F8交付补齐与相关测试修复

基线main：`a5d21226161bf568bfb715ea8302c0bd213478a0`。本批没有修改生产玩法、保存规则或schema60，不开启下一项机制。

## 可重复生成与最小范围

沿项目已有“局部Godot导出 → 精确JSON成员合并 → 原HTML生成器 → 保留校验”流程：

```bash
XDG_DATA_HOME=/tmp/godot-purity-reference-review XDG_CACHE_HOME=/tmp/godot-purity-reference-cache timeout 30 godot --headless --path . --script res://tools/purity_of_flesh_reference.gd -- res://docs/qa/purity-of-flesh-reference/reference-fragment.json res://docs/qa/purity-of-flesh-reference/source-tree-coverage.json
python3 tools/merge_purity_of_flesh_reference.py
cp docs/qa/purity-of-flesh-reference/source-tree-coverage.json docs/reference/source-tree-coverage.json
python3 tools/build_reference.py
python3 tools/verify_purity_of_flesh_reference.py
python3 tools/build_reference.py --check
```

没有重跑完整内容导出。新增 `Exporter.purity_of_flesh_reference()` 同时供局部导出和原完整collect入口使用，防止后续正常导出丢失新元数据。原始源数据没有修改。

`catalog.json`中只更新58218的执行/可达记录、该节点的中文展示及唯一 `+8% to Chaos Resistance` 行状态、当前schema/source政策60、对应窄范围说明，以及混沌防御元数据的已开放节点声明。其他历史业务字段保留原值字节。`source-tree-coverage.json`重新从同一运行时导出：只有58218节点记录变化；七职业分别只增加58218可达，汇总数字如实更新。其他节点、精通、仍未实装效果不变。

F8共3817张卡片，ID集合不变；3806张逐字节不变。变化的11张包括58218、源树保存规则、属性防御和混沌防御四张相关卡，以及七张仅更新当前schema/source版本标签的既有卡。对后七张明确断言仅59→60标签替换，不能夹带内容变化。新生成器加旧数据必须逐字节再现旧HTML；当前合并幂等，HTML与生成器一致。搜索负载只变records，对应同11张卡；仅58218的status改变，其余仅search文字改变。266个相关内部链接检查通过。详见 `reference-verification.json` 与生成日志。

[F8节点卡截图](f8-purity-card.png)已查看。Chromium 151.0.7922.173直接file://访问被环境管理员策略拒绝，因此用仅监听127.0.0.1的临时服务呈现同一HTML，结束即关闭。实际操作原搜索和状态筛选：58218可见于已实现、隐藏于尚未实现；28987继续显示暂未实装。没有页面脚本异常，仅自动favicon请求404；没有修改产品资源规避它。此项不是游戏F8按键或操作系统默认浏览器调用验证，也不是外部发布。

## 旧防御夹具的准确修复

原失败日志完整保留于[上一批](../purity-of-flesh/historical-defense-blocked.log)。测试将冻结v92防御脚本动态加载，但其DamageResolver预加载仍指向实时文件。它要求历史哈希 `720dc69a…`；此前铁握持提交 `47f31d0aeab2651f19a3590dbe6031ffb4a60830` 已合法添加 `excluded_tags` 行为。`9b6d28d`与本批基线`a5d2122`均为 `51a3c503c2cae7b7ec1513976de1ed03f41c3677b892b8b55ab47bdb0b2ef6e5`，与本批节点实装无关；证据见 `defense-baseline-evidence.json`。

从原精确提交 `897dbfc16c1308b2b6916fa9ba52792d9d82c293` 取出实际历史DamageResolver，在测试夹具中只去掉全局class_name，测试会恢复该行并断言原哈希。原冻结防御正文不改，只在内存中把预加载改指该历史副本；HitPenetration仍保留原哈希守卫。没有更新旧哈希去迁就当前生产文件，没有删除或绕过任何比较断言。

修复后的原 `chaos_resistance_rules_test.gd` 完整有限运行 **1188/0，exit0**，其中325次完整类型字节比较；`defense.json/log`保留。

## 本次schema升级相关测试更新

独立审查指出的CI测试问题属于本次升级需要同步的测试，不归为历史失败：

- `chaos_inoculation_migration_test.gd`：整个Game.load_build、重开和失败重试使用Rules.VERSION，future使用Rules.VERSION+1；纯58→59单步比较仍显式固定59，旧57→58比较仍固定58。有限回归 **77/0，exit0**。
- `chaos_inoculation_test.gd`：当前合法构筑使用Rules.VERSION；冻结58→59的效果指纹比较保持原政策版本。实际机制与Main路径回归 **111/0，exit0**。
- `purity_of_flesh_test.gd`：退款前将真实Main当前HP/ES设置为已分配节点的实际上限，断言两者都高于退款后的上限；失败写入保持这两个值，成功退款后下夹到新上限且均下降，不治疗、不改生产规则。完整该有限脚本 **100/0，exit0**。夹具沿原合法圣堂路径和现有戒指，不声称自然升级来源。

Godot4.6.3，隔离XDG，每个Godot进程30或45秒上限。没有完整core、600秒检测、Windows导出、模型修改或封包。所有新增/修复的相关检查已通过；上述file://限制以如实记录的本机预览替代，没有冒称游戏F8快捷键验证。
