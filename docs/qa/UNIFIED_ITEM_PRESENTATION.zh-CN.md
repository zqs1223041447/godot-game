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
