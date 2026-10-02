# 离线构筑手册

玩家入口是同目录 `index.html`。将整个 `docs/reference/` 放在 Windows 可执行文件旁，解压后直接打开即可使用。HTML 内嵌全部数据、CSS 与 JavaScript；仅使用同目录的原创运行时 PNG。不使用服务器、fetch、CDN、账号或浏览器存储，不读取或修改游戏存档。

## 重建

在仓库根目录，以隔离的 XDG 目录运行（Windows 不需要设置 XDG）：

```sh
XDG_DATA_HOME=/tmp/reference-build/data XDG_CONFIG_HOME=/tmp/reference-build/config XDG_CACHE_HOME=/tmp/reference-build/cache \
  godot --headless --path . --script res://tools/export_reference.gd
python3 tools/build_reference.py
```

第一步直接消费 EquipmentCatalog 的 canonical all_base_ids/all_affix_ids、pool_profiles 与 current_loot_profile、GameData、SupportCatalog、JewelData、PassiveData、MechanicRegistry 和 MonsterCatalog。技能示例取自新建 BuildState 与三件龙卷机制装备配置，经 SkillCompiler、DamageResolver 和 DamagePreview 生成。关联词缀也通过实际编译结果比较建立。覆盖示例使用 AllocationRules，不在浏览器重写分配合法性。受击图、原始/有效火抗与逐次命中已知目标示例使用 DefenseRules、DamageResolver 和实际 MonsterCatalog；不会在 HTML 生成器中重新计算减伤。灰烬守卫出现/奖励条件来自生产 fire_encounter_policy。其上限、接触分量、词缀数值和当前掉落权重是本游戏原创平衡，不宣称为 PoE 源规则。

`catalog.json` 是可复现的运行时导出，不含生成时间。`reference.css` / `reference.js` 是 HTML 构建输入，运行页面时无需单独载入。PNG 和 `art/manifest.json` 由 `tools/export_reference_art.gd` 导出；此脚本的本机渲染要求和参数见其文件头。修改运行时、版本或素材清单后应重跑两步。

## 检查

```sh
XDG_DATA_HOME=/tmp/reference-test/data XDG_CONFIG_HOME=/tmp/reference-test/config XDG_CACHE_HOME=/tmp/reference-test/cache \
  godot --headless --path . --script res://tests/reference_export_test.gd
python3 tests/reference_catalog_test.py
node --check docs/reference/reference.js
python3 tools/build_reference.py --check
```

检查覆盖完整目录 ID、编译示例配置、所有辅助组合、所有孔的共享分析器覆盖结果、来源版本、全部条目与内部链接、清单中全部本地素材、SVG 几何边界及确定性重建。没有把源游戏的原始数据、名称、文本、图像或布局引入玩家手册。研究来源为 PoE 天赋树 3.29.1 和词缀研究 3.29.3.3 / RePoE 固定提交 a77305840b4cc8555eeeea144eac3eeddeff134b。

## 渲染验证状态

当前环境的云浏览器拒绝 file:// 协议，并阻止 localhost 预览。没有绕过限制。因此本次未验证浏览器的实际渲染、200% 缩放、窄视口、搜索/筛选点击、历史返回或树图点击。静态检查和运行时一致性检查已经执行；不能把这些检查当作完整浏览器验收。
