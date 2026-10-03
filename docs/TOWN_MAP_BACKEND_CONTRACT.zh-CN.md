# v0.28 城镇测试与有限地图：后端/UI合同

## 文件所有权与存档

后端工作树 `/workspace/scratch/a51485f153de/v028-town-map-model`，分支 `codex/v028-town-map-model`，从v27冻结2a2fa38起步。后端独占 main.gd、CanonicalGameState、save模块、新scripts/world与scripts/town模块及对应测试/资料。root独占game_hud、scripts/ui及城镇交互画面。双方不覆盖v27冻结源或安装包。

正常游戏仍是原入口、原 `user://build_save.json`。用户点击可选「城镇测试」后才创建/打开 `user://town_test_build_save.json`；首次从当前完整有效构筑复制，保留旧UID，先原子落盘再切换。已有测试档再次打开不覆盖。测试商店免费、供应无限但背包/注册表有上限，只供真实已实现目录；测试碎片也为该测试档真实物品。退出测试回正常存档，不把测试物品或材料转回原档。禁用供应配置时不能领取。

C专用于属性。schema19局部迁移先按冻结v18规则校验并原字节备份，再去掉C绑定；组、宝石、辅助与其余字段保持。受影响行提示为未绑定，不自动选另一按键。地图草案/本轮状态暂不持久保存，不增存档地图字段。

## main.gd 公开接口

下面方法均返回脱离内部别名的数据。命令统一 `{ok:bool,code:String,reason:String,...}`；失败不产生部分物品或状态。UI只传ID、修订，不传价格/结果/种子。

信号：
- `world_context_changed`：区域/草案/目标/服务能力变化，UI重新取world_context
- `build_state_replaced`：arena.state和arena.build_save_path已切换。HUD必须重新绑定新model及保存路径，取消原确认/拖拽，防旧UI往原档写入

方法：
- `world_context() -> Dictionary`：`mode` normal/town/map/map_complete，`test_mode:bool`，`save_path:String`，`revision:int`（世界命令修订），`run_revision:int`，`map_id:String`，`map_name:String`，`ordinary_kills:int`，`ordinary_target:int`，`boss_defeated:bool`，`can_return:bool`，`supply_enabled:bool`，`description:String`
- `enter_town_test(expected_revision:int) -> Dictionary`：normal时进入测试档城镇；先保存正常进度，失败不切换
- `leave_town_test(expected_revision:int) -> Dictionary`：town时保存测试档并回到正常档、新正常战斗；失败不切换
- `town_services() -> Array[Dictionary]`：固定六项 `{id,name,description,available,reason}`，ID为skill_merchant/equipment_merchant/passive_reset/jewel_merchant/crafter/map_device
- `town_stock(service_id:String) -> Array[Dictionary]`：`{id,name,kind,definition_id,description,icon_path,size,category,available,reason,price_label}`；price_label明确测试免费。装备商人另供两药剂、真实碎片领取项。只读预览，不制造UID
- `town_buy(offer_id:String,expected_revision:int) -> Dictionary`：revision为state.revision()，成功额外返回uid；仅town/test/supply enabled可用，统一完整候选原子入包。UID序号、满包与保存失败保护
- `town_reset_passives(expected_revision:int) -> Dictionary`：revision为state.revision()；退还已花普通点保当前起点，已镶珠宝保UID回背包，放不下可进可见待安置；一次保存。返回refunded_points、returned_jewels。UI二次确认
- 工匠沿用state.crafting_operations/crafting_quote/execute_crafting/cancel接口，必须传arena.build_save_path；领取碎片走town_buy，不新建材料钱包
- `map_options() -> Dictionary`：`{maps:Array,normal_modifiers:Array,special_modifiers:Array,max_normal:int,max_special:int,cost_policy:Dictionary}`。每定义至少id/name/description；地图含wave/ordinary_target/boss_id。cost_policy明确test_free，非消费旧材料
- `map_draft() -> Dictionary`：`{revision:int,map_id:String,normal_ids:Array[String],special_ids:Array[String],valid:bool,reason:String,summary:String,cost_label:String}`
- `craft_map(map_id:String,normal_ids:Array,special_ids:Array,expected_revision:int) -> Dictionary`：revision为map_draft.revision；town/test时免费应用合法选择，先完整编译再提交草案，失败不改草案，不用战斗RNG
- `start_map(expected_revision:int) -> Dictionary`：revision为map_draft.revision；先保存测试档，冻结已编译草案开始独立新战斗，成功返回world_context；旧草案确认不得重复开图
- `return_to_town(expected_revision:int) -> Dictionary`：revision为world_context.revision；map/map_complete或死亡后可用。先保留已得进度保存，再清场返城；未完成离开视为放弃本图，不存在恢复旧敌人/重复首领奖励

`build_save_path`为main公开String，所有HUD面板setup/交易明确使用此路径。Normal与测试模式切换是不同model实例，前端不可沿用旧model闭包。

## 首批真实地图与修饰

两张有限地图：旧庭试炼（wave4，24个普通根怪）和断垣试炼（wave5，36个普通根怪）。完成普通根怪目标后生成一个现有裂隙守卫；击败首领并处理剩余死亡后代后完成，停止生成，可返城。无额外地图货币/通关奖励，现有合法根怪XP/掉落/药剂充能照常，后代零奖励照常。

普通词缀最多2个：复用已实现强健（生命×1.20）、迅行（速度×1.10），EncounterCompiler/Admission负责根怪与后代只应用一次。

特殊词缀最多1个：霜纹巡逻或雷纹巡逻。仅把符合原物种的自然普通生成原型换成已有霜纹守卫/雷纹掠行体，保原roll的稀有度、机制、预算；原灰烬名额优先保留。实际命中/预警/抗性使用既有同源消费者，不添加冻结或感电。雷纹需要地图wave≥5，非法选择编译前拒绝。特殊词缀单独展示，不能把目录未支持行为当成效果。

城镇模式不生成怪、不推进伤害/攻击；可以安全移动并操作六类服务。地图消费当前构筑、五药剂、旧投射物/死亡/奖励机制，原正常模式不套地图规则。

## 验收

一次定向批验：v18原字节C迁移与无C等价；正常/测试存档隔离、首次复制/重进/返回/失败不切换；真实目录全基础供应与满包/旧revision/写盘失败；重置点数与珠宝保留；普通/特殊词缀实际消费者、非法配置先于RNG/ID，有限生成→首领→后代清场→返城、死亡/放弃边界。UI由root原生验证。无600秒或历史全量。
