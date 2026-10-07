extends SceneTree
## Bounded real Main integration. All enemies come from actual map admission.
## Position/resource/cooldown probes are controlled consumer fixtures, not a
## claim of natural player progression, equipment power, or full-map combat.
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Chill = preload("res://scripts/combat/chill_rules.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const STAT := "damage_taken_from_mana_before_life"
var arena: Node
var checks := 0
var failures := 0
var failed_labels: Array[String] = []
var sections: Dictionary = {}
var report: Dictionary = {"method":"Real Main test-town craft/start; existing wave6 ginkgo residents; controlled movement/resources, no actor injection", "entries":[], "receipts":[]}
var frost: Dictionary = {}
var second_frost: Dictionary = {}
var initial_ids: Array[int] = []
var initial_records: Array = []
var normal_bytes := PackedByteArray()
var route: Array = []

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1; failed_labels.append(label); printerr("FAIL: " + label)
	return value
func accepted(value: Dictionary, label: String) -> bool:
	return check(bool(value.get("ok", false)), label + ": " + str(value.get("reason", "")))
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual - expected) < 0.001, "%s: %.9f vs %.9f" % [label, actual, expected])
func pause() -> void:
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	arena.hud._process(0.0)
	for unused: int in range(4): arena.hud.close_panel()
func ids() -> Array[int]:
	var result: Array[int] = []
	for enemy: Dictionary in arena.enemies: result.append(int(enemy.id))
	return result
func corridor() -> Vector2: return arena.ARENA.position + Vector2(1200, 2150)
func group_for(skill: String) -> String:
	for row: Dictionary in arena.state.snapshot().skill_groups:
		var compiled: Dictionary = arena.state.get_group_cast(row.id)
		if bool(compiled.get("ok", false)) and compiled.get("skill_id", "") == skill: return str(row.id)
	return ""
func status() -> Dictionary:
	var entries: Array = arena.chill_statuses()
	return entries[0] if entries.size() == 1 else {}
func atomic() -> PackedByteArray:
	return var_to_bytes([arena.health, arena.shield, arena.mana, arena.invulnerable, arena.damage_delay,
		arena._player_evasion_entropy, arena.incoming_damage_trace, arena.attack_admission_trace,
		arena.chill_runtime._state, arena.chill_runtime._last_settlement_at, arena.rng.state,
		arena.critical_runtime.checkpoint(), arena.group_cooldowns.snapshot(), arena.cooldowns,
		arena.feedback_runtime._pending, arena.feedback_runtime._visible, arena.state.snapshot(),
		arena.state.successful_saves, FileAccess.get_file_as_bytes(arena.build_save_path)])
func controlled_resources() -> void:
	# Only consumer values are overridden. The source fraction remains the actual
	# derived 34098 value, except the explicitly named 100% mana boundary below.
	arena._stats = arena.state.get_stats()
	for key: String in ["life_regen", "mana_regen", "shield_regen", "shield_regeneration_rate", "shield_recharge_rate", "armour", "evasion", "fire_resistance", "cold_resistance", "lightning_resistance"]: arena._stats[key] = 0.0
	arena._stats.max_health = 1000.0; arena._stats.max_mana = 1000.0; arena._stats.max_shield = 1000.0
	arena._stats.move_speed = 200.0
	arena.health = 1000.0; arena.mana = 500.0; arena.shield = 0.0
	arena.invulnerable = 0.0; arena.damage_delay = 0.0; arena._player_evasion_entropy = 50.0
	arena.attack_timer = 1000.0; arena._autosave_timer = 0.0
func reset_probe() -> void:
	arena.telegraphs.reset(); arena.chill_runtime.reset(); arena.burn_runtime.reset(); arena.shock_runtime.reset()
	arena.incoming_damage_trace.clear(); arena.telegraph_trace.clear(); arena.attack_admission_trace.clear()
	arena.feedback_runtime.reset(); arena.group_cooldowns.reset()
	for key: String in arena.cooldowns: arena.cooldowns[key] = 0.0
	for enemy: Dictionary in arena.enemies:
		enemy.speed = 0.0; enemy.attack_timer = 1000.0; enemy.knockback = Vector2.ZERO
	controlled_resources(); arena.player_pos = corridor(); arena.player_facing = Vector2.RIGHT
	if not frost.is_empty(): frost.pos = arena.player_pos + Vector2(100, 0); frost.spawn = 0.0
	if not second_frost.is_empty(): second_frost.pos = arena.player_pos + Vector2(-100, 0); second_frost.spawn = 0.0
func context(at: Variant = null) -> Dictionary:
	return {"chill_policy": Chill.ENEMY_POLICY.duplicate(true), "at": arena.elapsed if at == null else at, "phase":"controlled_consumer", "skill_id":"frost_chill"}
func hit(components: Dictionary = {"cold": 10.0}) -> bool:
	return arena.hit_player_components(components, int(frost.id), ["hit", "attack", "area"], context())
func warning(enemy: Dictionary) -> Dictionary:
	enemy.attack_timer = 0.0
	arena.tick(0.0)
	var result: Dictionary = arena.telegraphs.state_for(int(enemy.id))
	if not check(not result.is_empty(), "Existing resident starts real Main warning"): return {}
	enemy.attack_timer = 1000.0
	return result
func step_move(delta: float) -> float:
	var before: Vector2 = arena.player_pos
	Input.action_press("move_right"); arena.tick(delta); Input.action_release("move_right")
	return arena.player_pos.x - before.x

func source_fixture() -> bool:
	var start_checks := checks
	var root_id: String = SourceTree.Data.start_for_class(3)
	var paths: Dictionary = {root_id: [root_id]}
	var queue: Array[String] = [root_id]
	var index := 0
	while index < queue.size():
		var current: String = queue[index]; index += 1
		if current == "34098": route = paths[current]; break
		for node_id: String in SourceTree.Data.adjacency(current):
			var node: Dictionary = SourceTree.Data.node(node_id)
			if paths.has(node_id) or node.type in ["mastery", "start"] or node.source.get("isProxy", false) or node.source.get("isBlighted", false): continue
			if SourceTree.node_effect(node_id, 0, 35).status != "full": continue
			paths[node_id] = paths[current] + [node_id]; queue.append(node_id)
	if not check(route.size() == 8, "Existing legal Witch source route spends seven points"): return false
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level":3, "xp":0}; candidate.talents.class_id = 3
	candidate.talents.allocated = [route[0]]; candidate.talents.normal_points = 7; candidate.revision += 1
	if not check(arena.state.Rules.reason(candidate).is_empty(), "Earned-budget source fixture obeys canonical schema"): return false
	if not accepted(arena.state._commit(candidate, arena.build_save_path), "Commit isolated lawful source root"): return false
	for node_id: String in route.slice(1):
		if not accepted(arena.state.allocate_passive(node_id, 0, arena.state.revision(), arena.build_save_path), "Actual guarded allocation " + node_id): return false
	near(float(arena.state.get_stats()[STAT]), 0.4, "Real 34098 source derives forty-percent mana diversion")
	check(arena.state.talent_points == 0, "Seven source transactions consume exactly seven points")
	report.source = {"route":route, "fraction":arena.state.get_stats()[STAT], "fixture":"lawful level3 earned-budget fixture, not naturally earned play"}
	sections.legal_source = checks - start_checks
	return true

func enter(map_id: String, count: int) -> bool:
	if not accepted(arena.craft_map(map_id, [], [], arena.map_draft().revision), "Real test-town map draft " + map_id): return false
	var rng_before: int = arena.rng.state
	if not accepted(arena.start_map(arena.map_draft().revision), "Real Main start_map " + map_id): return false
	pause()
	var world: Dictionary = arena.world_context()
	check(arena.enemies.size() == count and arena.map_spawn_records().size() == count and world.initial_monsters == count, "All %d map roots including boss exist at entry" % count)
	check(world.awake_monsters == 0 and world.boss_phase == "resident", "Entire entry roster sleeps before approach")
	check(arena.rng.state == rng_before, "Complete exploration admission preserves gameplay RNG")
	check(arena.chill_statuses().is_empty() and arena.chill_runtime.is_empty(), "Map entry starts with no player chill")
	check(arena.ARENA.size == Vector2(3600, 2400) and arena.get_node("WorldCamera").zoom == Vector2(0.65, 0.65), "Exploration bounds and camera zoom remain unchanged")
	check(arena.get_node("WorldCamera").position.distance_to(View.follow_position(arena.player_pos, arena.ARENA)) < 0.001, "Camera follows authored entry immediately")
	report.entries.append({"map_id":map_id, "world":world, "ids":ids()})
	return true

func resident_flow() -> bool:
	var start_checks := checks
	if not enter("ginkgo_arcade", 37): return false
	check(arena.wave == 6 and arena._map_run.profile.normal_ids.is_empty() and arena._map_run.profile.special_ids.is_empty(), "Authored wave6 map has no added patrol or damage modifiers")
	initial_ids = ids(); initial_records = arena.map_spawn_records()
	for enemy: Dictionary in arena.enemies:
		if enemy.template_id == "frost_guard":
			if frost.is_empty(): frost = enemy
			elif second_frost.is_empty(): second_frost = enemy
	if not check(not frost.is_empty() and not second_frost.is_empty(), "Unmodified pregenerated roster contains two real frost guards"): return false
	check(frost.root_id == frost.id and frost.generation == 0 and frost.reward_eligible and frost.has("map_spawn_key"), "Selected frost identity retains genuine initial root provenance")
	check(float(arena.invulnerable) == 1.5, "Actual map start retains original 1.5-second protection")
	var protected_before := atomic()
	check(not hit() and atomic() == protected_before, "Actual opening protection rejects chill and all resource changes")
	arena.tick(1.6)
	check(ids() == initial_ids and arena.monster_runtime.queue.is_empty() and arena.world_context().awake_monsters == 0, "Dormant full roster advances without waking or admitting new actors")
	check(frost.spawn == 0.0 and arena.chill_statuses().is_empty(), "Distant birth clock expires without applying chill")
	# Existing far boss keeps recovery and cooldown while asleep, then real
	# shield damage wakes it. No actor or reward ledger is synthesized.
	var boss: Dictionary = {}
	for enemy: Dictionary in arena.enemies:
		if enemy.id == arena._map_run.boss_id: boss = enemy; break
	if not check(not boss.is_empty() and boss.max_shield > 2.0, "Existing sleeping map boss supplies shield probe"): return false
	var rate: float = boss.get("shield_recharge_rate", boss.shield_regen)
	boss.shield = float(boss.max_shield) - 2.0; boss.damage_delay = 0.05; boss.attack_timer = 0.8
	var shield_before: float = boss.shield
	arena.tick(0.1)
	near(boss.shield, shield_before + rate * 0.05, "Sleeping offscreen recovery consumes only time after delay")
	near(boss.attack_timer, 0.7, "Sleeping offscreen attack cooldown advances")
	check(not boss.exploration_awake, "Resource recovery alone does not wake distant actor")
	arena._damage_enemy(boss, 0.25, Color.WHITE)
	check(boss.exploration_awake and arena.world_context().boss_phase == "active", "Real offscreen damage wakes existing boss")
	reset_probe()
	var wall: Rect2 = arena.world_geometry().walls[1]
	frost.pos = Vector2(wall.position.x - float(frost.radius) - 8.0, wall.get_center().y)
	arena.player_pos = Vector2(wall.end.x + arena.PLAYER_RADIUS + 8.0, wall.get_center().y)
	check(frost.pos.distance_to(arena.player_pos) < 450.0 and not arena._terrain_visible(frost.pos, arena.player_pos), "Wall probe is inside450 with blocked line of sight")
	arena.tick(0.0)
	check(not frost.exploration_awake, "Wall blocks wake of original frost resident")
	frost.pos = corridor() + Vector2(451, 0); arena.player_pos = corridor()
	arena.tick(0.0)
	check(not frost.exploration_awake, "Clear451 distance stays asleep")
	step_move(0.01)
	check(frost.exploration_awake and ids() == initial_ids, "Actual held-input approach crosses450 and wakes same identity")
	check(arena.get_node("WorldCamera").position.distance_to(View.follow_position(arena.player_pos, arena.ARENA)) < 0.001, "Real approach updates followed camera")
	check(arena.map_spawn_records() == initial_records, "Controlled probes leave authoritative spawn provenance unchanged")
	sections.resident_exploration = checks - start_checks
	return true

func natural_warning_and_receipt() -> bool:
	var start_checks := checks
	reset_probe()
	var before_time: float = arena.elapsed
	var old_rng: int = arena.rng.state
	var attack: Dictionary = warning(frost)
	if attack.is_empty(): return false
	near(attack.profile.windup_seconds, 0.9, "Real frost warning retains0.9 seconds")
	near(attack.profile.radius, 90.0, "Real frost circle retains radius90")
	near(attack.profile.damage_multiplier, 0.8, "Real frost hit retains original0.8 multiplier")
	near(attack.packet.base.cold, float(frost.damage) * 0.8, "Original frost contact budget forms unchanged cold packet")
	check(attack.center == arena.player_pos and attack.chill_policy == Chill.ENEMY_POLICY, "Warning locks player position and exact enemy chill policy")
	arena.tick(0.4)
	check(arena.incoming_damage_trace.is_empty() and arena.chill_statuses().is_empty(), "Warning alone never damages or chills")
	var expected: Dictionary = Defense.incoming_source_hit(attack.packet.base, arena._stats, arena.shield, arena.health, "player", 0.0, arena.mana, arena._stats[STAT])
	if not accepted(expected, "Independent authoritative Defense receipt succeeds"): return false
	arena.tick(0.6)
	if not check(arena.incoming_damage_trace.size() == 1 and arena.telegraph_trace.size() == 1, "Real warning resolves once even when tick overshoots deadline"): return false
	var receipt: Dictionary = arena.incoming_damage_trace[0]
	if not accepted(receipt, "Actual Main incoming receipt is successful"): return false
	var projected: Dictionary = receipt.duplicate(true); projected.erase("source_id"); projected.erase("chill_applied")
	check(projected == expected, "Every original Defense receipt field is byte-value unchanged")
	near(receipt.damage_total, float(frost.damage) * 0.8, "Unmitigated natural frost damage remains exact")
	near(receipt.mana_spent, receipt.damage_total * 0.4, "Actual allocated source diverts40 percent after shield")
	near(receipt.health_lost, receipt.damage_total * 0.6, "Actual allocated source leaves60 percent life damage")
	var chilled := status()
	if not check(not chilled.is_empty(), "Living actual cold recipient acquires one chill"): return false
	near(chilled.applied_at, before_time + 0.9, "Status begins at actual warning hit time, not end of overshooting tick")
	near(chilled.expires_at, before_time + 2.1, "Expiry is actual hit time plus1.2")
	near(chilled.movement_multiplier, 0.75, "Enemy policy reduces only walking factor by25 percent")
	check(arena.rng.state == old_rng, "Warning, original receipt and chill attachment introduce no RNG draws")
	var detached: Array = arena.chill_statuses(); detached[0].expires_at = 99999.0; detached[0].position = Vector2.ZERO; detached.clear()
	check(arena.chill_statuses().size() == 1 and status() == chilled, "Main getter list and entries cannot mutate authoritative chill")
	report.receipts.append({"kind":"natural_warning", "attack":attack, "settlement":receipt.duplicate(true), "chill":chilled, "elapsed":arena.elapsed})
	sections.natural_warning_receipt = checks - start_checks
	return true

func movement_and_refresh() -> bool:
	var start_checks := checks
	# Continue the real status whose deadline has1.1 seconds remaining.
	var native_stats: Dictionary = arena._stats.duplicate(true)
	arena.attack_timer = 2.0; arena.cooldowns.dash = 2.0
	arena.shield = 0.0; arena.damage_delay = 0.0; arena._stats.shield_recharge_rate = 10.0
	near(step_move(0.3), 45.0, "Real held-input walk moves200*0.75*0.3")
	near(arena.attack_timer, 1.7, "Player basic attack clock is not slowed")
	near(arena.cooldowns.dash, 1.7, "Skill cooldown clock is not slowed")
	near(arena.shield, 3.0, "Shield recovery rate is not slowed")
	near(arena._stats.attack_speed, native_stats.attack_speed, "Derived attack speed remains unchanged")
	near(step_move(0.6), 90.0, "Walking remains75 percent before expiry")
	near(step_move(0.4), 70.0, "Cross-expiry movement splits0.2 chilled plus0.2 normal")
	check(arena.chill_statuses().is_empty() and arena.chill_runtime.is_empty(), "Exact expired status is pruned after consuming movement interval")
	near(step_move(0.1), 20.0, "Walking returns to100 percent after expiry")
	check(arena._stats.move_speed == native_stats.move_speed, "Chill never rewrites persistent or derived movement stat")
	reset_probe()
	var start_time: float = arena.elapsed
	if warning(frost).is_empty(): return false
	arena.tick(0.4)
	if warning(second_frost).is_empty(): return false
	arena.tick(0.5)
	var first := status()
	if not check(not first.is_empty() and arena.incoming_damage_trace.size() == 1, "First natural resident warning applies first status"): return false
	near(first.expires_at, start_time + 2.1, "First hit deadline is0.9+1.2")
	arena.tick(0.4)
	var refreshed := status()
	if not check(not refreshed.is_empty() and arena.incoming_damage_trace.size() == 2, "Second real warning lands after original hit protection expires"): return false
	check(arena.chill_statuses().size() == 1 and refreshed.source_id == second_frost.id, "Two actual sources refresh the single player status")
	near(refreshed.expires_at, maxf(first.expires_at, start_time + 1.3 + 1.2), "Refresh deadline is max(old, actual second hit+1.2)")
	near(refreshed.movement_multiplier, 0.75, "Repeated hits do not stack chill strength")
	check(refreshed.expires_at < float(first.expires_at) + 1.2, "Refresh does not accumulate durations")
	report.receipts.append({"kind":"two_real_warnings", "hits":arena.incoming_damage_trace.duplicate(true), "first":first, "refreshed":refreshed})
	sections.movement_refresh = checks - start_checks
	return true

func eligibility_and_atomicity() -> bool:
	var start_checks := checks
	for scenario: Dictionary in [{"name":"shield_only", "shield":100.0, "mana":500.0, "fraction":0.4}, {"name":"mana_and_life", "shield":0.0, "mana":500.0, "fraction":0.4}, {"name":"mana_shortfall", "shield":0.0, "mana":1.0, "fraction":0.4}, {"name":"pure_mana_consumer_boundary", "shield":0.0, "mana":500.0, "fraction":1.0}]:
		reset_probe(); arena.shield = scenario.shield; arena.mana = scenario.mana
		arena._stats[STAT] = scenario.fraction
		if not check(hit({"cold":10.0}), "Real Main cold consumer admits " + scenario.name): return false
		if not check(arena.incoming_damage_trace.size() == 1, "Admitted consumer creates one Defense receipt"): return false
		var receipt: Dictionary = arena.incoming_damage_trace[0]
		if not accepted(receipt, "Defense consumer receipt succeeds"): return false
		var actual: Dictionary = Chill.actual_cold_loss(receipt)
		if not accepted(actual, "Authoritative cold resource attribution validates"): return false
		check(actual.actual_cold > 0.0 and arena.chill_statuses().size() == 1, "Actual shield+mana+life cold loss qualifies " + scenario.name)
		if scenario.name == "pure_mana_consumer_boundary":
			check(receipt.health_lost == 0.0 and receipt.shield_spent == 0.0 and receipt.mana_spent == 10.0, "100percent interface fixture isolates actual cold mana spending; no claimed player source")
		if scenario.name == "shield_only": check(receipt.health_lost == 0.0 and receipt.mana_spent == 0.0 and receipt.shield_spent == 10.0, "Full shield loss qualifies without mana or life loss")
		report.receipts.append({"kind":scenario.name, "settlement":receipt.duplicate(true), "cold":actual})
	for scenario: String in ["zero", "no_cold", "no_hit_tag", "no_policy", "invulnerable", "evaded"]:
		reset_probe()
		var components: Dictionary = {"cold":10.0}
		var tags: Array = ["hit", "attack", "area"]
		var metadata: Dictionary = context()
		match scenario:
			"zero": components = {"cold":0.0}
			"no_cold": components = {"physical":10.0}
			"no_hit_tag": tags = ["dot"]
			"no_policy": metadata = {}
			"invulnerable": arena.invulnerable = 0.1
			"evaded": arena._stats.evasion = 1000000000.0
		arena.hit_player_components(components, int(frost.id), tags, metadata)
		check(arena.chill_statuses().is_empty() and arena.chill_runtime.is_empty(), "Main excludes chill for " + scenario)
		if scenario == "evaded": check(arena.incoming_damage_trace.is_empty() and arena.attack_admission_trace.size() == 1, "Evaded attack only records existing admission result")
	reset_probe()
	var invalid_cases: Array = [
		{"source":0, "context":context()}, {"source":-1, "context":context()},
		{"source":frost.id, "context":{"chill_policy":{"duration":1.2,"movement_speed_reduced":0.5},"at":arena.elapsed}},
		{"source":frost.id, "context":context(true)}, {"source":frost.id, "context":context("1")},
		{"source":frost.id, "context":context(NAN)}, {"source":frost.id, "context":context(arena.elapsed + 1.0)},
		{"source":frost.id, "context":context(arena.elapsed - 0.01)}]
	for invalid: Dictionary in invalid_cases:
		var before := atomic()
		check(not arena.hit_player_components({"cold":10.0}, int(invalid.source), ["hit", "attack"], invalid.context) and atomic() == before, "Invalid chill source/policy/time rejects before resource, entropy, state or RNG mutation")
	if not check(hit(), "Late-event probe first creates real Main chill"): return false
	var old_time: float = arena.elapsed
	arena.tick(1.3)
	if not check(arena.chill_runtime.is_empty(), "Late-event probe expires to truly empty runtime"): return false
	var empty_before := atomic()
	check(not arena.hit_player_components({"cold":10.0}, int(frost.id), ["hit", "attack"], context(old_time)) and atomic() == empty_before, "Old timestamp cannot resurrect an already expired empty status")
	sections.eligibility_atomicity = checks - start_checks
	return true

func utility_and_avoidance() -> bool:
	var start_checks := checks
	reset_probe(); frost.spawn = 0.5; frost.attack_timer = 0.0
	arena.tick(0.1)
	check(arena.telegraphs.state_for(frost.id).is_empty() and arena.chill_statuses().is_empty(), "Spawn-protected resident cannot warn or chill")
	reset_probe()
	if warning(frost).is_empty(): return false
	arena.player_pos += Vector2(140, 0)
	arena.tick(0.9)
	if not check(arena.telegraph_trace.size() == 1, "Dodge resolves one real warning"): return false
	check(not arena.telegraph_trace[0].inside and arena.incoming_damage_trace.is_empty() and arena.chill_statuses().is_empty(), "Leaving locked circle avoids damage and chill")
	reset_probe()
	var wall: Rect2 = arena.world_geometry().walls[1]
	arena.player_pos = Vector2(wall.position.x - 23.0, wall.position.y + 45.0)
	frost.pos = arena.player_pos - Vector2(100, 0)
	if warning(frost).is_empty(): return false
	var locked_center: Vector2 = arena.player_pos
	arena.player_pos = Vector2(wall.position.x + 45.0, wall.position.y - 23.0)
	check(locked_center.distance_to(arena.player_pos) < 105.0 and not arena._terrain_visible(locked_center, arena.player_pos), "Legal opposite-corner points remain in circle but have blocked LOS")
	arena.tick(0.9)
	check(arena.incoming_damage_trace.is_empty() and arena.chill_statuses().is_empty(), "Actual wall obstruction prevents frost damage and chill")
	for skill: String in ["dash", "ward"]:
		reset_probe()
		var group_id: String = group_for(skill)
		if not check(not group_id.is_empty(), "Existing owned utility group " + skill): return false
		if not check(hit(), "Existing chill before actual utility cast " + skill): return false
		var chilled := status()
		var before: Vector2 = arena.player_pos
		var compiled: Dictionary = arena.state.get_group_cast(group_id)
		if not accepted(compiled, "Owned utility compiler succeeds"): return false
		if not check(arena.cast_group(group_id), "Real owned utility cast " + skill): return false
		if skill == "dash":
			near(arena.player_pos.distance_to(before), 175.0, "Chilled dash retains exact175 distance")
			near(arena.group_cooldown_remaining(group_id), compiled.cooldown, "Chilled dash retains original cooldown debt")
			check(arena.get_node("WorldCamera").position.distance_to(View.follow_position(arena.player_pos, arena.ARENA)) < 0.001, "Chilled dash immediately updates followed camera")
		check(status().get("expires_at") == chilled.get("expires_at"), "Utility has no active chill dispel: " + skill)
		var prior := atomic()
		check(not hit() and atomic() == prior, "Actual utility protection blocks added damage and chill refresh: " + skill)
	sections.utility_avoidance = checks - start_checks
	return true

func build_changes_and_cleanup() -> bool:
	var start_checks := checks
	reset_probe()
	if not check(hit(), "Real status before refund and equipment edits"): return false
	var prior: Dictionary = arena.chill_runtime._state.duplicate(true)
	if not accepted(arena.state.refund_passive("34098", arena.state.revision(), arena.build_save_path), "Actual source refund while chilled"): return false
	near(arena.state.get_stats()[STAT], 0.0, "Source refund derives zero mana diversion")
	check(arena.chill_runtime._state == prior, "Refund cannot remove or rewrite fixed enemy chill")
	var equipped: Dictionary = arena.state.equipped_items()
	if not check(not equipped.is_empty(), "Character has real owned equipment for removal"): return false
	var slot: String = equipped.keys()[0]
	var uid: String = equipped[slot]
	var destination: Dictionary = arena.state.first_bag_position(uid)
	if not check(not destination.is_empty(), "Owned item has legal bag destination"): return false
	if not accepted(arena.state.move_item(uid, destination, arena.state.revision(), arena.build_save_path), "Actual equipment removal while chilled"): return false
	check(arena.chill_runtime._state == prior, "Equipment changes never add new state fields or dispel enemy chill")
	if not accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":slot}, arena.state.revision(), arena.build_save_path), "Restore same owned item"): return false
	check(arena.chill_runtime._state == prior, "Re-equipping keeps same fixed status and deadline")
	reset_probe()
	if not check(hit(), "No-source actual cold hit still applies fixed enemy chill"): return false
	check(arena.incoming_damage_trace[0].get("mana_spent", 0.0) == 0.0 and arena.chill_statuses().size() == 1, "Chill is independent of refunded player source")
	arena.invulnerable = 0.0; arena.health = 1.0; arena.shield = 0.0
	if not check(hit({"cold":100.0}), "Actual lethal cold settlement admitted"): return false
	check(not arena.alive and arena.health == 0.0 and arena.chill_runtime.is_empty() and arena.chill_statuses().is_empty(), "Lethal hit clears existing chill and cannot attach a new one")
	var dead_before := atomic()
	check(not hit() and atomic() == dead_before, "Dead player cannot receive or revive chill")
	arena.restart_run(); pause()
	check(arena.alive and arena.chill_runtime.is_empty() and arena.chill_statuses().is_empty(), "Actual restart clears all transient chill state")
	check(arena.enemies.size() == 37 and ids() != initial_ids, "Actual restart regenerates full37 roster with fresh IDs")
	frost = {}; second_frost = {}
	for enemy: Dictionary in arena.enemies:
		if enemy.template_id == "frost_guard" and frost.is_empty(): frost = enemy
	if not check(not frost.is_empty(), "Restart owns a new genuine frost resident"): return false
	reset_probe()
	if not check(hit(), "Actual status before town transition"): return false
	if not accepted(arena.return_to_town(arena.world_context().revision), "Actual return_to_town while chilled"): return false
	check(arena.chill_runtime.is_empty() and arena.chill_statuses().is_empty() and arena.enemies.is_empty(), "Town return clears status and actors")
	check(arena.map_spawn_records().is_empty() and arena.get_node("WorldCamera").position.distance_to(View.WORLD_ARENA.get_center()) < 0.001, "Town clears provenance and restores fixed camera")
	if not enter("old_garden", 25): return false
	frost = {}
	for enemy: Dictionary in arena.enemies:
		if enemy.template_id == "frost_guard": frost = enemy; break
	# Completion is an explicit consumer-boundary fixture, not a second full
	# progression run. The real Main transition must clear an actual live chill.
	if not check(not arena.enemies.is_empty(), "Completion fixture has genuine initial roots"): return false
	if frost.is_empty(): frost = arena.enemies[0]
	reset_probe()
	if not check(hit(), "Completion boundary fixture starts with actual Main cold status"): return false
	for enemy: Dictionary in arena.enemies: enemy.health = 0.0
	arena._map_run.defeated = arena._map_run.admitted.duplicate(true); arena._map_run.boss_defeated = true
	arena.monster_runtime.queue.clear(); arena._check_map_complete()
	check(arena.world_context().mode == "map_complete" and arena.chill_runtime.is_empty() and arena.chill_statuses().is_empty(), "Real completion transition clears active chill at controlled completion boundary")
	check(FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH) == normal_bytes, "Entire isolated gameplay fixture leaves formal save bytes unchanged")
	sections.build_lifecycle = checks - start_checks
	return true

func write_report() -> void:
	report.checks = checks; report.failures = failures; report.failed_labels = failed_labels; report.sections = sections
	report.final_elapsed = arena.elapsed
	var output: String = OS.get_environment("FROST_CHILL_GAMEPLAY_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null: check(false, "Report destination opens")
		else: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("FROST_CHILL_GAMEPLAY " + JSON.stringify({"checks":checks, "failures":failures, "sections":sections, "failed_labels":failed_labels}))

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v087-chill-"):
		printerr("Requires independent /tmp/godot-m1-v087-chill-* XDG_DATA_HOME"); quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame
	pause()
	arena.rng.seed = 870087; arena.critical_runtime.reset(870087)
	if accepted(arena.enter_town_test(arena.world_context().revision), "Real Main enters isolated test town"):
		normal_bytes = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
		if source_fixture() and resident_flow() and natural_warning_and_receipt() and movement_and_refresh() and eligibility_and_atomicity() and utility_and_avoidance():
			build_changes_and_cleanup()
	write_report()
	Input.action_release("move_right")
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
