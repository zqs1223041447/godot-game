class_name CanonicalGameState
extends "res://scripts/save/canonical_build_store.gd"
## Gameplay projection over canonical ownership. No parallel mutable inventory,
## equipment or gem-link tables exist here.
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const FlaskModifiers=preload("res://scripts/combat/flask_modifier_rules.gd")
const Leech=preload("res://scripts/combat/leech_rules.gd")
const Journey=preload("res://scripts/world/normal_journey_state.gd")
const Flasks=preload("res://scripts/items/flask_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const GemTrade = preload("res://scripts/items/gem_trade_rules.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Critical = preload("res://scripts/combat/critical_strike_rules.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Data = preload("res://scripts/game_data.gd")
const ShardCatalog = preload("res://scripts/items/currency_catalog.gd")
const LOOT_PROFILE_ID := Gear.CANONICAL_LOOT_PROFILE_ID
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
var _build_signature := PackedByteArray()
var _stats_cache: Dictionary = {}
var _snapshot_cache: Dictionary = {}
var _cast_cache: Dictionary = {}
var _seen_content_epoch := -1
var _view_epoch := -1
var _view_token := PackedByteArray()
var _stats_build_count := 0
var _cast_compile_count := 0
var _basic_attack_profile_cache: Dictionary = {}


# Read-only compatibility projections for the existing arena renderer and HUD.
# Mutations still go through canonical transactions; returned maps are detached.
var equipped: Dictionary:
	get: return equipped_items()
var level: int:
	get: return int(_current.progress.level)
var xp: int:
	get: return int(_current.progress.xp)
var talent_points: int:
	get: return int(_current.talents.normal_points)
var skill_slots: Array[String]:
	get:
		var result: Array[String] = []
		for index: int in range(5):
			var group: String = group_for_key(KEY_1+index)
			result.append(str(skill_group(group).skill_id) if not group.is_empty() else "")
		return result
var jewels: Dictionary:
	get:
		var result := {}
		for uid: String in _current.items:
			if _current.items[uid].kind=="jewel":result[uid]=_current.items[uid].payload.duplicate(true)
		return result
var last_load_error: String:
	get: return last_error
var migrated_from_legacy := false
var migration_message := ""



func get_item_definition(uid: String) -> Dictionary:
	return item_definition(uid)


func get_build_view_token() -> PackedByteArray:
	if _view_epoch == _content_epoch: return _view_token.duplicate()
	_ensure_cache()
	var groups: Array = []
	for group: Dictionary in _current.skill_groups:
		groups.append([group.id,skill_group(group.id)])
	_view_token = var_to_bytes([get_instance_id(),_build_signature,groups,_current.bindings])
	_view_epoch = _content_epoch
	return _view_token.duplicate()


func get_skill_cast(skill_id: String) -> Dictionary:
	for group: Dictionary in _current.skill_groups:
		if skill_group(group.id).skill_id == skill_id and group_index(group.id) < active_group_capacity():
			return get_group_cast(group.id)
	return {"ok":false,"error":"未装配主动宝石"}



func get_stats() -> Dictionary:
	_ensure_cache()
	if _stats_cache.is_empty():
		_stats_cache = _stats_for(_current)
		_stats_build_count += 1
	return _stats_cache.duplicate(true)


func get_basic_cast() -> Dictionary:
	_ensure_cache()
	if _cast_cache.has("$basic"):return _cast_cache["$basic"].duplicate(true)
	var result:Dictionary=Compiler.compile_basic(get_combat_snapshot())
	if result.ok:_cast_cache["$basic"]=result.duplicate(true)
	return result


## Cheap admission metadata only. Complete casting snapshots remain detached
## and are compiled/read only after an attack can actually begin.
func get_basic_attack_profile() -> Dictionary:
	_ensure_cache()
	if not _basic_attack_profile_cache.is_empty(): return _basic_attack_profile_cache.duplicate()
	_basic_attack_profile_cache = {"delivery":"projectile"}
	for uid: String in _current.locations:
		var location: Dictionary = _current.locations[uid]
		if location.kind != "equipment" or location.slot_id != "weapon": continue
		var item: Dictionary = _current.items[uid]
		if item.kind == "equipment" and item.payload.get("base_id", "") == "forgeblade":
			_basic_attack_profile_cache = Compiler.Recipes.BASIC_MELEE.duplicate()
		break
	return _basic_attack_profile_cache.duplicate()


func get_combat_snapshot() -> Dictionary:
	_ensure_cache()
	if not _snapshot_cache.is_empty(): return _snapshot_cache.duplicate(true)
	var effects: Array[String] = []
	var additions: Array[Dictionary] = []
	var equipment: Dictionary = equipped_items()
	for uid: String in equipment.values():
		var definition := item_definition(uid)
		for effect: String in definition.get("effects", []):
			if not effects.has(effect): effects.append(effect)
		for source: Dictionary in definition.get("added_sources", []): additions.append(source.duplicate(true))
	_snapshot_cache = Combat.snapshot(get_stats(), effects)
	_snapshot_cache.accuracy = float(get_stats().accuracy)
	_snapshot_cache.added_damage_sources = additions
	var weapon: Dictionary = item_definition(str(equipment.get("weapon", "")))
	if weapon.has("weapon_profile"): _snapshot_cache.weapon_profile = weapon.weapon_profile.duplicate(true)
	return _snapshot_cache.duplicate(true)


func get_group_cast(group_id: String) -> Dictionary:
	var index: int = group_index(group_id)
	if index < 0: return {"ok":false,"error":"未知技能行"}
	if index >= active_group_capacity(): return {"ok":false,"error":"此行暂未激活，宝石与配置已保留"}
	var content := skill_group(group_id)
	if content.main_uid.is_empty(): return {"ok":false,"error":"尚未装入主动宝石"}
	_ensure_cache()
	var key := var_to_bytes([content, _current.items[content.main_uid].payload])
	if _cast_cache.has(group_id) and _cast_cache[group_id].key == key:
		return _cast_cache[group_id].cast.duplicate(true)
	var result := Compiler.compile_group(content.skill_id, get_combat_snapshot(), content.support_ids)
	_cast_compile_count += 1
	if result.get("ok", false):
		result.group_id = group_id
		result.main_uid = content.main_uid
		_cast_cache[group_id] = {"key":key,"cast":result.duplicate(true)}
	return result


func group_index(group_id: String) -> int:
	for index: int in range(_current.skill_groups.size()):
		if _current.skill_groups[index].id == group_id: return index
	return -1


func group_for_key(keycode: int) -> String:
	for binding: Dictionary in _current.bindings:
		if binding.keycode == keycode and group_index(binding.group_id) < active_group_capacity(): return binding.group_id
	return ""


func active_group_capacity() -> int:
	return 10 + int(get_stats().additional_skill_slots)


func equipped_items() -> Dictionary:
	var result := {}
	for uid: String in _current.locations:
		if _current.locations[uid].kind == "equipment": result[_current.locations[uid].slot_id] = uid
	return result


func bind_group(group_id: Variant, keycode: Variant, expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy", "当前操作尚未结束")
	if not expected_revision is int or expected_revision != revision(): return _failure("stale_revision", "技能配置已变化")
	if not group_id is String or group_index(group_id) < 0 or not keycode is int or not Rules.BINDABLE_KEYS.has(keycode): return _failure("invalid_binding", "快捷键不可用")
	var candidate := snapshot()
	var bindings: Array = []
	for binding: Dictionary in candidate.bindings:
		if binding.group_id != group_id and binding.keycode != keycode: bindings.append(binding)
	bindings.append({"group_id":group_id,"keycode":keycode})
	if bindings == candidate.bindings: return _failure("no_change", "")
	candidate.bindings = bindings
	candidate.revision += 1
	return _commit(candidate, path)


func _prepare_candidate(candidate: Dictionary) -> Dictionary:
	var capacity := 10 + int(_stats_for(candidate).additional_skill_slots)
	var ids: Dictionary = {}
	for group: Dictionary in candidate.skill_groups: ids[group.id] = true
	while candidate.skill_groups.size() < capacity:
		var serial: int = 1
		while ids.has("group_%06d" % serial): serial += 1
		var id := "group_%06d" % serial
		candidate.skill_groups.append({"id":id})
		ids[id] = true
	return candidate


static func _stats_for(candidate: Dictionary) -> Dictionary:
	var stats: Dictionary = Legacy.BASE_STATS.duplicate(true)
	stats.additional_skill_slots = 0.0
	stats.damaging_ailments_faster = 0.0
	stats.damage_taken_from_mana_before_life = 0.0
	for stat: String in ["maximum_fire_resistance_add", "maximum_cold_resistance_add", "maximum_lightning_resistance_add"]:
		stats[stat] = 0.0
	# Explicit v39 player balance: natural monsters retain their zero base.
	stats.crit_base_chance = 0.05
	stats.crit_base_multiplier = 1.5
	for stat: String in Critical.STAT_KEYS: stats[stat] = 0.0
	for stat: String in Leech.STAT_KEYS: stats[stat] = 0.0
	for stat: String in ["strength","dexterity","intelligence","physical_increased","chaos_increased","melee_physical_increased","attack_physical_increased","accuracy_increased","evasion_increased","armour","armour_increased","cold_resistance","lightning_resistance","life_regen","life_regen_percent","area_size_increased","spell_area_size_increased","melee_area_size_increased","projectile_speed_increased","shield_recharge_rate_increased","shield_recharge_start_faster","mana_cost_efficiency_increased","mana_cost_increased","flask_life_recovery_increased","flask_mana_recovery_increased","flask_charges_gained_increased","fire_dot_multiplier_add"]:
		stats[stat] = 0.0
	# Authored base ratings for this arena, not a copied monster/level table.
	stats.accuracy = 100.0
	stats.evasion = 15.0
	for uid: String in candidate.locations:
		if candidate.locations[uid].kind != "equipment": continue
		var definition: Dictionary = Items.definition_for_instance(candidate.items[uid])
		for stat: String in definition.get("stats", {}):
			if stats.has(stat): stats[stat] += float(definition.stats[stat])
	stats = SourceTree.apply_stats(stats,candidate)
	for rate: String in ["attack_speed", "move_speed", "mana_regen"]:
		stats[rate] *= 1.0 + float(stats[rate + "_increased"])
	var recharge:=Defense.recharge_profile(stats,"player")
	assert(recharge.ok,"Validated source recharge stats must compile")
	stats.shield_recharge_rate=recharge.rate;stats.shield_recharge_delay=recharge.delay
	return stats


func passive_analysis() -> Dictionary:
	return SourceTree.analyze(_current)


func available_passives() -> Array[String]:
	return SourceTree.available(_current)


func allocate_passive(node_id: Variant, mastery_effect: Variant, expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy","当前操作尚未结束")
	if not expected_revision is int or expected_revision != revision(): return _failure("stale_revision","天赋配置已变化")
	if not node_id is String or not mastery_effect is int or not SourceTree.Data.standard_ids().has(node_id): return _failure("unknown_node","未知源天赋")
	var candidate := snapshot()
	if candidate.talents.allocated.has(node_id): return _failure("already_allocated","天赋已分配")
	if candidate.talents.normal_points <= 0: return _failure("no_points","没有可用天赋点")
	var node := SourceTree.Data.node(node_id)
	if node.type == "mastery":
		candidate.talents.masteries[node_id] = mastery_effect
	elif mastery_effect != 0: return _failure("invalid_mastery","普通节点不能携带精通选择")
	candidate.talents.allocated.append(node_id)
	candidate.talents.normal_points -= 1
	candidate.revision += 1
	return _commit(candidate,path)


func refund_passive(node_id: Variant, expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy","当前操作尚未结束")
	if not expected_revision is int or expected_revision != revision(): return _failure("stale_revision","天赋配置已变化")
	if not node_id is String or not _current.talents.allocated.has(node_id): return _failure("not_allocated","此天赋尚未分配")
	var candidate := snapshot()
	candidate.talents.allocated.erase(node_id)
	candidate.talents.masteries.erase(node_id)
	candidate.talents.normal_points += 1
	candidate.revision += 1
	return _commit(candidate,path)


func select_class(class_id: Variant, expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy","当前操作尚未结束")
	if not expected_revision is int or expected_revision != revision(): return _failure("stale_revision","天赋配置已变化")
	if not class_id is int or SourceTree.Data.start_for_class(class_id).is_empty(): return _failure("unknown_class","未知职业起点")
	if class_id == _current.talents.class_id: return _failure("no_change","")
	if _current.talents.allocated.size() != 1: return _failure("allocated_nodes","先退还已分配天赋，再切换起点")
	var candidate := snapshot()
	candidate.talents.class_id = class_id
	candidate.talents.allocated = [SourceTree.Data.start_for_class(class_id)]
	candidate.revision += 1
	return _commit(candidate,path)


func _ensure_cache() -> void:
	if _seen_content_epoch == _content_epoch: return
	_seen_content_epoch = _content_epoch
	var equipped: Dictionary = {}
	for uid: String in _current.locations:
		if _current.locations[uid].kind in ["equipment", "passive_socket"]:
			equipped[uid] = [_current.locations[uid], _current.items[uid]]
	var signature := var_to_bytes([equipped, _current.talents, _current.progress.level])
	if signature == _build_signature: return
	_build_signature = signature
	_stats_cache.clear()
	_snapshot_cache.clear()
	_cast_cache.clear()
	_basic_attack_profile_cache.clear()


func cache_diagnostics() -> Dictionary:
	return {"stats_builds":_stats_build_count,"skill_compiles":_cast_compile_count,"cast_entries":_cast_cache.size()}


## Combat rewards participate in main's existing bounded progress transaction.
## UI ownership commands above still require successful persistence first.
## Town UI commands retain the same full-candidate save-first transaction.
func town_claim_offer(offer_id:Variant,expected_revision:Variant,path:String)->Dictionary:
	if not Legacy._save_paths_match(path,"user://town_test_build_save.json") or not Legacy._save_paths_match(_path,path):return _failure("test_profile_required","测试供应只能写入已打开的城镇测试档")
	if _busy:return _failure("busy","当前操作尚未结束")
	if not expected_revision is int or expected_revision!=revision():return _failure("stale_revision","库存已变化")
	var catalog=preload("res://scripts/town/town_catalog.gd")
	var offer:Dictionary=catalog.offer(offer_id)
	if offer.is_empty():return _failure("unknown_offer","未知测试供应")
	if not pending_items().is_empty():return _failure("pending_items","请先安置已有待安置物品")
	var candidate:=snapshot()
	var created_uid:=""
	if offer.supply_kind=="currency":
		var granted:=_set_bag_currency_balance(candidate,crafting_balance()+100)
		if not granted.ok:return _failure(granted.error_code,granted.reason)
	else:
		if candidate.items.size()>=Rules.V17_MAX_ITEMS or candidate.next_item_serial>=Rules.MAX_SERIAL:return _failure("item_limit","物品注册表或序号已达上限")
		var item:Dictionary=catalog.make_item(offer,int(candidate.next_item_serial))
		if item.is_empty() or candidate.items.has(item.uid):return _failure("invalid_offer","目录实例无效或身份冲突")
		created_uid=item.uid;candidate.items[item.uid]=item
		var position:=Transfer.first_bag_space_paged(Items.metadata_for_items(candidate.items),candidate.locations,Migration.paged_location_context(candidate,_socket_ids),item.uid)
		if position.is_empty():return _failure("bag_full","背包没有合适空间")
		candidate.locations[item.uid]=position;candidate.next_item_serial+=1
	candidate.revision+=1
	var result:=_commit(candidate,path)
	if result.ok:result.uid=created_uid;result.offer_id=offer_id
	return result


func reset_all_passives(expected_revision:Variant,path:String)->Dictionary:
	if _busy:return _failure("busy","当前操作尚未结束")
	if not expected_revision is int or expected_revision!=revision():return _failure("stale_revision","天赋构筑已变化")
	var candidate:=snapshot()
	var refunded:int=candidate.talents.allocated.size()-1
	var returned:=0
	var returned_uids:Array[String]=[]
	candidate.talents.allocated=[SourceTree.Data.start_for_class(int(candidate.talents.class_id))]
	candidate.talents.masteries.clear();candidate.talents.normal_points+=refunded
	for uid:String in candidate.locations:
		if candidate.locations[uid].kind!="passive_socket":continue
		candidate.locations[uid]={"kind":"recovery","index":candidate.items.size()+returned}
		returned_uids.append(uid)
		returned+=1
	candidate.locations=Transfer.compact_recovery(candidate.locations)
	var metadata:=Items.metadata_for_items(candidate.items)
	for uid:String in returned_uids:
		var position:=Transfer.first_bag_space_paged(metadata,candidate.locations,Migration.paged_location_context(candidate,_socket_ids),uid)
		if not position.is_empty():candidate.locations[uid]=position
	candidate.locations=Transfer.compact_recovery(candidate.locations)
	candidate.revision+=1
	var result:=_commit(candidate,path)
	if result.ok:result.refunded_points=refunded;result.returned_jewels=returned
	return result


func award_equipment(rng: RandomNumberGenerator, item_level: int, rarity: String = "", pool: String = "current") -> String:
	if _busy or rng == null or not pending_items().is_empty() or _current.next_item_serial >= Rules.MAX_SERIAL:
		return ""
	if pool != "current" and not Gear.pool_profiles().has(pool): return ""
	var before_rng: int = rng.state
	var uid: String = "gear_%06d" % int(_current.next_item_serial)
	var generated: Dictionary = Gear.generate_loot_profile(rng, uid, item_level, rarity, LOOT_PROFILE_ID) if pool == "current" else Gear.generate_for_pool(rng, uid, item_level, rarity, pool)
	var wrapped: Dictionary = Items.wrap_equipment(generated)
	if wrapped.is_empty() or not _admit_reward_item(wrapped):
		rng.state = before_rng
		return ""
	return uid


func award_gem(definition_id: String) -> String:
	if _busy or not pending_items().is_empty() or _current.next_item_serial >= Rules.MAX_SERIAL: return ""
	var uid: String = "item_%06d" % int(_current.next_item_serial)
	var wrapped: Dictionary = Gems.create_instance(uid, definition_id)
	return uid if not wrapped.is_empty() and _admit_reward_item(wrapped) else ""


func award_flask(definition_id:String)->String:
	if _busy or not pending_items().is_empty() or _current.next_item_serial>=Rules.MAX_SERIAL:return ""
	var uid:="item_%06d"%int(_current.next_item_serial)
	var wrapped:Dictionary=Flasks.create_instance(uid,definition_id)
	return uid if not wrapped.is_empty() and _admit_reward_item(wrapped) else ""

func owned_flasks()->Dictionary:
	var result:Dictionary={}
	for uid:String in _current.items:
		if _current.items[uid].kind=="flask":result[uid]=_current.items[uid].definition_id
	return result

func flask_slots()->Array[Dictionary]:
	var slots:Array[Dictionary]=[]
	var by_slot:Dictionary={}
	for uid:String in _current.locations:
		var location:Dictionary=_current.locations[uid]
		if location.kind=="flask_slot":by_slot[location.slot_id]=uid
	for slot_id:String in ItemLocationRules.FLASK_SLOTS:
		var row:Dictionary={"slot_id":slot_id,"uid":"","definition_id":"","name":"","resource":"","icon_path":"","size":Vector2i(1,2)}
		if by_slot.has(slot_id):
			var uid:String=by_slot[slot_id]
			var definition:Dictionary=Flasks.definition(_current.items[uid].definition_id)
			for field:String in ["definition_id","name","resource","icon_path","size"]:row[field]=definition[field]
			row.uid=uid
		slots.append(row)
	return slots


func award_random_gem(rng: RandomNumberGenerator) -> String:
	if rng==null or _busy or not pending_items().is_empty():return ""
	var before:int=rng.state
	var ids:Array=Gems.definitions().keys()
	ids.sort()
	var uid:=award_gem(str(ids[rng.randi_range(0,ids.size()-1)]))
	if uid.is_empty():rng.state=before
	return uid


func can_discard_item(uid:Variant)->bool:
	if not uid is String or not _current.items.has(uid) or _current.locations[uid].kind!="bag":return false
	if _current.items[uid].kind!="equipment":return true
	if Legacy._save_paths_match(_path,"user://town_test_build_save.json"):return true
	var payload:Dictionary=_current.items[uid].get("payload",{})
	return Legacy._save_paths_match(_path,"user://build_save.json") and not payload.is_empty() and payload.get("rarity")=="normal"


func discard_item(uid: Variant,expected_revision: Variant,path: String) -> Dictionary:
	if _busy:return _failure("busy","当前操作尚未结束")
	if not expected_revision is int or expected_revision!=revision():return _failure("stale_revision","物品状态已变化，请重新确认")
	if not uid is String or not _current.items.has(uid) or _current.locations[uid].kind!="bag":return _failure("not_in_bag","只可丢弃背包中的物品")
	if not can_discard_item(uid):return _failure("equipment_crafting","正常进度的装备请使用回收，固定示例装备保留")
	var candidate:=snapshot()
	candidate.items.erase(uid)
	candidate.locations.erase(uid)
	candidate.locations=Transfer.compact_recovery(candidate.locations)
	candidate.revision+=1
	return _commit(candidate,path)


func award_jewel(rng: RandomNumberGenerator) -> String:
	if _busy or rng==null or not pending_items().is_empty() or _current.next_item_serial>=Rules.MAX_SERIAL:return ""
	var before_rng:int=rng.state
	var uid:="jewel_%06d"%int(_current.next_item_serial)
	var wrapped:Dictionary=Items.wrap_jewel(Rules.Jewels.generate(rng,uid))
	if wrapped.is_empty() or not _admit_reward_item(wrapped):rng.state=before_rng;return ""
	return uid


func award_special_jewel() -> String:
	if _busy or not pending_items().is_empty() or _current.next_item_serial>=Rules.MAX_SERIAL:return ""
	var uid:="jewel_%06d"%int(_current.next_item_serial)
	var wrapped:Dictionary=Items.wrap_jewel(Rules.Jewels.generate_special(uid))
	return uid if not wrapped.is_empty() and _admit_reward_item(wrapped) else ""


func equip(uid: String) -> bool:
	var definition:=item_definition(uid)
	var targets:Array=Slots.targets_for_category(str(definition.get("category","")))
	if targets.is_empty():return false
	var target:String=targets[0]
	for value:String in targets:
		if not equipped_items().has(value):target=value;break
	return bool(move_item(uid,{"kind":"equipment","slot_id":target},revision(),_command_path()).ok)


func unequip(slot_id: String) -> bool:
	var canonical:String=Slots.legacy_slot(slot_id)
	var uid:String=str(equipped_items().get(canonical,""))
	var destination:=first_bag_position(uid)
	return not uid.is_empty() and not destination.is_empty() and bool(move_item(uid,destination,revision(),_command_path()).ok)


func slot_skill(index: int,skill_id: String) -> bool:
	if index<0 or index>=5 or not Data.SKILLS.has(skill_id):return false
	var group_id:String=group_for_key(KEY_1+index)
	if group_id.is_empty():group_id=_current.skill_groups[index].id
	var uid:=""
	for id:String in _current.items:
		if _current.items[id].definition_id=="skill:"+skill_id:uid=id;break
	if uid.is_empty():return false
	var result:=move_item(uid,{"kind":"skill_main","group_id":group_id},revision(),_command_path())
	if not result.ok:return false
	if group_for_key(KEY_1+index)!=group_id:return bool(bind_group(group_id,KEY_1+index,revision(),_command_path()).ok)
	return true


func _command_path() -> String:
	return _path if not _path.is_empty() else "user://build_save.json"


func _admit_reward_item(wrapped: Dictionary) -> bool:
	var candidate := snapshot()
	if candidate.items.has(wrapped.uid) or candidate.items.size() >= Rules.V17_MAX_ITEMS or candidate.revision >= Rules.MAX_SERIAL: return false
	candidate.items[wrapped.uid] = wrapped.duplicate(true)
	var metadata: Dictionary = Items.metadata_for_items(candidate.items)
	var position: Dictionary = Transfer.first_bag_space_paged(metadata, candidate.locations,
		Migration.paged_location_context(candidate, _socket_ids), wrapped.uid)
	if position.is_empty(): return false
	candidate.locations[wrapped.uid] = position
	candidate.next_item_serial += 1
	candidate.revision += 1
	if not Rules.reason(candidate, _talent_validator, _socket_ids).is_empty(): return false
	_accept_memory(candidate)
	_busy = true
	changed.emit()
	_busy = false
	return true


func add_xp(amount: int) -> bool:
	if _busy or amount <= 0 or _current.progress.level >= 1000 or _current.revision >= Rules.MAX_SERIAL: return false
	var candidate := snapshot()
	candidate.progress.xp += mini(amount, 1000000000)
	var leveled := false
	while candidate.progress.xp >= 12 + int(candidate.progress.level) * 8 and candidate.progress.level < 1000:
		candidate.progress.xp -= 12 + int(candidate.progress.level) * 8
		candidate.progress.level += 1
		if candidate.progress.level + 4 <= Migration.NORMAL_POINT_LIMIT: candidate.talents.normal_points += 1
		leveled = true
	if candidate.progress.level >= 1000: candidate.progress.xp = 0
	candidate.revision += 1
	# Only bounded progress/available points changed from an already valid state.
	# Main validates the full candidate once at its existing reward-transaction flush.
	_accept_memory(candidate)
	_busy = true
	changed.emit()
	_busy = false
	return leveled


func save_block_reason(path: String = "user://build_save.json") -> String:
	return _io.save_block_reason(path)


func crafting_change_already_saved() -> bool:
	# Revision inequality only proves this memory is NOT the saved bytes. Keep
	# the exact receipt for equal revisions, including same-revision mutations.
	return _disk_expected_exists and typeof(_current.get("revision")) == TYPE_INT and _current.revision == _disk_revision \
		and JSON.stringify(_current,"\t",true,true).to_utf8_buffer() == _disk_bytes


func unbind_group(group_id: Variant, expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy", "当前操作尚未结束")
	if not expected_revision is int or expected_revision != revision(): return _failure("stale_revision", "技能配置已变化")
	if not group_id is String or group_index(group_id) < 0: return _failure("invalid_binding", "未知技能行")
	var candidate := snapshot()
	var bindings: Array = []
	for binding: Dictionary in candidate.bindings:
		if binding.group_id != group_id: bindings.append(binding)
	if bindings == candidate.bindings: return _failure("no_change", "")
	candidate.bindings = bindings
	candidate.revision += 1
	return _commit(candidate,path)


const Craft = preload("res://scripts/items/crafting_rules.gd")
const CraftPlanner = preload("res://scripts/items/crafting_transaction_planner.gd")
var _craft_quotes: Dictionary = {}
var _craft_sequence := 0
var _gem_trade_quotes: Dictionary = {}
var _gem_trade_sequence := 0


func load_build(path: String = "user://build_save.json") -> bool:
	_craft_quotes.clear()
	_gem_trade_quotes.clear()
	migrated_from_legacy=false
	migration_message=""
	var old_version:int=0
	var c_groups:Array[String]=[]
	if FileAccess.file_exists(path):
		var file:=FileAccess.open(path,FileAccess.READ)
		if file!=null and file.get_length()<=MAX_SAVE_BYTES:
			var parser:=JSON.new()
			var parsed:Error=parser.parse(file.get_as_text())
			var raw:Variant=parser.data if parsed==OK else null
			if raw is Dictionary and Items._whole(raw.get("version"), 1, Rules.MAX_SERIAL):
				old_version=int(raw.version)
				if raw.get("bindings") is Array:
					for binding:Variant in raw.bindings:
						if binding is Dictionary and binding.get("keycode")==KEY_C and binding.get("group_id") is String:c_groups.append(binding.group_id)
	var loaded:=super.load_build(path)
	if loaded and old_version>0 and old_version<Rules.VERSION:
		migrated_from_legacy=true
		if old_version == Rules.V35_VERSION:
			migration_message="旧存档已原字节备份，三元素最大抗性天赋已开放；基础上限75%，本游戏安全上限83%。原始抗性需另行获得，原物品、点数与旅程保持，不额外赠物或赠点。"
		elif old_version == Rules.V34_VERSION:
			migration_message="旧存档已原字节备份，心灵升华的魔力先承伤已开放；原物品、技能组、天赋、点数与旅程保持，不额外赠物或赠点。"
		elif old_version == Rules.V33_VERSION:
			migration_message="旧存档已原字节备份，锻纹短刃已加入装备掉落与制作；原物品、技能组、天赋、点数与旅程保持，不额外赠物。"
		elif old_version == Rules.V32_VERSION:
			migration_message="旧存档已原字节备份，伤害型异常加速源天赋已开放；原物品、技能组、已分配天赋、点数与普通旅程保持，不额外赠物。"
		elif old_version == Rules.V31_VERSION:
			migration_message="旧存档已原字节备份，火焰持续伤害加成源天赋已开放；原物品、技能组、已分配天赋、点数与普通旅程保持，不额外赠物。"
		elif old_version == Rules.V30_VERSION:
			migration_message="旧存档已原字节备份，感电辅助宝石已开放购买；原物品、技能组、天赋与普通旅程保持，不额外赠物。"
		elif old_version == Rules.V29_VERSION:
			migration_message="旧存档已原字节备份，晴泉台地 I 已开放；旧两图进度、进行中地图与待领奖励保持，不额外赠送碎片或物品。"
		elif old_version == Rules.V28_VERSION:
			migration_message="旧存档已原字节备份，余烬扩散辅助宝石已开放购买；原物品、技能组、天赋与普通旅程保持，不额外赠物。"
		elif old_version == Rules.V27_VERSION:
			migration_message="旧存档已原字节备份，点燃辅助宝石已开放购买；原物品、技能组、天赋与普通旅程保持，不额外赠物。"
		elif old_version==24:
			migration_message="旧存档已原字节备份，生命与法力偷取已接入；原物品、节点与点数预算保持。偷取按实际扣除的敌人生命与护盾计算。"
		elif old_version==23:
			migration_message="旧存档已原字节备份，暴击构筑已接入；玩家基础暴击5%、暴击伤害150%。原物品、节点与点数预算保持。"
		elif old_version==Rules.V22_VERSION:
			migration_message="旧存档已原字节备份，源天赋药剂回复与充能增幅已接入；原物品、节点与点数预算保持，不额外赠物。"
		elif old_version==Rules.V21_VERSION:
			migration_message="旧存档已原字节备份，源天赋魔力成本效率与成本增加已接入；原物品、节点与点数预算保持，不额外赠物。"
		elif old_version==Rules.V20_VERSION:
			migration_message="旧存档已原字节备份，源天赋护盾充能已接入；原物品、节点与点数预算保持，不额外赠物。"
		elif old_version==Rules.V19_VERSION:
			migration_message="旧存档已原字节备份，源天赋范围与投射速度已接入；原物品、已分配节点和点数预算保持，不额外赠物。"
		elif old_version==Rules.V18_VERSION:
			migration_message="旧存档已原字节备份，C已预留给角色属性；原物品与技能组保持。"
		elif old_version >= Rules.V16_VERSION:
			migration_message="旧存档已原字节备份，药剂栏已启用并放入两瓶药剂；原物品、键位与天赋预算保持不变。"
		elif old_version == Rules.V14_VERSION:
			migration_message="旧存档已备份，背包已扩容。原物品与构筑保持不变，校准碎片已转为物品。待安置物品：%d 件。"%pending_items().size()
		elif old_version == Rules.V15_VERSION:
			migration_message="旧存档已备份，背包已扩容，校准碎片已转为物品。待安置物品：%d 件。"%pending_items().size()
		else:
			migration_message="旧存档已备份，装备、珠宝和技能已保留，旧天赋点已退还。校准碎片已转为物品。待安置物品 %d 件，预算外 %d 点保留记账。"%[pending_items().size(),int(_current.migration_ledger.excess_points_recorded)]
		if not c_groups.is_empty():migration_message+=" 原绑定C的技能行已改为未绑定："+"、".join(c_groups)
	return loaded


## A replaced profile remains readable for detached UI snapshots, but delayed
## UI callbacks must not mutate the old file. Each return loads a fresh model.
func retire_profile()->void:
	_craft_quotes.clear()
	_gem_trade_quotes.clear()
	_busy=true


func crafting_balance() -> int:
	var total := 0
	for uid: String in _current.items:
		if _current.items[uid].kind == "currency" and _current.locations[uid].kind == "bag":
			total += int(_current.items[uid].payload.quantity)
	return total


## Lightweight menu projection: no issued handle, disk read, full snapshot or
## rolled result. The already validated store owns instances; the selected
## instance is checked by the real craft rules. Clicking still requires quote.
func crafting_operations(uid: Variant, path: String = "user://build_save.json") -> Array[Dictionary]:
	var blocked := ""
	var source: Dictionary = {}
	if not uid is String or not _current.items.has(uid): blocked = "请先选择背包中的随机装备"
	elif _current.items[uid].kind != "equipment" or _current.items[uid].payload.is_empty(): blocked = "仅随机装备可进行此工艺"
	elif _current.locations[uid].kind != "bag": blocked = "请先把装备放入背包"
	elif int(_current.crafting.revision) >= Rules.MAX_SERIAL: blocked = "制作修订已达上限"
	elif not save_block_reason(path).is_empty(): blocked = "当前存档受写保护"
	else: source = _current.items[uid].payload
	var balance := crafting_balance()
	var total: Dictionary = ShardCatalog.total_quantity(_current.items)
	var result: Array[Dictionary] = []
	for operation: String in Craft.operation_ids():
		var entry: Dictionary = Craft.operation_metadata(operation)
		entry.merge({"cost":{}, "materials":{}, "available":false, "reason":blocked})
		if blocked.is_empty():
			var economics: Dictionary = Craft.operation_quote(source, operation)
			if not economics.ok: entry.reason = economics.reason
			else:
				entry.cost = economics.cost.duplicate(true)
				entry.materials = economics.materials.duplicate(true)
				var debit := int(entry.cost.get(Craft.MATERIAL_ID, 0))
				var credit := int(entry.materials.get(Craft.MATERIAL_ID, 0))
				if not total.ok: entry.reason = "校准碎片库存无效"
				elif balance < debit: entry.reason = "背包中的校准碎片不足"
				elif credit > ShardCatalog.INVENTORY_LIMIT - (int(total.quantity) - debit): entry.reason = "全库存校准碎片总量已达上限"
				else: entry.available = true
		result.append(entry)
	return result


func crafting_quote(operation: Variant, uid: Variant, path: String = "user://build_save.json") -> Dictionary:
	if int(_current.crafting.revision) >= Rules.MAX_SERIAL: return _craft_failure("revision_limit","制作修订已达上限")
	if not uid is String or not _current.items.has(uid): return _craft_failure("not_owned","当前没有此物品")
	var owned: Dictionary = _current.items[uid]
	if owned.kind != "equipment" or owned.payload.is_empty(): return _craft_failure("fixed_item","仅随机装备可进行此工艺")
	if _current.locations[uid].kind != "bag": return _craft_failure("item_equipped","请先把装备放入背包")
	if not Rules.reason(_current,_talent_validator,_socket_ids).is_empty(): return _craft_failure("invalid_build","构筑数据无效")
	var quote: Dictionary = CraftPlanner.quote(_craft_context(uid,path),operation,uid)
	if not quote.ok: return quote
	var all_currency: Dictionary = ShardCatalog.total_quantity(_current.items)
	var debit: int = int(quote.cost.get(Craft.MATERIAL_ID, 0))
	var credit: int = int(quote.materials.get(Craft.MATERIAL_ID, 0))
	if not all_currency.ok or crafting_balance() < debit or debit > int(all_currency.quantity):
		return _craft_failure("invalid_currency","校准碎片库存无效")
	var after_debit: int = int(all_currency.quantity) - debit
	if credit > ShardCatalog.INVENTORY_LIMIT - after_debit:
		return _craft_failure("currency_limit","全库存校准碎片总量已达上限")
	var disk: Dictionary = _canonical_disk_stamp(path)
	if not disk.ok: return _craft_failure("save_unreadable","存档无法读取")
	_craft_sequence += 1
	var handle := "%d:%d" % [get_instance_id(),_craft_sequence]
	while _craft_quotes.size() >= 8: _craft_quotes.erase(_craft_quotes.keys()[0])
	_craft_quotes[handle] = {"quote":quote.duplicate(true),"snapshot":snapshot(),"path":path,"disk":disk.duplicate(true)}
	var visible: Dictionary = quote.duplicate(true)
	visible.handle = handle
	return visible


func cancel_crafting_quote(handle: String) -> void:
	_craft_quotes.erase(handle)


func execute_crafting(handle: Variant, source_instance: Variant) -> Dictionary:
	if _busy: return _craft_failure("busy","当前操作尚未结束")
	if not handle is String or not _craft_quotes.has(handle): return _craft_failure("unknown_quote","报价已失效")
	var issued: Dictionary = _craft_quotes[handle]
	var quote: Dictionary = issued.quote
	if not CraftPlanner._same_data(source_instance,quote.source_instance): return _craft_failure("source_mismatch","装备已变化")
	if not CraftPlanner._same_data(_current,issued.snapshot):
		_craft_quotes.erase(handle)
		return _craft_failure("stale_quote","构筑已变化，请重新获取报价")
	if _canonical_disk_stamp(issued.path) != issued.disk:
		_reject(issued.path,"存档已被外部修改")
		return _craft_failure("save_changed","存档已变化，物品与碎片保持原样")
	# Preserve the existing seed contract exactly for the two released operations.
	var seed_text := JSON.stringify({"rules":Craft.seed_rules_version(quote.operation),"revision":int(_current.crafting.revision),"item":quote.source_instance},"",true,true)
	var seed_value := seed_text.sha256_text().substr(0,15).hex_to_int()
	var plan: Dictionary = CraftPlanner.plan(_craft_context(quote.item_id,issued.path),quote,seed_value)
	if not plan.ok: return plan
	var candidate := snapshot()
	var released_location: Dictionary = {}
	if quote.operation == "salvage":
		released_location = candidate.locations[quote.item_id].duplicate(true)
		candidate.items.erase(quote.item_id)
		candidate.locations.erase(quote.item_id)
		candidate.locations = Transfer.compact_recovery(candidate.locations)
	else:
		candidate.items[quote.item_id] = Items.wrap_equipment(plan.candidate.equipment_instances[quote.item_id])
	candidate.crafting = {"revision":plan.candidate.revision}
	var currency_result: Dictionary = _set_bag_currency_balance(candidate,
		int(plan.candidate.materials.get(Craft.MATERIAL_ID, 0)), released_location)
	if not currency_result.ok:
		return _craft_failure(currency_result.error_code, currency_result.reason)
	candidate.revision += 1
	var result := _commit(candidate,issued.path)
	if not result.ok:
		return _craft_failure(result.error_code,result.reason)
	for key: String in _craft_quotes.keys():
		if int(_craft_quotes[key].snapshot.revision) != revision(): _craft_quotes.erase(key)
	return {"ok":true,"code":"","reason":"","operation":quote.operation,"item_id":quote.item_id,
		"cost":quote.cost.duplicate(true),"materials":quote.materials.duplicate(true),"revision":int(_current.crafting.revision)}


func _craft_context(uid: String,path: String) -> Dictionary:
	var cell: Dictionary = _current.locations[uid]
	# A narrow authoritative projection of the selected BAG item. Full canonical
	# ownership, every jewel/gem, all nine equipment targets and wallet are checked
	# again by Rules before committing the single complete candidate.
	return {"revision":int(_current.crafting.revision),"inventory":[uid],
		"equipment_instances":{uid:_current.items[uid].payload.duplicate(true)},"equipped":{},
		"backpack_positions":{"item:"+uid:[int(cell.x),int(cell.y)]},
		"materials":{Craft.MATERIAL_ID:crafting_balance()},"save_writable":save_block_reason(path).is_empty()}


static func _craft_failure(code: String, reason: String) -> Dictionary:
	return {"ok":false,"code":code,"reason":reason}


func _set_bag_currency_balance(candidate: Dictionary, target_balance: int,
		released_location: Dictionary = {}) -> Dictionary:
	if target_balance < 0 or target_balance > ShardCatalog.INVENTORY_LIMIT:
		return {"ok": false, "error_code": "currency_limit", "reason": "校准碎片余额超出物品上限"}
	var stack_uids: Array[String] = []
	var current_balance := 0
	for uid: String in candidate.items:
		if candidate.items[uid].kind == "currency" and candidate.locations[uid].kind == "bag":
			stack_uids.append(uid)
			current_balance += int(candidate.items[uid].payload.quantity)
	stack_uids.sort()
	if target_balance < current_balance:
		var remaining: int = current_balance - target_balance
		for uid: String in stack_uids:
			var quantity: int = int(candidate.items[uid].payload.quantity)
			if quantity > remaining:
				candidate.items[uid].payload.quantity = quantity - remaining
				remaining = 0
				break
			candidate.items.erase(uid)
			candidate.locations.erase(uid)
			remaining -= quantity
		if remaining != 0:
			return {"ok": false, "error_code": "invalid_currency", "reason": "背包中的校准碎片数量不足"}
	elif target_balance > current_balance:
		var remaining: int = target_balance - current_balance
		for uid: String in stack_uids:
			var quantity: int = int(candidate.items[uid].payload.quantity)
			var added: int = mini(remaining, ShardCatalog.STACK_LIMIT - quantity)
			candidate.items[uid].payload.quantity = quantity + added
			remaining -= added
			if remaining == 0:
				break
		if remaining > 0:
			if candidate.items.size() >= Rules.MAX_ITEMS:
				return {"ok": false, "error_code": "item_limit", "reason": "无法增加新的校准碎片物品"}
			if candidate.next_item_serial >= Rules.MAX_SERIAL:
				return {"ok": false, "error_code": "serial_limit", "reason": "物品序号已达上限"}
			var uid := "item_%06d" % int(candidate.next_item_serial)
			if candidate.items.has(uid):
				return {"ok": false, "error_code": "uid_conflict", "reason": "物品身份冲突"}
			var wrapped: Dictionary = Items.calibration_shard(uid, remaining)
			if wrapped.is_empty():
				return {"ok": false, "error_code": "invalid_currency", "reason": "新校准碎片堆无效"}
			candidate.items[uid] = wrapped
			var position: Dictionary = {}
			if released_location.get("kind", "") == "bag":
				position = released_location.duplicate(true)
			if position.is_empty():
				var metadata: Dictionary = Items.metadata_for_items(candidate.items)
				position = Transfer.first_bag_space_paged(metadata, candidate.locations,
					Migration.paged_location_context(candidate, _socket_ids), uid)
			if position.is_empty():
				return {"ok": false, "error_code": "bag_full", "reason": "背包没有碎片物品的可用格子"}
			candidate.locations[uid] = position
			candidate.next_item_serial += 1
	var total: Dictionary = ShardCatalog.total_quantity(candidate.items)
	if not total.ok or int(total.quantity) > ShardCatalog.INVENTORY_LIMIT:
		return {"ok": false, "error_code": "currency_limit", "reason": "全库存校准碎片总量超出上限"}
	return {"ok": true, "error_code": "", "reason": ""}


## Paid gem trades have no persistent side ledger. Metadata does not allocate
## handles, roll random results, copy the build or read the save file.
func normal_gem_offers(path: String = "user://build_save.json") -> Array[Dictionary]:
	var result: Array[Dictionary] = GemTrade.offers()
	var guard: Dictionary = _gem_trade_guard(revision(),path)
	var balance: int = crafting_balance()
	var reasons: Dictionary = {}
	for row: Dictionary in result:
		var cost: int = row.cost
		if not reasons.has(cost):
			reasons[cost] = str(guard.reason) if not guard.ok else "背包内校准碎片不足" if balance < cost else _gem_buy_space_reason(cost)
		row.reason = reasons[cost]
		row.available = row.reason.is_empty()
	return result


func gem_recycle_info(uid: Variant, path: String = "user://build_save.json") -> Dictionary:
	var result: Dictionary = {"available":false,"reason":"请选择背包中的主动或辅助宝石","credit":GemTrade.RECYCLE_CREDIT,"name":"","uid":uid if uid is String else ""}
	var guard: Dictionary = _gem_trade_guard(revision(),path)
	if not guard.ok: result.reason=guard.reason; return result
	if not uid is String or not _current.items.has(uid): return result
	var quote: Dictionary = GemTrade.quote("recycle",uid,_current.items[uid])
	if not quote.ok: return result
	result.name = quote.name
	if _current.locations[uid].kind != "bag": result.reason="请先把宝石放入背包"; return result
	var total: Dictionary = ShardCatalog.total_quantity(_current.items)
	if not total.ok or total.quantity >= ShardCatalog.INVENTORY_LIMIT: result.reason="全库存校准碎片总量已达上限"; return result
	if _gem_credit_requires_stack() and _current.next_item_serial >= Rules.MAX_SERIAL: result.reason="物品序号已达上限"; return result
	result.available=true; result.reason=""
	return result


func _gem_trade_guard(expected_revision: Variant,path: String) -> Dictionary:
	if path != "user://build_save.json" or _path != "user://build_save.json": return _craft_failure("normal_profile_required","宝石交易只能使用已打开的正式存档")
	var guard: Dictionary = _normal_journey_guard(expected_revision,path)
	if not guard.ok:
		return _craft_failure(str(guard.error_code),"宝石交易只能使用已打开的正式存档" if guard.error_code=="normal_profile_required" else str(guard.reason))
	if not save_block_reason(path).is_empty(): return _craft_failure("save_blocked","当前存档受写保护")
	return {"ok":true,"code":"","reason":""}


func _gem_buy_space_reason(cost: int) -> String:
	if _current.next_item_serial >= Rules.MAX_SERIAL: return "物品序号已达上限"
	var used_cells: int = 0
	var stacks: Array[String] = []
	for uid: String in _current.items:
		if _current.locations[uid].kind != "bag": continue
		var metadata: Dictionary = Items.metadata_for_instance(_current.items[uid])
		if metadata.is_empty(): return "物品数据无效"
		var raw_size: Variant = metadata.size
		var size: Vector2i = Vector2i(int(raw_size[0]),int(raw_size[1])) if raw_size is Array else raw_size
		used_cells += size.x*size.y
		if _current.items[uid].kind == "currency": stacks.append(uid)
	stacks.sort()
	var freed: int = 0
	var remaining: int = cost
	for uid: String in stacks:
		if remaining <= 0: break
		var quantity: int = _current.items[uid].payload.quantity
		if quantity <= remaining: freed+=1
		remaining -= mini(remaining,quantity)
	if remaining > 0: return "背包内校准碎片不足"
	if _current.items.size()-freed >= Rules.V17_MAX_ITEMS: return "物品注册表已达上限"
	if used_cells-freed >= ItemLocationRules.CURRENT_BAG_PAGES*ItemLocationRules.CURRENT_BAG_COLUMNS*ItemLocationRules.CURRENT_BAG_ROWS: return "背包没有宝石的可用格子"
	return ""


func _gem_credit_requires_stack() -> bool:
	for uid: String in _current.items:
		if _current.items[uid].kind=="currency" and _current.locations[uid].kind=="bag" and _current.items[uid].payload.quantity < ShardCatalog.STACK_LIMIT: return false
	return true


func gem_trade_quote(operation: Variant,target: Variant,expected_revision: Variant,path: String = "user://build_save.json") -> Dictionary:
	var guard: Dictionary = _gem_trade_guard(expected_revision,path)
	if not guard.ok: return guard
	if not Rules.reason(_current,_talent_validator,_socket_ids).is_empty(): return _craft_failure("invalid_build","构筑数据无效")
	var owned: Dictionary = _current.items.get(target,{}) if typeof(operation)==TYPE_STRING and operation=="recycle" and target is String else {}
	var quote: Dictionary = GemTrade.quote(operation,target,owned)
	if not quote.ok: return quote
	if operation=="recycle" and _current.locations[target].kind!="bag": return _craft_failure("item_equipped","请先把宝石放入背包")
	var debit: int = int(quote.cost.get(GemTrade.MATERIAL_ID,0))
	var credit: int = int(quote.materials.get(GemTrade.MATERIAL_ID,0))
	var balance: int = crafting_balance()
	if balance < debit: return _craft_failure("insufficient_shards","背包内校准碎片不足")
	var candidate: Dictionary = snapshot()
	var created_uid: String = ""
	var released: Dictionary = {}
	if operation=="recycle":
		released=candidate.locations[target].duplicate(true)
		candidate.items.erase(target); candidate.locations.erase(target)
	var currency: Dictionary = _set_bag_currency_balance(candidate,balance-debit+credit,released)
	if not currency.ok: return _craft_failure(currency.error_code,currency.reason)
	if operation=="buy":
		if candidate.items.size()>=Rules.V17_MAX_ITEMS or candidate.next_item_serial>=Rules.MAX_SERIAL: return _craft_failure("item_limit","物品注册表或序号已达上限")
		created_uid="item_%06d"%int(candidate.next_item_serial)
		if not _place_journey_reward(candidate,Gems.create_instance(created_uid,quote.definition_id)): return _craft_failure("bag_full","背包没有宝石的可用格子")
	candidate.revision+=1
	var reason: String = Rules.reason(candidate,_talent_validator,_socket_ids)
	if not reason.is_empty(): return _craft_failure("invalid_candidate",reason)
	var disk: Dictionary = _gem_trade_disk_receipt(path)
	if not disk.ok: return _craft_failure("save_changed","存档已变化或无法读取，请重新读取后操作")
	_gem_trade_sequence+=1
	var handle: String = "gem:%d:%d"%[get_instance_id(),_gem_trade_sequence]
	while _gem_trade_quotes.size()>=8: _gem_trade_quotes.erase(_gem_trade_quotes.keys()[0])
	_gem_trade_quotes[handle]={"quote":quote.duplicate(true),"snapshot":snapshot(),"candidate":candidate,"path":path,"disk":disk,"uid":created_uid}
	var visible: Dictionary = quote.duplicate(true)
	visible.handle=handle
	return visible


func _gem_trade_disk_receipt(path: String) -> Dictionary:
	var receipt: Dictionary = _canonical_disk_stamp(path)
	if not receipt.ok or receipt.get("exists",false)!=_disk_expected_exists: return {"ok":false}
	if _disk_expected_exists and FileAccess.get_file_as_bytes(path)!=_disk_bytes: return {"ok":false}
	return receipt


func cancel_gem_trade_quote(handle: String) -> void:
	_gem_trade_quotes.erase(handle)


func invalidate_gem_trade_quotes() -> void:
	_gem_trade_quotes.clear()


func execute_gem_trade(handle: Variant,current_target: Variant) -> Dictionary:
	if _busy: return _craft_failure("busy","当前操作尚未结束")
	if not handle is String or not _gem_trade_quotes.has(handle): return _craft_failure("unknown_quote","宝石报价已失效")
	var issued: Dictionary = _gem_trade_quotes[handle]
	_gem_trade_quotes.erase(handle)
	if not current_target is String or current_target!=issued.quote.target: return _craft_failure("target_mismatch","所选宝石已变化")
	var guard: Dictionary = _gem_trade_guard(issued.snapshot.revision,issued.path)
	if not guard.ok: return guard
	if not CraftPlanner._same_data(_current,issued.snapshot): return _craft_failure("stale_quote","构筑已变化，请重新获取报价")
	if _gem_trade_disk_receipt(issued.path)!=issued.disk: return _craft_failure("save_changed","存档已变化，物品与碎片保持原样")
	var result: Dictionary = _commit(issued.candidate.duplicate(true),issued.path)
	if not result.ok: return _craft_failure(result.error_code,result.reason)
	_gem_trade_quotes.clear()
	return {"ok":true,"code":"","reason":"","operation":issued.quote.operation,"target":current_target,"uid":issued.uid,"definition_id":issued.quote.definition_id,
		"cost":issued.quote.cost.duplicate(true),"materials":issued.quote.materials.duplicate(true),"revision":revision()}


func get_flask_profile(uid:String)->Dictionary:
	var owned:Dictionary=item(uid)
	if owned.is_empty() or owned.kind!="flask":return {"ok":false,"reason":"未知药剂"}
	var stats:Dictionary=get_stats();var definition:Dictionary=Flasks.definition(owned.definition_id)
	var maximum:float=float(stats.max_health if definition.resource=="health" else stats.max_mana)
	return FlaskModifiers.profile(owned.definition_id,stats,maximum)


func get_leech_profile() -> Dictionary:
	return Leech.profile(get_stats())


func get_mana_guard_profile() -> Dictionary:
	return Defense.mana_guard_profile(get_stats())


func get_resistance_profile() -> Dictionary:
	return Defense.resistance_profile(get_stats(), "player")


func normal_journey() -> Dictionary:
	return _current.journey.duplicate(true)


func normal_pending_rewards() -> Dictionary:
	var value: Dictionary = _current.journey
	return {"pending_map_reward": value.pending_map_reward.duplicate(true),
		"pending_gems": int(value.normal_root_kills) / 30 - int(value.claimed_gems),
		"pending_flasks": int(value.normal_root_kills) / 60 - int(value.claimed_flasks),
		"normal_root_kills": int(value.normal_root_kills)}


func _normal_journey_guard(expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy", "当前操作尚未结束")
	if not Legacy._save_paths_match(path, "user://build_save.json") or not Legacy._save_paths_match(_path, path):
		return _failure("normal_profile_required", "正式挑战只能写入已打开的正式存档")
	if not expected_revision is int or expected_revision != revision(): return _failure("stale_revision", "正式进度或库存已变化")
	if revision() >= Rules.MAX_SERIAL: return _failure("revision_limit", "存档修订已达上限")
	return {"ok": true, "reason": ""}


func normal_start_map(profile: Dictionary, expected_revision: Variant, path: String, replacing_run_id: Variant = 0) -> Dictionary:
	var guard: Dictionary = _normal_journey_guard(expected_revision, path)
	if not guard.ok: return guard
	if not replacing_run_id is int or replacing_run_id < 0: return _failure("invalid_run", "挑战序号无效")
	if not pending_items().is_empty(): return _failure("pending_items", "请先安置已有待安置物品")
	var current: Dictionary = _current.journey
	if replacing_run_id > 0:
		var active: Dictionary = current.active_run
		if active.is_empty() or active.get("run_id") != replacing_run_id or active.get("map_id") != profile.get("id") or active.get("tier") != profile.get("journey_tier") or active.get("normal_ids") != profile.get("normal_ids") or active.get("special_ids") != profile.get("special_ids"):
			return _failure("stale_run", "重新挑战配置已变化")
		var abandoned: Dictionary = Journey.abandon(current, replacing_run_id)
		if not abandoned.ok: return _failure("invalid_run", abandoned.reason)
		current = abandoned.journey
	var planned: Dictionary = Journey.start(current, profile)
	if not planned.ok: return _failure("invalid_run", planned.reason)
	var cost: int = int(planned.cost)
	if crafting_balance() < cost: return _failure("insufficient_shards", "背包内校准碎片不足，尚未扣费或开启地图")
	var candidate: Dictionary = snapshot()
	var currency: Dictionary = _set_bag_currency_balance(candidate, crafting_balance() - cost)
	if not currency.ok: return _failure(currency.error_code, currency.reason)
	candidate.journey = planned.journey
	candidate.revision += 1
	var result: Dictionary = _commit(candidate, path)
	if result.ok: result.run_id = planned.run_id; result.cost = cost
	return result


func normal_complete_map(run_id: Variant, expected_revision: Variant, path: String) -> Dictionary:
	var guard: Dictionary = _normal_journey_guard(expected_revision, path)
	if not guard.ok: return guard
	var planned: Dictionary = Journey.complete(_current.journey, run_id)
	if not planned.ok: return _failure("stale_run", planned.reason)
	var candidate: Dictionary = snapshot()
	candidate.journey = planned.journey; candidate.revision += 1
	var result: Dictionary = _commit(candidate, path)
	if result.ok: result.reward = candidate.journey.pending_map_reward.duplicate(true)
	return result


func normal_abandon_map(run_id: Variant, expected_revision: Variant, path: String) -> Dictionary:
	var guard: Dictionary = _normal_journey_guard(expected_revision, path)
	if not guard.ok: return guard
	var planned: Dictionary = Journey.abandon(_current.journey, run_id)
	if not planned.ok: return _failure("stale_run", planned.reason)
	var candidate: Dictionary = snapshot()
	candidate.journey = planned.journey; candidate.revision += 1
	return _commit(candidate, path)


## Same existing in-memory reward batch as add_xp: the final snapshot is saved
## once by main. Kill milestones share its revision, avoiding a second refresh.
func add_normal_root_xp(amount: int) -> bool:
	if _busy or amount < 0 or not Legacy._save_paths_match(_path, "user://build_save.json") or revision() >= Rules.MAX_SERIAL: return false
	if int(_current.journey.normal_root_kills) >= 1000000000: return false
	var candidate: Dictionary = snapshot()
	candidate.journey.normal_root_kills += 1
	var leveled: bool = false
	if int(candidate.progress.level) < 1000:
		candidate.progress.xp += mini(amount, 1000000000)
		while candidate.progress.xp >= 12 + int(candidate.progress.level) * 8 and candidate.progress.level < 1000:
			candidate.progress.xp -= 12 + int(candidate.progress.level) * 8
			candidate.progress.level += 1; leveled = true
			if candidate.progress.level + 4 <= Migration.NORMAL_POINT_LIMIT: candidate.talents.normal_points += 1
		if candidate.progress.level >= 1000: candidate.progress.xp = 0
	candidate.revision += 1
	_accept_memory(candidate); _busy = true; changed.emit(); _busy = false
	return leveled


func normal_claim_rewards(expected_revision: Variant, path: String, include_map: bool = true) -> Dictionary:
	var guard: Dictionary = _normal_journey_guard(expected_revision, path)
	if not guard.ok: return guard
	if not pending_items().is_empty(): return _failure("pending_items", "请先安置已有待安置物品，再领取奖励")
	var candidate: Dictionary = snapshot()
	var claimed_shards: int = 0; var claimed_gems: int = 0; var claimed_flasks: int = 0
	if include_map and not candidate.journey.pending_map_reward.is_empty():
		var quantity: int = int(candidate.journey.pending_map_reward.shards)
		var trial: Dictionary = candidate.duplicate(true)
		var result: Dictionary = _set_bag_currency_balance(trial, crafting_balance() + quantity)
		if result.ok:
			candidate = trial; claimed_shards = quantity; candidate.journey.pending_map_reward = {}
	var gem_due: int = int(candidate.journey.normal_root_kills) / 30
	while int(candidate.journey.claimed_gems) < gem_due:
		var ordinal: int = int(candidate.journey.claimed_gems) + 1
		var uid: String = "item_%06d" % int(candidate.next_item_serial)
		if not _place_journey_reward(candidate, Gems.create_instance(uid, Journey.gem_definition(ordinal))): break
		candidate.journey.claimed_gems = ordinal; claimed_gems += 1
	var flask_due: int = int(candidate.journey.normal_root_kills) / 60
	while int(candidate.journey.claimed_flasks) < flask_due:
		var ordinal: int = int(candidate.journey.claimed_flasks) + 1
		var uid: String = "item_%06d" % int(candidate.next_item_serial)
		if not _place_journey_reward(candidate, Flasks.create_instance(uid, Journey.flask_definition(ordinal))): break
		candidate.journey.claimed_flasks = ordinal; claimed_flasks += 1
	if claimed_shards == 0 and claimed_gems == 0 and claimed_flasks == 0:
		var pending: Dictionary = normal_pending_rewards()
		return _failure("bag_full" if not pending.pending_map_reward.is_empty() or pending.pending_gems > 0 or pending.pending_flasks > 0 else "no_pending_reward", "背包空间或物品上限不足，奖励仍保留待领" if not pending.pending_map_reward.is_empty() or pending.pending_gems > 0 or pending.pending_flasks > 0 else "没有待领取奖励")
	candidate.revision += 1
	var result: Dictionary = _commit(candidate, path)
	if result.ok:
		result.claimed_shards = claimed_shards; result.claimed_gems = claimed_gems; result.claimed_flasks = claimed_flasks
	return result


func _place_journey_reward(candidate: Dictionary, wrapped: Dictionary) -> bool:
	if wrapped.is_empty() or candidate.items.size() >= Rules.V17_MAX_ITEMS or candidate.next_item_serial >= Rules.MAX_SERIAL or candidate.items.has(wrapped.uid): return false
	candidate.items[wrapped.uid] = wrapped
	var metadata: Dictionary = Items.metadata_for_items(candidate.items)
	var position: Dictionary = Transfer.first_bag_space_paged(metadata, candidate.locations, Migration.paged_location_context(candidate, _socket_ids), wrapped.uid)
	if position.is_empty(): candidate.items.erase(wrapped.uid); return false
	candidate.locations[wrapped.uid] = position; candidate.next_item_serial += 1
	return true
