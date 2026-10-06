extends SceneTree
## v069 bounded actual-Main consumers. No historical-byte mode lives here.
## Setup uses lawful earned points, genuine allocations and owned-item moves.
const Model = preload("res://scripts/canonical_game_state.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const STAT := "physical_to_fire_conversion"
const PROFILE := {"enabled":true,"source_type":"physical","target_type":"fire","fraction":0.4}
# Source-supported Marauder path to Lava Lash, then its Fire Mastery.
const ROUTE: Array[String] = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "54396", "2550"]
const CLASS_ID := 1
const LEVEL := 5
const MASTERY := "48267"
const EFFECT := 65020
var arena: Node
var checks := 0
var failures := 0
var completed := false
var sections := {}
var report := {}
var blade := ""
var bow := ""
var groups := {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-9), "%s got=%s expected=%s" % [label, actual, expected])
func accepted(result: Variant, label: String) -> bool:
	return check(result is Dictionary and result.get("ok", false), label + ": " + JSON.stringify(result))
func section(test: Callable) -> bool:
	var before := checks
	completed = false
	test.call()
	check(completed, "Section returned normally: " + test.get_method())
	sections[test.get_method()] = checks - before
	return completed and failures == 0
func watchdog() -> void:
	push_error("CONVERSION_GAMEPLAY watchdog: an actual-Main section did not finish")
	quit(124)

func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear(); arena.particles.clear(); arena.floating_text.clear(); arena.rings.clear()
	arena.monster_runtime = arena.MonsterLifecycle.new(); arena.telegraphs = arena.TelegraphRuntime.new()
	arena.projectile_runtime = arena.Projectiles.new(); arena.feedback_runtime = arena.FeedbackRuntime.new(); arena.visual_cues = arena.VisualCueRuntime.new()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.leech_runtime.clear(); arena._sync_flasks(true)
	arena.damage_trace.clear(); arena.incoming_damage_trace.clear(); arena.burn_trace.clear(); arena.combat_trace.clear(); arena.attack_admission_trace.clear()
	arena.telegraph_trace.clear(); arena.event_counts.clear(); arena._ember_deaths.clear(); arena._ember_projectile_clock.clear()
	arena.group_cooldowns.reset(); arena.elapsed = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._burn_immunity_until = 0.0; arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena.auto_fire = false; arena.spawn_timer = 1000.0; arena._autosave_timer = 0.0; arena.wave = 1
	arena._simulation_accumulator = 0.0; arena._world_mode = "normal"; arena._geometry.configure("normal", arena.ARENA)
	arena._stats = arena.state.get_stats()
	for field: String in ["life_regen", "mana_regen", "shield_regen", "shield_recharge_rate"]: arena._stats[field] = 0.0
	arena._stats.max_health = 10000.0; arena._stats.max_mana = 10000.0
	arena.health = 1000.0; arena.shield = 0.0; arena.mana = 1000.0
	arena.kills = 0; arena.reward_kills = 0; arena.total_damage = 0.0; arena.total_shots = 0; arena.attack_timer = 0.0
	arena._refresh_leech_caps(); arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 690069; arena.critical_runtime.reset(690070); arena._player_evasion_entropy = 50.0
	arena.hud._process(0.0); arena.hud.close_panel()
	check(not arena.hud.is_blocking(), "Controlled actual-Main fixture is unpaused")
	for id: String in arena.Data.SKILLS: arena.cooldowns[id] = 0.0

func target(offset: Vector2 = Vector2(40, 0)) -> Dictionary:
	var value: Dictionary = arena._spawn_monster("crawler", arena.player_pos + offset, "ordinary", "", [], false)
	value.spawn = 0.0; value.health = 10000.0; value.max_health = 10000.0; value.shield = 0.0; value.max_shield = 0.0
	value.armour = 0.0; value.evasion = 0.0; value.evasion_entropy = 50.0; value.radius = 1.0
	value.resistances = {}; value.speed = 0.0; value.attack_timer = 1000.0; value.shield_regen = 0.0; value.shield_recharge_rate = 0.0
	return value
func readonly() -> Dictionary:
	return {"model":arena.state.snapshot(), "saves":arena.state.successful_saves, "disk":FileAccess.get_file_as_bytes(arena.build_save_path)}
func equip(uid: String) -> bool:
	if arena.state.equipped_items().get("weapon", "") == uid: return true
	return accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":"weapon"}, arena.state.revision(), arena.build_save_path), "Real weapon equip " + uid)
func own(base: String) -> String:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	var affixes: Array = []
	for id: String in ["whetstone_edge", "tempered_edge", "deepwell", "wellturn"]:
		affixes.append({"id":id, "tier":3, "value":int(Gear.affix_definition(id).tiers[2].max)})
	var item := {"id":uid, "base_id":base, "rarity":"rare", "item_level":16, "affixes":affixes}
	if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)), "Actual valid owned local weapon " + base): return ""
	return uid
func set_mastery(enabled: bool) -> bool:
	if arena.state.snapshot().talents.allocated.has(MASTERY) == enabled: return true
	var result: Dictionary = arena.state.allocate_passive(MASTERY, EFFECT, arena.state.revision(), arena.build_save_path) if enabled else arena.state.refund_passive(MASTERY, arena.state.revision(), arena.build_save_path)
	return accepted(result, "Real conversion mastery allocation" if enabled else "Real conversion mastery refund")
func packet_contract(packet: Dictionary, label: String) -> bool:
	if not check(packet.has("conversion") and packet.size() == 6, label + " has exactly the optional sixth packet field"): return false
	var p: float = packet.base.get("physical", 0.0)
	check(packet.conversion == {"source_type":"physical", "target_type":"fire", "fraction":0.4, "source_base":p, "remaining_base":p * (1.0 - 0.4), "converted_base":p * 0.4}, label + " preserves the frozen split descriptor")
	near(p, float(packet.assembly.intrinsic.get("physical", 0.0)) + float(packet.assembly.added.get("physical", 0.0)) + float(packet.assembly.get("weapon", {}).get("contribution", {}).get("physical", 0.0)), label + " original physical still equals all assembled sources")
	return true
func detail(record: Dictionary, type: String) -> Dictionary:
	var matches: Array = record.details.filter(func(row: Dictionary) -> bool: return row.type == type)
	if not check(matches.size() == 1, "Exactly one final-type detail row for " + type): return {}
	return matches[0]
func types_and_parts(record: Dictionary, native_fire: bool) -> bool:
	if not check(record.details.size() == 2 and record.components.size() == 2, "Main settles exactly physical and fire once"): return false
	var physical := detail(record, "physical"); var fire := detail(record, "fire")
	if not check(physical.has("parts") and fire.has("parts"), "Converted details retain nested lineage parts"): return false
	check(physical.parts.size() == 1 and physical.parts[0].lineage == ["physical"], "Residual physical retains its original lineage")
	check(fire.parts.size() == (2 if native_fire else 1), "Native and converted fire remain separate until final-type settlement")
	check(fire.parts.back().lineage == ["physical", "fire"], "Converted fire records both source and final type")
	if native_fire: check(fire.parts[0].lineage == ["fire"], "Native fire is the first independent part")
	return true

# This oracle reads real model sources, but never calls Damage.resolve or any
# conversion helper. Hand-derived numbers below separately pin its assumptions.
func scale_piece(base: float, packet: Dictionary, modifiers: Array, lineage: Array) -> float:
	var increased := 0.0; var more := 1.0
	for row: Dictionary in modifiers:
		var matches := true
		for tag: String in row.get("all_tags", []):
			if not packet.tags.has(tag): matches = false
		if not row.get("skills", []).is_empty() and not row.skills.has(packet.skill_id): matches = false
		var allowed: Array = row.get("damage_types", [])
		if not allowed.is_empty() and not lineage.any(func(type: String) -> bool: return allowed.has(type)): matches = false
		if matches:
			if row.mode == "increased": increased += float(row.value)
			elif row.mode == "more": more *= maxf(0.0, 1.0 + float(row.value))
	return base * maxf(0.0, 1.0 + increased) * more
func expected_raw(packet: Dictionary, snapshot: Dictionary, critical: float = 1.0) -> Dictionary:
	var p: float = packet.base.get("physical", 0.0); var f: float = packet.base.get("fire", 0.0)
	return {"physical":scale_piece(p * 0.6, packet, snapshot.modifiers, ["physical"]) * critical,
		"fire":(scale_piece(f, packet, snapshot.modifiers, ["fire"]) + scale_piece(p * 0.4, packet, snapshot.modifiers, ["physical", "fire"])) * critical}
func assert_raw(record: Dictionary, expected: Dictionary, label: String) -> void:
	near(record.before_defense_components.physical, expected.physical, label + " residual physical before defense")
	near(record.before_defense_components.fire, expected.fire, label + " joined final fire before defense")

func legal_source_and_owned_group() -> void:
	if not check(not ROUTE.is_empty() and not MASTERY.is_empty(), "Verified source route supplied before execution"): return
	if not accepted(arena.enter_town_test(arena.world_context().revision), "Actual test-town profile transition"): return
	if not accepted(arena.start_map(arena.map_draft().revision), "Actual test-map entry"): return
	blade = own("forgeblade"); bow = own("ashwood_bow")
	if [blade, bow].has("") or not equip(blade): return
	var cleave: String = arena.state.award_gem("skill:cleave")
	if not check(not cleave.is_empty(), "Real owned cleave gem"): return
	if not accepted(arena.state.move_item(cleave, {"kind":"skill_main", "group_id":"group_000009"}, arena.state.revision(), arena.build_save_path), "Actual cleave main-slot transaction"): return
	for group: Dictionary in arena.state.snapshot().skill_groups:
		var cast: Dictionary = arena.state.get_group_cast(group.id)
		if cast.get("ok", false): groups[cast.skill_id] = group.id
	if not check(groups.has("tornado") and groups.has("cleave"), "Actual owned skill groups exist"): return
	var support_ids := ["physical_focus", "fire_focus", "ignite", "focus", "efficiency"]
	if not check(Supports.compatibility_reason("tornado", support_ids, 5).is_empty(), "Exactly five compatible tornado supports"): return
	for index: int in range(support_ids.size()):
		var uid: String = arena.state.award_gem("support:" + support_ids[index])
		if not check(not uid.is_empty(), "Owned support " + support_ids[index]): return
		if not accepted(arena.state.move_item(uid, {"kind":"skill_support", "group_id":groups.tornado, "index":index}, arena.state.revision(), arena.build_save_path), "Real support slot " + str(index)): return
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level":LEVEL, "xp":0}; candidate.talents.class_id = CLASS_ID
	candidate.talents.allocated = [ROUTE[0]]; candidate.talents.masteries = {}; candidate.talents.normal_points = mini(LEVEL + 4, 123); candidate.revision += 1
	if not check(arena.state.Rules.reason(candidate).is_empty(), "Lawful source root fixture preserves earned-point budget"): return
	if not accepted(arena.state._commit(candidate, arena.build_save_path), "Commit source root fixture"): return
	for id: String in ROUTE.slice(1):
		if not check(arena.state.available_passives().has(id), "Reachable real allocation " + id): return
		if not accepted(arena.state.allocate_passive(id, 0, arena.state.revision(), arena.build_save_path), "Spend earned point " + id): return
	var before: Dictionary = arena.state.get_group_cast(groups.tornado)
	if not accepted(before, "Pre-mastery five-support tornado compiles"): return
	var rng: int = arena.rng.state; var crit: Dictionary = arena.critical_runtime.checkpoint(); var saves: int = arena.state.successful_saves; var points: int = arena.state.talent_points
	if not set_mastery(true): return
	near(arena.state.get_stats().get(STAT, 0.0), 0.4, "Actual selected effect derives original forty percent")
	check(arena.state.talent_points == points - 1 and arena.state.successful_saves == saves + 1, "Mastery spends one point and writes once")
	check(arena.rng.state == rng and arena.critical_runtime.checkpoint() == crit, "Actual allocation leaves combat RNG untouched")
	var cast: Dictionary = arena.state.get_group_cast(groups.tornado)
	if not accepted(cast, "Real source-to-five-support cast"): return
	check(cast.get("conversion_profile", {}) == PROFILE, "Compiled cast exposes exact conversion profile")
	if not packet_contract(cast.packets.parent, "Actual model parent") or not packet_contract(cast.packets.child, "Actual model child"): return
	check(var_to_bytes(cast.packets.secondary) == var_to_bytes(before.packets.secondary), "Real source allocation preserves existing pure-fire secondary packet bytes")
	check(not cast.packets.secondary.has("conversion"), "Existing secondary gets no invented conversion")
	var state_before := readonly(); var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.snapshot() == arena.state.snapshot(), "Schema44 actual source build reloads exactly")
	check(loaded.get_group_cast(groups.tornado) == cast and readonly() == state_before, "Reload and preview preserve source-derived frozen consumer without new saves")
	report.source = {"route":ROUTE, "mastery":MASTERY, "effect":EFFECT, "class_id":CLASS_ID, "level":LEVEL, "supports":support_ids, "version":arena.state.snapshot().version}
	completed = true

func actual_basic_and_cleave() -> void:
	var observations: Array = []
	for pair: Array in [[blade, "melee", "direct"], [bow, "projectile", "projectile"]]:
		if not equip(pair[0]): return
		clean(); var enemy := target()
		var cast: Dictionary = arena.state.get_basic_cast()
		if not accepted(cast, "Real " + pair[1] + " basic compiles") or not packet_contract(cast.packets[pair[2]], pair[1] + " basic"): return
		var packet: Dictionary = cast.packets[pair[2]]
		check(float(packet.assembly.weapon.contribution.physical) > 0.0, "Real local weapon contributes before conversion")
		var before := readonly()
		arena.auto_fire = true; arena._update_auto_attack(); arena._update_projectiles(0.15); arena.auto_fire = false
		if not check(arena.damage_trace.size() == 1, "Actual basic emits one settled hit"): return
		var record: Dictionary = arena.damage_trace[0]
		if not types_and_parts(record, false): return
		assert_raw(record, expected_raw(packet, cast.snapshot, record.get("critical", {}).get("multiplier", 1.0)), pair[1] + " basic")
		near(10000.0 - float(enemy.health), record.total, "Actual basic applies sum of final types once")
		check(arena.burn_runtime.is_empty(), "Converted basic fire never becomes automatically ignite-eligible")
		check(readonly() == before, "Basic conversion settlement adds no model write")
		observations.append(record.duplicate(true))
	if not equip(blade): return
	clean(); var enemy := target(); var cast: Dictionary = arena.state.get_group_cast(groups.cleave)
	if not accepted(cast, "Real allocated cleave") or not packet_contract(cast.packets.direct, "Actual cleave"): return
	if not check(arena.cast_group(groups.cleave), "Actual owned cleave cast accepted"): return
	if not check(arena.damage_trace.size() == 1, "Actual cleave settles one target"): return
	var record: Dictionary = arena.damage_trace[0]
	assert_raw(record, expected_raw(cast.packets.direct, cast.snapshot, record.get("critical", {}).get("multiplier", 1.0)), "Actual cleave")
	near(10000.0 - float(enemy.health), record.total, "Actual cleave life loss equals settled total")
	check(arena.burn_runtime.is_empty() and not Supports.compatibility_reason("cleave", ["ignite"], 5).is_empty(), "Converted cleave retains original ignite support gate")
	observations.append(record.duplicate(true)); report.basic_and_cleave = observations
	completed = true

func controlled_stats(critical: bool = false, resolute: bool = false) -> Dictionary:
	return {"damage":100.0, STAT:0.4, "physical_increased":0.5, "fire_increased":0.25, "elemental_increased":0.2, "global_increased":0.1,
		"attack_added_physical":10.0, "attack_added_fire":7.0, "added_damage":{"attack":{"physical":10.0,"fire":7.0}},
		"crit_base_chance":1.0 if critical else 0.0, "crit_base_multiplier":2.0, "resolute_technique":1.0 if resolute else 0.0,
		"max_health":10000.0, "max_mana":10000.0, "attack_life_leech":0.01, "physical_attack_life_leech":0.02,
		"attack_mana_leech":0.02, "physical_attack_mana_leech":0.03}

func focus_defense_leech_and_critical() -> void:
	var observations: Array = []
	for policy: Array in [[false, false], [true, false], [true, true]]:
		clean(); var stats := controlled_stats(policy[0], policy[1]); var snapshot := Combat.snapshot(stats, [])
		# One dual-type entry must match once; repeated IDs on different support
		# clauses must remain separate. An unrelated spell entry must not match.
		snapshot.modifiers.append({"id":"dual_lineage_once", "mode":"increased", "value":0.3, "all_tags":["hit","attack"], "damage_types":["physical","fire"]})
		snapshot.modifiers.append({"id":"wrong_delivery", "mode":"more", "value":9.0, "all_tags":["spell"], "damage_types":["physical","fire"]})
		var cast := Compiler.compile_group("cleave", snapshot, ["physical_focus"])
		if not accepted(cast, "Controlled genuine compiler cleave") or not packet_contract(cast.packets.direct, "Controlled cleave"): return
		var one := target(); one.armour = 240.0; one.resistances.fire = 0.25
		var two := target(Vector2(45, 10)); two.armour = 240.0; two.resistances.fire = 0.25; two.health = 10.0; two.shield = 5.0
		var before: Dictionary = arena.critical_runtime.checkpoint()
		if not check(arena._execute_compiled(cast), "Actual controlled cleave executes"): return
		if not check(arena.damage_trace.size() == 2, "Single accepted cast settles two target hits"): return
		var critical := 2.0 if policy[0] and not policy[1] else 1.0
		var p: float = cast.packets.direct.base.physical; var f: float = cast.packets.direct.base.fire
		var expected_physical := p * 0.6 * 1.9 * 1.2 * critical
		var expected_converted := p * 0.4 * 2.35 * 1.2 * 0.8 * critical
		var expected_native := f * 1.85 * 0.8 * critical
		var physical_final := expected_physical * (1.0 - 240.0 / (240.0 + 5.0 * expected_physical))
		var fire_final := (expected_converted + expected_native) * 0.75
		for record: Dictionary in arena.damage_trace:
			if not types_and_parts(record, true): return
			assert_raw(record, {"physical":expected_physical, "fire":expected_converted + expected_native}, "Hand-derived focus/dual-lineage case")
			near(record.components.physical, physical_final, "Armour depends on residual physical hit size")
			near(record.components.fire, fire_final, "Current fire resistance applies once after joining fire parts")
			var fire := detail(record, "fire"); var converted: Dictionary = fire.parts.back()
			near(converted.more, 0.96, "Both same-ID focus clauses apply once: 1.2 times 0.8")
			check(converted.modifiers.count("dual_lineage_once") == 1 and converted.modifiers.count("support:physical_focus") == 2, "Entry identity preserves one dual-type match and two independent same-ID clauses")
			check(converted.modifier_indices.size() == converted.modifiers.size(), "Modifier entry indices accompany every applied clause")
			var actual: float = record.shield_spent + record.health_lost
			var physical_share := actual * physical_final / (physical_final + fire_final)
			if not check(record.has("leech"), "Actual settled attack admits leech"): return
			near(record.leech.health, actual * 0.01 + physical_share * 0.02, "Life leech uses all actual loss plus actual residual physical share")
			near(record.leech.mana, actual * 0.02 + physical_share * 0.03, "Mana leech excludes converted fire from physical-only leech")
			if record.target_id == two.id: near(actual, 15.0, "Leech excludes all overkill and includes five shield plus ten life")
		near(10000.0 - float(one.health), physical_final + fire_final, "Actual Main subtracts summed final types once")
		var after: Dictionary = arena.critical_runtime.checkpoint()
		check(after.draws == before.draws and after.events - before.events == (1 if critical == 2.0 else 0), "Critical freezes exactly once per cast; certain roll draws no RNG; Resolute cancels it")
		check(arena.burn_runtime.is_empty(), "Controlled converted cleave still cannot attach burn")
		observations.append({"policy":policy, "hits":arena.damage_trace.duplicate(true), "critical":after})
	report.focus_defense_leech_critical = observations
	completed = true

func tornado_ignite_and_ember() -> void:
	var observations: Array = []
	for support: String in ["ignite", "ember_proliferation"]:
		clean(); var stats := controlled_stats(true); stats.fire_dot_multiplier_add = 0.4; stats.damaging_ailments_faster = 0.25
		var cast := Compiler.compile_group("tornado", Combat.snapshot(stats, []), ["physical_focus", "fire_focus", support, "focus", "efficiency"])
		if not accepted(cast, "Five-slot conversion/focus/burn tornado"): return
		var enemy := target(Vector2(60, 0)); enemy.resistances.fire = 0.25
		if not check(arena._execute_compiled(cast), "Actual supported tornado emits"): return
		arena._update_projectiles(0.2)
		if not check(not arena.damage_trace.is_empty(), "Actual tornado parent contacts target"): return
		var record: Dictionary = arena.damage_trace[0]
		assert_raw(record, expected_raw(cast.packets.parent, cast.snapshot, 2.0), "Actual supported tornado parent")
		var fire := detail(record, "fire")
		if not check(fire.has("parts"), "Burn source hit exposes lineage parts"): return
		# Each focus has two independently applicable clauses on the converted piece.
		near(fire.parts.back().more, 0.96 * 0.96 * 1.25 * 0.75, "Two element focuses plus direct-hit penalty apply once each")
		var burn: Dictionary = arena.burn_runtime.status_for("monster", enemy.id)
		if not check(not burn.is_empty(), "Existing supported tornado attaches burn from final fire"): return
		var expected_dps: float = record.before_defense_components.fire * float(cast.snapshot.burn_policy.rate_fraction) * 1.4 * 1.25
		near(burn.raw_dps, expected_dps, "Burn derives once from native-plus-converted pre-defense fire, then DoT and faster once")
		near(burn.remaining, 3.0 / 1.25, "Faster preserves compressed duration")
		near(cast.burn_profile.roles.parent.dps * 2.0, expected_dps, "Preview and actual burn agree with one frozen critical multiplier")
		var health: float = enemy.health; var before := readonly(); var rng: int = arena.rng.state; var crit: Dictionary = arena.critical_runtime.checkpoint(); var leech: Dictionary = arena.leech_runtime.snapshot()
		arena.elapsed = 0.5; arena._advance_monster_burns(0.5)
		# Contact happens during the projectile step; inspect the status clock
		# instead of assuming that the collision occurred at elapsed zero.
		var tick_time := 0.5 - float(burn.get("last_time", 0.0))
		near(health - float(enemy.health), expected_dps * tick_time * 0.75, "Actual DOT applies current fire resistance and never converts again")
		check(arena.critical_runtime.checkpoint() == crit and arena.rng.state == rng and arena.leech_runtime.snapshot() == leech and readonly() == before, "DOT changes no critical RNG, loot RNG, leech or model state")
		if support == "ember_proliferation":
			var receiver := target(Vector2(150, 0)); arena._damage_enemy(enemy, 1000000.0, Color.WHITE)
			var inherited: Dictionary = arena.burn_runtime.status_for("monster", receiver.id)
			if not check(not inherited.is_empty(), "Actual death carries existing ember to a nearby survivor"): return
			near(inherited.raw_dps, expected_dps, "Ember inherits final calculated DPS without reapplying conversion or DoT factors")
			check(inherited.provenance.ember_generation == 1, "Existing one-hop ember provenance survives conversion")
		observations.append({"support":support, "hit":record, "burn":burn})
	report.burning = observations
	completed = true

func pure_fire_and_dot_unchanged() -> void:
	var observations: Array = []
	for amount: float in [0.0, 0.4]:
		clean(); var stats := controlled_stats(); stats[STAT] = amount
		var cast := Compiler.compile_group("meteor", Combat.snapshot(stats, []), ["ignite"])
		if not accepted(cast, "Actual unchanged pure-fire meteor"): return
		check(not cast.has("conversion_profile") and not cast.packets.direct.has("conversion"), "Pure-fire cast gets no conversion profile or packet marker")
		var enemy := target(); enemy.resistances.fire = 0.25
		if not check(arena._execute_compiled(cast), "Actual pure-fire cast admitted"): return
		arena.elapsed = 0.5; arena._advance_monster_burns(0.5)
		observations.append({"packet":cast.packets.direct, "hits":arena.damage_trace.duplicate(true), "burns":arena.burn_runtime.statuses(), "burn_trace":arena.burn_trace.duplicate(true), "health":enemy.health})
	check(var_to_bytes(observations[0]) == var_to_bytes(observations[1]), "Pure-fire actual hits and DOT remain byte-identical with conversion stat present")
	report.pure_fire = observations[1]
	completed = true

func frozen_parent_child_return_and_secondary() -> void:
	if not equip(bow) or not set_mastery(true): return
	for pair: Array in [["return_mantle", "body_armour"], ["detonation_charm", "amulet"]]:
		var found := ""
		for uid: String in arena.state.snapshot().items:
			if arena.state.item(uid).definition_id == "equipment:" + pair[0]: found = uid; break
		if not check(not found.is_empty(), "Original fixed owned item " + pair[0]): return
		if not accepted(arena.state.move_item(found, {"kind":"equipment", "slot_id":pair[1]}, arena.state.revision(), arena.build_save_path), "Real effect equipment transaction " + pair[0]): return
	clean(); var cast: Dictionary = arena.state.get_group_cast(groups.tornado)
	if not accepted(cast, "Real owned five-slot frozen tornado"): return
	if not check(cast.snapshot.effects.has("return_on_range") and cast.snapshot.effects.has("explode_on_flight_end"), "Real starting mantle and charm provide return and secondary"): return
	var first := target(Vector2(60, 0))
	if not check(arena.cast_group(groups.tornado), "Real allocated tornado fires"): return
	if not check(not arena.projectiles.is_empty(), "Real parent carriers exist"): return
	var frozen: PackedByteArray = var_to_bytes(arena.projectiles[0].snapshot)
	var parent_packet: PackedByteArray = var_to_bytes(cast.packets.parent); var child_packet: PackedByteArray = var_to_bytes(cast.packets.child)
	var old_critical: Dictionary = arena.critical_runtime.checkpoint()
	if not set_mastery(false) or not equip(blade): return
	near(arena.state.get_stats().get(STAT, 0.0), 0.0, "Real refund removes conversion only from future casts")
	check(not arena.state.get_group_cast(groups.tornado).has("conversion_profile"), "Future group rebuild omits refunded conversion")
	for shot: Dictionary in arena.projectiles: check(var_to_bytes(shot.snapshot) == frozen, "Refund and weapon swap preserve original parent snapshot")
	arena._update_projectiles(0.4)
	if not check(not arena.damage_trace.is_empty() and int(arena.event_counts.get("split", 0)) > 0, "Old parents contact and naturally split after refund"): return
	var record: Dictionary = arena.damage_trace[0]
	assert_raw(record, expected_raw(cast.packets.parent, cast.snapshot, record.get("critical", {}).get("multiplier", 1.0)), "Frozen old parent after refund")
	check(first.health < 10000.0 and arena.projectiles.size() == int(cast.initial_count) * 3, "All real parents create original child count")
	for shot: Dictionary in arena.projectiles:
		check(shot.generation == 1 and var_to_bytes(shot.snapshot) == frozen, "Children inherit original conversion snapshot")
	if not check(not arena.projectiles.is_empty(), "Real children remain for contact test"): return
	var child: Dictionary = arena.projectiles[0]
	var child_target := target(Vector2(child.pos) + Vector2(child.velocity).normalized() * 30.0 - arena.player_pos)
	arena._update_projectiles(0.2)
	var child_hits: Array = arena.damage_trace.filter(func(hit: Dictionary) -> bool: return hit.target_id == child_target.id and hit.projectile_id == child.id)
	if not check(child_hits.size() == 1, "Real frozen child settles exactly once on outward contact"): return
	assert_raw(child_hits[0], expected_raw(cast.packets.child, cast.snapshot, child_hits[0].get("critical", {}).get("multiplier", 1.0)), "Child converts its own assembled base once")
	arena._update_projectiles(0.4)
	if not check(not arena.projectiles.is_empty() and int(arena.event_counts.get("return_started", 0)) > 0, "Frozen children begin the genuine return phase"): return
	for shot: Dictionary in arena.projectiles:
		check(shot.state == "returning" and var_to_bytes(shot.snapshot) == frozen, "Returning children preserve all frozen conversion data")
	check(arena.critical_runtime.checkpoint() == old_critical, "Parents, children and return use one original critical event")
	var returning: Dictionary = arena.projectiles[0]
	arena.enemies.clear(); arena.damage_trace.clear()
	var return_target := target(Vector2(returning.pos) + Vector2(returning.velocity).normalized() * 20.0 - arena.player_pos)
	arena._update_projectiles(0.10)
	var return_hits: Array = arena.damage_trace.filter(func(hit: Dictionary) -> bool: return hit.target_id == return_target.id and hit.projectile_id == returning.id)
	if not check(return_hits.size() == 1, "Returning frozen child makes a real new-target hit"): return
	assert_raw(return_hits[0], expected_raw(cast.packets.child, cast.snapshot, return_hits[0].get("critical", {}).get("multiplier", 1.0)), "Return never converts a second time")
	var remaining: float = float(returning.lifetime) - float(returning.age)
	var endpoint: Vector2 = Vector2(returning.pos) + Vector2(returning.velocity) * remaining
	arena.enemies.clear(); arena.damage_trace.clear()
	var end_target := target(endpoint + Vector2(returning.velocity).normalized().orthogonal() * 25.0 - arena.player_pos)
	arena._update_projectiles(remaining + 0.02)
	check(arena.projectiles.is_empty() and int(arena.event_counts.get("explosion", 0)) > 0, "Original real-cast children naturally expire and emit existing secondary")
	var explosions: Array = arena.damage_trace.filter(func(hit: Dictionary) -> bool: return hit.target_id == end_target.id and hit.tags.has("secondary"))
	if not check(not explosions.is_empty(), "Existing pure-fire secondary reaches a real target after refund"): return
	for hit: Dictionary in explosions:
		check(hit.components.keys() == ["fire"] and hit.details.size() == 1, "Natural secondary remains one pure-fire final type")
		var expected: float = scale_piece(cast.packets.secondary.base.fire, cast.packets.secondary, cast.snapshot.modifiers, ["fire"]) * float(hit.get("critical", {}).get("multiplier", 1.0))
		near(hit.before_defense_components.fire, expected, "Existing secondary receives no physical lineage or second conversion")
	check(var_to_bytes(cast.packets.parent) == parent_packet and var_to_bytes(cast.packets.child) == child_packet, "Carrier lifecycle cannot mutate either frozen compiled packet")
	report.frozen = {"parent":record, "child":child_hits[0], "return":return_hits[0], "secondary":explosions, "events":arena.event_counts.duplicate(true)}
	if not set_mastery(true): return
	completed = true

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v069-conversion-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78); return
	create_timer(30.0).timeout.connect(watchdog)
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	for test: Callable in [legal_source_and_owned_group, actual_basic_and_cleave, focus_defense_leech_and_critical, tornado_ignite_and_ember, pure_fire_and_dot_unchanged, frozen_parent_child_return_and_secondary]:
		if not section(test): break
	report.merge({"checks":checks, "failures":failures, "sections":sections, "scope":"Bounded headless actual Main, real source allocations and owned support/equipment transactions; no visual or Windows acceptance; no historical-byte oracle"})
	var output := OS.get_environment("CONVERSION_GAMEPLAY_REPORT")
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("CONVERSION_GAMEPLAY ", JSON.stringify({"checks":checks, "failures":failures, "sections":sections}))
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
