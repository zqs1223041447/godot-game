# PoE1 官方被动树数据导入与验证

本模块只导入和验证只读数据，不接入游戏运行时、构筑状态或存档。原有自制星图与项目许可证均未更改。**保留源数据不代表这些数值词缀已由游戏机制实现。**

## 固定来源

来源清单位于 `data/passive_source/source_manifest.json`，原始文件为上游 `data.json` 的固定副本：

- 游戏：Path of Exile 1，skilltree-export 3.29.1
- 仓库：[grindinggear/skilltree-export](https://github.com/grindinggear/skilltree-export)
- 提交：[8bd138b32ea2631455cac5935bfab089f826094f](https://github.com/grindinggear/skilltree-export/commit/8bd138b32ea2631455cac5935bfab089f826094f)
- 下载地址：[固定版本 data.json](https://raw.githubusercontent.com/grindinggear/skilltree-export/8bd138b32ea2631455cac5935bfab089f826094f/data.json)
- 字节数：6,666,935
- 下载后实算 SHA-256：`7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122`

导入器同时固定提交、字节数和摘要；下载文件必须全部匹配才会替换本地原始文件。被固定的仓库根目录没有发现 `LICENSE`、`LICENSE.md` 或 `LICENSE.txt`，README 也没有声明数据许可或再分发条款。因此这里记录为“未发现明确许可”，不推定为公有领域或开放许可。许可状态需在扩大分发或仓库外使用前重新审查。没有下载或复制官方二进制美术资源；原始数据里的图标引用字符串仍随节点记录保留。没有修改本项目许可证。

来源清单只纳入固定版 `data.json`；其他 alternate/ruthless 导出没有复制，`assets/` 美术目录没有下载。完整原始 `data.json` 仍保存在独立目录，因此归一化时略过的顶层 `extraImages` 和 `sprites` 也可由原文件复核。

## 归一化接口

`data/passive_source/normalized_tree.json` 是确定性生成文件，包含：

- `node_records`：3,390 条原始节点记录，按节点 ID 排序；节点字段、原文 stats、提醒文本、masteryEffects、原始 in/out 顺序均保留。
- `groups`：797 个完整上游 group，不拆改其原始 `nodes`、`orbits`、中心位置或背景键。
- `positions`：2,987 条可定位节点的位置派生值。每条保留 group ID、orbit、orbitIndex、角度、半径和坐标。
- `edges`：3,382 条去重的无向连接索引，并记录各边在上游节点 `out` / `in` 中出现的位置。原始连接数组也保留在 `node_records` 中。
- `standard_tree`：2,790 个节点 ID，含逻辑 root；其中 2,387 个有几何位置，403 个无位置（root 与 402 个没有 group/边的游离被动定义）。
- `special_subtrees.ascendancies`：37 个升华树分区，共 558 个节点；各分区列出内部边、跨区边、起点和珠宝槽。
- `special_subtrees.expansion_jewels`：42 个扩展珠宝节点，连同跨区边单独列出。
- 顶层还保留 7 个基础职业、16 个 alternate ascendancy 元数据、全部 60 个 jewel slot ID、点数、边界、坐标常数和角度规则。
- `coverage`：数据保留统计，不是词缀生效率或机制覆盖率。

标准区包含所有没有 `ascendancyName` 且没有 `expansionJewel` 的记录。没有 group 的 402 条标准区记录没有连接和坐标，因此保留为 detached definition，不伪造布局。组与节点的源字段分别保留：30 个 group 同时含普通树节点和扩展珠宝节点；另有 48 个节点的 orbit 不出现在该 group 的 `orbits` 数组中。位置计算以节点自身的 `orbit` / `orbitIndex` 和上游 group 中心为准，不把两个源字段强行改成相同。所有 3,382 个连接均保留，127 条跨分区连接列在相应分区的 `boundary_edge_ids` 中；其中 23 条 root 出边在源 `out` 里存在、`in` 中没有反向记录，按原状保留。

## 坐标与原文

位置公式遵循 PoE 树坐标：先取 `groups[node.group].x/y`，半径取 `constants.orbitRadii[node.orbit]`；轨道角度由 orbit 索引规则给出，再计算：

```text
x = group.x + sin(angle) * radius
y = group.y - cos(angle) * radius
0 degrees points up
```

Orbit 2/3 的 16 个角度按 [GGG README 3.17.0 的索引表](https://github.com/grindinggear/skilltree-export/blob/8bd138b32ea2631455cac5935bfab089f826094f/README.md) 使用：
`0, 30, 45, 60, 90, 120, 135, 150, 180, 210, 225, 240, 270, 300, 315, 330`。
40 位置轨道使用 [Path of Building 的 PoE1 `PassiveTree.lua`](https://github.com/PathOfBuildingCommunity/PathOfBuilding/blob/16de4b82d57f1c0de6eb40f37143c32d4da36a02/src/Classes/PassiveTree.lua) 记录的特定角度表，亦不等距：
`0, 10, 20, 30, 40, 45, 50, 60, 70, 80, 90, 100, 110, 120, 130, 135, 140, 150, 160, 170, 180, 190, 200, 210, 220, 225, 230, 240, 250, 260, 270, 280, 290, 300, 310, 315, 320, 330, 340, 350`。
其余轨道按上游 `skillsPerOrbit` 均分。位置只在归一化副本中新增，并保留六位小数以稳定重现。

节点 mastery options、multiple-choice 标记、珠宝槽、类别布尔标记和英文 stats 均逐字保留。导入过程不翻译、不归一化数值文本，也不将原始词缀映射到项目机制。

## 数据覆盖统计

| 数据面 | 保留量 |
| --- | ---: |
| 原始节点记录 / 位置记录 | 3,390 / 2,987 |
| 标准树记录 / 有位置节点 | 2,790 / 2,387 |
| 升华名称 / 升华节点 | 37 / 558 |
| 扩展珠宝节点 | 42 |
| groups / 完整连接 | 797 / 3,382 |
| 基础职业 / 职业起点 | 7 / 7 |
| Alternate ascendancy / jewel slots | 16 / 60 |
| Mastery 节点 / mastery options | 353 / 1,837 |
| Multiple-choice 节点 / option 节点 | 17 / 62 |
| 节点 stats 行 / 去重原文 | 4,966 / 2,622 |
| Mastery stats 行 / 去重原文 | 2,015 / 389 |

运行时**词缀执行覆盖没有在本任务中测量**。没有声称所有这些 stats、mastery 选择或升华效果已在项目中生效。

## 重现和检查

从仓库根目录执行：

```sh
# 从固定官方 URL 重新下载；仅在摘要和字节数匹配时写入
python3 tools/passive_import/import_tree.py --fetch-source --write

# 只验证来源哈希、数据结构、重建字节与已提交产物；不写文件
python3 tools/passive_import/import_tree.py --check --stats

# 重新归一化并写入结果
python3 tools/passive_import/import_tree.py --write

# 独立单元回归
python3 -m unittest discover -s tests -p 'passive_import_test.py' -v
```

测试覆盖固定来源哈希与失败拒绝、节点分区、group 与跨区边、root/起点、两种非均匀轨道角表和定位结果、mastery 与多选原文、60 个珠宝槽、确定性输出和 CLI 检查。模块不会运行或修改 `main.gd`、`build_state.gd`、`game_data.gd`、`game_hud.gd`，也不会触碰自制树。
