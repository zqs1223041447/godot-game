extends SceneTree
## Bounded actual-main v061 checks. The external legacy mode also runs against
## the independently frozen v060 project, loading that project's dependencies.
const Model = preload("res://scripts/canonical_game_state.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const STAT = "resolute_technique"
const ROUTE = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "63282", "31961"]
const POLICY = {"id":"resolute_technique", "hits_cannot_be_evaded":true, "cannot_deal_critical_strikes":true}
var arena: Node
var checks := 0
var failures := 0
var completed := false
var sections := {}
var report := {}
var blade := ""
var bow := ""
var vest := ""
var old_cleave := {}
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
	arena.health = float(arena._stats.max_health) * 0.25; arena.shield = 0.0; arena.mana = float(arena._stats.max_mana) * 0.8
	arena.kills = 0; arena.reward_kills = 0; arena.total_damage = 0.0; arena.total_shots = 0; arena.attack_timer = 0.0
	arena._refresh_leech_caps(); arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 610061; arena.critical_runtime.reset(610062); arena._player_evasion_entropy = 13.25
	arena.hud._process(0.0); arena.hud.close_panel()
	check(not arena.hud.is_blocking(), "Controlled actual-main fixture is unpaused")
	for id: String in arena.Data.SKILLS: arena.cooldowns[id] = 0.0

func target(offset: Vector2 = Vector2(40, 0), rewarding: bool = false) -> Dictionary:
	var value: Dictionary = arena._spawn_monster("crawler", arena.player_pos + offset, "ordinary", "", [], rewarding)
	value.spawn = 0.0; value.health = 10000.0; value.max_health = 10000.0; value.shield = 0.0; value.max_shield = 0.0
	value.armour = 0.0; value.evasion = 1000000000.0; value.evasion_entropy = 13.25; value.radius = 1.0
	value.resistances = {}; value.speed = 0.0; value.attack_timer = 1000.0; value.shield_regen = 0.0; value.shield_recharge_rate = 0.0
	return value
func readonly() -> Dictionary:
	return {"model":arena.state.snapshot(), "saves":arena.state.successful_saves, "disk":FileAccess.get_file_as_bytes(arena.build_save_path)}
func atomic() -> PackedByteArray:
	return var_to_bytes([readonly(), arena.health, arena.mana, arena.shield, arena.attack_timer, arena.cooldowns,
		arena.projectiles, arena.damage_trace, arena.attack_admission_trace, arena.event_counts, arena.rng.state,
		arena.critical_runtime.checkpoint(), arena.group_cooldowns.snapshot(), arena.leech_runtime.snapshot(),
		arena.projectile_runtime.next_cast_id, arena.projectile_runtime.next_projectile_id])
func equip(uid: String, slot: String = "weapon") -> bool:
	if arena.state.equipped_items().get(slot, "") == uid: return true
	return accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":slot}, arena.state.revision(), arena.build_save_path), "Real equip " + uid + " -> " + slot)
func own(base: String, ids: Array = []) -> String:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	var affixes: Array = []
	for id: String in ids: affixes.append({"id":id, "tier":3, "value":int(Gear.affix_definition(id).tiers[2].max)})
	var item := {"id":uid, "base_id":base, "rarity":"normal" if ids.is_empty() else "rare", "item_level":16, "affixes":affixes}
	if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)), "Actual valid owned fixture " + base): return ""
	return uid
func set_node(enabled: bool) -> bool:
	if arena.state.snapshot().talents.allocated.has("31961") == enabled: return true
	var result: Dictionary = arena.state.allocate_passive("31961", 0, arena.state.revision(), arena.build_save_path) if enabled else arena.state.refund_passive("31961", arena.state.revision(), arena.build_save_path)
	return accepted(result, "Real resolute allocation" if enabled else "Real resolute refund")
func no_critical_hits(label: String) -> void:
	check(not arena.damage_trace.is_empty(), label + " has actual settled damage")
	for record: Dictionary in arena.damage_trace: check(not record.get("critical", {}).get("critical", false), label + " cannot crit")
func zero_profile(compiled: Dictionary, label: String) -> bool:
	if not accepted(compiled, label + " compiles"): return false
	if not check(compiled.has("snapshot") and compiled.has("critical"), label + " exposes critical and snapshot keys"): return false
	check(compiled.get("hit_policy", {}) == POLICY and compiled.snapshot.get(STAT, 0.0) == 1.0, label + " carries exact indivisible policy")
	for role: String in compiled.critical: near(compiled.critical[role].chance, 0.0, label + " zero chance " + role)
	return true

func legal_source_and_equipment() -> void:
	if not accepted(arena.enter_town_test(arena.world_context().revision), "Actual test-town profile transition"): return
	if not accepted(arena.start_map(arena.map_draft().revision), "Actual test-map entry"): return
	for slot: String in arena.state.equipped_items().keys():
		if not check(arena.state.unequip(slot), "Real starting equipment unequip " + slot): return
	blade = own("forgeblade"); bow = own("ashwood_bow")
	vest = own("emberhide_vest", ["rootwell", "deepwell", "rimeward", "stormward"])
	var amulet := own("wayglass_token", ["attack_life_leech", "attack_mana_leech", "global_critical_chance", "global_critical_multiplier"])
	if [blade, bow, vest, amulet].has(""): return
	if not equip(blade) or not equip(vest, "body_armour") or not equip(amulet, "amulet"): return
	for pair: Array in [["cleave", "group_000009"], ["shade_bolt", "group_000010"]]:
		var uid: String = arena.state.award_gem("skill:" + pair[0])
		if not check(not uid.is_empty(), "Owned new active gem " + pair[0]): return
		if not accepted(arena.state.move_item(uid, {"kind":"skill_main", "group_id":pair[1]}, arena.state.revision(), arena.build_save_path), "Actual active gem equip " + pair[0]): return
	for group: Dictionary in arena.state.snapshot().skill_groups:
		var cast: Dictionary = arena.state.get_group_cast(group.id)
		if cast.get("ok", false): groups[cast.skill_id] = group.id
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level":7, "xp":0}; candidate.talents.class_id = 1
	candidate.talents.allocated = [ROUTE[0]]; candidate.talents.normal_points = 11; candidate.revision += 1
	if not check(arena.state.Rules.reason(candidate).is_empty(), "Level-seven Marauder has eleven earned points"): return
	if not accepted(arena.state._commit(candidate, arena.build_save_path), "Commit lawful level-seven root fixture"): return
	for id: String in ROUTE.slice(1):
		if id == "31961":
			old_cleave = arena.state.get_skill_cast("cleave")
			if not accepted(old_cleave, "Actual pre-node cleave snapshot"): return
			check(not old_cleave.snapshot.has(STAT) and not old_cleave.has("hit_policy"), "Unallocated snapshot omits new field/policy")
		if not check(arena.state.available_passives().has(id), "Real available connected path " + id): return
		if not accepted(arena.state.allocate_passive(id, 0, arena.state.revision(), arena.build_save_path), "Spend actual earned point " + id): return
	near(arena.state.get_stats().get(STAT, 0.0), 1.0, "Actual source derives one enabled stat")
	check(arena.state.talent_points == 0, "Eleven actual allocations spend exactly eleven points")
	near(arena.state.get_stats().cold_resistance, 0.25, "Existing new cold affix survives source allocation")
	near(arena.state.get_stats().lightning_resistance, 0.25, "Existing new lightning affix survives source allocation")
	var before := readonly()
	for id: String in arena.Data.SKILLS:
		if id in ["dash", "ward"]: continue
		if not zero_profile(arena.state.get_skill_cast(id), "Real source skill " + id): return
	if not zero_profile(arena.state.get_basic_cast(), "Real sword basic"): return
	check(readonly() == before, "Compilation does not save or mutate authoritative model")
	var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.snapshot() == arena.state.snapshot(), "Exact allocated owned build survives current save reload")
	check(loaded.get_combat_snapshot() == arena.state.get_combat_snapshot(), "Reload derives same hit policy source")
	report.source = {"route":ROUTE, "class_id":1, "level":7, "spent_points":11, "stats":arena.state.get_stats()}
	completed = true

func admitted_hits_and_leech() -> void:
	if not equip(blade): return
	var enabled: Dictionary = arena.state.get_skill_cast("cleave")
	if not zero_profile(enabled, "Enabled leech cleave"): return
	var receipts: Array = []
	for cast: Dictionary in [old_cleave, enabled]:
		clean(); var enemy := target(); enemy.health = 10.0; enemy.max_health = 10.0; enemy.shield = 5.0; enemy.max_shield = 5.0
		var rng_before: int = arena.rng.state; var critical_before: Dictionary = arena.critical_runtime.checkpoint()
		if not check(arena._execute_compiled(cast), "Actual matched high-evasion cleave accepted"): return
		if cast == old_cleave:
			check(arena.damage_trace.is_empty() and arena.leech_runtime.is_empty(), "Old high-evasion miss cannot leech")
			check(arena.attack_admission_trace.size() == 1 and not arena.attack_admission_trace[0].hit, "Old entropy branch reports genuine miss")
			near(enemy.evasion_entropy, 18.25, "Old miss advances entropy by five")
		else:
			if not check(arena.damage_trace.size() == 1, "Enabled high-evasion actual hit settles once"): return
			var hit: Dictionary = arena.damage_trace[0]
			check(arena.attack_admission_trace == [{"actor":"monster", "target_id":enemy.id, "hit":true, "chance":1.0}], "Enabled branch records one genuine chance-one admission")
			near(enemy.evasion_entropy, 13.25, "Enabled attack preserves defender entropy exactly")
			near(hit.shield_spent + hit.health_lost, 15.0, "Successful leech uses actual shield/life loss excluding overkill")
			if not check(hit.has("leech"), "Successful real attack creates leech receipt"): return
			near(hit.leech.health, 15.0 * 0.006, "Real life leech uses actual loss")
			near(hit.leech.mana, 15.0 * 0.0035, "Real mana leech uses actual loss")
			check(arena.critical_runtime.checkpoint() == critical_before, "Zero chance draws no private critical RNG")
			no_critical_hits("Enabled high-evasion leech")
		receipts.append({"enabled":cast != old_cleave, "admission":arena.attack_admission_trace.duplicate(true), "entropy":enemy.evasion_entropy, "hits":arena.damage_trace.duplicate(true), "critical_before":critical_before, "critical_after":arena.critical_runtime.checkpoint(), "loot_before":rng_before, "loot_after":arena.rng.state})
	# Use two admitted nonlethal hits when comparing shared RNG. Miss-vs-hit
	# legitimately produces different particles and cannot be an RNG oracle.
	var shared: Array = []
	for cast: Dictionary in [old_cleave, enabled]:
		clean(); var enemy := target(); enemy.evasion = 0.0
		if not check(arena._execute_compiled(cast), "Matched nonlethal accepted hit"): return
		shared.append({"loot":arena.rng.state, "critical":arena.critical_runtime.checkpoint()})
	check(shared[0].loot == shared[1].loot, "Enabled no-crit policy adds no shared loot/particle RNG draws")
	check(shared[0].critical != shared[1].critical, "Private critical stream deliberately differs after suppressing old draw")
	# Incoming enemy attack is unaffected by the player's offensive policy.
	var incoming: Array = []
	for enabled_flag: bool in [false, true]:
		if not set_node(enabled_flag): return
		clean(); arena._stats.evasion = 1000000000.0
		var before_health: float = arena.health
		check(not arena.hit_player_components({"physical":20.0}, 91, ["hit", "attack"]), "Enemy attack can still miss player")
		check(arena.health == before_health and arena.incoming_damage_trace.is_empty(), "Enemy miss causes no incoming settlement")
		incoming.append([arena._player_evasion_entropy, arena.attack_admission_trace.duplicate(true), arena.rng.state, arena.critical_runtime.checkpoint()])
	check(incoming[0] == incoming[1], "Enemy-to-player admission and RNG are identical with and without source")
	report.admission_leech = receipts; report.shared_rng = shared; report.incoming = incoming
	completed = true

func actual_cast_matrix() -> void:
	var receipts: Array = []
	for pair: Array in [[blade, "melee"], [bow, "bow"]]:
		if not equip(pair[0]): return
		clean(); var enemy := target(Vector2(40, 0)); arena.auto_fire = true
		var before: Dictionary = arena.critical_runtime.checkpoint()
		arena._update_auto_attack(); arena._update_projectiles(0.15); arena.auto_fire = false
		no_critical_hits("Actual " + pair[1] + " basic")
		near(enemy.evasion_entropy, 13.25, "Actual basic does not advance defender entropy")
		check(arena.attack_admission_trace.size() == 1 and arena.attack_admission_trace[0].chance == 1.0, "Actual basic records exactly one admission")
		check(arena.critical_runtime.checkpoint() == before and arena.attack_timer > 0.0, "Actual basic keeps attack timer and no private draw")
		receipts.append({"id":pair[1], "hits":arena.damage_trace.duplicate(true), "admission":arena.attack_admission_trace.duplicate(true), "critical":arena.critical_runtime.checkpoint()})
	if not equip(blade): return
	for id: String in ["cleave", "tornado", "bolt", "frost", "shade_bolt", "nova", "meteor", "chain"]:
		if not check(groups.has(id), "Real owned skill group exists " + id): return
		clean(); var one := target(Vector2(40, 0)); var two := target(Vector2(70, 12))
		var before: Dictionary = arena.critical_runtime.checkpoint()
		var cast: Dictionary = arena.state.get_group_cast(groups[id])
		if not zero_profile(cast, "Actual group " + id): return
		arena.mana = maxf(arena.mana, float(cast.mana))
		if not check(arena.cast_group(groups[id]), "Actual owned group pays and casts " + id): return
		if int(cast.initial_count) > 0: arena._update_projectiles(0.25)
		no_critical_hits("Actual owned " + id)
		near(one.evasion_entropy, 13.25, "First target entropy remains " + id)
		near(two.evasion_entropy, 13.25, "Second target entropy remains " + id)
		if id not in ["cleave", "tornado"]: check(arena.attack_admission_trace.is_empty(), "Non-attack spell has no fabricated attack trace " + id)
		check(arena.critical_runtime.checkpoint() == before, "All actual accepted hits avoid private critical draws " + id)
		receipts.append({"id":id, "hits":arena.damage_trace.duplicate(true), "admission":arena.attack_admission_trace.duplicate(true), "critical":arena.critical_runtime.checkpoint(), "loot":arena.rng.state})
	report.actual_casts = receipts
	completed = true

func geometry_and_refusals() -> void:
	if not equip(blade): return
	for row: Array in [["range", Vector2(80, 0), 0.0, 10000.0], ["spawn", Vector2(40, 0), 0.2, 10000.0], ["dead", Vector2(40, 0), 0.0, 0.0]]:
		clean(); var enemy := target(row[1]); enemy.spawn = row[2]; enemy.health = row[3]; arena.auto_fire = true
		var before: Dictionary = arena.critical_runtime.checkpoint(); arena._update_auto_attack()
		check(arena.damage_trace.is_empty() and arena.attack_admission_trace.is_empty() and arena.attack_timer == 0.0 and arena.critical_runtime.checkpoint() == before, "Unerring basic respects " + row[0])
	clean(); arena._geometry.configure("broken_ruins", arena.ARENA)
	var wall: Rect2 = arena._geometry.snapshot().walls[0]; arena.player_pos = wall.position + Vector2(-1, 100)
	var blocked := target(Vector2(58, 0)); arena.auto_fire = true
	check(not arena._terrain_visible(arena.player_pos, blocked.pos), "Real wall fixture blocks close target")
	arena._update_auto_attack()
	check(arena.damage_trace.is_empty() and arena.attack_admission_trace.is_empty() and arena.attack_timer == 0.0, "Unerring melee basic cannot hit through wall")
	if not check(arena.cast_group(groups.cleave), "Real cleave can cast toward occlusion"): return
	check(arena.damage_trace.is_empty() and arena.attack_admission_trace.is_empty(), "Unerring cleave cannot hit through wall")
	arena.player_pos = wall.position + Vector2(-30, 100); arena.player_facing = Vector2.RIGHT
	if not check(arena.cast_group(groups.bolt), "Real enabled spell launches toward actual wall"): return
	arena._update_projectiles(0.2)
	check(arena.damage_trace.is_empty() and arena.attack_admission_trace.is_empty() and int(arena.event_counts.get("terrain_hit", 0)) > 0, "Unerring projectile is consumed by wall before admission")
	clean(); target(Vector2(200, 0))
	if not check(arena.cast_group(groups.cleave), "Real enabled cleave accepts out-of-range empty cast"): return
	check(arena.damage_trace.is_empty() and arena.attack_admission_trace.is_empty(), "Unerring cleave retains actual original radius")
	clean(); var cast: Dictionary = arena.state.get_group_cast(groups.tornado)
	if not accepted(cast, "Refusal tornado compiles"): return
	arena.mana = float(cast.mana) - 0.00001; var before := atomic()
	check(not arena.cast_group(groups.tornado) and atomic() == before, "Insufficient mana refuses before RNG, IDs, debt, save or payment")
	arena.mana = float(cast.mana)
	if not check(arena.cast_group(groups.tornado), "Exact mana admits actual cast"): return
	near(arena.mana, 0.0, "Actual enabled cast pays exact normal cost")
	arena.mana = float(arena._stats.max_mana); before = atomic()
	check(not arena.cast_group(groups.tornado) and atomic() == before, "Cooldown refuses atomically")
	clean(); arena.projectiles.resize(arena.MAX_PROJECTILES)
	for index: int in range(arena.MAX_PROJECTILES): arena.projectiles[index] = {}
	before = atomic()
	check(not arena.cast_group(groups.tornado) and atomic() == before, "Full projectile capacity refuses atomically")
	capacity_and_dead()
	completed = true

func capacity_and_dead() -> void:
	# The capped arena remains safe: melee consumes no projectile slot.
	var enemy := target(); arena.auto_fire = true; arena._update_auto_attack()
	check(arena.damage_trace.size() == 1 and enemy.health < 10000.0, "Full carrier capacity still admits existing melee rule")
	if not equip(bow): return
	clean(); arena.projectiles.resize(arena.MAX_PROJECTILES)
	for index: int in range(arena.MAX_PROJECTILES): arena.projectiles[index] = {}
	target(); arena.auto_fire = true; var before := atomic(); arena._update_auto_attack()
	check(atomic() == before, "Full carrier capacity refuses bow before private draw and timer")
	clean(); arena.alive = false; before = atomic()
	check(not arena.cast_group(groups.cleave) and atomic() == before, "Dead player cannot cast unerring skill")

func winning_seed(snapshot: Dictionary) -> int:
	var runtime := Critical.new()
	for value: int in range(10000):
		runtime.reset(value); var frozen: Dictionary = runtime.freeze(snapshot)
		if frozen.get("ok", false) and frozen.snapshot.get("critical_roll", {}).get("critical", false): return value
	return -1

func flying_snapshot_transactions() -> void:
	if not equip(bow) or not set_node(false): return
	clean(); var evasive := target(Vector2(120, 0)); var hittable := target(Vector2(170, 0)); hittable.evasion = 0.0; arena.auto_fire = true
	var old: Dictionary = arena.state.get_basic_cast()
	if not accepted(old, "Pre-node real bow basic"): return
	var seed_value := winning_seed(old.snapshot)
	if not check(seed_value >= 0, "Reachable deterministic pre-node critical seed"): return
	arena.critical_runtime.reset(seed_value); arena._update_auto_attack(); arena.auto_fire = false
	if not check(arena.projectiles.size() == 1, "Real old bow projectile launched before allocation"): return
	var frozen := var_to_bytes(arena.projectiles[0].snapshot); var timer: float = arena.attack_timer
	if not set_node(true): return
	check(var_to_bytes(arena.projectiles[0].snapshot) == frozen and arena.attack_timer == timer, "Allocating node keeps old snapshot and timer")
	arena._update_projectiles(0.3)
	check(arena.damage_trace.size() == 1 and arena.attack_admission_trace.size() == 2 and not arena.attack_admission_trace[0].hit, "Pre-allocation projectile keeps old evadable admission after allocation")
	near(evasive.evasion_entropy, 18.25, "Pre-node shot still advances old evasion entropy")
	if not check(arena.damage_trace.size() == 1, "Old projectile reaches second target after first miss"): return
	check(arena.damage_trace[0].get("critical", {}).get("critical", false), "Old critical result still deals critical hit after allocating node")
	# Enabled launch then real refund plus equipment change must retain policy.
	clean(); var enemy := target(Vector2(120, 0)); arena.auto_fire = true; arena._update_auto_attack(); arena.auto_fire = false
	if not check(arena.projectiles.size() == 1, "Real enabled bow projectile launched"): return
	frozen = var_to_bytes(arena.projectiles[0].snapshot); timer = arena.attack_timer
	var critical_before: Dictionary = arena.critical_runtime.checkpoint()
	if not set_node(false) or not equip(blade): return
	check(var_to_bytes(arena.projectiles[0].snapshot) == frozen and arena.attack_timer == timer, "Refund and sword switch preserve in-flight enabled snapshot and timer")
	arena._update_projectiles(0.25)
	no_critical_hits("Enabled projectile after refund and sword switch")
	near(enemy.evasion_entropy, 13.25, "Old enabled projectile retains unerring admission after refund")
	check(arena.critical_runtime.checkpoint() == critical_before, "Old enabled impact does not draw current old crit profile")
	if not set_node(true): return
	completed = true

func tornado_children_return_and_explosion() -> void:
	# Use genuine original fixed owned items; all changes go through model equip.
	for pair: Array in [["prism_bow", "weapon"], ["return_mantle", "body_armour"], ["detonation_charm", "amulet"]]:
		var found := ""
		for uid: String in arena.state.snapshot().items:
			if arena.state.item(uid).definition_id == "equipment:" + pair[0]: found = uid; break
		if not check(not found.is_empty(), "Original fixed owned item " + pair[0]) or not equip(found, pair[1]): return
	clean(); var cast: Dictionary = arena.state.get_skill_cast("tornado")
	if not zero_profile(cast, "Real equipped tornado independent explosion"): return
	if not check(cast.critical.has("secondary") and cast.snapshot.get("effects", []).size() > 0, "Real equipment exposes frozen secondary chance"): return
	var parent := target(Vector2(60, 0)); var before: Dictionary = arena.critical_runtime.checkpoint()
	if not check(arena.cast_group(groups.tornado), "Real enabled equipped tornado cast"): return
	var original_snapshots: Array = []
	for shot: Dictionary in arena.projectiles: original_snapshots.append(var_to_bytes(shot.snapshot))
	arena._update_projectiles(0.4)
	check(int(arena.event_counts.get("split", 0)) > 0 and arena.projectiles.size() == int(cast.initial_count) * 3, "Actual parents contact and split into exact children")
	no_critical_hits("Actual tornado parent contact")
	near(parent.evasion_entropy, 13.25, "Actual parent contact preserves defender entropy")
	for shot: Dictionary in arena.projectiles:
		check(shot.generation == 1 and original_snapshots.has(var_to_bytes(shot.snapshot)), "Every child inherits original frozen policy")
	# Put one live body at a real child's next position so contact, not an
	# isolated compiler assertion, exercises the child admission callback.
	if not check(not arena.projectiles.is_empty(), "Children remain live for real contact"): return
	var child: Dictionary = arena.projectiles[0]
	var child_target := target(Vector2(child.pos) + Vector2(child.velocity).normalized() * 30.0 - arena.player_pos)
	arena._update_projectiles(0.2)
	check(arena.damage_trace.any(func(record: Dictionary) -> bool: return record.target_id == child_target.id and record.projectile_id == child.id), "Actual child contact settles against high evasion")
	near(child_target.evasion_entropy, 13.25, "Actual child hit preserves entropy")
	if not set_node(false) or not equip(blade) or not equip(vest, "body_armour"): return
	for shot: Dictionary in arena.projectiles: check(original_snapshots.has(var_to_bytes(shot.snapshot)), "Refund and equipment switch retain child snapshot")
	arena._update_projectiles(0.4)
	check(int(arena.event_counts.get("return_started", 0)) > 0, "Old enabled children begin original equipment return after removal")
	for shot: Dictionary in arena.projectiles: check(shot.state == "returning" and original_snapshots.has(var_to_bytes(shot.snapshot)), "Returning child retains original snapshot")
	check(arena.critical_runtime.checkpoint() == before, "Parent/child/return zero profiles draw no private RNG")
	# Continue these very same real-cast children to natural expiry after the
	# refund and equipment changes, before the separate exact two-target probe.
	if not check(not arena.projectiles.is_empty(), "Original returning children still exist before expiry"): return
	var returning: Dictionary = arena.projectiles[0]
	var remaining: float = float(returning.lifetime) - float(returning.age)
	var endpoint: Vector2 = Vector2(returning.pos) + Vector2(returning.velocity) * remaining
	arena.enemies.clear(); arena.damage_trace.clear(); arena.attack_admission_trace.clear()
	var actual_end_target := target(endpoint + Vector2(returning.velocity).normalized().orthogonal() * 25.0 - arena.player_pos)
	arena._update_projectiles(remaining + 0.02)
	check(int(arena.event_counts.get("explosion", 0)) > 0 and arena.projectiles.is_empty(), "Original real-cast returning children naturally expire and retain removed explosion effect")
	check(arena.damage_trace.any(func(record: Dictionary) -> bool: return record.target_id == actual_end_target.id and record.tags.has("secondary")), "Original real-cast secondary settles after refund and gear switch")
	no_critical_hits("Original real-cast natural secondary")
	check(arena.critical_runtime.checkpoint() == before, "Original real-cast secondary retains no-crit policy after refund")
	report.frozen_real_cast = {"hits":arena.damage_trace.duplicate(true), "events":arena.event_counts.duplicate(true), "critical":arena.critical_runtime.checkpoint(), "loot":arena.rng.state}
	# Natural-end carrier uses the genuine frozen compiled snapshot. Current
	# build has refunded the node and removed both relevant equipment effects.
	clean(); var origin: Vector2 = arena.player_pos + Vector2(200, 0)
	var one := target(origin + Vector2(0, 25) - arena.player_pos); var two := target(origin + Vector2(0, -25) - arena.player_pos)
	var born := target(origin + Vector2(0, 45) - arena.player_pos); born.spawn = 0.5
	var frozen_result: Dictionary = arena.critical_runtime.freeze(cast.snapshot)
	if not accepted(frozen_result, "Freeze genuine enabled old explosion source"): return
	before = arena.critical_runtime.checkpoint()
	var shot: Dictionary = arena.projectile_runtime.make_projectile(origin, Vector2.RIGHT, {"speed":10.0, "range":500.0, "lifetime":0.01, "pierce":-1, "radius":1.0}, cast.packets.parent, frozen_result.snapshot, arena.projectile_runtime.new_cast(), Color.WHITE)
	arena.projectiles.append(shot); arena._update_projectiles(0.02)
	check(int(arena.event_counts.get("explosion", 0)) == 1 and arena.damage_trace.size() == 2, "Natural-end frozen secondary hits exactly two live eligible targets")
	for record: Dictionary in arena.damage_trace: check(record.tags.has("secondary"), "Real independent event is secondary damage")
	no_critical_hits("Actual independent explosion after refund")
	check(arena.attack_admission_trace.is_empty(), "Independent non-attack explosion adds no fabricated attack admission")
	near(one.evasion_entropy, 13.25, "Secondary preserves first entropy"); near(two.evasion_entropy, 13.25, "Secondary preserves second entropy")
	near(born.health, 10000.0, "Unerring secondary respects birth immunity")
	check(arena.critical_runtime.checkpoint() == before, "Natural-end secondary zero chance draws no private RNG")
	report.secondary = {"hits":arena.damage_trace.duplicate(true), "events":arena.event_counts.duplicate(true), "critical":before, "loot":arena.rng.state}
	arena._update_projectiles(0.1)
	check(arena.critical_runtime.checkpoint() == before and int(arena.event_counts.get("explosion", 0)) == 1, "Terminal projectile cannot repeat secondary event")
	if not set_node(true): return
	completed = true

func projected_model(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	check(int(result.version) in [37, 38], "Only schema37/schema38 model version projection allowed")
	result.erase("version")
	return result
func projected_stats(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	if result.has(STAT):
		check(typeof(result[STAT]) == TYPE_FLOAT and result[STAT] == 0.0, "Only new derived zero resolute stat projected")
		result.erase(STAT)
	return result
func legacy_probe(output: String) -> void:
	clean(); arena.rng.seed = 610882; arena.critical_runtime.reset(610882)
	check(arena.state.snapshot().talents.allocated.size() == 1, "No-node independent oracle uses default legal source root")
	if not check(arena.save_build(), "Legacy probe initial save succeeds"): return
	for index: int in range(8):
		var enemy := target(Vector2(75 + index * 12, 15 if index % 2 else -15), true)
		enemy.evasion = 0.0; enemy.health = 1.0 if index < 3 else 10000.0; enemy.max_health = enemy.health
	arena.mana = float(arena._stats.max_mana)
	var samples: Array = []; var casts := 0
	for step: int in range(90):
		if step == 0: check(arena.hit_player_components({"physical":10.0}, 0, ["hit", "attack"]), "Legacy incoming attack exercised")
		if step in [0, 60]:
			if arena._execute_compiled(arena.state.get_skill_cast("nova")): casts += 1
		if step == 30:
			if arena._execute_compiled(arena.state.get_skill_cast("tornado")): casts += 1
		arena.auto_fire = true; arena.tick(1.0 / 60.0)
		var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(arena.build_save_path))
		if not check(disk is Dictionary, "Saved JSON parses before explicit version projection"): return
		samples.append({"enemies":arena.enemies.duplicate(true), "projectiles":arena.projectiles.duplicate(true),
			"queue":arena.monster_runtime.queue.duplicate(true), "roots":arena.monster_runtime.roots.duplicate(true),
			"rng":arena.rng.state, "model":projected_model(arena.state.snapshot()), "stats":projected_stats(arena._stats),
			"resources":[arena.health, arena.mana, arena.shield], "combat":arena.combat_trace.duplicate(true), "hits":arena.damage_trace.duplicate(true),
			"incoming":arena.incoming_damage_trace.duplicate(true), "admission":arena.attack_admission_trace.duplicate(true),
			"timer":arena.attack_timer, "cooldowns":arena.cooldowns.duplicate(true), "groups":arena.group_cooldowns.snapshot(),
			"flasks":arena.flask_runtime.snapshot(), "burns":arena.burn_runtime.statuses(), "shock":arena.shock_runtime.statuses(arena.elapsed),
			"critical":arena.critical_runtime.checkpoint(), "leech":arena.leech_runtime.snapshot(), "events":arena.event_counts.duplicate(true),
			"feedback":[arena.feedback_runtime._time, arena.feedback_runtime._pending.duplicate(true), arena.feedback_runtime._visible.duplicate(true)],
			"particles":arena.particles.duplicate(true), "text":arena.floating_text.duplicate(true), "pickups":arena.pickups.duplicate(true),
			"saves":arena.state.successful_saves, "saved_json":projected_model(disk)})
	check(casts > 0 and arena.kills >= 3 and arena.reward_kills >= 3 and arena.total_damage > 0.0, "Short actual legacy covers cast, attack, hit, kill, loot and save")
	if not check(arena.save_build(), "Legacy final save succeeds"): return
	FileAccess.open(output + ".bin", FileAccess.WRITE).store_buffer(var_to_bytes(samples))
	FileAccess.open(output + ".save", FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
	FileAccess.open(output + ".projected-save.json", FileAccess.WRITE).store_string(JSON.stringify(projected_model(arena.state.snapshot()), "\t", true, true))
	report = {"ticks":90, "seconds":arena.elapsed, "casts":casts, "kills":arena.kills, "reward_kills":arena.reward_kills,
		"damage":arena.total_damage, "rng":arena.rng.state, "critical":arena.critical_runtime.checkpoint(), "events":arena.event_counts,
		"version":arena.state.snapshot().version, "project_version":ProjectSettings.get_setting("application/config/version"), "checks":checks, "failures":failures}
	FileAccess.open(output + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	completed = true

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v061-consumers-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	var legacy: String = OS.get_environment("RESOLUTE_LEGACY_OUTPUT")
	if not legacy.is_empty():
		completed = false; legacy_probe(legacy); check(completed, "Legacy probe returned normally")
	else:
		for test: Callable in [legal_source_and_equipment, admitted_hits_and_leech, actual_cast_matrix, geometry_and_refusals, flying_snapshot_transactions, tornado_children_return_and_explosion]:
			if not section(test): break
		report.merge({"checks":checks, "failures":failures, "sections":sections, "scope":"Bounded headless actual main, real owned items and model transactions; no visual/Windows acceptance"})
		var output := OS.get_environment("RESOLUTE_GAMEPLAY_REPORT")
		if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("RESOLUTE_GAMEPLAY ", JSON.stringify({"checks":checks, "failures":failures, "sections":sections}))
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
