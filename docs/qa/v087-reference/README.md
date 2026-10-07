# v087 霜纹守卫冰缓 F8 有限更新

基线`1530db9`（已交付v86）。只插入`frost_guard_chill`片段，更新当前霜纹守卫、锁点寒击、霜纹巡逻三张卡，新增一张规则卡。四图当前卡、地图装置和旧伤害示例保持原字节；游戏版本标签差异单列。

## 来源与执行

- `ChillRules.ENEMY_POLICY`提供25%移动减速、1.2秒；`MonsterCatalog.make_enemy`建立脱离战斗的第4波霜纹目录样本
- `MonsterCatalog.telegraph_policy`提供实际策略；`TelegraphedAreaRuntime.start/advance`只产生纯起手、事件与恢复快照，不实例化Main或进行伤害结算
- 导出不构造玩家、不改装备、不读写存档、不重新编排四图、不抽取新奖励、不生成PNG或完整源coverage
- 实际Main结果、运行退出收据与输入指纹只读引用；检查通过且源码仍匹配才允许导出。原失败记录不会覆盖或删除
- Main输入指纹包含本批状态与事件消费者；未单列的`telegraph_profiles.gd`另外对照v86基线原字节。新事件的`chill_policy`／`step_time`明确列为新增元数据，不把伤害预算保持等同于整包事件不变
- schema50、Source49、Equipment46沿权威常量；只更新project资料标签至0.87.0

在共享import、Main实测和父任务源码稳定确认后，依次执行一次：

```sh
python3 docs/qa/v087-reference/run-reference-checks.py export --main-report=docs/qa/v087-gameplay/main-result.json --main-run=docs/qa/v087-integration/main-attempt01-result.json --main-inputs=docs/qa/v087-integration/main-attempt01-inputs.json
python3 docs/qa/v087-reference/run-reference-checks.py merge
python3 docs/qa/v087-reference/run-reference-checks.py build
python3 docs/qa/v087-reference/run-reference-checks.py verify
```

实际来源路径以`frost-chill-fragment.json`及运行收据为准。输出独占创建，不能静默覆盖已有证据。没有调用`tools/export_reference.gd`，没有增加原生画面验收门槛。

`merge-fragment.py`复用v86原始token插入方法：从基线原字节插入一个片段，仅替换顶层`game_version`。旧monster、attack、town、map与历史样本数据段完整保留。新纯快照可能产生极小JSON浮点往返差异，逐项单列；不将该差异写回任何旧伤害示例。

每阶段记录命令、退出码、耗时、错误行、输入SHA256、运行中源码变化和PNG／coverage的字节与mtime。`check-reference.py`在一次静态核对中确认HTML生成一致性、旧版本输入的整个页面兼容、三张目标卡与一张新卡的界限、全部旧锚点及本地链接，以及所有旧reference资源保全。

## 结果与范围

- 一次有限Godot导出：`frost-chill-fragment-result.json`，1.754秒、exit0、零错误
- 一次原字节合并：`merge-result.json`，1.177秒、exit0
- 一次HTML生成：`build-result.json`，0.892秒、exit0
- 一次静态／来源／结构／保全检查：`focused-reference-result.json`，5.597秒、exit0、零错误
- 84个旧catalog顶层数据段保留原始token，所有旧伤害示例数值逐字保持；原霜纹伤害示意图HTML也逐字保持
- 3775张旧卡逐字不变，22张仅游戏版本标签0.86.0→0.87.0变化，3张本批目标卡更新，新增1张规则卡
- 全部四图当前卡与地图装置逐字保持；3845个旧锚点保留，所有本地链接有效
- 77个旧reference资源、其中71张PNG及源coverage保留原字节，没有新PNG；每阶段PNG／coverage的mtime也未变
- 新纯快照与历史霜纹伤害基底本次没有浮点往返差异；新增事件元数据不等同于原事件整包不变
- 当前HTML与生成器一致；生成器使用原v86 catalog时，整个旧页面仍逐字一致

详情见[保全清单](preservation.json)及[原始token保全收据](catalog-format-preservation.json)。上述阶段运行期间源码均无变化。

Main来源为[实际174项、0失败原件](../v087-gameplay/main-result.json)，与[4.881秒、exit0且无错误的运行收据](../v087-integration/main-attempt01-result.json)及[输入SHA256](../v087-integration/main-attempt01-inputs.json)对应；导出和静态检查均核对当前输入一致，不重跑Main。其合法等级／天赋前置、受控位置／资源／时钟、100%魔力纯接口边界及地图完成消费者夹具按[原测试范围](../v087-gameplay/README.md)解释，不把受控样本宣称为自然成长或完整奖励旅程。

本批资料检查不是玩法或性能验收，不包含全量战斗、600秒稳定性、原生F8视觉、安装包或Release。规则见[霜纹冰缓合同](../../FROST_GUARD_CHILL.zh-CN.md)。
