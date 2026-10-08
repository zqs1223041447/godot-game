extends "res://tests/exploration_main_flow_test.gd"
## Existing fault boundary, not a seam-change regression or playable season.
## Lawful roster/deaths; explicit runtime source/route/actor-copy fault fixtures.
const Hud = preload("res://scripts/game_hud.gd")
var probes: Array[Dictionary] = []

func payout_and_ledger() -> Dictionary:
	return {"state": arena.state.snapshot(), "runtime": arena.EncounterAdmission._snapshot(arena.monster_runtime),
		"run": arena._map_run.snapshot(), "flasks": arena.flask_runtime.snapshot(),
		"rng": str(arena.rng.state), "kills": arena.kills, "reward_kills": arena.reward_kills,
		"disk": FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)}

func prepare_last_descendant() -> Dictionary:
	arena._begin_progress_transaction()
	kill(actor(arena._map_run.boss_id))
	arena._end_progress_transaction()
	arena._flush_monster_spawns()
	var held: Dictionary = {}
	for enemy: Dictionary in arena.enemies:
		if enemy.root_id == arena._map_run.boss_id and enemy.generation > 0:
			held = enemy
			break
	if not check(not held.is_empty() and held.death_spawns.is_empty(), "Real original boss supplies terminal final-descendant fixture"): return {}
	for round_index: int in range(5):
		arena._begin_progress_transaction()
		for enemy: Dictionary in arena.enemies.duplicate():
			if enemy.id != held.id: kill(enemy)
		arena._end_progress_transaction()
		arena._flush_monster_spawns()
		if arena.enemies.size() == 1 and arena.monster_runtime.queue.is_empty(): break
	check(arena.enemies.size() == 1 and arena.enemies[0].id == held.id and arena.monster_runtime.queue.is_empty(), "Original finite lineages leave exactly one living required descendant and no queue")
	check(arena._map_run.defeated.size() == arena._map_run.admitted.size() and arena._map_run.boss_defeated and not arena._map_run.complete, "Every required root and boss dead: only the last descendant prevents completion")
	return held

func blocked_probe(enemy: Dictionary, label: String, before: Dictionary) -> void:
	check(payout_and_ledger() == before, label + ": refusal preserves authoritative ledger, reward state, FIFO, RNG and saved bytes")
	check(not arena.monster_runtime.roots[enemy.root_id].processed.has(enemy.id), label + ": death identity remains unconsumed")
	var query_before: Dictionary = observation()
	var blocked: Dictionary = arena.exploration_cleanup_hint()
	check(blocked.kind == "blocked" and not str(blocked.reason).is_empty() and observation() == query_before, label + ": HUD read-only query blocks unsettled corpse")
	check(not str(Hud.cleanup_hint_view(blocked).text).is_empty(), label + ": HUD presents the blockage")
	arena._check_map_complete()
	arena._flush_monster_spawns()
	check(not arena._map_run.complete and arena.world_context().mode == "map" and arena.enemies.size() == 1 and arena.enemies[0].id == enemy.id, label + ": no premature completion or corpse filtering")
	check(payout_and_ledger() == before, label + ": completion and filtering probes preserve ledger, rewards and queue")
	probes.append({"label": label, "hint": blocked, "corpse_id": enemy.id,
		"root_id": enemy.root_id, "processed": false,
		"ledger_sha256": JSON.stringify(before.runtime, "", true, true).sha256_text(),
		"reward_kills": arena.reward_kills, "queue_size": arena.monster_runtime.queue.size()})

func boundary_and_recovery(enemy: Dictionary) -> void:
	var record: Dictionary = arena._map_spawn_records[enemy.root_id]
	var original_key: String = enemy.map_spawn_key
	# Controlled real defense/resource settlement before the death-entry probe.
	# Cosmetic hit RNG is outside this focused refusal contract.
	var settlement: Dictionary = Defense.incoming_hit({"physical": 1e9}, {}, enemy.shield, enemy.health, "monster")
	if not accepted(settlement, "Real defense packet produces final-descendant corpse"): return
	check(arena._apply_enemy_resources(enemy, settlement) and float(enemy.health) <= 0.0, "Original resource settlement reaches death boundary")
	var before: Dictionary = payout_and_ledger()
	record.reward_route = "unsupported_fault_fixture"
	arena._finish_enemy_death(enemy, false)
	check(not enemy.death_processed and not arena._encounter_error.is_empty(), "Unsupported runtime route refuses before once-only death ledger")
	blocked_probe(enemy, "FAULT: unsupported route on final descendant", before)
	arena._finish_enemy_death(enemy, false)
	check(payout_and_ledger() == before, "Repeated refused death still preserves identity, reward and queue")
	record.reward_route = "standard"
	enemy.map_spawn_key = "invalid_source_fault_fixture"
	arena._finish_enemy_death(enemy, false)
	blocked_probe(enemy, "FAULT: mismatched source key", before)
	enemy.map_spawn_key = original_key
	arena._map_spawn_records.erase(enemy.root_id)
	arena._finish_enemy_death(enemy, false)
	blocked_probe(enemy, "FAULT: missing source record", before)
	arena._map_spawn_records[enemy.root_id] = record
	# A reconstructed flag is not proof of settlement when ledger says otherwise.
	enemy.death_processed = true
	blocked_probe(enemy, "FAULT: true actor flag without authoritative death identity", before)
	enemy.death_processed = false
	arena._finish_enemy_death(enemy, false)
	check(enemy.death_processed and arena.monster_runtime.roots[enemy.root_id].processed.has(enemy.id), "Restored original source/standard route allows exactly one legal retry")
	check(arena.state.snapshot() == before.state and arena.flask_runtime.snapshot() == before.flasks and arena.reward_kills == before.reward_kills and str(arena.rng.state) == before.rng and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH) == before.disk, "Legal descendant retry grants no ordinary XP/items/milestones/flask charge or reward RNG")
	check(arena.monster_runtime.queue.is_empty() and arena._map_run.snapshot() == before.run and arena.kills == before.kills + 1, "Legal retry consumes one death identity without extra roots or descendants")
	var after_legal: Dictionary = payout_and_ledger()
	var stale_copy: Dictionary = enemy.duplicate(true)
	stale_copy.death_processed = false
	arena.enemies.append(stale_copy)
	arena._finish_enemy_death(stale_copy, false)
	check(payout_and_ledger() == after_legal, "Legally processed duplicate identity with false actor flag cannot replay death or reward")
	check(arena.exploration_cleanup_hint().kind != "blocked", "Authoritative ledger accepts legal duplicate corpse despite stale actor flag")
	arena._flush_monster_spawns()
	check(arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty(), "Original and stale legal corpses filter normally without permanent blockage")
	arena._check_map_complete()
	check(arena.world_context().mode == "map_complete" and arena._map_run.complete and arena.exploration_cleanup_hint().kind == "complete", "Restoration converges to ordinary completion without manually clearing encounter error")
	var complete_before: Dictionary = payout_and_ledger()
	arena._finish_enemy_death(stale_copy, false)
	check(payout_and_ledger() == complete_before, "Repeated death notification after normal lineage retirement remains harmless")
	check(arena.monster_runtime.roots.is_empty(), "Existing lineage garbage collection remains unchanged")
	return_to_town("Ordinary exit after restored boundary")

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-map-death-boundary-") or FileAccess.file_exists("user://build_save.json"):
		printerr("Requires fresh isolated /tmp/godot-m1-map-death-boundary-* user data")
		quit(78)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	pause()
	arena.rng.seed = 158423086
	if not check(arena.save_build(), "Save lawful fresh formal profile"): finish(); return
	if not enter("old_garden"): finish(); return
	var last: Dictionary = prepare_last_descendant()
	if not last.is_empty(): boundary_and_recovery(last)
	finish()

func finish() -> void:
	write_json("pending-death-boundary.json", {"method": "Existing final-descendant refusal boundary; lawful default roster and defense/resources, explicit runtime route/source/actor-copy faults; not natural combat or playable seasons",
		"checks": checks + 1, "failures": failures, "failed_labels": labels, "probes": probes})
	print("MAP_PENDING_DEATH_BOUNDARY checks=%d failures=%d" % [checks, failures])
	if is_instance_valid(arena): arena.queue_free()
	quit(1 if failures else 0)
