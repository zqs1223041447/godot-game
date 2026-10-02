extends SceneTree
## Independent acceptance: real catalog inputs, runtime descendants and 100 scene actors.
## Run with disposable XDG directories; this suite is not wired into tools/validate.sh.
const Catalog = preload("res://scripts/encounters/encounter_catalog.gd")
const Compiler = preload("res://scripts/encounters/encounter_compiler.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const BOTH: Array[String] = ["enemy_max_health_120", "enemy_move_speed_110"]
const ARENA := Rect2(0, 0, 2400, 1400)
var checks: int = 0
var failures: int = 0
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_case(_test_metadata, "single-source metadata and frozen profiles")
	_case(_test_selection, "bounded exact IDs and deterministic order")
	_case(_test_profiles, "forged, stale and incomplete profiles")
	_case(_test_all_templates_and_rarities, "all current templates, rarities and generation gates")
	_case(_test_resources, "life ratios, unchanged shields and typed defense")
	_case(_test_inputs, "invalid enemy resources and provenance")
	_case(_test_detachment_and_reentry, "deep copies and unconditional reentry rejection")
	_case(_test_lineages, "real descendants, reward eligibility and once-only deaths")
	_case(_test_rng, "spawn/loot/global RNG and loot outcome equivalence")
	_case(_test_hundred_real_actors, "100 real scene actors, movement, damage and cap")
	print("Encounter compiler: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	_finished = false
	test.call()
	_expect(_finished, "Suite reaches final assertion without script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(is_finite(actual) and absf(actual - expected) < 0.00001,
		"%s (actual %.8f, expected %.8f)" % [label, actual, expected])


func _base() -> Dictionary:
	return Monsters.make_enemy(1, "brute", 8, Vector2(300, 300), "ordinary", "rare",
		["grove_vitality", "aegis_capacity"])


func _frozen(value: Variant) -> bool:
	if value is Dictionary:
		if not value.is_read_only():
			return false
		for entry: Variant in value.values():
			if not _frozen(entry):
				return false
	elif value is Array:
		if not value.is_read_only():
			return false
		for entry: Variant in value:
			if not _frozen(entry):
				return false
	return true


func _preserved(before: Dictionary, after: Dictionary, label: String) -> void:
	var restored: Dictionary = after.duplicate(true)
	_expect(restored.has(Compiler.SOURCE_FIELD), label + ": source marker is present")
	restored.erase(Compiler.SOURCE_FIELD)
	for field: String in ["health", "max_health", "speed"]:
		restored[field] = before[field]
	_expect(restored == before, label + ": every other field and nested value stays equal")


func _test_metadata() -> void:
	_expect(Catalog.get_ids() == BOTH and Catalog.MAX_MODIFIERS == 2, "Exactly two supported challenges")
	var metadata: Dictionary = Catalog.metadata()
	var metadata_before: Dictionary = metadata.duplicate(true)
	_expect(metadata.source.monster_schema_version == Monsters.SCHEMA_VERSION, "Monster schema uses the live catalog constant")
	_expect(metadata.source.catalog == Catalog.SOURCE and metadata.source.balance_source == "original_game_balance", "Balance and definition source are explicit")
	_expect(Catalog.get_definition("unknown").is_empty(), "Unknown metadata lookup has no fallback")
	var result: Dictionary = Compiler.compile(BOTH)
	_expect(result.ok and _frozen(result.profile), "Entire compiled configuration is recursively read-only")
	_expect(result.profile.source == metadata.source and result.profile.definitions == metadata.definitions, "Preview and execution consume the same definitions")
	_expect(result.profile.resource_policy == metadata.resource_policy and result.profile.reward_budget == metadata.reward_budget, "Policy and budget have one source")
	_expect(not metadata.reward_budget.enabled and metadata.reward_budget.proposed_bonus_fraction == null
		and not metadata.reward_budget.grants_rewards and not metadata.reward_budget.creates_map_items, "Optional reward budget is unproposed and has no execution")
	for definition: Dictionary in metadata.definitions:
		_expect(definition.description.ends_with("×%.2f" % float(definition.multiplier)), "Description derives from numeric multiplier")
		_expect(definition.source_id == "encounter:" + str(definition.id), "Definition has stable source identity")
		_near(definition.risk.relative_increase, float(definition.multiplier) - 1.0, "Risk parameter derives from operation")
		_expect(result.profile.multipliers[definition.field] == definition.multiplier, "Compiled operation agrees with metadata")
	_near(result.profile.multipliers.max_health, 1.20, "Health challenge has the requested exact factor")
	_near(result.profile.multipliers.speed, 1.10, "Movement challenge has the requested exact factor")
	metadata.definitions[0].multiplier = 500.0
	metadata.resource_policy.health = "refill"
	metadata.source.definition_revision = -1
	_expect(Catalog.metadata() == metadata_before and result.profile == Compiler.compile(BOTH).profile, "Detached metadata edits cannot change catalog or frozen output")
	_expect(Catalog.get_definition(BOTH[0]).multiplier == 1.20, "Detached lookup cannot corrupt catalog")
	_finished = true


func _test_selection() -> void:
	for ids: Array in [[], [BOTH[0]], [BOTH[1]], BOTH, [BOTH[1], BOTH[0]]]:
		var before: Array = ids.duplicate(true)
		var result: Dictionary = Compiler.compile(ids)
		_expect(result.ok and ids == before, "Valid selection compiles without modifying caller array")
		_expect(Compiler.profile_error(result.profile).is_empty(), "Compiler output validates")
	_expect(Compiler.compile(BOTH).profile == Compiler.compile([BOTH[1], BOTH[0]]).profile, "Input order cannot alter canonical frozen profile")
	var empty: Dictionary = Compiler.compile([]).profile
	_expect(empty.multipliers == {"max_health": 1.0, "speed": 1.0} and empty.risk_parameters.is_empty(), "Empty selection is identity with no risk parameters")
	for ids: Variant in [null, {}, "enemy_max_health_120", 2, PackedStringArray(BOTH),
		[BOTH[0], BOTH[0]], [BOTH[1], BOTH[1]], [BOTH[0], BOTH[1], "other"],
		["other"], [BOTH[0], "other"], [1], [true], [null], [[]], [""], ["enemy_damage_110"]]:
		var rejected: Dictionary = Compiler.compile(ids)
		_expect(not rejected.ok and not rejected.error.is_empty() and not rejected.has("profile"), "Invalid selection fails atomically")
	_finished = true


func _test_profiles() -> void:
	var enemy: Dictionary = _base()
	var baseline: Dictionary = enemy.duplicate(true)
	var good: Dictionary = Compiler.compile(BOTH).profile
	for candidate: Variant in [null, [], 1, {}, Compiler.compile(BOTH), {"modifier_ids": BOTH}]:
		_expect(not Compiler.apply_to_enemy(enemy, candidate).ok, "Non-profile input is rejected")
	for field: String in good:
		var missing: Dictionary = good.duplicate(true)
		missing.erase(field)
		_expect(not Compiler.apply_to_enemy(enemy, missing).ok, "Profile requires field " + field)
	var corruptions: Array[Dictionary] = []
	var bad: Dictionary = good.duplicate(true)
	bad.multipliers.max_health = 100.0
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.multipliers.max_health += 1e-12
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.source.schema_version = 1.0
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.multipliers["damage"] = 1.1
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.source.definition_revision += 1
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.source.catalog = "external"
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.definitions[0].multiplier = 1.5
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.risk_parameters[0].relative_increase = 10.0
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.reward_budget.enabled = true
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.reward_budget.proposed_bonus_fraction = 0.2
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.resource_policy.shield = "scale_with_life"
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad.modifier_ids.reverse()
	corruptions.append(bad)
	bad = good.duplicate(true)
	bad["extra_operation"] = "grant_rewards"
	corruptions.append(bad)
	for profile: Dictionary in corruptions:
		var rejected: Dictionary = Compiler.apply_to_enemy(enemy, profile)
		_expect(not rejected.ok and not rejected.has("enemy") and not rejected.error.is_empty(), "Tampered profile cannot partially apply")
	_expect(Compiler.apply_to_enemy(enemy, good.duplicate(true)).ok, "Exact detached profile copy remains a valid snapshot")
	_expect(enemy == baseline and _frozen(good), "Rejected applications leave all inputs intact")
	_finished = true


func _test_all_templates_and_rarities() -> void:
	var accepted_templates: Dictionary = {}
	var accepted_rarities: Dictionary = {}
	var identity: int = 0
	for template_id: String in Monsters.TEMPLATES:
		for rarity: String in Monsters.RARITIES:
			for context: String in ["ordinary", "death_child", "demo", "level_boss", "map_boss"]:
				for wave: int in [1, 40]:
					identity += 1
					var enemy: Dictionary = Monsters.make_enemy(identity, template_id, wave, Vector2(200, 300), context, rarity)
					if enemy.is_empty():
						_expect(not Compiler.apply_to_enemy(enemy, Compiler.compile(BOTH).profile).ok, "Catalog-rejected rarity/context cannot enter compiler")
						continue
					accepted_templates[template_id] = true
					accepted_rarities[rarity] = true
					var before: Dictionary = enemy.duplicate(true)
					for ids: Array in [[], [BOTH[0]], [BOTH[1]], BOTH]:
						var applied: Dictionary = Compiler.apply_to_enemy(enemy, Compiler.compile(ids).profile)
						_expect(applied.ok, "Every catalog-approved fixture supports every valid selection")
						if not applied.ok:
							continue
						var after: Dictionary = applied.enemy
						_near(after.max_health, float(before.max_health) * (1.20 if BOTH[0] in ids else 1.0), "Maximum health has exactly one challenge multiplier")
						_near(after.health, float(before.health) * (1.20 if BOTH[0] in ids else 1.0), "Fresh spawn remains at full health")
						_near(after.speed, float(before.speed) * (1.10 if BOTH[1] in ids else 1.0), "Only movement speed receives speed challenge")
						_preserved(before, after, template_id + "/" + rarity)
						_expect(_frozen(after.encounter_source) and after.encounter_source.before.max_health == before.max_health, "Frozen marker records canonical baseline")
					_expect(enemy == before, "Canonical generator output remains unchanged across four applications")
		# Default template mechanisms must also be covered; rarity overrides above omit them.
		var context: String = "map_boss" if Monsters.TEMPLATES[template_id].rarity == "boss" else "ordinary"
		var native: Dictionary = Monsters.make_enemy(10000, template_id, 3, Vector2.ZERO, context)
		var transformed: Dictionary = Compiler.apply_to_enemy(native, Compiler.compile(BOTH).profile)
		_expect(transformed.ok, "Native mechanisms compile for " + template_id)
		_preserved(native, transformed.enemy, "Native mechanism fixture " + template_id)
	_expect(accepted_templates.size() == Monsters.TEMPLATES.size(), "Every current template was exercised")
	_expect(accepted_rarities.size() == Monsters.RARITIES.size() - 1 and not accepted_rarities.has("reserved"), "All four valid rarities exercised; reserved stays excluded")
	_finished = true


func _test_resources() -> void:
	var profile: Dictionary = Compiler.compile(BOTH).profile
	for life_ratio: float in [0.0, 0.25, 0.5, 1.0]:
		for shield_ratio: float in [0.0, 0.5, 1.0]:
			var enemy: Dictionary = _base()
			enemy.health *= life_ratio
			enemy.shield *= shield_ratio
			enemy.damage_delay = 3.5
			var after: Dictionary = Compiler.apply_to_enemy(enemy, profile).enemy
			_near(float(after.health) / float(after.max_health), life_ratio, "Current-to-maximum health ratio is preserved")
			_expect(after.shield == enemy.shield and after.max_shield == enemy.max_shield
				and after.shield_regen == enemy.shield_regen and after.damage_delay == 3.5, "Shield amount, cap, regeneration and recharge delay are unchanged")
			_near(float(after.shield) / float(after.max_shield), shield_ratio, "Shield ratio is unchanged without life-based scaling")
	var guard: Dictionary = Monsters.make_enemy(2, "ember_guard", 3, Vector2.ZERO)
	var modified: Dictionary = Compiler.apply_to_enemy(guard, profile).enemy
	_expect(Monsters.contact_components(guard) == Monsters.contact_components(modified), "Typed contact damage is unchanged")
	var hit: Dictionary = Defense.incoming_hit({"physical": 20.0, "fire": 20.0}, modified.defense_stats, modified.shield, modified.health, "monster")
	_expect(hit.ok, "Transformed enemy uses the shared typed defense executor")
	_near(hit.damage_total, 35.0, "25 percent native fire resistance still mitigates exactly five fire damage")
	_near(float(modified.health) - float(hit.remaining_health), 35.0, "Health multiplier is not damage mitigation")
	_expect(modified.shield == 0.0 and modified.max_shield == 0.0, "Zero-shield monster gains no shield")
	var empty: Dictionary = Compiler.apply_to_enemy(guard, Compiler.compile([]).profile).enemy
	empty.erase(Compiler.SOURCE_FIELD)
	_expect(empty == guard, "No-selection result equals canonical enemy after removing provenance")
	var corpse: Dictionary = _base()
	corpse.max_health = 100
	corpse.health = 0
	corpse.speed = 0
	corpse.shield = 0
	corpse.max_shield = 0
	corpse.death_processed = true
	var corpse_before: Dictionary = corpse.duplicate(true)
	corpse.make_read_only()
	for ids: Array in [[], [BOTH[0]], [BOTH[1]], BOTH]:
		var applied: Dictionary = Compiler.apply_to_enemy(corpse, Compiler.compile(ids).profile)
		_expect(applied.ok, "Read-only processed corpse with integer resources is a valid canonical snapshot")
		if not applied.ok:
			continue
		_expect(applied.enemy.health == 0.0 and applied.enemy.speed == 0.0
			and applied.enemy.death_processed, "Application cannot resurrect, start movement or reopen a processed death")
		_near(applied.enemy.max_health, 120.0 if BOTH[0] in ids else 100.0, "Integer maximum health follows the selected multiplier")
		_expect(not applied.enemy.is_read_only() and corpse.is_read_only() and corpse == corpse_before,
			"Read-only caller remains unchanged and returned actor remains mutable")
		_preserved(corpse_before, applied.enemy, "Processed corpse")
	_finished = true


func _test_inputs() -> void:
	var profile: Dictionary = Compiler.compile(BOTH).profile
	for invalid: Variant in [null, [], "crawler", {}, {"health": 10.0, "max_health": 10.0, "speed": 1.0}]:
		_expect(not Compiler.apply_to_enemy(invalid, profile).ok, "Incomplete or wrong-type enemy is rejected")
	for field: String in ["health", "max_health", "shield", "max_shield", "speed"]:
		for value: Variant in [-1.0, INF, -INF, NAN, "5", true, null]:
			var invalid: Dictionary = _base()
			invalid[field] = value
			_expect(not Compiler.apply_to_enemy(invalid, profile).ok, "Non-finite, negative and coerced resources fail: " + field)
	for patch: Dictionary in [{"id": 0}, {"wave": 0}, {"root_id": 0}, {"generation": -1},
		{"template_id": "missing"}, {"rarity": "reserved"}, {"rarity": "boss"}, {"kind": 0},
		{"mechanism_schema": -1}, {"mechanism_revision": 0}, {"mechanism_policy": ""},
		{"reward_eligible": 1}, {"death_processed": "false"}, {"max_health": 0.0},
		{"health": 100000.0}, {"shield": 100000.0}]:
		var invalid: Dictionary = _base()
		invalid.merge(patch, true)
		var before: Dictionary = invalid.duplicate(true)
		_expect(not Compiler.apply_to_enemy(invalid, profile).ok and invalid == before, "Bad identity, provenance or over-cap values fail without mutation")
	var huge: Dictionary = _base()
	huge.max_health = 1.7e308
	huge.health = 1.7e308
	var before: Dictionary = huge.duplicate(true)
	var rejected: Dictionary = Compiler.apply_to_enemy(huge, profile)
	_expect(not rejected.ok and not rejected.has("enemy") and huge == before, "Health multiplication overflow fails atomically")
	for ids: Array in [[], [BOTH[1]]]:
		var applied: Dictionary = Compiler.apply_to_enemy(huge, Compiler.compile(ids).profile)
		_expect(applied.ok, "Large finite life remains valid when the health challenge is absent")
		if applied.ok:
			_expect(applied.enemy.health == huge.health and applied.enemy.max_health == huge.max_health,
				"Unselected life multiplier preserves large finite resources exactly")
	huge = _base()
	huge.speed = 1.7e308
	before = huge.duplicate(true)
	rejected = Compiler.apply_to_enemy(huge, profile)
	_expect(not rejected.ok and not rejected.has("enemy") and huge == before, "Speed multiplication overflow fails atomically")
	for ids: Array in [[], [BOTH[0]]]:
		var applied: Dictionary = Compiler.apply_to_enemy(huge, Compiler.compile(ids).profile)
		_expect(applied.ok, "Large finite speed remains valid when the movement challenge is absent")
		if applied.ok:
			_expect(applied.enemy.speed == huge.speed, "Unselected speed multiplier preserves large finite speed exactly")
	_finished = true


func _test_detachment_and_reentry() -> void:
	var enemy: Dictionary = _base()
	enemy["extension"] = {"tags": ["kept"], "nested": {"value": 7}}
	var before: Dictionary = enemy.duplicate(true)
	var selection: Array = BOTH.duplicate()
	var profile: Dictionary = Compiler.compile(selection).profile
	selection.clear()
	_expect(profile.modifier_ids == BOTH, "Frozen profile does not alias caller selection")
	var first: Dictionary = Compiler.apply_to_enemy(enemy, profile).enemy
	var second: Dictionary = Compiler.apply_to_enemy(enemy, profile).enemy
	first.mechanism_ids.clear()
	first.mechanism_stats.clear()
	first.contact_weights.fire = 99.0
	first.extension.tags.append("changed")
	first.extension.nested.value = 8
	_expect(enemy == before and second == Compiler.apply_to_enemy(enemy, profile).enemy, "Output nested edits cannot affect input or another output")
	_expect(not first.is_read_only() and _frozen(first.encounter_source), "Live actor is mutable while provenance remains frozen")
	for initial_ids: Array in [[], [BOTH[0]], [BOTH[1]], BOTH]:
		var applied: Dictionary = Compiler.apply_to_enemy(enemy, Compiler.compile(initial_ids).profile).enemy
		for next_ids: Array in [[], [BOTH[0]], [BOTH[1]], BOTH]:
			var applied_before: Dictionary = applied.duplicate(true)
			var rejected: Dictionary = Compiler.apply_to_enemy(applied, Compiler.compile(next_ids).profile)
			_expect(not rejected.ok and not rejected.has("enemy") and applied == applied_before, "Every same/different/empty profile reentry fails without mutation")
		_expect(not Compiler.apply_to_enemy(applied.duplicate(true), profile).ok, "Deep-copying an applied enemy cannot bypass provenance guard")
	for marker: Variant in [null, {}, false, "old"]:
		var marked: Dictionary = enemy.duplicate(true)
		marked[Compiler.SOURCE_FIELD] = marker
		_expect(not Compiler.apply_to_enemy(marked, profile).ok, "Marker presence alone rejects even malformed provenance")
	_finished = true


func _test_lineages() -> void:
	var original = Runtime.new()
	var challenged = Runtime.new()
	var profile: Dictionary = Compiler.compile(BOTH).profile
	var left: Dictionary = original.create_root("brood_host", 3, ARENA.get_center())
	var right: Dictionary = Compiler.apply_to_enemy(challenged.create_root("brood_host", 3, ARENA.get_center()), profile).enemy
	var originals: Array[Dictionary] = [left]
	var modified: Array[Dictionary] = [right]
	var total: int = 0
	var rewards: int = 0
	while not originals.is_empty():
		_expect(originals.size() == modified.size(), "Challenge preserves each descendant generation count")
		for index: int in range(originals.size()):
			left = originals[index]
			right = modified[index]
			_preserved(left, right, "Lineage actor")
			left.health = 0.0
			right.health = 0.0
			var outcome: Dictionary = original.process_death(left)
			var changed_outcome: Dictionary = challenged.process_death(right)
			_expect(outcome == changed_outcome and outcome.processed, "Actual death transaction and rewards match baseline")
			rewards += int(changed_outcome.reward)
			total += 1
			_expect(not challenged.process_death(right.duplicate(true)).processed, "Copied corpse cannot create a second death transaction")
			_expect(not Compiler.apply_to_enemy(right, profile).ok, "Death does not clear encounter application guard")
		_expect(original.queue == challenged.queue and original.roots == challenged.roots, "Deferred queue and lineage budgets remain byte-for-byte equivalent values")
		_expect(original.drain(0, ARENA).is_empty() and challenged.drain(0, ARENA).is_empty(), "Full scene budget admits no descendants")
		originals = original.drain(100, ARENA)
		modified.clear()
		for child: Dictionary in challenged.drain(100, ARENA):
			_expect(not child.reward_eligible and child.xp_reward == 0 and child.generation > 0, "Runtime establishes descendant no-reward policy before application")
			var result: Dictionary = Compiler.apply_to_enemy(child, profile)
			_expect(result.ok and not result.enemy.reward_eligible and result.enemy.xp_reward == 0, "Challenge preserves descendant reward and XP suppression")
			modified.append(result.enemy)
	_expect(total == 9 and rewards == 1, "Native brood chain has nine total actors and only one reward-eligible death")
	_expect(original.trace == challenged.trace, "Unmodified runtime trace remains identical")
	_finished = true


func _test_rng() -> void:
	var reference := RandomNumberGenerator.new()
	var exercised := RandomNumberGenerator.new()
	reference.seed = 130021
	exercised.seed = reference.seed
	for index: int in range(100):
		var first: Dictionary = Monsters.ordinary_roll(reference, 1 + index % 20)
		var second: Dictionary = Monsters.ordinary_roll(exercised, 1 + index % 20)
		_expect(first == second, "Challenge cannot alter next ordinary monster roll")
		var enemy: Dictionary = Monsters.make_enemy(index + 1, second.template, 1 + index % 20,
			Vector2.ZERO, "ordinary", second.rarity, second.mechanisms)
		var state_before: int = exercised.state
		var profile: Dictionary = Compiler.compile(BOTH).profile
		var applied: Dictionary = Compiler.apply_to_enemy(enemy, profile)
		_expect(applied.ok and not Compiler.apply_to_enemy(applied.enemy, profile).ok
			and not Compiler.compile(["unknown"]).ok and exercised.state == state_before, "Success and rejection consume no caller RNG")
		var id: String = "gear_%06d" % (index + 1)
		var expected_item: Dictionary = Equipment.generate_current_loot(reference, id, 1 + index % 30)
		var actual_item: Dictionary = Equipment.generate_current_loot(exercised, id, 1 + index % 30)
		_expect(Equipment.validate_instance(expected_item) and Equipment.validate_instance(actual_item), "Loot differential uses valid generated items")
		_expect(expected_item == actual_item, "Current v0.13 natural loot result is unchanged")
		_expect(exercised.state == reference.state, "Current loot leaves exactly the same RNG state")
	for pool: String in Equipment.POOL_PROFILES:
		var state_before: int = exercised.state
		Compiler.apply_to_enemy(_base(), Compiler.compile(BOTH).profile)
		_expect(exercised.state == state_before, "Transform has no random pool selection")
		var expected_item: Dictionary = Equipment.generate_for_pool(reference, "gear_000501", 30, "rare", pool)
		var actual_item: Dictionary = Equipment.generate_for_pool(exercised, "gear_000501", 30, "rare", pool)
		_expect(Equipment.validate_instance(expected_item) and Equipment.validate_instance(actual_item), "Pool differential uses valid generated items: " + pool)
		_expect(expected_item == actual_item and exercised.state == reference.state, "All existing pool rolls and post-roll RNG remain identical: " + pool)
	seed(130022)
	var expected_global: int = randi()
	seed(130022)
	Compiler.compile(BOTH)
	Compiler.compile(["unknown"])
	Compiler.apply_to_enemy(_base(), Compiler.compile(BOTH).profile)
	_expect(randi() == expected_global, "Compilation and application also preserve global RNG")
	_finished = true


func _test_hundred_real_actors() -> void:
	var arena: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.start_density_demo()
	_expect(arena.MAX_ENEMIES == 100 and arena.enemies.size() == 100, "Real scene generates exactly 100 actors through existing runtime")
	var before_roots: Dictionary = arena.monster_runtime.roots.duplicate(true)
	var before_state: Dictionary = arena.state._snapshot().duplicate(true)
	var random_state: int = arena.rng.state
	var profile: Dictionary = Compiler.compile(BOTH).profile
	var positions: Array[Vector2] = []
	var expected_positions: Array[Vector2] = []
	var start: int = Time.get_ticks_usec()
	for index: int in range(arena.enemies.size()):
		var canonical: Dictionary = arena.enemies[index]
		var result: Dictionary = Compiler.apply_to_enemy(canonical, profile)
		_expect(result.ok, "Every real actor accepts the compiled profile")
		if not result.ok:
			continue
		_preserved(canonical, result.enemy, "Real actor %d" % index)
		_expect(not Compiler.apply_to_enemy(result.enemy, profile).ok, "Every one of 100 real actors rejects reentry")
		_near(result.enemy.max_health, float(canonical.max_health) * 1.20, "Real actor has exactly 20 percent more life")
		_near(result.enemy.speed, float(canonical.speed) * 1.10, "Real actor has exactly 10 percent more movement speed")
		arena.enemies[index] = result.enemy
		positions.append(result.enemy.pos)
		expected_positions.append(arena._clamp_to_arena(Vector2(result.enemy.pos)
			+ (arena.player_pos - Vector2(result.enemy.pos)).normalized() * float(result.enemy.speed) * 0.05,
			float(result.enemy.radius)))
	print("Encounter 100-actor apply/reentry/assertion loop: %d usec (diagnostic, not an FPS benchmark)" % (Time.get_ticks_usec() - start))
	_expect(arena.monster_runtime.roots == before_roots and arena.state._snapshot() == before_state
		and arena.rng.state == random_state, "Applying 100 profiles changes no lineage, progression, equipment or RNG state")
	_expect(arena._spawn_monster("crawler").is_empty() and arena.enemies.size() == 100, "Existing admission gate still rejects actor 101")
	arena.hud.close_panel()
	arena.invulnerable = 100.0
	arena._update_enemies(0.05)
	var moved: int = 0
	for index: int in range(arena.enemies.size()):
		var enemy: Dictionary = arena.enemies[index]
		if enemy.pos != positions[index]:
			moved += 1
		_expect(Vector2(enemy.pos).distance_to(expected_positions[index]) < 0.001, "Real AI consumes challenged speed without a second multiplier")
		_expect(not enemy.reward_eligible and enemy.has(Compiler.SOURCE_FIELD), "Real AI keeps demo no-reward flag and encounter marker")
	_expect(moved == 100, "All 100 challenged actors move in the actual scene")
	var target: Dictionary = arena.enemies[2]
	var initial_health: float = target.health
	arena._damage_enemy(target, 10.0, Color.WHITE)
	_near(target.health, initial_health - 10.0, "Actual scene damage consumes challenged health normally")
	_expect(arena.enemies.size() == 100 and arena.state._snapshot() == before_state, "Fixture grants no rewards or map items")
	arena.free()
	_finished = true
