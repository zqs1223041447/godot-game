# UnifiedItemPresentation 只读视图协议

`UnifiedItemPresentation.view(model, uid)` 继续返回物品名称、种类/品质、旧说明文本字段等既有信息，并添加以下可选字段供悬停卡或其他消费者使用：

```gdscript
{
    "tags": Array[String],
    "function": String,
    "base_stats": Array[Dictionary], # {"label": String, "value": String}
    "modifiers": Array[Dictionary], # {"label": String, "value": String, "polarity": String}
    "preview_lines": Array[String],
}
```

`polarity` 为 `"benefit"`、`"cost"` 或 `"neutral"`。字符串值由展示层呈现，不包含用于 UI 猜测的编码约定。

## 来源和边界

- 主动宝石标签来自 `GemCatalog` 能力和 `SkillCompiler` 用固定中性快照一次编译后缓存的基础配方事件标签；编译伤害被丢弃。辅助宝石的需求标签来自 `GemCatalog`，辅助家族与技能适用范围来自 `SupportRegistry`，适用范围按辅助 ID 缓存。
- 主动宝石静态属性取自 `GameData` / `CombatData` 的配方值与实例等级、品质字段。活跃组合消耗和伤害说明来自模型已有 `get_group_cast(group_id)` 结果，放在独立的 `preview_lines`。基础属性不读当前角色伤害，也不复述施放预览。
- `modifiers` 将辅助操作记录映射为显示标签、值与收益方向；在主动宝石视图中，来自当前施放快照的已链接辅助，在辅助宝石视图中显示该辅助自己的操作。`effect_lines` 继续镜像施放预览以维持旧消费者兼容；结构化卡优先显示 `preview_lines`，不会显示重复的旧效果段。
- `view` 和既有 `comparisons(model, uid)` 只读取模型 API 并复制其字典/数组；不会变更装备、宝石、施放快照或库存，不从 description 中解析数值或效果。

## 定向测试

```sh
godot --headless --editor --path . --import # 新检出且尚无 .godot 导入缓存时先运行一次
godot --headless --path . --script res://tests/unified_item_presentation_test.gd
```

2026-10-03、Godot 4.6.3：27 项、0 失败。测试使用 `GemCatalog` 真正义项、真实 `SkillCompiler` cast 和仿真只读模型，验证字段来源、当前预览与基础数据隔离、支持辅助修饰符、缓存及输入快照不变。

## v21 语义复核（2026-10-03）

- 主动宝石的基础标签只从该技能的内在配方事件读取：bolt/frost 取 projectile，tornado 取 parent/child，nova/meteor 取 direct，chain 取 bounces。编译器会预备给装备独立爆炸等组合效果使用的 `secondary` 事件；这些预备事件不等于宝石自带标签，不计入 bolt/frost/tornado 的基础“爆炸 / 次级 / 范围”标签。tornado 保留自己的投射物/分裂，nova/meteor 保留 direct 范围标签。装备提供的独立爆炸等当前组合效果仍由父级模型的施放快照提供给 `preview_lines`，不会写回固有基础标签。
- `other_components_more` 标签明确标记排除范围为“非物理 / 非火焰 / 非冰霜 / 非闪电伤害”，而不是笼统的“其他伤害”。乘算 `more` 值使用“总增 20%”或“总降 20%”表述，避免与加算属性的“增加”混淆。
- 最新 `tests/unified_item_presentation_test.gd`：78 项、0 失败；遍历 `GemCatalog` 全部 24 个定义，对八种主动宝石逐一核对标签边界，并验证四种 ElementSupports 的排除标签、总增/总降语义。历史 27 项记录是前一轮测试覆盖数。
