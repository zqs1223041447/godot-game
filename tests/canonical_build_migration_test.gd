extends SceneTree
const Migration = preload("res://scripts/save/canonical_build_migration.gd")
const Legacy = preload("res://scripts/build_state.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Layout = preload("res://scripts/items/item_location_rules.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passive_source/normalized_tree.json"))
	check(source.node_records[Migration.DEFAULT_START_ID].classStartIndex == Migration.DEFAULT_CLASS_ID, "default class source verified")
	check(source.points.totalPoints == Migration.NORMAL_POINT_LIMIT, "point budget source verified")
	var state := Legacy.new()
	state.set_skill_supports("bolt", ["focus", "efficiency"])
	state.set_skill_supports("frost", ["focus", "cold_focus"])
	state.crafting = {"materials":{"calibration_shard":79},"revision":37}
	for level: int in [1, 100, 120, 124, 1000]:
		state.level = level
		state.talent_points = Legacy.BASE_TALENT_POINTS + level - 1
		var snapshot := state._snapshot()
		var before := var_to_bytes(snapshot)
		var result := Migration.migrate(snapshot)
		check(not result.is_empty(), "migration admitted")
		if result.is_empty(): continue
		check(before == var_to_bytes(snapshot), "input unchanged")
		check(Migration.migrate(JSON.parse_string(JSON.stringify(snapshot))) == result, "JSON migration equality")
		check(result.skill_groups.size() == 10 and result.bindings.size() == 8, "ten stable rows, eight initial keys")
		check(result.crafting == state.crafting, "wallet revision untouched")
		check(result.progress == {"level":level,"xp":0}, "progress untouched")
		check(result.talents.normal_points == mini(level + 4, 123), "finite points")
		check(result.migration_ledger.excess_points_recorded == maxi(0, level + 4 - 123), "excess accounted")
		check(result.locations.azure_charm == {"kind":"equipment","slot_id":"amulet"}, "charm UID preserved")
		check(result.locations.guardian_robe == {"kind":"equipment","slot_id":"body_armour"}, "armor UID preserved")
		for key: String in snapshot.backpack_positions:
			var uid: String = key.substr(6) if key.begins_with("jewel:") else key.substr(5)
			check(result.locations[uid] == {"kind":"bag","x":snapshot.backpack_positions[key][0],"y":snapshot.backpack_positions[key][1]}, "prior bag position preserved")
		for uid: String in state.jewels:
			check(result.items[uid].payload == state.jewels[uid], "jewel values preserved")
		var definitions := {}
		var focus_uids := []
		for uid: String in result.items:
			check(Items.validate_instance(result.items[uid]), "valid envelope")
			definitions[result.items[uid].definition_id] = true
			if result.items[uid].definition_id == "support:focus": focus_uids.append(uid)
		for definition_id: String in Gems.definitions():
			check(definitions.has(definition_id), "old available gem retained")
		check(focus_uids.size() == 2 and focus_uids[0] != focus_uids[1], "shared definition becomes independent instances")
		check(Layout.validate(Items.metadata_for_items(result.items), result.locations, Migration.location_context(result)).ok, "complete ownership location")
	var exhausted := state._snapshot()
	exhausted.next_equipment_id = 1000000000
	exhausted.next_jewel_id = 1000000000
	var exhausted_result := Migration.migrate(exhausted)
	check(not exhausted_result.is_empty() and exhausted_result.next_item_serial == 1000000000,"valid exhausted old sequence still migrates all implicit gems")
	var future := state._snapshot()
	future.version = 14
	check(Migration.migrate(future).is_empty(), "unknown version cannot enter legacy migration")
	var invalid := state._snapshot()
	invalid.skill_supports.bolt = ["focus","efficiency","quickcast"]
	check(Migration.migrate(invalid).is_empty(), "old schema still rejects injected third link")
	# A legal crowded old backpack remains lossless after its implicit gems become items.
	state = Legacy.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3114
	for i: int in range(80): state.award_jewel(rng)
	var crowded := Migration.migrate(state._snapshot())
	check(not crowded.is_empty(), "crowded valid migration")
	if not crowded.is_empty():
		check(crowded.migration_ledger.initial_recovery_count > 0, "overflow retained visibly pending")
		check(crowded.items.size() == state.inventory.size() + state.jewels.size() + 24, "no lost overflow instance")
		check(crowded.items.size() == crowded.locations.size(), "all overflow owns one location")
	print("Canonical migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
