extends SceneTree
## Focused pure tests for deterministic page-aware bag planning.
const Paged = preload("res://scripts/items/paged_bag_layout.gd")
const Legacy = preload("res://scripts/items/item_location_rules.gd")
const RESULT_FIELDS: Array[String] = ["ok", "error_code", "reason", "locations", "recovery", "occupied_cells", "occupied_targets"]
const SLOT_CATEGORIES: Dictionary = {
	"weapon": "weapon", "body_armour": "body_armour", "amulet": "amulet",
	"ring_1": "ring", "ring_2": "ring", "boots": "boots", "belt": "belt",
	"gloves": "gloves", "helmet": "helmet",
}
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(731902)
	var expected_rng: Array[int] = [randi(), randi(), randi(), randi()]
	seed(731902)
	_case(_test_96_single_cells, "all 96 single cells fit across both pages")
	_case(_test_multicell_reflow, "multi-cell items are searched and stay within a page")
	_case(_test_visible_recovery, "oversize items receive explicit safe recovery")
	_case(_test_existing_recovery_indices, "existing recovery indices survive without collision")
	_case(_test_preservation_and_determinism, "UIDs and non-bag targets remain stable")
	_case(_test_full_pages_and_placement_api, "full page occupancy rejects another placement")
	_case(_test_strict_schema, "integer, size and unknown-field contracts are strict")
	_case(_test_inspect_and_arrange, "inspection and arrangement are pure and repeatable")
	_expect([randi(), randi(), randi(), randi()] == expected_rng, "All planner and occupancy calls preserve global RNG state")
	print("Paged bag layout: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	var before: int = failures
	test.call()
	_expect(failures == before, "Case passes: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _item(kind: String = "jewel", size: Array = [1, 1], category: String = "") -> Dictionary:
	return {"kind": kind, "category": category, "size": size}


func _context(allow_recovery: bool = true) -> Dictionary:
	return {
		"columns": 12,
		"rows": 8,
		"equipment_slots": SLOT_CATEGORIES.duplicate(true),
		"skill_group_ids": ["row_a", "row_b"],
		"passive_socket_ids": ["node_10", "node_20"],
		"allow_recovery": allow_recovery,
	}


func _failure_is_empty(result: Dictionary, expected_code: String, label: String) -> void:
	_expect(result.size() == RESULT_FIELDS.size() and result.has_all(RESULT_FIELDS), "Fixed plan result shape on failure: " + label)
	_expect(not result.ok and result.error_code == expected_code and not result.reason.is_empty(), "Explicit %s failure: %s" % [expected_code, label])
	_expect(result.locations.is_empty() and result.recovery.is_empty() and result.occupied_cells.is_empty() and result.occupied_targets.is_empty(),
		"Rejected plan exposes no partial candidate: " + label)


func _test_96_single_cells() -> void:
	var metadata: Dictionary = {}
	var locations: Dictionary = {}
	for index: int in range(96):
		var uid: String = "cell_%03d" % index
		metadata[uid] = _item()
		locations[uid] = {"kind": "bag", "x": index % 12, "y": int(index / 12)}
	var result: Dictionary = Paged.plan(metadata, locations, _context())
	_expect(result.ok and result.locations.size() == 96, "Legacy 96-cell bag becomes a complete two-page map")
	_expect(result.recovery.is_empty() and result.occupied_cells.size() == 96, "All single-cell items occupy the full 96-cell capacity")
	_expect(result.locations.cell_000 == {"kind": "bag", "page": 0, "x": 0, "y": 0}, "First UID has the first page cell")
	_expect(result.locations.cell_047 == {"kind": "bag", "page": 0, "x": 7, "y": 5}, "48th UID ends page zero")
	_expect(result.locations.cell_048 == {"kind": "bag", "page": 1, "x": 0, "y": 0}, "49th UID begins page one")
	_expect(result.locations.cell_095 == {"kind": "bag", "page": 1, "x": 7, "y": 5}, "96th UID fills the final page cell")
	_expect(result.occupied_cells["bag:1:7:5"] == "cell_095", "Page-aware occupancy key includes page, x and y")
	_expect(result.recovery.is_empty(), "No capacity loss is hidden as recovery")


func _test_multicell_reflow() -> void:
	var metadata: Dictionary = {
		"edge_2x2": _item("jewel", [2, 2]),
		"edge_3x2": _item("jewel", [3, 2]),
	}
	var locations: Dictionary = {
		# Both source footprints touch the old 12x8 bottom/right edges.
		"edge_2x2": {"kind": "bag", "x": 10, "y": 6},
		"edge_3x2": {"kind": "bag", "x": 7, "y": 6},
	}
	var result: Dictionary = Paged.plan(metadata, locations, _context())
	_expect(result.ok and result.recovery.is_empty(), "Edge-touching legacy footprints are re-searched into pages")
	_expect(result.locations.edge_2x2 != locations.edge_2x2, "Old coordinates are reflowed rather than truncated")
	for uid: String in ["edge_2x2", "edge_3x2"]:
		var place: Dictionary = result.locations[uid]
		var size: Array = metadata[uid].size
		_expect(place.page >= 0 and place.page < 2 and place.x + size[0] <= 8 and place.y + size[1] <= 6,
			"Every multi-cell footprint remains wholly inside one 8x6 page: " + uid)
	_expect(result.occupied_cells.size() == 10, "Occupancy contains every cell from both multi-cell footprints")
	var straddling: Dictionary = Paged.check_placement("edge_probe", [2, 1],
		{"kind": "bag", "page": 0, "x": 7, "y": 0}, {})
	_expect(not straddling.ok and straddling.error_code == "page_boundary", "A multi-cell item cannot spill into the next page")


func _test_visible_recovery() -> void:
	var metadata: Dictionary = {"small": _item(), "wide_9": _item("jewel", [9, 1])}
	var locations: Dictionary = {
		"small": {"kind": "bag", "x": 9, "y": 0},
		"wide_9": {"kind": "bag", "x": 0, "y": 0},
	}
	var result: Dictionary = Paged.plan(metadata, locations, _context())
	_expect(result.ok and result.locations.size() == metadata.size(), "An unplaceable shape does not invalidate or truncate the plan")
	_expect(result.locations.wide_9 == {"kind": "recovery", "index": 0}, "A 9-cell legacy item is retained in a new visible recovery slot")
	_expect(result.recovery == [{"uid": "wide_9", "index": 0, "reason": "item_exceeds_page"}], "Recovery reports the specific single-page size reason")
	_expect(result.locations.small.kind == "bag" and result.occupied_cells.size() == 1, "Other items still receive real page cells")

	# Three 6x4 rectangles fit the legacy 12x8 rectangle (two across in its
	# first four rows, then one below), but each 8x6 page holds only one.
	var shaped_metadata: Dictionary = {
		"shape_a": _item("jewel", [6, 4]),
		"shape_b": _item("jewel", [6, 4]),
		"shape_c": _item("jewel", [6, 4]),
	}
	var shaped_locations: Dictionary = {
		"shape_a": {"kind": "bag", "x": 0, "y": 0},
		"shape_b": {"kind": "bag", "x": 6, "y": 0},
		"shape_c": {"kind": "bag", "x": 0, "y": 4},
	}
	var shaped: Dictionary = Paged.plan(shaped_metadata, shaped_locations, _context())
	_expect(shaped.ok and shaped.locations.size() == 3, "Legacy-valid rectangle packing may still need safe page recovery")
	_expect(shaped.recovery.size() == 1 and shaped.recovery[0].reason == "no_paged_space",
		"Different page shapes preserve an item in recovery even when total footprint is below 96")
	_expect(shaped.occupied_cells.size() == 48, "Only the two actually fitted 6x4 rectangles occupy page cells")


func _test_existing_recovery_indices() -> void:
	var metadata: Dictionary = {
		"old_pending": _item(),
		"new_pending": _item("jewel", [9, 1]),
	}
	var locations: Dictionary = {
		"old_pending": {"kind": "recovery", "index": 0},
		"new_pending": {"kind": "bag", "x": 0, "y": 0},
	}
	var result: Dictionary = Paged.plan(metadata, locations, _context())
	_expect(result.ok, "Existing visible recovery state is accepted")
	_expect(result.locations.old_pending == locations.old_pending, "Existing recovery location and index stay unchanged")
	_expect(result.locations.new_pending == {"kind": "recovery", "index": 1}, "New overflow skips an occupied recovery index")
	_expect(result.recovery == [
		{"uid": "old_pending", "index": 0, "reason": "preserved_existing_recovery"},
		{"uid": "new_pending", "index": 1, "reason": "item_exceeds_page"},
	], "Full recovery audit is ordered by unique index")

	var conflicting_metadata: Dictionary = {"old_a": _item(), "old_b": _item()}
	var conflicting_locations: Dictionary = {
		"old_a": {"kind": "recovery", "index": 0},
		"old_b": {"kind": "recovery", "index": 0},
	}
	var rejected: Dictionary = Paged.plan(conflicting_metadata, conflicting_locations, _context())
	_failure_is_empty(rejected, "duplicate_target", "conflicting source recovery indices")


func _test_preservation_and_determinism() -> void:
	var metadata: Dictionary = {
		"boots_uid": _item("equipment", [2, 2], "boots"),
		"socket_uid": _item("jewel"),
		"main_uid": _item("skill_gem"),
		"support_uid": _item("support_gem"),
		"pending_uid": _item("jewel"),
		"bag_uid": _item("jewel", [2, 1]),
	}
	var locations: Dictionary = {
		"boots_uid": {"kind": "equipment", "slot_id": "boots"},
		"socket_uid": {"kind": "passive_socket", "node_id": "node_10"},
		"main_uid": {"kind": "skill_main", "group_id": "row_a"},
		"support_uid": {"kind": "skill_support", "group_id": "row_a", "index": 2},
		"pending_uid": {"kind": "recovery", "index": 4},
		"bag_uid": {"kind": "bag", "x": 10, "y": 7},
	}
	var metadata_bytes: PackedByteArray = var_to_bytes(metadata)
	var locations_bytes: PackedByteArray = var_to_bytes(locations)
	var first: Dictionary = Paged.plan(metadata, locations, _context())
	var reverse_metadata: Dictionary = {}
	var reverse_locations: Dictionary = {}
	var keys: Array = metadata.keys()
	keys.reverse()
	for uid: String in keys:
		reverse_metadata[uid] = metadata[uid].duplicate(true)
		reverse_locations[uid] = locations[uid].duplicate(true)
	var second: Dictionary = Paged.plan(reverse_metadata, reverse_locations, _context())
	_expect(first.ok and second.ok and first.locations == second.locations, "Dictionary insertion order does not affect the plan")
	_expect(var_to_bytes(first.locations) == var_to_bytes(second.locations), "Location output key order is canonical for byte-stable planning")
	_expect(first.recovery == second.recovery and first.occupied_cells == second.occupied_cells, "Recovery and occupancy are deterministic too")
	for uid: String in ["boots_uid", "socket_uid", "main_uid", "support_uid", "pending_uid"]:
		_expect(first.locations[uid] == locations[uid], "Non-bag location stays byte-for-byte equivalent: " + uid)
	_expect(first.locations.keys().size() == metadata.keys().size(), "Every original UID still has exactly one location")
	_expect(first.locations.has_all(metadata.keys()), "No item UID is lost or replaced")
	_expect(var_to_bytes(metadata) == metadata_bytes and var_to_bytes(locations) == locations_bytes, "Planner does not mutate source metadata or locations")


func _test_full_pages_and_placement_api() -> void:
	var occupied: Dictionary = {}
	for page: int in range(2):
		for y: int in range(6):
			for x: int in range(8):
				occupied["bag:%d:%d:%d" % [page, x, y]] = "block_%03d" % occupied.size()
	var full_before: PackedByteArray = var_to_bytes(occupied)
	var found: Dictionary = Paged.find_space([1, 1], occupied)
	_expect(not found.ok and found.error_code == "no_space" and found.location.is_empty(), "Search explicitly rejects the full two-page 96-cell bag")
	_expect(var_to_bytes(occupied) == full_before, "Failed search leaves existing occupancy unchanged")
	var placed: Dictionary = Paged.check_placement("extra", [1, 1], {"kind": "bag", "page": 0, "x": 0, "y": 0}, occupied)
	_expect(not placed.ok and placed.error_code == "bag_overlap", "Occupancy check rejects a colliding placement")
	_expect(var_to_bytes(occupied) == full_before, "Failed occupancy check does not mutate its input")
	var open: Dictionary = Paged.find_space([2, 1], {})
	var reserved: Dictionary = Paged.check_placement("new_drop", [2, 1], open.location, open.occupied_cells)
	_expect(open.ok and reserved.ok and reserved.occupied_cells.size() == 2, "Find then check can reserve a new drop without state side effects")


func _test_strict_schema() -> void:
	for size: Variant in [[true, 1], [1, 1.0], [0, 1], [13, 1], [1, 9], [1]]:
		var found: Dictionary = Paged.find_space(size, {})
		_expect(not found.ok and found.error_code == "invalid_size", "Reject invalid/boolean/float/oversize dimensions: " + str(size))
	var too_wide: Dictionary = Paged.find_space([9, 1], {})
	_expect(not too_wide.ok and too_wide.error_code == "item_exceeds_page", "Legacy-valid but page-too-wide item has a distinct reason")
	for invalid_location: Dictionary in [
		{"kind": "bag", "page": 0.0, "x": 0, "y": 0},
		{"kind": "bag", "page": 0, "x": true, "y": 0},
		{"kind": "bag", "page": 1, "x": 0, "y": false},
		{"kind": "bag", "page": 0, "x": 0, "y": 0, "extra": 1},
	]:
		var checked: Dictionary = Paged.check_placement("strict", [1, 1], invalid_location, {})
		_expect(not checked.ok and checked.error_code == "invalid_location", "Reject non-int or unknown paged location fields: " + str(invalid_location))
	var bad_meta: Dictionary = {"strict": _item()}
	bad_meta.strict.extra = "unknown"
	var bad_locations: Dictionary = {"strict": {"kind": "bag", "x": 0, "y": 0}}
	var bad_plan: Dictionary = Paged.plan(bad_meta, bad_locations, _context())
	_failure_is_empty(bad_plan, "invalid_metadata", "unknown metadata field")
	var bool_legacy: Dictionary = {"strict": {"kind": "bag", "x": true, "y": 0}}
	var bad_old_coord: Dictionary = Paged.plan({"strict": _item()}, bool_legacy, _context())
	_failure_is_empty(bad_old_coord, "invalid_location", "boolean legacy coordinate")
	var paged_extra: Dictionary = {"strict": {"kind": "bag", "page": 0, "x": 0, "y": 0, "old_x": 3}}
	var inspect_extra: Dictionary = Paged.inspect_layout({"strict": _item()}, paged_extra, _context())
	_failure_is_empty(inspect_extra, "invalid_location", "unknown paged location field")


func _test_inspect_and_arrange() -> void:
	var metadata: Dictionary = {"large": _item("jewel", [3, 2]), "small": _item()}
	var legacy_locations: Dictionary = {
		"large": {"kind": "bag", "x": 8, "y": 5},
		"small": {"kind": "bag", "x": 0, "y": 0},
	}
	var planned: Dictionary = Paged.plan(metadata, legacy_locations, _context())
	_expect(planned.ok, "Initial page plan succeeds")
	var input_copy: Dictionary = planned.locations.duplicate(true)
	var inspected: Dictionary = Paged.inspect_layout(metadata, planned.locations, _context())
	var arranged: Dictionary = Paged.arrange(metadata, planned.locations, _context())
	var arranged_again: Dictionary = Paged.arrange(metadata, planned.locations, _context())
	_expect(inspected.ok and inspected.occupied_cells == planned.occupied_cells, "Inspection reports exact page occupancy")
	_expect(arranged.ok and arranged.locations == arranged_again.locations, "Arrangement is deterministic for page-aware input")
	_expect(var_to_bytes(planned.locations) == var_to_bytes(input_copy), "Inspect and arrange leave their source locations untouched")
	_expect(arranged.locations.large == planned.locations.large and arranged.locations.small == planned.locations.small,
		"Stable packing order makes a second arrangement idempotent")
