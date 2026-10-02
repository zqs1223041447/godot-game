class_name BuildState
extends RefCounted
## Persistent character configuration. Transactions validate before any mutation.
## Owned jewel records have exactly one location: inventory OR one allocated socket.

signal changed

const Data = preload("res://scripts/game_data.gd")
const Passives = preload("res://scripts/passive_data.gd")
const JewelCatalog = preload("res://scripts/jewel_data.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const SupportCatalog = preload("res://scripts/combat/support_registry.gd")
const SkillCompiler = preload("res://scripts/combat/skill_compiler.gd")
const AllocationRules = preload("res://scripts/passives/allocation_rules.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const CraftPlanner = preload("res://scripts/items/crafting_transaction_planner.gd")
const SAVE_VERSION: int = 11
## Crafting adds a wallet/sequence; equipment still uses schema9 words.
## Explicit mapping must not make an unknown future save/item version acceptable.
const EQUIPMENT_VOCABULARY_BY_SAVE_VERSION: Dictionary = {10: 9, 11: 9}
const MAX_CRAFT_MATERIALS: int = 1000000000
const MAX_CRAFT_REVISION: int = 1000000000
const MAX_CRAFT_QUOTES: int = 8
const MAX_EQUIPMENT: int = 64
const MAX_EQUIPMENT_ID: int = 999999999
const MAX_LEVEL: int = 1000
const MAX_SAVE_BYTES: int = 262144
const BASE_TALENT_POINTS: int = 5
const MAX_JEWELS: int = 64
const MAX_JEWEL_ID: int = 999999999
const BACKPACK_COLUMNS: int = 12
const BACKPACK_COLS: int = BACKPACK_COLUMNS
const BACKPACK_ROWS: int = 8
const EQUIPMENT_SLOTS: Array[String] = ["weapon", "armor", "charm"]
const BASE_STATS: Dictionary = {
	"max_health": 120.0, "max_mana": 100.0, "max_shield": 60.0,
	"damage": 18.0, "attack_speed": 1.7, "move_speed": 240.0,
	"mana_regen": 9.0, "shield_regen": 13.0,
	"global_increased": 0.0, "projectile_increased": 0.0, "elemental_increased": 0.0,
	"area_increased": 0.0, "projectile_count": 0.0,
	"spell_increased": 0.0, "fire_increased": 0.0, "cold_increased": 0.0,
	"lightning_increased": 0.0, "attack_elemental_increased": 0.0,
	"attack_speed_increased": 0.0, "move_speed_increased": 0.0, "mana_regen_increased": 0.0,
	"attack_added_physical": 0.0, "attack_added_fire": 0.0,
	"spell_added_cold": 0.0, "spell_added_lightning": 0.0,
	"fire_resistance": 0.0,
}

var inventory: Array[String] = ["ember_wand", "swift_blade", "guardian_robe", "vitality_armor", "azure_charm", "storm_charm", "prism_bow", "return_mantle", "detonation_charm"]
var equipment_instances: Dictionary = {}
var next_equipment_id: int = 1
var equipped: Dictionary = {"weapon": "ember_wand", "armor": "guardian_robe", "charm": "azure_charm"}
var skill_supports: Dictionary = {}
var skill_slots: Array[String] = ["bolt", "frost", "nova", "dash", "ward"]
var allocated_nodes: Array[String] = [Passives.START_ID]
var jewels: Dictionary = JewelCatalog.starter_jewels()
var jewel_inventory: Array[String] = ["jewel_000001", "jewel_000002", "jewel_000003"]
var socketed_jewels: Dictionary = {}
var next_jewel_id: int = 4
var backpack_positions: Dictionary = {}
var level: int = 1
var xp: int = 0
var talent_points: int = BASE_TALENT_POINTS
var crafting: Dictionary = {"materials": {"calibration_shard": 0}, "revision": 0}
var migrated_from_v1: bool = false
var migrated_from_v2: bool = false
var migrated_from_v3: bool = false
var migrated_from_v4: bool = false
var migrated_from_v5: bool = false
var migrated_from_v6: bool = false
var migrated_from_v7: bool = false
var migrated_from_v8: bool = false
var migrated_from_v9: bool = false
var migrated_from_v10: bool = false
var _migration_version: int = 0
var migration_message: String = ""
var migration_backup_path: String = ""
var _migration_source_path: String = ""
var _migration_source_bytes: PackedByteArray = PackedByteArray()
var last_load_error: String = ""
var _blocked_save_paths: Dictionary = {}
var _craft_quotes: Dictionary = {}
var _craft_quote_sequence: int = 0
var _craft_busy: bool = false
var _craft_emitting: bool = false
var _craft_persisted_text: String = ""
## Primary snapshot writes only; historical backup writes are separately guarded.
var primary_save_attempt_count: int = 0


func _init() -> void:
	backpack_positions = _packed_layout(get_backpack_items(), equipment_instances)


func get_stats() -> Dictionary:
	var result: Dictionary = BASE_STATS.duplicate()
	for slot: String in EQUIPMENT_SLOTS:
		var item_id: String = str(equipped.get(slot, ""))
		var definition: Dictionary = get_item_definition(item_id)
		if not definition.is_empty():
			_add_stats(result, definition["stats"])
	var nodes: Dictionary = Passives.get_nodes()
	_add_stats(result, Passives.get_allocated_stats(allocated_nodes))
	for socket_id: String in socketed_jewels:
		if allocated_nodes.has(socket_id) and nodes.has(socket_id) and nodes[socket_id]["type"] == "socket":
			_add_stats(result, get_jewel_stats(socketed_jewels[socket_id]))
	# Percentage character rates are a separate stage from flat points/second.
	for rate: String in ["attack_speed", "move_speed", "mana_regen"]:
		result[rate] = float(result[rate]) * (1.0 + float(result[rate + "_increased"]))
	return result


func get_combat_snapshot() -> Dictionary:
	var effects: Array[String] = []
	for slot: String in EQUIPMENT_SLOTS:
		var id: String = str(equipped.get(slot, ""))
		for effect: String in get_item_definition(id).get("effects", []):
			if not effects.has(effect):
				effects.append(effect)
	var snapshot: Dictionary = preload("res://scripts/combat/combat_data.gd").snapshot(get_stats(), effects)
	var sources: Array[Dictionary] = []
	for slot: String in EQUIPMENT_SLOTS:
		for source: Dictionary in get_item_definition(str(equipped.get(slot, ""))).get("added_sources", []):
			sources.append(source.duplicate(true))
	snapshot["added_damage_sources"] = sources
	var weapon: Dictionary = get_item_definition(str(equipped.get("weapon", "")))
	if weapon.has("weapon_profile"):
		snapshot["weapon_profile"] = weapon.weapon_profile.duplicate(true)
	return snapshot


func equip(item_id: String) -> bool:
	if get_item_definition(item_id).is_empty() or not inventory.has(item_id):
		return false
	var slot: String = get_item_definition(item_id)["slot"]
	if equipped.get(slot, "") == item_id:
		return false
	equipped[slot] = item_id
	_sync_backpack()
	changed.emit()
	return true


func unequip(slot: String) -> bool:
	if not EQUIPMENT_SLOTS.has(slot) or not equipped.has(slot):
		return false
	equipped.erase(slot)
	_sync_backpack()
	changed.emit()
	return true


func get_item_definition(item_id: String) -> Dictionary:
	return _definition_for_id(item_id, equipment_instances)


static func _definition_for_id(item_id: String, instances: Dictionary) -> Dictionary:
	if Data.ITEMS.has(item_id):
		var result: Dictionary = Data.ITEMS[item_id].duplicate(true)
		result.merge({"id": item_id, "base_id": item_id, "rarity": "unique", "item_level": 1,
			"affix_lines": [], "base_name": result.name})
		return result
	return Equipment.definition(instances.get(item_id, {}))


func award_equipment(rng: RandomNumberGenerator, item_level: int, rarity: String = "", pool: String = "legacy") -> String:
	if pool not in ["legacy", "expanded", "loot", "current", "runewood", "defense", "local_weapon"]:
		return ""
	if rng == null or equipment_instances.size() >= MAX_EQUIPMENT or next_equipment_id > MAX_EQUIPMENT_ID:
		return ""
	var id: String = "gear_%06d" % next_equipment_id
	if equipment_instances.has(id):
		return ""
	var instance: Dictionary
	match pool:
		"expanded":
			instance = Equipment.generate_expanded(rng, id, item_level, rarity)
		"loot":
			instance = Equipment.generate_loot(rng, id, item_level, rarity)
		"current":
			instance = Equipment.generate_current_loot(rng, id, item_level, rarity)
		"runewood", "defense", "local_weapon":
			instance = Equipment.generate_for_pool(rng, id, item_level, rarity, pool)
		_:
			instance = Equipment.generate(rng, id, item_level, rarity)
	if not Equipment.validate_instance(instance):
		return ""
	var candidate_instances: Dictionary = equipment_instances.duplicate(true)
	candidate_instances[id] = instance
	var candidate_inventory: Array[String] = inventory.duplicate()
	candidate_inventory.append(id)
	if not _owned_items_fit(candidate_inventory, jewels.keys(), candidate_instances):
		return ""
	equipment_instances[id] = instance
	inventory.append(id)
	next_equipment_id += 1
	_sync_backpack()
	changed.emit()
	return id


func discard_equipment(item_id: String) -> bool:
	if not equipment_instances.has(item_id) or not inventory.has(item_id) or equipped.values().has(item_id):
		return false
	inventory.erase(item_id)
	equipment_instances.erase(item_id)
	_sync_backpack()
	changed.emit()
	return true


func crafting_balance() -> int:
	var materials: Variant = crafting.get("materials", {})
	return int(materials.get(Craft.MATERIAL_ID, 0)) if materials is Dictionary else 0


## The UI receives an opaque, process-local handle; no seed or rolled candidate.
## Full-build and disk bindings are held here, never accepted from a caller.
func crafting_quote(operation: Variant, item_id: Variant, path: String = "user://build_save.json") -> Dictionary:
	var snapshot: Dictionary = _snapshot()
	if _validate_snapshot(snapshot).is_empty():
		return _craft_failure("invalid_build", "构筑数据无效，无法制作。")
	if int(crafting.revision) >= MAX_CRAFT_REVISION:
		return _craft_failure("revision_limit", "制作次数已达上限。")
	var quote: Dictionary = CraftPlanner.quote(_craft_context(snapshot, path), operation, item_id)
	if not quote.ok:
		return quote
	var resulting_balance: int = crafting_balance() - int(quote.cost.get(Craft.MATERIAL_ID, 0)) + int(quote.materials.get(Craft.MATERIAL_ID, 0))
	if resulting_balance > MAX_CRAFT_MATERIALS:
		return _craft_failure("material_limit", "校准碎片已达上限。")
	var disk: Dictionary = _craft_disk_stamp(path)
	if not disk.ok:
		_reject_load(path, "存档无法安全读取")
		return _craft_failure("save_unreadable", "存档无法读取，暂时不能制作。")
	_craft_quote_sequence += 1
	var handle: String = "%d:%d" % [get_instance_id(), _craft_quote_sequence]
	while _craft_quotes.size() >= MAX_CRAFT_QUOTES:
		_craft_quotes.erase(_craft_quotes.keys()[0])
	_craft_quotes[handle] = {"quote": quote.duplicate(true), "snapshot": snapshot.duplicate(true),
		"path": path, "disk": disk.duplicate(true)}
	var visible: Dictionary = quote.duplicate(true)
	visible["handle"] = handle
	return visible


func cancel_crafting_quote(handle: String) -> void:
	_craft_quotes.erase(handle)


func execute_crafting(handle: Variant, source_instance: Variant) -> Dictionary:
	if _craft_busy:
		return _craft_failure("busy", "制作正在保存，请等待完成后再试。")
	if not handle is String or not _craft_quotes.has(handle):
		return _craft_failure("unknown_quote", "报价已失效，请重新选择装备。")
	var issued: Dictionary = _craft_quotes[handle]
	var quote: Dictionary = issued.quote
	if not CraftPlanner._same_data(source_instance, quote.source_instance):
		return _craft_failure("source_mismatch", "物品已变化，请重新选择装备。")
	var current: Dictionary = _snapshot()
	if not CraftPlanner._same_data(current, issued.snapshot):
		_craft_quotes.erase(handle)
		return _craft_failure("stale_quote", "构筑已变化，请重新获取报价。")
	if _validate_snapshot(current).is_empty():
		return _craft_failure("invalid_build", "构筑数据无效，无法制作。")
	if _craft_disk_stamp(issued.path) != issued.disk:
		_reject_load(issued.path, "存档已变化")
		return _craft_failure("save_changed", "存档已变化，未消耗装备或碎片。")
	var context: Dictionary = _craft_context(current, issued.path)
	# Stable across cancellation, failed writes and reloads of the same build.
	# No global/combat/loot RNG call and no caller-selected seed.
	var seed_text: String = JSON.stringify({"rules": Craft.RULES_VERSION,
		"revision": int(crafting.revision), "item": quote.source_instance}, "", true, true)
	var seed_value: int = seed_text.sha256_text().substr(0, 15).hex_to_int()
	var plan: Dictionary = CraftPlanner.plan(context, quote, seed_value)
	if not plan.ok:
		return plan
	var candidate: Dictionary = current.duplicate(true)
	for field: String in ["inventory", "equipment_instances", "equipped", "backpack_positions"]:
		candidate[field] = plan.candidate[field].duplicate(true)
	candidate.crafting = {"materials": plan.candidate.materials.duplicate(true), "revision": plan.candidate.revision}
	var validated: Dictionary = _validate_snapshot(candidate)
	if validated.is_empty():
		return _craft_failure("invalid_candidate", "制作结果未通过完整构筑校验。")
	_craft_busy = true
	var error: Error = _persist_snapshot(validated, issued.path)
	if error != OK:
		_craft_busy = false
		var failure: Dictionary = _craft_failure("save_failed", "保存失败，装备、碎片与制作次数均未变化。")
		failure["file_error"] = error
		return failure
	# The candidate is durable before any in-memory inventory/wallet mutation.
	inventory.assign(validated.inventory)
	equipment_instances = validated.equipment_instances.duplicate(true)
	equipped = validated.equipped.duplicate(true)
	backpack_positions.clear()
	for key: String in validated.backpack_positions:
		var position: Array = validated.backpack_positions[key]
		backpack_positions[key] = Vector2i(int(position[0]), int(position[1]))
	crafting = validated.crafting.duplicate(true)
	_craft_quotes.clear()
	_craft_persisted_text = JSON.stringify(validated, "\t", true, true)
	_craft_emitting = true
	changed.emit()
	_craft_emitting = false
	_craft_persisted_text = ""
	_craft_busy = false
	return {"ok": true, "code": "", "reason": "", "operation": quote.operation,
		"item_id": quote.item_id, "cost": quote.cost.duplicate(true),
		"materials": quote.materials.duplicate(true), "revision": int(crafting.revision)}


## A reentrant callback changing anything fails this exact-byte receipt check.
func crafting_change_already_saved() -> bool:
	return _craft_emitting and JSON.stringify(_snapshot(), "\t", true, true) == _craft_persisted_text


func _craft_context(snapshot: Dictionary, path: String) -> Dictionary:
	return {"revision": int(snapshot.crafting.revision), "materials": snapshot.crafting.materials.duplicate(true),
		"inventory": snapshot.inventory.duplicate(true), "equipment_instances": snapshot.equipment_instances.duplicate(true),
		"equipped": snapshot.equipped.duplicate(true), "backpack_positions": snapshot.backpack_positions.duplicate(true),
		"save_writable": save_block_reason(path).is_empty()}


func _craft_disk_stamp(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "exists": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return {"ok": false}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	var read_error: Error = file.get_error()
	file.seek(0)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if read_error != OK or parse_error != OK or _validate_snapshot(parser.data).is_empty():
		return {"ok": false}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return {"ok": true, "exists": true, "sha256": digest.finish().hex_encode()}


static func _craft_failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}


func allocation_analysis() -> Dictionary:
	# No cache: direct state edits in diagnostics/tests must never leave stale rules.
	return AllocationRules.analyze(allocated_nodes, socketed_jewels, jewels)


func allocation_sources(node_id: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(allocation_analysis().granted_by.get(node_id, []))
	return result


func jewel_radius_preview(socket_id: String, jewel_id: String) -> Dictionary:
	var result: Dictionary = AllocationRules.coverage_for_socket(socket_id, jewels.get(jewel_id, {}))
	if not result.is_empty():
		result["active"] = allocation_analysis().connected.has(socket_id)
	return result


func allocation_reason(node_id: String) -> String:
	if not Passives.get_nodes().has(node_id):
		return "未知天赋节点"
	if allocated_nodes.has(node_id):
		return "此节点已激活"
	if talent_points <= 0:
		return "天赋点不足；升级可获得天赋点"
	var candidate: Array[String] = allocated_nodes.duplicate()
	candidate.append(node_id)
	var analysis: Dictionary = AllocationRules.analyze(candidate, socketed_jewels, jewels)
	if analysis.legal:
		return ""
	if Passives.get_nodes()[node_id]["type"] == "socket" and not analysis.connected.has(node_id):
		return "珠宝孔必须沿已激活连线连通起点；寻枝覆盖不能激活远程珠宝孔"
	return "需要连通起点的相邻节点，或激活寻枝晶玉的范围覆盖。" + str(analysis.reason)


func can_allocate(node_id: String) -> bool:
	return allocation_reason(node_id).is_empty()


func allocate_passive(node_id: String) -> bool:
	if not can_allocate(node_id):
		return false
	allocated_nodes.append(node_id)
	talent_points -= 1
	_sync_backpack()
	changed.emit()
	return true


func refund_reason(node_id: String) -> String:
	if node_id == Passives.START_ID:
		return "起点永久免费，不能返还"
	if not allocated_nodes.has(node_id):
		return "此节点尚未激活"
	var remaining: Array = allocated_nodes.duplicate()
	remaining.erase(node_id)
	var candidate_sockets: Dictionary = socketed_jewels.duplicate()
	candidate_sockets.erase(node_id)
	return str(AllocationRules.analyze(remaining, candidate_sockets, jewels).reason)


func can_refund(node_id: String) -> bool:
	return refund_reason(node_id).is_empty()


func refund_passive(node_id: String) -> bool:
	if not can_refund(node_id):
		return false
	# Total-owned capacity reserves room for every equipped jewel to return.
	if socketed_jewels.has(node_id):
		jewel_inventory.append(socketed_jewels[node_id])
		socketed_jewels.erase(node_id)
	allocated_nodes.erase(node_id)
	talent_points += 1
	_sync_backpack()
	changed.emit()
	return true


func refund_talents() -> void:
	if allocated_nodes.size() <= 1:
		return
	if not AllocationRules.analyze([Passives.START_ID], {}, jewels).legal:
		return
	for socket_id: String in socketed_jewels:
		jewel_inventory.append(socketed_jewels[socket_id])
	socketed_jewels.clear()
	talent_points += allocated_nodes.size() - 1
	allocated_nodes.assign([Passives.START_ID])
	_sync_backpack()
	changed.emit()


func jewel_location(jewel_id: String) -> String:
	if not jewels.has(jewel_id):
		return ""
	if jewel_inventory.has(jewel_id):
		return "inventory"
	for socket_id: String in socketed_jewels:
		if socketed_jewels[socket_id] == jewel_id:
			return socket_id
	return ""


func get_jewel_at(socket_id: String) -> Dictionary:
	return jewels.get(socketed_jewels.get(socket_id, ""), {}).duplicate(true)


func get_jewel_stats(jewel_id: String) -> Dictionary:
	return JewelCatalog.get_stats(jewels.get(jewel_id, {}))


func _socket_input_reason(socket_id: String, jewel_id: String) -> String:
	var nodes: Dictionary = Passives.get_nodes()
	if not nodes.has(socket_id) or nodes[socket_id]["type"] != "socket":
		return "请选择珠宝孔"
	if not allocated_nodes.has(socket_id):
		return "需要先激活珠宝孔"
	if not jewels.has(jewel_id) or jewel_location(jewel_id).is_empty():
		return "未持有此珠宝"
	if socketed_jewels.get(socket_id, "") == jewel_id:
		return "此珠宝已在该孔中"
	return ""


func _socket_candidate(socket_id: String, jewel_id: String) -> Dictionary:
	var candidate: Dictionary = socketed_jewels.duplicate()
	var source: String = jewel_location(jewel_id)
	var previous: String = str(candidate.get(socket_id, ""))
	if source != "inventory":
		if previous.is_empty():
			candidate.erase(source)
		else:
			candidate[source] = previous
	candidate[socket_id] = jewel_id
	return candidate


func socket_preview_analysis(socket_id: String, jewel_id: String) -> Dictionary:
	var reason: String = _socket_input_reason(socket_id, jewel_id)
	if not reason.is_empty():
		var current: Dictionary = allocation_analysis()
		current.legal = false
		current.reason = reason
		return current
	return AllocationRules.analyze(allocated_nodes, _socket_candidate(socket_id, jewel_id), jewels)


func socket_reason(socket_id: String, jewel_id: String) -> String:
	return str(socket_preview_analysis(socket_id, jewel_id).reason)


func socket_jewel(socket_id: String, jewel_id: String) -> bool:
	if not socket_reason(socket_id, jewel_id).is_empty():
		return false
	var source: String = jewel_location(jewel_id)
	var previous: String = str(socketed_jewels.get(socket_id, ""))
	var candidate_sockets: Dictionary = _socket_candidate(socket_id, jewel_id)
	# Commit the same final layout used by the rules, never an intermediate removal.
	if source == "inventory":
		var index: int = jewel_inventory.find(jewel_id)
		if previous.is_empty():
			jewel_inventory.remove_at(index)
		else:
			jewel_inventory[index] = previous
	socketed_jewels = candidate_sockets
	_sync_backpack()
	changed.emit()
	return true


func remove_jewel_reason(socket_id: String) -> String:
	if not socketed_jewels.has(socket_id):
		return "此珠宝孔为空"
	var candidate: Dictionary = socketed_jewels.duplicate()
	candidate.erase(socket_id)
	return str(AllocationRules.analyze(allocated_nodes, candidate, jewels).reason)


func remove_jewel(socket_id: String) -> bool:
	if not remove_jewel_reason(socket_id).is_empty():
		return false
	jewel_inventory.append(socketed_jewels[socket_id])
	socketed_jewels.erase(socket_id)
	_sync_backpack()
	changed.emit()
	return true


func discard_jewel(jewel_id: String) -> bool:
	if not jewels.has(jewel_id) or not jewel_inventory.has(jewel_id):
		return false
	jewel_inventory.erase(jewel_id)
	jewels.erase(jewel_id)
	_sync_backpack()
	changed.emit()
	return true


func award_jewel(rng: RandomNumberGenerator) -> String:
	if rng == null or jewels.size() >= MAX_JEWELS or next_jewel_id > MAX_JEWEL_ID:
		return ""
	var id: String = "jewel_%06d" % next_jewel_id
	if jewels.has(id):
		return ""
	var jewel: Dictionary = JewelCatalog.generate(rng, id)
	if not JewelCatalog.validate_instance(jewel):
		return ""
	var candidate_jewels: Array = jewels.keys()
	candidate_jewels.append(id)
	if not _owned_items_fit(inventory, candidate_jewels, equipment_instances):
		return ""
	jewels[id] = jewel
	jewel_inventory.append(id)
	next_jewel_id += 1
	_sync_backpack()
	changed.emit()
	return id


func award_special_jewel() -> String:
	# Fixed boss reward: consumes no random draws and grants no starter/upgrade item.
	if jewels.size() >= MAX_JEWELS or next_jewel_id < 1 or next_jewel_id > MAX_JEWEL_ID:
		return ""
	var id: String = "jewel_%06d" % next_jewel_id
	if jewels.has(id):
		return ""
	var jewel: Dictionary = JewelCatalog.generate_special(id)
	if not JewelCatalog.validate_instance(jewel):
		return ""
	var candidate_jewels: Array = jewels.keys()
	candidate_jewels.append(id)
	if not _owned_items_fit(inventory, candidate_jewels, equipment_instances):
		return ""
	jewels[id] = jewel
	jewel_inventory.append(id)
	next_jewel_id += 1
	_sync_backpack()
	changed.emit()
	return id


func get_skill_supports(skill_id: String) -> Array[String]:
	var result: Array[String] = []
	var raw: Variant = skill_supports.get(skill_id, [])
	if not raw is Array:
		return result
	for value: Variant in raw:
		if not value is String:
			return []
		result.append(value)
	return result


func get_skill_cast(skill_id: String) -> Dictionary:
	var raw: Variant = skill_supports.get(skill_id, [])
	if not raw is Array:
		return {"ok": false, "error": "辅助配置必须为列表"}
	return SkillCompiler.compile_skill(skill_id, get_combat_snapshot(), raw)


func support_reason(skill_id: String, support_id: String) -> String:
	var current: Array[String] = get_skill_supports(skill_id)
	if current.has(support_id):
		return "此辅助已链接到该技能"
	current.append(support_id)
	return SupportCatalog.compatibility_reason(skill_id, current)


func set_skill_supports(skill_id: String, support_ids: Array) -> bool:
	if not SupportCatalog.compatibility_reason(skill_id, support_ids).is_empty():
		return false
	var canonical: Array[String] = []
	canonical.assign(support_ids)
	canonical.sort()
	if canonical == get_skill_supports(skill_id):
		return false
	if canonical.is_empty():
		skill_supports.erase(skill_id)
	else:
		skill_supports[skill_id] = canonical
	changed.emit()
	return true


func add_skill_support(skill_id: String, support_id: String) -> bool:
	if not support_reason(skill_id, support_id).is_empty():
		return false
	var selected: Array[String] = get_skill_supports(skill_id)
	selected.append(support_id)
	return set_skill_supports(skill_id, selected)


func remove_skill_support(skill_id: String, support_id: String) -> bool:
	var selected: Array[String] = get_skill_supports(skill_id)
	if not selected.has(support_id):
		return false
	selected.erase(support_id)
	return set_skill_supports(skill_id, selected)


func slot_skill(index: int, skill_id: String) -> bool:
	if index < 0 or index >= skill_slots.size() or not Data.SKILLS.has(skill_id):
		return false
	if skill_slots[index] == skill_id:
		return false
	var previous_index: int = skill_slots.find(skill_id)
	if previous_index >= 0:
		skill_slots[previous_index] = skill_slots[index]
	skill_slots[index] = skill_id
	_sync_backpack()
	changed.emit()
	return true


func add_xp(amount: int) -> bool:
	if amount <= 0 or level >= MAX_LEVEL:
		return false
	xp += mini(amount, 1000000000)
	var leveled: bool = false
	while xp >= xp_required() and level < MAX_LEVEL:
		xp -= xp_required()
		level += 1
		talent_points += 1
		leveled = true
	if level >= MAX_LEVEL:
		xp = 0
	_sync_backpack()
	changed.emit()
	return leveled


func xp_required() -> int:
	return 12 + level * 8


func save_build(path: String = "user://build_save.json") -> Error:
	return _persist_snapshot(_snapshot(), path)


func _persist_snapshot(snapshot: Dictionary, path: String) -> Error:
	if not save_block_reason(path).is_empty():
		return ERR_INVALID_DATA
	if _validate_snapshot(snapshot).is_empty():
		return ERR_INVALID_DATA
	var serialized: String = JSON.stringify(snapshot, "\t", true, true)
	if serialized.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return ERR_INVALID_DATA
	# Keep the original legacy save before the first migration overwrite.
	# A backup failure aborts autosave without touching the old file.
	if _save_paths_match(path, _migration_source_path) and not _migration_source_bytes.is_empty():
		var backup_error: Error = _backup_legacy_save(_migration_source_path)
		if backup_error != OK:
			return backup_error
	primary_save_attempt_count += 1
	var write_error: Error = _atomic_write(path, serialized)
	if write_error == OK and _save_paths_match(path, _migration_source_path):
		_migration_source_bytes = PackedByteArray()
	return write_error


func load_build(path: String = "user://build_save.json") -> bool:
	_craft_quotes.clear()
	if _craft_busy:
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		if FileAccess.file_exists(path):
			return _reject_load(path, "存档无法读取")
		return false
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return _reject_load(path, "存档大小超出安全上限")
	var source_bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.seek(0)
	var text: String = file.get_as_text() # Keep legacy UTF-8 BOM handling; backup uses raw bytes.
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return _reject_load(path, "存档格式损坏")
	var candidate: Dictionary = _validate_snapshot(parser.data)
	if candidate.is_empty():
		return _reject_load(path, "存档数据无效或属于不兼容版本")
	for blocked_path: String in _blocked_save_paths.keys():
		if _save_paths_match(path, blocked_path):
			_blocked_save_paths.erase(blocked_path)
	last_load_error = ""
	_craft_quotes.clear()
	# Commit only after every field, graph connection and jewel location validates.
	inventory.assign(candidate["inventory"])
	equipment_instances = candidate["equipment_instances"].duplicate(true)
	next_equipment_id = int(candidate["next_equipment_id"])
	equipped = candidate["equipped"].duplicate()
	skill_slots.assign(candidate["skill_slots"])
	skill_supports = candidate["skill_supports"].duplicate(true)
	allocated_nodes.assign(candidate["allocated_nodes"])
	jewels = candidate["jewels"].duplicate(true)
	jewel_inventory.assign(candidate["jewel_inventory"])
	socketed_jewels = candidate["socketed_jewels"].duplicate()
	next_jewel_id = int(candidate["next_jewel_id"])
	backpack_positions.clear()
	for key: String in candidate["backpack_positions"]:
		var position: Array = candidate["backpack_positions"][key]
		backpack_positions[key] = Vector2i(int(position[0]), int(position[1]))
	level = int(candidate["level"])
	xp = int(candidate["xp"])
	talent_points = int(candidate["talent_points"])
	crafting = candidate["crafting"].duplicate(true)
	migrated_from_v1 = int(parser.data["version"]) == 1
	migrated_from_v2 = int(parser.data["version"]) == 2
	migrated_from_v3 = int(parser.data["version"]) == 3
	migrated_from_v4 = int(parser.data["version"]) == 4
	migrated_from_v5 = int(parser.data["version"]) == 5
	migrated_from_v6 = int(parser.data["version"]) == 6
	migrated_from_v7 = int(parser.data["version"]) == 7
	migrated_from_v8 = int(parser.data["version"]) == 8
	migrated_from_v9 = int(parser.data["version"]) == 9
	migrated_from_v10 = int(parser.data["version"]) == 10
	_migration_version = int(parser.data["version"])
	if migrated_from_v1 or migrated_from_v2:
		for id: String in Data.COMBAT_STARTER_ITEMS:
			if not inventory.has(id):
				inventory.append(id)
	migration_message = "旧版天赋已迁移：所有已用点数已返还，装备与技能保留。现在可分配星图天赋。" if migrated_from_v1 else ""
	if migrated_from_v2:
		migration_message = "构筑已升级：原装备、天赋和珠宝保留，已补发三件机制装备。K 可查看战斗机制。"
	if migrated_from_v3:
		migration_message = "构筑已升级：原装备、天赋和珠宝保留。现在可获得有独立词缀的随机装备；按 I 查看。"
	if migrated_from_v4:
		migration_message = "构筑已升级：装备词缀与原有技能保留。按 K 为龙卷、飞弹或冰霜链接辅助，组合效果与耗魔可直接预览。"
	if migrated_from_v5:
		migration_message = "构筑已升级：旧装备与掷值保持不变。新增符木法器进入正常掉落，可获得攻击或法术分类点伤；K 和 F6 可查看构成。"
	if migrated_from_v6:
		migration_message = "构筑已升级：原装备、辅助与天赋保持不变。常规首领可掉落寻枝晶玉，在半径内开放远程天赋分配。"
	if migrated_from_v7:
		migration_message = "构筑已升级：原装备掷值、辅助、天赋与珠宝保持不变。新增灰烬皮甲进入正常掉落，可获得火焰抗性；有效火抗上限为 75%。"
	if migrated_from_v8:
		migration_message = "构筑已升级：原装备掷值、辅助、天赋与珠宝保持不变。新增白蜡长弓进入正常掉落；本武器词缀仅作用于武器攻击命中。"
	if migrated_from_v9:
		migration_message = "构筑已升级：装备、天赋、珠宝与已有辅助保持不变。新增贯穿辅助可用于飞弹和冰霜；按 K 配置。"
	if migrated_from_v10:
		migration_message = "构筑已升级：原装备与构筑保留。背包中的随机魔法、稀有装备可回收或校准；碎片从零开始。"
	migration_backup_path = ""
	_migration_source_path = path if _migration_version < SAVE_VERSION else ""
	_migration_source_bytes = source_bytes if _migration_version < SAVE_VERSION else PackedByteArray()
	_sync_backpack()
	changed.emit()
	return true


func save_block_reason(path: String = "user://build_save.json") -> String:
	for blocked_path: String in _blocked_save_paths:
		if _save_paths_match(path, blocked_path):
			return str(_blocked_save_paths[blocked_path])
	return ""


static func _save_paths_match(path_a: String, path_b: String) -> bool:
	if path_a.is_empty() or path_b.is_empty():
		return false
	var absolute_a: String = ProjectSettings.globalize_path(path_a).replace("\\", "/")
	var absolute_b: String = ProjectSettings.globalize_path(path_b).replace("\\", "/")
	if absolute_a == absolute_b:
		return true
	var filesystem: DirAccess = DirAccess.open(".")
	if filesystem == null:
		return false
	if absolute_a.is_relative_path():
		absolute_a = filesystem.get_current_dir().path_join(absolute_a)
	if absolute_b.is_relative_path():
		absolute_b = filesystem.get_current_dir().path_join(absolute_b)
	if filesystem.is_equivalent(absolute_a, absolute_b):
		return true
	# Keep protection when an external lock/deletion prevents querying the file.
	# Compare directory identity before applying that directory's filename rules.
	var parent_a: String = absolute_a.get_base_dir()
	var parent_b: String = absolute_b.get_base_dir()
	if not filesystem.is_equivalent(parent_a, parent_b):
		return false
	return absolute_a.get_file() == absolute_b.get_file() or (
		not filesystem.is_case_sensitive(parent_a)
		and absolute_a.get_file().nocasecmp_to(absolute_b.get_file()) == 0)


func _reject_load(path: String, reason: String) -> bool:
	last_load_error = reason + "；已保护原文件并暂停自动保存。请先备份，再使用兼容版本或恢复有效备份。"
	_blocked_save_paths[ProjectSettings.globalize_path(path)] = last_load_error
	return false


func _snapshot() -> Dictionary:
	var serialized_positions: Dictionary = {}
	for key: Variant in backpack_positions:
		var position: Variant = backpack_positions[key]
		if position is Vector2i:
			serialized_positions[key] = [position.x, position.y]
		else:
			# Preserve an invalid value for schema rejection instead of coercing it.
			serialized_positions[key] = null
	return {
		"version": SAVE_VERSION, "inventory": inventory.duplicate(), "equipped": equipped.duplicate(),
		"equipment_instances": equipment_instances.duplicate(true), "next_equipment_id": next_equipment_id,
		"skill_slots": skill_slots.duplicate(), "skill_supports": skill_supports.duplicate(true), "level": level, "xp": xp, "talent_points": talent_points,
		"allocated_nodes": allocated_nodes.duplicate(), "jewels": jewels.duplicate(true),
		"jewel_inventory": jewel_inventory.duplicate(), "socketed_jewels": socketed_jewels.duplicate(),
		"next_jewel_id": next_jewel_id, "backpack_positions": serialized_positions,
		"crafting": crafting.duplicate(true),
	}


func _validate_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var data: Dictionary = value
	if not _is_bounded_int(data.get("version"), 1, SAVE_VERSION) or not _validate_common(data):
		return {}
	if int(data["version"]) == 1:
		return _migrate_v1(data)
	var required: Array[String] = ["version", "inventory", "equipped", "skill_slots", "level", "xp", "talent_points", "allocated_nodes", "jewels", "jewel_inventory", "socketed_jewels", "next_jewel_id", "backpack_positions"]
	if int(data["version"]) >= 4:
		required.append_array(["equipment_instances", "next_equipment_id"])
	if int(data["version"]) >= 5:
		required.append("skill_supports")
	if int(data["version"]) >= 11:
		required.append("crafting")
	if data.size() != required.size() or not data.has_all(required):
		return {}
	if int(data["version"]) >= 11:
		var craft_state: Variant = data.crafting
		if not craft_state is Dictionary or craft_state.size() != 2 or not craft_state.has_all(["materials", "revision"]):
			return {}
		if not _is_bounded_int(craft_state.revision, 0, MAX_CRAFT_REVISION):
			return {}
		if not craft_state.materials is Dictionary or craft_state.materials.size() != 1 or not craft_state.materials.has(Craft.MATERIAL_ID):
			return {}
		if not _is_bounded_int(craft_state.materials[Craft.MATERIAL_ID], 0, MAX_CRAFT_MATERIALS):
			return {}
	if int(data["version"]) >= 5:
		if not data["skill_supports"] is Dictionary or data["skill_supports"].size() > Data.SKILLS.size():
			return {}
		for skill_id: Variant in data["skill_supports"]:
			if not skill_id is String or not SupportCatalog.saved_links_reason(skill_id, data["skill_supports"][skill_id], int(data["version"])).is_empty():
				return {}
	if not data["allocated_nodes"] is Array:
		return {}
	var loaded_nodes: Array = data["allocated_nodes"]
	var nodes: Dictionary = Passives.get_nodes()
	if loaded_nodes.is_empty() or loaded_nodes.size() > nodes.size():
		return {}
	var seen: Dictionary = {}
	for id: Variant in loaded_nodes:
		if not id is String or not nodes.has(id) or seen.has(id):
			return {}
		seen[id] = true
	if not seen.has(Passives.START_ID):
		return {}
	if loaded_nodes.size() - 1 + int(data["talent_points"]) != BASE_TALENT_POINTS + int(data["level"]) - 1:
		return {}
	if not data["jewels"] is Dictionary or not data["jewel_inventory"] is Array or not data["socketed_jewels"] is Dictionary:
		return {}
	var loaded_jewels: Dictionary = data["jewels"]
	var loaded_inventory: Array = data["jewel_inventory"]
	var loaded_sockets: Dictionary = data["socketed_jewels"]
	if loaded_jewels.size() > MAX_JEWELS or loaded_inventory.size() > MAX_JEWELS or loaded_sockets.size() > 12:
		return {}
	if not _is_bounded_int(data["next_jewel_id"], 1, MAX_JEWEL_ID + 1):
		return {}
	for id: Variant in loaded_jewels:
		if not id is String or not JewelCatalog.validate_instance(loaded_jewels[id], int(data["version"]) >= 7):
			return {}
		if loaded_jewels[id]["id"] != id or JewelCatalog.serial_from_id(id) >= int(data["next_jewel_id"]):
			return {}
	seen.clear()
	for id: Variant in loaded_inventory:
		if not id is String or not loaded_jewels.has(id) or seen.has(id):
			return {}
		seen[id] = true
	for socket_id: Variant in loaded_sockets:
		if not socket_id is String or not nodes.has(socket_id) or nodes[socket_id]["type"] != "socket" or not loaded_nodes.has(socket_id):
			return {}
		var id: Variant = loaded_sockets[socket_id]
		if not id is String or not loaded_jewels.has(id) or seen.has(id):
			return {}
		seen[id] = true
	if seen.size() != loaded_jewels.size():
		return {}
	# Ownership and versioned instance vocabulary validate before final graph rules.
	if not AllocationRules.analyze(loaded_nodes, loaded_sockets, loaded_jewels).legal:
		return {}
	if not _validate_backpack(data):
		return {}
	var result: Dictionary = data.duplicate(true)
	if int(data.version) < 11:
		result.crafting = {"materials": {Craft.MATERIAL_ID: 0}, "revision": 0}
	else:
		result.crafting.revision = int(result.crafting.revision)
		result.crafting.materials[Craft.MATERIAL_ID] = int(result.crafting.materials[Craft.MATERIAL_ID])
	if int(data["version"]) < 4:
		result["version"] = SAVE_VERSION
		result["equipment_instances"] = {}
		result["next_equipment_id"] = 1
	if int(data["version"]) < 5:
		result["version"] = SAVE_VERSION
		result["skill_supports"] = {}
	if int(data["version"]) < SAVE_VERSION:
		result["version"] = SAVE_VERSION
	for skill_id: String in result["skill_supports"]:
		var canonical: Array[String] = []
		canonical.assign(result["skill_supports"][skill_id])
		canonical.sort()
		result["skill_supports"][skill_id] = canonical
	# JSON numbers decode as floats. Normalize ONLY after exact integer/range
	# validation so persisted rolls have the same canonical types as fresh loot.
	for instance: Dictionary in result["equipment_instances"].values():
		instance["item_level"] = int(instance["item_level"])
		for affix: Dictionary in instance["affixes"]:
			affix["tier"] = int(affix["tier"])
			affix["value"] = int(affix["value"])
	return result


func _validate_common(data: Dictionary) -> bool:
	if not _is_bounded_int(data.get("level"), 1, MAX_LEVEL):
		return false
	var loaded_level: int = int(data["level"])
	if not _is_bounded_int(data.get("xp"), 0, 11 + loaded_level * 8):
		return false
	if loaded_level == MAX_LEVEL and int(data["xp"]) != 0:
		return false
	if not _is_bounded_int(data.get("talent_points"), 0, BASE_TALENT_POINTS + loaded_level - 1):
		return false
	if not data.get("inventory") is Array or not data.get("skill_slots") is Array or not data.get("equipped") is Dictionary:
		return false
	var loaded_inventory: Array = data["inventory"]
	var loaded_skills: Array = data["skill_slots"]
	var instances: Dictionary = {}
	if int(data.get("version", 0)) >= 4:
		if not data.get("equipment_instances") is Dictionary or not _is_bounded_int(data.get("next_equipment_id"), 1, MAX_EQUIPMENT_ID + 1):
			return false
		instances = data["equipment_instances"]
		if instances.size() > MAX_EQUIPMENT:
			return false
		for id: Variant in instances:
			var item_vocabulary: int = int(EQUIPMENT_VOCABULARY_BY_SAVE_VERSION.get(int(data.get("version", 0)), int(data.get("version", 0))))
			if not id is String or not Equipment.validate_instance_for_version(instances[id], item_vocabulary):
				return false
			if instances[id]["id"] != id or Equipment.serial_from_id(id) >= int(data["next_equipment_id"]) or not loaded_inventory.has(id):
				return false
	if loaded_inventory.size() > Data.ITEMS.size() + instances.size() or loaded_skills.size() != 5:
		return false
	var seen: Dictionary = {}
	for item_id: Variant in loaded_inventory:
		if not item_id is String or (not Data.ITEMS.has(item_id) and not instances.has(item_id)) or seen.has(item_id):
			return false
		seen[item_id] = true
	seen.clear()
	for skill_id: Variant in loaded_skills:
		if not skill_id is String or not Data.SKILLS.has(skill_id) or seen.has(skill_id):
			return false
		seen[skill_id] = true
	var loaded_equipped: Dictionary = data["equipped"]
	for slot: Variant in loaded_equipped:
		if not slot is String or not EQUIPMENT_SLOTS.has(slot):
			return false
		var item_id: Variant = loaded_equipped[slot]
		if not item_id is String or not loaded_inventory.has(item_id):
			return false
		if _definition_for_id(item_id, instances)["slot"] != slot:
			return false
	return true


func _migrate_v1(data: Dictionary) -> Dictionary:
	var required: Array[String] = ["version", "inventory", "equipped", "talents", "skill_slots", "level", "xp", "talent_points"]
	if data.size() != required.size() or not data.has_all(required):
		return {}
	if not data.get("talents") is Dictionary:
		return {}
	var spent_points: int = 0
	for talent_id: Variant in data["talents"]:
		if not talent_id is String or not Data.TALENTS.has(talent_id):
			return {}
		var rank: Variant = data["talents"][talent_id]
		if not _is_bounded_int(rank, 0, int(Data.TALENTS[talent_id]["max_rank"])):
			return {}
		spent_points += int(rank)
	if spent_points + int(data["talent_points"]) != BASE_TALENT_POINTS + int(data["level"]) - 1:
		return {}
	var result: Dictionary = {
		"version": SAVE_VERSION, "inventory": data["inventory"].duplicate(), "equipped": data["equipped"].duplicate(),
		"equipment_instances": {}, "next_equipment_id": 1, "skill_supports": {},
		"skill_slots": data["skill_slots"].duplicate(), "level": int(data["level"]), "xp": int(data["xp"]),
		"talent_points": int(data["talent_points"]) + spent_points, "allocated_nodes": [Passives.START_ID],
		"jewels": JewelCatalog.starter_jewels(), "jewel_inventory": ["jewel_000001", "jewel_000002", "jewel_000003"],
		"socketed_jewels": {}, "next_jewel_id": 4,
		"crafting": {"materials": {Craft.MATERIAL_ID: 0}, "revision": 0},
	}
	var positions: Dictionary = _packed_layout(_backpack_keys(result["inventory"], result["equipped"], result["jewel_inventory"]))
	result["backpack_positions"] = {}
	for key: String in positions:
		var cell: Vector2i = positions[key]
		result["backpack_positions"][key] = [cell.x, cell.y]
	return result


func _backup_legacy_save(path: String) -> Error:
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path) != _migration_source_bytes:
		return ERR_FILE_ALREADY_IN_USE
	var backup_path: String = path + ".v%d-backup.json" % _migration_version
	if FileAccess.file_exists(backup_path):
		# Never overwrite a previously preserved legacy build with other bytes.
		if FileAccess.get_file_as_bytes(backup_path) != _migration_source_bytes:
			return ERR_ALREADY_EXISTS
	else:
		var backup_error: Error = _atomic_write_bytes(backup_path, _migration_source_bytes)
		if backup_error != OK:
			return backup_error
	migration_backup_path = backup_path
	return OK


static func _atomic_write(path: String, text: String) -> Error:
	return _atomic_write_bytes(path, text.to_utf8_buffer())


static func _atomic_write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var temporary_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return write_error
	var rename_error: Error = DirAccess.rename_absolute(temporary_path, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
	return rename_error


static func _is_bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number) and number >= minimum and number <= maximum


static func _add_stats(target: Dictionary, modifiers: Dictionary) -> void:
	for stat: String in modifiers:
		if target.has(stat):
			target[stat] = float(target[stat]) + float(modifiers[stat])


func get_backpack_items() -> Array[String]:
	return _backpack_keys(inventory, equipped, jewel_inventory)


func item_size(key: String) -> Vector2i:
	return _item_size_for(key, equipment_instances)


static func _item_size_for(key: String, instances: Dictionary = {}) -> Vector2i:
	if key.begins_with("item:"):
		var id: String = key.substr(5)
		if Data.ITEMS.has(id):
			return Data.ITEMS[id]["size"]
		# Instance validity is established before packing; size is base metadata.
		# Avoid formatting/validating every affix at each grid collision probe.
		var instance: Variant = instances.get(id, {})
		if instance is Dictionary:
			return Equipment.base_definition(str(instance.get("base_id", ""))).get("size", Vector2i.ZERO)
		return Vector2i.ZERO
	if key.begins_with("jewel:"):
		return Vector2i.ONE
	return Vector2i.ZERO


func can_place_in_backpack(key: String, cell: Vector2i) -> bool:
	var owned: bool = (key.begins_with("item:") and inventory.has(key.substr(5))) or (key.begins_with("jewel:") and jewel_inventory.has(key.substr(6)))
	return owned and _fits_in_layout(key, cell, backpack_positions, equipment_instances)


func move_in_backpack(key: String, cell: Vector2i) -> bool:
	if not get_backpack_items().has(key) or not can_place_in_backpack(key, cell):
		return false
	if backpack_positions.get(key, Vector2i(-1, -1)) == cell:
		return false
	backpack_positions[key] = cell
	changed.emit()
	return true


func unequip_to_backpack(slot: String, cell: Vector2i) -> bool:
	if not EQUIPMENT_SLOTS.has(slot) or not equipped.has(slot):
		return false
	var key: String = "item:" + str(equipped[slot])
	if not can_place_in_backpack(key, cell):
		return false
	equipped.erase(slot)
	backpack_positions[key] = cell
	changed.emit()
	return true


func auto_sort_backpack() -> bool:
	var sorted_layout: Dictionary = _packed_layout(get_backpack_items(), equipment_instances)
	if sorted_layout == backpack_positions:
		return false
	backpack_positions = sorted_layout
	changed.emit()
	return true


func _sync_backpack() -> void:
	var keys: Array[String] = get_backpack_items()
	var layout: Dictionary = {}
	for key: String in keys:
		if backpack_positions.has(key) and _fits_in_layout(key, backpack_positions[key], layout, equipment_instances):
			layout[key] = backpack_positions[key]
	for key: String in keys:
		if layout.has(key):
			continue
		var cell: Vector2i = _first_fit(key, layout, equipment_instances)
		if cell.x < 0:
			# Fragmentation cannot lose an item. The owned cap guarantees this pack fits.
			backpack_positions = _packed_layout(keys, equipment_instances)
			return
		layout[key] = cell
	backpack_positions = layout


static func _backpack_keys(owned_items: Array, worn: Dictionary, loose_jewels: Array) -> Array[String]:
	var result: Array[String] = []
	for id: String in owned_items:
		if not worn.values().has(id):
			result.append("item:" + id)
	for id: String in loose_jewels:
		result.append("jewel:" + id)
	return result


static func _owned_items_fit(items: Array, owned_jewels: Array, instances: Dictionary) -> bool:
	var keys: Array[String] = _backpack_keys(items, {}, owned_jewels)
	return _packed_layout(keys, instances).size() == keys.size()


static func _packed_layout(keys: Array[String], instances: Dictionary = {}) -> Dictionary:
	var sorted_keys: Array[String] = keys.duplicate()
	sorted_keys.sort_custom(func(a: String, b: String) -> bool:
		var first: Vector2i = _item_size_for(a, instances)
		var second: Vector2i = _item_size_for(b, instances)
		if first.y != second.y:
			return first.y > second.y
		if first.x != second.x:
			return first.x > second.x
		return a < b
	)
	var layout: Dictionary = {}
	for key: String in sorted_keys:
		var cell: Vector2i = _first_fit(key, layout, instances)
		if cell.x < 0:
			return {}
		layout[key] = cell
	return layout


static func _first_fit(key: String, layout: Dictionary, instances: Dictionary = {}) -> Vector2i:
	for y: int in range(BACKPACK_ROWS):
		for x: int in range(BACKPACK_COLUMNS):
			var cell := Vector2i(x, y)
			if _fits_in_layout(key, cell, layout, instances):
				return cell
	return Vector2i(-1, -1)


static func _fits_in_layout(key: String, cell: Vector2i, layout: Dictionary, instances: Dictionary = {}) -> bool:
	var dimensions: Vector2i = _item_size_for(key, instances)
	if dimensions.x <= 0 or dimensions.y <= 0 or cell.x < 0 or cell.y < 0:
		return false
	if cell.x + dimensions.x > BACKPACK_COLUMNS or cell.y + dimensions.y > BACKPACK_ROWS:
		return false
	var rectangle := Rect2i(cell, dimensions)
	for other: String in layout:
		if other != key and rectangle.intersects(Rect2i(layout[other], _item_size_for(other, instances))):
			return false
	return true


static func _validate_backpack(data: Dictionary) -> bool:
	if not data.get("backpack_positions") is Dictionary:
		return false
	var expected: Array[String] = _backpack_keys(data["inventory"], data["equipped"], data["jewel_inventory"])
	var positions: Dictionary = data["backpack_positions"]
	if positions.size() != expected.size():
		return false
	var instances: Dictionary = data.get("equipment_instances", {})
	if not _owned_items_fit(data["inventory"], data["jewels"].keys(), instances):
		return false
	var checked: Dictionary = {}
	for key: Variant in positions:
		if not key is String or not expected.has(key) or not positions[key] is Array:
			return false
		var coordinates: Array = positions[key]
		if coordinates.size() != 2 or not _is_bounded_int(coordinates[0], 0, BACKPACK_COLUMNS - 1) or not _is_bounded_int(coordinates[1], 0, BACKPACK_ROWS - 1):
			return false
		var cell := Vector2i(int(coordinates[0]), int(coordinates[1]))
		if not _fits_in_layout(key, cell, checked, instances):
			return false
		checked[key] = cell
	return true
