extends SceneTree
## Bounded actual-Main bridge. This script deliberately preloads only v081 files:
## its zero-source mode runs unchanged against either already-imported tree.
const Model = preload("res://scripts/canonical_game_state.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const ROUTE: Array[String] = ["54447", "57226", "21678", "32210", "8948", "27659", "37671", "27415"]
const SOURCE := "14209"
const STAT := "cold_ailment_duration_increased"
const LEVEL := 4
var arena: Node
var checks := 0
var failures := 0
var serial := 0
var sections: Dictionary = {}
var report: Dictionary = {}
var fixture_exports: Dictionary = {}
var completed := false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-9), "%s got=%.14f expected=%.14f" % [label, actual, expected])
func accepted(value: Dictionary, label: String) -> bool: return check(value.get("ok", false), label + ": " + JSON.stringify(value))
func watchdog() -> void: push_error("COLD_DURATION_GAMEPLAY watchdog"); quit(124)
func resources() -> void:
	arena._stats = arena.state.get_stats()
	for field: String in ["life_regen", "mana_regen", "shield_regen", "shield_regeneration_rate", "shield_recharge_rate"]: arena._stats[field] = 0.0
	arena._stats.max_health = 10000.0; arena._stats.max_shield = 1000.0; arena._stats.max_mana = 10000.0
	arena.health = 10000.0; arena.shield = 1000.0; arena.mana = 10000.0
func clean() -> bool:
	arena._world_mode = "town"; arena.restart_run(); arena._world_mode = "normal"
	arena.enemies.clear(); arena.monster_runtime = arena.MonsterLifecycle.new(); arena.projectile_runtime = arena.Projectiles.new()
	arena._geometry.configure("normal", arena.ARENA); arena.auto_fire = false; arena.spawn_timer = 1000.0; arena._autosave_timer = 0.0
	arena.elapsed = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._ember_projectile_clock.clear(); arena._ember_deaths.clear(); arena.burn_trace.clear()
	arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 820082; arena.critical_runtime.reset(820082); arena._player_evasion_entropy = 50.0
	seed(820082)
	arena.hud._process(0.0)
	for unused: int in range(3): arena.hud.close_panel()
	resources()
	return check(not arena.hud.is_blocking(), "Actual Main HUD unpaused after bounded refresh")
func bag(uid: String) -> bool:
	var position: Dictionary = arena.state.first_bag_position(uid)
	return check(not position.is_empty(), "Lawful recovery bag room") and accepted(arena.state.move_item(uid, position, arena.state.revision(), arena.build_save_path), "Real owned item moved to bag")
func group(skill: String) -> String:
	for row: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(row.id).skill_id == skill: return row.id
	return ""
func fresh(enabled: bool = false, route: bool = true) -> bool:
	serial += 1
	var model := Model.new()
	var path := "user://cold-duration-%d.json" % serial
	if route:
		# Dynamic load keeps the zero-source entry runnable on the old tree.
		var fixture = load("res://tests/fixtures/v082/cold_ailment_duration_fixture.gd")
		if not accepted(fixture.prepare(model, path, enabled, 3), "Shared legal level4/eight-point Witch source fixture"): return false
	else:
		var candidate := model.snapshot()
		candidate.progress = {"level":LEVEL, "xp":0}; candidate.talents.class_id = 3; candidate.talents.allocated = [ROUTE[0]]
		candidate.talents.normal_points = LEVEL + 4; candidate.revision += 1
		if not check(model.Rules.reason(candidate).is_empty(), "Legal level4 Witch zero-source budget") or not accepted(model._commit(candidate, path), "Commit legal fixture origin"): return false
	arena._replace_build(model, path)
	if not clean(): return false
	for uid: String in model.pending_items():
		if not bag(uid): return false
	if not check(model.pending_items().is_empty(), "Recovery resolved before any owned reward admission"): return false
	resources()
	return true
func source(enabled: bool) -> bool:
	var result: Dictionary = arena.state.allocate_passive(SOURCE, 0, arena.state.revision(), arena.build_save_path) if enabled else arena.state.refund_passive(SOURCE, arena.state.revision(), arena.build_save_path)
	if not accepted(result, "Actual source " + ("allocation" if enabled else "refund")): return false
	return near(float(arena.state.get_stats().get(STAT, 0.0)), 0.2 if enabled else 0.0, "Actual source stat projection")
func configure(skill: String, supports: Array, destination: String = "") -> String:
	var id := group(skill) if destination.is_empty() else destination
	if not check(not id.is_empty(), "Owned active group exists: " + skill): return ""
	if not destination.is_empty():
		var main: String = arena.state.award_gem("skill:" + skill)
		if not check(not main.is_empty(), "Independent owned main gem admitted") or not accepted(arena.state.move_item(main, {"kind":"skill_main", "group_id":id}, arena.state.revision(), arena.build_save_path), "Independent main gem placed"): return ""
	var locations: Dictionary = arena.state.snapshot().locations
	for uid: String in locations:
		if locations[uid].kind == "skill_support" and locations[uid].group_id == id:
			if not bag(uid): return ""
	for index: int in supports.size():
		var uid: String = arena.state.award_gem("support:" + str(supports[index]))
		if not check(not uid.is_empty(), "Owned unreferenced support admitted: " + str(supports[index])) or not accepted(arena.state.move_item(uid, {"kind":"skill_support", "group_id":id, "index":index}, arena.state.revision(), arena.build_save_path), "Owned support linked through real transaction"): return ""
	resources()
	return id
func target(offset: Vector2 = Vector2(100, 0), rarity: String = "normal", reward: bool = false) -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster("rift_warden" if rarity == "boss" else "crawler", arena.player_pos + offset, "level_boss" if rarity == "boss" else "ordinary", rarity, [], reward)
	if not check(not enemy.is_empty(), "Real catalog target admitted"): return {}
	enemy.spawn = 0.0; enemy.health = 10000.0; enemy.max_health = 10000.0; enemy.shield = 0.0; enemy.max_shield = 0.0
	enemy.armour = 0.0; enemy.evasion = 0.0; enemy.evasion_entropy = 50.0; enemy.radius = 1.0; enemy.resistances = {}
	enemy.speed = 0.0; enemy.attack_timer = 1000.0; enemy.knockback = Vector2.ZERO
	enemy.shield_regen = 0.0; enemy.shield_recharge_rate = 0.0
	return enemy
func hit(enemy: Dictionary, cast: Dictionary, cast_id: int = 82) -> void:
	var role := "projectile" if cast.skill_id == "frost" else "direct"
	arena._apply_damage_packet(enemy, cast.packets[role], cast.snapshot, Color.WHITE, float(cast.recipe.get("slow", 0.6)), {"cast_id":cast_id,"projectile_id":cast_id * 10,"phase":"projectile"})
func frozen(enemy: Dictionary) -> Dictionary: return arena.freeze_runtime.state_for(int(enemy.id))
func equip(base: String) -> bool:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	return check(arena.state._admit_reward_item(Items.fixed_equipment(uid, base)), "Legal catalog equipment admitted") and accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":"weapon"}, arena.state.revision(), arena.build_save_path), "Actual owned weapon equipped")
func preserve_fixture(label: String, cast: Dictionary) -> void:
	var state: Dictionary = arena.state.snapshot()
	if not check(Model.Rules.reason(state).is_empty() and arena.state.pending_items().is_empty(), "Export fixture passes whole ownership and source rules"): return
	fixture_exports[label] = state
	report.get_or_add("compiled", {})[label] = {"group_id":cast.group_id,"stats":arena.state.get_stats(),"cast":cast.duplicate(true),"preview":Preview.details(cast)}

func compiled_and_preview() -> void:
	for scenario: Dictionary in [{"label":"plain-frost","skill":"frost","links":[],"old":3.0,"new":3.6},
			{"label":"lingering-frost","skill":"frost","links":["lingering_chill"],"old":4.5,"new":5.4},
			{"label":"frost-lock","skill":"frost","links":["frost_lock"],"old":3.0,"new":3.6},
			{"label":"nova","skill":"nova","links":[]}, {"label":"ambush-nova","skill":"nova","links":["ambush"]}]:
		if not fresh(): return
		var id := configure(scenario.skill, scenario.links)
		if id.is_empty(): return
		var before: Dictionary = arena.state.get_group_cast(id)
		if not accepted(before, "Owned before cast compiles"): return
		preserve_fixture("before-" + scenario.label, before)
		if not source(true): return
		var after: Dictionary = arena.state.get_group_cast(id)
		if not accepted(after, "Owned selected cast compiles"): return
		near(float(after.snapshot.get(STAT, -1.0)), 0.2, "Actual CombatData snapshot reaches SkillCompiler")
		check(after.packets == before.packets, "Duration allocation preserves all original packets: " + scenario.label)
		check(after.mana == before.mana and after.cooldown == before.cooldown and after.initial_count == before.initial_count, "Original mana/cooldown/count remain exact: " + scenario.label)
		var role := "projectile" if scenario.skill == "frost" else "direct"
		check(Damage.resolve(after.packets[role], after.snapshot.modifiers) == Damage.resolve(before.packets[role], before.snapshot.modifiers), "Resolved hit remains exact: " + scenario.label)
		var preview := Preview.details(after); var bytes := var_to_bytes(after)
		check(Preview.details(after) == preview and var_to_bytes(after) == bytes, "Actual preview is deterministic and read-only")
		if scenario.skill == "frost":
			near(before.recipe.slow, scenario.old, "Original compiled slow: " + scenario.label)
			near(after.recipe.slow, scenario.new, "Support factor then source duration: " + scenario.label)
			check(preview.contains("现有减速时长 %.2f 秒" % float(scenario.new)), "Actual compiled duration reaches visible preview: " + scenario.label)
			var unchanged_recipe: Dictionary = after.recipe.duplicate(true); unchanged_recipe.slow = before.recipe.slow
			check(unchanged_recipe == before.recipe, "All non-duration projectile recipe fields stay exact")
			var enemy := target()
			if not check(arena.cast_group(id), "Actual selected Frost cast admitted: " + scenario.label): return
			arena.tick(0.25)
			if not check(arena.damage_trace.size() == 1, "Actual selected Frost center pellet settles once"): return
			near(enemy.slow, scenario.new, "Actual Main receives selected carrier duration: " + scenario.label)
			check(not frozen(enemy).is_empty() if scenario.links.has("frost_lock") else frozen(enemy).is_empty(), "Only linked Frost Lock adds freeze")
		else:
			check(after.recipe == before.recipe, "Nova area recipe is not a cold ailment")
			var enemy := target(Vector2(50, 0))
			if not check(arena.cast_group(id), "Actual Nova cast admitted"): return
			if scenario.links.has("ambush"): arena.tick(0.35)
			near(enemy.slow, 0.6, "Nova generic slow stays0.6 including ambush")
			check(arena.freeze_runtime.is_empty(), "Nova never gains Frost Lock")
		if scenario.label == "frost-lock":
			var expected := {"normal":0.72,"magic":0.72,"rare":0.42,"boss":0.24}
			for rarity: String in expected: near(after.freeze_profile.duration_by_rarity[rarity], expected[rarity], "Authoritative freeze preview: " + rarity)
			near(after.freeze_profile.immunity_seconds, 1.5, "Protection is never duration-scaled")
			check(preview.contains("普通/魔法 0.72 秒") and preview.contains("稀有 0.42 秒") and preview.contains("首领 0.24 秒") and preview.contains("1.50 秒不能再被冻结"), "Actual compiled freeze profile reaches all visible durations")
		preserve_fixture("after-" + scenario.label, after)
		var reloaded := Model.new()
		check(reloaded.load_build(arena.build_save_path) and reloaded.snapshot() == arena.state.snapshot() and reloaded.get_group_cast(id) == after, "Selected source and exact owned cast survive save/reload")
		if not source(false): return
		var refunded: Dictionary = arena.state.get_group_cast(id)
		check(refunded.recipe == before.recipe and refunded.get("freeze_profile", {}) == before.get("freeze_profile", {}) and refunded.packets == before.packets, "Refund restores original compiled durations and packets")
		check(reloaded.load_build(arena.build_save_path) and reloaded.snapshot() == arena.state.snapshot(), "Refund persists through original save flow")
		if failures > 0: return
	completed = true

func actual_hit_and_partial_thaw() -> void:
	if not fresh(true): return
	var id := configure("frost", ["frost_lock"])
	if id.is_empty(): return
	var cast: Dictionary = arena.state.get_group_cast(id)
	for rarity: String in ["normal", "magic", "rare", "boss"]:
		if not clean(): return
		var enemy := target(Vector2(100, 0), rarity)
		hit(enemy, cast)
		if not check(not frozen(enemy).is_empty(), "Actual positive cold survivor freezes: " + rarity): return
		near(frozen(enemy).frozen_until, cast.freeze_profile.duration_by_rarity[rarity], "Main uses compiled rarity duration: " + rarity)
		near(frozen(enemy).immune_until - frozen(enemy).frozen_until, 1.5, "Main uses fixed protection: " + rarity)
		near(enemy.slow, 3.6, "Actual hit takes scaled slow")
	if not clean(): return
	var enemy := target(); enemy.shield = 1000.0; enemy.max_shield = 1000.0
	if not check(arena.cast_group(id), "Actual owned Frost volley launched"): return
	arena.tick(0.25)
	if not check(arena.damage_trace.size() == 1 and not frozen(enemy).is_empty(), "Real in-flight center pellet settles once and freezes"): return
	near(frozen(enemy).frozen_from, 0.25, "Freeze uses current settlement time")
	near(frozen(enemy).frozen_until, 0.97, "New normal freeze lasts0.72")
	near(enemy.slow, 3.6, "Real carrier conveys3.6-second slow")
	check(arena.damage_trace[0].shield_spent > 0.0 and arena.damage_trace[0].health_lost == 0.0, "Positive actual cold shield damage still qualifies")
	arena.projectile_runtime.cancel_all(arena.projectiles)
	enemy.pos = arena.player_pos + Vector2(150, 0); enemy.attack_timer = 1.0; enemy.speed = 100.0; enemy.knockback = Vector2.ZERO
	var position: Vector2 = enemy.pos
	arena.tick(0.5)
	near(enemy.attack_timer, 1.0, "Fully frozen attack clock remains paused")
	check(enemy.pos == position, "Fully frozen autonomous movement remains paused")
	arena.tick(0.4)
	near(enemy.attack_timer, 0.82, "Partial thaw advances only0.18 active seconds")
	check(Vector2(enemy.pos).distance_to(position + Vector2(-6.48, 0)) < 0.0001, "Partial thaw retains original0.36 slow movement factor")
	near(enemy.slow, 2.7, "Slow clock continues independently during freeze")
	report.partial_thaw = {"freeze":frozen(enemy),"enemy":enemy.duplicate(true),"damage":arena.damage_trace.duplicate(true)}
	completed = true

func shared_groups_and_protection() -> void:
	if not fresh(true): return
	var first := configure("frost", ["frost_lock"])
	var second := configure("frost", ["frost_lock"], "group_000009")
	if first.is_empty() or second.is_empty(): return
	var old_cast: Dictionary = arena.state.get_group_cast(first)
	var second_cast: Dictionary = arena.state.get_group_cast(second)
	check(old_cast.main_uid != second_cast.main_uid and old_cast.group_id != second_cast.group_id, "Two owned groups have independent main UIDs")
	var enemy := target()
	hit(enemy, old_cast, 1)
	var original := frozen(enemy)
	hit(enemy, second_cast, 2)
	check(frozen(enemy) == original, "Second group shares freeze without refresh or provenance change")
	arena.tick(0.36); hit(enemy, second_cast, 3)
	check(frozen(enemy) == original, "Mid-freeze second group never extends expiry")
	arena.tick(float(original.frozen_until) - arena.elapsed); hit(enemy, second_cast, 4)
	check(frozen(enemy) == original and arena.freeze_statuses().is_empty(), "Exact thaw boundary starts shared protection")
	var before_end: float = adjacent(float(original.immune_until), -1)
	arena.tick(before_end - arena.elapsed); hit(enemy, second_cast, 5)
	check(arena.elapsed == before_end and frozen(enemy) == original, "One floating-point step before protection expiry cannot refreeze")
	arena.tick(float(original.immune_until) - arena.elapsed); hit(enemy, second_cast, 6)
	if not check(not frozen(enemy).is_empty(), "Exact protection expiry permits second-group refreeze"): return
	near(frozen(enemy).frozen_from, original.immune_until, "Refreeze starts at exact shared boundary")
	near(frozen(enemy).frozen_until - frozen(enemy).frozen_from, 0.72, "New shared freeze gets exactly0.72 seconds")
	report.shared_groups = {"first":first,"second":second,"original":original,"reapplied":frozen(enemy)}
	completed = true
func adjacent(value: float, direction: int) -> float:
	var bytes := PackedByteArray(); bytes.resize(8); bytes.encode_double(0, value)
	bytes.encode_s64(0, bytes.decode_s64(0) + direction)
	return bytes.decode_double(0)

func flying_duration_snapshot() -> void:
	for enabled_before: bool in [false, true]:
		if not fresh(enabled_before) or not equip("ember_wand"): return
		var id := configure("frost", ["frost_lock"])
		if id.is_empty(): return
		var old: Dictionary = arena.state.get_group_cast(id)
		var enemy := target()
		if not check(arena.cast_group(id), "Real cast launched before source/gear edits"): return
		var carriers := var_to_bytes(arena.projectiles); var critical: Dictionary = arena.critical_runtime.checkpoint()
		if not source(not enabled_before) or not equip("swift_blade"): return
		var future: Dictionary = arena.state.get_group_cast(id)
		check(var_to_bytes(arena.projectiles) == carriers, "Allocation/refund and equipment transaction preserve all in-flight bytes")
		check(future.snapshot.base_damage != old.snapshot.base_damage, "Next cast observes actual weapon change")
		near(future.recipe.slow, 3.0 if enabled_before else 3.6, "Future cast reads current duration source")
		arena.tick(0.25)
		if not check(arena.damage_trace.size() == 1 and not frozen(enemy).is_empty(), "Old flying cast settles after source and gear changes"): return
		near(frozen(enemy).frozen_until - frozen(enemy).frozen_from, 0.72 if enabled_before else 0.6, "Old frozen policy survives source change")
		near(enemy.slow, 3.6 if enabled_before else 3.0, "Old carrier slow survives source change")
		check(arena.critical_runtime.checkpoint() == critical, "Settlement uses frozen critical without reroll")
		var evidence := {"before":old,"future":future,"old_damage":arena.damage_trace.duplicate(true),"old_freeze":frozen(enemy)}
		if not clean(): return
		enemy = target()
		if not check(arena.cast_group(id), "Next actual cast uses changed build"): return
		arena.tick(0.25)
		if not check(not frozen(enemy).is_empty(), "Next actual cast freezes"): return
		near(frozen(enemy).frozen_until - frozen(enemy).frozen_from, 0.6 if enabled_before else 0.72, "New cast receives new freeze duration")
		near(enemy.slow, 3.0 if enabled_before else 3.6, "New cast receives new slow duration")
		evidence.new_freeze = frozen(enemy)
		report.get_or_add("flying", {})["refund" if enabled_before else "allocation"] = evidence
		if failures > 0: return
	completed = true

func combat_observation() -> Dictionary:
	return {"mana":arena.mana,"health":arena.health,"shield":arena.shield,"elapsed":arena.elapsed,
		"cooldowns":arena.cooldowns.duplicate(true),"group_cooldowns":arena.group_cooldowns.snapshot(),
		"cast_id":arena.projectile_runtime.next_cast_id,"projectile_id":arena.projectile_runtime.next_projectile_id,
		"critical_rng":arena.critical_runtime.checkpoint(),"combat_loot_rng_state":str(arena.rng.state),
		"projectiles":arena.projectiles.duplicate(true),"freeze_states":arena.freeze_runtime._states.duplicate(true),
		"freeze_last_settlement":arena.freeze_runtime._last_settlement_at,"freeze_ui":arena.freeze_statuses(),
		"damage":arena.damage_trace.duplicate(true),"combat_events":arena.combat_trace.duplicate(true),
		"trap_events":arena.trap_trace.duplicate(true),"telegraph_events":arena.telegraph_trace.duplicate(true),
		"incoming":arena.incoming_damage_trace.duplicate(true),"attack_admission":arena.attack_admission_trace.duplicate(true),
		"enemies":arena.enemies.duplicate(true),"pickups":arena.pickups.duplicate(true),
		"kills":arena.kills,"reward_kills":arena.reward_kills,"damage_total":arena.total_damage,"shots":arena.total_shots,
		"items":arena.state.snapshot().items,"locations":arena.state.snapshot().locations,"progress":arena.state.snapshot().progress,
		"journey":arena.state.normal_journey()}
func zero_source_observation() -> void:
	var records: Array = []
	for scenario: Dictionary in [{"label":"plain-frost","skill":"frost","links":[]},
			{"label":"lingering-frost","skill":"frost","links":["lingering_chill"]},
			{"label":"frost-lock","skill":"frost","links":["frost_lock"]},
			{"label":"nova","skill":"nova","links":[]}, {"label":"ambush-nova","skill":"nova","links":["ambush"]}]:
		if not fresh(false, false): return
		var id := configure(scenario.skill, scenario.links)
		if id.is_empty(): return
		var cast: Dictionary = arena.state.get_group_cast(id)
		if not accepted(cast, "Zero-source owned cast compiles"): return
		check(not arena.state.snapshot().talents.allocated.has(SOURCE) and is_zero_approx(float(arena.state.get_stats().get(STAT, 0.0))), "Zero-source baseline never allocates14209")
		var enemy := target(Vector2(50, 0) if scenario.skill == "nova" else Vector2(100, 0))
		var row := {"scenario":scenario.label,"cast":cast,"preview":Preview.details(cast),"observations":[combat_observation()]}
		if not check(arena.cast_group(id), "Zero-source actual cast admitted"): return
		row.observations.append(combat_observation())
		arena.tick(0.35 if scenario.links.has("ambush") else 0.25)
		row.observations.append(combat_observation())
		if not check(arena.damage_trace.size() == 1, "Zero-source short run settles exactly one intended hit"): return
		near(enemy.slow, 0.6 if scenario.links.has("ambush") else 0.35 if scenario.skill == "nova" else 4.5 if scenario.links.has("lingering_chill") else 3.0, "Zero-source existing actual slow remains exact")
		arena.projectile_runtime.cancel_all(arena.projectiles)
		arena.tick(0.75)
		row.observations.append(combat_observation())
		# One actual eligible rare death exercises equipment generation and its RNG.
		var reward := target(Vector2(150, 80), "rare", true); reward.health = 1.0
		hit(reward, cast, 99)
		row.observations.append(combat_observation())
		check(arena.reward_kills == 1 and arena.state.snapshot().items.size() > row.observations[0].items.size(), "Zero-source real rare death awards owned loot exactly once")
		row.global_rng_next = [randi(), randi()]
		records.append(row)
		if failures > 0: return
	report.zero_source = records
	report.zero_source_final_model = arena.state.snapshot()
	var output := OS.get_environment("COLD_DURATION_GAMEPLAY_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output.trim_suffix(".json") + ".combat.bin", FileAccess.WRITE)
		if not check(file != null, "Open exact byte-level combat observation"): return
		file.store_buffer(var_to_bytes(records)); file.close()
	completed = true

func write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "Open artifact " + path): return false
	file.store_string(JSON.stringify(value, "\t", true, true)); file.close(); return true
func export_fixtures() -> void:
	var destination := OS.get_environment("COLD_DURATION_FIXTURE_DIR")
	if destination.is_empty(): return
	if not check(DirAccess.make_dir_recursive_absolute(destination) == OK, "Create checked fixture export directory"): return
	for label: String in fixture_exports: write_json(destination.path_join(label + ".json"), fixture_exports[label])
	write_json(destination.path_join("compiled-preview.json"), report.get("compiled", {}))
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v082-cold-") or not OS.get_user_data_dir().begins_with(isolated + "/"): quit(78); return
	create_timer(60.0).timeout.connect(watchdog)
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	var selection := OS.get_environment("COLD_DURATION_GAMEPLAY_SECTIONS").split(",", false)
	var tests: Array = [zero_source_observation] if OS.get_environment("COLD_DURATION_ZERO_SOURCE") == "1" else [compiled_and_preview, actual_hit_and_partial_thaw, shared_groups_and_protection, flying_duration_snapshot]
	for test: Callable in tests:
		if not selection.is_empty() and not selection.has(test.get_method()): continue
		var previous := checks; var old_failures := failures; completed = false; test.call()
		check(completed, "Section returned normally: " + test.get_method())
		sections[test.get_method()] = {"checks":checks - previous,"failures":failures - old_failures}
		print("COLD_DURATION_SECTION ", test.get_method(), " ", JSON.stringify(sections[test.get_method()]))
		if failures > 0: break
	if failures == 0: export_fixtures()
	report.merge({"checks":checks,"failures":failures,"sections":sections,"schema":arena.state.snapshot().version,
		"scope":"Legal level4 source/ownership fixtures and bounded actual Main. No original combat mutation, historical suite, native UI, or package claim."})
	var output := OS.get_environment("COLD_DURATION_GAMEPLAY_REPORT")
	if not output.is_empty(): write_json(output, report)
	print("COLD_DURATION_GAMEPLAY ", JSON.stringify({"checks":checks,"failures":failures,"sections":sections}))
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
