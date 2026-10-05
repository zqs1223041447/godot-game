extends SceneTree
## One bounded real-main fixture. Legacy mode runs this same harness against
## the complete independently frozen v57 project, never current dependencies.
const Model = preload("res://scripts/canonical_game_state.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Shock = preload("res://scripts/combat/shock_rules.gd")
const STAT := "damage_taken_from_mana_before_life"
var arena: Node
var checks := 0
var failures := 0
var sections: Dictionary = {}
var route: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func near(actual: float, expected: float, label: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-9), label + " got=%s expected=%s" % [actual, expected])

func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear(); arena.particles.clear(); arena.floating_text.clear(); arena.rings.clear()
	arena.monster_runtime = arena.MonsterLifecycle.new(); arena.telegraphs = arena.TelegraphRuntime.new()
	arena.projectile_runtime = arena.Projectiles.new(); arena.feedback_runtime = arena.FeedbackRuntime.new()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.leech_runtime.clear(); arena._sync_flasks(true)
	arena.damage_trace.clear(); arena.incoming_damage_trace.clear(); arena.burn_trace.clear(); arena.combat_trace.clear(); arena.attack_admission_trace.clear()
	arena.telegraph_trace.clear(); arena.event_counts.clear(); arena._ember_deaths.clear(); arena._ember_projectile_clock.clear()
	arena.group_cooldowns.reset(); arena.elapsed = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._burn_immunity_until = 0.0; arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena.auto_fire = false; arena.spawn_timer = 1000.0; arena._autosave_timer = 0.0; arena.wave = 1
	arena._world_mode = "normal"; arena._geometry.configure("old_garden", arena.ARENA)
	arena._stats = arena.state.get_stats()
	for field: String in ["life_regen", "mana_regen", "shield_regen", "shield_recharge_rate", "armour", "evasion", "fire_resistance", "cold_resistance", "lightning_resistance", "chaos_resistance"]:
		arena._stats[field] = 0.0
	arena._stats.max_health = 1000.0; arena._stats.max_shield = 1000.0; arena._stats.max_mana = 1000.0
	arena.health = 1000.0; arena.shield = 0.0; arena.mana = 100.0; arena.kills = 0; arena.reward_kills = 0
	arena.total_damage = 0.0; arena.total_shots = 0; arena.attack_timer = 0.0
	arena._refresh_leech_caps()
	arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 58058; arena.critical_runtime.reset(58058); arena._player_evasion_entropy = 50.0
	# HUD is process-disabled for determinism; revive its existing death latch
	# once, exactly as its ordinary next frame would, before closing any panel.
	arena.hud._process(0.0)
	arena.hud.close_panel()
	check(not arena.hud.is_blocking(), "Controlled live fixture is not paused")
	for id: String in arena.Data.SKILLS: arena.cooldowns[id] = 0.0

func readonly() -> Dictionary:
	return {"rng": arena.rng.state, "critical": arena.critical_runtime.checkpoint(), "model": arena.state.snapshot(),
		"saves": arena.state.successful_saves, "bytes": FileAccess.get_file_as_bytes(arena.build_save_path)}

func atomic() -> PackedByteArray:
	return var_to_bytes([readonly(), arena.health, arena.mana, arena.shield, arena.invulnerable, arena.damage_delay,
		arena.incoming_damage_trace, arena.burn_trace, arena.group_cooldowns.snapshot(), arena.cooldowns,
		arena.leech_runtime.snapshot(), arena.feedback_runtime._pending, arena.feedback_runtime._visible,
		arena.projectiles, arena.projectile_runtime.next_cast_id, arena.shock_runtime.statuses(arena.elapsed)])

func target(offset: Vector2 = Vector2(80, 0), rewarding: bool = false) -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster("brute", arena.player_pos + offset, "ordinary", "", [], rewarding)
	enemy.spawn = 0.0; enemy.health = 1000.0; enemy.max_health = 1000.0
	enemy.shield = 0.0; enemy.max_shield = 0.0; enemy.armour = 0.0; enemy.evasion = 0.0; enemy.radius = 1.0
	enemy.resistances = {}; enemy.speed = 0.0; enemy.attack_timer = 1000.0
	enemy.shield_regen = 0.0; enemy.shield_recharge_rate = 0.0
	return enemy

func shortest_route() -> Array:
	var start: String = SourceTree.Data.start_for_class(3)
	var paths := {start: [start]}
	var queue: Array[String] = [start]
	var index := 0
	while index < queue.size():
		var current: String = queue[index]; index += 1
		for id: String in SourceTree.Data.adjacency(current):
			var node: Dictionary = SourceTree.Data.node(id)
			if paths.has(id) or node.type in ["mastery", "start"] or node.source.get("isProxy", false) or node.source.get("isBlighted", false): continue
			if SourceTree.node_effect(id, 0, 35).status != "full": continue
			paths[id] = paths[current] + [id]
			if id == "34098": return paths[id]
			queue.append(id)
	return []

func legal_allocation() -> void:
	var start := checks
	route = shortest_route()
	check(route.size() == 8, "Witch reaches actual source 34098 in seven spent points")
	if route.is_empty(): return
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level": 3, "xp": 0}; candidate.talents.class_id = 3
	candidate.talents.allocated = [route[0]]; candidate.talents.normal_points = 7; candidate.revision += 1
	check(arena.state.Rules.reason(candidate).is_empty() and arena.state._commit(candidate, arena.build_save_path).ok, "Lawful level-three root fixture commits")
	for id: String in route.slice(1):
		check(arena.state.available_passives().has(id) and arena.state.allocate_passive(id, 0, arena.state.revision(), arena.build_save_path).ok, "Real guarded source allocation " + id)
	check(arena.state.talent_points == 0, "Seven real allocation transactions spend seven earned points")
	near(arena.state.get_stats()[STAT], 0.4, "Actual source stat is forty percent")
	var before := readonly()
	var profile: Dictionary = arena.state.get_mana_guard_profile()
	check(profile.ok and profile.enabled, "Actual model enables read-only mana profile")
	near(profile.fraction, 0.4, "Actual profile retains source fraction")
	profile.fraction = 0.9
	near(arena.state.get_mana_guard_profile().fraction, 0.4, "Returned profile is detached")
	check(readonly() == before, "Profile reads change neither model/save nor combat RNG")
	var loaded: Variant = Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.snapshot() == arena.state.snapshot(), "Real allocated source survives disk reload")
	near(loaded.get_mana_guard_profile().fraction, 0.4, "Reload derives same source consumer")
	sections.legal_source_allocation = checks - start

func actual_hits() -> void:
	var start := checks
	for scenario: Dictionary in [
		{"shield": 0.0, "mana": 100.0, "shield_spent": 0.0, "mana_spent": 40.0, "life": 60.0},
		{"shield": 25.0, "mana": 100.0, "shield_spent": 25.0, "mana_spent": 30.0, "life": 45.0},
		{"shield": 100.0, "mana": 100.0, "shield_spent": 100.0, "mana_spent": 0.0, "life": 0.0},
		{"shield": 0.0, "mana": 10.0, "shield_spent": 0.0, "mana_spent": 10.0, "life": 90.0}]:
		clean(); arena.shield = scenario.shield; arena.mana = scenario.mana
		var before := readonly(); var leech: Dictionary = arena.leech_runtime.snapshot()
		check(arena.hit_player_components({"physical": 100.0}), "Actual main admits controlled hundred-damage hit")
		var hit: Dictionary = arena.incoming_damage_trace.back()
		near(hit.damage_total, 100.0, "Mitigated damage total remains unchanged")
		near(hit.shield_spent, scenario.shield_spent, "Shield pays before mana")
		near(hit.mana_spent, scenario.mana_spent, "Mana pays only post-shield fraction bounded by current pool")
		near(hit.health_lost, scenario.life, "Mana spending is excluded from health_lost")
		near(arena.mana, scenario.mana - scenario.mana_spent, "Main writes remaining mana exactly once")
		near(arena.health, 1000.0 - scenario.life, "Main writes actual remaining life")
		arena.feedback_runtime.flush_target("player", 0)
		var feedback: Array = arena.damage_feedback()
		check(feedback.size() == 1, "Actual incoming hit publishes one feedback receipt")
		if not feedback.is_empty(): near(feedback[0].amount, scenario.shield_spent + scenario.life, "Float text includes shield/life loss only")
		check(readonly() == before and arena.leech_runtime.snapshot() == leech, "Incoming guard hit adds no save, leech or combat RNG")
	# Hand-calculated mixed mitigation; the guard is after armour/resistances/Shock.
	clean(); arena._stats.armour = 1000.0; arena._stats.fire_resistance = 0.5
	arena._stats.cold_resistance = 0.25; arena._stats.lightning_resistance = 0.75; arena._stats.chaos_resistance = 0.1
	arena.shield = 20.0; arena.mana = 1000.0
	check(arena.shock_runtime.apply("player", 0, 1, 0.0, Shock.ENEMY_POLICY).ok, "Live player Shock fixture admitted")
	check(arena.hit_player_components({"physical": 100.0, "fire": 100.0, "cold": 100.0, "lightning": 100.0, "chaos": 100.0}), "Actual mixed incoming hit admitted")
	var hit: Dictionary = arena.incoming_damage_trace.back()
	# The published source defense profile implements elemental resistances;
	# chaos remains unmitigated, so a fixture-only chaos_resistance is inert.
	var mitigated := (100.0 / 3.0 + 50.0 + 75.0 + 25.0 + 100.0) * 1.15
	near(hit.damage_total, mitigated, "Armour, supported elemental resistances and Shock applied once")
	near(hit.mana_spent, (mitigated - 20.0) * 0.4, "Mixed result diverted once after all defenses and shield")
	near(hit.health_lost, (mitigated - 20.0) * 0.6, "Mixed residual life is sixty percent")
	sections.hit_mitigation_and_feedback = checks - start

func rejected_hits_and_casts() -> void:
	var start := checks
	clean(); arena.invulnerable = 1.0
	var before := atomic()
	check(not arena.hit_player_components({"physical": 100.0}) and atomic() == before, "Invulnerable main hit changes no resources, clocks, traces or RNG")
	clean(); arena._stats.evasion = 1000000000.0
	before = atomic()
	check(not arena.hit_player_components({"physical": 100.0}, 0, ["hit", "attack"]), "Deterministic evasion rejects incoming attack")
	check(atomic() == before and arena.attack_admission_trace.size() == 1 and not arena.attack_admission_trace[0].hit, "Evaded attack advances only existing admission entropy/receipt, never spends mana")
	for components: Variant in [{"physical": -1.0}, {"physical": NAN}, {"physical": true}, {"unknown": 10.0}, []]:
		clean(); before = atomic()
		check(not arena.hit_player_components(components) and atomic() == before, "Invalid incoming component rejects atomically " + str(components))
	for fraction: Variant in [NAN, -0.1, 1.1, true]:
		clean(); arena._stats[STAT] = fraction; before = atomic()
		check(not arena.hit_player_components({"physical": 100.0}) and atomic() == before, "Invalid guard profile rejects hit atomically")
	clean(); arena.mana = 20.0
	check(arena.hit_player_components({"physical": 100.0}), "Real guard hit exhausts mana before cast test")
	near(arena.mana, 0.0, "Damage and skills share exhausted mana")
	var group_id := ""
	for group: Dictionary in arena.state.snapshot().skill_groups:
		var cast: Dictionary = arena.state.get_group_cast(group.id)
		if cast.get("ok", false) and float(cast.mana) > 0.0: group_id = group.id; break
	check(not group_id.is_empty(), "Owned real skill group has positive mana cost")
	before = atomic()
	check(not arena.cast_group(group_id) and atomic() == before, "Actual owned cast rejects at zero mana without resource, cooldown, projectile, model or RNG mutation")
	sections.atomic_rejections_and_cast = checks - start

func burn_entry_and_death() -> void:
	var start := checks
	for shield_value: float in [0.0, 25.0, 100.0]:
		clean(); arena.shield = shield_value
		check(arena.burn_runtime.apply("player", 0, 1, 100.0, 3.0, 0.0).ok, "Real player burn attaches")
		var before := readonly(); arena.elapsed = 1.0; arena._advance_player_burn(1.0)
		var burn: Dictionary = arena.burn_trace.back().settlement
		near(burn.shield_spent, shield_value, "Burn pays shield before mana")
		near(burn.mana_spent, (100.0 - shield_value) * 0.4, "Burn shares same forty-percent diversion")
		near(burn.health_lost, (100.0 - shield_value) * 0.6, "Burn excludes mana from life loss")
		near(arena.mana, 100.0 - float(burn.mana_spent), "Burn main writes same live mana pool")
		arena.feedback_runtime.flush_target("player", 0)
		near(arena.damage_feedback()[0].amount, shield_value + float(burn.health_lost), "Burn feedback excludes mana diversion")
		check(readonly() == before and arena.leech_runtime.is_empty(), "Burn diversion introduces no RNG, saves or leech")
	clean(); arena._stats.fire_resistance = 0.5; arena._stats.armour = 10000.0
	check(arena.shock_runtime.apply("player", 0, 1, 0.0, Shock.ENEMY_POLICY).ok, "Burn resistance control has active Shock")
	check(arena.burn_runtime.apply("player", 0, 1, 100.0, 3.0, 0.0).ok, "Burn clock fixture attaches")
	arena.invulnerable = 0.32; arena.tick(0.5)
	near(arena.mana, 100.0 - 100.0 * 0.18 * 0.5 * 0.4, "Actual tick clips hit immunity then resistance then mana, ignoring armour/Shock")
	near(arena.health, 1000.0 - 100.0 * 0.18 * 0.5 * 0.6, "Only nonimmune positive-width burn affects life")
	near(arena.burn_runtime.status_for("player", 0).remaining, 2.5, "Immunity advances original burn clock without deferring damage")
	clean(); arena.health = 10.0; arena.mana = 5.0
	check(arena.burn_runtime.apply("player", 0, 1, 100.0, 3.0, 0.0).ok, "Lethal burn attaches")
	var saves: int = arena.state.successful_saves
	arena.elapsed = 1.0; arena._advance_player_burn(1.0)
	check(not arena.alive and arena.health == 0.0 and arena.mana == 0.0, "Mana shortage spills to life and actual burn kills")
	var lethal: Dictionary = arena.burn_trace.back().settlement
	near(lethal.mana_spent, 5.0, "Lethal burn spends available mana exactly")
	near(lethal.health_lost, 10.0, "Lethal burn reports bounded actual life")
	near(lethal.overkill, 85.0, "Lethal burn overkill excludes mana and actual life")
	check(arena.burn_runtime.is_empty() and arena.leech_runtime.is_empty() and arena.state.successful_saves == saves + 1, "Existing death clears effects and performs only existing death save")
	var dead := atomic(); arena._advance_player_burn(2.0)
	check(atomic() == dead, "Dead player cannot pay the same burn again")
	sections.burn_immunity_and_death = checks - start

func shared_recovery_and_monsters() -> void:
	var start := checks
	clean(); arena.mana = 40.0
	check(arena.hit_player_components({"physical": 100.0}) and arena.mana == 0.0, "Shared recovery begins after actual mana depletion")
	var enemy := target()
	check(not enemy.has("mana") and not enemy.has(STAT), "Natural monster gains no mana resource or player guard stat")
	var attack: Dictionary = Compiler.compile_basic(Combat.snapshot({"damage": 100.0, "max_health": 1000.0, "max_mana": 1000.0, "attack_mana_leech": 0.1}, []))
	arena._apply_damage_packet(enemy, attack.packets.projectile, attack.snapshot, Color.WHITE)
	var hit: Dictionary = arena.damage_trace.back()
	near(hit.health_lost, 100.0, "Player guard never diverts natural monster loss")
	near(hit.leech.mana, 10.0, "Existing outgoing leech uses actual shield/life damage")
	near(arena.mana, 0.0, "Leech admission is not instant recovery")
	var before := readonly()
	arena._advance_leech(0.25)
	near(arena.mana, 5.0, "Existing leech recovers the guard-depleted live mana pool")
	arena.leech_runtime.clear(); arena._stats.mana_regen = 10.0; arena.tick(0.5)
	near(arena.mana, 10.0, "Normal regeneration restores the same resource pool")
	arena._stats.mana_regen = 0.0
	var flask_slot := ""
	for slot: Dictionary in arena.state.flask_slots():
		if slot.resource == "mana": flask_slot = slot.slot_id; break
	check(not flask_slot.is_empty() and arena.use_flask(flask_slot).ok, "Actual equipped mana flask starts recovery after guard spending")
	var rate: float = arena.flask_runtime.snapshot().active_by_resource.mana.rate
	arena.tick(0.3)
	near(arena.mana, 10.0 + rate * 0.3, "Flask tick writes same live mana used by guard and casting")
	check(readonly() == before, "Nonlethal recovery and guard affect no persistent model or RNG")
	arena.invulnerable = 0.0; var available: float = arena.mana
	check(arena.hit_player_components({"physical": 100.0}), "Future hit consumes replenished mana")
	near(arena.mana, available - minf(available, 40.0), "Recovered mana is immediately available for later diversion")
	sections.shared_recovery_and_natural_monsters = checks - start

func equipment_change() -> void:
	var start := checks
	clean(); var model: RefCounted = arena.state
	var equipped: Dictionary = model.equipped_items()
	check(not equipped.is_empty(), "Legal source fixture retains equipped actual items")
	if not equipped.is_empty():
		var slot: String = equipped.keys()[0]; var uid: String = equipped[slot]
		for equipped_slot: String in equipped:
			var candidate_uid: String = equipped[equipped_slot]
			if model.snapshot().items[candidate_uid].definition_id == "equipment:azure_charm":
				slot = equipped_slot; uid = candidate_uid; break
		arena.mana = model.get_stats().max_mana
		var equipped_max: float = arena.mana
		var where: Dictionary = model.first_bag_position(uid)
		check(not where.is_empty() and model.move_item(uid, where, model.revision(), arena.build_save_path).ok, "Actual equipment moves to owned bag")
		near(arena._stats[STAT], 0.4, "Build change recomputes guard from allocated source")
		check(float(arena._stats.max_mana) < equipped_max, "Removing actual mana charm reduces derived maximum")
		near(arena.mana, arena._stats.max_mana, "Removing mana charm clamps existing pool, without extra state")
		arena.shield = 0.0; arena.invulnerable = 0.0
		var before_mana: float = arena.mana
		check(arena.hit_player_components({"chaos": 10.0}), "Future incoming hit after real equipment change is admitted")
		near(arena.mana, before_mana - 4.0, "Unequipped future hit still consumes forty percent from clamped pool")
		check(model.move_item(uid, {"kind": "equipment", "slot_id": slot}, model.revision(), arena.build_save_path).ok, "Actual equipment re-equips through transaction")
		near(arena._stats[STAT], 0.4, "Re-equipping never duplicates source guard")
		near(arena._stats.max_mana, equipped_max, "Re-equipped mana charm restores maximum")
		near(arena.mana, before_mana - 4.0, "Re-equipping increases capacity without refilling spent mana")
	sections.equipment_and_next_hit = checks - start

func transactions_and_world_reset() -> void:
	var start := checks
	var model: RefCounted = arena.state
	equipment_change()
	clean(); check(arena.burn_runtime.apply("player", 0, 1, 100.0, 3.0, 0.0).ok, "Persistent burn fixture starts before refund")
	arena.elapsed = 0.5; arena._advance_player_burn(0.5)
	near(arena.mana, 80.0, "Pre-refund burn uses current guard")
	var current_mana: float = arena.mana
	check(model.refund_passive("34098", model.revision(), arena.build_save_path).ok, "Real node refund accepted while burn is active")
	near(arena._stats[STAT], 0.0, "Refund immediately updates future incoming behavior")
	# Build changes may clamp pools to their real maxima; compare against that
	# committed post-change baseline rather than the larger controlled fixture.
	current_mana = arena.mana; var current_health: float = arena.health
	arena._stats.fire_resistance = 0.0; arena.elapsed = 1.0; arena._advance_player_burn(1.0)
	near(arena.mana, current_mana, "Already-active burn stops diverting after refund")
	near(arena.health, current_health - 50.0, "Future half-second burn goes entirely to life after refund")
	check(model.allocate_passive("34098", 0, model.revision(), arena.build_save_path).ok, "Actual source node can be allocated again")
	clean(); check(arena.hit_player_components({"physical": 100.0}), "Reallocated guard protects future hit")
	near(arena.mana, 60.0, "Reallocation changes future behavior exactly once")
	check(arena.save_build(), "Damaged live run saves build")
	var saved: Dictionary = model.snapshot(); var loaded: Variant = Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.snapshot() == saved, "Reload retains build and allocations only")
	for key: String in ["mana", "health", "shield", "remaining_mana", "mana_spent", "mana_guard_runtime", "mana_guard_state"]:
		check(not saved.has(key), "Temporary resource state is absent from save: " + key)
	arena._replace_build(loaded, arena.build_save_path); arena.restart_run()
	near(arena.mana, arena._stats.max_mana, "Reload plus actual new-run lifecycle resets current mana")
	check(arena.burn_runtime.is_empty() and arena.leech_runtime.is_empty(), "Reload/new run has no temporary guard/effect debt")
	check(arena.enter_normal_town(arena.world_context().revision).ok, "Actual formal-town transition accepted")
	check(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok, "Actual tier-one map begins with source build")
	arena.invulnerable = 0.0; arena.shield = 0.0
	check(arena.hit_player_components({"chaos": 10.0}) and arena.mana < arena._stats.max_mana, "Actual map damage spends live mana")
	check(arena.return_to_town(arena.world_context().revision).ok, "Actual map return follows existing lifecycle")
	near(arena.mana, arena._stats.max_mana, "Map return resets current mana to current derived maximum")
	check(arena.state.get_mana_guard_profile().enabled and arena.burn_runtime.is_empty(), "Map transition keeps source allocation without temporary effects")
	sections.equipment_refund_reload_and_map = checks - start

func projected_model(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	check(int(result.version) in [34, 35], "Only explicit schema34/schema35 model version projection is allowed")
	result.erase("version")
	return result

func projected_stats(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	if result.has(STAT):
		check(typeof(result[STAT]) == TYPE_FLOAT and result[STAT] == 0.0, "Only new derived zero guard stat is projected")
		result.erase(STAT)
	return result

func legacy_probe(output: String) -> void:
	clean(); arena.rng.seed = 580882; arena.critical_runtime.reset(580882)
	check(arena.state.snapshot().talents.allocated.size() == 1, "Independent no-node oracle uses default legal source root")
	check(arena.save_build(), "Independent no-node probe initial save succeeds")
	for index: int in range(8):
		var enemy := target(Vector2(75 + index * 12, 20 if index % 2 else -20), true)
		enemy.health = 1.0 if index < 3 else 1000.0; enemy.max_health = enemy.health
	arena.mana = 1000.0
	var samples: Array = []; var casts := 0; var player_burn_loss := 0.0; var monster_burn_loss := 0.0
	var seen_segments: Dictionary = {}
	for step: int in range(90):
		if step == 0:
			check(arena.hit_player_components({"physical": 10.0, "fire": 5.0}), "No-node real incoming hit is exercised")
			check(arena.burn_runtime.apply("player", 0, 1, 10.0, 2.0, 0.0).ok, "No-node real player burn is attached")
		if step in [0, 60]:
			if arena._execute_compiled(Compiler.compile_group("meteor", arena.state.get_combat_snapshot(), ["ignite"])): casts += 1
		if step == 30:
			if arena._execute_compiled(Compiler.compile_group("tornado", arena.state.get_combat_snapshot(), ["ember_proliferation"])): casts += 1
		arena.tick(1.0 / 60.0)
		for segment: Dictionary in arena.burn_trace:
			var identity: PackedByteArray = var_to_bytes([segment.target_kind, segment.target_id, segment.from_time, segment.to_time, segment.raw_dps, segment.get("provenance", {})])
			if seen_segments.has(identity): continue
			seen_segments[identity] = true
			if segment.target_kind == "player": player_burn_loss += float(segment.settlement.health_lost)
			else: monster_burn_loss += float(segment.settlement.health_lost)
		var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(arena.build_save_path))
		check(disk is Dictionary, "Independent saved JSON parses before explicit projection")
		samples.append({"enemies": arena.enemies.duplicate(true), "projectiles": arena.projectiles.duplicate(true),
			"queue": arena.monster_runtime.queue.duplicate(true), "roots": arena.monster_runtime.roots.duplicate(true),
			"rng": arena.rng.state, "model": projected_model(arena.state.snapshot()), "stats": projected_stats(arena._stats),
			"resources": [arena.health, arena.mana, arena.shield], "combat": arena.combat_trace.duplicate(true),
			"hits": arena.damage_trace.duplicate(true), "incoming": arena.incoming_damage_trace.duplicate(true),
			"cooldowns": arena.group_cooldowns.snapshot(), "flasks": arena.flask_runtime.snapshot(),
			"burns": arena.burn_runtime.statuses(), "shock": arena.shock_runtime.statuses(arena.elapsed), "burn_trace": arena.burn_trace.duplicate(true),
			"critical": arena.critical_runtime.checkpoint(), "leech": arena.leech_runtime.snapshot(),
			"feedback": [arena.feedback_runtime._time, arena.feedback_runtime._pending.duplicate(true), arena.feedback_runtime._visible.duplicate(true)],
			"particles": arena.particles.duplicate(true), "text": arena.floating_text.duplicate(true), "pickups": arena.pickups.duplicate(true),
			"saves": arena.state.successful_saves, "saved_json": projected_model(disk)})
	check(casts > 0 and arena.kills >= 3 and arena.reward_kills >= 3 and arena.total_damage > 0.0, "Independent legacy probe covers actual cast/hit/root loot")
	check(player_burn_loss > 0.0 and monster_burn_loss > 0.0, "Independent legacy probe includes actual player and monster life-paying burn ticks")
	check(arena.save_build(), "Independent final save succeeds")
	FileAccess.open(output + ".bin", FileAccess.WRITE).store_buffer(var_to_bytes(samples))
	FileAccess.open(output + ".save", FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
	FileAccess.open(output + ".projected-save.json", FileAccess.WRITE).store_string(JSON.stringify(projected_model(arena.state.snapshot()), "\t", true, true))
	var report := {"ticks": 90, "seconds": arena.elapsed, "casts": casts, "kills": arena.kills, "reward_kills": arena.reward_kills,
		"damage": arena.total_damage, "rng": arena.rng.state, "events": arena.event_counts, "version": arena.state.snapshot().version,
		"project_version": ProjectSettings.get_setting("application/config/version"), "player_burn_actual_life_loss": player_burn_loss,
		"monster_burn_actual_life_loss": monster_burn_loss, "unique_burn_segments": seen_segments.size(), "checks": checks, "failures": failures}
	FileAccess.open(output + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("MANA_GUARD_LEGACY ", JSON.stringify(report))

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v058-consumers-"):
		quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false)
	var output: String = OS.get_environment("MANA_GUARD_LEGACY_OUTPUT")
	if not output.is_empty(): legacy_probe(output)
	else:
		check(arena.save_build(), "Fresh isolated current-schema build saved")
		legal_allocation()
		if not route.is_empty():
			if OS.get_environment("MANA_GUARD_GAMEPLAY_SECTION") == "equipment": equipment_change()
			else: actual_hits(); rejected_hits_and_casts(); burn_entry_and_death(); shared_recovery_and_monsters(); transactions_and_world_reset()
		print("Mana guard actual gameplay: %d checks, %d failures; sections %s; actual path %s" % [checks, failures, JSON.stringify(sections), JSON.stringify(route)])
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
