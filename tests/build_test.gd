extends SceneTree
## Deterministic, isolated model tests; never read or modify the player's real save.

const Model = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
const TEST_SAVE: String = "user://build_model_test.json"
const BAD_SAVE: String = "user://build_model_invalid_test.json"

var failures: int = 0
var checks: int = 0
var change_count: int = 0


func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	_remove_test_files()
	_check_catalogs()
	_check_equipment()
	_check_talents()
	_check_skills()
	_check_progression()
	_check_persistence()
	_remove_test_files()
	print("Build model: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_catalogs() -> void:
	_expect(Data.SKILLS.size() == 7, "Seven available skills")
	_expect(Data.ITEMS.size() == 6, "Six initial equipment items")
	_expect(Data.TALENTS.size() >= 4, "Talent catalog populated")
	for skill_id: String in Data.SKILLS:
		var skill: Dictionary = Data.SKILLS[skill_id]
		_expect(skill.has_all(["name", "short_name", "description", "mana", "cooldown", "color", "icon"]), "Complete skill: " + skill_id)
		_expect(float(skill["mana"]) >= 0.0 and float(skill["cooldown"]) > 0.0, "Valid skill costs: " + skill_id)
	for item_id: String in Data.ITEMS:
		_expect(Model.EQUIPMENT_SLOTS.has(Data.ITEMS[item_id]["slot"]), "Known item slot: " + item_id)
		for stat: String in Data.ITEMS[item_id]["stats"]:
			_expect(Model.BASE_STATS.has(stat), "Known item stat: " + stat)
	for talent_id: String in Data.TALENTS:
		for stat: String in Data.TALENTS[talent_id]["stats"]:
			_expect(Model.BASE_STATS.has(stat), "Known talent stat: " + stat)


func _check_equipment() -> void:
	var build := Model.new()
	build.changed.connect(_on_changed)
	change_count = 0
	_expect(build.inventory.size() == 6, "Inventory starts with all six items")
	_expect(build.equipped.size() == 3, "One equipped item in each slot")
	_expect(is_equal_approx(build.get_stats()["damage"], 26.0), "Default weapon adds damage")
	_expect(is_equal_approx(build.get_stats()["max_mana"], 130.0), "Default charm adds mana")
	_expect(not build.equip("unknown") and not build.unequip("hat"), "Invalid equipment IDs rejected")
	_expect(not build.equip("ember_wand"), "Equipping the same item is a no-op")
	_expect(change_count == 0, "No signal for invalid or unchanged equipment")
	_expect(build.equip("swift_blade"), "Equip replacement weapon")
	_expect(build.equipped["weapon"] == "swift_blade", "Replacement occupies correct slot")
	_expect(build.inventory.has("ember_wand") and build.inventory.has("swift_blade"), "Equipping preserves inventory")
	_expect(is_equal_approx(build.get_stats()["damage"], 18.0), "Replaced weapon stats removed")
	_expect(is_equal_approx(build.get_stats()["attack_speed"], 2.2), "Replacement attack speed applied")
	_expect(change_count == 1, "Equipment change emits once")
	for slot: String in Model.EQUIPMENT_SLOTS:
		_expect(build.unequip(slot), "Unequip " + slot)
	_expect(not build.unequip("weapon"), "Empty equipment slot is a no-op")
	_expect(build.get_stats() == Model.BASE_STATS, "Unequipped stats equal base stats")
	build.inventory.erase("ember_wand")
	_expect(not build.equip("ember_wand"), "Cannot equip an item outside inventory")
	var independent := Model.new()
	_expect(independent.inventory.size() == 6 and independent.equipped.size() == 3, "Build instances do not share mutable collections")
	var detached: Dictionary = independent.get_stats()
	detached["damage"] = 999.0
	_expect(is_equal_approx(independent.get_stats()["damage"], 26.0), "Returned stats do not mutate base stats")


func _check_talents() -> void:
	var build := Model.new()
	_expect(not build.allocate_talent("unknown"), "Unknown talent rejected")
	for rank: int in range(5):
		_expect(build.allocate_talent("power"), "Allocate power rank %d" % (rank + 1))
	_expect(build.talent_points == 0 and build.talents["power"] == 5, "Talent points spent exactly")
	_expect(is_equal_approx(build.get_stats()["damage"], 46.0), "Talent stats accumulate per rank")
	_expect(not build.allocate_talent("vitality"), "Cannot allocate with zero points")
	_expect(build.add_xp(build.xp_required()), "Gain talent point through level-up")
	_expect(not build.allocate_talent("power"), "Max rank enforced with points available")
	_expect(build.allocate_talent("focus"), "Different talent accepts point")
	_expect(is_equal_approx(build.get_stats()["max_mana"], 142.0), "Multi-stat talent maximum applied")
	_expect(is_equal_approx(build.get_stats()["mana_regen"], 13.0), "Multi-stat talent regeneration applied")
	build.refund_talents()
	_expect(build.talent_points == 6, "Refund restores all invested points")
	_expect(build.talents["power"] == 0 and build.talents["focus"] == 0, "Refund clears ranks")
	_expect(is_equal_approx(build.get_stats()["damage"], 26.0), "Refund removes talent stats")
	build.refund_talents()
	_expect(build.talent_points == 6, "Repeated refund cannot duplicate points")


func _check_skills() -> void:
	var build := Model.new()
	_expect(build.skill_slots == ["bolt", "frost", "nova", "dash", "ward"], "Initial five skill slots")
	_expect(not build.slot_skill(-1, "meteor") and not build.slot_skill(5, "meteor"), "Out-of-range skill indices rejected")
	_expect(not build.slot_skill(0, "unknown"), "Unknown skill rejected")
	_expect(not build.slot_skill(0, "bolt"), "Same skill placement is a no-op")
	_expect(build.slot_skill(0, "ward"), "Existing skill can move")
	_expect(build.skill_slots[0] == "ward" and build.skill_slots[4] == "bolt", "Existing skills swap without duplicates")
	_expect(build.slot_skill(2, "meteor"), "Unequipped skill replaces a slot")
	_expect(build.skill_slots[2] == "meteor" and not build.skill_slots.has("nova"), "Replacement skill set is correct")
	_expect(build.slot_skill(2, "chain"), "Second spare skill is available")


func _check_progression() -> void:
	var build := Model.new()
	_expect(build.level == 1 and build.xp == 0 and build.xp_required() == 20, "Initial level threshold")
	_expect(not build.add_xp(-1) and not build.add_xp(0), "Non-positive XP rejected")
	_expect(not build.add_xp(19) and build.xp == 19, "Partial XP does not report level-up")
	_expect(build.add_xp(1) and build.level == 2 and build.xp == 0, "Exact threshold levels once")
	_expect(build.talent_points == 6 and build.xp_required() == 28, "Level-up grants point and raises threshold")
	_expect(build.add_xp(28 + 36 + 7), "Large XP award levels repeatedly")
	_expect(build.level == 4 and build.xp == 7 and build.talent_points == 8, "XP overflow preserved across levels")
	var capped := Model.new()
	_expect(capped.add_xp(1000000000), "Large award safely reaches cap")
	_expect(capped.level == Model.MAX_LEVEL and capped.xp == 0, "Level and XP are bounded at cap")
	_expect(not capped.add_xp(1), "Capped progression does not add extra talent points")


func _check_persistence() -> void:
	var build := Model.new()
	build.equip("swift_blade")
	build.unequip("armor")
	build.slot_skill(4, "meteor")
	build.add_xp(57)
	build.allocate_talent("focus")
	build.allocate_talent("aegis")
	_expect(build.save_build(TEST_SAVE) == OK, "Save valid build")
	build.allocate_talent("haste")
	_expect(build.save_build(TEST_SAVE) == OK, "Atomically replace existing save")
	var loaded := Model.new()
	loaded.changed.connect(_on_changed)
	change_count = 0
	_expect(loaded.load_build(TEST_SAVE), "Load saved build")
	_expect(_snapshot(loaded) == _snapshot(build), "Save round-trip preserves all configuration")
	_expect(loaded.get_stats() == build.get_stats(), "Save round-trip preserves calculated stats")
	_expect(change_count == 1, "Successful load emits one change")
	_expect(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "No temporary file remains after save")
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	var candidate: Dictionary = valid.duplicate(true)
	candidate["inventory"][0] = "unknown_item"
	_expect_invalid(loaded, candidate, "Unknown inventory item")
	candidate = valid.duplicate(true)
	candidate["inventory"][1] = candidate["inventory"][0]
	_expect_invalid(loaded, candidate, "Duplicate inventory item")
	candidate = valid.duplicate(true)
	candidate["inventory"] = "not an array"
	_expect_invalid(loaded, candidate, "Inventory wrong type")
	candidate = valid.duplicate(true)
	candidate["equipped"]["weapon"] = "azure_charm"
	_expect_invalid(loaded, candidate, "Wrong equipment slot")
	candidate = valid.duplicate(true)
	candidate["inventory"].erase(candidate["equipped"]["weapon"])
	_expect_invalid(loaded, candidate, "Equipped item absent from inventory")
	candidate = valid.duplicate(true)
	candidate["equipped"]["head"] = "azure_charm"
	_expect_invalid(loaded, candidate, "Unknown equipment slot")
	candidate = valid.duplicate(true)
	candidate["skill_slots"][0] = "unknown_skill"
	_expect_invalid(loaded, candidate, "Unknown slotted skill")
	candidate = valid.duplicate(true)
	candidate["skill_slots"][0] = candidate["skill_slots"][1]
	_expect_invalid(loaded, candidate, "Duplicate slotted skill")
	candidate = valid.duplicate(true)
	candidate["skill_slots"].pop_back()
	_expect_invalid(loaded, candidate, "Wrong number of skill slots")
	candidate = valid.duplicate(true)
	candidate["talents"]["unknown_talent"] = 0
	_expect_invalid(loaded, candidate, "Unknown talent")
	candidate = valid.duplicate(true)
	candidate["talents"]["power"] = 6
	_expect_invalid(loaded, candidate, "Talent exceeds maximum")
	candidate = valid.duplicate(true)
	candidate["talents"]["power"] = -1
	_expect_invalid(loaded, candidate, "Negative talent rank")
	candidate = valid.duplicate(true)
	candidate["talents"]["focus"] = 1.5
	_expect_invalid(loaded, candidate, "Fractional talent rank")
	candidate = valid.duplicate(true)
	candidate["talent_points"] += 1
	_expect_invalid(loaded, candidate, "Inconsistent talent point budget")
	for invalid_level: Variant in [0, -1, Model.MAX_LEVEL + 1, 2.5, "2", true]:
		candidate = valid.duplicate(true)
		candidate["level"] = invalid_level
		_expect_invalid(loaded, candidate, "Invalid level " + str(invalid_level))
	for invalid_xp: Variant in [-1, loaded.xp_required(), 2.5, "2"]:
		candidate = valid.duplicate(true)
		candidate["xp"] = invalid_xp
		_expect_invalid(loaded, candidate, "Invalid XP " + str(invalid_xp))
	candidate = valid.duplicate(true)
	candidate["version"] = 999
	_expect_invalid(loaded, candidate, "Unsupported save version")
	candidate = valid.duplicate(true)
	candidate.erase("equipped")
	_expect_invalid(loaded, candidate, "Missing required field")
	_expect_invalid(loaded, [], "Top-level array")
	_expect_invalid(loaded, null, "Top-level null")
	var before: Dictionary = _snapshot(loaded)
	_write_bad_file("{invalid json")
	_expect(not loaded.load_build(BAD_SAVE), "Malformed JSON rejected")
	_write_bad_file(" ".repeat(Model.MAX_SAVE_BYTES + 1))
	_expect(not loaded.load_build(BAD_SAVE), "Oversized save rejected")
	DirAccess.remove_absolute(BAD_SAVE)
	_expect(not loaded.load_build(BAD_SAVE), "Missing save returns false")
	_expect(_snapshot(loaded) == before, "Failed reads never partially mutate current build")
	loaded.talent_points = -1
	_expect(loaded.save_build(TEST_SAVE) == ERR_INVALID_DATA, "Invalid in-memory build cannot overwrite save")
	var last_good := Model.new()
	_expect(last_good.load_build(TEST_SAVE) and _snapshot(last_good) == _snapshot(build), "Last valid save survives rejected write")


func _expect_invalid(build: Model, candidate: Variant, description: String) -> void:
	var before: Dictionary = _snapshot(build)
	var previous_changes: int = change_count
	_write_bad_file(JSON.stringify(candidate))
	_expect(not build.load_build(BAD_SAVE), description + " rejected")
	_expect(_snapshot(build) == before and change_count == previous_changes, description + " preserves build without signal")


func _write_bad_file(contents: String) -> void:
	var file: FileAccess = FileAccess.open(BAD_SAVE, FileAccess.WRITE)
	if file == null:
		_expect(false, "Create invalid-save fixture")
		return
	file.store_string(contents)
	file.close()


func _snapshot(build: Model) -> Dictionary:
	return {
		"inventory": build.inventory.duplicate(), "equipped": build.equipped.duplicate(),
		"talents": build.talents.duplicate(), "skill_slots": build.skill_slots.duplicate(),
		"level": build.level, "xp": build.xp, "talent_points": build.talent_points,
	}


func _remove_test_files() -> void:
	for path: String in [TEST_SAVE, TEST_SAVE + ".tmp", BAD_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _on_changed() -> void:
	change_count += 1


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)
