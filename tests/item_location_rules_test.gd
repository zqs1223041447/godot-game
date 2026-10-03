extends SceneTree
## Pure contract tests for item locations. No game state, saves, or random item generation.
const Rules = preload("res://scripts/items/item_location_rules.gd")
const RESULT_FIELDS: Array[String] = ["ok", "error_code", "reason", "occupied_cells", "occupied_targets"]
const SLOT_CATEGORIES: Dictionary = {
	"weapon": "weapon", "body_armour": "body_armour", "amulet": "amulet",
	"ring_1": "ring", "ring_2": "ring", "boots": "boots", "belt": "belt",
	"gloves": "gloves", "helmet": "helmet",
}
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(731902)
	var expected_rng: Array[int] = [randi(), randi(), randi(), randi()]
	seed(731902)
	_case(_test_valid_locations, "valid types, target map and footprints")
	_case(_test_exact_contract, "exact keys and one-location key set")
	_case(_test_equipment, "equipment categories and duplicate slots")
	_case(_test_skills_and_sockets, "skill rows, socket targets and duplicates")
	_case(_test_recovery, "migration recovery gate and indices")
	_case(_test_bag_boundaries, "12 by 8 bag bounds, overlap and capacity")
	_case(_test_integer_and_metadata_bounds, "true integers and bounded metadata")
	_case(_test_context_validation, "strict context schema and allowlists")
	_case(_test_purity_and_rng, "detached outputs and input/RNG purity")
	_expect([randi(), randi(), randi(), randi()] == expected_rng, "All validation calls preserve the global RNG stream")
	print("Item location rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	completed = false
	test.call()
	_expect(completed, "Case completes without a script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _item(kind: String, size: Array = [1, 1], category: String = "") -> Dictionary:
	return {"kind": kind, "category": category, "size": size}


func _context(allow_recovery: bool = false) -> Dictionary:
	return {
		"columns": 12,
		"rows": 8,
		"equipment_slots": SLOT_CATEGORIES.duplicate(true),
		# inactive_row remains configured and valid even if the UI does not render it.
		"skill_group_ids": ["row_a", "inactive_row"],
		"passive_socket_ids": ["node_10", "node_20"],
		"allow_recovery": allow_recovery,
	}


func _fixture(allow_recovery: bool = false) -> Dictionary:
	var metadata: Dictionary = {}
	var locations: Dictionary = {}
	for slot_id: String in SLOT_CATEGORIES:
		var uid: String = "gear_" + slot_id
		metadata[uid] = _item("equipment", [2, 2], SLOT_CATEGORIES[slot_id])
		locations[uid] = {"kind": "equipment", "slot_id": slot_id}
	metadata["jewel_socket"] = _item("jewel", [1, 1])
	locations["jewel_socket"] = {"kind": "passive_socket", "node_id": "node_10"}
	metadata["main_a"] = _item("skill_gem", [2, 1])
	locations["main_a"] = {"kind": "skill_main", "group_id": "row_a"}
	metadata["main_inactive"] = _item("skill_gem")
	locations["main_inactive"] = {"kind": "skill_main", "group_id": "inactive_row"}
	metadata["support_zero"] = _item("support_gem")
	locations["support_zero"] = {"kind": "skill_support", "group_id": "row_a", "index": 0}
	metadata["support_four"] = _item("support_gem")
	locations["support_four"] = {"kind": "skill_support", "group_id": "inactive_row", "index": 4}
	metadata["bag_large"] = _item("jewel", [2, 2])
	locations["bag_large"] = {"kind": "bag", "x": 0, "y": 0}
	metadata["bag_last_cell"] = _item("support_gem")
	locations["bag_last_cell"] = {"kind": "bag", "x": 11, "y": 7}
	if allow_recovery:
		metadata["recovered_item"] = _item("equipment", [1, 2], "boots")
		locations["recovered_item"] = {"kind": "recovery", "index": 4}
	return {"metadata": metadata, "locations": locations, "context": _context(allow_recovery)}


func _result(metadata: Dictionary, locations: Dictionary, context: Dictionary) -> Dictionary:
	return Rules.validate(metadata, locations, context)


func _expect_rejected(metadata: Variant, locations: Variant, context: Variant, expected_code: String, label: String) -> void:
	var result: Dictionary = Rules.validate(metadata, locations, context)
	_expect(_envelope(result), "Fixed result shape on failure: " + label)
	_expect(result.ok == false and result.error_code == expected_code and not result.reason.is_empty(), "Reject with %s (got %s): %s" % [expected_code, result.error_code, label])
	_expect(result.occupied_cells.is_empty() and result.occupied_targets.is_empty(), "Failure exposes no partial occupancy: " + label)


func _envelope(result: Dictionary) -> bool:
	return (result.size() == RESULT_FIELDS.size() and result.has_all(RESULT_FIELDS)
		and result.ok is bool and result.error_code is String and result.reason is String
		and result.occupied_cells is Dictionary and result.occupied_targets is Dictionary)


func _test_valid_locations() -> void:
	var fixture: Dictionary = _fixture(true)
	var result: Dictionary = _result(fixture.metadata, fixture.locations, fixture.context)
	_expect(_envelope(result) and result.ok, "Full valid mix returns the fixed success envelope")
	_expect(result.error_code == "" and result.reason == "", "Valid result has empty error fields")
	_expect(result.occupied_cells.size() == 5, "Only 2x2 and 1x1 bag objects occupy five cells")
	_expect(result.occupied_cells["bag:0:0"] == "bag_large" and result.occupied_cells["bag:1:1"] == "bag_large", "Cell keys use stable bag:x:y encoding")
	_expect(result.occupied_cells["bag:11:7"] == "bag_last_cell", "Bottom-right bag cell is included")
	_expect(result.occupied_targets.size() == 15, "All nine equipment targets and six non-bag targets are reported")
	_expect(result.occupied_targets["equipment:ring_1"] == "gear_ring_1" and result.occupied_targets["equipment:ring_2"] == "gear_ring_2", "Ring targets are independently occupied")
	_expect(result.occupied_targets["passive_socket:node_10"] == "jewel_socket", "Passive socket target uses stable encoding")
	_expect(result.occupied_targets["skill_main:inactive_row"] == "main_inactive", "Configured inactive row remains a valid target")
	_expect(result.occupied_targets["skill_support:inactive_row:4"] == "support_four", "Support target encodes group and index")
	_expect(result.occupied_targets["recovery:4"] == "recovered_item", "Migration recovery target uses stable encoding")
	completed = true


func _test_exact_contract() -> void:
	var fixture: Dictionary = _fixture()
	var metadata: Dictionary = fixture.metadata.duplicate(true)
	var locations: Dictionary = fixture.locations.duplicate(true)
	metadata.erase("bag_last_cell")
	_expect_rejected(metadata, locations, fixture.context, "location_set_mismatch", "metadata UID has no location")
	metadata = fixture.metadata.duplicate(true)
	locations["extra_uid"] = {"kind": "bag", "x": 0, "y": 0}
	_expect_rejected(metadata, locations, fixture.context, "location_set_mismatch", "unknown location UID metadata set mismatch")
	locations = fixture.locations.duplicate(true)
	locations["bag_last_cell"]["extra"] = 1
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "unknown extra location field")
	metadata = fixture.metadata.duplicate(true)
	metadata["bag_last_cell"]["extra"] = true
	_expect_rejected(metadata, fixture.locations, fixture.context, "invalid_metadata", "unknown extra metadata field")
	metadata = fixture.metadata.duplicate(true)
	metadata["bag_last_cell"] = {"kind": "future", "category": "", "size": [1, 1]}
	_expect_rejected(metadata, fixture.locations, fixture.context, "invalid_metadata", "unsupported item kind")
	for value: Variant in [null, [], "items", 1, 1.0, true]:
		_expect_rejected(value, fixture.locations, fixture.context, "invalid_input", "metadata must be a dictionary: " + str(value))
		_expect_rejected(fixture.metadata, value, fixture.context, "invalid_input", "locations must be a dictionary: " + str(value))
	completed = true


func _test_equipment() -> void:
	var fixture: Dictionary = _fixture()
	var locations: Dictionary = fixture.locations.duplicate(true)
	locations.gear_ring_2.slot_id = "ring_1"
	_expect_rejected(fixture.metadata, locations, fixture.context, "duplicate_target", "two items in one equipment target")
	locations = fixture.locations.duplicate(true)
	locations.gear_ring_1.slot_id = "boots"
	_expect_rejected(fixture.metadata, locations, fixture.context, "target_mismatch", "equipment category does not match target")
	locations = fixture.locations.duplicate(true)
	locations.gear_helmet.slot_id = "future_slot"
	_expect_rejected(fixture.metadata, locations, fixture.context, "target_mismatch", "unknown equipment target")
	var metadata: Dictionary = fixture.metadata.duplicate(true)
	metadata.gear_weapon.kind = "jewel"
	metadata.gear_weapon.category = ""
	_expect_rejected(metadata, fixture.locations, fixture.context, "kind_mismatch", "only equipment may use equipment target")
	metadata = fixture.metadata.duplicate(true)
	metadata.gear_body_armour.category = "staff"
	_expect_rejected(metadata, fixture.locations, fixture.context, "invalid_metadata", "equipment category allowlist")
	completed = true


func _test_skills_and_sockets() -> void:
	var fixture: Dictionary = _fixture()
	var locations: Dictionary = fixture.locations.duplicate(true)
	locations.main_inactive.group_id = "not_configured"
	_expect_rejected(fixture.metadata, locations, fixture.context, "target_mismatch", "unknown skill row")
	locations = fixture.locations.duplicate(true)
	locations.main_inactive.group_id = "row_a"
	_expect_rejected(fixture.metadata, locations, fixture.context, "duplicate_target", "duplicate skill main target")
	locations = fixture.locations.duplicate(true)
	locations.support_four.index = 0
	locations.support_four.group_id = "row_a"
	_expect_rejected(fixture.metadata, locations, fixture.context, "duplicate_target", "duplicate support target")
	locations = fixture.locations.duplicate(true)
	locations.support_four.index = 3
	_expect(Rules.validate(fixture.metadata, locations, fixture.context).ok, "Distinct support indices can share one skill row")
	locations = fixture.locations.duplicate(true)
	locations["gear_weapon"] = {"kind": "skill_main", "group_id": "row_a"}
	_expect_rejected(fixture.metadata, locations, fixture.context, "kind_mismatch", "only skill_gem may use main target")
	locations = fixture.locations.duplicate(true)
	locations["gear_weapon"] = {"kind": "skill_support", "group_id": "row_a", "index": 1}
	_expect_rejected(fixture.metadata, locations, fixture.context, "kind_mismatch", "only support_gem may use support target")
	locations = fixture.locations.duplicate(true)
	locations.jewel_socket.node_id = "node_99"
	_expect_rejected(fixture.metadata, locations, fixture.context, "target_mismatch", "unknown passive socket")
	locations = fixture.locations.duplicate(true)
	locations["gear_weapon"] = {"kind": "passive_socket", "node_id": "node_20"}
	_expect_rejected(fixture.metadata, locations, fixture.context, "kind_mismatch", "only jewel may use passive socket")
	locations = fixture.locations.duplicate(true)
	locations.jewel_socket.node_id = "node_20"
	locations["second_jewel"] = {"kind": "passive_socket", "node_id": "node_20"}
	var metadata: Dictionary = fixture.metadata.duplicate(true)
	metadata["second_jewel"] = _item("jewel")
	_expect_rejected(metadata, locations, fixture.context, "duplicate_target", "duplicate jewel socket")
	completed = true


func _test_recovery() -> void:
	var fixture: Dictionary = _fixture(true)
	_expect(Rules.validate(fixture.metadata, fixture.locations, fixture.context).ok, "Recovery location is allowed only when enabled")
	var regular_context: Dictionary = fixture.context.duplicate(true)
	regular_context.allow_recovery = false
	_expect_rejected(fixture.metadata, fixture.locations, regular_context, "recovery_disabled", "ordinary movement cannot use recovery")
	var locations: Dictionary = fixture.locations.duplicate(true)
	locations.recovered_item.index = -1
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "negative recovery index")
	locations = fixture.locations.duplicate(true)
	locations.recovered_item.index = 5
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "recovery index above four")
	locations = fixture.locations.duplicate(true)
	locations["another_recovery"] = {"kind": "recovery", "index": 4}
	var metadata: Dictionary = fixture.metadata.duplicate(true)
	metadata["another_recovery"] = _item("support_gem")
	_expect_rejected(metadata, locations, fixture.context, "duplicate_target", "duplicate recovery target")
	locations = fixture.locations.duplicate(true)
	locations["recovered_item"]["uid"] = "unexpected"
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "recovery rejects extra fields")
	completed = true


func _test_bag_boundaries() -> void:
	var fixture: Dictionary = _fixture()
	var locations: Dictionary = fixture.locations.duplicate(true)
	var metadata: Dictionary = fixture.metadata.duplicate(true)
	metadata.bag_last_cell.size = [2, 1]
	locations.bag_last_cell.x = 11
	_expect_rejected(metadata, locations, fixture.context, "out_of_bounds", "2x1 item crosses right edge")
	locations = fixture.locations.duplicate(true)
	locations.bag_last_cell.y = 6
	locations.bag_large.x = 11
	_expect_rejected(fixture.metadata, locations, fixture.context, "out_of_bounds", "2x2 item crosses right edge")
	locations = fixture.locations.duplicate(true)
	locations.bag_large.x = 0
	locations.bag_large.y = 7
	_expect_rejected(fixture.metadata, locations, fixture.context, "out_of_bounds", "2x2 item crosses bottom edge")
	locations = fixture.locations.duplicate(true)
	locations.bag_last_cell.x = -1
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "negative coordinate")
	locations = fixture.locations.duplicate(true)
	locations.bag_last_cell.x = 12
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "coordinate outside bag")
	locations = fixture.locations.duplicate(true)
	locations.bag_last_cell.x = 1
	locations.bag_last_cell.y = 1
	_expect_rejected(fixture.metadata, locations, fixture.context, "bag_overlap", "overlapping footprints")
	var full_metadata: Dictionary = {}
	var full_locations: Dictionary = {}
	for cell: int in range(96):
		var uid: String = "cell_%03d" % cell
		full_metadata[uid] = _item("jewel")
		full_locations[uid] = {"kind": "bag", "x": cell % 12, "y": int(cell / 12)}
	var full_result: Dictionary = Rules.validate(full_metadata, full_locations, _context())
	_expect(full_result.ok and full_result.occupied_cells.size() == 96, "All 96 non-overlapping bag cells may be occupied")
	full_metadata["overflow"] = _item("skill_gem")
	full_locations["overflow"] = {"kind": "bag", "x": 0, "y": 0}
	_expect_rejected(full_metadata, full_locations, _context(), "bag_overlap", "97th item cannot overlap a full bag")
	completed = true


func _test_integer_and_metadata_bounds() -> void:
	var fixture: Dictionary = _fixture()
	var locations: Dictionary = fixture.locations.duplicate(true)
	for invalid: Variant in [true, false, 1.0, 0.5, "0", null]:
		locations = fixture.locations.duplicate(true)
		locations.bag_last_cell.x = invalid
		_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "x must be int, got " + str(invalid))
		locations = fixture.locations.duplicate(true)
		locations.bag_last_cell.y = invalid
		_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "y must be int, got " + str(invalid))
	locations = fixture.locations.duplicate(true)
	locations.support_zero.index = true
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "support index rejects bool")
	locations = fixture.locations.duplicate(true)
	locations.support_zero.index = 1.0
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "support index rejects float")
	locations = fixture.locations.duplicate(true)
	locations.support_zero.index = -1
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "support index below zero")
	locations = fixture.locations.duplicate(true)
	locations.support_zero.index = 5
	_expect_rejected(fixture.metadata, locations, fixture.context, "invalid_location", "support index above four")
	for size: Variant in [[0, 1], [13, 1], [1, 9], [true, 1], [1.0, 1], [1, false], PackedInt32Array([1, 1]), [1]]:
		var metadata: Dictionary = fixture.metadata.duplicate(true)
		metadata.bag_large.size = size
		_expect_rejected(metadata, fixture.locations, fixture.context, "invalid_metadata", "reject malformed or unbounded size " + str(size))
	completed = true


func _test_context_validation() -> void:
	var fixture: Dictionary = _fixture()
	var context: Dictionary = fixture.context.duplicate(true)
	context.extra = true
	_expect_rejected(fixture.metadata, fixture.locations, context, "invalid_context", "context rejects extra field")
	context = fixture.context.duplicate(true)
	context.erase("rows")
	_expect_rejected(fixture.metadata, fixture.locations, context, "invalid_context", "context rejects missing field")
	for dimension: Variant in [11, 9, 12.0, true, "12"]:
		context = fixture.context.duplicate(true)
		context.columns = dimension
		_expect_rejected(fixture.metadata, fixture.locations, context, "invalid_context", "columns must be 12 true int: " + str(dimension))
	context = fixture.context.duplicate(true)
	context.allow_recovery = 1
	_expect_rejected(fixture.metadata, fixture.locations, context, "invalid_context", "allow_recovery must be bool")
	context = fixture.context.duplicate(true)
	context.equipment_slots.ring_2 = "amulet"
	_expect_rejected(fixture.metadata, fixture.locations, context, "invalid_context", "ring_2 target kind is fixed")
	context = fixture.context.duplicate(true)
	context.equipment_slots.future = "future"
	_expect_rejected(fixture.metadata, fixture.locations, context, "invalid_context", "equipment target map rejects extra slot")
	context = fixture.context.duplicate(true)
	context.skill_group_ids = ["row_a", "row_a"]
	_expect_rejected(fixture.metadata, fixture.locations, context, "invalid_context", "skill row ids must be unique")
	context = fixture.context.duplicate(true)
	context.passive_socket_ids = ["node_10", 4]
	_expect_rejected(fixture.metadata, fixture.locations, context, "invalid_context", "passive node ids must be strings")
	completed = true


func _test_purity_and_rng() -> void:
	var fixture: Dictionary = _fixture(true)
	var metadata_before: PackedByteArray = var_to_bytes(fixture.metadata)
	var locations_before: PackedByteArray = var_to_bytes(fixture.locations)
	var context_before: PackedByteArray = var_to_bytes(fixture.context)
	var first: Dictionary = Rules.validate(fixture.metadata, fixture.locations, fixture.context)
	_expect(first.ok, "Purity fixture validates")
	var reverse_metadata: Dictionary = {}
	var reverse_locations: Dictionary = {}
	var reversed_uids: Array = fixture.metadata.keys()
	reversed_uids.reverse()
	for uid: String in reversed_uids:
		reverse_metadata[uid] = fixture.metadata[uid]
		reverse_locations[uid] = fixture.locations[uid]
	var reordered: Dictionary = Rules.validate(reverse_metadata, reverse_locations, fixture.context)
	_expect(first.occupied_cells.keys() == reordered.occupied_cells.keys(), "Bag output keys are canonical across input order")
	_expect(first.occupied_targets.keys() == reordered.occupied_targets.keys(), "Target output keys are canonical across input order")
	_expect(metadata_before == var_to_bytes(fixture.metadata), "Validation preserves caller metadata")
	_expect(locations_before == var_to_bytes(fixture.locations), "Validation preserves caller locations")
	_expect(context_before == var_to_bytes(fixture.context), "Validation preserves caller context")
	var expected_copy: Dictionary = first.duplicate(true)
	first.occupied_cells.clear()
	first.occupied_targets.clear()
	first.reason = "caller mutation"
	var second: Dictionary = Rules.validate(fixture.metadata, fixture.locations, fixture.context)
	_expect(second == expected_copy, "Mutating a prior output cannot affect future results")
	var invalid_locations: Dictionary = fixture.locations.duplicate(true)
	invalid_locations.bag_last_cell.x = -1
	var bad_before: PackedByteArray = var_to_bytes(invalid_locations)
	var rejected: Dictionary = Rules.validate(fixture.metadata, invalid_locations, fixture.context)
	_expect(not rejected.ok and bad_before == var_to_bytes(invalid_locations), "Rejected validation preserves caller locations")
	completed = true
