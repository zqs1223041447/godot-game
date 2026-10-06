extends SceneTree
## Focused v067 actual Main coverage. Only resources, earned source budget and
## stationary catalog actors are fixtures; ownership, casts and movement are real.
const Model = preload("res://scripts/canonical_game_state.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const SOURCE_PREFIX: Array[String] = ["54447", "57226", "21678", "32210", "8948", "38176", "11551", "19635"]
const POLICY = {"enabled":true, "impulse_speed":190.0, "mana_multiplier":1.20, "direction":"toward_origin"}
var arena: Node
var checks := 0
var failures := 0
var sections := {}
var fixture_serial := 0
var completed := false


func _initialize() -> void: call_deferred("run")


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual - expected) <= maxf(0.00000001, absf(expected) * 0.000000001), "%s: %.12f / %.12f" % [label, actual, expected])


func vector_near(actual: Vector2, expected: Vector2, label: String) -> bool:
	return check(actual.is_finite() and actual.distance_to(expected) <= 0.0002, "%s: %s / %s" % [label, actual, expected])


func accepted(result: Variant, label: String) -> bool:
	return check(result is Dictionary and result.get("ok", false), label + ": " + JSON.stringify(result))


func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v067-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Inward pull gameplay requires disposable Linux XDG roots"); quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false)
	for scenario: Callable in [paired_owned_casts, current_origin_and_admission, terrain_admission,
			real_enemy_movement, frozen_ambush_build, sequential_current_alive, atomic_refusals]:
		var before := checks; completed = false
		scenario.call()
		check(completed, "Section reached its end: " + scenario.get_method())
		sections[scenario.get_method()] = checks - before
		print("INWARD_PULL_SECTION %s checks=%d failures=%d" % [scenario.get_method(), checks - before, failures])
		if failures > 0: break
	print("INWARD_PULL_GAMEPLAY_COMPLETE checks=%d failures=%d sections=%s" % [checks, failures, JSON.stringify(sections)])
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)


func fresh() -> bool:
	fixture_serial += 1
	var model := Model.new()
	var candidate := model.snapshot()
	candidate.progress = {"level":119, "xp":0}; candidate.talents.class_id = 3
	candidate.talents.allocated = SOURCE_PREFIX.duplicate()
	candidate.talents.normal_points = 124 - candidate.talents.allocated.size(); candidate.revision += 1
	var path := "user://inward-pull-%d.json" % fixture_serial
	if not check(model.Rules.reason(candidate).is_empty(), "Lawful earned-budget connected source fixture"): return false
	if not accepted(model._commit(candidate, path), "Commit source fixture"): return false
	arena._replace_build(model, path)
	if not clean(): return false
	# Reward admission requires recovery to be resolved; never repeatedly retry a
	# rejected award or spin on a blocked HUD.
	for uid: String in model.pending_items():
		if not to_bag(uid, "Resolve original pending recovery UID"): return false
	if not check(model.pending_items().is_empty(), "Recovery is empty before any new owned gem"): return false
	if not check(model.available_passives().has("44723"), "Real spell critical source node is connected"): return false
	if not accepted(model.allocate_passive("44723", 0, model.revision(), path), "Allocate source spell critical node"): return false
	resources()
	return true


func resources() -> void:
	arena._stats = arena.state.get_stats()
	for field: String in ["life_regen", "mana_regen", "shield_regen", "shield_regeneration_rate", "shield_recharge_rate"]: arena._stats[field] = 0.0
	arena._stats.max_health = 10000.0; arena._stats.max_shield = 1000.0; arena._stats.max_mana = 10000.0
	arena.health = 10000.0; arena.shield = 1000.0; arena.mana = 10000.0


func clean() -> bool:
	arena._world_mode = "town"; arena.restart_run(); arena._world_mode = "normal"
	arena.enemies.clear(); arena.monster_runtime = arena.MonsterLifecycle.new(); arena.projectile_runtime = Projectiles.new()
	arena._geometry.configure("old_garden", arena.ARENA)
	arena.auto_fire = false; arena.spawn_timer = 1000.0; arena._autosave_timer = 0.0
	arena.elapsed = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._ember_projectile_clock.clear(); arena._ember_deaths.clear(); arena.burn_trace.clear()
	arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 67067; arena.critical_runtime.reset(67067)
	arena.hud._process(0.0)
	for unused: int in range(3): arena.hud.close_panel()
	resources()
	return check(not arena.hud.is_blocking(), "Actual HUD clears after bounded death-latch refresh")


func to_bag(uid: String, label: String) -> bool:
	var position: Dictionary = arena.state.first_bag_position(uid)
	if not check(not position.is_empty(), label + " has lawful bag room"): return false
	return accepted(arena.state.move_item(uid, position, arena.state.revision(), arena.build_save_path), label)


func group(skill: String) -> String:
	for row: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(row.id).skill_id == skill: return row.id
	return ""


func equip_links(skill: String, links: Array) -> String:
	var id := group(skill)
	if not check(not id.is_empty(), "Actual active UID group exists: " + skill): return ""
	var locations: Dictionary = arena.state.snapshot().locations
	for uid: String in locations:
		if locations[uid].kind == "skill_support" and locations[uid].group_id == id:
			if not to_bag(uid, "Unlink owned support UID"): return ""
	for index: int in links.size():
		var uid: String = arena.state.award_gem("support:" + str(links[index]))
		if not check(not uid.is_empty(), "Admit owned support UID: " + str(links[index])): return ""
		if not accepted(arena.state.move_item(uid, {"kind":"skill_support", "group_id":id, "index":index}, arena.state.revision(), arena.build_save_path), "Equip support UID in real group"): return ""
	resources()
	return id


func target(point: Vector2) -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster("crawler", point, "ordinary", "normal", [], false)
	if not check(not enemy.is_empty(), "Real catalog actor admitted"): return {}
	enemy.pos = point; enemy.spawn = 0.0; enemy.health = 10000.0; enemy.max_health = 10000.0
	enemy.shield = 0.0; enemy.max_shield = 0.0; enemy.armour = 0.0; enemy.evasion = 0.0
	enemy.radius = 10.0; enemy.resistances = {}; enemy.speed = 0.0; enemy.attack_timer = 1000.0
	enemy.knockback = Vector2.ZERO; enemy.shield_regen = 0.0; enemy.shield_recharge_rate = 0.0
	return enemy


func winning_seed(snapshot: Dictionary) -> int:
	var runtime := Critical.new()
	for value: int in range(10000):
		runtime.reset(value)
		if runtime.freeze(snapshot).snapshot.get("critical_roll", {}).get("critical", false): return value
	check(false, "Source critical has a reachable winning seed")
	return 0


func observation() -> PackedByteArray:
	return var_to_bytes([arena.mana, arena.cooldowns, arena.group_cooldowns.snapshot(), arena.projectile_runtime.next_cast_id,
		arena.projectile_runtime.next_projectile_id, arena.critical_runtime.checkpoint(), arena.rng.state, arena.trap_runtime._entries,
		arena.trap_runtime._next_id, arena.trap_runtime._clock, arena.trap_trace, arena.projectiles, arena.damage_trace,
		arena.state.snapshot(), arena.state.successful_saves, FileAccess.get_file_as_bytes(arena.build_save_path)])


func paired_owned_casts() -> void:
	for skill: String in ["nova", "meteor"]:
		for ordinary: Array in [[], ["breadth", "efficiency"], ["ambush"], ["ambush", "concentrate", "quickcast"]]:
			var pair: Array = []
			for selected: bool in [false, true]:
				if not fresh(): return
				var links := ordinary.duplicate()
				if selected: links.append("inward_pull")
				var id := equip_links(skill, links)
				if id.is_empty(): return
				var compiled: Dictionary = arena.state.get_group_cast(id)
				if not check(compiled.get("ok", false), "Actual owned group compiles: " + str(links)): return
				check(compiled.group_id == id and compiled.main_uid == arena.state.skill_group(id).main_uid, "Compiled cast retains group and active UID identity")
				if selected:
					check(compiled.get("area_impulse_profile", {}) == POLICY and compiled.snapshot.get("area_impulse_policy", {}) == POLICY, "Exact profile and frozen policy are both present")
				else:
					check(not compiled.has("area_impulse_profile") and not compiled.snapshot.has("area_impulse_policy"), "Unselected actual group has no pull profile or policy")
				var origin: Vector2 = arena.player_pos + (Vector2(160, 0) if skill == "meteor" and not ordinary.has("ambush") else Vector2.ZERO)
				var center := target(origin); var nearby := target(origin + Vector2(0, 60))
				if center.is_empty() or nearby.is_empty(): return
				nearby.shield = 7.0; nearby.resistances = {"fire":0.25, "lightning":0.125}
				arena.rng.seed = 670067; arena.critical_runtime.reset(winning_seed(compiled.snapshot))
				var model_bytes := var_to_bytes(arena.state.snapshot()); var saves: int = arena.state.successful_saves
				var mana_before: float = arena.mana
				if not check(arena.cast_group(id), "Actual Main accepts owned area group"): return
				near(mana_before - arena.mana, compiled.mana, "Actual selected final resource cost is paid once")
				near(arena.group_cooldown_remaining(id), compiled.cooldown, "Actual original group cooldown is retained")
				if ordinary.has("ambush"):
					check(arena.damage_trace.is_empty() and arena.trap_statuses().size() == 1, "Combined support places one original carrier before damage")
					arena.elapsed = 0.35; arena._update_traps()
				check(arena.damage_trace.size() == 2 and arena.trap_statuses().is_empty() and arena.projectiles.is_empty(), "Exactly two admitted area hits, no residual carrier or new projectile")
				vector_near(center.knockback, Vector2.ZERO, "Exact center retains zero normalized impulse")
				vector_near(nearby.knockback, Vector2(0, -190 if selected else 190), "Only selected direction reverses around actual blast center")
				check(var_to_bytes(arena.state.snapshot()) == model_bytes and arena.state.successful_saves == saves, "Nonlethal runtime cast does not persist build changes")
				pair.append({"mana":compiled.mana, "cooldown":compiled.cooldown, "packets":compiled.packets, "recipe":compiled.recipe,
					"trace":arena.damage_trace.duplicate(true), "rng":arena.rng.state, "critical":arena.critical_runtime.checkpoint(),
					"center_health":center.health, "nearby_health":nearby.health, "nearby_shield":nearby.shield, "slow":nearby.slow})
			near(pair[1].mana, pair[0].mana * 1.20, "Pull multiplies current final mana by exactly 1.20")
			for field: String in ["cooldown", "packets", "recipe", "trace", "rng", "critical", "center_health", "nearby_health", "nearby_shield", "slow"]:
				check(pair[0][field] == pair[1][field], "Paired actual casts preserve " + field + ": " + skill + str(ordinary))
	completed = true


func current_origin_and_admission() -> void:
	for skill: String in ["nova", "meteor"]:
		if not fresh(): return
		var id := equip_links(skill, ["inward_pull"])
		if id.is_empty(): return
		var cast: Dictionary = arena.state.get_group_cast(id)
		var origin: Vector2 = arena.player_pos + (Vector2(120, 0) if skill == "meteor" else Vector2.ZERO)
		var center := target(origin); var edge := target(origin + Vector2(float(cast.recipe.radius) + 10.0, 0))
		var outside := target(origin + Vector2(float(cast.recipe.radius) + 10.01, 0))
		var born := target(origin + Vector2(20, 0)); var dead := target(origin + Vector2(25, 0)); var lethal := target(origin + Vector2(30, 35))
		if center.is_empty() or edge.is_empty() or outside.is_empty() or born.is_empty() or dead.is_empty() or lethal.is_empty(): return
		born.spawn = 0.5; dead.health = 0.0; lethal.health = 1.0
		for enemy: Dictionary in [center, edge, outside, born, dead, lethal]: enemy.knockback = Vector2(17, 19)
		if not check(arena.cast_group(id), "Real area admission cast"): return
		check(arena.damage_trace.size() == 3 and center.health < 10000.0 and edge.health < 10000.0, "Exact body-inclusive radius admits center and edge")
		vector_near(center.knockback, Vector2.ZERO, "Center overwrites previous impulse with the original zero result")
		vector_near(edge.knockback, Vector2.LEFT * 190.0, "Body-edge hit receives inward impulse from current blast origin")
		for enemy: Dictionary in [outside, born, dead]: vector_near(enemy.knockback, Vector2(17, 19), "Outside, protected and already-dead actors retain existing impulse")
		check(outside.health == 10000.0 and born.health == 10000.0 and dead.health == 0.0, "Excluded actors retain health")
		check(lethal.health <= 0.0, "Admitted lethal hit settles death")
		vector_near(lethal.knockback, (origin - Vector2(lethal.pos)).normalized() * 190.0, "Post-hit assignment is retained even when this hit killed the actor")
		if not clean(): return
		# Move after obtaining the compiled group. Nova follows this cast's feet;
		# meteor uses its selected target, not either old or current player feet.
		var old_player: Vector2 = arena.player_pos; arena.player_pos += Vector2(-220, 100)
		origin = arena.player_pos + (Vector2(120, 0) if skill == "meteor" else Vector2.ZERO)
		center = target(origin); var witness := target(origin + Vector2(0, 50))
		if center.is_empty() or witness.is_empty(): return
		if not check(arena.cast_group(id), "Moved-player cast uses currently owned group"): return
		vector_near(witness.knockback, Vector2.UP * 190.0, "Impulse uses current blast center after player movement")
		check((old_player - Vector2(witness.pos)).normalized().distance_to(Vector2.UP) > 0.1, "Old player center would produce a measurably different direction")
	completed = true


func terrain_admission() -> void:
	for links: Array in [["inward_pull"], ["ambush", "inward_pull"]]:
		if not fresh(): return
		var id := equip_links("nova", links)
		if id.is_empty(): return
		arena._geometry.configure("broken_ruins", arena.ARENA)
		var wall: Rect2 = arena._geometry.snapshot().walls[0]
		arena.player_pos = Vector2(wall.position.x - 16.0, wall.get_center().y)
		var hidden := target(Vector2(wall.end.x + 10.0, arena.player_pos.y)); var visible := target(arena.player_pos + Vector2(-30, 0))
		if hidden.is_empty() or visible.is_empty(): return
		hidden.knockback = Vector2(11, 13)
		check(not arena._terrain_visible(arena.player_pos, hidden.pos) and arena._geometry.is_clear(hidden.pos, hidden.radius), "Real wall occludes a legal body inside blast distance")
		if not check(arena.cast_group(id), "Cast beside wall is admitted"): return
		if links.has("ambush"): arena.elapsed = 0.35; arena._update_traps()
		check(hidden.health == 10000.0 and visible.health < 10000.0 and arena.damage_trace.size() == 1, "Direct or trapped pull retains per-target wall admission")
		vector_near(hidden.knockback, Vector2(11, 13), "Occluded body receives no impulse")
		vector_near(visible.knockback, Vector2.RIGHT * 190.0, "Visible body pulls toward the actual side of the wall")
	completed = true


func real_enemy_movement() -> void:
	if not fresh(): return
	var id := equip_links("nova", ["inward_pull"])
	if id.is_empty(): return
	var enemy := target(arena.player_pos + Vector2(90, 0))
	if enemy.is_empty() or not check(arena.cast_group(id), "Movement fixture receives a real cast"): return
	var start: Vector2 = enemy.pos
	arena._update_enemies(0.1)
	vector_near(enemy.pos, start + Vector2(-19, 0), "Real enemy update consumes velocity at 190 units/second")
	vector_near(enemy.knockback, Vector2(-138, 0), "Original real consumer decays at 520 units/second squared")
	arena._update_enemies(0.3)
	vector_near(enemy.pos, start + Vector2(-60.4, 0), "Second real update consumes the decayed 138 velocity")
	vector_near(enemy.knockback, Vector2.ZERO, "Original decay reaches zero without a new queue or status")
	start = enemy.pos; arena._update_enemies(0.1)
	vector_near(enemy.pos, start, "Stationary isolated actor stops once the original impulse ends")
	if not clean(): return
	var first := target(arena.player_pos + Vector2(55, -5)); var second := target(arena.player_pos + Vector2(55, 5))
	if first.is_empty() or second.is_empty() or not check(arena.cast_group(id), "Close real bodies both receive inward cast"): return
	var first_before: Vector2 = first.pos; var first_impulse: Vector2 = first.knockback
	var pure_pull: Vector2 = first_before + first_impulse * 0.05
	arena._update_enemies(0.05)
	check(float(first.pos.y) < pure_pull.y and Vector2(first.pos).distance_to(second.pos) > 10.0, "Existing mutual separation remains active while bodies converge")
	check(Vector2(first.pos).distance_to(arena.player_pos) < first_before.distance_to(arena.player_pos) and arena.separation_candidate_visits > 0, "Real spatial separation and inward motion execute together")
	vector_near(first.knockback, first_impulse.move_toward(Vector2.ZERO, 26.0), "Separation does not replace original 520 decay")
	if not clean(): return
	arena._geometry.configure("broken_ruins", arena.ARENA)
	var wall: Rect2 = arena._geometry.snapshot().walls[0]
	arena.player_pos = Vector2(wall.position.x - 16.0, wall.get_center().y)
	enemy = target(Vector2(wall.position.x - 40.0, arena.player_pos.y))
	if enemy.is_empty() or not check(arena.cast_group(id), "Wall movement receives real rightward pull"): return
	start = enemy.pos
	check(not arena._geometry.is_clear(start + Vector2(38, 0), enemy.radius), "Unclipped integration would enter the actual expanded wall")
	arena._update_enemies(0.2)
	check(arena._geometry.is_clear(enemy.pos, enemy.radius) and enemy.pos.x <= wall.position.x - enemy.radius and enemy.pos.x > start.x, "Real body-radius movement clips at wall while advancing toward origin")
	vector_near(enemy.knockback, Vector2(86, 0), "Wall collision retains original decaying impulse")
	arena._update_enemies(0.2)
	check(arena._geometry.is_clear(enemy.pos, enemy.radius), "Further impulse cannot tunnel the wall")
	vector_near(enemy.knockback, Vector2.ZERO, "Wall-limited impulse also expires through original decay")
	completed = true


func equip_fixed(base: String) -> bool:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	if not check(arena.state._admit_reward_item(Items.fixed_equipment(uid, base)), "Admit legal existing equipment " + base): return false
	return accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":"weapon"}, arena.state.revision(), arena.build_save_path), "Change real equipped weapon UID")


func frozen_ambush_build() -> void:
	for skill: String in ["nova", "meteor"]:
		if not fresh() or not equip_fixed("ember_wand"): return
		var id := equip_links(skill, ["ambush", "inward_pull", "breadth"])
		if id.is_empty(): return
		var cast: Dictionary = arena.state.get_group_cast(id)
		var origin: Vector2 = arena.player_pos; var enemy := target(origin + Vector2(50, 0))
		if enemy.is_empty(): return
		arena.critical_runtime.reset(winning_seed(cast.snapshot))
		if not check(arena.cast_group(id), "Source and equipment enhanced combined trap placed"): return
		var frozen := var_to_bytes(arena.trap_runtime._entries)
		var critical: Dictionary = arena.critical_runtime.checkpoint()
		var base_damage: float = cast.snapshot.base_damage
		if not accepted(arena.state.refund_passive("44723", arena.state.revision(), arena.build_save_path), "Refund actual spell critical source after placement"): return
		if equip_links(skill, []).is_empty() or not equip_fixed("swift_blade"): return
		var future: Dictionary = arena.state.get_group_cast(id)
		check(var_to_bytes(arena.trap_runtime._entries) == frozen, "Refund, unlink and equipment swap leave frozen carrier bytes intact")
		check(not future.has("trap_profile") and not future.has("area_impulse_profile") and not future.snapshot.has("area_impulse_policy") and future.snapshot.base_damage < base_damage, "Next cast observes removed supports and changed equipment damage")
		check(future.critical != cast.critical, "Next cast observes refunded source critical")
		arena.player_pos = origin + Vector2(400, 200)
		enemy.pos = origin + Vector2(0, 60); enemy.resistances = {"fire":0.5, "lightning":0.25}; enemy.shield = 7.0
		var expected: Dictionary = Damage.resolve(cast.packets.direct, cast.snapshot.modifiers, enemy.resistances, cast.critical.primary.multiplier)
		arena.elapsed = 0.35; arena._update_traps()
		check(arena.trap_statuses().is_empty() and arena.damage_trace.size() == 1, "Previously placed carrier still triggers exactly once")
		near(10007.0 - float(enemy.health) - float(enemy.shield), expected.total, "Frozen old offense applies current target resistance and shield")
		vector_near(enemy.knockback, Vector2.UP * 190.0, "Snapshot pull uses fixed placement center and current enemy position after player leaves")
		check(arena.critical_runtime.checkpoint() == critical and arena.damage_trace[0].critical.critical, "Old source critical stays frozen without another roll after refund")
		check(arena.trap_trace.back().position == origin and arena.damage_trace[0].phase == "trap", "Original fixed placement provenance survives build edits")
	completed = true


func sequential_current_alive() -> void:
	if not fresh(): return
	var nova := equip_links("nova", ["ambush", "inward_pull"]); var meteor := equip_links("meteor", ["ambush", "inward_pull"])
	if nova.is_empty() or meteor.is_empty(): return
	var origin: Vector2 = arena.player_pos; var first := target(origin + Vector2(60, 0)); var second := target(origin + Vector2(210, 0))
	if first.is_empty() or second.is_empty(): return
	first.health = 1.0; second.health = 1.0
	if not check(arena.cast_group(nova), "First pull trap placed"): return
	arena.player_pos = origin + Vector2(140, 0)
	if not check(arena.cast_group(meteor), "Second pull trap placed"): return
	arena.group_cooldowns.reset()
	if not check(arena.cast_group(meteor), "Third pull trap placed"): return
	var ids: Array = []
	for row: Dictionary in arena.trap_statuses(): ids.append(row.id)
	arena.enemies.reverse(); arena.elapsed = 0.35; arena._update_traps()
	var triggered: Array = []
	for event: Dictionary in arena.trap_trace:
		if event.event == "triggered": triggered.append(event)
	if not check(triggered.size() == 2, "Only two sequential carriers find currently alive targets"): return
	check(triggered[0].id == ids[0] and triggered[0].target_id == first.id and triggered[1].id == ids[1] and triggered[1].target_id == second.id, "Stable carrier order reselects current alive targets after preceding death")
	check(first.health <= 0.0 and second.health <= 0.0 and arena.trap_statuses().size() == 1 and arena.trap_statuses()[0].id == ids[2], "Third trap remains after first two kill every qualifying target")
	vector_near(first.knockback, Vector2.LEFT * 190.0, "First lethal pull preserves its own fixed origin")
	vector_near(second.knockback, Vector2.LEFT * 190.0, "Second lethal pull preserves its different fixed origin")
	var before := observation(); arena._update_traps()
	check(observation() == before, "Repeated observation neither retriggers dead targets nor reassigns consumed impulse")
	completed = true


func atomic_refusals() -> void:
	for skill: String in ["nova", "meteor"]:
		for links: Array in [["inward_pull"], ["ambush", "inward_pull"]]:
			if not fresh(): return
			var id := equip_links(skill, links)
			if id.is_empty(): return
			var cast: Dictionary = arena.state.get_group_cast(id)
			arena.mana = cast.mana - 0.000001; var before := observation()
			check(not arena.cast_group(id) and observation() == before, "Selected cost mana refusal preserves debt, IDs, RNG, carriers, build and save bytes")
			arena.mana = cast.mana
			if not check(arena.cast_group(id), "Exactly final selected mana admits cast"): return
			near(arena.mana, 0.0, "Exact selected payment leaves zero mana")
			arena.mana = 10000.0; before = observation()
			check(not arena.cast_group(id) and observation() == before, "Direct or combined cooldown refusal is fully atomic")
	completed = true
