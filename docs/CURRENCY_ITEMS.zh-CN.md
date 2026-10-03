# schema16 校准碎片物品

schema16 将旧制作钱包中的校准碎片改为行囊中的真实堆叠物品。规范实例如下：

```json
{
  "uid": "currency_calibration_shard_000001",
  "kind": "currency",
  "definition_id": "currency:calibration_shard",
  "payload": { "quantity": 37 }
}
```

碎片物品占用 `1×1`，只允许位于 `bag` 或可见的 `recovery`。单堆与全库存总量上限都沿用旧材料上限 `1,000,000,000`；全库存总量统计所有位置，可消费余额只统计 `bag`。`recovery` 中的碎片不能用于校准。零数量堆、布尔/小数/负数量、未知 kind 或定义、堆叠和全库存超限均拒绝。

`CanonicalBuildRules.VERSION` 为 16。持久化的 `crafting` 对象严格只有 `revision`；没有 `materials` 字段，也没有隐藏钱包副本。现有 `CraftingTransactionPlanner` 仍用于报价和规则重算，主集成每次从背包碎片堆构造临时 `materials.calibration_shard` 投影，结果随后写回实际物品堆，不将 Planner 投影保存。

## 迁移

v14、v15 输入分别通过原有完整校验器验证其旧字段、物品 kind、背包位置、余额和最多 1024 件物品限制。v14 继续先经过既有 v14→v15 双页行囊转换；v15 直接进入货币迁移。v1–v13 仍先经过既有旧存档验证和 v13→v14→v15 链路。旧版本校验器明确拒绝新增的 `currency` kind，不能把注入的新实例当作合法旧档。

余额为零时不创建物品；非零余额创建一个稳定 UID 堆，不改变 `next_item_serial`。迁移先扫描双页行囊的第一个合法格；满包时放入 `recovery`。v16 允许更大的物品注册表，以保留恰有 1024 件物品的合法旧档并额外加入一个余额堆。

加载器完整校验候选后，先将原文件的字节写入对应 `.v14-backup.json` / `.v15-backup.json`（v13 及更早版本仍使用实际来源版本号），检查来源字节没有变化，再原子写入 schema16。只有新档写盘成功后才替换内存。未来版本、来源变动、备份冲突、候选错误或写盘失败都会保留当前内存和旧档内容；失败迁移可能留下已成功创建的原字节备份供恢复。

## 运行时事务

- `crafting_balance()` 实时合计背包中的校准碎片，不读取 `crafting.materials`。
- 校准按稳定 UID 顺序扣除背包堆；扣至零的堆连同位置一并删除。recovery 堆不参与扣款。
- 回收先从完整候选中移除装备，再把收益合入现有背包堆。没有可合并的背包堆时，新堆使用回收装备释放的真实格；若没有可用格，则进入可见 recovery。
- 报价检查扣款和收益后的全库存总量不超过上限。候选物品、制作修订和装备变化一起校验并原子保存；写盘失败不改变内存。种子仍由原规则版本、制作修订与源装备摘要派生，失败重试得到相同掷值。
- `can_move_item(uid, destination, expected_revision) -> bool` 仍只报告现有操作是否可提交。`move_item(uid, destination, expected_revision, path)` 仍返回 `{ok, error_code, reason, revision}`。把碎片堆拖到同 kind、未满的目标堆会在一次完整候选中合并数量并删除源 UID。超过目标堆上限时整笔拒绝，不做部分移动；其他 kind 沿用原背包占格校验。

物品定义向展示层提供 `quantity`、`stack_limit`、`color`、`name` 与 `1×1` 尺寸。货币没有新增纹理依赖。

## 专项验收

从仓库根运行：

```sh
XDG_DATA_HOME=/tmp/godot-game-currency/data \
XDG_CONFIG_HOME=/tmp/godot-game-currency/config \
XDG_CACHE_HOME=/tmp/godot-game-currency/cache \
godot --headless --path . --script res://tests/currency_catalog_test.gd

XDG_DATA_HOME=/tmp/godot-game-currency/data \
XDG_CONFIG_HOME=/tmp/godot-game-currency/config \
XDG_CACHE_HOME=/tmp/godot-game-currency/cache \
godot --headless --path . --script res://tests/currency_item_migration_test.gd

XDG_DATA_HOME=/tmp/godot-game-currency/data \
XDG_CONFIG_HOME=/tmp/godot-game-currency/config \
XDG_CACHE_HOME=/tmp/godot-game-currency/cache \
godot --headless --path . --script res://tests/currency_transaction_test.gd
```

测试覆盖 v14/v15 零和非零余额、满包回收区、1024 件合法旧档边界、v13 代表迁移、旧 schema 的货币注入拒绝、同种堆合并与容量边界、recovery 不可消费、全库存上限、稳定 UID 扣款至零、回收格复用、报价过期、外部改档、写盘失败与同种子重试，以及 schema16 保存读回时不存在 `materials` 双账。
