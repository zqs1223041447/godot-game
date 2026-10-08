extends "res://tests/exploration_main_flow_test.gd"
## Explicit unit/fault fixtures on a lawful Main roster. Rewardless roots and
## unknown actors here are injected assertions, NOT playable seasonal content.
const RunState = preload("res://scripts/world/map_run_state.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const Hud = preload("res://scripts/game_hud.gd")

func registration_fixtures() -> void:
	var roots: Array[Dictionary] = []
	var boss: Dictionary = {}
	for enemy: Dictionary in arena.enemies:
		var copy := enemy.duplicate(true)
		copy.reward_eligible = false
		if int(copy.id) == arena._map_run.boss_id: boss = copy
		else: roots.append(copy)
	var run_state = RunState.new()
	check(run_state.begin(arena._map_run.profile) and run_state.register_initial_group(roots, boss), "UNIT FIXTURE: initial required identities can be registered without standard rewards")
	for enemy: Dictionary in roots: check(run_state.record_death(enemy), "UNIT FIXTURE: rewardless registered root advances completion")
	check(run_state.record_death(boss) and not run_state.record_death(boss), "UNIT FIXTURE: rewardless boss identity advances exactly once")
	check(run_state.check_complete(0, 0), "UNIT FIXTURE: required completion has no payout dependency")
	run_state = RunState.new()
	run_state.begin(arena._map_run.profile)
	check(run_state.register_group(roots), "UNIT FIXTURE: group admission is independent of standard reward eligibility")
	for enemy: Dictionary in roots: run_state.record_death(enemy)
	check(run_state.register_root(boss, true), "UNIT FIXTURE: deferred boss admission is independent of standard reward eligibility")
	run_state = RunState.new()
	run_state.begin(arena._map_run.profile)
	check(run_state.register_root(roots[0]), "UNIT FIXTURE: single root admission is independent of standard reward eligibility")
	var invalid: Dictionary = roots[1].duplicate(true)
	invalid.reward_eligible = null
	check(not run_state.register_root(invalid), "Malformed eligibility type still rejects admission")
	check(not run_state.owns_lineage(0) and not run_state.owns_lineage(str(roots[0].id)), "Membership requires a positive typed admitted identity")

func rewardless_fixture() -> void:
	var enemy: Dictionary = {}
	for candidate: Dictionary in arena.enemies:
		if int(candidate.id) != arena._map_run.boss_id and candidate.death_spawns.is_empty():
			enemy = candidate
			break
	if not check(not enemy.is_empty(), "Unit fixture selects a real nonsplitting registered root"): return
	# Runtime-only payout flag mutation: no invented route, item, currency or save.
	enemy.reward_eligible = false
	enemy.health = 0.0
	var state_before: Dictionary = arena.state.snapshot()
	var flasks_before: Dictionary = arena.flask_runtime.snapshot()
	var disk_before := FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	var rng_before: int = arena.rng.state
	var rewards_before: int = arena.reward_kills
	var progress_before: int = arena._map_run.defeated.size()
	arena._finish_enemy_death(enemy, false)
	check(enemy.death_processed and arena._map_run.defeated.size() == progress_before + 1 and arena._map_run.defeated.has(enemy.id), "UNIT FIXTURE: Main records required root death even when payout eligibility is false")
	check(arena.state.snapshot() == state_before and arena.flask_runtime.snapshot() == flasks_before and arena.reward_kills == rewards_before, "UNIT FIXTURE: no standard XP, items, milestones, rewarded-kill count or flask charge")
	check(arena.rng.state == rng_before and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH) == disk_before, "UNIT FIXTURE: no reward RNG or save write")
	var runtime_before: Dictionary = arena.EncounterAdmission._snapshot(arena.monster_runtime)
	var run_before: Dictionary = arena._map_run.snapshot()
	var kills_before: int = arena.kills
	arena._finish_enemy_death(enemy, false)
	var stale_copy := enemy.duplicate(true)
	stale_copy.death_processed = false
	arena._finish_enemy_death(stale_copy, false)
	check(arena.monster_runtime.roots[enemy.root_id].processed.has(enemy.id) and arena.EncounterAdmission._snapshot(arena.monster_runtime) == runtime_before and arena._map_run.snapshot() == run_before and arena.kills == kills_before, "UNIT FIXTURE: original and stale copied corpse cannot repeat ledger, progress or death count")
	check(arena.state.snapshot() == state_before and arena.flask_runtime.snapshot() == flasks_before and arena.rng.state == rng_before and arena.reward_kills == rewards_before, "UNIT FIXTURE: repeated death cannot duplicate any ordinary reward")

func required_descendants() -> void:
	arena._begin_progress_transaction()
	for enemy: Dictionary in arena.enemies.duplicate(): kill(enemy)
	arena._end_progress_transaction()
	var hint_before: Dictionary = arena.exploration_cleanup_hint()
	var fifo: Array[Dictionary] = arena.monster_runtime.queue.duplicate(true)
	check(hint_before.kind == "waiting" and hint_before.living_count == 0 and hint_before.pending_count == fifo.size() and not fifo.is_empty(), "All required roots dead: HUD counts the actual mandatory FIFO queue")
	arena._check_map_complete()
	check(not arena._map_run.complete and arena.world_context().mode == "map" and arena.monster_runtime.queue == fifo, "Required queued descendants block completion without draining or changing FIFO")
	var staged = Runtime.new()
	arena.EncounterAdmission._restore(staged, arena.EncounterAdmission._snapshot(arena.monster_runtime))
	var drained: Dictionary = Admission.drain(staged, arena._map_run.profile, 1, arena.ARENA)
	check(drained.ok and drained.enemies.size() == 1 and drained.enemies[0].root_id == fifo[0].root_id and drained.enemies[0].parent_id == fifo[0].parent_id and drained.enemies[0].template_id == fifo[0].template and staged.queue == fifo.slice(1), "UNIT FIXTURE: existing admission drains only the FIFO head at one free slot")
	arena._flush_monster_spawns()
	var living: Dictionary = arena.exploration_cleanup_hint()
	check(living.living_count == arena.enemies.size() and living.pending_count == arena.monster_runtime.queue.size(), "HUD counts every real mandatory living descendant")
	arena._check_map_complete()
	check(not arena._map_run.complete, "Required living descendants block completion")
	for round_index: int in range(4):
		arena._begin_progress_transaction()
		for enemy: Dictionary in arena.enemies.duplicate(): kill(enemy)
		arena._end_progress_transaction()
		arena._flush_monster_spawns()
		if arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty(): break
	check(arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty(), "Existing finite required lineages terminate within bounded rounds")

func unknown_membership_fixtures() -> void:
	var unknown: Dictionary = arena.monster_runtime.create_root("crawler", arena.wave, arena.player_pos)
	arena.enemies.append(unknown)
	var before: Dictionary = observation()
	var blocked: Dictionary = arena.exploration_cleanup_hint()
	check(blocked.kind == "blocked" and not str(blocked.reason).is_empty() and observation() == before, "FAULT FIXTURE: unknown live actor produces a read-only blocked HUD instead of being ignored")
	check(not str(Hud.cleanup_hint_view(blocked).text).is_empty(), "Faulted membership has a visible HUD explanation")
	arena._check_map_complete()
	check(not arena._map_run.complete and arena.world_context().mode == "map" and not arena._encounter_error.is_empty(), "FAULT FIXTURE: unknown live root prevents otherwise-ready completion")
	unknown.health = 0.0
	check(arena.exploration_cleanup_hint().kind == "blocked", "FAULT FIXTURE: unprocessed unknown corpse cannot silently escape membership validation")
	arena._flush_monster_spawns()
	check(arena.enemies.size() == 1 and arena.enemies[0].id == unknown.id and not arena._map_run.complete, "FAULT FIXTURE: cleanup cannot discard unknown corpse before reporting invalid membership")
	arena.enemies.clear()
	arena.monster_runtime.roots.erase(unknown.id)
	arena._encounter_error = ""
	arena.monster_runtime.queue.append({"root_id": unknown.id})
	before = observation()
	blocked = arena.exploration_cleanup_hint()
	check(blocked.kind == "blocked" and observation() == before, "FAULT FIXTURE: unknown queued lineage blocks HUD without consuming queue or RNG")
	arena._check_map_complete()
	check(not arena._map_run.complete and not arena._encounter_error.is_empty() and arena.monster_runtime.queue.size() == 1, "FAULT FIXTURE: unknown queued lineage prevents otherwise-ready completion")
	arena._flush_monster_spawns()
	check(arena.monster_runtime.queue.size() == 1 and arena.enemies.is_empty(), "FAULT FIXTURE: unknown request cannot be consumed into an unregistered descendant")
	arena.monster_runtime.queue.clear()
	arena._encounter_error = ""

func exit_cleanup() -> void:
	arena._check_map_complete()
	check(arena.world_context().mode == "map_complete", "Only known required lineages cleared allows completion")
	if not return_to_town("Exit after explicit semantic fixtures"): return
	if not accepted(arena.claim_normal_rewards(arena.world_context().revision), "Claim original completed-map reward"): return
	if not accepted(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision), "Fresh original draft for pending exit check"): return
	if not accepted(arena.start_map(arena.map_draft().revision), "Fresh original map for pending exit check"): return
	pause()
	arena._begin_progress_transaction()
	kill(actor(arena._map_run.boss_id))
	arena._end_progress_transaction()
	check(arena.monster_runtime.queue.size() == 4, "Original boss queues its real four descendants before exit")
	if not return_to_town("Abandonment with real pending descendants"): return
	check(arena.monster_runtime.roots.is_empty() and arena._map_run.admitted.is_empty() and arena._map_run.boss_id == 0 and arena.exploration_cleanup_hint().kind == "inactive", "Town exit clears mandatory membership, lineage ledger, pending queue and HUD")

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-map-seams-fixture-") or FileAccess.file_exists("user://build_save.json"):
		printerr("Requires fresh isolated /tmp/godot-m1-map-seams-fixture-* user data")
		quit(78)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	pause()
	arena.rng.seed = 158423086
	if not check(arena.save_build(), "Save lawful fresh formal character"): finish(); return
	if not enter("old_garden"): finish(); return
	registration_fixtures()
	rewardless_fixture()
	required_descendants()
	unknown_membership_fixtures()
	exit_cleanup()
	finish()

func finish() -> void:
	write_json("seam-fixtures.json", {"method": "Explicit unit/fault semantic fixtures on a lawful Main roster; NOT playable seasons or natural-combat evidence", "checks": checks + 1, "failures": failures, "failed_labels": labels})
	print("MAP_COMPLETION_REWARD_SEAMS checks=%d failures=%d" % [checks, failures])
	if is_instance_valid(arena): arena.queue_free()
	quit(1 if failures else 0)
