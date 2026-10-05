extends SceneTree
## Focused vocabulary34 proof; no UI, persistence, combat replay or broad suite.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Profile = preload("res://scripts/items/forgeblade_profile.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Expand = preload("res://scripts/items/crafting_expansion_rules.gd")
const Targeted = preload("res://scripts/items/targeted_reforge_rules.gd")
const Old = preload("res://tests/fixtures/v055/equipment_catalog_v054.gd")
const OldCraft = preload("res://tests/fixtures/v055/crafting_rules_v054.gd")
const LEVELS: Array[int] = [1, 7, 8, 15, 16, 30]
const SEEDS: Array[int] = [0, 1, 4927, -817, 550034]
var checks: int = 0
var failures: int = 0
var old_rolls: int = 0
var old_crafts: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_metadata, _all_family_combinations, _tier_boundaries_and_invalid_instances, _generation_and_profiles, _crafting, _frozen_v054]:
		completed = false
		test.call()
		_expect(completed, "Case completes without exceptions: " + test.get_method())
	print("Forgeblade catalog/crafting: %d checks, %d failures; %d old item+RNG byte comparisons, %d old craft plans" % [checks, failures, old_rolls, old_crafts])
	quit(0 if failures == 0 else 1)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _item(rarity: String = "normal", level: int = 16, ids: Array = [], tier: int = 1, maximum: bool = false, base_id: String = "forgeblade") -> Dictionary:
	var affixes: Array = []
	for id: String in ids:
		var definition: Dictionary = Catalog.affix_definition(id).tiers[tier - 1]
		affixes.append({"id": id, "tier": tier, "value": int(definition.max if maximum else definition.min)})
	return {"id": "gear_000551", "base_id": base_id, "rarity": rarity, "item_level": level, "affixes": affixes}


func _same(actual: Variant, expected: Variant, label: String) -> void:
	_expect(var_to_bytes(actual) == var_to_bytes(expected), label)


func _metadata() -> void:
	_expect(Catalog.CURRENT_VOCABULARY == 34 and Catalog.CANONICAL_LOOT_PROFILE_ID == "canonical_v34" and Catalog.CURRENT_LOOT_PROFILE_ID == "canonical_v34", "Explicit vocabulary and both current natural dispatch selectors are34")
	_expect(Catalog.all_base_ids().size() == Old.all_base_ids().size() + 1 and Catalog.all_affix_ids() == Old.all_affix_ids(), "Exactly one base; no duplicate/new affix identities")
	var base: Dictionary = Catalog.base_definition("forgeblade")
	_expect(base.name == "锻纹短刃" and base.size == Vector2i(1, 3) and base.slot == "weapon" and base.stats.is_empty(), "One-by-three short blade has no global intrinsic stats")
	_expect(Catalog._valid_local_weapon_base(base, "forgeblade"), "New local base uses the authoritative weapon physical metadata")
	_expect(Catalog.pool_for_base("forgeblade") == "forgeblade_v34" and Catalog.current_pool_for_base("forgeblade") == "forgeblade_v34", "Every base-to-pool lookup agrees")
	_same(Catalog.pool_profile("forgeblade_v34"), Profile.POOL_PROFILE, "Versioned six-family profile is authoritative")
	for id: String in Catalog.all_affix_ids():
		_expect(Catalog.family_eligible(id, "forgeblade") == Profile.POOL_PROFILE.affix_ids.has(id), "Exactly six eligible families: " + id)
		var family: Dictionary = Catalog.affix_definition(id)
		var old_family: Dictionary = Old.affix_definition(id)
		_same(family.tiers, old_family.tiers, "All original family budgets, weights and tier gates remain frozen: " + id)
		for old_base: String in Old.all_base_ids():
			_expect(Catalog.family_eligible(id, old_base) == Old.family_eligible(id, old_base), "No old base gains or loses eligibility: " + id + ":" + old_base)
		if Profile.LOCAL_AFFIX_IDS.has(id) or Profile.CRITICAL_AFFIX_IDS.has(id):
			_expect(family.allowed_base_ids.has("forgeblade") and family.slots.has("weapon"), "Expanded public family metadata agrees with runtime eligibility: " + id)
			family.allowed_base_ids.erase("forgeblade")
			if Profile.CRITICAL_AFFIX_IDS.has(id): family.slots.erase("weapon")
		_same(family, old_family, "Only four explicit eligibility allowlists change: " + id)
	for id: String in Profile.LOCAL_AFFIX_IDS:
		_expect(Catalog._valid_local_weapon_family(Catalog.affix_definition(id)) and Catalog._valid_local_weapon_family(Catalog.LOCAL_WEAPON_AFFIXES[id]), "Both frozen and extended local metadata remain semantically valid")
	_same(Catalog.LOCAL_WEAPON_AFFIXES, Old.LOCAL_WEAPON_AFFIXES, "Raw local budgets and old allowlist are frozen")
	_same(Catalog.BuildAffixes.AFFIXES, Old.BuildAffixes.AFFIXES, "Raw crit/leech profile is frozen")
	completed = true


func _all_family_combinations() -> void:
	for level: int in LEVELS:
		var counts: Dictionary = {"normal": {}, "magic": {}, "rare": {}}
		for mask: int in range(64):
			var ids: Array = []
			var prefixes: int = 0
			var suffixes: int = 0
			for index: int in range(6):
				if mask & (1 << index):
					ids.append(Profile.POOL_PROFILE.affix_ids[index])
					if index < 3: prefixes += 1
					else: suffixes += 1
			for rarity: String in ["normal", "magic", "rare"]:
				var expected: bool = ids.is_empty() if rarity == "normal" else (ids.size() >= 1 and ids.size() <= 2 and prefixes <= 1 and suffixes <= 1 if rarity == "magic" else ids.size() >= 4 and ids.size() <= 6 and prefixes <= 3 and suffixes <= 3)
				var item: Dictionary = _item(rarity, level, ids)
				_expect(Catalog.validate_instance(item) == expected, "Exhaustive actual-instance family mask/rarity legality: %d/%s/ilvl%d" % [mask, rarity, level])
				if expected:
					counts[rarity][ids.size()] = int(counts[rarity].get(ids.size(), 0)) + 1
					if level in [1, 8, 16]: _all_tier_assignments(item, 1 if level == 1 else (2 if level == 8 else 3))
		_same(counts, {"normal": {0: 1}, "magic": {1: 6, 2: 9}, "rare": {4: 15, 5: 6, 6: 1}}, "All legal family combination counts at ilvl%d" % level)
	completed = true


func _all_tier_assignments(source: Dictionary, unlocked: int) -> void:
	var permutations: int = int(pow(unlocked, source.affixes.size()))
	for encoded: int in range(permutations):
		var item: Dictionary = source.duplicate(true)
		var remaining: int = encoded
		for affix: Dictionary in item.affixes:
			affix.tier = remaining % unlocked + 1
			remaining = int(remaining / unlocked)
			affix.value = Catalog.affix_definition(affix.id).tiers[affix.tier - 1].min
		_expect(Catalog.validate_instance(item), "Every legal mixed-tier assignment validates; at most3402 rare assignments per gate")


func _tier_boundaries_and_invalid_instances() -> void:
	for id: String in Profile.POOL_PROFILE.affix_ids:
		for tier: int in range(1, 4):
			var rule: Dictionary = Catalog.affix_definition(id).tiers[tier - 1]
			_expect(rule.level == [1, 8, 16][tier - 1] and rule.weight == [100, 60, 30][tier - 1], "Uniform existing tier gate and weight")
			for level: int in LEVELS:
				for maximum: bool in [false, true]:
					var item: Dictionary = _item("magic", level, [id], tier, maximum)
					_expect(Catalog.validate_instance(item) == (level >= rule.level), "Inclusive tier endpoints and exact ilvl gates")
			for bad_value: Variant in [int(rule.min) - 1, int(rule.max) + 1, true, 1.5, "1", null]:
				var invalid: Dictionary = _item("magic", 30, [id], tier)
				invalid.affixes[0].value = bad_value
				_expect(not Catalog.validate_instance(invalid), "Invalid rolled ticks fail closed")
	var normal: Dictionary = _item()
	for version: int in range(1, 34):
		_expect(not Catalog.validate_instance_for_version(normal, version), "Every old vocabulary rejects the new base including33")
	for forbidden: String in ["runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread", "beatlink", "attack_life_leech", "attack_mana_leech"]:
		_expect(not Catalog.validate_instance(_item("magic", 16, [forbidden])), "Actual otherwise legal magic instance rejects off-pool family: " + forbidden)
	var duplicated: Dictionary = _item("rare", 16, ["whetstone_edge", "tempered_edge", "wellturn", "global_critical_chance"])
	duplicated.affixes[1] = duplicated.affixes[0].duplicate(true)
	duplicated.affixes[1].tier = 3
	duplicated.affixes[1].value = 6
	_expect(not Catalog.validate_instance(duplicated), "Real rare instance rejects repeated family/group across tiers")
	_expect(not Catalog.validate_instance(_item("magic", 16, Profile.LOCAL_AFFIX_IDS)), "Two local prefixes cannot form a legal magic item")
	var invalid_count: Dictionary = _item("rare", 16, ["whetstone_edge", "tempered_edge", "deepwell", "wellturn"])
	invalid_count.affixes.append({"id": "whetstone_edge", "tier": 2, "value": 3})
	_expect(not Catalog.validate_instance(invalid_count), "Four-prefix real rare instance fails both cap and same-group exclusivity")
	for field: String in ["stage", "scope", "stat", "kind", "unit", "slots", "allowed_base_ids", "damage_type"]:
		for value: Variant in [null, true, 99, {}, [], "unknown"]:
			var malformed: Dictionary = Catalog.affix_definition("whetstone_edge")
			malformed[field] = value
			_expect(not Catalog._valid_local_weapon_family(malformed), "Malformed extended metadata rejects: " + field)
	completed = true


func _generation_and_profiles() -> void:
	var rng := _rng(550034)
	for level: int in LEVELS:
		var unlocked: int = 1 if level < 8 else (2 if level < 16 else 3)
		var tiers: Dictionary = {}
		for rarity: String in ["normal", "magic", "rare"]:
			var counts: Dictionary = {}
			for sample: int in range(60):
				var item: Dictionary = Catalog.generate_for_pool(rng, "gear_000551", level, rarity, "forgeblade_v34")
				_expect(Catalog.validate_instance(item) and item.size() == 5 and item.base_id == "forgeblade" and item.rarity == rarity, "New pool generator always returns canonical legal item")
				if item.is_empty(): continue
				counts[item.affixes.size()] = true
				for affix: Dictionary in item.affixes:
					tiers[affix.tier] = true
					_expect(int(affix.tier) <= unlocked, "Natural roll respects tier boundary")
			var limits: Dictionary = Catalog.RARITIES[rarity]
			for count: int in range(limits.min_affixes, limits.max_affixes + 1):
				_expect(counts.has(count), "Natural generation witnesses every legal affix count")
		_expect(tiers.size() == unlocked, "All and only unlocked tiers reached")
	var normal: Dictionary = _item()
	var full: Dictionary = _item("rare", 16, Profile.POOL_PROFILE.affix_ids, 3, true)
	var before: PackedByteArray = var_to_bytes(full)
	var definition: Dictionary = Catalog.definition(full)
	_expect(Catalog.weapon_profile(normal).size() == 7 and Catalog.definition(normal).weapon_damage.physical == 4.0, "White blade derives seven-field profile and physical4")
	_expect(definition.weapon_profile.size() == 7 and definition.weapon_damage.physical == 13.0 and definition.weapon_profile.sources.size() == 2, "T3 legal six-family rare derives W13 once from exactly two local sources")
	_expect(definition.stats == {"max_mana": 22.0, "mana_regen_increased": 0.14, "crit_chance_increased": 0.4, "crit_multiplier_add": 0.15}, "Only resource and global crit affixes enter character stats")
	_expect(definition.weapon_damage_summary.ends_with("仅裂刃斩直接命中") and not definition.weapon_damage_summary.contains("普攻"), "Short blade summary names its real local consumer")
	_same(full, bytes_to_var(before), "Definition and profile readers are pure")
	definition.weapon_profile.base.physical = 999.0
	definition.weapon_damage.physical = 999.0
	_expect(Catalog.definition(full).weapon_damage.physical == 13.0, "Derived profile and panel are detached")
	var detached: Dictionary = Catalog.affix_definition("global_critical_chance")
	detached.allowed_base_ids.clear()
	detached.tiers[0].min = 999
	_expect(Catalog.family_eligible("global_critical_chance", "forgeblade") and Catalog.affix_definition("global_critical_chance").tiers[0].min == 15, "Current extended metadata is deeply detached")
	var expected_weights: Array = [25, 20, 10, 10, 30, 5]
	var profile: Array[Dictionary] = Catalog.current_loot_profile()
	for i: int in range(profile.size()): _expect(profile[i].weight == expected_weights[i], "Authored canonical34 distribution")
	var mirror := _rng(550035)
	rng = _rng(550035)
	var observed: Dictionary = {}
	for i: int in range(240):
		var roll: int = mirror.randi_range(1, 100)
		var pool_id: String = ""
		for entry: Dictionary in profile:
			roll -= entry.weight
			if roll <= 0: pool_id = entry.pool_id; break
		var expected: Dictionary = Catalog.generate_for_pool(mirror, "gear_000551", 16, "", pool_id)
		var actual: Dictionary = Catalog.generate_current_loot(rng, "gear_000551", 16)
		_same(actual, expected, "Current natural profile makes precisely one authored pool roll")
		_expect(rng.state == mirror.state, "Current profile post-roll RNG exact")
		observed[pool_id] = true
	_expect(observed.size() == 6 and observed.has("forgeblade_v34"), "New natural dispatch reaches all six pools")
	var saved_rng: int = rng.state
	for args: Array in [["bad",16,"rare"],["gear_000551",0,"rare"],["gear_000551",31,"rare"],["gear_000551",16,"unknown"]]:
		_expect(Catalog.generate_for_pool(rng, args[0], args[1], args[2], "forgeblade_v34").is_empty() and rng.state == saved_rng, "Invalid new request consumes no RNG")
	completed = true


func _crafting() -> void:
	for level: int in LEVELS:
		var normal: Dictionary = _item("normal", level)
		var magic: Dictionary = _item("magic", level, ["whetstone_edge"])
		var saturated_magic: Dictionary = _item("magic", level, ["whetstone_edge", "wellturn"])
		var rare: Dictionary = _item("rare", level, ["whetstone_edge", "tempered_edge", "wellturn", "global_critical_chance"])
		for source: Dictionary in [normal, magic, saturated_magic, rare]:
			for operation: String in Craft.operation_ids():
				var before: PackedByteArray = var_to_bytes(source)
				var quoted: Dictionary = Craft.operation_quote(source, operation)
				for seed_value: int in SEEDS:
					seed(551991)
					var global_next: int = randi()
					seed(551991)
					var planned: Dictionary = Craft.operation_plan(source, operation, seed_value)
					_expect(randi() == global_next and var_to_bytes(source) == before, "Pure craft leaves global RNG and source untouched")
					_expect(planned.ok == quoted.ok, "Quote availability agrees with execution")
					if not planned.ok: continue
					_same(planned.cost, quoted.cost, "Existing quote cost exactly matches plan")
					if operation == "salvage": continue
					_expect(Catalog.validate_instance(planned.instance) and planned.instance.id == source.id and planned.instance.base_id == source.base_id and planned.instance.item_level == source.item_level, "Every existing craft preserves identity and produces legal current item")
					if operation == "targeted_reforge_damage":
						_expect(Profile.LOCAL_AFFIX_IDS.has(planned.instance.affixes[0].id), "Damage target guarantees one of exactly two local families")
					if operation == "targeted_reforge_critical":
						_expect(Profile.CRITICAL_AFFIX_IDS.has(planned.instance.affixes[0].id), "Critical target guarantees existing global crit family")
		for operation: String in ["targeted_reforge_life_leech", "targeted_reforge_mana_leech"]:
			for source: Dictionary in [magic, rare]:
				var refused: Dictionary = Craft.operation_plan(source, operation, "unused-invalid-seed")
				_expect(not refused.ok and refused.code == "no_legal_target" and refused.cost.is_empty() and refused.instance.is_empty(), "Leech target disabled before seed validation or cost")
		_expect(not Craft.operation_quote(saturated_magic, "augment").ok, "Saturated magic cannot add a third affix")
		var pool: Array[Dictionary] = Expand._pool("forgeblade", level, [])
		for operation: String in ["targeted_reforge_damage", "targeted_reforge_critical"]:
			var actual: Array[String] = []
			for entry: Dictionary in Targeted._target_pool(pool, operation):
				if not actual.has(entry.id): actual.append(entry.id)
			_expect(actual == (Profile.LOCAL_AFFIX_IDS if operation == "targeted_reforge_damage" else Profile.CRITICAL_AFFIX_IDS), "Target candidate families exactly match effective pool")
	completed = true


func _frozen_v054() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v055/oracle_manifest.json"))
	_expect(manifest.baseline_commit == "5e442d98e82b248efc3a553fdf9bf95733929096", "Oracle comes from exact v54 baseline")
	for file: Dictionary in manifest.files:
		_expect(FileAccess.get_sha256("res://" + file.fixture) == file.fixture_sha256, "Frozen independent oracle source hash: " + file.fixture)
	for pool_id: String in Old.POOL_PROFILES:
		_same(Catalog.pool_profile(pool_id), Old.pool_profile(pool_id), "Old pool membership/order/metadata bytes unchanged: " + pool_id)
	for profile_id: String in Old.LOOT_PROFILES:
		_same(Catalog.loot_profile(profile_id), Old.loot_profile(profile_id), "Old named loot dispatch unchanged: " + profile_id)
	for method: String in ["pool", "loot", "generate", "generate_expanded", "generate_loot"]:
		var profiles: Array = Old.POOL_PROFILES.keys() if method == "pool" else (Old.LOOT_PROFILES.keys() if method == "loot" else [""])
		for profile_id: String in profiles:
			for seed_value: int in SEEDS:
				var a := _rng(seed_value)
				var b := _rng(seed_value)
				for level: int in LEVELS:
					for rarity: String in ["", "normal", "magic", "rare"]:
						var actual: Dictionary
						var expected: Dictionary
						if method == "pool":
							actual = Catalog.generate_for_pool(a, "gear_000551", level, rarity, profile_id)
							expected = Old.generate_for_pool(b, "gear_000551", level, rarity, profile_id)
						elif method == "loot":
							actual = Catalog.generate_loot_profile(a, "gear_000551", level, rarity, profile_id)
							expected = Old.generate_loot_profile(b, "gear_000551", level, rarity, profile_id)
						elif method == "generate":
							actual = Catalog.generate(a, "gear_000551", level, rarity)
							expected = Old.generate(b, "gear_000551", level, rarity)
						elif method == "generate_expanded":
							actual = Catalog.generate_expanded(a, "gear_000551", level, rarity)
							expected = Old.generate_expanded(b, "gear_000551", level, rarity)
						else:
							actual = Catalog.generate_loot(a, "gear_000551", level, rarity)
							expected = Old.generate_loot(b, "gear_000551", level, rarity)
						_same(actual, expected, "Frozen v54 exact item bytes: " + method + ":" + profile_id)
						_expect(a.state == b.state, "Frozen v54 exact caller RNG state")
						_same(Catalog.definition(actual), Old.definition(expected), "Old full definition and bow summary bytes unchanged")
						old_rolls += 1
	for base_id: String in Old.all_base_ids():
		for level: int in [1, 16]:
			var normal: Dictionary = _item("normal", level, [], 1, false, base_id)
			var magic: Dictionary = OldCraft.operation_plan(normal, "enchant", 4927).instance
			var rare: Dictionary = OldCraft.operation_plan(magic, "elevate", -817).instance
			for source: Dictionary in [normal, magic, rare]:
				for operation: String in OldCraft.operation_ids():
					_same(Craft.operation_metadata(operation), OldCraft.operation_metadata(operation), "Old operation metadata frozen")
					_expect(Craft.seed_rules_version(operation) == OldCraft.seed_rules_version(operation), "Old operation seed rules remain unchanged")
					_same(Craft.operation_quote(source, operation), OldCraft.operation_quote(source, operation), "Old base quote bytes unchanged")
					for seed_value: int in [0, 4927, -817]:
						seed(552001)
						var global_next: int = randi()
						seed(552001)
						var actual: Dictionary = Craft.operation_plan(source, operation, seed_value)
						_expect(randi() == global_next, "Old craft does not consume caller global RNG")
						_same(actual, OldCraft.operation_plan(source, operation, seed_value), "Old base six-craft and targeted plan bytes unchanged")
						old_crafts += 1
	completed = true
