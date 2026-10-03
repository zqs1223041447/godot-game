# GemCatalog 前置模块定向验收

本次只新增纯定义与实例模块，为 M2 后续接线准备稳定技能宝石/辅助宝石身份。它读取既有 `GameData.SKILLS` 与 `SupportRegistry`，复用 8 个技能、16 个辅助的名称、说明、能力标签及 `docs/reference/art/{skills,supports}/` 现有图标；不复制或重算技能/辅助效果。

## 接口与数据契约

- `GemCatalog.definitions()` 返回按命名空间索引的 24 个定义：`skill:<skill_id>` 和 `support:<support_id>`。
- `GemCatalog.definition(id)` 只接受完整稳定 ID，返回与目录隔离的定义副本。裸 ID、未知 ID 和错误类型返回 `{}`，不会回退或别名解析。
- `GemCatalog.create_instance(uid, definition_id)` 返回且只返回 `{uid, kind, definition_id, payload}`。`kind` 为 `skill_gem` 或 `support_gem`；`payload` 固定且仅有 `{level: 1, quality: 0}`。UID 必须是非空白字符串，未知 ID 或无效 UID 返回 `{}`。
- `GemCatalog.validate_instance(value)` 严格要求这四个字段、正确的定义与 kind、恰好两个 payload 字段，以及整数 `level == 1`、整数 `quality == 0`。浮点数 `1.0/0.0`、布尔值、额外字段、缺失字段和其他等级/品质均拒绝。当前 Godot JSON 解析会把数字读为浮点 Variant；后续持久化适配器需在校验前恢复为整数，本模块不负责 JSON 编解码。
- `GemCatalog.metadata_for_instance(value)` 对有效实例返回源名称、说明、图标、`[1,1]` 格子尺寸、`skill_id`/`support_id` 和原能力标签；无效实例返回 `{}`。返回的字典与数组均为副本。

定义分辨率使用 `skill:bolt`、`support:focus` 等有命名空间的 ID。同一 `definition_id` 可创建多个不同 UID 的独立实例；模块不维护 UID 全局唯一性或实例库存。

## 明确边界

等级与品质暂时没有消费方，因此本版拒绝任何非 `1/0` 值，且不把这些字段解释成伤害、消耗、稀有度或其他效果。模块不发放物品、不配置背包或支持槽位、不编译效果、不改存档/迁移/UI/主协调器。辅助的技能适配和执行定义仍由现有 `SupportRegistry` 及各规则提供器负责；宝石元数据只引用来源标签。

## 定向验证

运行环境：Godot 4.6.3；使用隔离的 XDG 数据、配置和缓存目录：

```sh
QA_ROOT="$(mktemp -d /tmp/godot-gem-catalog-XXXXXX)"
export XDG_DATA_HOME="$QA_ROOT/data"
export XDG_CONFIG_HOME="$QA_ROOT/config"
export XDG_CACHE_HOME="$QA_ROOT/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
godot --headless --path . --script res://tests/gem_catalog_test.gd
```

测试覆盖 24 个来源定义及图标、原始标签一致性、稳定 ID、四字段实例与严格 payload 拒绝、JSON 数字解析边界、未知/别名 ID、深层副本隔离、同定义不同 UID、确定性及全局 RNG 状态不变。该检查只运行新增定向测试，不执行完整项目套件。
