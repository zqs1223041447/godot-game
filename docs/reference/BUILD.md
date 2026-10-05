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

检查覆盖完整目录 ID、编译示例配置、所有辅助组合、所有孔的共享分析器覆盖结果、来源版本、全部条目与内部链接、清单中全部本地素材、SVG 几何边界及确定性重建。源树条目保留固定版本的英文名称、原始词句和图结构，用于明确执行边界；不引入官方图像。研究来源为 PoE 天赋树 3.29.1 和词缀研究 3.29.3.3 / RePoE 固定提交 a77305840b4cc8555eeeea144eac3eeddeff134b。

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
