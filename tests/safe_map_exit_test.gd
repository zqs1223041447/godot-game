extends SceneTree
## Actual Main/HUD/CanonicalGameState integration, with a bounded lawful map.
## Only filesystem failure and process quit are replaced. No completion flag,
## earned currency, unlock, encounter roster, timer, or RNG fixture is granted.
const Model = preload("res://scripts/canonical_game_state.gd")

class FaultModel extends Model:
	var fail_all := false
	var fail_writes: Array[int] = []
	var write_calls := 0
	var before_write: Callable
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		write_calls += 1
		var callback := before_write
		before_write = Callable()
		if callback.is_valid(): callback.call()
		if fail_all or write_calls in fail_writes: return ERR_CANT_CREATE
		return super._write_bytes(path, bytes)

class ExitSpyArena extends "res://scripts/main.gd":
	var quit_requests := 0
	func _quit_game() -> void:
		quit_requests += 1

var arena: Node2D
var model: FaultModel
var checks := 0
var failures := 0
var failed_labels: Array[String] = []
var current_group := ""
var group_results: Array[Dictionary] = []
var nested_result: Dictionary = {}
var original_auto_accept := true

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		failed_labels.append(current_group + ": " + label)
		printerr("FAIL: " + current_group + ": " + label)
	return value

func accepted(result: Dictionary, label: String) -> bool:
	return check(bool(result.get("ok", false)), label + ": " + JSON.stringify(result))

func exit_result(result: Dictionary, expected_ok: bool, label: String, code: String = "") -> bool:
	var valid := result.get("ok") is bool and result.get("reason") is String and result.get("error_code") is String
	if not check(valid, label + " exposes ok/reason/error_code: " + JSON.stringify(result)): return false
	if not check(bool(result.ok) == expected_ok, label + " outcome: " + JSON.stringify(result)): return false
	if not expected_ok:
		check(not str(result.reason).is_empty(), label + " gives an actionable failure reason")
		check(not str(result.error_code).is_empty(), label + " gives a failure code")
		if not code.is_empty(): check(str(result.error_code) == code, label + " failure stage is " + code)
	return true

func pause() -> void:
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	for unused: int in range(4): arena.hud.close_panel()

func dispose() -> void:
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	arena = null
	model = null

func load_arena() -> void:
	arena = load("res://scenes/main.tscn").instantiate()
	arena.set_script(ExitSpyArena)
	model = FaultModel.new()
	arena.state = model
	root.add_child(arena)
	pause()
	await process_frame
	check(not auto_accept_quit, "Main disables automatic SceneTree window-close quit")

func fresh(prior_auto_accept: bool = true) -> bool:
	await dispose()
	if FileAccess.file_exists("user://build_save.json"):
		if not check(DirAccess.remove_absolute(ProjectSettings.globalize_path("user://build_save.json")) == OK, "Remove only this isolated suite's previous profile"): return false
	auto_accept_quit = prior_auto_accept
	await load_arena()
	if not check(arena.world_context().normal_town and model.normal_journey().active_run.is_empty(), "Fresh actual Main starts in formal town"): return false
	return check(arena.save_build(), "Fresh canonical profile saves through Main")

func disk() -> PackedByteArray: return FileAccess.get_file_as_bytes("user://build_save.json")

func observation() -> Dictionary:
	return {"state": model.snapshot(), "world": arena.world_context(), "disk": disk(), "run": arena._map_run.snapshot(), "rng": arena.rng.state, "quit": arena.quit_requests}

func enter_map() -> bool:
	if not accepted(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision), "Lawful free tier-I Old Garden draft"): return false
	if not accepted(arena.start_map(arena.map_draft().revision), "Actual Main admits the lawful map"): return false
	pause()
	return check(arena.enemies.size() == 25 and arena.world_context().mode == "map" and model.crafting_balance() == 0, "All 25 actual roots entered without grants or entry charge")

func complete_with_failure() -> bool:
	if not enter_map(): return false
	var entry_bytes := disk()
	model.fail_all = true
	var rounds := 0
	arena._begin_progress_transaction()
	while arena.world_context().mode == "map" and rounds < 12:
		rounds += 1
		arena._flush_monster_spawns()
		for enemy: Dictionary in arena.enemies.duplicate():
			if float(enemy.health) <= 0.0: continue
			enemy.spawn = 0.0
			arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 10000.0, Color.WHITE)
		arena._flush_monster_spawns()
		arena._check_map_complete()
	arena._end_progress_transaction()
	if not check(rounds < 12 and arena.world_context().mode == "map_complete" and arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty(), "Actual bounded damage/death loop clears roots and descendants"): return false
	check(arena.reward_kills == 25 and model.normal_journey().normal_root_kills == 25, "Exactly 25 lawful root kills earn progression")
	check(arena.world_context().completion_save_pending, "Failed genuine completion retains its runtime retry receipt")
	var journey: Dictionary = model.normal_journey()
	check(journey.best_tiers.old_garden == 0 and journey.pending_map_reward.is_empty() and not journey.active_run.is_empty(), "Failed completion neither unlocks tier nor mints reward")
	check(disk() == entry_bytes, "Injected failed writes preserve the admitted save bytes")
	return true

func settled(label: String) -> bool:
	var journey: Dictionary = model.normal_journey()
	return check(not arena.world_context().completion_save_pending and journey.active_run.is_empty() and journey.best_tiers.old_garden == 1 and journey.pending_map_reward.get("shards", 0) == 4, label)

func repeated_success() -> void:
	var before := observation()
	var writes := model.write_calls
	exit_result(arena.request_safe_exit(), true, "Repeated successful exit")
	arena.hud._exit_game()
	arena.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(arena.quit_requests == 1 and model.write_calls == writes and observation() == before, "Repeated direct/menu/window exit neither saves nor quits again")

func reload_and_claim() -> void:
	var expected := model.snapshot()
	await dispose()
	await load_arena()
	check(arena.world_context().normal_town and model.snapshot() == expected, "Actual startup retains completed progress rather than abandoning it")
	if not settled("Reload keeps tier-I unlock and exactly four pending shards"): return
	check(model.crafting_balance() == 0, "Unclaimed map reward is not yet credited")
	var claimed: Dictionary = arena.claim_normal_rewards(arena.world_context().revision)
	if not accepted(claimed, "Actual town claims recovered completion reward"): return
	check(claimed.get("claimed_shards", -1) == 4 and model.crafting_balance() == 4, "Claim credits exactly four shards")
	var before := observation()
	var duplicate: Dictionary = arena.claim_normal_rewards(arena.world_context().revision)
	check(not bool(duplicate.get("ok", false)) and observation() == before, "Second claim cannot duplicate currency or rewrite save")
	expected = model.snapshot()
	await dispose()
	await load_arena()
	check(model.snapshot() == expected and model.crafting_balance() == 4 and model.normal_journey().pending_map_reward.is_empty(), "Claimed receipt remains consumed after a second actual reload")

func town_and_reentry() -> void:
	if not await fresh(): return
	model.fail_all = true
	var before := observation()
	for unused: int in range(2): exit_result(arena.request_safe_exit(), false, "Persistent town save failure", "save_failed")
	check(observation() == before and arena.quit_requests == 0, "Persistent town failure keeps the live game and exact save")
	model.fail_all = false
	nested_result = {}
	model.before_write = func() -> void: nested_result = arena.request_safe_exit()
	var writes := model.write_calls
	if not exit_result(arena.request_safe_exit(), true, "Town exit recovers once writing works"): return
	exit_result(nested_result, false, "Reentry while writer is active", "busy")
	check(model.write_calls == writes + 1 and arena.quit_requests == 1, "Reentrant request cannot nest a write or duplicate quit")
	repeated_success()
	await dispose()
	check(auto_accept_quit, "Freeing Main restores an originally enabled auto_accept_quit")
	if not await fresh(false): return
	arena.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(arena.quit_requests == 1, "Window close in a clean town routes through safe exit")
	await dispose()
	check(not auto_accept_quit, "Freeing Main also preserves an originally disabled auto_accept_quit")

func unfinished_map() -> void:
	if not await fresh() or not enter_map(): return
	var active: Dictionary = model.normal_journey().active_run.duplicate(true)
	var next_id: int = model.normal_journey().next_run_id
	var before := model.snapshot()
	arena.hud.open_panel("pause")
	arena.hud._exit_game()
	check(arena.quit_requests == 1 and model.snapshot() == before and model.normal_journey().active_run == active, "Menu exit saves an uncompleted map without manufacturing completion")
	repeated_success()
	await dispose()
	await load_arena()
	var journey: Dictionary = model.normal_journey()
	check(arena.world_context().normal_town and journey.active_run.is_empty() and journey.next_run_id == next_id, "Existing startup abandonment handles the uncompleted saved map")
	check(journey.best_tiers.old_garden == 0 and journey.pending_map_reward.is_empty() and model.crafting_balance() == 0, "Uncompleted map reload grants no unlock or completion reward")

func completion_recovery() -> void:
	if not await fresh() or not complete_with_failure(): return
	model.fail_all = false
	if not check(arena.save_build(), "Ordinary save_build remains available after failed completion"): return
	check(arena.world_context().completion_save_pending and not model.normal_journey().active_run.is_empty() and model.normal_journey().pending_map_reward.is_empty(), "Ordinary save_build does not silently finalize pending completion")
	model.fail_all = true
	arena.hud.open_panel("pause")
	var before := observation()
	for unused: int in range(2): arena.hud._exit_game()
	check(arena.quit_requests == 0 and observation() == before, "Repeated menu exits preserve pending completion during persistent failure")
	check(arena.hud._panel_footer.visible and not arena.hud._panel_footer.text.is_empty(), "Menu exit failure is visible in the existing footer")
	exit_result(arena.request_safe_exit(), false, "Pending completion failure reports its stage", "completion_save_failed")
	model.fail_all = false
	arena.hud._exit_game()
	if not check(arena.quit_requests == 1, "Menu exit quits once after completion and final save succeed"): return
	if not settled("Menu retry commits the lawful completion exactly once"): return
	repeated_success()
	await reload_and_claim()

func partial_commit() -> void:
	if not await fresh() or not complete_with_failure(): return
	model.fail_all = false
	var writes := model.write_calls
	var successes: int = model.successful_saves
	model.fail_writes = [writes + 2]
	arena.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(model.write_calls == writes + 2 and model.successful_saves == successes + 1, "Window close commits completion then reaches the injected later plain-save failure")
	check(arena.quit_requests == 0, "Window close stays alive after later progress-save failure")
	if not settled("A committed completion is not marked pending again after final save fails"): return
	var receipt: Dictionary = model.normal_journey().pending_map_reward.duplicate(true)
	var expected := model.snapshot()
	var persisted := Model.new()
	if not check(persisted.load_build("user://build_save.json"), "Committed completion remains a loadable canonical save"): return
	check(persisted.snapshot() == expected and persisted.normal_journey().pending_map_reward == receipt, "Successful completion survives on disk despite failed later save")
	model.fail_all = true
	var before := observation()
	exit_result(arena.request_safe_exit(), false, "Repeated later plain-save failure", "save_failed")
	check(observation() == before and arena.quit_requests == 0, "Persistent later failure preserves the already committed receipt")
	model.fail_all = false
	model.fail_writes.clear()
	writes = model.write_calls
	if not exit_result(arena.request_safe_exit(), true, "Final progress save retries successfully"): return
	check(model.write_calls == writes + 1 and arena.quit_requests == 1 and model.snapshot() == expected and model.normal_journey().pending_map_reward == receipt, "Retry performs only plain save and never remints completion")
	repeated_success()
	await reload_and_claim()

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v099-") or FileAccess.file_exists("user://build_save.json"):
		printerr("Requires a fresh isolated /tmp/godot-m1-v099-* XDG_DATA_HOME")
		quit(78)
		return
	original_auto_accept = auto_accept_quit
	var selected := OS.get_environment("SAFE_EXIT_GROUP")
	for group: String in ["town_and_reentry", "unfinished_map", "completion_recovery", "partial_commit"]:
		if not selected.is_empty() and selected != group: continue
		current_group = group
		var previous_checks := checks
		var previous_failures := failures
		await call(group)
		group_results.append({"group": group, "checks": checks - previous_checks, "failures": failures - previous_failures})
		print("SAFE_EXIT_GROUP " + JSON.stringify(group_results.back()))
	check(not group_results.is_empty(), "Requested group exists")
	await dispose()
	auto_accept_quit = original_auto_accept
	var report := {"checks": checks, "failures": failures, "groups": group_results, "failed_labels": failed_labels, "method": "Actual Main/HUD/CanonicalGameState; isolated filesystem faults and bounded real Old Garden deaths; exit-only spy"}
	var output := OS.get_environment("SAFE_EXIT_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			printerr("Cannot write requested report: " + output)
			failures += 1
		else:
			file.store_string(JSON.stringify(report, "\t", true, true))
			file.close()
	print("SAFE_MAP_EXIT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
