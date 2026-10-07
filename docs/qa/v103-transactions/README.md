# v103 抗性定向重铸：真实事务与界面接点

首次有界运行通过：**1,684 项检查，0 失败，Godot 退出码 0**。五个测试段为 1,683 项，另 1 项确认结果报告文件成功打开。没有失败重跑，没有改动 Model、Planner、保存 schema 或 UI 生产代码。

| 测试段 | 检查数 | 验证内容 |
| --- | ---: | --- |
| metadata_matrix | 662 | 目录全部底材；合法衣服/指环的普通、魔法、稀有组合；四个新目标的实际 available、reason、cost 与拒绝报价 |
| atomic_transactions | 777 | 14 个合法底材×抗性×稀有度组合；实际报价、取消、错 UID、写盘失败、同句柄重试、重复确认、穿戴、重载 |
| rejected_boundaries | 213 | 四抗分别覆盖魔法/稀有少 1 碎片、非持有 UID、状态过期、穿戴后过期/禁用、外部存档字节改写 |
| full_bag | 12 | 当前两页背包每格占满时，原位稀有指环重铸仍只扣 40 碎片，不分配新 UID，不挪格 |
| inventory_dialog | 19 | 真实 Main/CanonicalInventoryPanel 选择混沌抗性、请求并审阅确认文本、取消不变、确认一次、重复确认不扣款不重掷 |

## 同源证据

- [测试源码](../../../tests/resistance_targeted_transactions_test.gd)：来源装备由 `EquipmentCatalog.generate_for_pool()` 按当前底材池生成；种子和池 ID 保存在报告。所有源装备都经当前目录验证、真实模型奖励入库与正常存档写盘。稀有事务源是合法六词缀装备，未手写非法稀有物品。
- [原始运行日志](first/run.log) 与 [结果 JSON](first/transactions-report.json)：当前权威 schema=53、vocabulary=51。每个事务包含真实 quote、result、Craft.operation_metadata、生成源、最终装备与两个抗性 getter 的穿戴前后结果。
- [源码 SHA-256](first/source-hashes.sha256) 与 [基线提交](first/base-commit.txt)：固定测试、目录、重铸规则、模型、规划器、保存、抗性和实际 UI 接点源文件。
- `first/*-before.save` 是 14 份经当前 Model 重新读取验证的合法源存档；对应 `first/*.save` 是穿戴完成后的合法输出。`inventory-dialog-chaos.save` 是真实界面确认后的输出，共 29 份。F8 文档直接读取这些证据，不重新编造装备或再跑模型。

每次取消、错 UID、余额不足、穿戴禁用、存档变化和过期拒绝都比较完整内存与磁盘字节；UID、材料、序号和制作种子修订保持。失败写盘只增加一次尝试，不增加成功保存或 changed 信号；原句柄重试得到同一确定性输出。成功事务精确比较整份构筑，只有装备词缀、实际支付的碎片堆及两种修订号变化。

穿戴结果经 `get_resistance_profile()` 和 `get_chaos_resistance_profile()` 读取。测试核对目录百分比刻度、raw 与 effective 的确切值，元素/混沌上限保持，再由真实存档重载检查整份构筑、UID、词缀与两个 getter 完全一致。不添加最大抗性、不承诺阶级或更强数值。

## 运行方式与边界

Godot 4.6.3；Linux headless；已有依赖导入缓存；未运行 editor/import；写盘严格隔离至 `/tmp/godot-m1-v103-transactions-first/{data,config,cache}`。首轮命令：

```sh
XDG_DATA_HOME=/tmp/godot-m1-v103-transactions-first/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v103-transactions-first/config \
XDG_CACHE_HOME=/tmp/godot-m1-v103-transactions-first/cache \
V103_TRANSACTION_OUT="$PWD/docs/qa/v103-transactions/first" \
timeout 180 /usr/local/bin/godot --headless --path . \
  --script res://tests/resistance_targeted_transactions_test.gd
```

仅影响某一段时可指定 `V103_TRANSACTION_CASE=段名` 并使用新的临时隔离目录和报告目录。本次所有段首次通过，没有调用该重跑路径。

这是本批有界模型/保存/实际 UI 信号链验收；不是历史全量、实际鼠标渲染、Windows 实机或战斗伤害验收。旧四目标确定性差分和纯规则池边界由本批另一份规则证据负责。
