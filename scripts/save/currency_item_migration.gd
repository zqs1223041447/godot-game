class_name CurrencyItemMigration
extends RefCounted
## Pure v15 -> v16 conversion. The store calls this only after the complete
## legacy shape has passed its frozen v15 validator and owns backup/persistence.

const LegacyMigration = preload("res://scripts/save/canonical_build_migration.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Currency = preload("res://scripts/items/currency_catalog.gd")
const BagLayout = preload("res://scripts/items/paged_bag_layout.gd")

const FROM_VERSION := 15
const TO_VERSION := 16


static func migrate_v15(valid_v15: Variant, passive_socket_ids: Array = []) -> Dictionary:
	if not valid_v15 is Dictionary or typeof(valid_v15.get("version")) != TYPE_INT \
			or valid_v15.version != FROM_VERSION or not valid_v15.get("items") is Dictionary \
			or not valid_v15.get("locations") is Dictionary or not valid_v15.get("crafting") is Dictionary:
		return {}
	var old_crafting: Dictionary = valid_v15.crafting
	if old_crafting.size() != 2 or not old_crafting.has_all(["materials", "revision"]) \
			or not old_crafting.materials is Dictionary or old_crafting.materials.size() != 1 \
			or not old_crafting.materials.has("calibration_shard") \
			or typeof(old_crafting.materials.calibration_shard) != TYPE_INT \
			or old_crafting.materials.calibration_shard < 0 \
			or old_crafting.materials.calibration_shard > Currency.INVENTORY_LIMIT:
		return {}
	var candidate: Dictionary = valid_v15.duplicate(true)
	var balance: int = old_crafting.materials.calibration_shard
	candidate.crafting = {"revision": old_crafting.revision}
	candidate.version = TO_VERSION
	if balance == 0:
		return candidate
	if candidate.items.size() >= 2048:
		return {}
	var uid: String = _new_uid(candidate.items)
	if uid.is_empty():
		return {}
	var shard: Dictionary = Items.calibration_shard(uid, balance)
	if shard.is_empty():
		return {}
	candidate.items[uid] = shard
	var old_metadata: Dictionary = Items.metadata_for_items(valid_v15.items)
	if old_metadata.size() != valid_v15.items.size():
		return {}
	var context: Dictionary = LegacyMigration.location_context(valid_v15, passive_socket_ids)
	var inspected: Dictionary = BagLayout.inspect_layout(old_metadata, valid_v15.locations, context)
	if not inspected.get("ok", false):
		return {}
	var placement: Dictionary = BagLayout.find_space([1, 1], inspected.occupied_cells)
	if placement.get("ok", false):
		candidate.locations[uid] = placement.location.duplicate(true)
	else:
		var recovery_index: int = _first_recovery_index(candidate.locations, candidate.items.size())
		if recovery_index < 0:
			return {}
		candidate.locations[uid] = {"kind": "recovery", "index": recovery_index}
	return candidate


static func _new_uid(items: Dictionary) -> String:
	for serial: int in range(1, 2049):
		var uid := "currency_calibration_shard_%06d" % serial
		if not items.has(uid):
			return uid
	return ""


static func _first_recovery_index(locations: Dictionary, item_count: int) -> int:
	var used: Dictionary = {}
	for location: Variant in locations.values():
		if location is Dictionary and location.get("kind", "") == "recovery":
			used[int(location.index)] = true
	for index: int in range(item_count):
		if not used.has(index):
			return index
	return -1
