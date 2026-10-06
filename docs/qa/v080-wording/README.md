# v080 资源词缀文字定向验证

结果：唯一一次实际 Godot focused 运行通过，**447 checks、0 failures**，退出码 0，4.491 秒；实际测试日志没有 SCRIPT ERROR / ERROR。12 份记录输入执行前后 SHA256 一致。

- 基线：`33ed04b73edf3545b98339291df81b4c49f891cf`
- 环境：Godot 4.6.3.stable.official.7d41c59c4，Linux headless
- 时间：2026-10-06T13:27:39.864574+00:00
- 资源：复用本批已经完成的统一 import；此测试未重导入，未运行 v079 旧套件
- 隔离：每次新建 `/tmp/godot-m1-v080-wording/<run>/` 下的 data/config/cache；仅建立测试自己的新存档

## 覆盖内容

通过现有 `CanonicalPassivePanel`、真实 `CanonicalGameState` 和原始英文源树验证九个精确 key。测试直接使用既有 `LineEdit.text_submitted`、`node_clicked`、`node_hovered` 信号；没有替换搜索算法或模拟面板。

| 源节点／词缀索引 | 预期显示 |
|---|---|
| 25714 / 1 | 技能的魔力消耗提高5% |
| 26960 / 1 | 技能的魔力消耗提高10% |
| 10835 / 0 | 魔力再生速率提高30% |
| 31033 / 0 | 每秒再生10点生命 |
| 31033 / 1 | 每秒再生相当于最大生命1.2%的生命 |
| 22356 / 1 | 生命偷取的每秒总回复速率提高100% |
| 65053 / 2 | 魔力偷取的每秒总回复速率提高100% |
| 22356 / 0、39530 / 1 | 生命偷取的每秒总回复上限提高40% |
| 65053 / 1 | 魔力偷取的每秒总回复上限提高50% |

以上九个 key 共十处源引用，在真实画布描述、详情及 hover 中逐行验证；全部保留已实现状态，不出现缺失翻译或未实装后缀。

七个代表节点保留全部原始词缀、完整 typed grants（stat、mode、浮点值和顺序）及 `full` 状态，仍属于有真实坐标的标准可分配图。检查包含未改动的最大魔力、魔力消耗效能及攻击偷取词缀，没有只检查九条改动行。

每个节点的现有中文名、英文名和 ID 均执行一次真实搜索，共 21 次，每次都从另一个选中节点开始，并验证选择、原坐标居中和详情标题：

| ID | 既有中文名 | 既有英文名 |
|---|---|---|
| 25714 | 魔力与提高魔力消耗 | Mana and Increased Mana Cost |
| 26960 | 深谋 | Forethought |
| 10835 | 梦行者 | Dreamer |
| 31033 | 强韧 | Robust |
| 22356 | 嗜血 | Hematophagy |
| 65053 | 精华树液 | Essence Sap |
| 39530 | 活力虚空 | Vitality Void |

原始 node ID、英文名、stats、完整 source record、源版本/hash/commit、位置、邻接、标准图 ID、class starts、面板的全部 edges、画布节点元数据均保持。源树文件 SHA256 与 v079 基线一致；显示及搜索后的完整 Data.nodes 缓存与 typed node effects 字节保持一致。

在 setup/显示/hover 及每次搜索前后，检查真实模型 snapshot、revision、stats、combat snapshot、content epoch、changed 信号、存档字节、save attempts、successful saves、文件列表及全局 RNG 抽样序列不变。只建立一次初始测试存档，面板操作不保存。

## 证据与范围

- [测试源码](../../../tests/passive_resource_wording_test.gd)
- [可重现的单次运行器](run-focused.py)
- [完整 stdout/stderr](20261006T132739.864574Z/wording.stdout.log)
- [退出码](20261006T132739.864574Z/wording.exit.txt)
- [命令、隔离目录、时间及输入 SHA256](20261006T132739.864574Z/wording-result.json)
- [复用的统一 import](../v080-integration/import.log.txt)

运行器在测试之前获取 `godot --version` 时，主环境 stderr 曾输出重复 `Fontconfig error: No writable cache directories`。隔离后的实际测试日志无此警告，测试成功没有依赖重试；未因此重跑。

没有实际分配节点、建立竞技场、执行战斗或全量翻译测试，也没有修改生产/UI/词典/F8。本验证中的 RNG 仅为面板／模型可访问的全局 RNG；未声明竞技场 RNG、原生图形、Windows 实机或全项目验收通过。

重现前先完成同一工程的统一 import，再执行 `python docs/qa/v080-wording/run-focused.py`。每次运行建立新的时间戳证据目录，并保留成功或失败日志，不覆盖历史结果。
