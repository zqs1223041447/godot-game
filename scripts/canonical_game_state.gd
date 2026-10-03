class_name CanonicalGameState
extends "res://scripts/save/canonical_build_store.gd"
## Gameplay projection over canonical ownership. No parallel mutable inventory,
## equipment or gem-link tables exist here.
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Data = preload("res://scripts/game_data.gd")
const LOOT_PROFILE_ID := "canonical_v14"
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
	for stat: String in ["strength","dexterity","intelligence","physical_increased","chaos_increased","melee_physical_increased","attack_physical_increased","accuracy_increased","evasion_increased","armour","armour_increased","cold_resistance","lightning_resistance","life_regen","life_regen_percent"]:
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


func cache_diagnostics() -> Dictionary:
	return {"stats_builds":_stats_build_count,"skill_compiles":_cast_compile_count,"cast_entries":_cast_cache.size()}


## Combat rewards participate in main's existing bounded progress transaction.
## UI ownership commands above still require successful persistence first.
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


func award_random_gem(rng: RandomNumberGenerator) -> String:
	if rng==null or _busy or not pending_items().is_empty():return ""
	var before:int=rng.state
	var ids:Array=Gems.definitions().keys()
	ids.sort()
	var uid:=award_gem(str(ids[rng.randi_range(0,ids.size()-1)]))
	if uid.is_empty():rng.state=before
	return uid


func discard_item(uid: Variant,expected_revision: Variant,path: String) -> Dictionary:
	if _busy:return _failure("busy","当前操作尚未结束")
	if not expected_revision is int or expected_revision!=revision():return _failure("stale_revision","物品状态已变化，请重新确认")
	if not uid is String or not _current.items.has(uid) or _current.locations[uid].kind!="bag":return _failure("not_in_bag","只可丢弃背包中的物品")
	if _current.items[uid].kind=="equipment":return _failure("equipment_crafting","随机装备请使用回收，固定示例装备保留")
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
	if candidate.items.has(wrapped.uid) or candidate.items.size() >= Rules.MAX_ITEMS or candidate.revision >= Rules.MAX_SERIAL: return false
	candidate.items[wrapped.uid] = wrapped.duplicate(true)
	var metadata: Dictionary = Items.metadata_for_items(candidate.items)
	var position: Dictionary = Transfer._first_bag_space(metadata, candidate.locations, wrapped.uid)
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
	return _disk_expected_exists and JSON.stringify(_current,"\t",true,true).to_utf8_buffer() == _disk_bytes


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


func load_build(path: String = "user://build_save.json") -> bool:
	_craft_quotes.clear()
	migrated_from_legacy=false
	migration_message=""
	var old_version:int=0
	if FileAccess.file_exists(path):
		var file:=FileAccess.open(path,FileAccess.READ)
		if file!=null and file.get_length()<=MAX_SAVE_BYTES:
			var raw:Variant=JSON.parse_string(file.get_as_text())
			if raw is Dictionary and raw.get("version") is float:old_version=int(raw.version)
	var loaded:=super.load_build(path)
	if loaded and old_version>0 and old_version<Rules.VERSION:
		migrated_from_legacy=true
		migration_message="旧存档已原字节备份，装备与珠宝身份保留，技能转为独立宝石；旧天赋点已退还。待安置物品 %d 件，预算外 %d 点保留记账。"%[pending_items().size(),int(_current.migration_ledger.excess_points_recorded)]
	return loaded


func crafting_balance() -> int:
	return int(_current.crafting.materials[Craft.MATERIAL_ID])


func crafting_quote(operation: Variant, uid: Variant, path: String = "user://build_save.json") -> Dictionary:
	if int(_current.crafting.revision) >= Rules.MAX_SERIAL: return _craft_failure("revision_limit","制作修订已达上限")
	if not uid is String or not _current.items.has(uid): return _craft_failure("not_owned","当前没有此物品")
	var owned: Dictionary = _current.items[uid]
	if owned.kind != "equipment" or owned.payload.is_empty(): return _craft_failure("fixed_item","仅随机装备可进行此工艺")
	if _current.locations[uid].kind != "bag": return _craft_failure("item_equipped","请先把装备放入背包")
	if not Rules.reason(_current,_talent_validator,_socket_ids).is_empty(): return _craft_failure("invalid_build","构筑数据无效")
	var quote: Dictionary = CraftPlanner.quote(_craft_context(uid,path),operation,uid)
	if not quote.ok: return quote
	if crafting_balance() - int(quote.cost.get(Craft.MATERIAL_ID,0)) + int(quote.materials.get(Craft.MATERIAL_ID,0)) > Rules.MAX_SERIAL:
		return _craft_failure("material_limit","材料已达上限")
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
	var seed_text := JSON.stringify({"rules":Craft.RULES_VERSION,"revision":int(_current.crafting.revision),"item":quote.source_instance},"",true,true)
	var seed_value := seed_text.sha256_text().substr(0,15).hex_to_int()
	var plan: Dictionary = CraftPlanner.plan(_craft_context(quote.item_id,issued.path),quote,seed_value)
	if not plan.ok: return plan
	var candidate := snapshot()
	if quote.operation == "salvage":
		candidate.items.erase(quote.item_id)
		candidate.locations.erase(quote.item_id)
		candidate.locations = Transfer.compact_recovery(candidate.locations)
	else:
		candidate.items[quote.item_id] = Items.wrap_equipment(plan.candidate.equipment_instances[quote.item_id])
	candidate.crafting = {"materials":plan.candidate.materials.duplicate(true),"revision":plan.candidate.revision}
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
		"materials":_current.crafting.materials.duplicate(true),"save_writable":save_block_reason(path).is_empty()}


static func _craft_failure(code: String, reason: String) -> Dictionary:
	return {"ok":false,"code":code,"reason":reason}
