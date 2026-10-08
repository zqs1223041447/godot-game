# 攻击技能元素伤害：F8 局部同步

基线 `2235f079c6140176cd2c374ac1857bbc68690a7f`。五个源节点18670、25511、30894、56646、64878此前仍显示“暂未实装”。本批从已有运行时导出器读取完整节点执行结果、中文显示和覆盖报告，合并五个节点、一条中文源行，以及当前存档55/源政策55。源树原始SHA、坐标、连线、起点、点数和所有历史章节保留；`canonical.save_version=47`是原历史快照，未改成当前版本。

18670的效果完整接入，但两个普通邻居仍有未实现效果，当前已支持普通路径不能到达。卡片明确说明不能普通连线分配，特殊珠宝准入未验证。其余四点仍需合法连接、点数和位置资格；报告的拓扑可达不表示任何角色现有构筑已经能付点。

复现（Godot使用隔离XDG目录，不读正式用户档）：

```sh
env XDG_DATA_HOME=/tmp/attack-elemental-reference/data XDG_CONFIG_HOME=/tmp/attack-elemental-reference/config XDG_CACHE_HOME=/tmp/attack-elemental-reference/cache godot --headless --path . --script tools/attack_elemental_reference.gd -- res://docs/qa/attack-elemental-reference/fragment.json res://docs/reference/source-tree-coverage.json
python3 tools/merge_attack_elemental_reference.py docs/qa/attack-elemental-reference/fragment.json
python3 tools/build_reference.py
python3 tools/merge_attack_elemental_reference.py docs/qa/attack-elemental-reference/fragment.json --check
python3 tools/build_reference.py --check
python3 tools/verify_attack_elemental_reference.py
```

`fragment.json`是同源局部导出，`verification.json`记录静态核验：五张目标卡片、8张仅当前版本标注更新的规则卡、3803张逐字保持的其他卡片、259个有效相关本地链接。覆盖报告只有五个节点执行记录及派生统计/可达前沿变化；各职业普通拓扑可达数709→713，新增可达四点，18670仍不在其中。未改变或新增图鉴图片。

未重跑战斗、存档迁移或长时检测，未声明浏览器交互验收；这些边界与前一机制提交的验证分开记录。本批无游戏机制、数值、UI布局或奖励变动。
