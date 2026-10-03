extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Legacy = preload("res://scripts/build_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	var state := Model.new()
	var legacy := Legacy.new()
	var stats := state.get_stats()
	var legacy_stats := legacy.get_stats()
	check(stats.max_health==legacy_stats.max_health+10 and stats.max_mana==legacy_stats.max_mana+10 and is_equal_approx(stats.max_shield,legacy_stats.max_shield*1.02), "source Scion attributes add derived resources to preserved legacy gear/base")
	var snapshot := state.get_combat_snapshot()
	var original_snapshot := legacy.get_combat_snapshot()
	check(snapshot.base_damage==original_snapshot.base_damage and snapshot.added_damage==original_snapshot.added_damage and snapshot.effects==original_snapshot.effects, "legacy damage/additions/effects remain unchanged; new scoped strength and accuracy are explicit")
	var cast := state.get_group_cast("group_000002")
	check(cast.ok and cast.skill_id == "frost", "group resolves actual active gem")
	var d := state.cache_diagnostics()
	for i: int in range(20):
		state.get_group_cast("group_000002")
		state.get_stats()
	check(state.cache_diagnostics() == d, "repeat stable compile cached")
	var path := "user://game-state-%d.json" % Time.get_ticks_usec()
	check(state.save_build(path) == OK, "start persisted")
	var source := state.snapshot()
	for definition_id: String in ["support:swift_projectiles","support:heavy_projectiles","support:lingering_chill","support:efficiency","support:quickcast"]:
		var uid := ""
		for id: String in source.items:
			if source.items[id].definition_id == definition_id: uid = id
		var index: int = state.skill_group("group_000002").support_ids.size()
		check(state.move_item(uid, {"kind":"skill_support","group_id":"group_000002","index":index}, state.revision(), path).ok, "actual fifth slot commits")
	cast = state.get_group_cast("group_000002")
	check(cast.ok and cast.support_ids.size() == 5 and is_equal_approx(cast.recipe.slow, 4.5), "all five actual consumer recipe")
	var second_uid := state.award_gem("skill:frost")
	check(not second_uid.is_empty(), "second same skill independently obtained")
	check(state.move_item(second_uid, {"kind":"skill_main","group_id":"group_000009"}, state.revision(), path).ok, "duplicate active definition in separate row")
	var second := state.get_group_cast("group_000009")
	check(second.ok and second.main_uid != cast.main_uid and second.support_ids.is_empty(), "same name no shared links")
	# Obtain a real catalog helmet/belt carrying an extra row; no fabricated payload.
	var rng := RandomNumberGenerator.new()
	rng.seed = 91414
	var row_item := ""
	for i: int in range(8):
		var uid := state.award_equipment(rng, 30, "rare", "nine_slot")
		if uid.is_empty(): break
		if state.item_definition(uid).stats.has("additional_skill_slots"):
			row_item = uid
			break
	check(not row_item.is_empty(), "natural generation yields actual extra-row item")
	if not row_item.is_empty():
		var category: String = state.item_definition(row_item).category
		var old_location := state.location(row_item)
		check(state.move_item(row_item, {"kind":"equipment","slot_id":category}, state.revision(), path).ok, "new target accepts real item")
		check(state.active_group_capacity() == 11 and state.snapshot().skill_groups.size() == 11, "extra row actually exists and active")
		check(state.move_item(second_uid, {"kind":"skill_main","group_id":"group_000011"}, state.revision(), path).ok, "gem installs to eleventh row")
		check(state.bind_group("group_000011", KEY_F1, state.revision(), path).ok and state.group_for_key(KEY_F1) == "group_000011", "eleventh row can bind actual input")
		check(state.get_group_cast("group_000011").ok, "eleventh row compiles real skill")
		check(state.move_item(row_item, old_location, state.revision(), path).ok, "remove capacity item")
		check(state.active_group_capacity() == 10 and state.snapshot().skill_groups.size() == 11, "capacity loss retains stable row")
		check(state.location(second_uid).group_id == "group_000011" and not state.get_group_cast("group_000011").ok and state.group_for_key(KEY_F1) == "", "inactive row retains gem and binding without cast")
		check(state.move_item(row_item, {"kind":"equipment","slot_id":category}, state.revision(), path).ok and state.get_group_cast("group_000011").ok, "reequip restores existing row")
	var loaded := Model.new()
	check(loaded.load_build(path) and loaded.snapshot() == state.snapshot(), "five links and eleventh row save roundtrip")
	state.get_group_cast("group_000002")
	var before := state.cache_diagnostics()
	state.add_xp(1)
	state.get_group_cast("group_000002")
	check(state.cache_diagnostics() == before, "XP without level does not invalidate stable build")
	check(Rules.reason(state.snapshot()).is_empty(), "final full canonical candidate valid")
	print("Canonical game state: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
