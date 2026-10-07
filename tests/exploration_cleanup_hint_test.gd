extends "res://tests/exploration_main_flow_test.gd"
## Bounded v100 read-only guidance integration. Reuses lawful Main entry and
## original defense/death settlement; controlled runtime positions are not footage.
var group_results: Dictionary = {}
var probes: Array[Dictionary] = []

func script_values(owner: Object) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in owner.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var value: Variant = owner.get(property.name)
		if value is Object: continue
		result[property.name] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func strict_observation() -> Dictionary:
	var result: Dictionary = observation()
	result.main = script_values(arena)
	result.model = script_values(arena.state)
	result.geometry = script_values(arena._geometry)
	result.runtimes = {}
	for name: String in ["monster_runtime", "projectile_runtime", "burn_runtime", "shock_runtime", "freeze_runtime", "chill_runtime", "trap_runtime", "critical_runtime", "leech_runtime", "flask_runtime", "telegraphs", "visual_cues", "feedback_runtime"]:
		result.runtimes[name] = script_values(arena.get(name))
	return result

func hint(label: String) -> Dictionary:
	var before: Dictionary = strict_observation()
	var result: Dictionary = arena.exploration_cleanup_hint()
	check(strict_observation() == before, label + ": getter preserves snapshots, timers, queues, RNG and exact saved bytes")
	probes.append({"label": label, "hint": result.duplicate(true), "disk_sha256": FileAccess.get_sha256(arena.NORMAL_BUILD_PATH), "rng": str(arena.rng.state)})
	return result

func formal_entry(map_id: String) -> bool:
	var version_before: int = arena.state.snapshot().version
	if not accepted(arena.craft_normal_map(map_id, 1, [], [], arena.map_draft().revision), "Lawful free tier I draft: " + map_id): return false
	if not accepted(arena.start_map(arena.map_draft().revision), "Lawful formal entry: " + map_id): return false
	pause()
	check(arena.world_context().mode == "map" and not arena.world_context().test_mode and arena.monster_runtime.queue.is_empty(), "Formal map enters with original roots and no injected queue")
	check(arena.state.snapshot().version == version_before and Rules.reason(arena.state.snapshot()).is_empty(), "Entry preserves existing schema and legal character ownership")
	return true

func kill_batch_except(keep: Array[int]) -> void:
	arena._begin_progress_transaction()
	for enemy: Dictionary in arena.enemies.duplicate():
		if not keep.has(int(enemy.id)): kill(enemy)
	arena._end_progress_transaction()

func drain_except(keep: Array[int]) -> bool:
	# Original runtime lineage limits are generation <= 3, bounded per root.
	for round_index: int in range(5):
		kill_batch_except(keep)
		arena._flush_monster_spawns()
		var unwanted := false
		for enemy: Dictionary in arena.enemies:
			if float(enemy.health) > 0.0 and not keep.has(int(enemy.id)): unwanted = true
		if not unwanted and arena.monster_runtime.queue.is_empty():
			return check(true, "Actual descendant cleanup reaches bounded stopping condition in " + str(round_index + 1) + " rounds")
	return check(false, "Actual descendant cleanup stays within five bounded rounds")

func detached_check(label: String) -> void:
	var before: Dictionary = strict_observation()
	var original: Dictionary = arena.exploration_cleanup_hint()
	var edited: Dictionary = arena.exploration_cleanup_hint()
	edited.kind = "tampered"
	edited.living_count = -999
	if not edited.outposts.is_empty():
		edited.outposts[0].id = "tampered"
		edited.outposts[0].living_count = -999
		edited.outposts.append({"id": "injected"})
	if not edited.target.is_empty():
		edited.target.id = -999
		edited.target.position = Vector2(-999, -999)
	check(arena.exploration_cleanup_hint() == original and strict_observation() == before, label + ": caller mutation of nested target/outposts cannot poison queries or simulation")

func query_group() -> bool:
	if not formal_entry("broken_ruins"): return false
	var overview: Dictionary = hint("Initial full roster")
	check(overview.kind == "overview" and overview.living_count == 37 and overview.outposts.size() == 6 and overview.target.is_empty(), "Above five living actors exposes only six uncleared outposts and count")
	detached_check("Overview")
	var kept: Array[int] = []
	for enemy: Dictionary in arena.enemies:
		if int(enemy.id) != arena._map_run.boss_id and enemy.get("death_spawns", []).is_empty():
			kept.append(int(enemy.id))
			if kept.size() == 6: break
	if not check(kept.size() == 6, "Actual generated roster supplies six nonsplitting roots"): return false
	if not drain_except(kept): return false
	var six: Dictionary = hint("Six roots left")
	check(six.kind == "overview" and six.living_count == 6 and six.target.is_empty(), "Exactly six living roots remains overview")
	var removed: Dictionary = actor(kept.pop_back())
	arena._begin_progress_transaction()
	kill(removed)
	arena._end_progress_transaction()
	removed.pos = arena.player_pos
	var five: Dictionary = hint("Five roots and a nearer dead actor")
	check(five.kind == "target" and five.living_count == 5 and five.target.id != removed.id and float(removed.health) < 0.0, "Five-root threshold excludes negative-health actor even at zero distance")
	removed.health = 0.0 # Same already-processed death, no reward or ledger edit.
	var zero: Dictionary = hint("Zero-health actor retained until normal cleanup")
	check(zero.kind == "target" and zero.living_count == 5 and zero.target.id != removed.id, "Exactly zero health is excluded before the normal array cleanup")
	arena._flush_monster_spawns()
	var target: Dictionary = actor(kept[0])
	var center: Vector2 = arena.ARENA.get_center()
	arena.player_pos = center
	for id: int in kept: actor(id).pos = center + Vector2(600, 300)
	var directions: Array[String] = ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast", "here"]
	var offsets: Array[Vector2] = [Vector2(100, 0), Vector2(100, 100), Vector2(0, 100), Vector2(-100, 100), Vector2(-100, 0), Vector2(-100, -100), Vector2(0, -100), Vector2(100, -100), Vector2.ZERO]
	for index: int in range(directions.size()):
		target.pos = center + offsets[index]
		var bearing: Dictionary = hint("Bearing " + directions[index])
		check(bearing.target.id == target.id and bearing.target.position == target.pos and bearing.target.direction == directions[index], "Y-down bearing is " + directions[index] + " from current world position")
	var a: Dictionary = actor(kept[0])
	var b: Dictionary = actor(kept[1])
	a.pos = center + Vector2(100, 0)
	b.pos = center + Vector2(-100, 0)
	var stable_id: int = mini(int(a.id), int(b.id))
	check(hint("Equal squared distance").target.id == stable_id, "Exact distance tie chooses smaller actor ID")
	arena.enemies.reverse()
	check(hint("Reversed actor order").target.id == stable_id, "Exact distance tie is independent of array iteration order")
	# The bearing intentionally includes a nearby target across solid terrain.
	var wall: Rect2 = arena.world_geometry().walls[0]
	a.pos = Vector2(wall.position.x - float(a.radius) - 8.0, wall.get_center().y)
	arena.player_pos = Vector2(wall.end.x + arena.PLAYER_RADIUS + 8.0, wall.get_center().y)
	for id: int in kept:
		if id != int(a.id): actor(id).pos = arena.player_pos + Vector2(2000, 1000)
	check(not arena._terrain_visible(a.pos, arena.player_pos), "Controlled bearing probe is blocked by actual terrain")
	var blocked: Dictionary = hint("Bearing through blocking terrain")
	check(blocked.target.id == a.id and not blocked.target.has("visible") and not blocked.target.has("path"), "Nearest target is a bearing only and makes no line-of-sight or navigation claim")
	detached_check("Target")
	if not return_to_town("Return after getter probes"): return false
	check(hint("Town after target").kind == "inactive", "Town clears guidance")
	return true

func lineage_group() -> bool:
	if not formal_entry("ginkgo_arcade"): return false
	var splitter: Dictionary = {}
	var home: Dictionary = {}
	for outpost: Dictionary in arena._camp_landmarks.outposts:
		for id: int in outpost.root_ids:
			if not actor(id).get("death_spawns", []).is_empty():
				splitter = actor(id)
				home = outpost
				break
		if not splitter.is_empty(): break
	if not check(not splitter.is_empty(), "Lawful generated nonboss outpost root has original descendants"): return false
	if not drain_except([int(splitter.id)]): return false
	var root_hint: Dictionary = hint("Last splitting outpost root")
	check(root_hint.kind == "target" and root_hint.living_count == 1 and root_hint.target.root_id == splitter.id and root_hint.target.outpost_id == home.id and not root_hint.target.is_boss, "Last root retains actual outpost ownership")
	arena._begin_progress_transaction()
	kill(splitter)
	arena._end_progress_transaction()
	var waiting: Dictionary = hint("Pending-only outpost descendants")
	check(waiting.kind == "waiting" and waiting.living_count == 0 and waiting.pending_count > 0 and waiting.target.is_empty(), "Queued-only descendants report waiting without inventing an actor target")
	check(waiting.outposts.size() == 1 and waiting.outposts[0].id == home.id and waiting.outposts[0].pending_descendants == waiting.pending_count, "All cleared outposts disappear but the queued lineage keeps its original outpost uncleared")
	arena._flush_monster_spawns()
	var child: Dictionary = {}
	for enemy: Dictionary in arena.enemies:
		if int(enemy.root_id) == int(splitter.id) and int(enemy.generation) > 0: child = enemy; break
	if not check(not child.is_empty() and not child.reward_eligible, "Original monster runtime admits lawful unrewarded descendant"): return false
	if not drain_except([int(child.id)]): return false
	var spawn: Vector2 = arena._map_spawn_records[int(child.root_id)].position
	var first_pos: Vector2 = child.pos
	child.pos = arena._geometry.legal_point(arena.ARENA.get_center() + Vector2(180, 0), float(child.radius))
	arena.player_pos = child.pos + Vector2(0, 100)
	var live: Dictionary = hint("Last living descendant moved away from original spawn")
	check(child.pos != spawn and child.pos != first_pos and live.kind == "target" and live.living_count == 1 and live.target.id == child.id and live.target.root_id == splitter.id, "Living descendant is counted and targeted using its actual actor identity")
	check(live.target.position == child.pos and live.target.direction == "north" and live.target.outpost_id == home.id and live.target.outpost_name == home.name and not live.target.is_boss, "Moved child uses current position and root lineage outpost, never historical spawn position")
	check(arena.map_spawn_records().filter(func(row: Dictionary) -> bool: return int(row.root_id) == int(child.root_id))[0].position == spawn, "Controlled runtime movement leaves authoritative initial spawn record unchanged")
	detached_check("Descendant")
	var previous_ids: Array[int] = ids()
	if not accepted(arena.retry_normal_map(arena.world_context().revision), "Lawful free-tier restart through real save transaction"): return false
	pause()
	var restarted: Dictionary = hint("Restart after descendant target")
	check(restarted.kind == "overview" and restarted.living_count == 37 and restarted.pending_count == 0 and restarted.target.is_empty() and restarted.outposts.size() == 6, "Restart replaces stale descendant guidance with complete fresh roster")
	check(not previous_ids.has(int(arena.enemies[0].id)) and arena.monster_runtime.queue.is_empty(), "Restart clears old lineage and keeps monotonic actor identities")
	if not return_to_town("Return after lawful restart"): return false
	var inactive: Dictionary = hint("Town after restart")
	check(inactive.kind == "inactive" and inactive.outposts.is_empty() and inactive.target.is_empty() and inactive.living_count == 0 and inactive.pending_count == 0, "Return clears all guidance fields")
	arena.restart_run()
	check(hint("Town restart").kind == "inactive", "Town restart cannot revive old map guidance")
	return true

func settlement_group() -> bool:
	if not formal_entry("old_garden"): return false
	var root_kills_before: int = arena.state.normal_journey().normal_root_kills
	var boss: Dictionary = actor(arena._map_run.boss_id)
	if not drain_except([int(boss.id)]): return false
	var alone: Dictionary = hint("Boss alone after all other lineages clear")
	check(alone.kind == "target" and alone.living_count == 1 and alone.outposts.is_empty() and alone.target.id == boss.id and alone.target.is_boss and alone.target.outpost_id == "boss" and alone.target.outpost_name == "首领", "Boss alone gets explicit identity and is counted as a living target")
	arena._begin_progress_transaction()
	kill(boss)
	arena._end_progress_transaction()
	var queued: Dictionary = hint("Boss descendants queued only")
	check(queued.kind == "waiting" and queued.pending_count == 4 and queued.living_count == 0 and queued.target.is_empty(), "Original boss death queues its four children with no fake target")
	arena._flush_monster_spawns()
	var boss_children: Dictionary = hint("Actual four living boss descendants")
	check(boss_children.kind == "target" and boss_children.living_count == 4 and boss_children.pending_count == 0 and boss_children.target.root_id == boss.id and boss_children.target.id != boss.id and not boss_children.target.is_boss, "Actual four boss children count as live offspring with distinct actor identities")
	check(boss_children.target.outpost_id == "boss" and boss_children.target.outpost_name == "首领后代", "Boss lineage identifies a descendant without calling it the boss")
	if not drain_except([]): return false
	check(arena.reward_kills == 25 and arena.state.normal_journey().normal_root_kills - root_kills_before == 25, "Actual completion fixture rewards precisely 25 roots and never offspring")
	var model := FaultModel.new()
	if not check(model.load_build(arena.NORMAL_BUILD_PATH) and model.snapshot() == arena.state.snapshot(), "Write-failure seam loads exact legitimately earned current save"): return false
	arena._replace_build(model, arena.NORMAL_BUILD_PATH)
	model.fail_save = true
	var saved_before: PackedByteArray = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	arena._check_map_complete()
	var pending: Dictionary = hint("Real completion settlement write failure")
	check(arena._map_run.complete and arena.world_context().mode == "map_complete" and arena._normal_completion_pending and pending.kind == "settlement" and pending.target.is_empty(), "Real map completion with failed save reports settlement, not complete")
	check(FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH) == saved_before and arena.state.normal_journey().pending_map_reward.is_empty(), "Failed settlement leaves exact prior bytes and no invented completion reward")
	var before: Dictionary = strict_observation()
	var refused: Dictionary = arena.return_to_town(arena.world_context().revision)
	check(not refused.ok and arena._normal_completion_pending and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH) == saved_before, "Existing return flow remains blocked by genuine write failure")
	check(arena.exploration_cleanup_hint().kind == "settlement" and arena.state.snapshot() == before.state, "Failed return cannot replace unsettled guidance with success")
	model.fail_save = false
	if not accepted(arena._finish_normal_map(), "Existing completion transaction retries after write fault removal"): return false
	var complete: Dictionary = hint("Successful real completion settlement")
	check(complete.kind == "complete" and complete.target.is_empty() and complete.outposts.is_empty() and complete.living_count == 0 and complete.pending_count == 0 and not arena._normal_completion_pending, "Persisted completion has distinct complete guidance with no stale target")
	check(arena.state.normal_journey().pending_map_reward.shards == 4 and arena.state.normal_journey().best_tiers.old_garden == 1, "Completion uses original four-shard reward and tier unlock")
	detached_check("Complete")
	before = strict_observation()
	arena._check_map_complete()
	check(strict_observation() == before, "Repeated completion cannot duplicate save, reward, RNG or guidance state")
	if not return_to_town("Return after completed real map"): return false
	check(hint("Town after complete").kind == "inactive", "Completed map return clears completion guidance")
	return true

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v100-") or FileAccess.file_exists("user://build_save.json"):
		printerr("Requires fresh isolated /tmp/godot-m1-v100-* XDG_DATA_HOME with no existing build_save.json")
		quit(78)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	pause()
	check(arena.world_context().normal_town and not arena.world_context().test_mode, "Default Main begins in real formal town")
	if not check(arena.save_build(), "Save legitimate fresh formal build"): await finish_guidance(); return
	arena.rng.seed = 90090
	check(hint("Fresh town").kind == "inactive", "Guidance inactive before formal map")
	var selection: String = OS.get_environment("CLEANUP_GUIDANCE_GROUPS")
	for group: String in ["query", "lineage", "settlement"]:
		if not selection.is_empty() and not group in selection.split(","): continue
		var start_checks: int = checks
		var start_failures: int = failures
		var ok: bool = call(group + "_group")
		group_results[group] = {"checks": checks - start_checks, "failures": failures - start_failures, "completed": ok}
		if not ok: break
	await finish_guidance()

func finish_guidance() -> void:
	var output: String = OS.get_environment("CLEANUP_GUIDANCE_REPORT")
	if output.is_empty(): output = "res://docs/qa/v100-guidance/main-result.json"
	var result: Dictionary = {"checks": checks, "failures": failures, "failed_labels": labels, "groups": group_results, "probes": probes,
		"method": "Real formal Main entry and original bounded death/lineage transactions; controlled runtime positions; exact snapshots/RNG/save bytes; no fabricated equipment, currency, root rewards or spawn records; no natural-combat, performance or UI-clock claim"}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot open report: " + output)
		failures += 1
	else:
		file.store_string(JSON.stringify(result, "\t", true, true))
		file.close()
	print("EXPLORATION_CLEANUP_HINT checks=%d failures=%d groups=%s" % [checks, failures, JSON.stringify(group_results)])
	if is_instance_valid(arena): arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
