extends SceneTree
## Focused v066 consumers: real canonical ownership and unwrapped production Main.
## Source budget/enemy life fixtures are explicit; casts, damage, rewards and
## persistence all run through their existing entry points.
const Model = preload("res://scripts/canonical_game_state.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
const SPELL_PREFIX: Array[String] = ["54447", "57226", "21678", "32210", "8948", "38176", "11551", "19635"]
const FASTER_PREFIX: Array[String] = ["50986", "39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544"]
var arena: Node
var checks := 0
var failures := 0
var sections: Dictionary = {}
var fixture_serial := 0


func _initialize() -> void: call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func near(actual: float, expected: float, label: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= maxf(0.00000001, absf(expected) * 0.000000001), "%s: %.12f / %.12f" % [label, actual, expected])


func adjacent(value: float, direction: int) -> float:
	var bytes := PackedByteArray(); bytes.resize(8); bytes.encode_double(0, value)
	bytes.encode_s64(0, bytes.decode_s64(0) + direction)
	return bytes.decode_double(0)


func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v066-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Ambush gameplay requires disposable Linux XDG roots"); quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false)
	for scenario: Callable in [actual_support_matrix, frozen_source_and_supports, atomic_admission,
			exact_boundaries_and_geometry, sequential_current_targets, old_events_settle_first,
			rewards_and_cancellation, unchanged_direct_area]:
		var before := checks
		scenario.call()
		sections[scenario.get_method()] = checks - before
		print("AMBUSH_SECTION %s checks=%d failures=%d" % [scenario.get_method(), checks - before, failures])
		if failures > 0: break
	print("AMBUSH_GAMEPLAY_COMPLETE checks=%d failures=%d sections=%s" % [checks, failures, JSON.stringify(sections)])
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)


func fresh(faster: bool = false) -> void:
	fixture_serial += 1
	var model := Model.new()
	var candidate := model.snapshot()
	candidate.progress = {"level":119, "xp":0}
	candidate.talents.class_id = 4 if faster else 3
	candidate.talents.allocated = FASTER_PREFIX.duplicate() if faster else SPELL_PREFIX.duplicate()
	candidate.talents.normal_points = 124 - candidate.talents.allocated.size()
	candidate.revision += 1
	var path := "user://ambush-%d.json" % fixture_serial
	check(model.Rules.reason(candidate).is_empty() and model._commit(candidate, path).ok, "Lawful earned-budget connected source fixture commits")
	arena._replace_build(model, path)
	clean()
	var node := "11364" if faster else "44723"
	check(model.available_passives().has(node) and model.allocate_passive(node, 0, model.revision(), path).ok, "Real available source node allocation reaches model compiler")
	combat_resources()


func combat_resources() -> void:
	arena._stats = arena.state.get_stats()
	for field: String in ["life_regen", "mana_regen", "shield_regen", "shield_regeneration_rate", "shield_recharge_rate"]: arena._stats[field] = 0.0
	arena._stats.max_health = 10000.0; arena._stats.max_shield = 1000.0; arena._stats.max_mana = 10000.0
	arena.health = 10000.0; arena.shield = 1000.0; arena.mana = 10000.0


func clean() -> void:
	arena._world_mode = "town"; arena.restart_run(); arena._world_mode = "normal"
	arena.enemies.clear(); arena.monster_runtime = arena.MonsterLifecycle.new(); arena.projectile_runtime = Projectiles.new()
	arena._geometry.configure("old_garden", arena.ARENA)
	arena.auto_fire = false; arena.spawn_timer = 1000.0; arena._autosave_timer = 0.0
	arena.elapsed = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._ember_projectile_clock.clear(); arena._ember_deaths.clear(); arena.burn_trace.clear()
	arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 66066; arena.critical_runtime.reset(66066)
	# A dead HUD has a latch. Refresh it once after restoring life, never spin on Close.
	arena.hud._process(0.0)
	for unused: int in range(3): arena.hud.close_panel()
	check(not arena.hud.is_blocking(), "Fixture restores actual HUD without an unbounded close loop")
	combat_resources()


func group(skill: String) -> String:
	for row: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(row.id).skill_id == skill: return row.id
	return ""


func equip_links(skill: String, links: Array) -> String:
	var id := group(skill)
	check(not id.is_empty(), "Actual owned active group exists: " + skill)
	var locations: Dictionary = arena.state.snapshot().locations
	for uid: String in locations:
		if locations[uid].kind == "skill_support" and locations[uid].group_id == id:
			check(arena.state.move_item(uid, arena.state.first_bag_position(uid), arena.state.revision(), arena.build_save_path).ok, "Existing support returns through real bag transfer")
	for index: int in links.size():
		var uid: String = arena.state.award_gem("support:" + str(links[index]))
		check(not uid.is_empty() and arena.state.move_item(uid, {"kind":"skill_support", "group_id":id, "index":index}, arena.state.revision(), arena.build_save_path).ok, "Owned support UID slots through real command: " + str(links[index]))
	combat_resources()
	return id


func target(offset: Vector2 = Vector2(50, 0), rewards: bool = false) -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster("crawler", arena.player_pos + offset, "ordinary", "normal", [], rewards)
	check(not enemy.is_empty(), "Real catalog root admitted")
	enemy.spawn = 0.0; enemy.health = 10000.0; enemy.max_health = 10000.0; enemy.shield = 0.0; enemy.max_shield = 0.0
	enemy.armour = 0.0; enemy.evasion = 0.0; enemy.radius = 10.0; enemy.resistances = {}
	enemy.speed = 0.0; enemy.attack_timer = 1000.0; enemy.knockback = Vector2.ZERO
	enemy.shield_regen = 0.0; enemy.shield_recharge_rate = 0.0
	return enemy


func winning_seed(snapshot: Dictionary) -> int:
	var runtime := Critical.new()
	for seed_value: int in range(10000):
		runtime.reset(seed_value)
		if runtime.freeze(snapshot).snapshot.get("critical_roll", {}).get("critical", false): return seed_value
	check(false, "Actual source critical has a reachable winning seed")
	return 0


func observation() -> PackedByteArray:
	return var_to_bytes([arena.mana, arena.cooldowns, arena.group_cooldowns.snapshot(), arena.projectile_runtime.next_cast_id,
		arena.projectile_runtime.next_projectile_id, arena.critical_runtime.checkpoint(), arena.rng.state, arena.trap_runtime._entries,
		arena.trap_runtime._next_id, arena.trap_runtime._clock, arena.trap_trace, arena.projectiles, arena.damage_trace,
		arena.state.snapshot(), arena.state.successful_saves, FileAccess.get_file_as_bytes(arena.build_save_path)])


func traps_at(at: float) -> void:
	arena.elapsed = at
	arena._update_traps()


func actual_support_matrix() -> void:
	for skill: String in ["nova", "meteor"]:
		var variants: Array = [["ambush"], ["ambush", "breadth"], ["ambush", "concentrate"]]
		variants.append(["ambush", "breadth", "shock"] if skill == "nova" else ["ambush", "breadth", "ignite"])
		variants.append(["ambush", "concentrate", "shock"] if skill == "nova" else ["ambush", "concentrate", "ember_proliferation"])
		for links: Array in variants:
			fresh(); var id := equip_links(skill, links); var compiled: Dictionary = arena.state.get_group_cast(id)
			check(compiled.ok and compiled.has("trap_profile"), "Real group compiles selected trap policy: " + str(links))
			if not compiled.ok or not compiled.has("trap_profile"): return
			var ordinary := links.duplicate(); ordinary.erase("ambush")
			var baseline: Dictionary = Compiler.compile_group(skill, arena.state.get_combat_snapshot(), ordinary)
			near(compiled.mana, baseline.mana * 1.25, "Final compiled mana applies Ambush once")
			near(compiled.cooldown, baseline.cooldown, "Source cooldown and other supports stay authoritative")
			near(Damage.resolve(compiled.packets.direct, compiled.snapshot.modifiers).total, Damage.resolve(baseline.packets.direct, baseline.snapshot.modifiers).total * 0.85, "Primary hit tradeoff composes once")
			var near_target := target(); var area_target := target(Vector2(0, float(compiled.recipe.radius) + 9.0)); var far_target := target(Vector2(500, 0))
			arena.critical_runtime.reset(winning_seed(compiled.snapshot))
			var mana_before: float = arena.mana; var cast_id: int = arena.projectile_runtime.next_cast_id
			var saved: Dictionary = arena.state.snapshot(); var saves: int = arena.state.successful_saves
			check(arena.cast_group(id), "Actual Main admits equipped trap")
			near(mana_before - arena.mana, compiled.mana, "Placement pays mana exactly once")
			near(arena.group_cooldown_remaining(id), compiled.cooldown, "Placement owns original group/main UID cooldown")
			check(arena.damage_trace.is_empty() and arena.projectiles.is_empty(), "Placement has no immediate hit or projectile")
			check(arena.critical_runtime.draws == 1 and arena.critical_runtime.events == 1 and arena.projectile_runtime.next_cast_id == cast_id + 1, "Accepted placement freezes exactly one critical roll and cast identity")
			check(arena.state.snapshot() == saved and arena.state.successful_saves == saves, "Runtime placement does not write profile progress")
			var statuses: Array = arena.trap_statuses()
			check(statuses.size() == 1 and statuses[0].position == arena.player_pos and not statuses[0].armed and statuses[0].size() == 6, "Detached bounded projection records feet placement and arming")
			statuses[0].position = Vector2.ZERO; statuses[0].remaining_seconds = 999.0
			check(arena.trap_statuses()[0].position == arena.player_pos and arena.trap_statuses()[0].remaining_seconds == 12.0, "Mutating status projection cannot mutate carrier")
			arena.tick(0.35)
			check(arena.trap_statuses().is_empty() and arena.damage_trace.size() == 2, "Real tick arms and settles both original-area targets")
			var factor: float = compiled.critical.primary.multiplier
			var expected: float = Damage.resolve(compiled.packets.direct, compiled.snapshot.modifiers, {}, factor).total
			for enemy: Dictionary in [near_target, area_target]: near(10000.0 - float(enemy.health), expected, "Actual shared critical area hit agrees with compiled source")
			near(far_target.health, 10000.0, "Meteor trap is placed at feet, not remote enemy aim")
			for record: Dictionary in arena.damage_trace:
				check(record.phase == "trap" and record.cast_id == cast_id and record.skill_id == skill and record.tags == ["hit", "spell", "area"] and record.critical.critical, "Trigger preserves original spell tags, one critical and explicit cast provenance")
			check(arena.critical_runtime.draws == 1 and arena.critical_runtime.events == 1, "Trigger and area target count never reroll critical")
			near(near_target.slow, 0.6 if skill == "nova" else 0.0, "Original skill slow survives conversion")
			if links.has("shock"):
				var shocked: Dictionary = arena.shock_runtime.status_at("monster", near_target.id, arena.elapsed)
				check(shocked.active and not arena.damage_trace[0].has("shock"), "Trap attaches Shock after its original hit without amplifying that hit")
			if links.has("ignite") or links.has("ember_proliferation"):
				var burning: Dictionary = arena.burn_runtime.status_for("monster", near_target.id)
				check(not burning.is_empty() and burning.provenance.phase == "trap" and burning.provenance.cast_id == cast_id, "Trap uses existing burn admission and retains origin")
				near(burning.raw_dps, compiled.burn_profile.roles.direct.dps * factor, "Existing burn uses frozen critical fire coefficient")
			var hit_count: int = arena.damage_trace.size(); arena._update_traps()
			check(arena.damage_trace.size() == hit_count, "Consumed trap cannot fire twice")


func frozen_source_and_supports() -> void:
	fresh(true); var id := equip_links("meteor", ["ambush", "ignite", "breadth"])
	var compiled: Dictionary = arena.state.get_group_cast(id); var enemy := target()
	arena.critical_runtime.reset(winning_seed(compiled.snapshot)); check(arena.cast_group(id), "Source-enhanced meteor trap placed")
	var frozen: PackedByteArray = var_to_bytes(arena.trap_runtime._entries)
	check(arena.state.refund_passive("11364", arena.state.revision(), arena.build_save_path).ok, "Source Faster burn refunds through actual transaction")
	var locations: Dictionary = arena.state.snapshot().locations
	for uid: String in locations:
		if locations[uid].kind == "skill_support" and locations[uid].group_id == id:
			check(arena.state.move_item(uid, arena.state.first_bag_position(uid), arena.state.revision(), arena.build_save_path).ok, "Supporting UID can be unequipped with a trap active")
	check(var_to_bytes(arena.trap_runtime._entries) == frozen and not arena.state.get_group_cast(id).has("trap_profile"), "Active carrier retains exact old packet/snapshot after refund and support removal")
	enemy.resistances.fire = 0.5; enemy.shield = 10.0
	var expected: Dictionary = Damage.resolve(compiled.packets.direct, compiled.snapshot.modifiers, enemy.resistances, compiled.critical.primary.multiplier)
	traps_at(0.35)
	near(10010.0 - float(enemy.health) - float(enemy.shield), expected.total, "Frozen offense applies current enemy resistance and shield at trigger")
	var burning: Dictionary = arena.burn_runtime.status_for("monster", enemy.id)
	check(not burning.is_empty(), "Removed Ignite still belongs to already placed trap")
	near(burning.raw_dps, compiled.burn_profile.roles.direct.dps * compiled.critical.primary.multiplier, "Refund does not recalculate frozen source burn")
	near(burning.remaining, 3.0 / 1.05, "Refund does not restore already frozen Faster burn duration")
	var before: float = enemy.health
	arena.elapsed = 0.85; arena._advance_monster_burns(arena.elapsed)
	near(before - float(enemy.health), burning.raw_dps * 0.5 * 0.5, "Actual subsequent burn applies current target fire resistance once")


func atomic_admission() -> void:
	fresh(); var nova := equip_links("nova", ["ambush"]); var meteor := equip_links("meteor", ["ambush"])
	var compiled: Dictionary = arena.state.get_group_cast(nova)
	arena.mana = compiled.mana - 0.000001; var before := observation()
	check(not arena.cast_group(nova) and observation() == before, "Insufficient mana changes no debt, IDs, RNG, traps, model or save bytes")
	arena.mana = compiled.mana
	check(arena.cast_group(nova), "Exact final mana admits placement"); near(arena.mana, 0.0, "Exact payment leaves zero mana")
	arena.mana = 10000.0; before = observation()
	check(not arena.cast_group(nova) and observation() == before, "Cooldown refusal is fully atomic")
	check(arena.cast_group(meteor), "Second skill shares the same trap budget")
	arena.group_cooldowns.reset(); check(arena.cast_group(nova), "Third placement fills global capacity")
	arena.group_cooldowns.reset(); before = observation()
	check(not arena.cast_group(meteor) and observation() == before and arena.trap_statuses().size() == 3, "Fourth cross-group trap refuses before resources, critical and cast identity")
	var bolt := group("bolt")
	check(arena.cast_group(bolt) and not arena.projectiles.is_empty(), "Three traps do not occupy ordinary projectile capacity")
	clean(); arena.projectiles.resize(arena.MAX_PROJECTILES)
	for index: int in arena.MAX_PROJECTILES: arena.projectiles[index] = {}
	check(arena.cast_group(nova) and arena.projectiles.size() == arena.MAX_PROJECTILES and arena.trap_statuses().size() == 1, "Full projectile budget does not block an independent trap")
	arena.projectiles.clear()
	clean(); arena._geometry.configure("broken_ruins", arena.ARENA)
	arena.player_pos = arena._geometry.snapshot().walls[0].get_center(); before = observation()
	check(not arena.cast_group(nova) and observation() == before, "Illegal wall placement rejects before any admission side effects")
	arena.player_pos = arena._geometry.legal_point(arena.player_pos, arena.PLAYER_RADIUS)
	check(arena.cast_group(nova) and arena.trap_statuses()[0].position == arena.player_pos, "Geometry-approved player feet accept a trap without relocating it")


func exact_boundaries_and_geometry() -> void:
	fresh(); var id := equip_links("nova", ["ambush"]); var enemy := target(Vector2(80, 0))
	check(arena.cast_group(id), "Boundary trap placed")
	traps_at(adjacent(0.35, -1)); check(arena.damage_trace.is_empty(), "One ULP before arm cannot trigger")
	traps_at(0.35); check(arena.damage_trace.size() == 1, "Exact arming includes exact 70 plus body boundary")
	clean(); enemy = target(Vector2(80.01, 0)); check(arena.cast_group(id), "Outer trigger fixture placed")
	traps_at(0.35); check(arena.damage_trace.is_empty() and arena.trap_statuses().size() == 1, "Inside explosion radius but outside trigger plus body does not fire")
	enemy.pos = arena.player_pos + Vector2(80, 0); enemy.spawn = 0.1
	arena._update_traps(); check(arena.damage_trace.is_empty(), "Born-protected target cannot trigger")
	enemy.spawn = 0.0; arena._update_traps(); check(arena.damage_trace.size() == 1, "Current birth completion qualifies a waiting armed trap")
	clean(); check(arena.cast_group(id), "Expiry trap placed without a target")
	traps_at(adjacent(12.0, -1)); check(arena.trap_statuses().size() == 1, "One ULP before expiry remains active")
	enemy = target(); traps_at(12.0)
	check(arena.trap_statuses().is_empty() and arena.damage_trace.is_empty() and enemy.health == 10000.0, "Exact expiry wins over current target and never explodes")
	clean(); arena._geometry.configure("broken_ruins", arena.ARENA)
	var wall: Rect2 = arena._geometry.snapshot().walls[0]
	arena.player_pos = wall.position + Vector2(-arena.PLAYER_RADIUS - 0.1, 100)
	enemy = target(); enemy.pos = wall.position + Vector2(wall.size.x + 0.1, 100); enemy.radius = 30.0
	check(arena.player_pos.distance_to(enemy.pos) <= 70.0 + enemy.radius and not arena._terrain_visible(arena.player_pos, enemy.pos), "Wall fixture is in trigger radius and truly occluded")
	check(arena.cast_group(id), "Valid feet beside actual map wall admits trap")
	traps_at(0.35); check(arena.damage_trace.is_empty() and arena.trap_statuses().size() == 1, "LOS blocks trigger even with body overlap")
	var visible := target(Vector2(-30, 0)); arena._update_traps()
	check(visible.health < 10000.0 and enemy.health == 10000.0, "Visible trigger fires original AoE, which independently respects the wall")


func sequential_current_targets() -> void:
	fresh(); var nova := equip_links("nova", ["ambush"]); var meteor := equip_links("meteor", ["ambush"])
	var origin: Vector2 = arena.player_pos; var a := target(Vector2(60, 0)); var b := target(Vector2(210, 0)); a.health = 1.0; b.health = 1.0
	check(arena.cast_group(nova), "First sequential trap placed")
	arena.player_pos = origin + Vector2(140, 0)
	check(arena.cast_group(meteor), "Second sequential trap placed")
	arena.group_cooldowns.reset(); check(arena.cast_group(meteor), "Third sequential trap placed")
	var ids: Array = []
	for row: Dictionary in arena.trap_statuses(): ids.append(row.id)
	# Reverse enemy storage: nearest choice and trap identity do not depend on it.
	arena.enemies.reverse(); traps_at(0.35)
	var triggers: Array = []
	for event: Dictionary in arena.trap_trace:
		if event.event == "triggered": triggers.append(event)
	check(triggers.size() == 2 and triggers[0].id == ids[0] and triggers[1].id == ids[1], "Trap IDs settle sequentially in stable placement order")
	if triggers.size() == 2: check(triggers[0].target_id == a.id and triggers[1].target_id == b.id, "Later trap reselects current live target after first trap kills its former nearest")
	check(a.health <= 0.0 and b.health <= 0.0 and arena.trap_statuses().size() == 1 and arena.trap_statuses()[0].id == ids[2], "Third trap remains when preceding hits removed every qualifying target")
	clean(); a = target(Vector2(40, 0)); b = target(Vector2(-40, 0)); arena.enemies.reverse()
	check(arena.cast_group(nova), "Equal-distance target fixture placed"); traps_at(0.35)
	check(arena.trap_trace.back().target_id == mini(a.id, b.id), "Exact nearest tie uses stable smallest monster ID")


func old_events_settle_first() -> void:
	fresh(); var id := equip_links("nova", ["ambush"])
	for event_kind: String in ["projectile", "burn"]:
		clean(); var enemy := target(Vector2(40, 0)); enemy.health = 1.0
		check(arena.cast_group(id), "Trap waits while existing event is outstanding")
		if event_kind == "projectile":
			var basic: Dictionary = arena.state.get_basic_cast()
			arena._shoot(arena.player_pos, Vector2.RIGHT, basic.packets.projectile, Color.WHITE, 0, 0.0, 600.0, {"snapshot":basic.snapshot})
		else:
			check(arena.burn_runtime.apply("monster", enemy.id, 0, 100.0, 3.0, 0.0).ok, "Earlier ordinary burn admitted")
		arena.tick(0.35)
		check(enemy.health <= 0.0 and arena.trap_statuses().size() == 1, "Old %s kills before tick-end trap qualification" % event_kind)
		for record: Dictionary in arena.damage_trace: check(record.phase != "trap", "No trap hit is preplanned before existing event settlement")


func rewards_and_cancellation() -> void:
	fresh(); var id := equip_links("nova", ["ambush"])
	# Normal journey admission intentionally requires its canonical path, still
	# isolated underneath this test's disposable XDG data root.
	arena.build_save_path = arena.NORMAL_BUILD_PATH
	check(arena.state.save_build(arena.build_save_path) == OK, "Real normal profile path admits root progression")
	var enemy := target(Vector2(50, 0), true); enemy.health = 1.0
	var old_kills: int = arena.state.normal_journey().normal_root_kills
	check(arena.cast_group(id), "Reward-eligible real root has a placed trap"); arena.tick(0.35)
	check(arena.kills == 1 and arena.reward_kills == 1 and arena.state.normal_journey().normal_root_kills == old_kills + 1, "Trap routes one root death through existing progression and reward counters")
	var saved := observation(); arena._finish_enemy_death(enemy); arena._update_traps()
	check(observation() == saved, "Repeated root death and consumed trap create no extra RNG, save or rewards")
	var reopened := Model.new()
	check(reopened.load_build(arena.build_save_path) and reopened.snapshot() == arena.state.snapshot(), "Real root progress persists through existing save path")
	clean(); check(arena.cast_group(id), "Pause fixture placed"); arena.hud.open_panel("pause")
	saved = observation(); var at: float = arena.elapsed; arena._process(1.0)
	check(arena.elapsed == at and observation() == saved, "Actual paused process does not age, fire or expire traps")
	arena.hud.close_panel()
	arena.health = 0.0; arena._finish_player_death()
	check(arena.trap_runtime.is_empty(), "Actual player death clears carriers")
	clean(); check(arena.cast_group(id), "Restart fixture placed"); arena.restart_run()
	check(arena.trap_runtime.is_empty(), "Actual restart clears carriers")
	clean(); check(arena.cast_group(id), "Town fixture placed")
	check(arena.enter_normal_town(arena.world_context().revision).ok and arena.trap_runtime.is_empty(), "Actual town transition clears carriers")
	clean(); check(arena.cast_group(id), "Profile fixture placed")
	var replacement := Model.new(); check(replacement.save_build("user://ambush-replacement.json") == OK, "Replacement profile saved")
	arena._replace_build(replacement, "user://ambush-replacement.json")
	check(arena.trap_runtime.is_empty(), "Actual profile replacement clears carriers independently of restart")
	# Completion entry uses the real completion function; only finished map state is fixture data.
	clean(); id = equip_links("nova", ["ambush"]); check(arena.cast_group(id), "Map-complete fixture placed")
	arena.build_save_path = arena.TOWN_TEST_BUILD_PATH
	check(arena._map_run.begin(arena.MapCompiler.compile("old_garden", [], []).profile), "Valid test map profile admitted")
	arena._world_mode = "map"; arena._map_run.boss_defeated = true
	arena._check_map_complete()
	check(arena._world_mode == "map_complete" and arena.trap_runtime.is_empty(), "Actual map completion clears remaining traps")


func unchanged_direct_area() -> void:
	fresh()
	for skill: String in ["nova", "meteor"]:
		clean(); var id := equip_links(skill, []); var enemy := target()
		var compiled: Dictionary = arena.state.get_group_cast(id)
		arena.critical_runtime.reset(winning_seed(compiled.snapshot))
		check(arena.cast_group(id) and arena.trap_statuses().is_empty() and arena.damage_trace.size() == 1, "Unselected original area skill remains immediate")
		check(arena.damage_trace[0].cast_id == 0 and arena.damage_trace[0].phase == "direct", "Old area calls retain original zero cast ID and direct phase")
		near(10000.0 - float(enemy.health), Damage.resolve(compiled.packets.direct, compiled.snapshot.modifiers, {}, compiled.critical.primary.multiplier).total, "Unselected original area hit arithmetic remains exact")
