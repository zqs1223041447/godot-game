extends SceneTree
## v070 bounded actual-Main acceptance. Legal source allocations and owned gear.
## Section selection supports minimal setup + affected-section retries.
const Model = preload("res://scripts/canonical_game_state.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const Attack = preload("res://scripts/combat/attack_hit_rules.gd")
const ROUTE = ["50459", "39821", "52904", "444", "61306", "60942", "64709", "3469", "63620"]
const STAT := "precise_technique"
const MORE := "precise_technique_attack_more"
var arena: Node
var checks := 0
var failures := 0
var completed := false
var sections := {}
var report := {}
var blade := ""
var bow := ""
var groups := {}
var low_equipment := {}
var life_equipment := {}
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
	push_error("PRECISE_GAMEPLAY watchdog: an actual-Main section did not finish")
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
	arena.health = float(arena._stats.max_health); arena.shield = 0.0; arena.mana = float(arena._stats.max_mana)
	arena.kills = 0; arena.reward_kills = 0; arena.total_damage = 0.0; arena.total_shots = 0; arena.attack_timer = 0.0
	arena._refresh_leech_caps(); arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 700069; arena.critical_runtime.reset(700070); arena._player_evasion_entropy = 50.0
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
func equip(uid: String, slot: String = "weapon") -> bool:
	if arena.state.equipped_items().get(slot, "") == uid: return true
	return accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":slot}, arena.state.revision(), arena.build_save_path), "Real weapon equip " + uid)
func own(base: String, ids: Array = ["whetstone_edge", "tempered_edge", "deepwell", "wellturn"]) -> String:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	var affixes: Array = []
	for id: String in ids:
		affixes.append({"id":id, "tier":3, "value":int(Gear.affix_definition(id).tiers[2].max)})
	var item := {"id":uid, "base_id":base, "rarity":"rare", "item_level":16, "affixes":affixes}
	if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)), "Actual valid owned local weapon " + base): return ""
	return uid
func set_node(enabled: bool) -> bool:
	if arena.state.snapshot().talents.allocated.has("63620") == enabled: return true
	var result: Dictionary = arena.state.allocate_passive("63620", 0, arena.state.revision(), arena.build_save_path) if enabled else arena.state.refund_passive("63620", arena.state.revision(), arena.build_save_path)
	return accepted(result, "Actual precise allocation" if enabled else "Actual precise refund")
func health_gear(high: bool) -> bool:
	for slot: String in life_equipment:
		if high:
			if not equip(life_equipment[slot], slot): return false
		elif low_equipment.has(slot):
			if not equip(low_equipment[slot], slot): return false
		elif arena.state.equipped_items().has(slot):
			var uid: String = arena.state.equipped_items()[slot]
			var position: Dictionary = arena.state.first_bag_position(uid)
			if not check(not position.is_empty(), "Lawful unequip location " + slot): return false
			if not accepted(arena.state.move_item(uid, position, arena.state.revision(), arena.build_save_path), "Actual low-life unequip " + slot): return false
	var stats: Dictionary = arena.state.get_stats()
	return check((stats.accuracy <= stats.max_health) == high, "Real max-life gear crosses strict final threshold: " + JSON.stringify({"accuracy":stats.accuracy, "max_health":stats.max_health}))
func profile(cast: Dictionary, applies: bool, label: String) -> bool:
	if not accepted(cast, label): return false
	var stats: Dictionary = arena.state.get_stats()
	var condition: bool = stats.accuracy > stats.max_health
	var expected := {"enabled":true, "accuracy":float(stats.accuracy), "max_health":float(stats.max_health), "condition_met":condition,
		"attack_more":0.4 if condition else 0.0, "cannot_deal_critical_strikes":true, "attack_applies":applies and condition}
	if not check(cast.get("precise_technique_profile", {}) == expected, label + " exact public current-hit profile"): return false
	check(cast.snapshot.get(STAT, {}) == {"accuracy":float(stats.accuracy), "max_health":float(stats.max_health)}, label + " freezes final accuracy and maximum life")
	var modifiers: Array = cast.snapshot.modifiers.filter(func(row: Dictionary) -> bool: return row.id == MORE)
	check(modifiers.size() == (1 if condition else 0), label + " exactly one conditional MORE source")
	for modifier: Dictionary in modifiers:
		check(modifier == {"id":MORE,"mode":"more","value":0.4,"all_tags":["hit","attack"],"skills":[],"damage_types":[]}, label + " unrestricted damage types but both hit/attack tags")
	for role: String in cast.critical: near(cast.critical[role].chance, 0.0, label + " unconditional crit ban " + role)
	check(not cast.get("hit_policy", {}).get("hits_cannot_be_evaded", false), label + " gains no Resolute admission")
	return true
func no_crit(label: String) -> void:
	check(not arena.damage_trace.is_empty(), label + " has actual hits")
	for hit: Dictionary in arena.damage_trace: check(not hit.get("critical", {}).get("critical", false), label + " does not crit")
func scale_piece(base: float, packet: Dictionary, modifiers: Array, lineage: Array, omit_precise: bool = false) -> float:
	var increased := 0.0; var more := 1.0
	for row: Dictionary in modifiers:
		if omit_precise and row.id == MORE: continue
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
func expected_raw(packet: Dictionary, snapshot: Dictionary, omit_precise: bool = false) -> Dictionary:
	var result := {}
	for type: String in packet.base:
		result[type] = scale_piece(packet.base[type], packet, snapshot.modifiers, [type], omit_precise)
	if packet.has("conversion"):
		var p: float = packet.base.get("physical", 0.0)
		result.physical = scale_piece(p * 0.6, packet, snapshot.modifiers, ["physical"], omit_precise)
		result.fire = scale_piece(packet.base.get("fire", 0.0), packet, snapshot.modifiers, ["fire"], omit_precise) + scale_piece(p * 0.4, packet, snapshot.modifiers, ["physical", "fire"], omit_precise)
	return result
func assert_hit(hit: Dictionary, packet: Dictionary, snapshot: Dictionary, label: String, multiplier: float = 1.0) -> void:
	var expected := expected_raw(packet, snapshot)
	var without := expected_raw(packet, snapshot, true)
	for type: String in expected:
		near(hit.before_defense_components.get(type, 0.0), expected[type] * multiplier, label + " actual " + type)
		var more := 1.4 if packet.tags.has("attack") and snapshot.has(STAT) and snapshot[STAT].accuracy > snapshot[STAT].max_health else 1.0
		near(expected[type], without[type] * more, label + " exactly one MORE " + type)

func legal_source_and_owned_items() -> void:
	if not accepted(arena.enter_town_test(arena.world_context().revision), "Actual test-town transition"): return
	if not accepted(arena.start_map(arena.map_draft().revision), "Actual test-map entry"): return
	blade = own("forgeblade"); bow = own("ashwood_bow")
	if [blade,bow].has("") or not equip(blade): return
	for pair: Array in [["return_mantle","body_armour"],["detonation_charm","amulet"]]:
		var found := ""
		for uid: String in arena.state.snapshot().items:
			if arena.state.item(uid).definition_id == "equipment:" + pair[0]: found = uid; break
		if not check(not found.is_empty(), "Explicit original fixed ownership " + pair[0]) or not equip(found,pair[1]): return
	low_equipment = arena.state.equipped_items()
	for pair: Array in [["woven_bastion","body_armour"],["pulse_seed","amulet"],["nine_slot_etched_ring","ring_1"],["nine_slot_etched_ring","ring_2"],["nine_slot_trail_boots","boots"],["nine_slot_folded_belt","belt"],["nine_slot_threaded_gloves","gloves"],["nine_slot_slate_helmet","helmet"]]:
		var ids := ["rootwell","deepwell","wellturn","trailstep"] if pair[1] in ["body_armour","amulet"] else ["nine_slot_prefix_vitality","nine_slot_prefix_clarity","nine_slot_suffix_endurance","nine_slot_suffix_mana_flow"]
		var uid := own(pair[0],ids)
		if uid.is_empty(): return
		life_equipment[pair[1]] = uid
	var cleave: String = arena.state.award_gem("skill:cleave")
	if not check(not cleave.is_empty(), "Actual owned cleave gem"): return
	if not accepted(arena.state.move_item(cleave,{"kind":"skill_main","group_id":"group_000009"},arena.state.revision(),arena.build_save_path), "Actual cleave equip"): return
	for group: Dictionary in arena.state.snapshot().skill_groups:
		var cast: Dictionary = arena.state.get_group_cast(group.id)
		if cast.get("ok",false): groups[cast.skill_id] = group.id
	if not check(groups.has("cleave") and groups.has("tornado") and groups.has("nova") and groups.has("bolt"), "Required actual owned groups exist"): return
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level":4,"xp":0}; candidate.talents.class_id = 2
	candidate.talents.allocated = [ROUTE[0]]; candidate.talents.masteries = {}; candidate.talents.normal_points = 8; candidate.revision += 1
	if not check(Model.Rules.reason(candidate).is_empty(), "Lawful level4 Ranger root preserves earned 8-point budget"): return
	if not accepted(arena.state._commit(candidate,arena.build_save_path), "Commit only lawful root fixture"): return
	for id: String in ROUTE.slice(1):
		if not check(arena.state.available_passives().has(id), "Reachable actual source allocation " + id): return
		if not accepted(arena.state.allocate_passive(id,0,arena.state.revision(),arena.build_save_path), "Spend real earned point " + id): return
	if not check(arena.state.talent_points == 0 and arena.state.get_stats().get(STAT) == 1.0, "Eight API allocations consume exact earned budget and expose source flag"): return
	if not health_gear(false) or not profile(arena.state.get_basic_cast(),true,"Ranger actual selected basic"): return
	var before := readonly(); var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.snapshot() == arena.state.snapshot(), "Current source save reloads exactly")
	check(loaded.get_basic_cast() == arena.state.get_basic_cast() and readonly() == before, "Read-only reload and preview agree without a write")
	report.source = {"route":ROUTE,"class_id":2,"level":4,"points_spent":8,"stats":arena.state.get_stats()}
	completed = true

func maximum_life_gear_and_resources() -> void:
	if not set_node(true) or not equip(blade): return
	var observations: Array = []
	for high: bool in [false,true,false]:
		if not health_gear(high): return
		clean(); var before: Dictionary = arena.state.get_basic_cast()
		if not profile(before,true,"Actual gear condition " + str(high)): return
		var maximum: float = arena._stats.max_health
		if not check(arena.hit_player_components({"physical":maximum * 0.8},0,["hit","spell"]), "Actual incoming hit injures current life"): return
		check(arena.health < arena.state.get_stats().accuracy, "Injured current life is below accuracy in both condition states")
		check(arena.state.get_basic_cast() == before, "Injury cannot change maximum-life condition or cached cast")
		var health: float = arena.health
		if not accepted(arena.use_flask("flask_1"), "Actual life flask use"): return
		arena.tick(0.5)
		check(arena.health > health and arena.health <= maximum, "Actual flask tick recovers current life only")
		check(arena.state.get_basic_cast() == before and arena._stats.max_health == maximum, "Actual recovery preserves exact cast and maximum-life threshold")
		if not export_fixture("selected-below" if high else "selected-above"): return
		observations.append({"high_life_gear":high,"profile":before.precise_technique_profile,"maximum":maximum,"healed_life":arena.health})
	report.resources = observations; completed = true

func actual_basic_cleave_and_spells() -> void:
	if not set_node(true): return
	var observations: Array = []
	for high: bool in [false,true]:
		if not health_gear(high): return
		for pair: Array in [[blade,"direct"],[bow,"projectile"]]:
			if not equip(pair[0]): return
			clean(); var enemy := target(); var cast: Dictionary = arena.state.get_basic_cast()
			if not profile(cast,true,"Actual basic " + pair[1]): return
			var expected_rng := RandomNumberGenerator.new(); expected_rng.state = arena.rng.state
			for draw: int in range(9 if pair[1]=="direct" else 15): expected_rng.randf()
			var crit: Dictionary = arena.critical_runtime.checkpoint(); var saved := readonly()
			arena.auto_fire = true; arena._update_auto_attack(); arena._update_projectiles(0.15); arena.auto_fire = false
			if not check(arena.damage_trace.size() == 1, "Actual basic settles exactly one hit"): return
			assert_hit(arena.damage_trace[0],cast.packets[pair[1]],cast.snapshot,"Actual basic " + pair[1])
			near(10000.0-enemy.health,arena.damage_trace[0].total,"Basic actual life debit equals settled total")
			no_crit("Actual basic"); check(arena.rng.state == expected_rng.state and arena.critical_runtime.checkpoint() == crit and readonly() == saved,"Precise basic preserves exact legacy visual RNG draws, spends no critical RNG and adds no save")
			observations.append(arena.damage_trace[0].duplicate(true))
		if not equip(blade): return
		for id: String in ["cleave","nova","bolt"]:
			clean(); target(); var cast: Dictionary = arena.state.get_group_cast(groups[id])
			if not profile(cast,id=="cleave","Actual " + id): return
			var crit: Dictionary = arena.critical_runtime.checkpoint()
			if not check(arena.cast_group(groups[id]), "Real owned " + id + " cast"): return
			arena._update_projectiles(0.15)
			if not check(arena.damage_trace.size() == (int(cast.initial_count) if id=="bolt" else 1),"Actual " + id + " preserves original hit count on one live target"): return
			var packet: Dictionary = cast.packets.get("direct",cast.packets.get("projectile",{}))
			for hit: Dictionary in arena.damage_trace: assert_hit(hit,packet,cast.snapshot,"Actual " + id)
			no_crit("Actual " + id); check(arena.critical_runtime.checkpoint() == crit,"Actual " + id + " spends no crit draw/event regardless condition")
			observations.append(arena.damage_trace[0].duplicate(true))
	report.cast_matrix = observations; completed = true

func evasion_and_resolute_union() -> void:
	if not set_node(true) or not health_gear(false) or not equip(blade): return
	clean(); var enemy := target(); enemy.evasion = 1000000000.0; enemy.evasion_entropy = 13.25
	var cast: Dictionary = arena.state.get_basic_cast(); var expected := Attack.resolve(cast.snapshot.accuracy,enemy.evasion,enemy.evasion_entropy)
	arena.auto_fire = true; arena._update_auto_attack(); arena.auto_fire = false
	check(arena.damage_trace.is_empty() and arena.attack_admission_trace.size() == 1 and not arena.attack_admission_trace[0].hit,"Precise still permits actual high-evasion miss")
	near(enemy.evasion_entropy,expected.entropy,"Precise advances existing defender entropy on miss")
	var results: Array = []
	for resolute: bool in [false,true]:
		clean(); var stats: Dictionary = arena.state.get_stats(); stats.resolute_technique = 1.0 if resolute else 0.0; stats.crit_base_chance = 1.0
		var snapshot := Combat.snapshot(stats,[]); snapshot.accuracy = stats.accuracy
		cast = Compiler.compile_group("cleave",snapshot,[])
		if not accepted(cast,"Actual union compiled cleave"): return
		enemy = target(); enemy.evasion = 1000000000.0; enemy.evasion_entropy = 98.25
		var crit: Dictionary = arena.critical_runtime.checkpoint()
		if not check(arena._execute_compiled(cast),"Actual union consumer executes"): return
		if not check(arena.damage_trace.size() == 1,"Union comparison admits same hit"): return
		near(enemy.evasion_entropy,98.25 if resolute else 3.25,"Only Resolute preserves defender entropy")
		assert_hit(arena.damage_trace[0],cast.packets.direct,cast.snapshot,"Union actual attack")
		no_crit("Union actual attack"); check(arena.critical_runtime.checkpoint() == crit,"Union crit ban draws no RNG")
		results.append(arena.damage_trace[0].before_defense_components)
	check(results[0] == results[1],"Precise plus Resolute never doubles the forty-percent MORE")
	report.union = results; completed = true

func winning_seed(snapshot: Dictionary) -> int:
	var runtime := Critical.new()
	for value: int in range(10000):
		runtime.reset(value); var frozen: Dictionary = runtime.freeze(snapshot)
		if frozen.get("ok",false) and frozen.snapshot.get("critical_roll",{}).get("critical",false): return value
	return -1
func flying_allocation_refund_and_gear() -> void:
	if not health_gear(false) or not equip(bow) or not set_node(false): return
	clean(); target(Vector2(120,0)); var old: Dictionary = arena.state.get_basic_cast()
	if not accepted(old,"Unselected old bow cast"): return
	check(not old.has("precise_technique_profile") and not old.snapshot.has(STAT),"Unselected cast omits both optional public/source fields")
	var seed_value := winning_seed(old.snapshot)
	if not check(seed_value >= 0,"Actual old critical chance has deterministic winning seed"): return
	arena.critical_runtime.reset(seed_value); arena.auto_fire = true; arena._update_auto_attack(); arena.auto_fire = false
	if not check(arena.projectiles.size() == 1,"Old critical projectile launches"): return
	var frozen := var_to_bytes(arena.projectiles[0].snapshot); var timer: float = arena.attack_timer
	if not set_node(true): return
	check(var_to_bytes(arena.projectiles[0].snapshot) == frozen and arena.attack_timer == timer,"Allocation cannot alter in-flight old roll or timer")
	arena._update_projectiles(0.25)
	if not check(arena.damage_trace.size() == 1 and arena.damage_trace[0].get("critical",{}).get("critical",false),"Old projectile still crits after precise allocation"): return
	assert_hit(arena.damage_trace[0],old.packets.projectile,old.snapshot,"Old projectile retains old damage",arena.damage_trace[0].critical.multiplier)
	# Allocate/gear/condition/refund affect subsequent casts, never live carriers.
	for change: String in ["raise_maximum","lower_maximum","refund"]:
		if not set_node(true) or not health_gear(change == "lower_maximum") or not equip(bow): return
		clean(); target(Vector2(120,0)); old = arena.state.get_basic_cast()
		if not profile(old,true,"Pre-change actual bow"): return
		arena.auto_fire = true; arena._update_auto_attack(); arena.auto_fire = false
		if not check(arena.projectiles.size() == 1,"Enabled real bow carrier exists"): return
		frozen = var_to_bytes(arena.projectiles[0].snapshot); timer = arena.attack_timer
		var crit: Dictionary = arena.critical_runtime.checkpoint()
		if change == "raise_maximum":
			if not health_gear(true): return
		elif change == "lower_maximum":
			if not health_gear(false): return
		else:
			if not set_node(false) or not equip(blade) or not export_fixture("refunded"): return
		check(var_to_bytes(arena.projectiles[0].snapshot) == frozen and arena.attack_timer == timer,"Actual " + change + " preserves frozen original cast")
		var fresh: Dictionary = arena.state.get_basic_cast()
		check(fresh.snapshot != old.snapshot,"Actual " + change + " changes future cast only")
		arena._update_projectiles(0.25)
		if not check(arena.damage_trace.size() == 1,"Old enabled projectile settles after " + change): return
		assert_hit(arena.damage_trace[0],old.packets.projectile,old.snapshot,"Frozen " + change)
		no_crit("Frozen " + change); check(arena.critical_runtime.checkpoint() == crit,"Impact cannot draw current build critical RNG")
	completed = true
func path_to(destination: String) -> Array:
	var paths := {}; var queue: Array[String] = []
	for id: String in arena.state.snapshot().talents.allocated: paths[id] = []; queue.append(id)
	var offset := 0
	while offset < queue.size():
		var id := queue[offset]; offset += 1
		if id == destination: return paths[id]
		for next: String in Source.Data.adjacency(id):
			var node: Dictionary = Source.Data.node(next)
			if paths.has(next) or node.type in ["mastery","start"] or node.source.get("isProxy",false) or node.source.get("isBlighted",false): continue
			if Source.node_effect(next).status != "full": continue
			paths[next] = paths[id] + [next]; queue.append(next)
	return []
func allocate_real_conversion() -> bool:
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level":100,"xp":0}; candidate.talents.normal_points = 104 - (candidate.talents.allocated.size()-1); candidate.revision += 1
	if not check(Model.Rules.reason(candidate).is_empty(),"Lawful conversion route earned-point fixture"): return false
	if not accepted(arena.state._commit(candidate,arena.build_save_path),"Commit lawful point budget for real conversion route"): return false
	var route := path_to("2550")
	if not check(not route.is_empty(),"Supported path reaches real Arsonist2550 notable"): return false
	for id: String in route:
		if not check(arena.state.available_passives().has(id),"Real conversion approach node reachable " + id): return false
		if not accepted(arena.state.allocate_passive(id,0,arena.state.revision(),arena.build_save_path),"Real conversion approach allocation " + id): return false
	if not check(arena.state.available_passives().has("48267"),"Real fire mastery unlocked"): return false
	if not accepted(arena.state.allocate_passive("48267",65020,arena.state.revision(),arena.build_save_path),"Actual mastery65020 allocation"): return false
	near(arena.state.get_stats().get("physical_to_fire_conversion",0.0),0.4,"Real source65020 provides original conversion ratio")
	report.conversion_route = route
	return true
func tornado_conversion_frozen_lifecycle() -> void:
	if not set_node(true) or not health_gear(false) or not equip(bow) or not allocate_real_conversion(): return
	var conversion_hits: Array = []
	for pair: Array in [[blade,"direct"],[bow,"projectile"]]:
		if not equip(pair[0]): return
		clean(); target(); var basic: Dictionary = arena.state.get_basic_cast()
		if not profile(basic,true,"Real65020 precise basic") or not check(basic.packets[pair[1]].has("conversion"),"Actual65020 converts basic " + pair[1]): return
		arena.auto_fire=true; arena._update_auto_attack(); arena._update_projectiles(0.15); arena.auto_fire=false
		if not check(arena.damage_trace.size()==1,"Real65020 basic settles one hit"): return
		assert_hit(arena.damage_trace[0],basic.packets[pair[1]],basic.snapshot,"Real65020 basic " + pair[1])
		check(arena.damage_trace[0].components.size()==2,"Real65020 basic settles physical and fire")
		conversion_hits.append(arena.damage_trace[0].duplicate(true))
	if not equip(blade): return
	clean(); target(); var cleave: Dictionary = arena.state.get_group_cast(groups.cleave)
	if not profile(cleave,true,"Real65020 precise cleave") or not check(cleave.packets.direct.has("conversion"),"Actual65020 converts real cleave"): return
	if not check(arena.cast_group(groups.cleave),"Real65020 precise cleave executes") or not check(arena.damage_trace.size()==1,"Real65020 cleave settles one hit"): return
	assert_hit(arena.damage_trace[0],cleave.packets.direct,cleave.snapshot,"Real65020 precise cleave")
	conversion_hits.append(arena.damage_trace[0].duplicate(true)); report.conversion_attacks=conversion_hits
	if not equip(bow): return
	clean(); var cast: Dictionary = arena.state.get_group_cast(groups.tornado)
	if not profile(cast,true,"Real precise and65020 tornado"): return
	if not check(cast.snapshot.effects.has("return_on_range") and cast.snapshot.effects.has("explode_on_flight_end"),"Explicit owned mantle/charm supply genuine return and secondary"): return
	for role: String in ["parent","child"]:
		if not check(cast.packets[role].has("conversion"),"Real65020 converts " + role): return
	var first := target(Vector2(60,0)); var crit: Dictionary = arena.critical_runtime.checkpoint()
	if not check(arena.cast_group(groups.tornado),"Real converted precise tornado launches"): return
	if not check(not arena.projectiles.is_empty(),"Actual tornado parent carriers exist"): return
	var frozen := var_to_bytes(arena.projectiles[0].snapshot)
	if not set_node(false) or not equip(blade): return
	check(not arena.state.get_group_cast(groups.tornado).has("precise_technique_profile"),"Refund removes precise only from future cast")
	arena._update_projectiles(0.4)
	if not check(not arena.damage_trace.is_empty() and int(arena.event_counts.get("split",0))>0,"Frozen parents hit and naturally split after refund"): return
	var parent: Dictionary = arena.damage_trace[0].duplicate(true)
	assert_hit(parent,cast.packets.parent,cast.snapshot,"Converted precise parent after refund")
	check(first.health < 10000.0 and arena.projectiles.size() == int(cast.initial_count)*3,"Real parent creates exact original children")
	for shot: Dictionary in arena.projectiles: check(shot.generation == 1 and var_to_bytes(shot.snapshot)==frozen,"Child inherits exact original precise/MORE/critical snapshot")
	if not check(not arena.projectiles.is_empty(),"Actual children remain"): return
	var child: Dictionary = arena.projectiles[0]
	var child_target := target(Vector2(child.pos)+Vector2(child.velocity).normalized()*30.0-arena.player_pos)
	arena._update_projectiles(0.2)
	var hits: Array = arena.damage_trace.filter(func(hit: Dictionary) -> bool: return hit.target_id==child_target.id and hit.projectile_id==child.id)
	if not check(hits.size()==1,"Actual converted precise child contacts once"): return
	var child_hit: Dictionary = hits[0].duplicate(true)
	assert_hit(child_hit,cast.packets.child,cast.snapshot,"Converted precise child after refund")
	arena._update_projectiles(0.4)
	if not check(not arena.projectiles.is_empty() and int(arena.event_counts.get("return_started",0))>0,"Original children enter natural return phase"): return
	for shot: Dictionary in arena.projectiles: check(shot.state=="returning" and var_to_bytes(shot.snapshot)==frozen,"Returning child retains original snapshot")
	var returning: Dictionary = arena.projectiles[0]
	arena.enemies.clear(); arena.damage_trace.clear()
	var receiver := target(Vector2(returning.pos)+Vector2(returning.velocity).normalized()*20.0-arena.player_pos)
	arena._update_projectiles(0.1)
	hits = arena.damage_trace.filter(func(hit: Dictionary) -> bool: return hit.target_id==receiver.id and hit.projectile_id==returning.id)
	if not check(hits.size()==1,"Original returning child settles real hit"): return
	assert_hit(hits[0],cast.packets.child,cast.snapshot,"Converted returning child no second MORE")
	var remaining: float = float(returning.lifetime)-float(returning.age)
	var endpoint: Vector2 = Vector2(returning.pos)+Vector2(returning.velocity)*remaining
	arena.enemies.clear(); arena.damage_trace.clear()
	var end_target := target(endpoint+Vector2(returning.velocity).normalized().orthogonal()*25.0-arena.player_pos)
	arena._update_projectiles(remaining+0.02)
	check(arena.projectiles.is_empty() and int(arena.event_counts.get("explosion",0))>0,"Real frozen children naturally expire and explode")
	var secondary: Array = arena.damage_trace.filter(func(hit: Dictionary) -> bool: return hit.target_id==end_target.id and hit.tags.has("secondary"))
	if not check(not secondary.is_empty(),"Real original secondary hits after precise refund"): return
	for hit: Dictionary in secondary:
		assert_hit(hit,cast.packets.secondary,cast.snapshot,"Natural secondary has no attack MORE")
		check(not hit.get("critical",{}).get("critical",false),"Secondary retains old unconditional critical ban after refund")
	check(arena.critical_runtime.checkpoint()==crit,"Whole parent/child/return/secondary lifecycle draws no crit event")
	report.lifecycle = {"parent":parent,"child":child_hit,"secondary":secondary,"events":arena.event_counts.duplicate(true)}
	completed = true
func false_condition_secondary() -> void:
	if not set_node(true) or not health_gear(true) or not equip(bow) or not equip(low_equipment.amulet,"amulet"): return
	clean(); var cast: Dictionary = arena.state.get_group_cast(groups.tornado)
	if not profile(cast,true,"Condition-false actual secondary source"): return
	if not check(not cast.precise_technique_profile.condition_met and cast.snapshot.effects.has("explode_on_flight_end"),"Real life gear/charm retains secondary with false condition"): return
	var crit: Dictionary = arena.critical_runtime.checkpoint()
	# This carrier uses the actual owned cast's frozen packet/snapshot and the
	# real natural-expiry consumer, with an exact two-target geometry fixture.
	var frozen: Dictionary = arena.critical_runtime.freeze(cast.snapshot)
	if not accepted(frozen,"Actual condition-false freeze"): return
	var origin: Vector2 = arena.player_pos+Vector2(200,0)
	var one := target(origin+Vector2(0,25)-arena.player_pos); var two := target(origin+Vector2(0,-25)-arena.player_pos)
	var shot: Dictionary = arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,{"speed":10.0,"range":500.0,"lifetime":0.01,"pierce":-1,"radius":1.0},cast.packets.parent,frozen.snapshot,arena.projectile_runtime.new_cast(),Color.WHITE)
	arena.projectiles.append(shot); arena._update_projectiles(0.02)
	if not check(arena.damage_trace.size()==2 and int(arena.event_counts.get("explosion",0))==1,"Condition-false natural secondary hits exact two live targets"): return
	for hit: Dictionary in arena.damage_trace:
		check(hit.tags.has("secondary"),"Actual condition-false hit is secondary")
		assert_hit(hit,cast.packets.secondary,cast.snapshot,"Condition-false secondary no MORE")
	no_crit("Condition-false secondary")
	check(arena.critical_runtime.checkpoint()==crit and arena.attack_admission_trace.is_empty(),"False-condition secondary draws no critical event or attack admission")
	check(one.health<10000.0 and two.health<10000.0,"Actual secondary debits both targets")
	report.false_secondary = arena.damage_trace.duplicate(true); completed = true

func export_fixture(name: String) -> bool:
	var directory := OS.get_environment("PRECISE_FIXTURE_DIR")
	if directory.is_empty(): return true
	if not check(DirAccess.make_dir_recursive_absolute(directory)==OK,"Create readonly fixture output directory"): return false
	var raw: Dictionary = arena.state.snapshot(); var stats: Dictionary = arena.state.get_stats()
	if not check(Model.Rules.reason(raw).is_empty(),"Exported representative build is legal " + name): return false
	var file := FileAccess.open(directory+"/"+name+".json",FileAccess.WRITE)
	if not check(file!=null,"Open representative raw snapshot " + name): return false
	file.store_string(JSON.stringify(raw,"\t",true,true)); file.close()
	var expected := {"stats":stats,"basic":arena.state.get_basic_cast(),"tornado":arena.state.get_group_cast(groups.tornado),"cleave":arena.state.get_group_cast(groups.cleave)}
	file=FileAccess.open(directory+"/"+name+"-expected.json",FileAccess.WRITE)
	if not check(file!=null,"Open representative expected projection " + name): return false
	file.store_string(JSON.stringify(expected,"\t",true,true)); file.close()
	return true
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v070-precise-") or not OS.get_user_data_dir().begins_with(isolated+"/"):
		quit(78); return
	create_timer(35.0).timeout.connect(watchdog)
	arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire=false
	var selection := OS.get_environment("PRECISE_GAMEPLAY_SECTIONS").split(",",false)
	if section(legal_source_and_owned_items):
		for test: Callable in [maximum_life_gear_and_resources,actual_basic_cleave_and_spells,evasion_and_resolute_union,flying_allocation_refund_and_gear,false_condition_secondary,tornado_conversion_frozen_lifecycle]:
			if not selection.is_empty() and not selection.has(test.get_method()): continue
			if not section(test): break
	report.merge({"checks":checks,"failures":failures,"sections":sections,"scope":"Bounded actual Main, lawful source allocations and real item transactions. No Windows/UI/package acceptance; no historical-byte oracle."})
	var output := OS.get_environment("PRECISE_GAMEPLAY_REPORT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("PRECISE_GAMEPLAY ",JSON.stringify({"checks":checks,"failures":failures,"sections":sections}))
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
