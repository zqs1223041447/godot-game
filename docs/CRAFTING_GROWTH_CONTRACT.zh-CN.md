# v0.27 四工艺接入合同

本批为本游戏原型预算，并非 PoE 原样经济。当前 schema18、真实校准碎片物品与240格背包不变。

|操作|名称|合法输入与结果|碎片费用|
|---|---|---|---:|
|enchant|赋魔|普通→魔法，1–2条合法随机词缀|8|
|elevate|升格|保留魔法原词缀，变稀有并补至4–6条|24|
|augment|补缀|魔法/稀有保留原词缀，加1条合法词缀|6|
|reforge|重铸|魔法/稀有保持稀有度，重掷全部词缀|魔法10/稀有28|

实际池、互斥族、前后缀上限、物品等级与正权重阶级由当前 EquipmentCatalog 决定。无法达到合法结果时拒绝且不收费。重铸可能相同或更差；不暴露种子或随机结果。ID、底材与物品等级保持，词缀结果走现有目录完整验证和属性解析。

## 轻量菜单数据

`state.crafting_operations(uid: Variant, path: String = "user://build_save.json") -> Array[Dictionary]`

固定顺序：salvage、recalibrate、enchant、elevate、augment、reforge。每项字段：

- `operation/label/description/risk`：String，由规则同源派生
- `cost/materials`：Dictionary，和权威报价相同的 `{calibration_shard: int}` 形状。前者消耗，后者为回收预计收益。空映射表示没有该项；非法装备不能计算费用时也是空映射，UI 应根据 available/reason 显示不可用，不能声称免费
- `available`：bool，当前选择/所有权/已知写保护/资格/余额允许显示操作
- `reason`：String，不可用原因；可用为空

无选择、非装备、固定装备也返回六项禁用记录。该方法不签发报价、不复制完整构筑、不生成随机结果、不读取存档内容、不写入状态。已登记保护路径可能进行既有路径同一性检查。最终磁盘状态与完整构筑以点击后的权威报价和提交为准。

`CraftingRules.operation_metadata(operation)` 提供不涉及物品和费用的名称、描述、风险。调用者不能据 metadata 扣款或修改物品。

## 事务接口

现有 `crafting_quote(operation, uid, path)` 返回单个权威报价。成功具有 handle、source_instance、cost、materials、operation、revision；没有随机结果/seed。UI 仅在按下具体工艺时调用，确认以这次返回数据为准；取消、换选择应取消句柄。

`execute_crafting(handle, source_instance)` 保留完整构筑和磁盘来源检查、真实碎片堆扣除、候选全验证以及先原子保存后内存/changed 的顺序。失败不消费，原句柄同种子可重试；成功使旧句柄失效。只存制作 revision，不新增材料账。

旧回收、校准继续 `original-crafting-prototype-v1` 种子语义与旧成本；新四项用 v2 + 操作ID。旧已发布存档不迁移。回收装备不可撤销，校准与重铸可能降低属性。

## 验收范围

当前14底材、26族、5池，按目录真实解锁区间验证可达结果与回收价值上界；随机样例仅验证执行，不冒充上界证明。另验真实物品事务、失败回滚/取消/旧句柄/重试、原有回收校准等价、新结果当前消费者。运行和结果记录由最终批次验收补齐。本阶段合同不是已完成整体验收声明。
