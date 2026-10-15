extends SceneTree
## Persisted paid receipts, actual Main startup and transition handlers; only IO is faulted.
const Model = preload("res://scripts/canonical_game_state.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const PATH := "user://build_save.json"
class FaultModel extends Model:
	var fail_writes := false
	var write_attempts := 0
	var abandon_attempts := 0
	var abandon_commits := 0
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		write_attempts += 1
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path, bytes)
	func normal_abandon_map(run_id: Variant, expected_revision: Variant, path: String) -> Dictionary:
		abandon_attempts += 1
		var result := super.normal_abandon_map(run_id, expected_revision, path)
		if result.ok: abandon_commits += 1
		return result
class MissingRecovery extends "res://scripts/main.gd":
	func _recover_normal_active() -> Dictionary:
		return {"ok": true, "reason": ""}
var checks := 0
var failures := 0
var arena
var model: FaultModel
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func observe() -> Array:
	return [var_to_bytes(model.snapshot()), FileAccess.get_file_as_bytes(PATH), model.successful_saves,
		arena.world_context(), arena.map_draft(), arena.build_save_path, arena.run_revision]
func transition(action: String, stale: bool = false) -> Dictionary:
	var revision: int = arena.map_draft().revision if action == "start" else arena.world_context().revision
	if stale: revision += 100
	match action:
		"start": return arena.start_map(revision)
		"leave": return arena.leave_normal_town(revision)
		_: return arena.enter_town_test(revision)
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	var scenario := OS.get_environment("STARTUP_CASE")
	if not isolated.begins_with("/tmp/godot-startup-recovery.") or not OS.get_user_data_dir().begins_with(isolated + "/") or FileAccess.file_exists(PATH) or scenario not in ["start", "leave", "test", "completed_start", "completed_leave", "completed_test"]:
		printerr("Requires fresh isolated /tmp/godot-startup-recovery.* and explicit STARTUP_CASE")
		quit(78)
		return
	var completed := scenario.begins_with("completed_")
	var action := scenario.trim_prefix("completed_")
	var seed := Model.new()
	check(seed.save_build(PATH) == OK, "Fresh canonical receipt saved")
	var free: Dictionary = Maps.compile_normal("old_garden", 1, [], []).profile
	for unused in range(2):
		var began := seed.normal_start_map(free, seed.revision(), PATH)
		check(began.ok, "Supported free admission")
		check(seed.normal_complete_map(began.run_id, seed.revision(), PATH).ok, "Supported completion unlocks paid tier")
		check(seed.normal_claim_rewards(seed.revision(), PATH).ok, "Supported claim funds physical currency")
	var paid: Dictionary = Maps.compile_normal("old_garden", 2, [], []).profile
	var paid_run := seed.normal_start_map(paid, seed.revision(), PATH)
	check(paid_run.ok and paid_run.cost == 4 and seed.crafting_balance() == 4, "Paid receipt deducts exactly four of eight shards")
	var run_id: int = paid_run.run_id
	for unused in range(60): seed.add_normal_root_xp(0)
	check(seed.save_build(PATH) == OK and seed.normal_pending_rewards().pending_gems == 2 and seed.normal_pending_rewards().pending_flasks == 1, "Supported root milestones persist existing unclaimed rewards")
	if completed:
		check(seed.normal_complete_map(run_id, seed.revision(), PATH).ok, "Existing completed run creates persisted unclaimed reward")
	var saved := seed.snapshot()
	var disk := FileAccess.get_file_as_bytes(PATH)
	var pending := seed.normal_pending_rewards()
	model = FaultModel.new()
	model.fail_writes = true
	arena = load("res://scenes/main.tscn").instantiate()
	if OS.get_environment("STARTUP_RED_CONTROL") == "skip_recovery": arena.set_script(MissingRecovery)
	arena.state = model
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	await process_frame
	check(model.snapshot() == saved and FileAccess.get_file_as_bytes(PATH) == disk and model.successful_saves == 0, "Startup retains exact persisted memory, bytes and revision despite failed recovery")
	check(arena.world_context().mode == "town" and not arena.world_context().test_mode, "Actual startup remains in normal town")
	check(model.abandon_attempts == (0 if completed else 1) and model.abandon_commits == 0 and model.write_attempts == (0 if completed else 1), "Startup only attempts abandon for an unfinished receipt")
	check(model.crafting_balance() == 4 and model.normal_journey().next_run_id == saved.journey.next_run_id and model.normal_pending_rewards() == pending, "Startup neither refunds fee nor duplicates run IDs or rewards")
	if OS.get_environment("STARTUP_RED_CONTROL") == "skip_recovery":
		print("STARTUP_RECOVERY_RED ", checks, " checks, ", failures, " failures")
		arena.queue_free()
		await process_frame
		quit(1 if failures else 0)
		return
	if action == "start":
		check(arena.craft_normal_map("old_garden", 2, [], [], arena.map_draft().revision).ok, "Actual town crafts supported paid retry draft")
	var before := observe()
	var attempts := model.abandon_attempts
	check(not transition(action, true).ok and observe() == before and model.abandon_attempts == attempts, "Wrong transition revision rejects before recovery and preserves all state")
	if not completed:
		var failed := transition(action)
		check(not failed.ok and failed.code == "save_failed" and observe() == before, "Continued IO failure rejects transition without changing memory, disk or world")
		check(model.abandon_attempts == attempts + 1 and model.abandon_commits == 0, "Blocked transition retried real abandon without committing")
		check(model.normal_journey().active_run.run_id == run_id and model.normal_journey().active_run.fee_paid == 4, "Failed transition preserves paid active receipt")
	model.fail_writes = false
	var result := transition(action)
	if completed and action == "start":
		check(not result.ok and observe() == before, "Unclaimed completion blocks new admission with exact state preservation")
	else:
		check(result.ok, "Restored writes allow intended transition")
	check(model.abandon_commits == (0 if completed else 1), "Unfinished receipt clears exactly once; completed receipt never abandoned")
	var journey := model.normal_journey()
	if not completed and action == "start":
		check(journey.active_run.run_id == saved.journey.next_run_id and journey.next_run_id == saved.journey.next_run_id + 1 and journey.active_run.fee_paid == 4 and model.crafting_balance() == 0, "New paid admission consumes one fee and one new run ID")
		check(arena.world_context().mode == "map", "Successful retry enters actual map")
	else:
		check(journey.active_run.is_empty() and journey.next_run_id == saved.journey.next_run_id and model.crafting_balance() == 4, "Recovery neither reissues a run nor refunds paid fee")
		check(arena.world_context().mode == ("normal" if action == "leave" else "town") and arena.world_context().test_mode == (action == "test"), "Transition reaches intended normal or independent-test destination")
	check(model.normal_pending_rewards() == pending and journey.best_tiers == saved.journey.best_tiers, "Existing completion and milestone rewards and unlocks remain exact")
	var reloaded := Model.new()
	check(reloaded.load_build(PATH) and reloaded.snapshot() == model.snapshot(), "Normal on-disk receipt reloads exactly after transition")
	before = observe()
	check(not model.normal_complete_map(run_id, model.revision(), PATH).ok and observe() == before, "Old receipt cannot mint duplicate completion reward")
	check(not model.normal_abandon_map(run_id, model.revision(), PATH).ok and observe() == before, "Old receipt cannot be abandoned twice")
	if action != "test":
		before = observe()
		check(not transition(action).ok and observe() == before, "Repeated transition is harmless outside its valid context")
	else:
		check(arena.state != model and arena.build_save_path == "user://town_test_build_save.json", "Test transition actually replaces profile without losing normal receipt")
	print("STARTUP_RECOVERY ", scenario, " ", checks, " checks, ", failures, " failures")
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
