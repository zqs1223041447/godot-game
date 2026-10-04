class_name CanonicalBuildMigration
extends RefCounted
## Pure v1-v13 -> canonical candidate conversion. The caller owns byte backup,
## full target-schema validation, atomic persistence and the final memory swap.
const Legacy = preload("res://scripts/build_state.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
const Layout = preload("res://scripts/items/item_location_rules.gd")
const Transfer = preload("res://scripts/items/item_transfer_plan.gd")
const Data = preload("res://scripts/game_data.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const VERSION := 14
const BASE_GROUPS := 10
const NORMAL_POINT_LIMIT := 123
# Verified against the pinned source classStartIndex. Not a single-class rule:
# a later class-selection transaction may choose any validated source start.
const DEFAULT_CLASS_ID := 0
const DEFAULT_START_ID := "58833"
const TREE_VERSION := "3.29.1"


static func migrate(raw: Variant) -> Dictionary:
	var legacy = Legacy.new()
	var old: Dictionary = legacy._validate_snapshot(raw)
	if old.is_empty():
		return {}
	var serial: int = maxi(int(old.next_equipment_id), int(old.next_jewel_id))
	var result: Dictionary = {"version": VERSION, "revision": 0, "items": {}, "locations": {},
		"next_item_serial": serial, "skill_groups": [], "bindings": [], "talents": {},
		"progress": {"level": int(old.level), "xp": int(old.xp)},
		"crafting": old.crafting.duplicate(true), "migration_ledger": {}}
	for uid: String in old.inventory:
		var item: Dictionary = Items.wrap_equipment(old.equipment_instances[uid]) if old.equipment_instances.has(uid) else Items.fixed_equipment(uid, uid)
		if item.is_empty() or result.items.has(uid):
			return {}
		result.items[uid] = item
	for uid: String in old.jewels:
		var item: Dictionary = Items.wrap_jewel(old.jewels[uid])
		if item.is_empty() or result.items.has(uid):
			return {}
		result.items[uid] = item
	for slot: String in old.equipped:
		result.locations[old.equipped[slot]] = {"kind": "equipment", "slot_id": Slots.legacy_slot(slot)}
	var skill_order: Array = old.skill_slots.duplicate()
	var remaining: Array = Data.LEGACY_SKILL_IDS.duplicate()
	remaining.sort()
	for id: String in remaining:
		if not skill_order.has(id):
			skill_order.append(id)
	var represented_supports: Dictionary = {}
	for index: int in range(BASE_GROUPS):
		var group_id: String = "group_%06d" % (index + 1)
		result.skill_groups.append({"id": group_id})
		if index >= skill_order.size():
			continue
		var skill_id: String = skill_order[index]
		var uid: String = _new_gem(result, "skill:" + skill_id)
		if uid.is_empty():
			return {}
		result.locations[uid] = {"kind": "skill_main", "group_id": group_id}
		# Preserve the first five hotkeys; make the remaining three directly usable.
		result.bindings.append({"group_id": group_id, "keycode": KEY_1 + index})
		var links: Array = old.skill_supports.get(skill_id, [])
		for support_index: int in range(links.size()):
			var support_id: String = links[support_index]
			uid = _new_gem(result, "support:" + support_id)
			if uid.is_empty():
				return {}
			result.locations[uid] = {"kind": "skill_support", "group_id": group_id, "index": support_index}
			represented_supports[support_id] = true
	# Previously free selectable definitions remain available after itemization.
	var support_ids: Array = Supports.SUPPORTS.keys()
	support_ids.sort()
	for support_id: String in support_ids:
		# This itemization step only grants the frozen schema14 vocabulary.
		if Gems.minimum_save_version("support:" + support_id) > VERSION: continue
		if not represented_supports.has(support_id) and _new_gem(result, "support:" + support_id).is_empty():
			return {}
	var metadata: Dictionary = Items.metadata_for_items(result.items)
	if metadata.size() != result.items.size():
		return {}
	var occupied: Dictionary = {}
	# Reuse legal bag positions before packing newly itemized gems / returned jewels.
	for key: String in old.backpack_positions:
		var uid: String = key.substr(6) if key.begins_with("jewel:") else key.substr(5) if key.begins_with("item:") else ""
		if not result.items.has(uid) or result.locations.has(uid):
			continue
		var point: Array = old.backpack_positions[key]
		var position: Dictionary = {"kind": "bag", "x": int(point[0]), "y": int(point[1])}
		if _fits(metadata[uid].size, position, occupied):
			result.locations[uid] = position
			Transfer._occupy(occupied, uid, position, metadata[uid].size)
	var pending: Array[String] = []
	for uid: String in result.items:
		if not result.locations.has(uid):
			pending.append(uid)
	pending.sort_custom(func(a: String, b: String) -> bool:
		var area_a: int = metadata[a].size[0] * metadata[a].size[1]
		var area_b: int = metadata[b].size[0] * metadata[b].size[1]
		return a < b if area_a == area_b else area_a > area_b)
	var recovery_index: int = 0
	for uid: String in pending:
		var position: Dictionary = Transfer._space_in_cells(metadata[uid].size, occupied)
		if position.is_empty():
			result.locations[uid] = {"kind": "recovery", "index": recovery_index}
			recovery_index += 1
		else:
			result.locations[uid] = position
			Transfer._occupy(occupied, uid, position, metadata[uid].size)
	var earned: int = int(old.talent_points) + old.allocated_nodes.size() - 1
	var budget: int = mini(earned, NORMAL_POINT_LIMIT)
	result.talents = {"source_version": TREE_VERSION, "class_id": DEFAULT_CLASS_ID,
		"allocated": [DEFAULT_START_ID], "masteries": {}, "ascendancy": "",
		"ascendancy_allocated": [], "normal_points": budget, "ascendancy_points": 0}
	result.migration_ledger = {"from_version": int(raw.version), "legacy_points_earned": earned,
		"legacy_points_refunded": old.allocated_nodes.size() - 1,
		"normal_budget_at_migration": budget, "excess_points_recorded": earned - budget,
		"default_class_id": DEFAULT_CLASS_ID, "default_start_id": DEFAULT_START_ID,
		"legacy_allocated_nodes": old.allocated_nodes.duplicate(),
		"returned_socketed_jewels": old.socketed_jewels.values().duplicate(),
		"initial_recovery_count": recovery_index}
	var layout: Dictionary = Layout.validate(metadata, result.locations, location_context(result))
	return result if layout.ok else {}


static func location_context(candidate: Dictionary, passive_socket_ids: Array = []) -> Dictionary:
	var groups: Array[String] = []
	for group: Dictionary in candidate.skill_groups:
		groups.append(group.id)
	var slots: Dictionary = {}
	for slot: String in Slots.all_slots():
		slots[slot] = Slots.category_for_slot(slot)
	return {"columns": 12, "rows": 8, "equipment_slots": slots,
		"skill_group_ids": groups, "passive_socket_ids": passive_socket_ids.duplicate(), "allow_recovery": true}


static func paged_location_context(candidate: Dictionary, passive_socket_ids: Array = []) -> Dictionary:
	var context := v15_location_context(candidate,passive_socket_ids)
	context.columns = Layout.CURRENT_BAG_COLUMNS
	context.rows = Layout.CURRENT_BAG_ROWS
	context.pages = Layout.CURRENT_BAG_PAGES
	return context


static func v15_location_context(candidate: Dictionary, passive_socket_ids: Array = []) -> Dictionary:
	var groups: Array[String] = []
	for group: Dictionary in candidate.skill_groups:
		groups.append(group.id)
	var slots: Dictionary = {}
	for slot: String in Slots.all_slots():
		slots[slot] = Slots.category_for_slot(slot)
	return {"columns": 8, "rows": 6, "pages": 2, "equipment_slots": slots,
		"skill_group_ids": groups, "passive_socket_ids": passive_socket_ids.duplicate(), "allow_recovery": true}


static func _new_gem(candidate: Dictionary, definition_id: String) -> String:
	# Migration identities use a reserved namespace, so a valid legacy save at
	# its exhausted gear/jewel serial boundary can still retain all implicit gems.
	# Ordinary future drops use the one next_item_serial allocator in the owner.
	var serial: int = 1
	while candidate.items.has("migration_gem_%06d" % serial): serial += 1
	var uid: String = "migration_gem_%06d" % serial
	var item: Dictionary = Gems.create_instance(uid, definition_id)
	if item.is_empty(): return ""
	candidate.items[uid] = item
	return uid


static func _fits(size: Array, position: Dictionary, occupied: Dictionary) -> bool:
	if position.x < 0 or position.y < 0 or position.x + size[0] > 12 or position.y + size[1] > 8:
		return false
	for y: int in range(position.y, position.y + size[1]):
		for x: int in range(position.x, position.x + size[0]):
			if occupied.has(Vector2i(x, y)):
				return false
	return true
