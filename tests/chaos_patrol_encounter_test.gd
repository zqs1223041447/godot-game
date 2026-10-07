extends SceneTree
## Pure catalog, roster and scheduler checks. Real Main admission/combat is a
## separate bounded integration check; these fixtures never claim natural play.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Camps = preload("res://scripts/world/map_camp_state.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const Factory = preload("res://scripts/monsters/monster_runtime.gd")
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const OldMonsters = preload("res://docs/qa/v093-encounter/frozen/monster_catalog.gd")
const OldMaps = preload("res://docs/qa/v093-encounter/frozen/map_compiler.gd")
const OldCamps = preload("res://docs/qa/v093-encounter/frozen/map_camp_state.gd")
const OldRuntime = preload("res://docs/qa/v093-encounter/frozen/telegraphed_area_runtime.gd")
const BOUNDS := Rect2(0, 0, 1840, 710)
const CENTER := Vector2(600, 350)
var checks := 0
var failures := 0
var profiles_checked := 0
var chaos_roots := 0
var rarity_coverage := {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)


func same(actual: Variant, expected: Variant, label: String) -> void:
	check(var_to_bytes(actual) == var_to_bytes(expected), label)


func _initialize() -> void:
	seed(930093)
	var expected_random := randi()
	seed(930093)
	_templates()
	_legacy_contracts()
	_map_rosters()
	_telegraphs()
	check(randi() == expected_random, "All catalog, map and scheduler work preserves global RNG")
	print("Chaos patrol encounter: %d checks, %d failures; %d legacy profiles; %d chaos roots; rarities %s" % [checks, failures, profiles_checked, chaos_roots, rarity_coverage.keys()])
	quit(1 if failures else 0)


func _project(enemy: Dictionary) -> Dictionary:
	var result := enemy.duplicate(true)
	for field: String in ["template_id", "name", "defense_stats", "resistances", "contact_weights"]: result.erase(field)
	return result


func _templates() -> void:
	check(Monsters.validate_templates(Monsters.TEMPLATES).is_empty(), "Authored catalog validates")
	for rarity: String in Monsters.ORDINARY_RARITIES:
		var grants: Array = [] if rarity == "normal" else (["source_gale_stride"] if rarity == "magic" else ["source_ember_power", "source_aegis_capacity"])
		var chaos := Monsters.make_enemy(1, "chaos_guard", 5, CENTER, "ordinary", rarity, grants)
		var brute := Monsters.make_enemy(1, "brute", 5, CENTER, "ordinary", rarity, grants)
		check(not chaos.is_empty() and chaos.kind == 2 and chaos.rarity == rarity, "Chaos guard retains ordinary heavy species and rarity " + rarity)
		same(_project(chaos), _project(brute), "Only authored identity, attack type and resistance differ from original heavy actor " + rarity)
		same(chaos.defense_stats, {"chaos_resistance": 0.25}, "Only the new actor explicitly carries chaos resistance")
		check(chaos.resistances.chaos == 0.25 and chaos.contact_weights == {"chaos":1.0}, "New enemy has 25 percent resistance and pure chaos components")
		check(chaos.equipment_pool == "" and chaos.death_spawns.is_empty(), "No new item pool or descendants")
		check(Monsters.uses_telegraph(chaos), "Chaos actor cannot fall through to unavoidable contact damage")
		var policy := Monsters.telegraph_policy(chaos)
		check(policy.target_rule == "player_at_start" and policy.visual_pattern == "chaos_guard" and policy.trigger_distance == 150.0, "Canonical player-locked policy and visual identity")
		check(policy.profile.windup_seconds == 1.0 and policy.profile.radius == 90.0 and policy.profile.damage_multiplier == 0.8, "One-second warning and conservative readable damage budget")
		check(is_equal_approx(policy.profile.recovery_seconds, 1.8 * Monsters.BASE_ATTACK_SPEED / chaos.attack_speed), "Only recovery inherits attack speed")
		check(Monsters.mechanism_text(chaos).contains("纯混沌") and Monsters.resistance_text(chaos).contains("25%"), "Enemy explanation names pure chaos and resistance")
		check(Monsters.resistance_text(chaos, true) == "混抗25%", "Compact new resistance text")
		var burst: float = chaos.damage * policy.profile.damage_multiplier
		check(burst < brute.damage and burst / (policy.profile.windup_seconds + policy.profile.recovery_seconds) < brute.damage * brute.attack_speed, "Dodgeable chaos burst and cycle budget are below original contact budget")
	for id: String in OldMonsters.TEMPLATES:
		check(not Monsters.TEMPLATES[id].get("defense_stats", {}).has("chaos_resistance"), "Old template has no implicit chaos stat " + id)
	for invalid: Variant in [null, [], "25", true, NAN, INF, -INF, {"chaos_resistance":0.25, "unknown_defense":1.0}, {"chaos_resistance":0.25, "cold_resistance":0.25}]:
		var templates := Monsters.TEMPLATES.duplicate(true)
		templates.chaos_guard.defense_stats = invalid if invalid is Dictionary or invalid == null or invalid is Array else {"chaos_resistance": invalid}
		check(not Monsters.validate_templates(templates).is_empty(), "Malformed or unrecognized chaos template defense fails closed")
	var missing := Monsters.TEMPLATES.duplicate(true)
	missing.chaos_guard.defense_stats = {}
	check(not Monsters.validate_templates(missing).is_empty(), "New template requires its explicit resistance field")
	for id: String in ["brute", "custom_guard"]:
		var templates := Monsters.TEMPLATES.duplicate(true)
		templates[id] = Monsters.TEMPLATES.brute.duplicate(true)
		templates[id].defense_stats = {"chaos_resistance":0.25}
		check(not Monsters.validate_templates(templates).is_empty(), "Only authored new template receives the explicit schema extension " + id)
	check(not Defense.defense_profile({"chaos_resistance":0.25}, "monster").ok, "Historical defense schema stays strict and fire-only")


func _legacy_contracts() -> void:
	var current_catalog := Monsters.new()
	var before_catalog := OldMonsters.new()
	same(Monsters.elemental_encounter_policy(), OldMonsters.elemental_encounter_policy(), "Natural elemental encounter policy is byte-identical")
	same(Monsters.fire_encounter_policy(), OldMonsters.fire_encounter_policy(), "Reserved fire encounter and once-only reward policy unchanged")
	same(Maps.Catalog.MAPS, OldMaps.Catalog.MAPS, "Every existing map including descriptions remains byte-identical")
	for test_mode: bool in [false, true]:
		var options := Maps.Catalog.options(test_mode)
		var added: Dictionary = options.special_modifiers.pop_back()
		check(added.id == "chaos_patrol" and added.completion_reward_bonus == (0 if test_mode else 2), "New option appends with existing test/normal reward policy")
		same(options, OldMaps.Catalog.options(test_mode), "Old option rows, order and metadata remain byte-identical")
	for id: String in OldMonsters.TEMPLATES:
		var context := "map_boss" if id == "rift_warden" else "ordinary"
		for wave: int in [1, 5, 10]:
			var current := Monsters.make_enemy(3, id, wave, CENTER, context)
			var before := OldMonsters.make_enemy(3, id, wave, CENTER, context)
			same(current, before, "Old complete actor bytes unchanged " + id)
			same(Monsters.telegraph_policy(current), OldMonsters.telegraph_policy(before), "Old explicit telegraph profile bytes unchanged " + id)
			same(Monsters.mechanism_text(current), OldMonsters.mechanism_text(before), "Old mechanism descriptions unchanged " + id)
			check(not current.defense_stats.has("chaos_resistance") and not current.resistances.has("chaos"), "No new chaos key on an old actor " + id)
	for method: String in ["ordinary_roll", "ordinary_roll_source_stride", "ordinary_roll_source_damage_life", "ordinary_roll_current"]:
		for wave: int in [1, 4, 5, 10]:
			var current_rng := RandomNumberGenerator.new(); current_rng.seed = 9381 + wave
			var before_rng := RandomNumberGenerator.new(); before_rng.seed = current_rng.seed
			for unused: int in range(64):
				same(current_catalog.call(method, current_rng, wave), before_catalog.call(method, before_rng, wave), "Historical sampler output unchanged " + method)
				check(current_rng.state == before_rng.state, "Historical sampler RNG consumption unchanged " + method)


func _entries(state: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for camp_id: String in Camps.CAMP_IDS: result.append_array(state.entries(camp_id))
	return result


func _map_rosters() -> void:
	var before_maps := OldMaps.new()
	var current_maps := Maps.new()
	for map_id: String in Maps.Catalog.MAPS:
		var landmarks: Dictionary = Layout.layout(map_id, BOUNDS).landmarks
		for tier: int in range(0, 4):
			var compile_method := "compile" if tier == 0 else "compile_normal"
			for special: Array in [[], ["elemental_aegis"], ["frost_patrol"], ["storm_patrol"]]:
				var args: Array = [map_id, [], special] if tier == 0 else [map_id, tier, [], special]
				var old: Dictionary = before_maps.callv(compile_method, args)
				var current: Dictionary = current_maps.callv(compile_method, args)
				same(current, old, "Old explicit map profile or rejection is byte-identical %s/%d/%s" % [map_id,tier,special])
				if not current.ok: continue
				profiles_checked += 1
				var before := OldCamps.new(); var now := Camps.new()
				check(before.begin(old.profile, landmarks, 9301, Monsters.CURRENT_ROLL_POLICY).ok and now.begin(current.profile, landmarks, 9301, Monsters.CURRENT_ROLL_POLICY).ok, "Both frozen and current camp preplans admit")
				same(now.checkpoint(), before.checkpoint(), "Existing special preplans preserve full native bytes")
			var plain: Dictionary = Maps.compile(map_id, [], []) if tier == 0 else Maps.compile_normal(map_id, tier, [], [])
			var chaos: Dictionary = Maps.compile(map_id, [], ["chaos_patrol"]) if tier == 0 else Maps.compile_normal(map_id, tier, [], ["chaos_patrol"])
			check(chaos.ok == (plain.profile.wave >= 5), "Chaos patrol wave gate is exact for all four maps and three tiers")
			if not chaos.ok: continue
			check(Maps.profile_reason(chaos.profile).is_empty(), "New profile is canonical")
			if tier > 0: check(chaos.profile.completion_reward == plain.profile.completion_reward + 2, "Normal special grants only existing completion +2")
			else: check(not chaos.profile.has("completion_reward"), "Test special adds no completion reward")
			for seed_value: int in [9301, 9302, 9303]:
				var before := Camps.new(); var now := Camps.new()
				check(before.begin(plain.profile, landmarks, seed_value, Monsters.CURRENT_ROLL_POLICY).ok and now.begin(chaos.profile, landmarks, seed_value, Monsters.CURRENT_ROLL_POLICY).ok, "Selected patrol uses original complete pre-generation")
				var old_entries := _entries(before); var entries := _entries(now)
				check(entries.size() == plain.profile.ordinary_target and entries.size() == old_entries.size(), "Patrol never adds or loses slots")
				for index: int in range(entries.size()):
					var entry: Dictionary = entries[index]; var original: Dictionary = old_entries[index]
					if original.template_id not in ["brute", "frost_guard"]:
						same(entry, original, "Reserved ember, split, brood, skitter and other slots untouched")
						continue
					chaos_roots += 1; rarity_coverage[entry.rarity] = true
					check(entry.template_id == "chaos_guard", "Only original heavy patrol species becomes chaos guard")
					var projection := entry.duplicate(true); projection.template_id = original.template_id
					same(projection, original, "Replacement preserves rarity, source grants, position and admission identity")
					var original_enemy := Monsters.make_enemy(index + 1, original.template_id, plain.profile.wave, original.position, "ordinary", original.rarity, original.mechanisms)
					var admitted := Admission.create_root(Factory.new(), chaos.profile, entry.template_id, chaos.profile.wave, entry.position, "ordinary", entry.rarity, entry.mechanisms, true)
					check(admitted.ok, "Real map admission accepts selected chaos template")
					if admitted.ok:
						admitted.enemy.id = index + 1; admitted.enemy.root_id = index + 1
						same(_project(admitted.enemy), _project(original_enemy), "Map actor projection retains inherited combat/reward/lineage fields")
			var factory := Factory.new()
			var boss := Admission.create_root(factory, chaos.profile, "rift_warden", chaos.profile.wave, CENTER, "map_boss", "", [], true)
			check(boss.ok and boss.enemy.template_id == "rift_warden", "Patrol never replaces map boss")
			boss.enemy.health = 0.0; check(factory.process_death(boss.enemy).reward, "Boss still has one original reward")
			var children := Admission.drain(factory, chaos.profile, 10, BOUNDS)
			check(children.ok and children.enemies.size() == 4, "Original boss descendants stay in the original queue")
			for child: Dictionary in children.enemies: check(child.template_id == "crawler" and not child.reward_eligible, "Patrol does not replace or reward descendants")
	check(rarity_coverage.has_all(["normal", "magic", "rare"]), "Natural deterministic new rosters cover all original ordinary rarities")
	var factory := Factory.new(); var root_enemy := factory.create_root("chaos_guard", 5, CENTER)
	root_enemy.health = 0.0
	check(factory.process_death(root_enemy) == {"processed":true,"reward":true,"queued":0}, "Chaos root yields only its original once-only reward")
	check(factory.process_death(root_enemy) == {"processed":false,"reward":false,"queued":0}, "Repeated chaos death grants nothing")


func _telegraphs() -> void:
	var enemy := Monsters.make_enemy(1, "chaos_guard", 5, Vector2(500,350))
	var policy := Monsters.telegraph_policy(enemy)
	var runtime := Runtime.new()
	check(not runtime.start(enemy, CENTER, policy.profile, policy.visual_pattern).ok, "Birth protection blocks new warning through existing scheduler")
	enemy.spawn = 0.0
	check(runtime.start(enemy, CENTER, policy.profile, policy.visual_pattern).ok, "Pure chaos uses original locked-circle scheduler")
	check(not runtime.has_burning_actions() and not runtime.has_timed_sequence_actions(), "Chaos introduces no status/sequence clock")
	var before := var_to_bytes(runtime.state_for(1))
	check(runtime.advance(2.0, [enemy], true, {1:2.0}).is_empty(), "Frozen chaos windup emits nothing")
	check(var_to_bytes(runtime.state_for(1)) == before, "Freeze pauses the original local clock without retargeting")
	enemy.pos = Vector2(900, 350)
	check(runtime.advance(0.99, [enemy]).is_empty(), "No damage before full one-second warning")
	var events := runtime.advance(0.51, [enemy], true, {1:0.5})
	check(events.size() == 1, "Partial thaw emits exactly one pending chaos attack")
	if events.size() != 1: return
	var event: Dictionary = events[0]
	check(event.center == CENTER and event.visual_pattern == "chaos_guard", "Pure chaos warning retains original locked position and shape identity")
	check(event.packet.base.size() == 1 and is_equal_approx(event.packet.base.chaos, enemy.damage * 0.8), "Attack packet contains only authored pure chaos budget")
	check(not event.has("burn_policy") and not event.has("shock_policy") and not event.has("chill_policy"), "New hit has no borrowed ailment payload")
	check(Runtime.overlaps(event, CENTER, 15.0) and not Runtime.overlaps(event, CENTER + Vector2(106,0), 15.0), "Standing is hit and leaving 90-plus-15 collision radius dodges")
	check(not Runtime.overlaps(event, CENTER + Vector2(200,0) * policy.profile.windup_seconds, 15.0), "Controlled 200-unit walking fixture clears warning during its one-second windup")
	before = var_to_bytes(runtime.state_for(1))
	check(runtime.advance(2.0, [enemy], false, {1:2.0}).is_empty() and var_to_bytes(runtime.state_for(1)) == before, "Existing freeze behavior also pauses chaos recovery")
	check(runtime.advance(1.8, [enemy]).is_empty() and runtime.active_count() == 0, "One recovery finishes without repeat hits")
	var impostor := Monsters.make_enemy(2, "brute", 5, CENTER); impostor.spawn = 0.0
	check(not runtime.start(impostor, CENTER, policy.profile, "chaos_guard").ok, "Chaos visual pattern cannot be attached to another template")
	for pattern: String in ["ember_burn", "storm_shock", "garden_slam", "unknown"]:
		check(not runtime.start(enemy, CENTER, policy.profile, pattern).ok, "New template cannot forge an old/unknown attack identity")
	check(runtime.start(enemy, CENTER, policy.profile).ok, "Empty visual argument derives the new template's authoritative identity")
	enemy.health = 0.0
	check(runtime.advance(4.0, [enemy]).is_empty() and runtime.active_count() == 0, "Original source-death cancellation prevents delayed chaos damage")
	for id: String in ["brute", "ember_guard", "frost_guard", "storm_skitter"]:
		var actor := Monsters.make_enemy(1, id, 5, CENTER); actor.spawn = 0.0
		var old := OldRuntime.new(); var now := Runtime.new()
		var old_policy := OldMonsters.telegraph_policy(actor)
		var profile: Dictionary = old_policy.get("profile", {})
		var pattern: String = old_policy.get("visual_pattern", "")
		same(now.start(actor, CENTER, profile, pattern), old.start(actor, CENTER, profile, pattern), "Old scheduler start remains byte-identical " + id)
		for delta: float in [0.0, 0.2, 0.7, 0.1, 1.0, 2.0]:
			same(now.advance(delta, [actor], true), old.advance(delta, [actor], true), "Old scheduler events remain byte-identical " + id)
			same(now.state_for(1), old.state_for(1), "Old scheduler retained state remains byte-identical " + id)
