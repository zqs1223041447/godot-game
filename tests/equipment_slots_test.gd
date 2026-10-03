extends SceneTree
## Pure nine-target equipment directory contract; no inventory or equip operations.
const Slots = preload("res://scripts/items/equipment_slots.gd")

const EXPECTED_SLOTS: Array[String] = [
	"weapon", "body_armour", "amulet", "ring_1", "ring_2",
	"boots", "belt", "gloves", "helmet",
]
const EXPECTED_CATEGORIES: Dictionary = {
	"weapon": "weapon",
	"body_armour": "body_armour",
	"amulet": "amulet",
	"ring_1": "ring",
	"ring_2": "ring",
	"boots": "boots",
	"belt": "belt",
	"gloves": "gloves",
	"helmet": "helmet",
}
const EXPECTED_TARGETS: Dictionary = {
	"weapon": ["weapon"],
	"body_armour": ["body_armour"],
	"amulet": ["amulet"],
	"ring": ["ring_1", "ring_2"],
	"boots": ["boots"],
	"belt": ["belt"],
	"gloves": ["gloves"],
	"helmet": ["helmet"],
}

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_slots_and_categories()
	_check_category_targets()
	_check_target_reasons()
	_check_legacy_boundary()
	_check_returned_copies()
	print("Equipment slots: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _check_slots_and_categories() -> void:
	_expect(Slots.all_slots() == EXPECTED_SLOTS, "Exactly nine target IDs in canonical order")
	for slot: String in EXPECTED_SLOTS:
		_expect(Slots.category_for_slot(slot) == EXPECTED_CATEGORIES[slot], "Exact category for " + slot)
	for invalid: Variant in ["", "armor", "charm", "ring", "head", null, true, 1, {}, [], StringName("weapon")]:
		_expect(Slots.category_for_slot(invalid) == "", "Unknown or non-string slot is refused")


func _check_category_targets() -> void:
	for category: String in EXPECTED_TARGETS:
		_expect(Slots.targets_for_category(category) == EXPECTED_TARGETS[category], "Exact targets for " + category)
	_expect(Slots.targets_for_category("ring") == ["ring_1", "ring_2"], "Ring category exposes both independent targets")
	for invalid: Variant in ["", "armor", "charm", "ring_1", "unknown", null, true, 1, {}, [], StringName("ring")]:
		_expect(Slots.targets_for_category(invalid).is_empty(), "Unknown or non-string category is refused")


func _check_target_reasons() -> void:
	for slot: String in EXPECTED_SLOTS:
		_expect(Slots.target_reason(EXPECTED_CATEGORIES[slot], slot) == "", "Valid target has empty reason: " + slot)
	_expect(Slots.target_reason("ring", "ring_1") == "" and Slots.target_reason("ring", "ring_2") == "", "Both ring targets are accepted")
	_expect(Slots.target_reason("missing", "weapon") == Slots.ERROR_UNKNOWN_CATEGORY and Slots.ERROR_UNKNOWN_CATEGORY == "unknown_category", "Unknown category has stable error code")
	_expect(Slots.target_reason("weapon", "missing") == Slots.ERROR_UNKNOWN_SLOT and Slots.ERROR_UNKNOWN_SLOT == "unknown_slot", "Unknown target has stable error code")
	_expect(Slots.target_reason("body_armour", "weapon") == Slots.ERROR_CATEGORY_MISMATCH and Slots.ERROR_CATEGORY_MISMATCH == "category_mismatch", "Known but mismatched target has stable error code")
	_expect(Slots.target_reason(null, "weapon") == "unknown_category", "Non-string category is safely rejected")
	_expect(Slots.target_reason("weapon", null) == "unknown_slot", "Non-string target is safely rejected")
	_expect(Slots.target_reason("missing", null) == "unknown_category", "Category validation has stable precedence")
	_expect(Slots.target_reason("body_armour", "armor") == "unknown_slot", "Target checks do not silently apply legacy aliases")


func _check_legacy_boundary() -> void:
	_expect(Slots.legacy_slot("armor") == "body_armour", "Legacy armor maps to body_armour")
	_expect(Slots.legacy_slot("charm") == "amulet", "Legacy charm maps to amulet")
	for slot: String in EXPECTED_SLOTS:
		_expect(Slots.legacy_slot(slot) == slot, "Canonical target passes through migration: " + slot)
	for invalid: Variant in ["ring", "armour", "head", "unknown", "", null, true, 1, {}, []]:
		_expect(Slots.legacy_slot(invalid) == "", "No unlisted legacy mapping is accepted")
	_expect(Slots.category_for_slot("armor") == "" and Slots.category_for_slot("charm") == "", "Legacy names are not canonical slot queries")


func _check_returned_copies() -> void:
	var slots: Array[String] = Slots.all_slots()
	slots[0] = "helmet"
	slots.append("fake_slot")
	_expect(Slots.all_slots() == EXPECTED_SLOTS, "Mutating all_slots result cannot alter the directory")
	var rings: Array[String] = Slots.targets_for_category("ring")
	rings[0] = "amulet"
	rings.clear()
	_expect(Slots.targets_for_category("ring") == ["ring_1", "ring_2"], "Mutating ring targets cannot alter the directory")
	var armour: Array[String] = Slots.targets_for_category("body_armour")
	armour.append("weapon")
	_expect(Slots.targets_for_category("body_armour") == ["body_armour"], "Every category target result is detached")
