# PoE1 普通装备词缀研究参考

入口：[中文设计说明](docs/POE_AFFIX_REFERENCE.zh-CN.md)。本目录是数据研究参考，不是已经接入游戏的装备/制作系统。

- `source_manifest.json`：固定上游commit、版本、原始文件URL、SHA256及Git blob校验
- `filter_spec.json`：可复现的范围、排除项与权重计算
- `normalized/`：筛选后的数值/机制数据、底材、适用池、派生层级、统计报告
- `design/godot_mapping.json`：原创语义映射建议，区分已支持能力与待实现规则
- `tools/affix_reference.py`：获取、筛选、验证、查询；仅Python标准库
- `validation.json`：最近一次验证结果

## 复现

在此目录运行：

```sh
python tools/affix_reference.py fetch
python tools/affix_reference.py build
python tools/affix_reference.py validate
python tools/build_design_mapping.py
```

原始输入下载到已忽略的`raw/`。固定哈希不匹配时会停止，绝不把变动源混入原快照。

## 查询示例

```sh
python tools/affix_reference.py query \
  --base-id Metadata/Items/Weapons/TwoHandWeapons/Bows/Bow1 \
  --ilvl 83 --affix prefix --group LocalPhysicalDamagePercent
```

可重复传`--existing ModId`测试已有词缀组互斥。查询器只做候选资格/权重，不模拟物品稀有度词缀总数、特殊制作货币、掉落分布或整件成品概率。

## 使用边界

上游RePoE解析器是MIT；GGG导出数据并不因此获得MIT许可。本目录只保留研究所需的标识符、数值和机制事实，不复制游戏词缀创意名称、描述文本、美术或音频。原始文件仅为本地研究缓存；勿随游戏发布。是否可以以特定形式再分发仍需按权利方条款审查。与游戏集成时保留`.gdignore`并显式排除本目录，实际运行数据应使用独立原创命名/数值与适配逻辑。
