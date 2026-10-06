# v0.71 雾羽掠行体 F8 资料验证

基线为 `4166822ff7a487bb498c7086b20e2823e4e71edb`。只新增一个普通怪物卡片和晴泉地图内的简短出现提示；没有独立流派排行、天赋章节或新图片。

## 同源输入与精确变化范围

实际 `MonsterCatalog.MIST_SKITTER_POLICY` 与 `make_enemy` 提供生命、伤害和闪避。雾羽模板用正式根怪上下文生成，不绕过模板拒绝演示/蓝金/后代的限制；F8闪避读取实际模板1600，而非仅按kind1取旧默认320。

五组命中值100/284/304/414/600直接交给原 `AttackHitRules.resolve`，同时给出旧闪避320、实际闪避1600和坚决技艺结果。它们是独立数值探针，不创建装备或构筑。既有v70实际Main夹具沿原严格校验入口读取，未重跑Main或另造物品。

出现资格读取实际正式地图编译器与 `MistSkitterRosterRules.eligible_profile`。四组seed43示例读取实际 `MapCampState` 完整编排结果，再与[已通过的集中名单验证](../v071-mist-skitter/roster/roster_report.json)对照：正式II/III无词缀各为入场序号6、21、25；雷纹巡逻各为0。固定例子不代表随机出现频率。

完整旧catalog只允许两个明确路径：应用版本 `game_version` 与新增 `monsters.mist_skitter` 子树。所有旧默认构筑、技能示例、历史章节、物品池和schema45必须整体相等。源树覆盖JSON必须保持原字节；原执行覆盖没有新增节点、属性或政策。

## 一次集中生成与保全

[运行入口](run-reference-checks.py)在父任务完成统一导入和名单门禁后执行一次导出、HTML构建、确定性检查和[定向保全](check-reference.py)。每步记录命令、退出码、耗时、输入SHA256、错误行和执行期间输入变化。导出使用独立临时XDG，不额外import、Main运行、原生启动或打包。

导出仍从真实规则计算覆盖报告，序列化结果相同时保留原文件，不打开写句柄。HTML构建同样跳过与原始资源字节相同的既有图标。收据逐步检查覆盖与70张F8 PNG的SHA256及mtime均不变；字体补字由独立集成负责，不纳入本批固定图像校验。

[完整保全收据](v070-preservation.json)记录新卡片的24个权威数值及实际显示、旧3825个锚点保留、唯一新增 `monsters-mist_skitter`、全部内部锚点和本地链接、原始数据和中文映射、63张运行时PNG与70张F8 PNG保全。CSS、JS与图片清单也须保持原字节。

单次[完整导出](godot-export-result.json)27.428秒、[构建](build-result.json)0.538秒、[确定性检查](build-check-result.json)0.546秒与[定向检查](focused-reference-result.json)3.834秒，全部exit0，无错误行或执行期间输入变化；覆盖和F8 PNG没有发生写入。24个数值显示、旧3825个锚点与全部保全检查通过。这是源码资料与定向保全记录，不是Windows、PCK、ZIP或Release验收。

[出现与预算合同](../../MIST_SKITTER.zh-CN.md)
