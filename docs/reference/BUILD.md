# 离线构筑手册

玩家入口是同目录 `index.html`。将整个 `docs/reference/` 放在 Windows 可执行文件旁，解压后直接打开即可使用。HTML 内嵌全部数据、CSS 与 JavaScript；仅使用同目录的原创运行时 PNG。不使用服务器、fetch、CDN、账号或浏览器存储，不读取或修改游戏存档。

## 重建

在仓库根目录，以隔离的 XDG 目录运行（Windows 不需要设置 XDG）：

```sh
XDG_DATA_HOME=/tmp/reference-build/data XDG_CONFIG_HOME=/tmp/reference-build/config XDG_CACHE_HOME=/tmp/reference-build/cache \
  godot --headless --path . --script res://tools/export_reference.gd
python3 tools/build_reference.py
```

第一步直接消费 EquipmentCatalog 的 canonical all_base_ids/all_affix_ids、pool_profiles 与 current_loot_profile、GameData、SupportRegistry、JewelData、PassiveData、MechanicRegistry 和 MonsterCatalog。技能示例取自新建 BuildState 与三件龙卷机制装备配置，经 SkillCompiler、DamageResolver 和 DamagePreview 生成。关联词缀也通过实际编译结果比较建立。覆盖示例使用 AllocationRules，不在浏览器重写分配合法性。受击图、原始/有效火抗与逐次命中已知目标示例使用 DefenseRules、DamageResolver 和实际 MonsterCatalog；不会在 HTML 生成器中重新计算减伤。灰烬守卫出现/奖励条件来自生产 fire_encounter_policy。其上限、接触分量、词缀数值和当前掉落权重是本游戏原创平衡，不宣称为 PoE 源规则。

`catalog.json` 是可复现的运行时导出，不含生成时间。`reference.css` / `reference.js` 是 HTML 构建输入，运行页面时无需单独载入。PNG 和 `art/manifest.json` 由 `tools/export_reference_art.gd` 导出；此脚本的本机渲染要求和参数见其文件头。修改运行时、版本或素材清单后应重跑两步。

## 检查

```sh
XDG_DATA_HOME=/tmp/reference-test/data XDG_CONFIG_HOME=/tmp/reference-test/config XDG_CACHE_HOME=/tmp/reference-test/cache \
  godot --headless --path . --script res://tests/reference_export_test.gd
python3 tests/reference_catalog_test.py
node --check docs/reference/reference.js
python3 tools/build_reference.py --check
```

检查覆盖完整目录 ID、编译示例配置、所有辅助组合、所有孔的共享分析器覆盖结果、来源版本、全部条目与内部链接、清单中全部本地素材、SVG 几何边界及确定性重建。源树权威数据保留固定版本的英文名称、原始词句和图结构；v57可见条目通过同一Godot本地化接口展示中文和逐条实现状态，用于明确执行边界；不引入官方图像。研究来源为 PoE 天赋树 3.29.1 和词缀研究 3.29.3.3 / RePoE 固定提交 a77305840b4cc8555eeeea144eac3eeddeff134b。

## 渲染验证状态

当前环境的云浏览器拒绝 file:// 协议，并阻止 localhost 预览。没有绕过限制。因此本次未验证浏览器的实际渲染、200% 缩放、窄视口、搜索/筛选点击、历史返回或树图点击。静态检查和运行时一致性检查已经执行；不能把这些检查当作完整浏览器验收。


## v0.53.0 火焰持续伤害加成

新增规则入口为 `index.html#rules-source_fire_dot`。`catalog.json.source_fire_dot` 直接导出实际 SourceTreeRuntime、CombatData、SkillCompiler、BurnRuntime、EmberProliferationRules 与 schema31→32 迁移结果；HTML 只展示已算好的燃烧每秒伤害与总量，不再次乘加成。默认导出命令还通过原 `export_source_execution_coverage.gd.build_report()` 同时刷新 `source-tree-coverage.json`，无需另一次 Godot 启动。

本批新增8个可分配的完整标准普通节点。七职业各自非起点普通节点可达数676→685，额外的第9个可达节点1550原本已完整。火焰精通36313仍因未支持的自身点燃时长词句而锁定；Elementalist记录12738虽可解析完整词句，但仍不在标准可分配图，未接入升华点数来源。

当前批次聚焦检查：

```sh
python3 tools/build_reference.py --check
python3 tests/fire_dot_reference_test.py
node --check docs/reference/reference.js
```

检查包括8节点、56条职业路径、8组真实编译器前后比较、3条完整合法路线、93个渲染数值、全部内部链接、无来源/零值编译结构、余烬继承与67张旧图像的字节指纹。原始源词句与几何保持；新增字段为明确的schema32执行证据。本批没有新增图像、装备词缀池或宝石，没有运行历史完整套件、导入工程、性能长跑或截图验收。详细命令、退出码和日志见 `../qa/v053-reference/`。

## v0.54.0 源天赋加速燃烧

入口为 `index.html#rules-source_faster_burn`。`catalog.json.source_faster_burn` 导出实际源节点解析、SkillCompiler、BurnRuntime、余烬传播和schema32→33迁移结果。三个完整标准节点11364/43684各5%、59766为15%，合计F=0.25。既有火焰持续伤害加成M结算后，每秒伤害乘1.25，基础3秒压缩至2.4秒；原始完整时长总量理论不变，按 `max(1e-9,1e-12*abs(old_total))` 检查浮点误差。

页面直接读取已生效的roles.dps、roles.total和最终duration，不再乘算。初始施放冻结burn_faster；余烬继承已计算DPS和压缩后的绝对截止时间，不重新取得完整时长。当前只由玩家燃烧消费，不代表流血、中毒或完整异常体系已实现。

七职业各685→688，21条真实合法路径及一条包含全部三节点的完整分支均有同源证据。Deadly Draw 48823仍因弓技能持续伤害而partial；非标准Wasting Affliction 19686仍因异常伤害提高而partial，没有新增精通或其他新可达节点。英文源名称、词句、几何和67张原有PNG保持。

本批实际聚焦检查：

```sh
python3 tools/build_reference.py --check
python3 tests/faster_burn_reference_test.py
node --check docs/reference/reference.js
```

一次Godot无头导出同时更新catalog与source-tree-coverage；以上检查首次均通过。8组真实编译器示例包含M=0.10/F=0.25，123个页面数值与导出对应，58类旧目录结构保持；11处旧派生属性字典新增零值字段是明确的结构扩展，零F技能编译字节保持。没有运行历史完整套件、工程导入或截图。详细命令、退出码、来源指纹和日志见 `../qa/v054-reference/`。

## v0.55.0 锻纹短刃

本节记录v0.55历史验收；其普通攻击零W结论已由下方v0.56普通近战规则替代。v0.55已经飞出的旧投射物快照仍冻结原规则。

新增入口为 `index.html#rules-forgeblade` 与随机装备条目 `equipment-forgeblade`。`catalog.json.forgeblade` 来自实际底材/词缀目录、合法物品、SkillCompiler、CraftingRules和schema33→34纯迁移函数。5个合法隔离样本导出95个命中包，73个HTML数值逐一核对；全部其他role的本地贡献为零，同时验证全局暴击与资源仍是全局。

样本明确固定B18、基础暴击5%/150%，没有职业三属性、天赋、其他装备与辅助。原始命中包、后modifier普通命中和零防御单次期望分别展示；不把隔离输入当默认角色，也不称为实战DPS。双本地T1由合法四缀金装承载。

`canonical_v34`采用25/20/10/10/30/5分布，旧所有命名池和profile保留。现有六工艺与伤害/暴击定向重铸复用；短刃生命/魔力偷取定向禁用。schema34只扩展装备词汇，源天赋执行政策33保持；历史迁移示例继续导出各自固定版本。

本批聚焦命令：

```sh
python3 tools/build_reference.py --check
python3 tests/forgeblade_reference_test.py
node --check docs/reference/reference.js
```

导出只调用一次Godot，12.875秒、exit0、无错误行。旧catalog通过明确新增内容、资格/版本元数据与裂刃消费者解释投影后，与独立v54基线语义hash完全相同；不是忽略旧实例或只比部分数值。源树全部execution与覆盖JSON逐字节保持，旧67张PNG保持，新短刃PNG直接复制原字节。聚焦检查与确定性构建均通过；不运行历史全量、600秒或新增每版截图验收。完整命令、退出码、失败调试记录和指纹见 `../qa/v055-reference/`。

## v0.56.0 短刃近战普攻

新增入口`index.html#rules-melee_basic`，同源数据为`catalog.json.melee_basic`。装备短刃时普通攻击使用半径60、全角90°、最多1目标的近战direct；基础系数与附加效用各1.0，hit/attack/melee、不含area。保留原attack_timer与0魔力，裂刃95/180°、2.8系数、12魔力/1.4秒保持。

实际Canonical装备UID给出白装原包22、默认20力量后22.88，合法六族T3原包31、默认力量后32.24；隔离编译器样本与真实默认属性分开。纯位置计划在新建内存状态通过完整schema校验，未读写玩家存档。旧v55飞箭原B18经过当前冻结读取器仍保持原包。新近战没有secondary、返回或飞行结束爆炸，不占弹体容量。

```sh
python3 tools/build_reference.py --check
python3 tests/melee_basic_reference_test.py
node --check docs/reference/reference.js
```

唯一Godot导出12.606秒、exit0、无错误行；构建及以上聚焦检查均通过。26个近战卡+72个短刃卡数值逐项对应，90个真实命中包，2个实际装备示例、2个旧飞箭冻结示例。旧catalog完整投影仅放行明确批准的新短刃basic行为、精确描述、消费者元数据和版本，所有其他旧内容与源树执行保持，68图字节保持。组合输出提高是新行为，不声称短刃同seed战斗等价或实战DPS；无新schema、gem、词族或图片。完整结果与首次基线捕获器的文本匹配调试记录见`../qa/v056-reference/`。

## v0.57.0 天赋中文展示

原`catalog.source_tree`保持英文身份、数值、几何和execution；新增独立`source_tree_localization`展示投影，直接取当前Godot Localization，不在Python重新判断支持。源天赋卡片及火DoT/faster引用表使用同一中文名称/逐原条标记，中英文搜索保留但英文只作隐藏别名。

3390卡片包含3389个非空名称与一个无坐标空名root结构哨兵，后者沿共享适配器显示“节点名称缺失”；不添加原始名称或伪造图坐标。2974独立词句中388已实现、2586标注，1837专精选项与39分区同源。

唯一Godot导出14.628秒/exit0，所有64个旧catalog段只允许游戏版本变化，68原PNG与全部source execution/覆盖保持。3808锚点/20028链接和其他卡片精确投影通过；19个辅助卡自动版本文案及root哨兵的测试前提修正保留原日志，无重导出或生产公式修改。

本批只运行 `tests/passive_localization_reference_test.py`、确定性HTML构建与JS语法检查。详情见[本批图鉴证据](../qa/v057-reference/README.md)。

## v0.61.0 坚决技艺

新增入口 `index.html#rules-resolute_technique`，数据来自 `catalog.json.resolute_technique`。源31961完整原双行块只授予一个开关：命中不能被闪避，同时所有命中不能暴击。七职业的可达预算与7级野蛮人11点真实路径见[规则说明](../RESOLUTE_TECHNIQUE.zh-CN.md)。没有扩开条件“精准技艺”、新精通或任意多行词句。

示例先把旧装备合法放回包，再装备已有棱光长弓与终焰护符；两边使用同一7级野蛮人路径，仅改变最后1点。实际Canonical、Compiler、AttackHitRules、DamageResolver与DefenseRules导出7类命中角色。敏捷型闪避320时普通攻击命中率94%→100%，成功非暴击伤害35.2不变，每次尝试期望33.9152→35.2；零闪避时36.08→35.2，明确显示禁暴击代价。它们不是实战DPS。攻击、法术和独立爆炸一并禁暴击，护甲及抗性仍参与减伤；网页不重复公式。

正式Godot导出一次通过：16.810秒、exit0、无错误行或输入漂移。HTML构建、确定性重建、JS语法与本批聚焦检查均通过。59个页面权威数值、3814个唯一锚点及全部内部/本地资源链接核对完成。旧catalog只投影57处精确批准的新增章节、零属性、版本与31961执行/中文状态差异后，与独立v60语义hash完全相同；装备、词缀、掉落池与旧61张运行时/68张图鉴PNG保持。source-tree-coverage严格等于仅31961从unsupported转full、七职业各多可达一个节点的期望，其余节点、精通、源文本和几何保持。

字体首轮完整扫描发现UI新文案的唯一缺字“括”，首次失败完整保留。保持原文案，按原同源字体仅补这一字；定向验证1.070秒exit0，旧1655全部字形与度量保留，mapped1656覆盖全部1651需求。175份运行时文本输入保持，未重复90秒全扫描或已过Godot、F8、历史战斗。详细生成记录与独立验证见[本批证据](../qa/v061-reference/README.md)。


## v0.62.0 灰烬皮甲护甲与闪避

新增入口 `index.html#rules-defense_rating_affixes`；两个新词族的固定点数、档位、权重与五选三前缀资格来自EquipmentCatalog。`catalog.json.defense_rating_affixes`使用完整合法Canonical装备位置和真实职业统计，再调用AttackHitRules/DefenseRules，导出四个装备取舍、42个职业/闪避档位端点、四个目录物理攻击和五类100点命中。HTML展示已算结果，不重写角色、防御或命中公式。

原三抗卡保留v0.60的三资源/三抗六词预算与显式词汇37制作见证，明确当前39词池和新前缀取舍。原始/有效抗性、护甲物理边界、attack准入、燃烧不读双防御与盾魔血顺序分别说明；新资料不把隔离单次命中比较称为实战DPS。

本次Godot导出一次21.377秒、exit0，无错误行或输入漂移。HTML构建、确定性重建、JS语法与聚焦资料检查通过；168个HTML权威数值、3817个唯一锚点及所有内部/本地资源链接核对完成。完整旧catalog只接受72处明确的新章节/新族、当前词池资格/版本、主动当前奖励样本变化，投影后与独立发布v61语义hash一致；原三抗预算与历史显式制作seed保持。源政策38及英文源树、中文展示、执行覆盖逐字节保持，61张运行时PNG与68张图鉴PNG原字节保持。

字体只运行collect_required与cmap，177份运行时文本需要1652字符，发现唯一新增缺字“革”。首次旧字体结果完整保留；随后同源仅补“革”，定向验证0.949秒确认177份文字输入未变、原1656字形/度量保持，最终1657映射覆盖1652需求。完整字体证明见[本批记录](../qa/v062-reference/README.md)，没有重复全量字形扫描、历史完整战斗或GUI截图。完整规则见[护甲闪避说明](../DEFENSE_RATING_AFFIXES.zh-CN.md)。

## v119 遗迹庭园：有界原生地图增量

新增入口 `index.html#maps-ruins_garden`；地图装置列出五图。新增字段仅为 `catalog.exploration_maps.maps.ruins_garden`，不刷新历史构筑、四图数据或源执行覆盖。正式城镇选择地图/阶级/词缀 → 准备地图 → 开启地图；遗迹庭园不在历史免费测试选项内。

```sh
XDG_DATA_HOME=/tmp/godot-v119-reference/data XDG_CONFIG_HOME=/tmp/godot-v119-reference/config XDG_CACHE_HOME=/tmp/godot-v119-reference/cache \
  godot --headless --path . --script res://tools/export_ruins_garden_reference.gd
python3 tools/merge_ruins_garden_reference.py
python3 tools/build_reference.py
python3 tools/merge_ruins_garden_reference.py --check
python3 tools/build_reference.py --check
python3 tests/ruins_garden_reference_test.py
node --check docs/reference/reference.js
```

单图导出复用正式目录、原生模块轮廓、准备后的两个绕行与一个脱离角色的I档Plan。SVG直接画4条/99顶点原生轮廓、14段真实路网、25初始实体、入口和7路标，不使用包围盒假墙。三档经济与首领预警均读取实际目录。旧3815卡中仅地图装置和探索规则补充当前入口与历史证据边界；其余3813卡、完整旧catalog原字节、美术和历史QA保持。旧catalog交给新版生成器时，整页HTML也与原版逐字节相同。

无Main、收费/存档事务、战斗、全量历史导出或渲染。运行范围、保全基线和日志见[本批有界导出记录](../qa/v119-reference/README.md)。
