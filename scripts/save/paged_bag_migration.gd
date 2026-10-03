class_name PagedBagMigration
extends RefCounted
## v14 has already passed CanonicalBuildRules.decode_v14/reason_v14 when this
## pure converter is called. It changes the schema version and bag locations;
## the store remains responsible for full v15 validation and durable commit.
const LegacyMigration = preload("res://scripts/save/canonical_build_migration.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const BagLayout = preload("res://scripts/items/paged_bag_layout.gd")

const FROM_VERSION := 14
const TO_VERSION := 15


static func migrate_v14(valid_v14: Variant, passive_socket_ids: Array = []) -> Dictionary:
	if not valid_v14 is Dictionary or not valid_v14.get("version") is int \
			or valid_v14.version != FROM_VERSION or not valid_v14.get("items") is Dictionary \
			or not valid_v14.get("locations") is Dictionary:
		return {}
	var source_items: Dictionary = valid_v14.items
	var source_locations: Dictionary = valid_v14.locations
	var metadata: Dictionary = Items.metadata_for_items(source_items)
	if metadata.size() != source_items.size():
		return {}
	var context: Dictionary = LegacyMigration.location_context(valid_v14, passive_socket_ids)
	var plan: Dictionary = BagLayout.plan(metadata, source_locations, context)
	if not plan.get("ok", false):
		return {}
	var candidate: Dictionary = valid_v14.duplicate(true)
	candidate.locations = plan.locations.duplicate(true)
	_append_new_recovery_after_existing(candidate.locations, source_locations, plan.recovery)
	candidate.version = TO_VERSION
	return candidate


## The v14 owner emits dense recovery indices. Keep each existing pending UID
## ahead of overflow from the pack plan; close the queue once if newly
## unplaceable bag items need recovery slots.
static func _append_new_recovery_after_existing(locations: Dictionary,
		old_locations: Dictionary, recovery_entries: Array) -> void:
	var existing: Array[String] = []
	for uid: String in old_locations:
		if old_locations[uid].kind == "recovery":
			existing.append(uid)
	existing.sort_custom(func(a: String, b: String) -> bool:
		var index_a: int = int(old_locations[a].index)
		var index_b: int = int(old_locations[b].index)
		return a < b if index_a == index_b else index_a < index_b)

	var overflow: Array[String] = []
	for entry: Dictionary in recovery_entries:
		var uid: String = str(entry.get("uid", ""))
		if old_locations.has(uid) and old_locations[uid].kind == "bag" \
				and locations.get(uid, {}).get("kind", "") == "recovery":
			overflow.append(uid)
	overflow.sort_custom(func(a: String, b: String) -> bool:
		var index_a: int = int(locations[a].index)
		var index_b: int = int(locations[b].index)
		return a < b if index_a == index_b else index_a < index_b)
	if overflow.is_empty():
		return

	var ordered: Array[String] = existing.duplicate()
	ordered.append_array(overflow)
	for index: int in range(ordered.size()):
		locations[ordered[index]] = {"kind": "recovery", "index": index}
