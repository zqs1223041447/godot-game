extends SceneTree
## Focused actual-main/model consumer checks. The same external script drives
## the independently frozen v58 project for the bounded no-new-node oracle.
const Model = preload("res://scripts/canonical_game_state.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Shock = preload("res://scripts/combat/shock_rules.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const MapDefense = preload("res://scripts/world/map_defense_rules.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const ELEMENTS: Array[String] = ["fire", "cold", "lightning"]
const STAT := "damage_taken_from_mana_before_life"
var arena: Node
var checks := 0
var failures := 0
var sections: Dictionary = {}
var route: Array = []
var source_fixture: Dictionary = {}
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

func legal_allocation() -> bool:
	var start := checks
	source_fixture = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v059-source/allocation-witness.json"))
	route = source_fixture.allocated
	check(route.size() == 74, "Marauder route contains root plus 73 paid nodes")
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level": 69, "xp": 0}; candidate.talents.class_id = 1
	candidate.talents.allocated = [route[0]]; candidate.talents.normal_points = 73; candidate.revision += 1
	check(arena.state.Rules.reason(candidate).is_empty() and arena.state._commit(candidate, arena.build_save_path).ok, "Lawful level69 Marauder fixture commits with 73 earned points")
	for id: String in route.slice(1):
		check(arena.state.available_passives().has(id) and arena.state.allocate_passive(id, 0, arena.state.revision(), arena.build_save_path).ok, "Real guarded source transaction " + id)
	check(arena.state.talent_points == 0 and arena.state.snapshot().talents.allocated.size() == 74, "Exactly 73 allocation transactions spend the whole budget")
	for id: String in source_fixture.maximum_nodes:
		check(arena.state.snapshot().talents.allocated.has(id), "All twelve new maximum nodes coexist: " + id)
	var before := readonly()
	var profile: Dictionary = arena.state.get_resistance_profile()
	check(profile.ok and profile.has_all(["reason", "base_cap", "safety_cap", "raw_resistances", "maximum_resistances", "effective_resistances"]), "Actual model exports complete read-only resistance profile")
	near(profile.base_cap, 0.75, "Base cap remains75 percent"); near(profile.safety_cap, 0.83, "Shared safety cap is83 percent")
	for element: String in ELEMENTS:
		near(profile.raw_resistances[element], 0.91 if element == "fire" else 0.83, "Actual all-node raw resistance " + element)
		near(profile.maximum_resistances[element], 0.83, "Actual all-node cap " + element)
		near(profile.effective_resistances[element], 0.83, "Actual all-node effective resistance " + element)
	profile.raw_resistances.fire = 99.0; profile.maximum_resistances.fire = 0.1; profile.effective_resistances.fire = 0.1
	near(arena.state.get_resistance_profile().effective_resistances.fire, 0.83, "Returned nested profile is detached")
	var panel: Variant = load("res://scripts/ui/canonical_character_panel.gd").new()
	root.add_child(panel); panel.setup(arena.state)
	check(panel.model == arena.state and panel.refresh_generation > 0 and not panel._dirty, "Real C panel consumes actual all-node model profile and finishes refresh")
	panel.queue_free()
	check(readonly() == before, "Model profile and actual panel reads preserve model, saved bytes and RNG")
	var loaded: Variant = Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.snapshot() == arena.state.snapshot(), "Actual 73-point build survives disk reload")
	check(loaded.get_resistance_profile() == arena.state.get_resistance_profile(), "Reload derives identical resistance profile")
	sections.legal_source_and_actual_model_panel = checks - start
	return failures == 0

func restore_source_resistances() -> void:
	var stats: Dictionary = arena.state.get_stats()
	for element: String in ELEMENTS:
		arena._stats[element + "_resistance"] = stats[element + "_resistance"]
		arena._stats["maximum_" + element + "_resistance_add"] = stats["maximum_" + element + "_resistance_add"]

func source_hits() -> void:
	var start := checks
	for element: String in ELEMENTS:
		clean(); restore_source_resistances()
		var before := readonly()
		check(arena.hit_player_components({element:100.0}), "Real incoming " + element + " hit accepted")
		var hit: Dictionary = arena.incoming_damage_trace.back()
		near(hit.effective_resistances[element], 0.83, "Incoming hit uses actual83cap " + element)
		near(hit.damage_total, 17.0, "Hundred incoming damage leaves17 " + element)
		near(hit.health_lost, 17.0, "Actual main health loses17 " + element)
		near(arena.health, 983.0, "Main writes actual life " + element)
		check(readonly() == before, "Incoming cap changes no saved state or RNG " + element)
		var outcomes: Array = []
		for bonus: float in [0.0, 0.08]:
			clean(); arena._stats[element + "_resistance"] = 0.4
			arena._stats["maximum_" + element + "_resistance_add"] = bonus
			check(arena.hit_player_components({element:100.0}), "Under-cap actual hit accepted " + element)
			outcomes.append(arena.incoming_damage_trace.back().damage_total)
		near(outcomes[0], 60.0, "Insufficient raw resistance leaves60 " + element)
		near(outcomes[1], outcomes[0], "Higher maximum alone grants no mitigation " + element)
	sections.actual_three_element_hits_and_low_raw = checks - start

func current_player_burn() -> Dictionary:
	for status: Dictionary in arena.burn_statuses():
		if status.target_kind == "player": return status
	return {}

func burn_and_order() -> void:
	var start := checks
	clean(); restore_source_resistances()
	check(arena.burn_runtime.apply("player", 0, 1, 100.0, 4.0, 0.0).ok, "Actual player burn attaches raw100DPS")
	var before := readonly()
	var status := current_player_burn()
	near(status.raw_dps, 100.0, "Burn status retains incoming snapshot rawDPS")
	near(status.effective_dps, 17.0, "Burn presentation uses actual83cap")
	arena.elapsed = 1.0; arena._advance_player_burn(1.0)
	var burn: Dictionary = arena.burn_trace.back().settlement
	near(burn.damage_total, status.effective_dps, "One-second actual settlement equals presented effectiveDPS")
	near(burn.health_lost, 17.0, "83cap reduces player burn actual health loss")
	near(arena.burn_runtime.status_for("player", 0).raw_dps, 100.0, "Settlement leaves original rawDPS snapshot unchanged")
	check(readonly() == before, "Player burn cap introduces no model/save/RNG writes")
	for bonus: float in [0.0, 0.08]:
		clean(); arena._stats.fire_resistance = 0.4; arena._stats.maximum_fire_resistance_add = bonus
		check(arena.burn_runtime.apply("player", 0, 1, 100.0, 4.0, 0.0).ok, "Under-cap player burn attaches")
		near(current_player_burn().effective_dps, 60.0, "Burn maximum alone adds no raw resistance")
		arena.elapsed = 1.0; arena._advance_player_burn(1.0)
		near(arena.burn_trace.back().settlement.damage_total, 60.0, "Under-cap settlement gets no maximum-only benefit")
	# Deliberate controlled stat fixture composes the independently tested source
	# maximum with mana guard, without claiming this is a73-point combined build.
	clean(); restore_source_resistances(); arena._stats[STAT] = 0.4; arena.shield = 10.0
	check(arena.shock_runtime.apply("player", 0, 1, 0.0, Shock.ENEMY_POLICY).ok, "Live15percent Shock applies for ordering test")
	before = readonly()
	check(arena.hit_player_components({"fire":100.0,"cold":100.0,"lightning":100.0}), "Real combined elemental hit accepted")
	var hit: Dictionary = arena.incoming_damage_trace.back()
	near(hit.damage_total, 51.0 * 1.15, "83cap mitigates all components before15percent Shock")
	near(hit.shield_spent, 10.0, "Shield pays first after resistances and Shock")
	near(hit.mana_spent, (51.0 * 1.15 - 10.0) * 0.4, "Forty percent mana guard pays post-shield damage")
	near(hit.health_lost, (51.0 * 1.15 - 10.0) * 0.6, "Actual life excludes mana paid")
	near(arena.mana, 100.0 - hit.mana_spent, "Main writes mana separately")
	arena.feedback_runtime.flush_target("player", 0)
	near(arena.damage_feedback()[0].amount, hit.shield_spent + hit.health_lost, "Hit float feedback includes shield and life only")
	check(readonly() == before, "Combined defense pipeline preserves saved bytes and RNG")
	clean(); restore_source_resistances(); arena._stats[STAT] = 0.4; arena.shield = 5.0; arena._stats.armour = 10000.0
	check(arena.shock_runtime.apply("player", 0, 1, 0.0, Shock.ENEMY_POLICY).ok, "Burn comparison also has15percent Shock")
	check(arena.burn_runtime.apply("player", 0, 1, 100.0, 4.0, 0.0).ok, "Combined capped burn attaches")
	near(current_player_burn().effective_dps, 17.0, "Burn effectiveDPS excludes hit-only Shock and armour")
	arena.elapsed = 1.0; arena._advance_player_burn(1.0)
	burn = arena.burn_trace.back().settlement
	near(burn.damage_total, 17.0, "Burn shares83cap without hit-only multipliers")
	near(burn.shield_spent, 5.0, "Burn consumes shield before mana")
	near(burn.mana_spent, 12.0 * 0.4, "Burn diverts40percent of post-shield amount")
	near(burn.health_lost, 12.0 * 0.6, "Burn life excludes diverted mana")
	arena.feedback_runtime.flush_target("player", 0)
	near(arena.damage_feedback()[0].amount, 5.0 + 12.0 * 0.6, "Burn feedback excludes mana spending")
	sections.actual_burn_status_settlement_and_order = checks - start

func refund_during_burn() -> void:
	var start := checks
	clean(); restore_source_resistances()
	check(arena.burn_runtime.apply("player", 0, 1, 100.0, 10.0, 0.0).ok, "Long-lived raw100DPS snapshot begins before actual refunds")
	arena.elapsed = 0.5; arena._advance_player_burn(0.5)
	near(arena.burn_trace.back().settlement.damage_total, 8.5, "Initial half-second burn uses83cap")
	var removed: Array[String] = []
	var reverse: Array = route.slice(1); reverse.reverse()
	for id: String in reverse:
		check(arena.state.refund_passive(id, arena.state.revision(), arena.build_save_path).ok, "Actual legal reverse-order source refund " + id)
		removed.append(id)
		if float(arena.state.get_resistance_profile().maximum_resistances.fire) < 0.83 - 1e-8: break
	var profile: Dictionary = arena.state.get_resistance_profile()
	check(profile.maximum_resistances.fire < 0.83, "Real source refunds reduce capped maximum")
	near(arena._stats.maximum_fire_resistance_add, arena.state.get_stats().maximum_fire_resistance_add, "Build changed signal immediately refreshes live main defense")
	near(arena.burn_runtime.status_for("player", 0).raw_dps, 100.0, "Actual refunds preserve admitted rawDPS snapshot")
	var expected: float = 100.0 * (1.0 - float(profile.effective_resistances.fire))
	near(current_player_burn().effective_dps, expected, "Already-active burn display uses current refunded defense")
	var health_before: float = arena.health
	arena.elapsed = 1.0; arena._advance_player_burn(1.0)
	near(arena.burn_trace.back().settlement.damage_total, expected * 0.5, "Next burn interval uses current refunded defense")
	near(arena.health, health_before - expected * 0.5, "Refunded burn applies corresponding actual life loss")
	arena.invulnerable = 0.0; arena.shield = 0.0
	check(arena.hit_player_components({"fire":100.0}), "Next incoming hit after actual refund admitted")
	near(arena.incoming_damage_trace.back().damage_total, expected, "Next hit uses same current refunded defense")
	removed.reverse()
	for id: String in removed:
		check(arena.state.allocate_passive(id, 0, arena.state.revision(), arena.build_save_path).ok, "Actual source reallocation " + id)
	near(arena.state.get_resistance_profile().effective_resistances.fire, 0.83, "Actual reallocation restores83effective")
	near(arena.burn_runtime.status_for("player", 0).raw_dps, 100.0, "Reallocation also preserves admitted rawDPS snapshot")
	arena.invulnerable = 0.0
	near(current_player_burn().effective_dps, 17.0, "Reallocation updates active burn effectiveDPS")
	arena.elapsed = 1.5; arena._advance_player_burn(1.5)
	near(arena.burn_trace.back().settlement.damage_total, 8.5, "Reallocated next burn interval returns to83cap")
	arena.invulnerable = 0.0; arena.shield = 0.0
	check(arena.hit_player_components({"fire":100.0}), "Next incoming hit after reallocation admitted")
	near(arena.incoming_damage_trace.back().damage_total, 17.0, "Reallocated next hit returns to83cap")
	sections.actual_refund_reallocation_and_live_burn = checks - start

func natural_catalog_observations() -> Dictionary:
	var result: Dictionary = {}
	var profile: Dictionary = Maps.compile("old_garden", [], ["elemental_aegis"]).profile
	for id: String in Monsters.TEMPLATES:
		var template: Dictionary = Monsters.TEMPLATES[id]
		var enemy: Dictionary = arena._spawn_monster(id, arena.player_pos + Vector2(200, 0), "level_boss" if template.rarity == "boss" else "ordinary", "", [], false)
		var applied: Dictionary = MapDefense.apply_to_enemy(enemy, profile)
		check(applied.ok, "Aegis applies to actual spawned natural monster " + id)
		for element: String in ELEMENTS:
			check(not enemy.has("maximum_" + element + "_resistance_add") and not enemy.defense_stats.has("maximum_" + element + "_resistance_add"), "Natural monster receives no player maximum stat " + element)
			near(float(applied.enemy.resistances[element]), clampf(float(enemy.defense_stats.get(element + "_resistance", 0.0)) + 0.2, 0.0, 0.75), "Aegis retains raw+20 and75cap on " + id + "/" + element)
		result[id] = {"natural":enemy.duplicate(true), "aegis":applied.enemy.duplicate(true)}
	arena.enemies.clear(); arena.monster_runtime = arena.MonsterLifecycle.new()
	return result

func natural_monsters() -> void:
	var start := checks
	clean(); restore_source_resistances()
	var observation := natural_catalog_observations()
	near(observation.ember_guard.natural.resistances.fire, 0.25, "Natural ember guard keeps original25fire")
	near(observation.ember_guard.aegis.resistances.fire, 0.45, "Aegis ember guard remains45fire")
	near(observation.ember_guard.aegis.resistances.cold, 0.2, "Aegis cold remains20")
	near(observation.ember_guard.aegis.resistances.lightning, 0.2, "Aegis lightning remains20")
	sections.natural_monsters_and_aegis = checks - start

func projected_model(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	check(int(result.version) in [35, 36], "Only explicit schema35/schema36 model version projection is allowed")
	result.erase("version")
	return result

func projected_stats(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	for element: String in ELEMENTS:
		var field: String = "maximum_" + element + "_resistance_add"
		if result.has(field):
			check(typeof(result[field]) == TYPE_FLOAT and result[field] == 0.0, "Only the three new derived zero maximum-resistance stats are projected")
			result.erase(field)
	return result

func legacy_probe(output: String) -> void:
	clean(); arena.rng.seed = 590882; arena.critical_runtime.reset(590882)
	check(arena.state.snapshot().talents.allocated.size() == 1, "Independent no-node oracle uses default legal source root")
	check(arena.save_build(), "Independent no-node probe initial save succeeds")
	var natural_observation: Dictionary = natural_catalog_observations()
	for index: int in range(8):
		var enemy := target(Vector2(75 + index * 12, 20 if index % 2 else -20), true)
		enemy.health = 1.0 if index < 3 else 1000.0; enemy.max_health = enemy.health
	arena.mana = 1000.0
	var samples: Array = [natural_observation]; var casts := 0; var player_burn_loss := 0.0; var monster_burn_loss := 0.0
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
			"burns": arena.burn_runtime.statuses(), "burn_presentation": arena.burn_statuses(), "shock": arena.shock_runtime.statuses(arena.elapsed), "burn_trace": arena.burn_trace.duplicate(true),
			"critical": arena.critical_runtime.checkpoint(), "leech": arena.leech_runtime.snapshot(),
			"feedback": [arena.feedback_runtime._time, arena.feedback_runtime._pending.duplicate(true), arena.feedback_runtime._visible.duplicate(true)],
			"particles": arena.particles.duplicate(true), "text": arena.floating_text.duplicate(true), "pickups": arena.pickups.duplicate(true),
			"events": arena.event_counts.duplicate(true), "saves": arena.state.successful_saves, "saved_json": projected_model(disk)})
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
	print("RESISTANCE_CAP_LEGACY ", JSON.stringify(report))

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v059-consumers-"):
		quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false)
	var output: String = OS.get_environment("RESISTANCE_CAP_LEGACY_OUTPUT")
	if not output.is_empty(): legacy_probe(output)
	else:
		check(arena.save_build(), "Fresh isolated current-schema build saved")
		if legal_allocation():
			source_hits(); burn_and_order(); refund_during_burn(); natural_monsters()
		var report: Dictionary = {"checks":checks,"failures":failures,"sections":sections,"paid_points":route.size()-1,"version":arena.state.snapshot().version}
		var report_path: String = OS.get_environment("RESISTANCE_CAP_REPORT")
		if not report_path.is_empty(): FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
		print("Resistance cap actual gameplay: ", JSON.stringify(report))
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
