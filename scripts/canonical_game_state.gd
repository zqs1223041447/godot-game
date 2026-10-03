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
var _build_signature := PackedByteArray()
var _stats_cache: Dictionary = {}
var _snapshot_cache: Dictionary = {}
var _cast_cache: Dictionary = {}
var _stats_build_count := 0
var _cast_compile_count := 0


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
	for uid: String in candidate.locations:
		if candidate.locations[uid].kind != "equipment": continue
		var definition: Dictionary = Items.definition_for_instance(candidate.items[uid])
		for stat: String in definition.get("stats", {}):
			if stats.has(stat): stats[stat] += float(definition.stats[stat])
	for rate: String in ["attack_speed", "move_speed", "mana_regen"]:
		stats[rate] *= 1.0 + float(stats[rate + "_increased"])
	return stats


func _ensure_cache() -> void:
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
	var generated: Dictionary = Gear.generate_loot_profile(rng, uid, item_level, rarity, "canonical_v14") if pool == "current" else Gear.generate_for_pool(rng, uid, item_level, rarity, pool)
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
	_current = candidate
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
	if not Rules.reason(candidate, _talent_validator, _socket_ids).is_empty(): return false
	_current = candidate
	_busy = true
	changed.emit()
	_busy = false
	return leveled
