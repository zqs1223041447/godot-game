extends SceneTree
## Focused v052 actual-main integration. No historical suites or endurance run.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Shock = preload("res://scripts/combat/shock_rules.gd")
const SOURCES: Array[String] = [
	"tests/shock_gameplay_test.gd", "scripts/main.gd",
	"scripts/combat/shock_rules.gd", "scripts/combat/shock_runtime.gd",
	"scripts/combat/shock_support_rules.gd", "scripts/combat/skill_compiler.gd",
	"scripts/combat/combat_data.gd", "scripts/combat/damage_resolver.gd",
	"scripts/mechanics/defense_rules.gd", "scripts/combat/critical_strike_runtime.gd",
	"scripts/combat/leech_runtime.gd", "scripts/combat/projectile_runtime.gd",
	"scripts/combat/burn_runtime.gd", "scripts/combat/telegraphed_area_runtime.gd",
	"scripts/monsters/monster_catalog.gd", "scripts/monsters/telegraph_profiles.gd",
]
var arena: Node
var checks := 0
var failures := 0
var sections: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) <= maxf(0.00000001, absf(expected) * 0.000000001),
		label + " got=%s expected=%s" % [actual, expected])


func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear()
	arena.monster_runtime.reset(); arena.telegraphs.reset(); arena.burn_runtime.reset()
	arena.shock_runtime.reset(); arena.leech_runtime.clear(); arena.feedback_runtime.reset()
	arena.damage_trace.clear(); arena.incoming_damage_trace.clear(); arena.burn_trace.clear()
	arena.telegraph_trace.clear(); arena.combat_trace.clear(); arena.attack_admission_trace.clear()
	arena.event_counts.clear(); arena._ember_deaths.clear(); arena._ember_projectile_clock.clear()
	arena.group_cooldowns.reset(); arena.flask_runtime.clear_effects()
	arena.elapsed = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._burn_immunity_until = 0.0; arena.alive = true; arena.invulnerable = 0.0
	arena.damage_delay = 0.0; arena.auto_fire = false; arena.spawn_timer = 1000.0
	arena._autosave_timer = 0.0; arena.wave = 1; arena._world_mode = "normal"
	arena._geometry.configure("old_garden", arena.ARENA)
	arena._stats = arena.state.get_stats()
	for field: String in ["life_regen", "mana_regen", "shield_regen", "shield_recharge_rate", "armour", "evasion", "fire_resistance", "cold_resistance", "lightning_resistance"]:
		arena._stats[field] = 0.0
	arena._stats.max_health = 10000.0; arena._stats.max_shield = 5000.0; arena._stats.max_mana = 10000.0
	arena.health = 10000.0; arena.shield = 5000.0; arena.mana = 10000.0
	arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 52052; arena.critical_runtime.reset(52052)
	arena._player_evasion_entropy = 50.0
	arena.hud.close_panel()
	for id: String in arena.Data.SKILLS:
		arena.cooldowns[id] = 0.0


func target(offset: Vector2 = Vector2(80, 0), template: String = "brute") -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster(template, arena.player_pos + offset, "ordinary", "", [], false)
	enemy.spawn = 0.0; enemy.max_health = 10000.0; enemy.health = 10000.0
	enemy.max_shield = 5000.0; enemy.shield = 5000.0; enemy.armour = 0.0; enemy.evasion = 0.0
	enemy.resistances = {}; enemy.speed = 0.0; enemy.attack_timer = 1000.0
	enemy.shield_regen = 0.0; enemy.shield_recharge_rate = 0.0
	enemy.attack_speed = arena.Monsters.BASE_ATTACK_SPEED
	return enemy


func cast(skill: String = "nova", amount: float = 20.0, critical: bool = false, effects: Array = []) -> Dictionary:
	return Compiler.compile_group(skill, Combat.snapshot({"damage": amount,
		"crit_base_chance": 1.0 if critical else 0.0, "crit_base_multiplier": 2.0}, effects), ["shock"])


func hit(enemy: Dictionary, compiled: Dictionary, packet: Dictionary = {}, context: Dictionary = {}) -> void:
	var payload: Dictionary = packet
	if payload.is_empty():
		payload = compiled.packets.projectile if compiled.skill_id == "bolt" else compiled.packets.bounces[0] if compiled.skill_id == "chain" else compiled.packets.direct
	arena._apply_damage_packet(enemy, payload, compiled.snapshot, Color.CYAN, 0.0, context)


func status(enemy: Dictionary) -> Dictionary:
	return arena.shock_runtime.status_at("monster", int(enemy.id), arena.elapsed)


func pure_observation() -> Dictionary:
	return {"rng": arena.rng.state, "critical": arena.critical_runtime.checkpoint(),
		"leech": arena.leech_runtime.snapshot(), "state": arena.state.snapshot(),
		"saves": arena.state.successful_saves,
		"save_bytes": FileAccess.get_file_as_bytes(arena.build_save_path),
		"health": arena.health, "shield": arena.shield, "mana": arena.mana,
		"damage": arena.damage_trace.duplicate(true), "incoming": arena.incoming_damage_trace.duplicate(true)}


func actual_group_casts() -> void:
	var start: int = checks
	var support_uid: String = arena.state.award_gem("support:shock")
	check(not support_uid.is_empty(), "Real canonical model owns one Shock support gem")
	for skill: String in ["bolt", "nova", "chain"]:
		var group_id := ""
		for group: Dictionary in arena.state.snapshot().skill_groups:
			if arena.state.skill_group(group.id).skill_id == skill:
				group_id = group.id
		check(not group_id.is_empty(), "Default actual skill group found: " + skill)
		if group_id.is_empty(): continue
		check(arena.state.move_item(support_uid, {"kind": "skill_support", "group_id": group_id, "index": 0}, arena.state.revision(), arena.build_save_path).ok,
			"Canonical support UID equips: " + skill)
		var compiled: Dictionary = arena.state.get_group_cast(group_id)
		var plain: Dictionary = Compiler.compile_group(skill, arena.state.get_combat_snapshot(), [])
		check(compiled.ok and compiled.snapshot.shock_policy == Shock.PLAYER_POLICY, "Actual group freezes Shock policy: " + skill)
		near(compiled.mana, float(plain.mana) * 1.2, "Actual group final mana120%: " + skill)
		clean()
		var targets: Array[Dictionary] = [target(Vector2(60, 0))]
		if skill == "chain":
			targets.append(target(Vector2(120, 0))); targets.append(target(Vector2(180, 0)))
		var before_mana: float = arena.mana
		var state_before: Dictionary = arena.state.snapshot()
		var saves_before: int = arena.state.successful_saves
		check(arena.cast_group(group_id), "Real main cast_group entry accepted: " + skill)
		near(before_mana - arena.mana, compiled.mana, "Real cast pays exactly once: " + skill)
		near(arena.group_cooldown_remaining(group_id), compiled.cooldown, "Real UID cooldown remains authoritative: " + skill)
		if skill == "bolt": arena._update_projectiles(0.2)
		check(arena.damage_trace.size() == (int(compiled.initial_count) if skill == "bolt" else targets.size()), "Real cast reaches intended targets: " + skill)
		for index: int in range(targets.size()):
			var enemy: Dictionary = targets[index]
			check(status(enemy).active, "Real surviving target is shocked: %s/%d" % [skill, index])
			if not status(enemy).active: continue
			near(status(enemy).status.remaining_seconds, 2.0, "No instant duration consumed: " + skill)
			near(status(enemy).hit_damage_taken_increased, 0.15, "Exact15% strength: " + skill)
			if index >= arena.damage_trace.size(): continue
			var record: Dictionary = arena.damage_trace[index]
			var original: Dictionary = plain.packets.projectile if skill == "bolt" else plain.packets.bounces[index] if skill == "chain" else plain.packets.direct
			var expected: Dictionary = Damage.resolve(original, plain.snapshot.modifiers, {}, float(record.get("critical", {}).get("multiplier", 1.0)))
			near(record.total, float(expected.total) * 0.8, "Trigger has80%% hit and does not boost itself: %s/%d" % [skill, index])
			check(not record.has("shock") and record.has("shock_applied"), "Trace separates triggering hit from later benefit: " + skill)
		if skill == "bolt" and not arena.damage_trace.is_empty():
			for index: int in range(1, arena.damage_trace.size()):
				near(arena.damage_trace[index].total, float(arena.damage_trace[0].total) * 1.15, "Later real bolt from same volley benefits once")
				check(arena.damage_trace[index].has("shock"), "Later real same-time bolt records existing Shock")
		check(arena.state.snapshot() == state_before and arena.state.successful_saves == saves_before, "Actual cast and attachment leave canonical save untouched: " + skill)
	sections.actual_group_casts = checks - start


func ordering_and_boundaries() -> void:
	var start: int = checks
	clean()
	var enemy := target()
	var compiled := cast()
	hit(enemy, compiled)
	var first: Dictionary = arena.damage_trace.back().duplicate(true)
	var shield: float = enemy.shield
	hit(enemy, compiled)
	near(shield - float(enemy.shield), float(first.total) * 1.15, "Later hit at the same timestamp benefits exactly once")
	near(status(enemy).status.expires_at, 2.0, "Same-time refresh does not stack or extend twice")
	arena.elapsed = 0.5; hit(enemy, compiled)
	near(status(enemy).status.expires_at, 2.5, "Later equal-strength hit refreshes to its own deadline")
	var probe: Dictionary = Damage.packet({"physical": 10.0}, ["hit"], "boundary_probe")
	for at: float in [2.5 - 0.000000001, 2.5, 2.5 + 0.000000001]:
		arena.elapsed = at; shield = enemy.shield
		arena._apply_damage_packet(enemy, probe, {}, Color.WHITE)
		near(shield - float(enemy.shield), 11.5 if at < 2.5 else 10.0, "Strict expiry boundary at %.12f" % at)
	check(arena.shock_statuses().is_empty(), "Expired status is absent from main presentation getter")
	# Read-only main presentation must not expose writable runtime state.
	clean(); enemy = target(); hit(enemy, compiled)
	var detached: Array = arena.shock_statuses()
	var runtime_before: Array = arena.shock_runtime.statuses(arena.elapsed)
	check(detached.size() == 1, "Main getter reports one actual live target")
	if not detached.is_empty():
		detached[0].remaining_seconds = 1000.0; detached[0].hit_damage_taken_increased = 9.0
		detached[0].position = Vector2(-1000, -1000); detached.clear()
	check(arena.shock_runtime.statuses(arena.elapsed) == runtime_before, "Mutating main getter output cannot alter runtime")
	var query: Dictionary = status(enemy)
	query.status.provenance.skill_id = "mutated"; query.status.expires_at = 999.0
	check(arena.shock_runtime.statuses(arena.elapsed) == runtime_before, "Nested runtime getter provenance and timing are detached")
	var frozen: Array = arena.shock_runtime.statuses(arena.elapsed)
	arena.hud.open_panel("inventory"); arena._process(0.8)
	check(arena.elapsed == 0.0 and arena.shock_runtime.statuses(arena.elapsed) == frozen, "Menu pause freezes Shock duration")
	arena.hud.close_panel()
	sections.ordering_and_boundaries = checks - start


func attachment_gates() -> void:
	var start: int = checks
	clean(); var enemy := target(); var zero := cast("nova", 0.0)
	var shield: float = enemy.shield
	hit(enemy, zero)
	near(enemy.shield, shield, "Zero damage does not spend a target resource")
	check(not status(enemy).active, "Zero damage cannot attach Shock")
	# Existing monster resistance caps at90%; model immunity by exactly suppressing
	# lightning while retaining a positive cold hit through the real resolver.
	clean(); enemy = target()
	var mixed: Dictionary = Compiler.compile_group("nova", Combat.snapshot({"damage": 20.0, "spell_added_cold": 10.0}, []), ["shock"])
	mixed.snapshot.modifiers.append({"id": "test:lightning_immune", "mode": "more", "value": -1.0, "all_tags": ["hit"], "damage_types": ["lightning"]})
	shield = enemy.shield; hit(enemy, mixed)
	check(float(enemy.shield) < shield and arena.damage_trace.back().components.cold > 0.0, "Immunity fixture still loses resources to cold")
	near(arena.damage_trace.back().components.lightning, 0.0, "Lightning contribution is exactly zero")
	check(not status(enemy).active, "No settled lightning cannot attach even with positive other damage")
	clean(); enemy = target(); enemy.spawn = 0.5; hit(enemy, cast())
	check(arena.damage_trace.is_empty() and not status(enemy).active, "Birth protection prevents both hit and attachment")
	enemy.spawn = 0.0; enemy.shield = 0.0; enemy.health = 1.0; hit(enemy, cast())
	check(float(enemy.health) <= 0.0 and not status(enemy).active, "Lethal lightning hit cannot attach to a corpse")
	clean(); enemy = target(); hit(enemy, cast()); enemy.shield = 0.0; enemy.health = 1.0
	arena._damage_enemy(enemy, 100.0, Color.WHITE)
	check(not status(enemy).active and arena.shock_runtime.is_empty(), "Death removes pre-existing Shock")
	clean(); enemy = target()
	var observation := pure_observation()
	var rejected: Dictionary = arena._attach_shock("monster", int(enemy.id), 0, 0.0, Shock.PLAYER_POLICY,
		{"shield_spent": 0.0, "health_lost": 0.0, "components": {"lightning": 10.0}}, {})
	check(rejected.ok and not rejected.applied and arena.shock_runtime.is_empty(), "Positive component with zero actual resource loss cannot attach")
	check(pure_observation() == observation, "Rejected pure attachment has no resource/RNG/save effect")
	sections.attachment_gates = checks - start


func mitigation_critical_leech_and_dot() -> void:
	var start: int = checks
	clean(); var enemy := target(); hit(enemy, cast())
	enemy.armour = 1000.0; enemy.resistances = {"fire": 0.5, "cold": 0.25, "lightning": 0.75, "chaos": 0.1}
	var packet: Dictionary = Damage.packet({"physical": 100.0, "fire": 100.0, "cold": 100.0, "lightning": 100.0, "chaos": 100.0}, ["hit"], "all_components")
	var shield: float = enemy.shield
	arena._apply_damage_packet(enemy, packet, {}, Color.WHITE)
	var result: Dictionary = arena.damage_trace.back()
	var expected := {"physical": 100.0 / 3.0, "fire": 50.0, "cold": 75.0, "lightning": 25.0, "chaos": 90.0}
	var total := 0.0
	for type: String in expected:
		near(result.components[type], float(expected[type]) * 1.15, "Each mitigated component multiplied once: " + type)
		near(result.before_defense_components[type], 100.0, "Unboosted raw basis retained: " + type)
		total += float(expected[type]) * 1.15
	near(shield - float(enemy.shield), total, "Armour evaluated before Shock, then all components settle together")
	# Critical is frozen by actual cast admission and precedes the target multiplier.
	clean(); enemy = target(); hit(enemy, cast())
	var critical := cast("nova", 20.0, true)
	shield = enemy.shield
	check(arena._execute_compiled(critical), "Guaranteed critical Shock cast admitted through main")
	result = arena.damage_trace.back()
	var ordinary: Dictionary = Damage.resolve(critical.packets.direct, critical.snapshot.modifiers)
	check(result.critical.critical, "Actual main frozen critical result present")
	near(shield - float(enemy.shield), float(ordinary.total) * 2.0 * 1.15, "Critical and Shock each apply once to final actual hit")
	# An actual attack can leech from a target shocked by a prior spell.
	var attack: Dictionary = Compiler.compile_basic(Combat.snapshot({"damage": 100.0, "attack_added_fire": 20.0,
		"crit_base_chance": 1.0, "crit_base_multiplier": 2.0, "max_health": 10000.0, "max_mana": 10000.0,
		"attack_life_leech": 0.1, "attack_mana_leech": 0.05}, []))
	var frozen: Dictionary = arena.critical_runtime.freeze(attack.snapshot).snapshot
	arena.health = 5000.0; arena.mana = 5000.0; enemy.shield = 5.0; enemy.health = 10.0
	arena._apply_damage_packet(enemy, attack.packets.projectile, frozen, Color.WHITE)
	result = arena.damage_trace.back()
	near(result.shield_spent + result.health_lost, 15.0, "Critical shocked overkill records only15 actual resources")
	check(result.has("leech"), "Eligible actual attack creates leech from final settlement")
	if result.has("leech"):
		near(result.leech.health, 1.5, "Life leech excludes critical/Shock overkill")
		near(result.leech.mana, 0.75, "Mana leech excludes critical/Shock overkill")
	# Shock must not inflate an ignite's frozen raw basis or either actor's DOT tick.
	clean(); enemy = target(); hit(enemy, cast()); enemy.resistances.fire = 0.5
	var ignite: Dictionary = Compiler.compile_group("meteor", Combat.snapshot({"damage": 20.0}, []), ["ignite"])
	hit(enemy, ignite, ignite.packets.direct)
	var burn: Dictionary = arena.burn_runtime.status_for("monster", int(enemy.id))
	near(burn.raw_dps, ignite.burn_profile.roles.direct.dps, "Shock does not inflate hit-derived burn basis")
	shield = enemy.shield; var observation := pure_observation()
	arena.elapsed = 0.5; arena._advance_monster_burns(arena.elapsed)
	near(shield - float(enemy.shield), float(burn.raw_dps) * 0.5 * 0.5, "Monster DOT ignores active15% Shock")
	check(pure_observation() == observation, "Nonlethal DOT changes no hit trace, player resources, RNG, leech or saves")
	check(arena.shock_runtime.apply("player", 0, int(enemy.id), 0.5, Shock.ENEMY_POLICY).ok, "Player DOT control has live Shock")
	check(arena.burn_runtime.apply("player", 0, int(enemy.id), 20.0, 3.0, 0.5).ok, "Player DOT control has real burn")
	arena._stats.fire_resistance = 0.5; shield = arena.shield; arena.elapsed = 1.0
	arena._advance_player_burn(arena.elapsed)
	near(shield - arena.shield, 5.0, "Player DOT ignores active15% Shock")
	sections.mitigation_critical_leech_and_dot = checks - start


func independent_explosion() -> void:
	var start: int = checks
	clean()
	var center: Vector2 = arena.player_pos + Vector2(200, 0)
	var shocked := target(Vector2(200, 40)); var plain := target(Vector2(200, -40))
	hit(shocked, cast())
	var deadline: float = status(shocked).status.expires_at
	var compiled := cast("bolt", 20.0, false, ["explode_on_flight_end"])
	var shot: Dictionary = arena.projectile_runtime.make_projectile(center, Vector2.RIGHT,
		{"speed": 10.0, "range": 500.0, "lifetime": 0.01, "pierce": -1, "radius": 1.0},
		compiled.packets.projectile, compiled.snapshot, arena.projectile_runtime.new_cast(), Color.CYAN)
	arena.projectiles.append(shot); arena.damage_trace.clear(); arena.elapsed = 0.2
	arena._update_projectiles(0.02)
	check(int(arena.event_counts.get("explosion", 0)) == 1, "Actual natural projectile end emits one independent explosion")
	check(arena.damage_trace.size() == 2, "Independent explosion reaches both nearby controls")
	var expected: Dictionary = Damage.resolve(compiled.packets.secondary, compiled.snapshot.modifiers)
	for record: Dictionary in arena.damage_trace:
		near(record.total, float(expected.total) * (1.15 if record.target_id == shocked.id else 1.0), "Independent explosion may benefit from existing Shock")
		check(record.tags.has("secondary") and not record.has("shock_applied"), "Secondary cannot inherit Shock attachment")
	check(not status(plain).active, "Independent explosion cannot attach to previously unshocked target")
	near(status(shocked).status.expires_at, deadline, "Independent explosion cannot refresh existing Shock")
	sections.independent_explosion = checks - start


func enemy_telegraph_and_dodge() -> void:
	var start: int = checks
	clean(); var enemy := target(Vector2(80, 0), "storm_skitter")
	enemy.attack_timer = 0.0; enemy.damage = 20.0
	arena._start_enemy_telegraphs()
	var warning: Dictionary = arena.telegraphs.state_for(int(enemy.id))
	check(not warning.is_empty(), "Actual storm-skitter begins locked warning")
	if warning.is_empty(): return
	near(warning.profile.windup_seconds, 0.7, "Storm windup remains0.7s")
	near(warning.profile.recovery_seconds, 1.6, "Storm recovery remains1.6s")
	near(warning.profile.radius, 65.0, "Storm radius remains65")
	near(warning.profile.damage_multiplier, 1.4, "Storm multiplier is1.4 instead of1.6")
	near(warning.packet.base.lightning, 28.0, "Storm immediate raw budget is1.4D")
	check(warning.shock_policy == Shock.ENEMY_POLICY and warning.center == arena.player_pos, "Storm freezes one-second15% policy and target center")
	var shield: float = arena.shield
	arena.tick(0.7); enemy.attack_timer = 1000.0
	near(shield - arena.shield, 28.0, "Actual telegraph triggering hit does not amplify itself")
	var view: Array = arena.shock_statuses()
	check(view.size() == 1 and view[0].target_kind == "player", "Actual storm hit attaches player Shock")
	if not view.is_empty():
		near(view[0].remaining_seconds, 1.0, "Enemy policy lasts exactly one second")
		near(view[0].hit_damage_taken_increased, 0.15, "Enemy policy increases subsequent hits15%")
	near(arena.invulnerable, 0.32, "Original hit invulnerability remains0.32s")
	arena.invulnerable = 0.0; shield = arena.shield
	check(arena.hit_player_components({"physical": 10.0}, 0, ["hit"]), "Same-time later independent player hit admitted after resetting fixture immunity")
	near(shield - arena.shield, 11.5, "Player later same-time hit receives15% once")
	arena._damage_enemy(enemy, 1000000.0, Color.WHITE)
	check(arena.shock_runtime.status_at("player", 0, arena.elapsed).active, "Source death preserves already attached player Shock")
	for at: float in [1.7 - 0.000000001, 1.7, 1.7 + 0.000000001]:
		arena.elapsed = at; arena.invulnerable = 0.0; shield = arena.shield
		check(arena.hit_player_components({"physical": 10.0}, 0, ["hit"]), "Player boundary hit admitted")
		near(shield - arena.shield, 11.5 if at < 1.7 else 10.0, "Enemy Shock strict expiry boundary %.12f" % at)
	clean(); enemy = target(Vector2(80, 0), "storm_skitter"); enemy.attack_timer = 0.0
	arena._start_enemy_telegraphs(); var locked: Vector2 = arena.telegraphs.state_for(int(enemy.id)).center
	arena.player_pos += Vector2(0, 200); shield = arena.shield; arena.tick(0.7)
	near(arena.shield, shield, "Walking outside locked warning avoids actual damage")
	check(arena.shock_runtime.is_empty(), "Dodged storm telegraph cannot attach Shock")
	check(arena.telegraph_trace.size() == 1 and arena.telegraph_trace[0].center == locked and not arena.telegraph_trace[0].inside, "Resolved actual warning retains original ground center")
	clean(); enemy = target(Vector2(80, 0), "storm_skitter"); enemy.attack_timer = 0.0
	arena._stats.evasion = 100000000.0; arena._player_evasion_entropy = 0.0
	arena._start_enemy_telegraphs(); shield = arena.shield; arena.tick(0.7)
	near(arena.shield, shield, "Failed actual attack admission avoids storm damage")
	check(arena.shock_runtime.is_empty(), "Evaded telegraph cannot attach Shock")
	sections.enemy_telegraph_and_dodge = checks - start


func pure_status_and_lifecycle() -> void:
	var start: int = checks
	clean(); var enemy := target()
	var observation := pure_observation()
	check(arena.shock_runtime.apply("monster", int(enemy.id), 0, 0.0, Shock.PLAYER_POLICY).ok, "Pure status attach accepted")
	check(arena.shock_runtime.apply("player", 0, int(enemy.id), 0.0, Shock.ENEMY_POLICY).ok, "Pure player status attach accepted")
	arena.shock_statuses(); arena._shock_hit_increase("monster", int(enemy.id), 0.5)
	check(arena.shock_runtime.apply("monster", int(enemy.id), 0, 0.5, Shock.PLAYER_POLICY).ok, "Pure refresh accepted")
	check(arena.shock_runtime.prune(3.0).ok and arena.shock_runtime.is_empty(), "Pure expiry cleanup removes both actors")
	check(pure_observation() == observation, "Attach/read/refresh/expiry changes no resources, RNG, critical, leech, build or save bytes")
	# Lifecycle tests enter the actual existing main transitions.
	clean(); enemy = target(); hit(enemy, cast()); arena.restart_run()
	check(arena.shock_runtime.is_empty() and arena.shock_statuses().is_empty(), "Actual restart clears transient Shock")
	clean(); enemy = target(); hit(enemy, cast())
	check(arena.enter_normal_town(arena.world_context().revision).ok and arena.shock_runtime.is_empty(), "Actual enter-normal-town clears Shock")
	check(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision).ok, "Actual normal map draft accepted")
	check(arena.start_map(arena.map_draft().revision).ok and arena.shock_runtime.is_empty(), "Actual start-map begins with no old Shock")
	if arena.world_context().mode == "map":
		arena.invulnerable = 0.0
		check(arena.hit_player_components({"lightning": 1.0}, 0, ["hit"], {"shock_policy": Shock.ENEMY_POLICY, "at": arena.elapsed}), "Actual map player hit seeds transient Shock")
		check(not arena.shock_runtime.is_empty(), "Map has live Shock before return")
		check(arena.return_to_town(arena.world_context().revision).ok and arena.shock_runtime.is_empty(), "Actual map return clears Shock")
	check(arena.leave_normal_town(arena.world_context().revision).ok, "Actual normal arena restored")
	clean(); enemy = target(); hit(enemy, cast())
	check(arena.enter_town_test(arena.world_context().revision).ok and arena.shock_runtime.is_empty(), "Actual profile switch clears Shock")
	check(arena.craft_map("old_garden", [], [], arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok, "Actual isolated map opens for completion cleanup")
	if arena.world_context().mode == "map":
		var layout: Dictionary = arena.world_geometry().landmarks
		arena._begin_progress_transaction()
		for camp: Dictionary in layout.camps:
			arena.player_pos = camp.trigger_center; arena._update_map_spawning(0.0)
		for root_enemy: Dictionary in arena.enemies.duplicate():
			root_enemy.spawn = 0.0; arena._damage_enemy(root_enemy, 1000000.0, Color.WHITE)
		check(arena.world_context().boss_phase == "ready", "Actual camp root deaths unlock map boss")
		arena.player_pos = layout.boss.trigger_center; arena._update_map_spawning(0.0)
		arena.invulnerable = 0.0
		check(arena.hit_player_components({"lightning": 1.0}, 0, ["hit"], {"shock_policy": Shock.ENEMY_POLICY, "at": arena.elapsed}), "Completion fixture has an actual shocked player")
		var loops := 0
		while arena.world_context().mode == "map" and loops < 10:
			loops += 1
			for live_enemy: Dictionary in arena.enemies.duplicate():
				if float(live_enemy.health) > 0.0:
					live_enemy.spawn = 0.0; arena._damage_enemy(live_enemy, 1000000.0, Color.WHITE)
			arena._flush_monster_spawns(); arena._check_map_complete()
		arena._end_progress_transaction()
		check(loops < 10 and arena.world_context().mode == "map_complete", "Actual boss and descendants finish the isolated map")
		check(arena.shock_runtime.is_empty(), "Actual map-complete transition clears all Shock")
		check(arena.return_to_town(arena.world_context().revision).ok, "Actual completed-map return succeeds")
	check(arena.leave_town_test(arena.world_context().revision).ok and arena.shock_runtime.is_empty(), "Actual normal profile restore has no transient Shock")
	check(arena.leave_normal_town(arena.world_context().revision).ok, "Normal arena restored after profile isolation")
	clean(); enemy = target(); hit(enemy, cast())
	arena.shield = 0.0; arena.health = 1.0; arena.invulnerable = 0.0
	check(arena.hit_player_components({"lightning": 10.0}, int(enemy.id), ["hit"], {"shock_policy": Shock.ENEMY_POLICY, "at": arena.elapsed}), "Actual lethal incoming hit admitted")
	check(not arena.alive and arena.shock_runtime.is_empty(), "Player death clears all statuses and cannot attach a lethal Shock")
	sections.pure_status_and_lifecycle = checks - start


func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v052-shock-gameplay-"):
		push_error("Shock integration requires a fresh dedicated /tmp XDG root")
		quit(78)
		return
	var hashes: Dictionary = {}
	for path: String in SOURCES:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	print("SHOCK_GAMEPLAY_SOURCES " + JSON.stringify(hashes))
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false)
	check(arena.save_build(), "Fresh current profile saves in isolated XDG")
	actual_group_casts()
	ordering_and_boundaries()
	attachment_gates()
	mitigation_critical_leech_and_dot()
	independent_explosion()
	enemy_telegraph_and_dodge()
	pure_status_and_lifecycle()
	var exit_code: int = 1 if failures else 0
	print("SHOCK_GAMEPLAY_COMPLETE " + JSON.stringify({"checks": checks, "failures": failures,
		"sections": sections, "exit": exit_code, "source_hashes": hashes,
		"xdg_data_home": OS.get_environment("XDG_DATA_HOME")}))
	arena.queue_free()
	await process_frame
	quit(exit_code)
