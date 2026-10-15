extends SceneTree
## Real map/completion/return transactions. Only disk failure and quit are replaced.
const Maps = preload("res://scripts/world/map_compiler.gd")
class Fault extends "res://scripts/canonical_game_state.gd":
	var writes := 0
	var fail_at := -1
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		writes += 1
		return ERR_CANT_CREATE if writes == fail_at else super._write_bytes(path, bytes)
class ExitSpy extends "res://scripts/main.gd":
	var quit_requests := 0
	func _quit_game() -> void: quit_requests += 1
var checks := 0
var failures := 0
var arena
var model
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func load_arena():
	arena = load("res://scenes/main.tscn").instantiate()
	arena.set_script(ExitSpy)
	model = Fault.new()
	arena.state = model
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	await process_frame
	for unused in range(4): arena.hud.close_panel()
func disk_matches(label: String):
	var disk = Fault.new()
	check(disk.load_build(arena.build_save_path) and disk.snapshot() == model.snapshot(), label + " persisted snapshot")
func kill_one():
	for enemy in arena.enemies.duplicate():
		if float(enemy.health) <= 0: continue
		enemy.spawn = 0.0
		arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 10000, Color.WHITE)
		break
func clear_map():
	arena._begin_progress_transaction()
	for unused in range(12):
		arena._flush_monster_spawns()
		for enemy in arena.enemies.duplicate():
			if float(enemy.health) <= 0: continue
			enemy.spawn = 0.0
			arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 10000, Color.WHITE)
		arena._flush_monster_spawns()
		arena._check_map_complete()
		if arena.world_context().mode == "map_complete": break
	arena._end_progress_transaction()
	check(arena.world_context().mode == "map_complete", "full clear reached")
func run():
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/") or FileAccess.file_exists("user://build_save.json"):
		printerr("Requires a fresh isolated /tmp XDG_DATA_HOME")
		quit(78)
		return
	var mode = OS.get_environment("RETURN_CASE")
	if mode.is_empty(): mode = "second_clear"
	var fixture = OS.get_environment("RETURN_FIXTURE")
	if fixture.is_empty(): fixture = "free"
	await load_arena()
	check(arena.save_build(), "initial save")
	var tier = 1 if fixture == "free" else 2
	if tier == 2:
		var seed_profile = Maps.compile_normal("old_garden", 1, [], []).profile
		var seeded = model.normal_start_map(seed_profile, model.revision(), arena.build_save_path)
		check(seeded.ok, "supported seed start")
		check(model.normal_complete_map(seeded.run_id, model.revision(), arena.build_save_path).ok, "supported seed completion")
		check(model.normal_claim_rewards(model.revision(), arena.build_save_path).ok, "supported seed claim")
		check(model.crafting_balance() == 4, "paid fixture starts with four shards")
	var normal_ids = ["enemy_max_health_120", "enemy_shield_from_health_20"] if fixture == "affixed" else []
	var special_ids = ["elemental_aegis"] if fixture == "affixed" else []
	check(arena.craft_normal_map("old_garden", tier, normal_ids, special_ids, arena.map_draft().revision).ok, "craft")
	check(arena.start_map(arena.map_draft().revision).ok, "start")
	var run_id = int(model.normal_journey().active_run.run_id)
	check(model.crafting_balance() == 0, "entry fee charged exactly once")
	if mode != "control":
		model.fail_at = model.writes + (1 if mode == "first_clear" else 2)
		var returned = arena.return_to_town(arena.world_context().revision)
		check(not returned.ok, "injected return write fails")
		check(arena.world_context().mode == "map", "failed return keeps map live")
		check(int(model.normal_journey().active_run.get("run_id", 0)) == run_id, "live map retains completion identity")
		disk_matches("failure")
		model.fail_at = -1
	if mode == "second_reload":
		arena.queue_free()
		await process_frame
		await load_arena()
		check(arena.world_context().mode == "town" and model.normal_journey().active_run.is_empty(), "reload safely abandons unfinished map")
	elif mode in ["second_retry", "second_kill"]:
		if mode == "second_kill":
			arena._begin_progress_transaction()
			kill_one()
			arena._end_progress_transaction()
			check(model.normal_journey().normal_root_kills == 1, "one kill retained")
		check(arena.return_to_town(arena.world_context().revision).ok, "return retry succeeds")
		check(model.normal_journey().pending_map_reward.is_empty(), "abandon does not award completion")
	else:
		clear_map()
		check(not arena.world_context().completion_save_pending, "completion persisted")
		var reward = model.normal_journey().pending_map_reward
		check(int(reward.get("shards", 0)) == (12 if fixture == "affixed" else tier * 4), "exact one completion receipt")
		check(int(reward.get("run_id", 0)) == run_id, "receipt belongs to original run")
		check(model.normal_journey().best_tiers.old_garden == tier, "tier advancement retained")
		check(arena.return_to_town(arena.world_context().revision).ok, "return after clear succeeds")
		var before = model.snapshot()
		check(not arena.return_to_town(arena.world_context().revision).ok and model.snapshot() == before, "duplicate return has no mutation")
	check(arena.world_context().mode == "town", "ends in town")
	check(model.crafting_balance() == 0, "no duplicate entry debit or refund")
	disk_matches("final")
	var snapshot = model.snapshot()
	arena.queue_free()
	await process_frame
	await load_arena()
	check(model.snapshot() == snapshot, "scene reload preserves exact canonical state")
	check(arena.request_safe_exit().ok and arena.quit_requests == 1, "safe exit succeeds once")
	check(arena.request_safe_exit().ok and arena.quit_requests == 1, "safe exit idempotent")
	disk_matches("safe exit")
	print("RETURN_RESULT ", fixture, "/", mode, " checks=", checks, " failures=", failures)
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
