# 构筑重构设计约束（历史基线）

本文保留 2026-10-03 M0 重构时确定的设计约束，不作为当前版本、存档 schema、发布状态或待办清单。当前开发约定见 [AGENTS.md](../AGENTS.md)；现行行为以对应实现、测试和专项契约为准。下列数值与接口记录历史设计，不覆盖后续正式实现。

## 物品、定义、位置

统一注册表 items 按UID索引。记录结构为 {uid, kind, definition_id, payload}；kind仅equipment/jewel/skill_gem/support_gem。定义与持有实例分开。旧gear/jewel和固定示例物的现有UID完整保留；新实例由唯一分配器产生，不允许UI提供或重用已消费UID。类别前缀可以不同，所有UID必须全局唯一。

装备payload先保留既有合法实例的5字段及固定示例信息；珠宝保留其既有合法字段；主动/辅助宝石payload含等级、品质，默认1/0，扩展数值必须真有消费者。definition_id对应不可变运行定义，不能从名字或背包位置判断身份。通用位置校验器只消费主控已解析的metadata，不能代替装备/珠宝/宝石payload真实性检查。

locations为同UID键集合，每件实例恰有一个位置。准确形状：

- {kind: bag, x, y}
- {kind: equipment, slot_id}
- {kind: passive_socket, node_id}
- {kind: skill_main, group_id}
- {kind: skill_support, group_id, index}，index为0..4
- {kind: recovery, index}，仅用于迁移待安置；不得当普通掉落的无限背包

共享背包12×8，只有实际bag位置占格。卸下/取回若放不下，整笔拒绝；不删除实例、不覆盖格子。迁移确有溢出时保留为清楚显示的待安置记录，先处理后领取更多物品。位置与物品数据分开更新，但同一完整候选校验后原子提交。

## 位置纯校验API

ItemLocationRules.validate(metadata_by_uid, locations, context) → {ok,error_code,reason,occupied_cells,occupied_targets}。

metadata_by_uid={uid:{kind,category,size:[w,h]}}。equipment类别为下述8种；其余category为空。尺寸、坐标和索引要求真正整数，拒布尔/浮点/额外字段。context准确为{columns:12,rows:8,equipment_slots:{目标:类别},skill_group_ids:[稳定行ID],passive_socket_ids:[合法源孔ID],allow_recovery:bool}。

每个UID必须且只能有一个合法位置；bag内不越界/重叠，装备目标类型匹配，技能主槽/辅助槽/天赋孔各接收正确kind，同目标不重复。失败后二个occupied字典为空，成功结果为副本，不动输入/RNG。树连通、技能标签、装备需求、材料/磁盘状态由上层最终验证。

## 九装备位

目标顺序：weapon/body_armour/amulet/ring_1/ring_2/boots/belt/gloves/helmet。类别为weapon/body_armour/amulet/ring/boots/belt/gloves/helmet。ring_1和ring_2属于同ring类别，穿戴命令带明确目标。

EquipmentSlots纯API：all_slots()、category_for_slot(id)、targets_for_category(category)、legacy_slot(id)、target_reason(category,target)。最后成功空串，失败稳定错误码。迁移只映射armor→body_armour、charm→amulet；已经规范的槽位可幂等通过，未知拒绝。底材与词池沿已有局部/全局语义扩充，不能只加空栏位。

## 技能组合与施放身份

skill_groups存稳定group_id与显示顺序，UID位置表是主/辅助宝石归属的唯一事实；不要同时维护第二份可漂移的拥有关系。每行1主+5辅助，容量严格由10+active_additional_skill_slots计算。增加行与原行同规则；容量下降仅将超出行标为不激活，保留组、宝石和位置，不强塞回背包或删实例。

同名主动宝石不同UID可在不同组独立装配；同组不允许相同辅助定义重复生效，除非未来明确设计叠加消费者。现有16辅助都保留，适配按原生能力标签和实际作用域，不由装备临时加的分量改变资格。五个辅助均须进入耗魔、冷却、伤害和行为编译，不能只画五孔。

战斗快捷键绑定group_id，不绑定技能名称或显示行下标；冷却按稳定组身份记录。移动行、换键不重置冷却，移动主宝石不能通过换组免费刷新原已触发的冷却。多实例的共享/独立规则由主控统一执行并测试。所有激活行都可配置输入绑定，旧五个键仅是默认快捷映射。施放快照继续冻结当时构筑；命中时读目标实时防御。

## 菜单协议

MenuRouteState只管理一个当前根窗口：inventory/passive_tree/skill_gems/debug_build/debug_monsters/pause/settings。I或B行囊，T天赋，K技能，F6/F7开发面板；同入口开关，切系统替换当前根，按键echo不重复触发。Esc有窗口关闭、无窗口打开pause。UI控制器读同一状态，不能复制库存。独立根场景共享主题、悬停卡和拖拽协议；战场保持静止。

## 缓存与动态边界

稳定属性、效果源和技能结构按构筑内容/规则版本复用，UI读副本。装备/珠宝/天赋/技能宝石变化必须失效；纯经验增长、金币材料或背包坐标变化不该让所有技能重编译。等级变化和任何真正影响稳定属性的条件源要失效。

生命、法力、冷却、当前目标抗性、临时状态、动态条件仍按原结算时机读取，不缓存命中结果或把动态状态冻结为永久属性。原投射物快照与新施放隔离，拒绝仍在扣费前。迁移期间保留公开可变旧模型的内容签名校验，之后规范事务修订替代无谓重复扫描。

## 新保存与一次迁移

目标新格式预留 version、items、locations、next_item_serial、skill_groups、bindings、talents、progress、crafting、migration_ledger；准确字段/验证上限由总控迁移实现统一锁定，子任务不得先写新格式。

旧装备/掷值/UID/材料/revision和合法进度保留，armor/charm槽映射新目标；旧技能配置转主/辅助实例，重复同定义也保留独立身份。原树分配不伪映射为新源节点：返还投入，按有限新预算分配，差额记录于migration_ledger。原镶嵌珠宝完整保存。树数据库随版本加载，存档只存选择、源ID及专精，不复制整份树数据。

新点数预算、默认源起点与专用点数将在锁定树规范化结果后一起确定；它们必须有限、可解释、记录迁移差额。M0不提前清空旧树或提高保存版本。首次真实迁移原字节备份、完整候选和先落盘后内存的失败恢复必须通过，未来文件继续保护。

## 完整树边界

官方3.29.1固定提交8bd138b32ea2631455cac5935bfab089f826094f，data.json SHA256=7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122。保留标准角色源ID/连线/原轨道角度/起点/专精/珠宝孔，独立升华等子图分开；不把不同模式混在一起。

导入完整度与运行效果完整度分别统计。原数值和适用条件不缩放，旧投影与额外安全上限退出新树；未有消费者的机制明确未实现，不能以导入或拒绝分配冒称全部效果完成。原画继续本项目素材，不复制原游戏美术。效应规则扩展按属性族与真实消费者成批实现。
