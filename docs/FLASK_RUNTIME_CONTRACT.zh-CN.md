# 生命/魔力药剂初版接口（v0.26在制）

统一实例四字段不变：`{uid,kind:"flask",definition_id:"flask:life"|"flask:mana",payload:{}}`。非堆叠1×2；位置为原bag/recovery或`{kind:"flask_slot",slot_id:"flask_1"…"flask_5"}`。原240格不变，其他类型不能入药剂槽。

schema18前必须用冻结v17规则验证。首次迁移/新档各加一瓶生命和魔力，直接入新槽1/2；唯一migration_flask_UID避冲突、旧serial/UID/位置/预算/材料/ledger不变，注册上限+2只容纳赠瓶，普通奖励仍受原注册上限。v18不重复赠瓶。原字节备份和候选先写盘再发布仍由Store负责。

`FlaskCatalog.definition(id)`返回name/resource/icon_path/size/max_charges/cost/duration/recovery_fraction/description/rarity/effects/stats/category/definition_id/kind。resource为health或mana；预算30充能、每次10、3秒35%使用瞬间最大资源。两图原始PNG与prompt来自root，保持真实透明，512px导入。

- `state.flask_slots()`：固定五条slot_id/uid/definition_id/name/resource/icon_path/size；空槽uid等为空
- `state.owned_flasks()`：已验证全部药剂UID→definition_id副本
- `state.award_flask(definition_id)`：复用权威入袋与序号，返回UID或空串
- 复用`move_item(uid,destination,revision,path)`进行入袋/换槽/交换，仍完整候选验证且写盘成功后发changed
- `arena.flask_statuses()`：五条槽位加charges/max_charges/cost/active/resource_active/remaining_seconds/can_use/code/reason。active只指当前效果来源UID，resource_active指同资源恢复中；全部返回副本
- `arena.use_flask(slot_id)`：ok/code/reason及运行状态，非空有效槽、活着且未暂停、资源未满、同资源未恢复、充能足够才扣10。Alt+1…5先于数字技能处理

运行态单独按UID保管：`{charges_by_uid,active_by_resource}`。active字段有uid/remaining_seconds/rate/locked_maximum。移动或卸下不补充；效果锁定后即使卸下/丢弃也按已消耗次数继续。满资源提前结束，生命与魔力可同时恢复。死亡清效果，真实restart_run重置全体本场拥有药剂为30；这是既有每次新战斗的资源重置语义。构筑JSON不保存临时charge，普通读档后新战斗照此初始化，不承诺外部旧档恢复反作弊。

仅已有合法根怪奖励门通过时，给当时已装瓶各+1，上限30；后代/演示/重复尸体不加。每60有效根怪额外掉1瓶，按生命/魔力交替，零新增RNG；原奖励调用顺序不变。满包不加入物品也不增serial。回复每帧不发changed/不写盘，物品奖励仍合并到原一次进度事务。

阶段证据：模型209项、实际Main资源/Alt输入路由/换槽不刷新/真实根怪奖励与原RNG/死亡重开68项通过。原始文件迁移边界与root UI接线仍在本批验收，不视为已发行。没有600秒或历史全量。
