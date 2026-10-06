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
const Currency = preload("res://scripts/items/currency_catalog.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const V14_VERSION := 14
const V15_VERSION := 15
const V16_VERSION := 16
const V17_VERSION := 17
const V18_VERSION := 18
const V19_VERSION := 19
const V20_VERSION := 20
const V21_VERSION := 21
const V22_VERSION := 22
const V23_VERSION := 23
const V24_VERSION := 24
const V25_VERSION := 25
const V26_VERSION := 26
const V27_VERSION := 27
const V28_VERSION := 28
const V29_VERSION := 29
const V30_VERSION := 30
const V31_VERSION := 31
const V32_VERSION := 32
const V33_VERSION := 33
const V34_VERSION := 34
const V35_VERSION := 35
const V36_VERSION := 36
const V37_VERSION := 37
const V38_VERSION := 38
const V39_VERSION := 39
const V40_VERSION := 40
const V41_VERSION := 41
const V42_VERSION := 42
const VERSION := 43
const LEGACY_MAX_ITEMS := 1024
const V17_MAX_ITEMS := LEGACY_MAX_ITEMS + 1
const MAX_ITEMS := V17_MAX_ITEMS + 2 # Two once-only migration bottles; bag capacity is unchanged.
const MAX_GROUPS := 64
const MAX_SERIAL := 1000000000
const LEGACY_FIELDS := ["version", "revision", "items", "locations", "next_item_serial", "skill_groups", "bindings", "talents", "progress", "crafting", "migration_ledger"]
const FIELDS := ["version", "revision", "items", "locations", "next_item_serial", "skill_groups", "bindings", "talents", "progress", "crafting", "migration_ledger", "journey"]
const V18_BINDABLE_KEYS := [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
	KEY_E, KEY_F, KEY_G, KEY_H, KEY_J, KEY_L, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_N, KEY_M]
const BINDABLE_KEYS := [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
	KEY_E, KEY_F, KEY_G, KEY_H, KEY_J, KEY_L, KEY_Z, KEY_X, KEY_V, KEY_N, KEY_M]


static func decode(raw: Variant) -> Dictionary:
	return _decode(raw, true, VERSION, true)


static func decode_v18(raw:Variant)->Dictionary:
	return _decode(raw,true,V18_VERSION,true)

static func decode_v25(raw:Variant)->Dictionary:
	return _decode(raw,true,V25_VERSION,true)


static func decode_v26(raw: Variant) -> Dictionary:
	return _decode(raw, true, V26_VERSION, true)


static func decode_v27(raw: Variant) -> Dictionary:
	return _decode(raw, true, V27_VERSION, true)


static func decode_v28(raw: Variant) -> Dictionary:
	return _decode(raw, true, V28_VERSION, true)


static func decode_v29(raw: Variant) -> Dictionary:
	return _decode(raw, true, V29_VERSION, true)


## Freeze all schema42 fields, source policy41 and equipment vocabulary39.
## Current catalogs must not admit a schema43 gem through an older envelope.
static func decode_v42(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V42_VERSION, true)
	return decoded if reason_v42(decoded).is_empty() else {}


## Freeze all schema41 fields, source policy41 and equipment vocabulary39.
## Current catalogs must not admit later gems through an older envelope.
static func decode_v41(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V41_VERSION, true)
	return decoded if reason_v41(decoded).is_empty() else {}


## Freeze all schema40 fields, source policy40 and equipment vocabulary39.
static func decode_v40(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V40_VERSION, true)
	return decoded if reason_v40(decoded).is_empty() else {}


## Freeze all schema39 fields, source policy38 and equipment vocabulary39.
static func decode_v39(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V39_VERSION, true)
	return decoded if reason_v39(decoded).is_empty() else {}


## Freeze all schema38 fields, source policy38 and equipment vocabulary37.
static func decode_v38(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V38_VERSION, true)
	return decoded if reason_v38(decoded).is_empty() else {}


## Freeze all schema37 fields, source policy36 and equipment vocabulary37.
static func decode_v37(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V37_VERSION, true)
	return decoded if reason_v37(decoded).is_empty() else {}


## Schema36 opens maximum resistance source nodes, but keeps equipment vocabulary34.
static func decode_v36(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V36_VERSION, true)
	return decoded if reason_v36(decoded).is_empty() else {}


## Freeze the entire schema35 envelope before opening maximum resistance nodes.
static func decode_v35(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V35_VERSION, true)
	return decoded if reason_v35(decoded).is_empty() else {}


## Schema34 keeps the schema33 source vocabulary and the existing equipment pools.
static func decode_v34(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V34_VERSION, true)
	return decoded if reason_v34(decoded).is_empty() else {}


## The last pre-forgeblade envelope must validate completely before migration.
static func decode_v33(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V33_VERSION, true)
	return decoded if reason_v33(decoded).is_empty() else {}


static func decode_v32(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V32_VERSION, true)
	return decoded if reason_v32(decoded).is_empty() else {}


static func decode_v31(raw: Variant) -> Dictionary:
	var decoded := _decode(raw, true, V31_VERSION, true)
	return decoded if reason_v31(decoded).is_empty() else {}


static func decode_v30(raw: Variant) -> Dictionary:
	return _decode(raw, true, V30_VERSION, true)


static func decode_v24(raw:Variant)->Dictionary:
	return _decode(raw,true,V24_VERSION,true)


static func decode_v23(raw:Variant)->Dictionary:
	return _decode(raw,true,V23_VERSION,true)


static func decode_v22(raw:Variant)->Dictionary:
	return _decode(raw,true,V22_VERSION,true)


static func decode_v21(raw:Variant)->Dictionary:
	return _decode(raw,true,V21_VERSION,true)


static func decode_v20(raw:Variant)->Dictionary:
	return _decode(raw,true,V20_VERSION,true)


static func decode_v19(raw:Variant)->Dictionary:
	return _decode(raw,true,V19_VERSION,true)


static func decode_v17(raw:Variant)->Dictionary:
	return _decode(raw,true,V17_VERSION,true)


static func decode_v16(raw: Variant) -> Dictionary:
	return _decode(raw, true, V16_VERSION, true)


## Preserve the v15 paged-bag/wallet contract before converting the wallet to
## item stacks. This decoder deliberately rejects v16-only currency instances.
static func decode_v15(raw: Variant) -> Dictionary:
	return _decode(raw, true, V15_VERSION, false)


## Preserve the exact v14 decoder contract for the mandatory pre-migration
## validation pass. v14 bag locations have no page field.
static func decode_v14(raw: Variant) -> Dictionary:
	return _decode(raw, false, V14_VERSION, false)


static func _decode(raw: Variant, paged: bool, expected_version: int, allow_currency: bool) -> Dictionary:
	if not Locations._exact_string_keys(raw, FIELDS if expected_version >= 26 else LEGACY_FIELDS): return {}
	var value: Dictionary = raw.duplicate(true)
	for field: String in ["version", "revision", "next_item_serial"]:
		if not Items._whole(value[field], 0, MAX_SERIAL): return {}
		value[field] = int(value[field])
	if value.version != expected_version: return {}
	if expected_version >= 26:
		value.journey = Journey.decode_legacy(value.journey) if expected_version <= V29_VERSION else Journey.decode(value.journey)
		if value.journey.is_empty(): return {}
	if not value.items is Dictionary or not value.locations is Dictionary: return {}
	for uid: Variant in value.items:
		if not allow_currency and value.items[uid] is Dictionary and value.items[uid].get("kind", "") == "currency": return {}
		var item: Dictionary = Items.decode_instance(value.items[uid])
		if item.is_empty(): return {}
		# A current item decoder may know later affixes. Opening an old envelope
		# must still prove its payload belongs to that envelope's vocabulary.
		if expected_version < Equipment.CURRENT_VOCABULARY and item.kind == "equipment" and not item.payload.is_empty() \
				and not Equipment.validate_instance_for_version(item.payload, equipment_vocabulary_for_save_version(expected_version)): return {}
		if item.kind=="flask" and expected_version<18:return {}
		if item.kind in ["skill_gem","support_gem"] and Items.Gems.minimum_save_version(item.definition_id)>expected_version: return {}
		value.items[uid] = item
	for uid: Variant in value.locations:
		var location: Dictionary = Items.decode_current_location(value.locations[uid]) if expected_version>=18 else Items.decode_v17_location(value.locations[uid]) if allow_currency else Items.decode_paged_location(value.locations[uid]) if paged else Items.decode_location(value.locations[uid])
		if location.is_empty(): return {}
		value.locations[uid] = location
	for group: String in ["progress", "crafting", "talents", "migration_ledger"]:
		if not value[group] is Dictionary: return {}
	for field: String in ["level", "xp"]:
		if not _decode_integer(value.progress, field): return {}
	if not _decode_integer(value.crafting, "revision"): return {}
	if allow_currency:
		if not Locations._exact_string_keys(value.crafting, ["revision"]): return {}
	else:
		if not value.crafting.get("materials") is Dictionary: return {}
		if not _decode_integer(value.crafting.materials, "calibration_shard"): return {}
	for field: String in ["class_id", "normal_points", "ascendancy_points"]:
		if not _decode_integer(value.talents, field): return {}
	if not value.talents.get("masteries") is Dictionary: return {}
	for id: Variant in value.talents.masteries:
		if not id is String or not _decode_integer(value.talents.masteries,id): return {}
	for field: String in ["from_version", "legacy_points_earned", "legacy_points_refunded", "normal_budget_at_migration", "excess_points_recorded", "default_class_id", "initial_recovery_count"]:
		if not _decode_integer(value.migration_ledger, field): return {}
	if not value.bindings is Array: return {}
	for binding: Variant in value.bindings:
		if not binding is Dictionary or not _decode_integer(binding, "keycode"): return {}
	return value


static func reason(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	var native_reason := _reason(value, VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v18(value:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->String:
	return _reason(value,V18_VERSION,true,true,MAX_ITEMS,validate_talents,socket_ids)

static func reason_v19(value:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->String:
	return _reason(value,V19_VERSION,true,true,MAX_ITEMS,validate_talents,socket_ids)

static func reason_v25(value:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->String:
	return _reason(value,V25_VERSION,true,true,MAX_ITEMS,validate_talents,socket_ids)


static func reason_v26(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V26_VERSION, true, true, MAX_ITEMS, validate_talents, socket_ids)


static func reason_v27(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V27_VERSION, true, true, MAX_ITEMS, validate_talents, socket_ids)


static func reason_v28(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V28_VERSION, true, true, MAX_ITEMS, validate_talents, socket_ids)


static func reason_v29(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V29_VERSION, true, true, MAX_ITEMS, validate_talents, socket_ids)


static func reason_v42(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# Full frozen native legality is mandatory; callbacks can only add restrictions.
	var native_reason := _reason(value, V42_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v41(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# Full frozen native legality is mandatory; callbacks can only add restrictions.
	var native_reason := _reason(value, V41_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v40(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# Frozen native legality is mandatory; callbacks can only add restrictions.
	var native_reason := _reason(value, V40_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v39(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# Frozen native legality is mandatory; callbacks can only add restrictions.
	var native_reason := _reason(value, V39_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v38(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# Frozen native source and equipment legality always precede extra restrictions.
	var native_reason := _reason(value, V38_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v37(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# A caller may add restrictions only after the whole frozen envelope is legal.
	var native_reason := _reason(value, V37_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v36(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# Neither equipment nor native source legality may be relaxed by a callback.
	var native_reason := _reason(value, V36_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v35(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# A callback may add restrictions, never bypass frozen source legality.
	var native_reason := _reason(value, V35_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v34(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# Frozen native source validation cannot be bypassed by a caller callback.
	var native_reason := _reason(value, V34_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v33(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	# Native schema33 talent legality is mandatory even when a caller adds a check.
	var native_reason := _reason(value, V33_VERSION, true, true, MAX_ITEMS, Callable(), socket_ids)
	if not native_reason.is_empty(): return native_reason
	return str(validate_talents.call(value)) if validate_talents.is_valid() else ""


static func reason_v32(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V32_VERSION, true, true, MAX_ITEMS, validate_talents, socket_ids)


static func reason_v31(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V31_VERSION, true, true, MAX_ITEMS, validate_talents, socket_ids)


static func reason_v30(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V30_VERSION, true, true, MAX_ITEMS, validate_talents, socket_ids)


static func reason_v24(value:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->String:
	return _reason(value,V24_VERSION,true,true,MAX_ITEMS,validate_talents,socket_ids)


static func reason_v23(value:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->String:
	return _reason(value,V23_VERSION,true,true,MAX_ITEMS,validate_talents,socket_ids)


static func reason_v22(value:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->String:
	return _reason(value,V22_VERSION,true,true,MAX_ITEMS,validate_talents,socket_ids)


static func reason_v21(value:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->String:
	return _reason(value,V21_VERSION,true,true,MAX_ITEMS,validate_talents,socket_ids)


static func reason_v20(value:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->String:
	return _reason(value,V20_VERSION,true,true,MAX_ITEMS,validate_talents,socket_ids)


static func reason_v17(value:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->String:
	return _reason(value,V17_VERSION,true,true,V17_MAX_ITEMS,validate_talents,socket_ids)


static func reason_v16(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V16_VERSION, true, true, V17_MAX_ITEMS, validate_talents, socket_ids)


static func reason_v15(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V15_VERSION, true, false, LEGACY_MAX_ITEMS, validate_talents, socket_ids)


static func reason_v14(value: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> String:
	return _reason(value, V14_VERSION, false, false, LEGACY_MAX_ITEMS, validate_talents, socket_ids)


static func _reason(value: Variant, expected_version: int, paged: bool, allow_currency: bool,
		item_limit: int, validate_talents: Callable, socket_ids: Array) -> String:
	if not Locations._exact_string_keys(value, FIELDS if expected_version >= 26 else LEGACY_FIELDS): return "保存结构无效"
	if not value.version is int or value.version != expected_version: return "保存版本不兼容"
	if expected_version >= 26:
		var journey_error: String = Journey.reason_legacy(value.journey) if expected_version <= V29_VERSION else Journey.reason(value.journey)
		if not journey_error.is_empty(): return journey_error
	if not _integer(value.revision, 0, MAX_SERIAL) or not _integer(value.next_item_serial, 1, MAX_SERIAL): return "修订或物品序号无效"
	if not value.items is Dictionary or value.items.size() > item_limit: return "物品注册表无效"
	if expected_version<18:
		for item:Variant in value.items.values():
			if item is Dictionary and item.get("kind","")=="flask":return "旧版本不能包含药剂物品"
	if not allow_currency:
		for item: Variant in value.items.values():
			if item is Dictionary and item.get("kind", "") == "currency": return "旧版本不能包含货币物品"
	# Older envelopes need a frozen vocabulary check before current metadata can
	# accept them. Current saves retain the complete typed positive-cache path.
	if expected_version < Equipment.CURRENT_VOCABULARY:
		for item: Variant in value.items.values():
			if item is Dictionary and item.get("kind", "") == "equipment" \
					and item.get("payload") is Dictionary and not item.payload.is_empty() \
					and not Equipment.validate_instance_for_version(item.payload, equipment_vocabulary_for_save_version(expected_version)):
				return "此存档版本不能包含新增装备词缀"
	var metadata: Dictionary = Items.metadata_for_items(value.items)
	if metadata.size() != value.items.size(): return "物品实例无效"
	if allow_currency and not Currency.total_quantity(value.items).ok: return "校准碎片堆或全库存数量无效"
	for uid: String in value.items:
		var instance: Dictionary=value.items[uid]
		if instance.kind in ["skill_gem","support_gem"] and Items.Gems.minimum_save_version(instance.definition_id)>expected_version: return "此存档版本不能包含新增宝石"
		var serial: int = Equipment.serial_from_id(uid) if uid.begins_with("gear_") else Jewels.serial_from_id(uid) if uid.begins_with("jewel_") else _item_serial(uid)
		if serial >= value.next_item_serial: return "物品序号不得重用"
	if not value.skill_groups is Array or value.skill_groups.size() < 10 or value.skill_groups.size() > MAX_GROUPS: return "技能行数量无效"
	var group_ids: Dictionary = {}
	for group: Variant in value.skill_groups:
		if not Locations._exact_string_keys(group, ["id"]) or not Locations._stable_id(group.id) or group_ids.has(group.id): return "技能行身份无效"
		group_ids[group.id] = true
	var valid_sockets := SourceTree.Data.standard_socket_ids() if socket_ids.is_empty() else socket_ids
	var layout_context: Dictionary = Migration.paged_location_context(value, valid_sockets) if allow_currency else Migration.v15_location_context(value, valid_sockets) if paged else Migration.location_context(value, valid_sockets)
	var layout: Dictionary = Locations.validate_current(metadata,value.locations,layout_context) if expected_version>=18 else Locations.validate_v17(metadata,value.locations,layout_context) if allow_currency else Locations.validate_paged(metadata, value.locations, layout_context) if paged else Locations.validate(metadata, value.locations, layout_context)
	if not layout.ok: return layout.reason
	if not value.bindings is Array or value.bindings.size() > group_ids.size(): return "快捷键无效"
	var keys: Dictionary = {}
	var bound_groups: Dictionary = {}
	for binding: Variant in value.bindings:
		if not Locations._exact_string_keys(binding, ["group_id", "keycode"]) or not binding.group_id is String or not group_ids.has(binding.group_id) \
				or not binding.keycode is int or not (V18_BINDABLE_KEYS if expected_version<=V18_VERSION else BINDABLE_KEYS).has(binding.keycode) or keys.has(binding.keycode) or bound_groups.has(binding.group_id): return "快捷键重复或不可用"
		keys[binding.keycode] = true
		bound_groups[binding.group_id] = true
	for group_id: String in group_ids:
		var group: Dictionary = skill_contents(value, group_id)
		var seen: Dictionary = {}
		for support_id: String in group.support_ids:
			if seen.has(support_id): return "同组辅助定义不可重复"
			seen[support_id] = true
		if not group.skill_id.is_empty():
			var error: String = Supports.compatibility_reason(group.skill_id, group.support_ids, Supports.GROUP_MAX_SUPPORTS)
			if not error.is_empty(): return error
	if not Locations._exact_string_keys(value.progress, ["level", "xp"]) or not _integer(value.progress.level, 1, 1000) \
			or not _integer(value.progress.xp, 0, 11 + int(value.progress.level) * 8) or (value.progress.level == 1000 and value.progress.xp != 0): return "成长进度无效"
	if not value.crafting is Dictionary or not _integer(value.crafting.get("revision"), 0, MAX_SERIAL): return "制作修订无效"
	if allow_currency:
		if not Locations._exact_string_keys(value.crafting, ["revision"]): return "schema16 制作区只能保存修订号"
	else:
		if not Locations._exact_string_keys(value.crafting, ["materials", "revision"]) \
				or not Locations._exact_string_keys(value.crafting.get("materials"), ["calibration_shard"]) \
				or not _integer(value.crafting.materials.calibration_shard, 0, MAX_SERIAL): return "旧版制作材料或修订无效"
	var ledger_error: String = _ledger_reason(value.migration_ledger)
	if not ledger_error.is_empty(): return ledger_error
	return str(validate_talents.call(value)) if validate_talents.is_valid() else SourceTree.reason(value)


## Source-only schemas35/36/38/40/41 and gem-only42/43 define no equipment vocabularies.
## Keep save-to-equipment mapping explicit and the Catalog API historically strict.
static func equipment_vocabulary_for_save_version(save_version: int) -> int:
	if save_version >= V39_VERSION: return 39
	if save_version >= V37_VERSION: return 37
	return 34 if save_version >= V34_VERSION else save_version


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
		or value.initial_recovery_count > LEGACY_MAX_ITEMS: return "迁移预算记录不一致"
	for field: String in ["legacy_allocated_nodes", "returned_socketed_jewels"]:
		if not value[field] is Array or value[field].size() > LEGACY_MAX_ITEMS: return "迁移身份记录无效"
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
