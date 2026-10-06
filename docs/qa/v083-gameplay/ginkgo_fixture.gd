extends RefCounted
## Controlled QA only. Never called by the normal game entry point.
## Uses full real camp admissions and real death/descendant settlement.
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const ColdFixture = preload("res://tests/fixtures/v082/cold_ailment_duration_fixture.gd")

static func pause(arena: Node) -> void:
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	for unused: int in range(4): arena.hud.close_panel()

static func kill(arena: Node, enemy: Dictionary) -> void:
	if float(enemy.health) <= 0.0: return
	enemy.spawn = 0.0
	var settled := Defense.incoming_hit({"physical":1e9}, {}, enemy.shield, enemy.health, "monster")
	arena._apply_enemy_settlement(enemy, settled, Color.WHITE)

static func clear_descendants(arena: Node, exempt_id: int = 0) -> int:
	var count := 0
	for unused: int in range(8):
		arena._flush_monster_spawns()
		var living := 0
		arena._begin_progress_transaction()
		for enemy: Dictionary in arena.enemies.duplicate():
			if float(enemy.health) > 0.0 and int(enemy.id) != exempt_id:
				living += 1
				count += 1
				kill(arena, enemy)
		arena._end_progress_transaction()
		if living == 0 and arena.monster_runtime.queue.is_empty(): break
	return count

static func open_test_map(arena: Node) -> Dictionary:
	pause(arena)
	var result: Dictionary = arena.enter_town_test(arena.world_context().revision)
	if not result.ok: return result
	result = arena.craft_map("ginkgo_arcade", [], [], arena.map_draft().revision)
	if not result.ok: return result
	result = arena.start_map(arena.map_draft().revision)
	pause(arena)
	return result

static func natural_boss(arena: Node, order: Array = [2, 0, 1]) -> Dictionary:
	var marks: Dictionary = arena.world_geometry().landmarks
	for index: int in order:
		arena.player_pos = marks.camps[index].trigger_center
		arena._update_map_spawning(0.0)
	if arena._map_run.snapshot().admitted != 36: return {}
	clear_descendants(arena)
	arena.player_pos = marks.boss.trigger_center
	arena._update_map_spawning(0.0)
	for enemy: Dictionary in arena.enemies:
		if int(enemy.id) == arena._map_run.boss_id: return enemy
	return {}

static func lawful_freeze_source(path: String) -> Dictionary:
	# Separate lawful model, retained only as evidence. It grants nothing to the
	# formal map character or the native visual fixture.
	var model := Model.new()
	var result: Dictionary = ColdFixture.prepare(model, path, true, 3)
	if not result.ok: return result
	for uid: String in model.pending_items():
		var destination: Dictionary = model.first_bag_position(uid)
		if destination.is_empty(): return {"ok":false,"reason":"No lawful bag position"}
		result = model.move_item(uid, destination, model.revision(), path)
		if not result.ok: return result
	var group_id := ""
	for row: Dictionary in model.snapshot().skill_groups:
		if model.skill_group(row.id).skill_id == "frost": group_id = row.id
	if group_id.is_empty(): return {"ok":false,"reason":"Owned Frost group missing"}
	var locations: Dictionary = model.snapshot().locations
	for uid: String in locations:
		if locations[uid].kind == "skill_support" and locations[uid].group_id == group_id:
			result = model.move_item(uid, model.first_bag_position(uid), model.revision(), path)
			if not result.ok: return result
	var support: String = model.award_gem("support:frost_lock")
	if support.is_empty(): return {"ok":false,"reason":"Owned Frost Lock admission failed"}
	result = model.move_item(support, {"kind":"skill_support","group_id":group_id,"index":0}, model.revision(), path)
	if not result.ok: return result
	var cast: Dictionary = model.get_group_cast(group_id)
	if not cast.get("ok",false): return cast
	return {"ok":true,"cast":cast,"model":model.snapshot(),"stats":model.get_stats()}
