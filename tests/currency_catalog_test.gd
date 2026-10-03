extends SceneTree

const Currency = preload("res://scripts/items/currency_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Layout = preload("res://scripts/items/item_location_rules.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	var item: Dictionary = Items.calibration_shard("currency_test_000001", 37)
	check(item == {"uid": "currency_test_000001", "kind": "currency",
		"definition_id": "currency:calibration_shard", "payload": {"quantity": 37}}, "canonical currency envelope")
	check(Items.validate_instance(item) and Currency.validate_instance(item), "catalog accepts the exact currency instance")
	check(Items.metadata_for_instance(item) == {"kind": "currency", "category": "", "size": [1, 1]}, "currency footprint is one cell")
	var definition: Dictionary = Items.definition_for_instance(item)
	check(definition.quantity == 37 and definition.stack_limit == 1000000000
		and definition.name == "校准碎片" and definition.color is Color, "definition exposes quantity, stack limit and presentation")
	var decoded: Dictionary = Items.decode_instance(JSON.parse_string(JSON.stringify(item)))
	check(decoded == item, "currency JSON round trip")
	var bad: Dictionary
	for invalid: Variant in [true, false, 0, -1, 1.5, "37", null, 1000000001]:
		check(Items.calibration_shard("bad", invalid).is_empty(), "factory rejects malformed quantity: " + str(invalid))
		bad = item.duplicate(true)
		bad.payload.quantity = invalid
		check(not Items.validate_instance(bad) and Items.decode_instance(bad).is_empty(), "validator and decoder reject quantity: " + str(invalid))
	bad = item.duplicate(true)
	bad.payload.quantity = 1.0
	check(not Items.validate_instance(bad) and Items.decode_instance(bad).payload.quantity == 1,
		"JSON integer quantity is explicitly normalized after parsing")
	bad = item.duplicate(true)
	bad.payload.extra = 1
	check(not Items.validate_instance(bad), "unknown payload field rejected")
	bad = item.duplicate(true)
	bad.definition_id = "currency:unknown"
	check(not Items.validate_instance(bad), "unknown currency definition rejected")
	bad = item.duplicate(true)
	bad.kind = "material"
	check(not Items.validate_instance(bad), "unknown item kind rejected")
	var maximum: Dictionary = Items.calibration_shard("currency_max", Currency.STACK_LIMIT)
	check(Items.validate_instance(maximum), "legacy maximum stack is accepted")
	var summary: Dictionary = Currency.total_quantity({"currency_test_000001": item, "two": Items.calibration_shard("two", 63)})
	check(summary.ok and summary.quantity == 100, "multiple UIDs contribute to one inventory total")
	summary = Currency.total_quantity({"currency_max": maximum, "two": Items.calibration_shard("two", 1)})
	check(not summary.ok and summary.error_code == "currency_inventory_limit", "total inventory cap applies across stacks")
	var metadata := {"currency_test_000001": Items.metadata_for_instance(item)}
	var context := {"columns": 12, "rows": 10, "pages":2,
		"equipment_slots": {"weapon": "weapon", "body_armour": "body_armour", "amulet": "amulet",
			"ring_1": "ring", "ring_2": "ring", "boots": "boots", "belt": "belt", "gloves": "gloves", "helmet": "helmet"},
		"skill_group_ids": [], "passive_socket_ids": [], "allow_recovery": true}
	check(Layout.validate_current(metadata, {"currency_test_000001": {"kind": "bag", "page":0,"x": 0, "y": 0}}, context).ok,
		"currency can be placed in bag")
	check(Layout.validate_current(metadata, {"currency_test_000001": {"kind": "recovery", "index": 0}}, context).ok,
		"currency can be visibly pending in recovery")
	check(not Layout.validate_current(metadata, {"currency_test_000001": {"kind": "equipment", "slot_id": "weapon"}}, context).ok,
		"currency cannot occupy equipment")
	check(not Layout.validate_current(metadata, {"currency_test_000001": {"kind": "skill_main", "group_id": "row"}}, context).ok,
		"currency cannot occupy a skill slot")
	print("Currency catalog: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
