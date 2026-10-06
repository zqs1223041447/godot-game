# v083 银杏回廊 F8 窄集成

基线 `f18cf07`。只新增 `ginkgo_arcade` 同源资料片段、F8 地图卡与布局图，更新当前游戏版本和 schema 标签。资料与实际玩法的验证范围分别记录。

## 来源与调用

`export-fragment.gd` 在主任务完成共享 import 后运行，只导出新图，不调用全量 `tools/export_reference.gd`，不读入旧 catalog，也不生成完整源树 coverage。

- 地图定义和正式三档来自 `MapCatalog`、`MapCompiler`；费用与奖励不在图鉴脚本中重编译
- 地形、完整阵形、木牌与首领标记来自 `MapGeometry`、`MapCampLayout`；HTML 不手写一套坐标
- 基础物种按位示例来自 `GinkgoRosterRules`；真实整组重放来自 `MapCampState`
- 三档合法前置复用 `tests/fixtures/v083/ginkgo_journey_fixture.gd`：载入已发布原始 schema49，在隔离 XDG 下的 `user://build_save.json` 通过真实迁移、完成和领奖事务解锁，不手写装备、货币或最高阶级
- I／II profile 和完整 roster 精确对照已通过的 `../v083-gameplay/results/main-result.json`；自然首领冻结的攻击参数读取同一证据，并与当前共享首领策略比较。Main 的 64 位 seed 从原 JSON 整数字面量恢复，避免 Godot JSON 浮点转换丢失低位
- `formal-tier1.json`、`formal-tier2.json` 只读验证完整 schema50 模型。冻结案例只复用独立合法的 `freeze-source.json` 和 `freeze-cast.json`，不改正式地图角色

运行命令：

```sh
python3 docs/qa/v083-reference/run-reference-checks.py export --prefix=corrected-
python3 docs/qa/v083-reference/run-reference-checks.py merge
python3 docs/qa/v083-reference/run-reference-checks.py build
python3 docs/qa/v083-reference/run-reference-checks.py verify
```

证据使用独占创建；已有输出不能直接覆盖重跑。`*-result.json` 记录命令、退出码、耗时、错误、输入 SHA256，以及旧资料图片与源 coverage 的字节和 mtime 保持情况。

## 保全与范围

`merge-fragment.py` 直接在基线 catalog 原字节中插入一个顶层新图字段，并仅替换 `game_version`、`save_version`。旧地图、物品、源树、机制与历史样本原始 token 不改；旧三图卡保持逐字节一致。旧卡出现的当前版本标签单独列入 `preservation.json`，不把标签更新算作旧卡原字节保全。

新图进入正常“有限地图”分类和搜索，作为第 4 项；地图装置补充四图导航与正式／测试费用区分，三张特殊词缀卡的关联地图补充银杏回廊。这四张旧卡仅有明确列出的新图链接／导航差异，旧数值和此前正文保持。护甲历史预算中的“三图III首领”指当批三个实际样本，不是当前可用地图总数，保留其历史范围。

`check-reference.py` 验证实际 Main profile／roster／64 位 seed、同源数值文本、三个障碍、36 个出生点、四个触发圆及入口／首领标记。它还核对所有旧锚点、本地链接、图片和数据字节、无新 PNG，以及源 coverage 逐字节保留。字体补字属于主任务的独立同源资源工作，不包含在这里的图鉴图片保全统计中。

第一次 Python 对照在新片段的 Main 攻击浮点重序列化差异处停下，保留 `focused-reference-*` 收据。检查修正为：Main profile／整组 roster／64 位 seed 仍完全一致；重读 Main 后的新攻击浮点允许小于 `1e-12` 的往返误差，每一处差异及原值单列，整数、键和值结构不放宽。原 Main 原件的 SHA256 与全部旧 catalog token 仍严格保全。这不是玩法差异，也不要求重跑 Godot 导出。

第二次 Python 对照 `checked-focused-reference-*` 发现新图 SVG 的世界边界使用了旧通用六位有效数字显示格式，导致实际非整数宽高被舍入；修正新图 SVG 为完整同源数值后再生成、核验。障碍和标记不重算，旧卡不改。

首次导出 `ginkgo-fragment-result.json` 在 4.373 秒因夹具路径合同不符主动停下：资料脚本选择了自命名存档路径，正式旅程事务正确拒绝。该次没有写入片段或旧 catalog、coverage、图片。修正为隔离 XDG 内真实正式路径后，`corrected-ginkgo-fragment-*` 记录 6.442 秒、exit0、零错误；不重跑战斗或绕过正式路径守卫。

Main 原结果记录 212 项、0 失败；stdout 的 213 包含最后证据文件打开检查。原件不改，图鉴按原结果文件 212 记录来源。Main I／II 是真实流程和完整怪群的受控死亡／静态站位验证，不是自然战斗录像。

本批资料验证不等于玩法通过，不包含全战斗、600 秒稳定性、原生 F8 视觉验收、安装包或 Release。实际通过项以本目录最终结果及各独立玩法、布局、存档、原生视觉报告为准。

## 最终结果

- 有效窄导出：`corrected-ginkgo-fragment-result.json`，6.442 秒，exit0，零错误
- 生成与一致性：`checked-build-result.json`／`checked-build-check-result.json`，1.221／1.323 秒，exit0
- 最终静态保全：`final-focused-reference-result.json`，6.714 秒，exit0，零错误；详情见 `preservation.json`
- 正常地图分类共 4 项，中文名、ID 与动作名可搜索；旧 3843 个锚点保留，新增 `maps-ginkgo_arcade`
- 3 档合法 helper 前置，2 组 Main profile／完整 roster 精确一致；2 个原始 64 位 seed 完整保留
- 30 个同源数值，3 个墙体、36 个出生点、4 个触发圆与入口／首领坐标均核对通过
- 81 个旧 catalog 顶层数据段逐字节保留；3764 张旧卡逐字节保留（含全部旧三图卡），30 张仅当前版本标签更新，4 张仅新图导航／适用链接更新
- 165 个受保护文件、135 张 PNG 与源 coverage 逐字节保持；每次命令也检查资料 PNG 和 coverage 的 mtime 未变
- 新 Main 攻击数据仅两处浮点往返差异：`2.22e-16` 与 `7.11e-15`，逐项记录原值与导出值；未改任何旧 token
