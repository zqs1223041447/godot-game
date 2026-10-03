# 源天赋树纯分配规则

`SourceTreeAllocationRules.analyze(context, selection, socketed)` 只判断一次候选天赋分配的最终图是否合法。它不读取游戏状态、珠宝物品定义或存档，也不抽取随机数、不修改参数。调用方提供经过自身验证的节点图与点数预算，并负责珠宝身份、payload真实性、保存和整笔操作的消费。

## 输入契约

三个输入对象必须符合下列形状；对象与节点记录拒绝额外字段。

```gdscript
context = {
    "nodes": {
        "node_id": {
            "id": "node_id",
            "type": "start | small | notable | keystone | socket | mastery | proxy",
            "group_id": "source group ID",
            "position": Vector2(...),
            "blighted": false,
            "class_id": -1, # 非职业起点；起点使用非负整数
            "mastery_effects": [], # 源节点许可的整数 effect ID
        },
    },
    "adjacency": {"node_id": ["neighbor_id"]},
    "start_id": "own class start ID",
    "budget": 0, # 调用方给出的 0..123 整数；分析器不补点
}
selection = {
    "allocated": ["node_id"],
    "masteries": {"mastery_node_id": 12345},
}
socketed = {
    "socket_id": {"rule_id": "", "radius": 0.0},
}
```

`start` 节点必须有唯一、非负的 `class_id`；其他节点的 `class_id` 必须是 `-1`。`mastery` 节点必须带非空、无重复的源 effect ID 列表，其他类型不得带 mastery effects。所有节点 ID 必须与字典键相同；邻接表须覆盖全部节点、仅含已知邻居、无自环或重复边，且每条边双向。位置必须是有限 `Vector2`，group ID 必须非空。

未知 `type` 一律拒绝。已知 `proxy` 类型可出现在完整图中，但不能被分配，也不能作为通路。`blighted` 节点和除 `start_id` 以外的任何职业起点均不可分配。

普通珠宝记录仅允许空 `rule_id` 与 `0.0` 半径。唯一支持的特殊规则是 `disconnected_radius`，其半径须为有限非负浮点数。珠宝身份、物品定义和该半径是否为该物品的真实数值由调用方验证。

## 判定顺序与语义

1. `allocated` 必须是 context 节点的唯一字符串 ID 集合，且必须包含自己的起点。预算按 `allocated.size() - 1` 计算；每个其他节点（包括 mastery 和远程点）花 1 点。
2. 从自己的起点，仅沿已分配的普通邻接节点做 BFS。`mastery` 不进入 `normal_connected`，也不能用作路径中继。
3. 不在普通连通集内的已分配节点仅可为 `small` 或 `notable`，且必须位于至少一个已激活 `disconnected_radius` 珠宝孔的半径内。距离边界包含等号。`keystone`、`socket`、`mastery`、`start` 和 `proxy` 均不能远程分配。
4. `socketed` 中每个孔必须是已分配且普通连通的 `socket`。普通珠宝占用孔但不授予范围。特殊珠宝只能从自身普通连通的孔覆盖小型/显著节点；远程点不扩展通路，也不能打开孔或提供新的覆盖来源。
5. 每个已分配 mastery 必须在 `selection.masteries` 里选择恰好一个、由该节点 `mastery_effects` 明确允许的整数 ID。该 mastery 所属组还必须有至少一个已分配且普通连通的 `notable`。远程 notable 不满足这个条件。不同 mastery 不得选择相同 effect ID；额外、未分配或非 mastery 节点的选择均拒绝。

`normal_connected` 返回按字符串排序的普通连通已分配节点，包括自己的起点，不包括 mastery 或远程分配。`active_sockets` 是按字符串排序的已分配、普通连通且出现在 `socketed` 的孔，包含普通珠宝孔。`remote_sources` 以远程可覆盖节点 ID 为键，值是按字符串排序的授予它的已激活特殊孔 ID 数组；它包含当前未分配但可远程分配的小型/显著节点，不包含普通连通节点或其他类型。

成功结果严格包含 `legal`、`reason`、`normal_connected`、`remote_sources`、`active_sockets`、`spent`、`remaining` 七个字段。失败时 `reason` 非空，三个授权集合为空，`spent` 和 `remaining` 均为零；不返回部分合法图或部分点数账本。`remaining` 只从调用方预算扣除实际花费。

## 验证

`tests/source_tree_allocation_rules_test.gd` 同时覆盖小型因果图和随仓标准树：标准图断言 2,387 节点 / 2,697 边，检查物理路径、退款断连、孔依赖、范围等号边界、mastery 来源与远程 notable 反例、123 点预算及超预算拒绝；小图覆盖远程不可扩路、mastery 不作通路、重复 effect ID、非法节点类型和失败原子性。测试还核验输入不变与全局 RNG 序列不变。

这份规则刻意不执行高级效果或升华经济，不修改 `SourceTreeData`、主模型、存档、原始树数据或 UI。导入图中的属性效果是否有真实消费者属于其他阶段。
