# 奥术意志27163：实际构筑、中文状态与F8同步

基线main：`cdaee678322da0298e7b3e774a92ba62e2327c4d`。复用已有节点、固定魔力再生统计、连续资源恢复、正式T分配/退款和保存事务；只开放原节点27163，没有另建同功能系统。

## 规则与合法路径

原三条效果现在完整可用：最大魔力提高30%、每秒再生5点魔力、智慧+10。固定5点先与原固定再生相加，再乘已有魔力再生率提高；实际施法仍扣原耗魔，后续资源帧持续恢复并受最大魔力限制。分配不补满魔力/护盾，退款将超过新上限的当前资源下夹。

女巫普通路径：`54447 → 57226 → 21678 → 32210 → 8948 → 27929 → 7503 → 65203 → 27163`。起点免费，实际共8点，最早4级预算可达。测试使用合法4级前缀，经原分配事务逐点走完全程，并在原生T面板真实鼠标分配/退款；合法夹具不代表自然练级来源。

该路径现有装备下，分配前后最大魔力223.56→292.56、智慧82→92、最大护盾133.92→135.16、魔力再生13.2→18.7/秒。原合法魔力再生头盔的固定值和提高继续参与同一公式，选中节点时为19.04/秒。实际进入免费旧庭园，通过原施法组验证扣魔、随后1/60秒资源恢复、满魔力上限，回城再退款；生产Main恢复与施法代码未改。

## 单节点范围与schema61

旧schema60把不完整节点整体锁定。新61使该节点可合法保存，因此保留冻结60政策，新增60→61最小迁移：完整验证旧60，原字节备份`.v60-backup.json`，仅改变版本，不赠物、不赠点、不改物品/技能/旅程。59→60仍固定终点60；完整加载链只备份最初版本，保存/发布一次。城镇及进行中地图夹具、备份失败/冲突、外部修改、原子写失败/重试、未来版本保护均有限验证。

原句`Regenerate 5 Mana per second`还出现于12处魔力专精选项2902。首次75项检查发现范围扩大（1失败），随即改为明确节点上下文：只有27163且政策≥61开放。无节点上下文的通用句子仍保持未实装；解析、缓存、中文状态、T图/详情/悬浮与精通选择、F8节点展示都传递相同上下文。全树旧60效果指纹不变，60→61差异只有27163；12处同句专精仍锁定，实际T选项仍禁用且有未实装标记。

## 有限验收

Godot4.6.3；隔离/tmp XDG；每个Godot进程30或45秒上限。最终相关检查均exit0：

| 检查 | 通过/失败 | 证据 |
|---|---:|---|
| 奥术意志原生X11机制、T鼠标操作、两张截图 | 91/0 | native.json/log |
| 60→61迁移与故障保护 | 77/0 | migration.json/log |
| 纯净的血肉迁移 / 实际机制 | 77/0、100/0 | purity-migration、purity-mechanism |
| 混沌防护迁移 / 实际机制 | 77/0、111/0 | ci-migration、ci-mechanism |
| 现有冻结防御比较 | 1188/0（含325次类型字节比较） | defense.json/log |
| 原资源预览原生X11 | 238/0 | resource-preview-native.json/log |
| 中文全树状态审计 | 38254/0 | localization.log |
| 天赋动作展示 | 13/0 | presentation.log |

纯净的血肉整链测试同步使用当前Rules.VERSION；纯59→60比较仍显式固定60，未来版本使用Rules.VERSION+1。资源预览当前存档断言同步当前版本。没有用依赖失配、跳过检查或修改冻结效果预期来凑通过。

首次失败均保留且不算通过：`mechanism-attempt01`为12处专精越界；`migration-attempt01.log`为错误夹具路径导致脚本异常，30秒退出124，修正后77/0；原资源预览headless的3个鼠标失败记录在`resource-preview-headless-failed`，相同测试在原X11模式238/0；`browser-attempt01.log`读取折叠详情不可见文本，测试改为先展开原详情后通过。中间headless88/0记录早于新增明确T专精禁用检查；最终原生91含该检查和两张截图。

详细汇总见[verification.json](verification.json)。[分配前](available.png)、[分配后](allocated.png)与[F8卡片](f8-arcane-card.png)保留；后两张已人工查看。

## F8可重复生成与范围证明

```bash
XDG_DATA_HOME=/tmp/godot-arcane-reference-review XDG_CACHE_HOME=/tmp/godot-arcane-reference-cache timeout 30 godot --headless --path . --script res://tools/arcane_will_reference.gd -- res://docs/qa/arcane-will/reference-fragment.json res://docs/qa/arcane-will/source-tree-coverage.json
python3 tools/merge_arcane_will_reference.py
cp docs/qa/arcane-will/source-tree-coverage.json docs/reference/source-tree-coverage.json
python3 tools/build_reference.py
python3 tools/verify_arcane_will_reference.py
python3 tools/build_reference.py --check
python3 docs/qa/arcane-will/browser_check.py
```

复用局部导出→精确JSON成员合并→原HTML生成器；完整collect也保留新元数据。没有跑完整内容导出。3817张卡片ID集合不变，3807张逐字节不变。10张变化包括27163、源树保存规则、魔力再生说明，以及7张仅更新60→61来源版本标签的既有卡。12张同句专精卡逐字节不变，通用行字典不变；覆盖表只有27163节点改变，七职业分别只增加该节点可达。244个相关内部链接有效，搜索负载仅相应records改变。新生成器+旧数据逐字节重现基线HTML，合并幂等，当前HTML通过`--check`。

Chromium管理员策略限制file://，浏览器测试用仅监听127.0.0.1的临时服务呈现同一HTML，完成关闭。实际操作原搜索、已实现/尚未实现筛选、专精折叠详情；27163已实现，10495同句仍未实装，无页面脚本异常，只有自动favicon404。这不是游戏F8快捷键或系统默认浏览器调用验证，也没有外部发布。

没有完整core、600秒检测、Windows导出/封包、模型修改。当前限定范围没有剩余阻塞。
