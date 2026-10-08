# 正式首领待安置说明的最小同步

基线为已审并进入 main 的运行时提交 `a2f6f21669c43c037668756e512e9aa32c898923`。
本批独立分支为 `codex/formal-boss-recovery-reference`，仅同步现有玩法说明与 F8；不合并或推送 main。

现有 `EXPLORATION_MAPS.zh-CN.md` 的「完成、奖励与退出」及 F8 `rules-exploration_maps` 是对应入口，各补一段同文说明：

> 正式地图首领的稀有装备在背包放不下时进入待安置；按 I 腾出尺寸足够的连续空间后取回同一实例，UID 与词缀保持。原物品与序号上限不变。

F8 复用 `tools/build_reference.py`；只有目录新增 `exploration_maps.formal_boss_equipment_recovery` 说明字段时才追加该段，因此旧目录输入生成结果保持。该字段是批准行为的文字说明，不是新奖励执行器或存档字段。目录插入复用 `merge_ruins_garden_reference.member_span`，不重新序列化任何既有值。

## 局部检查

- `timeout 45s python tests/formal_boss_recovery_reference_test.py` 通过，详见 `preservation.json/log`。
- 3816 个卡片 ID 保持，仅 `rules-exploration_maps` 新增一段，其余3815卡字节相同。
- 搜索数据仅该卡的 `search` 更新；目录指纹正确，卡外 HTML 除对应搜索数据与指纹外逐字节不变。
- 旧目录语义与原值 token 全部保持；旧输入的 HTML 完全一致；玩法 Markdown 仅新增一段。
- 该卡原两个内部链接继续有效；运行时代码、素材、执行覆盖及旧验证记录保持。
- `timeout 45s python tools/build_reference.py --check` 通过，见 `build-check.log`；`git diff --check` 通过。

报告记录生成器、玩法说明和已合入运行时代码的 SHA256。仅运行上述本地 Python 检查，未重跑 Godot 导出、事务或战斗测试、长期检测、原生图形、Windows 导出或模型。

行为和保存边界沿用[运行时验收说明](../formal-boss-equipment-recovery/README.md)：原总量与序号限制仍生效，保存失败内存待重试不等同于崩溃持久原子性。当前说明没有承诺所有情况绝不丢落物，也没有扩展至其他奖励类型。
