extends SceneTree
## Focused schema47 actual Main bridge. Earned point budget and stationary catalog
## actors are fixtures; owned gems, casts, settlement, clocks and transitions are real.
const Model = preload("res://scripts/canonical_game_state.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Policy = preload("res://scripts/combat/frost_lock_rules.gd")
const SOURCE_PREFIX: Array[String] = ["54447", "57226", "21678", "32210", "8948", "38176", "11551", "19635"]
var arena: Node
var checks := 0
var failures := 0
var sections := {}
var report := {}
var completed := false
var serial := 0
var frost_group := ""
var frost_uid := ""
var selected: Dictionary = {}
var legal_fixture: Dictionary = {}
var fixture_casts: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-9), "%s got=%s expected=%s" % [label, actual, expected])
func vector_near(actual: Vector2, expected: Vector2, label: String) -> bool:
	return check(actual.distance_to(expected) < 0.00001, "%s got=%s expected=%s" % [label, actual, expected])
func accepted(value: Dictionary, label: String) -> bool: return check(value.get("ok", false), label + ": " + JSON.stringify(value))
func watchdog() -> void: push_error("FROST_LOCK_GAMEPLAY watchdog"); quit(124)
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
	arena.rng.seed = 730073; arena.critical_runtime.reset(730073); arena._player_evasion_entropy = 50.0
	arena.hud._process(0.0)
	for unused: int in range(3): arena.hud.close_panel()
	resources()
	return check(not arena.hud.is_blocking(), "Actual Main HUD unpaused after bounded death-latch refresh")
func bag(uid: String) -> bool:
	var position: Dictionary = arena.state.first_bag_position(uid)
	return check(not position.is_empty(), "Lawful recovery bag room") and accepted(arena.state.move_item(uid, position, arena.state.revision(), arena.build_save_path), "Real owned item moved to bag")
func group(skill: String) -> String:
	for row: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(row.id).skill_id == skill: return row.id
	return ""
func fresh() -> bool:
	serial += 1
	var model := Model.new(); var candidate := model.snapshot()
	candidate.progress = {"level":119, "xp":0}; candidate.talents.class_id = 3; candidate.talents.allocated = SOURCE_PREFIX.duplicate()
	candidate.talents.normal_points = 124 - candidate.talents.allocated.size(); candidate.revision += 1
	var path := "user://frost-lock-%d.json" % serial
	if not check(model.Rules.reason(candidate).is_empty(), "Lawful connected earned-budget fixture") or not accepted(model._commit(candidate, path), "Commit lawful source fixture"): return false
	arena._replace_build(model, path)
	if not clean(): return false
	for uid: String in model.pending_items():
		if not bag(uid): return false
	if not check(model.pending_items().is_empty(), "Resolve pending recovery before reward admission"): return false
	if not accepted(model.allocate_passive("44723", 0, model.revision(), path), "Actual spell critical source allocation"): return false
	frost_group = group("frost")
	if not check(not frost_group.is_empty(), "Existing owned Frost active group"): return false
	for uid: String in model.snapshot().locations:
		var location: Dictionary = model.snapshot().locations[uid]
		if location.kind == "skill_support" and location.group_id == frost_group:
			if not bag(uid): return false
	frost_uid = model.award_gem("support:frost_lock")
	if not check(not frost_uid.is_empty(), "Actual owned schema47 Frost Lock award"): return false
	if not accepted(model.move_item(frost_uid, {"kind":"skill_support", "group_id":frost_group, "index":2}, model.revision(), path), "Actual Frost Lock support slot2 transaction"): return false
	selected = model.get_group_cast(frost_group)
	resources()
	return accepted(selected, "Owned selected Frost compiles")
func target(offset: Vector2 = Vector2(100, 0), template: String = "crawler", rarity: String = "normal", reward: bool = false) -> Dictionary:
	var context := "level_boss" if rarity == "boss" else "ordinary"
	var enemy: Dictionary = arena._spawn_monster(template, arena.player_pos + offset, context, rarity, [], reward)
	if not check(not enemy.is_empty(), "Real catalog target admitted"): return {}
	enemy.spawn = 0.0; enemy.health = 10000.0; enemy.max_health = 10000.0; enemy.shield = 0.0; enemy.max_shield = 0.0
	enemy.armour = 0.0; enemy.evasion = 0.0; enemy.evasion_entropy = 50.0; enemy.radius = 1.0; enemy.resistances = {}
	enemy.speed = 0.0; enemy.attack_timer = 1000.0; enemy.knockback = Vector2.ZERO
	enemy.shield_regen = 0.0; enemy.shield_recharge_rate = 0.0
	return enemy
func hit(enemy: Dictionary, packet: Dictionary = {}, snapshot: Dictionary = {}) -> void:
	arena._apply_damage_packet(enemy, selected.packets.projectile if packet.is_empty() else packet,
		selected.snapshot if snapshot.is_empty() else snapshot, Color.WHITE, selected.recipe.slow, {"cast_id":73,"projectile_id":731,"phase":"projectile"})
func frozen(enemy: Dictionary) -> Dictionary: return arena.freeze_runtime.state_for(int(enemy.id))
func observation() -> PackedByteArray:
	return var_to_bytes([arena.mana, arena.cooldowns, arena.group_cooldowns.snapshot(), arena.projectile_runtime.next_cast_id,
		arena.projectile_runtime.next_projectile_id, arena.critical_runtime.checkpoint(), arena.rng.state, arena.projectiles,
		arena.freeze_runtime._states, arena.freeze_runtime._last_settlement_at, arena.damage_trace, arena.enemies,
		arena.state.snapshot(), arena.state.successful_saves, FileAccess.get_file_as_bytes(arena.build_save_path)])
func equip(base: String) -> bool:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	return check(arena.state._admit_reward_item(Items.fixed_equipment(uid, base)), "Legal owned fixed equipment admitted") and accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":"weapon"}, arena.state.revision(), arena.build_save_path), "Actual weapon transaction")

func owned_cost_and_exclusion() -> void:
	if not fresh(): return
	var selected_copy := selected.duplicate(true)
	if not bag(frost_uid): return
	var plain: Dictionary = arena.state.get_group_cast(frost_group)
	if not accepted(arena.state.move_item(frost_uid, {"kind":"skill_support", "group_id":frost_group, "index":2}, arena.state.revision(), arena.build_save_path), "Relink same owned Frost Lock UID"): return
	near(selected.mana, plain.mana * 1.2, "Real model selected cost is exactly1.20")
	near(Damage.resolve(selected.packets.projectile, selected.snapshot.modifiers).total, Damage.resolve(plain.packets.projectile, plain.snapshot.modifiers).total * 0.75, "Real model primary hit is exactly0.75")
	check(selected.initial_count == 5 and selected.recipe.pierce == 2 and selected.recipe.slow == 3.0 and selected.cooldown == 4.0, "Native five pellets, two pierce, three-second slow, four-second cooldown")
	var chill: String = arena.state.award_gem("support:lingering_chill")
	if not check(not chill.is_empty(), "Real owned conflicting support"): return
	var before := observation()
	check(not arena.state.move_item(chill, {"kind":"skill_support", "group_id":frost_group, "index":1}, arena.state.revision(), arena.build_save_path).ok and observation() == before, "Lingering Chill mutual exclusion is atomic in canonical ownership")
	var other: String = group("bolt"); before = observation()
	check(not arena.state.move_item(frost_uid, {"kind":"skill_support", "group_id":other, "index":2}, arena.state.revision(), arena.build_save_path).ok and observation() == before, "Wrong skill ownership move is atomic")
	var enemy := target(); arena.mana = selected.mana - 0.000001; before = observation()
	check(not arena.cast_group(frost_group) and observation() == before, "Insufficient mana changes no debt, IDs, RNG, carriers, freeze or saves")
	arena.mana = selected.mana
	if not check(arena.cast_group(frost_group), "Exactly selected final mana admits actual cast"): return
	near(arena.mana, 0.0, "Actual cost paid once"); near(arena.group_cooldown_remaining(frost_group), 4.0, "Original debt retained")
	check(arena.projectiles.size() == 5, "Actual native five projectile carrier count")
	arena.mana = 10000.0; before = observation()
	check(not arena.cast_group(frost_group) and observation() == before, "Cooldown refusal remains fully atomic")
	if not clean(): return
	target(); arena.projectiles.resize(arena.MAX_PROJECTILES - 4); before = observation()
	check(not arena.cast_group(frost_group) and observation() == before, "Insufficient room for whole five-pellet volley is atomic")
	arena.projectiles.clear()
	legal_fixture = arena.state.snapshot(); fixture_casts = {"group_id":frost_group, "selected":selected_copy, "plain":plain, "stats":arena.state.get_stats()}
	report.owned = {"support_uid":frost_uid,"group_id":frost_group,"support_index":2,"mana":selected.mana,"cooldown":selected.cooldown}
	completed = true

func flying_snapshot() -> void:
	if not fresh() or not equip("ember_wand"): return
	selected = arena.state.get_group_cast(frost_group)
	var enemy := target(); enemy.shield = 1000.0; enemy.max_shield = 1000.0
	if not check(arena.cast_group(frost_group), "Owned cast launched before build edits"): return
	var carriers := var_to_bytes(arena.projectiles); var critical: Dictionary = arena.critical_runtime.checkpoint()
	var old_damage: float = selected.snapshot.base_damage
	if not accepted(arena.state.refund_passive("44723", arena.state.revision(), arena.build_save_path), "Refund actual allocated source while pellets fly") or not bag(frost_uid) or not equip("swift_blade"): return
	var future: Dictionary = arena.state.get_group_cast(frost_group)
	check(var_to_bytes(arena.projectiles) == carriers, "Refund, unlink and equipment change preserve in-flight carrier bytes")
	check(not future.has("freeze_profile") and not future.snapshot.has("freeze_policy") and future.snapshot.base_damage < old_damage and future.critical != selected.critical, "Next cast observes removed support, refunded source and changed gear")
	arena.tick(0.25)
	if not check(arena.damage_trace.size() == 1 and not frozen(enemy).is_empty(), "Actual in-flight old center pellet still damages and freezes"): return
	near(frozen(enemy).frozen_from, 0.25, "Freeze starts at current settlement boundary, not earlier swept contact")
	near(frozen(enemy).frozen_until, 0.85, "Old frozen support retains normal duration")
	check(arena.damage_trace[0].shield_spent > 0.0 and arena.damage_trace[0].health_lost == 0.0, "Positive actual cold shield loss alone qualifies")
	check(arena.critical_runtime.checkpoint() == critical, "Settlement uses frozen critical without a reroll")
	var statuses: Array = arena.freeze_statuses(); statuses[0].remaining_seconds = 900.0; statuses[0].position = Vector2.ZERO
	check(arena.freeze_statuses()[0].remaining_seconds < 1.0 and arena.freeze_statuses()[0].position == enemy.pos, "Main active status projection is detached")
	report.flying = {"record":arena.damage_trace[0].duplicate(true),"freeze":frozen(enemy),"cast":selected}
	completed = true

func settlement_eligibility() -> void:
	if not fresh(): return
	for rarity: String in ["normal", "magic", "rare", "boss"]:
		if not clean(): return
		var enemy := target(Vector2(100, 0), "rift_warden" if rarity == "boss" else "crawler", rarity)
		hit(enemy)
		if not check(not frozen(enemy).is_empty(), "Positive actual cold survivor freezes: " + rarity): return
		near(frozen(enemy).frozen_until, Policy.PLAYER_POLICY.duration_by_rarity[rarity], "Exact natural rarity duration: " + rarity)
		var original := frozen(enemy); hit(enemy)
		check(frozen(enemy) == original, "Same-time hit cannot refresh: " + rarity)
		arena.tick(float(original.frozen_until)); hit(enemy)
		check(frozen(enemy) == original and arena.freeze_statuses().is_empty(), "Exact thaw begins immunity and active-only UI hides it: " + rarity)
		arena.tick(1.4); hit(enemy)
		check(frozen(enemy) == original, "Later positive hit cannot refresh immunity: " + rarity)
		arena.tick(0.10000001); hit(enemy)
		check(frozen(enemy).frozen_from > original.frozen_from, "New actual hit re-freezes after complete immunity: " + rarity)
	for kind: String in ["birth", "zero", "no_cold", "secondary", "dot", "lethal", "absent_policy"]:
		if not clean(): return
		var enemy := target(); var packet: Dictionary = selected.packets.projectile.duplicate(true); var snapshot: Dictionary = selected.snapshot.duplicate(true)
		match kind:
			"birth": enemy.spawn = 0.5
			"zero": packet.base = {"cold":0.0}
			"no_cold": packet.base = {"fire":10.0}
			"secondary": packet.role = "secondary"
			"dot": packet.tags.erase("hit"); packet.tags.append("dot")
			"lethal": enemy.health = 1.0
			"absent_policy": snapshot.erase("freeze_policy")
		hit(enemy, packet, snapshot)
		check(arena.freeze_runtime.is_empty(), "Main excludes freeze for " + kind)
	completed = true

func current_boundary_and_contacts() -> void:
	if not fresh(): return
	var enemy := target(Vector2(21, 0)); enemy.radius = 10.0; enemy.attack_timer = 0.0
	if not check(arena.cast_group(frost_group), "Contact fixture uses actual Frost volley"): return
	arena.tick(0.2)
	if not check(arena.incoming_damage_trace.size() == 1 and not frozen(enemy).is_empty(), "Enemy contact already executed this frame remains after later projectile freeze"): return
	near(frozen(enemy).frozen_from, 0.2, "All pellet contacts admit only at current0.2 settlement")
	check(arena.attack_admission_trace.size() >= 1, "Existing incoming attack still uses attack admission entropy")
	var timer: float = enemy.attack_timer; var position: Vector2 = enemy.pos; var status := frozen(enemy)
	enemy.speed = 100.0; enemy.knockback = Vector2.ZERO; arena.tick(0.2)
	near(enemy.attack_timer, timer, "Frozen next-frame contact timer pauses")
	vector_near(enemy.pos, position, "Frozen autonomous pursuit pauses")
	check(arena.incoming_damage_trace.size() == 1 and frozen(enemy) == status, "Frozen actor cannot contact again and status never refreshes")
	arena.projectile_runtime.cancel_all(arena.projectiles)
	enemy.pos = arena.player_pos + Vector2(150, 0); enemy.attack_timer = 1.0; position = enemy.pos
	arena.tick(0.5)
	near(enemy.attack_timer, 0.9, "Partial thaw consumes only remaining0.1 active delta")
	vector_near(enemy.pos, position + Vector2(-3.6, 0), "Original slow0.36 remains a movement factor after partial thaw")
	check(enemy.slow > 0.0 and not arena.freeze_runtime.is_frozen(enemy.id, arena.elapsed), "Slow continues independently after freeze expires")
	# Exact tick start is authoritative even when elapsed-delta would round upward.
	if not clean(): return
	enemy = target(); arena.tick(0.1); hit(enemy)
	for unused: int in range(18): arena.tick(1.0 / 60.0)
	check(arena.freeze_runtime.is_frozen(enemy.id, arena.elapsed), "Eighteen exact real ticks retain freeze without reversed-frame assertion")
	completed = true

func telegraph_pause() -> void:
	if not fresh(): return
	var enemy := target(Vector2(90, 0), "frost_guard"); enemy.attack_timer = 0.0
	if not check(arena.cast_group(frost_group), "Freeze-before-end-tick guard cast"): return
	arena.tick(0.2)
	check(not frozen(enemy).is_empty() and arena.telegraphs.active_count() == 0, "Newly frozen enemy cannot begin a new end-tick telegraph")
	arena.projectile_runtime.cancel_all(arena.projectiles); arena.tick(0.6)
	if not check(arena.telegraphs.active_count() == 1, "Exact thaw admits next end-tick telegraph"): return
	if not clean(): return
	enemy = target(Vector2(90, 0), "frost_guard"); enemy.attack_timer = 0.0
	arena.tick(0.0); arena.tick(0.3)
	var before: Dictionary = arena.telegraphs.state_for(enemy.id)
	if not check(before.phase == "windup" and before.elapsed == 0.3, "Existing real guard windup starts and advances"): return
	hit(enemy); var status := frozen(enemy)
	arena.player_pos += Vector2(250, 100); arena.tick(0.4)
	check(arena.telegraphs.state_for(enemy.id) == before, "Freeze preserves old center, elapsed, windup, recovery and attack identity")
	arena.tick(0.4)
	var thawed: Dictionary = arena.telegraphs.state_for(enemy.id)
	near(thawed.elapsed, 0.5, "Partial-thaw scheduler advances only unfrozen0.2")
	check(thawed.center == before.center and thawed.attack_id == before.attack_id and thawed.profile == before.profile, "Partial thaw preserves locked center and authored timing")
	arena.tick(0.4)
	if not check(arena.telegraph_trace.size() == 1 and arena.telegraphs.state_for(enemy.id).phase == "recovery", "Resumed original windup resolves exactly once into original recovery"): return
	check(arena.telegraph_trace[0].center == before.center and not arena.telegraph_trace[0].inside, "Attack still aims at old center after player movement")
	check(arena.telegraph_trace[0].packet.base.keys() == ["cold"] and not arena.telegraph_trace[0].has("freeze_policy") and not arena.telegraph_trace[0].has("freeze_applied"), "Monster frost remains cold attack without player freeze metadata")
	near(status.frozen_until, 0.9, "Guard freeze starts at existing windup boundary")
	report.telegraph = {"before":before,"partial":thawed,"resolved":arena.telegraph_trace[0].duplicate(true)}
	completed = true

func continuing_resources() -> void:
	if not fresh(): return
	var enemy := target(); hit(enemy)
	if not accepted(arena.burn_runtime.apply("monster", enemy.id, 0, 20.0, 2.0, arena.elapsed, {"skill_id":"meteor","phase":"direct"}), "Existing real monster burn admitted"): return
	if not accepted(arena.shock_runtime.apply("monster", enemy.id, 0, arena.elapsed, arena.ShockRules.PLAYER_POLICY, {"skill_id":"bolt","phase":"projectile"}), "Existing shock admitted beside freeze"): return
	var health: float = enemy.health; var shock: Array = arena.shock_statuses()
	arena.tick(0.2)
	near(health - float(enemy.health), 4.0, "Frozen target's actual fire DOT continues for complete wall delta")
	check(not arena.burn_trace.is_empty() and arena.shock_statuses()[0].remaining_seconds < shock[0].remaining_seconds, "Burn settlement and shock wall-clock age continue while frozen")
	var life: float = enemy.health; hit(enemy)
	check(life - float(enemy.health) > Damage.resolve(selected.packets.projectile, selected.snapshot.modifiers).total, "Existing shock still increases cold hits on a frozen enemy")
	if not clean(): return
	enemy = target(); hit(enemy); enemy.shield = 0.0; enemy.max_shield = 100.0; enemy.shield_recharge_rate = 10.0; enemy.damage_delay = 0.0
	enemy.knockback = Vector2(190, 0); var position: Vector2 = enemy.pos
	arena.tick(0.1)
	near(enemy.shield, 1.0, "Frozen enemy energy-shield recharge continues")
	vector_near(enemy.pos, position + Vector2(19, 0), "External knockback continues through freeze")
	vector_near(enemy.knockback, Vector2(138, 0), "Original knockback decay remains520 per second")
	if not clean(): return
	var first := target(Vector2(70, -5)); var second := target(Vector2(70, 5)); first.radius = 10.0; second.radius = 10.0
	hit(first); hit(second); position = first.pos; arena.tick(0.05)
	check(first.pos.y < position.y and Vector2(first.pos).distance_to(second.pos) > 10.0 and arena.separation_candidate_visits > 0, "Frozen bodies still undergo original spatial separation")
	if not clean(): return
	arena._geometry.configure("broken_ruins", arena.ARENA)
	var wall: Rect2 = arena._geometry.snapshot().walls[0]
	arena.player_pos = Vector2(wall.position.x - 80.0, wall.get_center().y)
	enemy = target(Vector2(40, 0)); enemy.radius = 10.0; hit(enemy); enemy.knockback = Vector2(190, 0)
	arena.tick(0.3)
	check(arena._geometry.is_clear(enemy.pos, enemy.radius) and enemy.pos.x <= wall.position.x - enemy.radius, "Frozen external impulse still clips at real expanded wall")
	completed = true

func cleanup_and_capacity() -> void:
	if not fresh(): return
	arena.build_save_path = arena.NORMAL_BUILD_PATH
	if not check(arena.state.save_build(arena.build_save_path) == OK, "Canonical normal path saved for actual reward authority"): return
	var enemy := target(Vector2(100, 0), "crawler", "normal", true); hit(enemy)
	var kills: int = arena.state.normal_journey().normal_root_kills
	enemy.health = 1.0; hit(enemy)
	check(arena.kills == 1 and arena.reward_kills == 1 and arena.state.normal_journey().normal_root_kills == kills + 1 and frozen(enemy).is_empty(), "Lethal real cold hit removes freeze and rewards exactly one root death")
	var before := observation(); arena._finish_enemy_death(enemy)
	check(observation() == before, "Repeated death cannot change reward, RNG, freeze or save bytes")
	if not clean(): return
	for index: int in range(100):
		var next := target(Vector2(100 + (index % 10) * 20, -90 + (index / 10) * 20)); hit(next)
	check(arena.freeze_runtime.active_count() == 100 and arena.freeze_statuses().size() == 100, "Actual Main exposes bounded maximum100 active target statuses")
	enemy = arena.enemies[0]; arena._damage_enemy(enemy, 1000000.0, Color.WHITE); arena.enemies.erase(enemy)
	var replacement := target(Vector2(350, 0)); hit(replacement)
	check(arena.freeze_runtime.active_count() == 100 and not frozen(replacement).is_empty(), "Death immediately releases capacity for a new real target ID")
	arena.health = 0.0; arena._finish_player_death()
	check(arena.freeze_runtime.is_empty() and arena.freeze_statuses().is_empty(), "Actual player death clears every freeze/immunity state")
	if not clean(): return
	enemy = target(); hit(enemy); arena.restart_run()
	check(arena.freeze_runtime.is_empty(), "Actual restart clears freeze state")
	if not clean(): return
	enemy = target(); hit(enemy)
	if not accepted(arena.enter_normal_town(arena.world_context().revision), "Actual normal-town transition"): return
	check(arena.freeze_runtime.is_empty(), "Town entry clears statuses")
	if not accepted(arena.enter_town_test(arena.world_context().revision), "Actual test-profile transition") or not accepted(arena.start_map(arena.map_draft().revision), "Actual test-map entry"): return
	check(arena.freeze_runtime.is_empty(), "No statuses cross profile or real map entry")
	if not clean(): return
	enemy = target(); hit(enemy)
	arena.build_save_path = arena.TOWN_TEST_BUILD_PATH
	check(arena._map_run.begin(arena.MapCompiler.compile("old_garden", [], []).profile), "Valid test-map completion fixture")
	arena._world_mode = "map"; arena._map_run.boss_defeated = true; arena.enemies.clear(); arena._check_map_complete()
	check(arena._world_mode == "map_complete" and arena.freeze_runtime.is_empty(), "Actual map completion clears residual statuses")
	completed = true

func export_fixtures() -> void:
	var directory := OS.get_environment("FROST_LOCK_FIXTURE_DIR")
	if directory.is_empty() or legal_fixture.is_empty(): return
	if not check(Model.Rules.reason(legal_fixture).is_empty(), "Passing exported source/ownership fixture remains legal"): return
	if not check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create legal fixture directory"): return
	for pair: Array in [["selected.json", legal_fixture], ["selected-casts.json", fixture_casts]]:
		var file := FileAccess.open(directory + "/" + pair[0], FileAccess.WRITE)
		if not check(file != null, "Open checked fixture " + pair[0]): return
		file.store_string(JSON.stringify(pair[1], "\t", true, true)); file.close()
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v073-frost-lock-") or not OS.get_user_data_dir().begins_with(isolated + "/"): quit(78); return
	create_timer(45.0).timeout.connect(watchdog)
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	var selection := OS.get_environment("FROST_LOCK_GAMEPLAY_SECTIONS").split(",", false)
	for test: Callable in [owned_cost_and_exclusion, flying_snapshot, settlement_eligibility, current_boundary_and_contacts, telegraph_pause, continuing_resources, cleanup_and_capacity]:
		if not selection.is_empty() and not selection.has(test.get_method()): continue
		var previous := checks; var old_failures := failures; completed = false; test.call()
		check(completed, "Section returned normally: " + test.get_method())
		sections[test.get_method()] = {"checks":checks - previous, "failures":failures - old_failures}
		print("FROST_LOCK_SECTION ", test.get_method(), " ", JSON.stringify(sections[test.get_method()]))
	if failures == 0: export_fixtures()
	report.merge({"checks":checks,"failures":failures,"sections":sections,"scope":"Bounded actual Main; lawful source budget, real ownership and cast transactions, real arena.tick phase order. No historical suite, UI, packaging or production changes."})
	var output := OS.get_environment("FROST_LOCK_GAMEPLAY_REPORT")
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("FROST_LOCK_GAMEPLAY ", JSON.stringify({"checks":checks,"failures":failures,"sections":sections}))
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
