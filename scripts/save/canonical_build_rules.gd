class_name CanonicalBuildRules
extends RefCounted
## Canonical save envelope. Domain validators stay mandatory at the final boundary;
## item locations never stand in for skill compatibility or passive legality.
const Migration = preload("res://scripts/save/canonical_build_migration.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const VERSION := 14
const MAX_ITEMS := 1024
const MAX_GROUPS := 64
const MAX_SERIAL := 1000000000
const FIELDS := ["version", "revision", "items", "locations", "next_item_serial", "skill_groups", "bindings", "talents", "progress", "crafting", "migration_ledger"]
const BINDABLE_KEYS := [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
	KEY_E, KEY_F, KEY_G, KEY_H, KEY_J, KEY_L, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_N, KEY_M]


static func decode(raw: Variant) -> Dictionary:
	if not Locations._exact_string_keys(raw, FIELDS): return {}
	var value: Dictionary = raw.duplicate(true)
	for field: String in ["version", "revision", "next_item_serial"]:
		if not Items._whole(value[field], 0, MAX_SERIAL): return {}
		value[field] = int(value[field])
	if not value.items is Dictionary or not value.locations is Dictionary: return {}
	for uid: Variant in value.items:
		var item: Dictionary = Items.decode_instance(value.items[uid])
		if item.is_empty(): return {}
		value.items[uid] = item
	for uid: Variant in value.locations:
		var location: Dictionary = Items.decode_location(value.locations[uid])
		if location.is_empty(): return {}
		value.locations[uid] = location
	for group: String in ["progress", "crafting", "talents", "migration_ledger"]:
		if not value[group] is Dictionary: return {}
	for field: String in ["level", "xp"]:
		if not _decode_integer(value.progress, field): return {}
	if not _decode_integer(value.crafting, "revision") or not value.crafting.get("materials") is Dictionary: return {}
	if not _decode_integer(value.crafting.materials, "calibration_shard"): return {}
	for field: String in ["class_id", "normal_points", "ascendancy_points"]:
		if not _decode_integer(value.talents, field): return {}
	for field: String in ["from_version", "legacy_points_earned", "legacy_points_refunded", "normal_budget_at_migration", "excess_points_recorded", "default_class_id", "initial_recovery_count"]:
		if not _decode_integer(value.migration_ledger, field): return {}
	if not value.bindings is Array: return {}
	for binding: Variant in value.bindings:
		if not binding is Dictionary or not _decode_integer(binding, "keycode"): return {}
	return value


static func reason(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	if not Locations._exact_string_keys(value, FIELDS): return "保存结构无效"
	if not value.version is int or value.version != VERSION: return "保存版本不兼容"
	if not _integer(value.revision, 0, MAX_SERIAL) or not _integer(value.next_item_serial, 1, MAX_SERIAL): return "修订或物品序号无效"
	if not value.items is Dictionary or value.items.size() > MAX_ITEMS: return "物品注册表无效"
	var metadata: Dictionary = Items.metadata_for_items(value.items)
	if metadata.size() != value.items.size(): return "物品实例无效"
	for uid: String in value.items:
		var serial: int = Equipment.serial_from_id(uid) if uid.begins_with("gear_") else Jewels.serial_from_id(uid) if uid.begins_with("jewel_") else _item_serial(uid)
		if serial >= value.next_item_serial: return "物品序号不得重用"
	if not value.skill_groups is Array or value.skill_groups.size() < 10 or value.skill_groups.size() > MAX_GROUPS: return "技能行数量无效"
	var group_ids: Dictionary = {}
	for group: Variant in value.skill_groups:
		if not Locations._exact_string_keys(group, ["id"]) or not Locations._stable_id(group.id) or group_ids.has(group.id): return "技能行身份无效"
		group_ids[group.id] = true
	var layout: Dictionary = Locations.validate(metadata, value.locations, Migration.location_context(value, socket_ids))
	if not layout.ok: return layout.reason
	if not value.bindings is Array or value.bindings.size() > group_ids.size(): return "快捷键无效"
	var keys: Dictionary = {}
	var bound_groups: Dictionary = {}
	for binding: Variant in value.bindings:
		if not Locations._exact_string_keys(binding, ["group_id", "keycode"]) or not binding.group_id is String or not group_ids.has(binding.group_id) \
				or not binding.keycode is int or not BINDABLE_KEYS.has(binding.keycode) or keys.has(binding.keycode) or bound_groups.has(binding.group_id): return "快捷键重复或不可用"
		keys[binding.keycode] = true
		bound_groups[binding.group_id] = true
	for group_id: String in group_ids:
		var group: Dictionary = skill_contents(value, group_id)
		var seen: Dictionary = {}
		for support_id: String in group.support_ids:
			if seen.has(support_id): return "同组辅助定义不可重复"
			seen[support_id] = true
			if not group.skill_id.is_empty():
				var error: String = Supports.compatibility_reason(group.skill_id, [support_id])
				if not error.is_empty(): return error
	if not Locations._exact_string_keys(value.progress, ["level", "xp"]) or not _integer(value.progress.level, 1, 1000) \
			or not _integer(value.progress.xp, 0, 11 + int(value.progress.level) * 8) or (value.progress.level == 1000 and value.progress.xp != 0): return "成长进度无效"
	if not Locations._exact_string_keys(value.crafting, ["materials", "revision"]) or not _integer(value.crafting.revision, 0, MAX_SERIAL) \
			or not Locations._exact_string_keys(value.crafting.materials, ["calibration_shard"]) or not _integer(value.crafting.materials.calibration_shard, 0, MAX_SERIAL): return "制作材料或修订无效"
	var ledger_error: String = _ledger_reason(value.migration_ledger)
	if not ledger_error.is_empty(): return ledger_error
	# M1's conservative initial-tree validator is replaced by the source runtime
	# validator during M3 integration. Non-initial allocations cannot slip through.
	return str(validate_talents.call(value)) if validate_talents.is_valid() else initial_talents_reason(value)


static func skill_contents(value: Dictionary, group_id: String) -> Dictionary:
	var result: Dictionary = {"skill_id": "", "main_uid": "", "support_ids": [], "support_uids": []}
	var by_index: Dictionary = {}
	for uid: String in value.locations:
		var loc: Dictionary = value.locations[uid]
		if loc.get("group_id", "") != group_id: continue
		if loc.kind == "skill_main":
			result.main_uid = uid
			result.skill_id = str(value.items[uid].definition_id).trim_prefix("skill:")
		elif loc.kind == "skill_support":
			by_index[int(loc.index)] = uid
	for index: int in range(5):
		if not by_index.has(index): continue
		var uid: String = by_index[index]
		result.support_uids.append(uid)
		result.support_ids.append(str(value.items[uid].definition_id).trim_prefix("support:"))
	return result


static func initial_talents_reason(value: Dictionary) -> String:
	var talents: Variant = value.talents
	if not Locations._exact_string_keys(talents, ["source_version", "class_id", "allocated", "masteries", "ascendancy", "ascendancy_allocated", "normal_points", "ascendancy_points"]): return "天赋数据无效"
	if talents.source_version != Migration.TREE_VERSION or not talents.class_id is int or talents.class_id != Migration.DEFAULT_CLASS_ID \
			or talents.allocated != [Migration.DEFAULT_START_ID] or talents.masteries != {} or talents.ascendancy != "" or talents.ascendancy_allocated != [] \
			or not _integer(talents.normal_points, 0, Migration.NORMAL_POINT_LIMIT) or not talents.ascendancy_points is int or talents.ascendancy_points != 0: return "完整树消费者接入前只允许已验证初始天赋"
	if talents.normal_points != mini(int(value.progress.level) + 4, Migration.NORMAL_POINT_LIMIT): return "天赋预算不一致"
	return ""


static func _ledger_reason(value: Variant) -> String:
	var fields := ["from_version", "legacy_points_earned", "legacy_points_refunded", "normal_budget_at_migration", "excess_points_recorded", "default_class_id", "default_start_id", "legacy_allocated_nodes", "returned_socketed_jewels", "initial_recovery_count"]
	if not Locations._exact_string_keys(value, fields): return "迁移记录无效"
	for field: String in ["from_version", "legacy_points_earned", "legacy_points_refunded", "normal_budget_at_migration", "excess_points_recorded", "default_class_id", "initial_recovery_count"]:
		if not _integer(value[field], 0, MAX_SERIAL): return "迁移记录数值无效"
	if value.from_version > 13 or value.legacy_points_earned > 1004 or value.normal_budget_at_migration != mini(value.legacy_points_earned, 123) \
			or value.excess_points_recorded != value.legacy_points_earned - value.normal_budget_at_migration or value.legacy_points_refunded > value.legacy_points_earned \
			or value.default_class_id != Migration.DEFAULT_CLASS_ID or value.default_start_id != Migration.DEFAULT_START_ID \
			or value.initial_recovery_count > MAX_ITEMS: return "迁移预算记录不一致"
	for field: String in ["legacy_allocated_nodes", "returned_socketed_jewels"]:
		if not value[field] is Array or value[field].size() > MAX_ITEMS: return "迁移身份记录无效"
		var seen: Dictionary = {}
		for id: Variant in value[field]:
			if not Locations._stable_id(id) or seen.has(id): return "迁移身份记录重复"
			seen[id] = true
	return ""


static func _decode_integer(value: Dictionary, field: String) -> bool:
	if not value.has(field) or not Items._whole(value[field], 0, MAX_SERIAL): return false
	value[field] = int(value[field])
	return true
static func _integer(value: Variant, low: int, high: int) -> bool:
	return value is int and value >= low and value <= high
static func _item_serial(uid: String) -> int:
	if not uid.begins_with("item_"): return 0
	var digits := uid.substr(5)
	return int(digits) if digits.is_valid_int() and uid == "item_%06d" % int(digits) else 0
