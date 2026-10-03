extends SceneTree

const Layout = preload("res://scripts/items/item_location_rules.gd")
const Transfer = preload("res://scripts/items/item_transfer_plan.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Legacy = preload("res://scripts/build_state.gd")
const LegacyMigration = preload("res://scripts/save/canonical_build_migration.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(Rules.VERSION == 15 and Rules.V14_VERSION == 14, "current schema advances while v14 remains explicit")
	var v14_candidate := LegacyMigration.migrate(Legacy.new()._snapshot())
	var v14_decoded := Rules.decode_v14(v14_candidate)
	_expect(not v14_decoded.is_empty() and Rules.reason_v14(v14_decoded).is_empty(),
		"legacy conversion output passes the complete original v14 decoder and validator")
	var v14_with_unknown_page := v14_candidate.duplicate(true)
	for uid: String in v14_with_unknown_page.locations:
		if v14_with_unknown_page.locations[uid].kind == "bag":
			v14_with_unknown_page.locations[uid].page = 0
			break
	_expect(Rules.decode_v14(v14_with_unknown_page).is_empty(), "v14 decoder rejects new or unknown location fields")

	var legacy_context := _context(false)
	legacy_context.erase("pages")
	legacy_context.columns = 12
	legacy_context.rows = 8
	var legacy_metadata := {"old": _meta("jewel")}
	var legacy_locations := {"old": {"kind": "bag", "x": 11, "y": 7}}
	_expect(Layout.validate(legacy_metadata, legacy_locations, legacy_context).ok,
		"legacy validator still accepts the original 12×8 coordinate shape")
	_expect(not Layout.validate_paged(legacy_metadata, legacy_locations, _context(false)).ok,
		"paged validator does not silently reinterpret a v14 bag location")
	_expect(Items.decode_location({"kind": "bag", "x": 0, "y": 0}) == {"kind": "bag", "x": 0, "y": 0},
		"legacy location decoder remains page-free")
	var whole_float_page := Items.decode_paged_location({"kind": "bag", "page": 1.0, "x": 7.0, "y": 5.0})
	_expect(whole_float_page == {"kind": "bag", "page": 1, "x": 7, "y": 5},
		"paged decoder recovers explicitly integral JSON numbers as integers")
	for invalid_page: Variant in [true, 0.5, 2, -1]:
		_expect(Items.decode_paged_location({"kind": "bag", "page": invalid_page, "x": 0, "y": 0}).is_empty(),
			"paged decoder rejects invalid page: " + str(invalid_page))
	_expect(Items.decode_paged_location({"kind": "bag", "x": 0, "y": 0}).is_empty(),
		"paged decoder requires explicit page")

	var metadata := {"page_zero": _meta("jewel"), "page_one": _meta("jewel"),
		"large": _meta("equipment", [2, 3], "body_armour")}
	var locations := {"page_zero": {"kind": "bag", "page": 0, "x": 0, "y": 0},
		"page_one": {"kind": "bag", "page": 1, "x": 0, "y": 0},
		"large": {"kind": "bag", "page": 1, "x": 6, "y": 3}}
	var valid := Layout.validate_paged(metadata, locations, _context(false))
	_expect(valid.ok and valid.occupied_cells["bag:0:0:0"] == "page_zero"
		and valid.occupied_cells["bag:1:0:0"] == "page_one",
		"same coordinates are independent across pages and occupancy keys include page")
	var same_page := locations.duplicate(true)
	same_page.page_one.page = 0
	_expect(Layout.validate_paged(metadata, same_page, _context(false)).error_code == "bag_overlap",
		"same-page overlap is rejected")
	var out_of_bounds := locations.duplicate(true)
	out_of_bounds.large.x = 7
	_expect(Layout.validate_paged(metadata, out_of_bounds, _context(false)).error_code == "out_of_bounds",
		"a 2×3 item cannot cross the right edge of an 8×6 page")
	for invalid_page: Variant in [true, 1.5, 2, -1]:
		var malformed := locations.duplicate(true)
		malformed.page_one.page = invalid_page
		_expect(Layout.validate_paged(metadata, malformed, _context(false)).error_code == "invalid_location",
			"invalid page value rejected: " + str(invalid_page))
	var extra_context := _context(false)
	extra_context.pages = 3
	_expect(Layout.validate_paged(metadata, locations, extra_context).error_code == "invalid_context",
		"page count is a strict two-page contract")

	var swap_metadata := {"ring_a": _meta("equipment", [1, 1], "ring"),
		"ring_b": _meta("equipment", [1, 1], "ring"), "gem": _meta("support_gem")}
	var swap_locations := {"ring_a": {"kind": "equipment", "slot_id": "ring_1"},
		"ring_b": {"kind": "equipment", "slot_id": "ring_2"},
		"gem": {"kind": "bag", "page": 0, "x": 0, "y": 0}}
	var original := var_to_bytes([swap_metadata, swap_locations])
	var swapped := Transfer.move_paged(swap_metadata, swap_locations, _context(false), "ring_a",
		{"kind": "equipment", "slot_id": "ring_2"}, 5, 5)
	_expect(swapped.ok and swapped.locations.ring_a.slot_id == "ring_2"
		and swapped.locations.ring_b.slot_id == "ring_1", "paged transfer retains atomic equipment swaps")
	_expect(var_to_bytes([swap_metadata, swap_locations]) == original, "paged transfer leaves input detached")
	var moved := Transfer.move_paged(swap_metadata, swap_locations, _context(false), "gem",
		{"kind": "bag", "page": 1, "x": 0, "y": 0}, 5, 5)
	_expect(moved.ok and moved.locations.gem.page == 1, "transfer accepts a complete destination on the second page")
	_expect(Transfer.first_bag_space_paged(swap_metadata, swap_locations, null, "gem").is_empty(),
		"first-space query safely rejects a null context")
	_expect(Transfer.first_bag_space_paged(swap_metadata, swap_locations, {}, "gem").is_empty(),
		"first-space query safely rejects an empty context")
	var wrong_dimensions := _context(false)
	wrong_dimensions.columns = 12
	_expect(Transfer.first_bag_space_paged(swap_metadata, swap_locations, wrong_dimensions, "gem").is_empty(),
		"first-space query safely rejects a context with legacy dimensions")
	_expect(Transfer.first_bag_space_paged({}, swap_locations, _context(false), "gem").is_empty(),
		"first-space query safely rejects missing moving metadata")
	var invalid_moving_metadata := swap_metadata.duplicate(true)
	invalid_moving_metadata.gem.kind = "unsupported"
	_expect(Transfer.first_bag_space_paged(invalid_moving_metadata, swap_locations, _context(false), "gem").is_empty(),
		"first-space query safely rejects invalid moving metadata")
	var missing_page := Transfer.move_paged(swap_metadata, swap_locations, _context(false), "gem",
		{"kind": "bag", "x": 0, "y": 1}, 5, 5)
	_expect(not missing_page.ok and missing_page.error_code == "invalid_destination",
		"user bag destinations must supply an explicit page")
	var linked_metadata := {"main": _meta("skill_gem"), "support": _meta("support_gem")}
	var linked_locations := {"main": {"kind": "bag", "page": 1, "x": 0, "y": 0},
		"support": {"kind": "bag", "page": 1, "x": 1, "y": 0}}
	var main_link := Transfer.move_paged(linked_metadata, linked_locations, _context(false), "main",
		{"kind": "skill_main", "group_id": "group_1"}, 7, 7)
	var support_link := Transfer.move_paged(linked_metadata, main_link.locations, _context(false), "support",
		{"kind": "skill_support", "group_id": "group_1", "index": 4}, 8, 8) if main_link.ok else {}
	_expect(main_link.ok and support_link.get("ok", false)
		and support_link.locations.main.group_id == "group_1"
		and support_link.locations.support.index == 4,
		"active and support gems can move from page two into canonical skill targets")
	var arrange_places := swap_locations.duplicate(true)
	arrange_places.gem.page = 1
	var arranged := Transfer.arrange_paged(swap_metadata, arrange_places, _context(false), 5, 5)
	_expect(arranged.ok and Layout.validate_paged(swap_metadata, arranged.locations, _context(false)).ok
		and arranged.locations.ring_a == arrange_places.ring_a and arranged.locations.gem.page == 0,
		"arrangement validates both pages and preserves non-bag targets")
	print("Paged bag transfer: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _meta(kind: String, size: Array = [1, 1], category: String = "") -> Dictionary:
	return {"kind": kind, "category": category, "size": size.duplicate()}


func _context(allow_recovery: bool) -> Dictionary:
	var equipment: Dictionary = {}
	for slot: String in Slots.all_slots():
		equipment[slot] = Slots.category_for_slot(slot)
	return {"columns": 8, "rows": 6, "pages": 2, "equipment_slots": equipment,
		"skill_group_ids": ["group_1", "group_2"], "passive_socket_ids": ["socket_1"],
		"allow_recovery": allow_recovery}


func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
