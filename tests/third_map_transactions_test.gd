extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const MAP_ID := "sunwell_terrace"
const PATH := "user://build_save.json"

class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func observed(model: Model) -> Dictionary:
	return {"memory": var_to_bytes(model.snapshot()), "disk": FileAccess.get_file_as_bytes(PATH), "saves": model.successful_saves}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-v048-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	var model := FaultModel.new()
	check(model.save_build(PATH) == OK and model.snapshot().version == 30, "Fresh schema30 normal profile saved")
	var one := Maps.compile_normal(MAP_ID, 1, [], [])
	var two := Maps.compile_normal(MAP_ID, 2, ["enemy_armour_80", "enemy_move_speed_110"], ["frost_patrol"])
	var three := Maps.compile_normal(MAP_ID, 3, ["enemy_armour_80", "enemy_move_speed_110"], ["storm_patrol"])
	check(one.ok and two.ok and three.ok, "All three sunwell profiles compile")
	if not one.ok or not two.ok or not three.ok:
		quit(1)
		return
	check(one.profile.wave == 3 and two.profile.wave == 6 and three.profile.wave == 10, "Sunwell waves are3/6/10")
	check(one.profile.fee == 0 and two.profile.fee == 4 and three.profile.fee == 8, "Existing currency fee is0/4/8")
	check(one.profile.base_completion_reward == 4 and two.profile.base_completion_reward == 8 and three.profile.base_completion_reward == 12 and two.profile.completion_reward == 12 and three.profile.completion_reward == 16, "Existing4/8/12 reward plus at most4 modifier bonus")
	var changes := [0]
	model.changed.connect(func(): changes[0] += 1)
	var before := observed(model)
	check(not model.normal_start_map(two.profile, model.revision(), PATH).ok and observed(model) == before, "New tierII starts locked without deductions")
	var first := model.normal_start_map(one.profile, model.revision(), PATH)
	check(first.ok and first.run_id == 1 and first.cost == 0 and model.crafting_balance() == 0, "Free tierI opens immediately with persisted run1")
	var reopened := Model.new()
	check(reopened.load_build(PATH) and reopened.normal_journey().active_run.map_id == MAP_ID and reopened.normal_journey().active_run.run_id == 1 and reopened.save_attempts == 0, "Current30 preserves new active map across reopen")
	check(model.normal_complete_map(first.run_id, model.revision(), PATH).ok and model.normal_journey().best_tiers[MAP_ID] == 1, "TierI completion unlocks only this map's tierII")
	check(model.normal_journey().best_tiers.old_garden == 0 and model.normal_journey().best_tiers.broken_ruins == 0, "Old maps keep independent zero progress")
	before = observed(model)
	check(not model.normal_complete_map(first.run_id, model.revision(), PATH).ok and observed(model) == before, "A completed run cannot settle twice")
	check(not model.normal_start_map(two.profile, model.revision(), PATH).ok and observed(model) == before, "Pending shards block new admission")
	var claimed := model.normal_claim_rewards(model.revision(), PATH)
	check(claimed.ok and claimed.claimed_shards == 4 and model.crafting_balance() == 4, "TierI reward becomes exactly four real inventory shards")
	before = observed(model)
	var signal_count: int = changes[0]
	model.fail_save = true
	check(not model.normal_start_map(two.profile, model.revision(), PATH).ok and observed(model) == before and changes[0] == signal_count, "Failed tierII write keeps currency, run serial and memory")
	model.fail_save = false
	var second := model.normal_start_map(two.profile, model.revision(), PATH)
	check(second.ok and second.cost == 4 and second.run_id == 2 and model.crafting_balance() == 0, "Sunwell tierII charges exactly four once")
	before = observed(model)
	check(not model.normal_start_map(two.profile, model.revision(), PATH, second.run_id).ok and observed(model) == before, "Unfunded death retry cannot change the active run")
	check(model.normal_complete_map(second.run_id, model.revision(), PATH).ok and model.normal_journey().best_tiers[MAP_ID] == 2 and model.normal_pending_rewards().pending_map_reward.shards == 12, "TierII completes once for existing8+4 modifier reward")
	claimed = model.normal_claim_rewards(model.revision(), PATH)
	check(claimed.ok and claimed.claimed_shards == 12 and model.crafting_balance() == 12, "TierII reward uses real currency inventory")
	var third := model.normal_start_map(three.profile, model.revision(), PATH)
	check(third.ok and third.cost == 8 and model.crafting_balance() == 4, "Unlocked tierIII charges exactly eight")
	check(model.normal_abandon_map(third.run_id, model.revision(), PATH).ok and model.crafting_balance() == 4 and model.normal_journey().best_tiers[MAP_ID] == 2, "Abandon preserves best tier and gives no refund")
	# Fill all real bag cells with legal UID gems. Existing non-bag identities remain.
	var filled := model.snapshot()
	for uid: String in filled.locations.keys():
		if filled.locations[uid].kind == "bag":
			filled.locations.erase(uid)
			filled.items.erase(uid)
	while true:
		var uid := "item_%06d" % int(filled.next_item_serial)
		if not model._place_journey_reward(filled, Gems.create_instance(uid, "support:efficiency")): break
	filled.revision += 1
	check(Rules.reason(filled).is_empty() and model._commit(filled, PATH).ok, "Actual full bag fixture passes current canonical validation")
	var full := model.normal_start_map(one.profile, model.revision(), PATH)
	check(full.ok and model.normal_complete_map(full.run_id, model.revision(), PATH).ok, "Full bag still permits free tierI completion")
	before = observed(model)
	signal_count = changes[0]
	check(not model.normal_claim_rewards(model.revision(), PATH).ok and observed(model) == before and changes[0] == signal_count, "Full bag retains pending shards without consuming UID or write")
	var pending: Dictionary = model.normal_pending_rewards().pending_map_reward
	check(pending.map_id == MAP_ID and pending.shards == 4 and model.crafting_balance() == 0, "Full-bag sunwell reward remains owed")
	var pending_reopen := Model.new()
	check(pending_reopen.load_build(PATH) and pending_reopen.normal_pending_rewards().pending_map_reward == pending and pending_reopen.save_attempts == 0, "Current30 preserves new pending reward across reopen")
	var discard_uid := ""
	for uid: String in model.snapshot().locations:
		if model.snapshot().locations[uid].kind == "bag":
			discard_uid = uid
			break
	check(model.discard_item(discard_uid, model.revision(), PATH).ok, "Release one actual bag slot")
	claimed = model.normal_claim_rewards(model.revision(), PATH)
	check(claimed.ok and claimed.claimed_shards == 4 and model.crafting_balance() == 4 and model.normal_pending_rewards().pending_map_reward.is_empty(), "One released slot delivers owed reward once")
	before = observed(model)
	check(not model.normal_claim_rewards(model.revision(), PATH).ok and observed(model) == before, "Cleared reward cannot duplicate")
	check(Rules.reason(model.snapshot()).is_empty() and model.normal_journey().best_tiers[MAP_ID] == 2 and model.normal_journey().best_tiers.old_garden == 0 and model.normal_journey().best_tiers.broken_ruins == 0, "Final state preserves per-map progression and all invariants")
	print("Third map transactions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
