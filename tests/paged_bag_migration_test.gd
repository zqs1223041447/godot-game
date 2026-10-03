extends SceneTree

const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Legacy = preload("res://scripts/build_state.gd")
const LegacyMigration = preload("res://scripts/save/canonical_build_migration.gd")
const PagedMigration = preload("res://scripts/save/paged_bag_migration.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Layout = preload("res://scripts/items/item_location_rules.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var base := _v14_default()
	_expect(not base.is_empty() and Rules.reason_v14(Rules.decode_v14(base)).is_empty(),
		"fixture is a complete, validated v14 canonical build")
	var migrated := PagedMigration.migrate_v14(base)
	_expect(not migrated.is_empty() and migrated.version == 15 and Rules.reason(migrated).is_empty(),
		"ordinary v14 source converts to a valid v15 candidate")
	_expect(_same_except_locations_and_version(base, migrated),
		"ordinary conversion preserves every payload, UID, talent, binding, material, and ledger field")
	_expect(_non_bag_locations_equal(base.locations, migrated.locations),
		"all non-bag targets and existing recovery locations remain identical when there is no new overflow")
	for uid: String in migrated.locations:
		if migrated.locations[uid].kind == "bag":
			_expect(migrated.locations[uid].has_all(["kind", "page", "x", "y"])
				and migrated.locations[uid].page is int and migrated.locations[uid].page >= 0
				and migrated.locations[uid].page <= 1,
				"every bag location receives an explicit integer page")

	var edge := _v14_with_edge_armour()
	_expect(not edge.is_empty() and Rules.reason_v14(edge).is_empty(),
		"2×3 legacy item exactly touching the old 12×8 boundary is a valid v14 source")
	var edge_uid := "migration_test_armour"
	var edge_result := PagedMigration.migrate_v14(edge)
	_expect(not edge_result.is_empty() and edge_result.locations[edge_uid].kind == "bag"
		and edge_result.locations[edge_uid].page in [0, 1]
		and edge_result.locations[edge_uid].x + Items.metadata_for_items(edge_result.items)[edge_uid].size[0] <= 8
		and edge_result.locations[edge_uid].y + Items.metadata_for_items(edge_result.items)[edge_uid].size[1] <= 6
		and Rules.reason(edge_result).is_empty(),
		"2×3 legacy edge placement is deterministically repacked within one 8×6 page")
	_expect(_same_except_locations_and_version(edge, edge_result)
		and _non_bag_locations_equal(edge.locations, edge_result.locations),
		"repacking keeps every non-location field and non-bag target")

	var recovered := base.duplicate(true)
	var recovered_uid := _first_bag_uid(recovered.locations)
	if not recovered_uid.is_empty():
		recovered.locations[recovered_uid] = {"kind": "recovery", "index": 0}
	var recovered_result := PagedMigration.migrate_v14(recovered)
	_expect(not recovered_uid.is_empty() and Rules.reason_v14(recovered).is_empty()
		and not recovered_result.is_empty() and recovered_result.locations[recovered_uid] == {"kind": "recovery", "index": 0}
		and recovered_result.migration_ledger == recovered.migration_ledger,
		"original pending recovery UID/order and migration ledger survive the page conversion")

	var full := _v14_with_full_legacy_bag(96)
	var full_result := PagedMigration.migrate_v14(full)
	var full_validation := Layout.validate_paged(Items.metadata_for_items(full_result.get("items", {})),
		full_result.get("locations", {}), LegacyMigration.paged_location_context(full_result)) if not full_result.is_empty() else {}
	_expect(not full.is_empty() and Rules.reason_v14(full).is_empty() and not full_result.is_empty()
		and Rules.reason(full_result).is_empty() and full_validation.ok
		and full_validation.occupied_cells.size() == 96,
		"a full 96-cell legacy bag retains all UIDs across both 8×6 pages")
	if not full_result.is_empty():
		_expect(full_result.items.size() == full.items.size() and full_result.locations.size() == full.locations.size()
			and full_result.items == full.items,
			"full migration preserves every item envelope and location identity")

	var queue_locations := {
		"old_first": {"kind": "recovery", "index": 3},
		"old_second": {"kind": "recovery", "index": 7},
		"new_second": {"kind": "recovery", "index": 1},
		"new_first": {"kind": "recovery", "index": 0},
	}
	var old_queue := {"old_first": {"kind": "recovery", "index": 3},
		"old_second": {"kind": "recovery", "index": 7},
		"new_second": {"kind": "bag", "x": 0, "y": 0},
		"new_first": {"kind": "bag", "x": 1, "y": 0}}
	PagedMigration._append_new_recovery_after_existing(queue_locations, old_queue, [
		{"uid": "new_second", "index": 1, "reason": "no_paged_space"},
		{"uid": "new_first", "index": 0, "reason": "no_paged_space"},
	])
	_expect(queue_locations.old_first.index == 0 and queue_locations.old_second.index == 1
		and queue_locations.new_first.index == 2 and queue_locations.new_second.index == 3,
		"old recovery order stays first, then new overflow, with compact indices")

	print("Paged bag migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _v14_default() -> Dictionary:
	return LegacyMigration.migrate(Legacy.new()._snapshot())


func _v14_with_edge_armour() -> Dictionary:
	var result := _v14_default()
	if result.is_empty():
		return {}
	var uid := "migration_test_armour"
	result.items[uid] = Items.fixed_equipment(uid, "guardian_robe")
	result.locations[uid] = {"kind": "bag", "x": 10, "y": 5}
	var metadata: Dictionary = Items.metadata_for_items(result.items)
	var context: Dictionary = LegacyMigration.location_context(result)
	if not Layout.validate(metadata, result.locations, context).ok:
		return {}
	return result


func _v14_with_full_legacy_bag(cell_target: int) -> Dictionary:
	var result := _v14_default()
	if result.is_empty():
		return {}
	var metadata: Dictionary = Items.metadata_for_items(result.items)
	var context: Dictionary = LegacyMigration.location_context(result)
	var occupancy: Dictionary = Layout.validate(metadata, result.locations, context).occupied_cells
	var serial: int = int(result.next_item_serial)
	while occupancy.size() < cell_target:
		var free: Vector2i = Vector2i(-1, -1)
		for y: int in range(Layout.BAG_ROWS):
			for x: int in range(Layout.BAG_COLUMNS):
				if not occupancy.has("bag:%d:%d" % [x, y]):
					free = Vector2i(x, y)
					break
			if free.x >= 0:
				break
		if free.x < 0:
			return {}
		var uid := "item_%06d" % serial
		serial += 1
		while result.items.has(uid):
			uid = "item_%06d" % serial
			serial += 1
		var gem: Dictionary = Gems.create_instance(uid, "support:focus")
		if gem.is_empty():
			return {}
		result.items[uid] = gem
		result.locations[uid] = {"kind": "bag", "x": free.x, "y": free.y}
		occupancy["bag:%d:%d" % [free.x, free.y]] = uid
	result.next_item_serial = serial
	return result if Layout.validate(Items.metadata_for_items(result.items), result.locations, context).ok else {}


func _first_bag_uid(locations: Dictionary) -> String:
	var ids: Array[String] = []
	for uid: String in locations:
		if locations[uid].kind == "bag":
			ids.append(uid)
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


func _same_except_locations_and_version(before: Dictionary, after: Dictionary) -> bool:
	if after.is_empty():
		return false
	var copy := after.duplicate(true)
	copy.erase("version")
	copy.erase("locations")
	var expected := before.duplicate(true)
	expected.erase("version")
	expected.erase("locations")
	return copy == expected


func _non_bag_locations_equal(before: Dictionary, after: Dictionary) -> bool:
	for uid: String in before:
		if before[uid].kind != "bag" and before[uid] != after.get(uid, {}):
			return false
	return true


func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
