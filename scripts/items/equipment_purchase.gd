extends RefCounted
## Bounded town purchase service. Existing inventory helpers and _commit remain
## the only ownership, currency, placement and persistence authorities.
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Planner = preload("res://scripts/items/crafting_transaction_planner.gd")
const PATH := "user://build_save.json"
const COST := 8
const ITEM_LEVEL := 1
var _quotes: Dictionary = {}
var _sequence := 0

static func make_item(base_id: Variant, serial: int) -> Dictionary:
	if typeof(base_id) != TYPE_STRING or Gear.base_definition(base_id).is_empty() or serial < 1 or serial >= Rules.MAX_SERIAL: return {}
	return Items.wrap_equipment({"id":"gear_%06d" % serial,"base_id":base_id,"rarity":"normal","item_level":ITEM_LEVEL,"affixes":[]})

func offers(model: RefCounted, path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var guard := _guard(model, model.revision(), path)
	var space_reasons: Dictionary = {}
	for base_id: String in Gear.all_base_ids():
		var wrapped := make_item(base_id, 1)
		var preview := Items.definition_for_instance(wrapped)
		var size: Variant = preview.get("size", Vector2i.ONE)
		var reason: String = str(guard.reason)
		if guard.ok:
			if not space_reasons.has(size):
				var planned := _plan(model, base_id)
				space_reasons[size] = str(planned.reason)
			reason = space_reasons[size]
		rows.append({"id":"base:"+base_id,"base_id":base_id,"definition_id":wrapped.definition_id,
			"kind":"equipment","name":str(preview.name)+" · 物品等级 %d" % ITEM_LEVEL,
			"description":"普通无词缀底材，可装备或在工匠处赋魔；更高物品等级来自地图掉落。",
			"preview":preview,"icon_path":str(preview.get("icon_path","")),"size":size,
			"cost":COST,"paid":true,"purchase_kind":"equipment","price_label":"%d 校准碎片" % COST,
			"available":reason.is_empty(),"reason":reason})
	return rows

func quote(model: RefCounted, base_id: Variant, expected_revision: Variant, path: String, context: PackedByteArray) -> Dictionary:
	var guard := _guard(model, expected_revision, path)
	if not guard.ok: return guard
	if not Rules.reason(model._current,model._talent_validator,model._socket_ids).is_empty(): return _failure("invalid_build","构筑数据无效")
	var planned := _plan(model, base_id)
	if not planned.ok: return planned
	var reason := Rules.reason(planned.candidate,model._talent_validator,model._socket_ids)
	if not reason.is_empty(): return _failure("invalid_candidate",reason)
	var disk: Dictionary = model._gem_trade_disk_receipt(path)
	if not disk.ok: return _failure("save_changed","存档已变化或无法读取，请重新读取后操作")
	_sequence += 1
	var handle := "equipment:%d:%d" % [get_instance_id(),_sequence]
	while _quotes.size() >= 8: _quotes.erase(_quotes.keys()[0])
	_quotes[handle] = {"model_id":model.get_instance_id(),"before":model.snapshot(),"candidate":planned.candidate,
		"path":path,"disk":disk,"context":context.duplicate(),"base_id":base_id,"uid":planned.uid}
	return {"ok":true,"code":"","reason":"","handle":handle,"base_id":base_id,"uid":planned.uid,
		"name":Gear.base_definition(base_id).name,"item_level":ITEM_LEVEL,"cost":{"calibration_shard":COST}}

func execute(model: RefCounted, handle: Variant, base_id: Variant, context: PackedByteArray) -> Dictionary:
	if model._busy: return _failure("busy","当前操作尚未结束")
	if typeof(handle) != TYPE_STRING or not _quotes.has(handle): return _failure("unknown_quote","底材报价已失效")
	var issued: Dictionary = _quotes[handle]
	_quotes.erase(handle)
	if typeof(base_id) != TYPE_STRING or base_id != issued.base_id: return _failure("target_mismatch","所选底材已变化")
	if model.get_instance_id() != issued.model_id or context != issued.context: return _failure("stale_world","城镇或存档已切换，请重新获取报价")
	var guard := _guard(model, issued.before.revision, issued.path)
	if not guard.ok: return guard
	if not Planner._same_data(model._current, issued.before): return _failure("stale_quote","构筑已变化，请重新获取报价")
	if model._gem_trade_disk_receipt(issued.path) != issued.disk: return _failure("save_changed","存档已变化，装备与碎片保持原样")
	var result: Dictionary = model._commit(issued.candidate.duplicate(true),issued.path)
	if not result.ok: return _failure(str(result.error_code),str(result.reason))
	_quotes.clear()
	return {"ok":true,"code":"","reason":"","uid":issued.uid,"base_id":base_id,"cost":{"calibration_shard":COST},"revision":model.revision()}

func cancel(handle: String) -> void: _quotes.erase(handle)
func clear() -> void: _quotes.clear()

func _guard(model: RefCounted, expected_revision: Variant, path: String) -> Dictionary:
	if path != PATH or model._path != PATH: return _failure("normal_profile_required","底材购买只能使用已打开的正式存档")
	var guard: Dictionary = model._normal_journey_guard(expected_revision,path)
	if not guard.ok: return _failure(str(guard.error_code),str(guard.reason))
	if not model.save_block_reason(path).is_empty(): return _failure("save_blocked","当前存档受写保护")
	if not model.pending_items().is_empty(): return _failure("pending_items","请先安置已有待安置物品")
	return {"ok":true,"code":"","reason":""}

func _plan(model: RefCounted, base_id: Variant) -> Dictionary:
	var candidate: Dictionary = model.snapshot()
	var wrapped := make_item(base_id,int(candidate.next_item_serial))
	if wrapped.is_empty(): return _failure("invalid_base","底材不存在或物品序号已达上限")
	var balance: int = model.crafting_balance()
	if balance < COST: return _failure("insufficient_shards","背包内校准碎片不足")
	var currency: Dictionary = model._set_bag_currency_balance(candidate,balance-COST)
	if not currency.ok: return _failure(str(currency.error_code),str(currency.reason))
	if not model._place_journey_reward(candidate,wrapped): return _failure("bag_full","背包没有底材的可用空间，物品上限或序号已用尽")
	candidate.revision += 1
	return {"ok":true,"code":"","reason":"","candidate":candidate,"uid":wrapped.uid}

static func _failure(code: String, reason: String) -> Dictionary:
	return {"ok":false,"code":code,"reason":reason}
