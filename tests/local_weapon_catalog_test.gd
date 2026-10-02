extends SceneTree
## Freeze historical RNG contracts; exercise the separately versioned local pool.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Rules = preload("res://scripts/items/weapon_local_rules.gd")
var checks: int = 0
var failures: int = 0
var golden_samples: int = 0
var completed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for test: Callable in [_goldens, _metadata, _samples, _current_loot, _profiles_and_rejections]:
		completed = false
		test.call()
		_expect(completed, "Case completes without exceptions: " + test.get_method())
	print("Local weapon catalog: %d frozen rolls; %d checks, %d failures" % [golden_samples, checks, failures])
	quit(0 if failures == 0 else 1)

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func _goldens() -> void:
	for path: String in ["typed_affix_legacy_rng.json", "defense_prior_pools_rng.json", "local_weapon_prior_pools_rng.json"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + path))
		if path == "local_weapon_prior_pools_rng.json":
			_expect(fixture.source_version == "v0.12.0" and fixture.source_sha256 == "90d85ba8bec97fbc23541a29ca53094cb96961a86a275ba5fdfd7ae4b9e8da9c", "New goldens captured from immutable v0.12 catalog before edits")
			_expect(str_to_var(fixture.defense_bases) == Catalog.DEFENSE_BASES and str_to_var(fixture.defense_affixes) == Catalog.DEFENSE_AFFIXES, "Defense records remain byte-contract-equivalent")
			var old_pools: Dictionary = str_to_var(fixture.pool_profiles)
			for id: String in old_pools:
				_expect(Catalog.pool_profile(id) == old_pools[id], "All historical pool order, membership and version fences remain exact")
			_expect(str_to_var(fixture.loot_profile) == Catalog.loot_profile("v0.11"), "Original 60/25/15 dispatch now has an immutable version ID")
		elif path == "defense_prior_pools_rng.json":
			_expect(str_to_var(fixture.expansion_bases) == Catalog.EXPANSION_BASES and str_to_var(fixture.expansion_affixes) == Catalog.EXPANSION_AFFIXES, "Historical runewood definitions remain exact")
		else:
			_expect(str_to_var(fixture.bases) == Catalog.BASES and str_to_var(fixture.affixes) == Catalog.AFFIXES and str_to_var(fixture.rarities) == Catalog.RARITIES, "All legacy records remain exact")
		for sequence: Dictionary in fixture.sequences:
			var rng := _rng(int(sequence.seed))
			for sample: Dictionary in sequence.samples:
				var expected: Dictionary = sample.instance
				var actual: Dictionary
				match str(sequence.get("method", "generate")):
					"generate_expanded": actual = Catalog.generate_expanded(rng, expected.id, int(expected.item_level), sample.requested_rarity)
					"generate_loot": actual = Catalog.generate_loot(rng, expected.id, int(expected.item_level), sample.requested_rarity)
					"generate_current_loot": actual = Catalog.generate_loot_profile(rng, expected.id, int(expected.item_level), sample.requested_rarity, "v0.11")
					"generate_for_pool": actual = Catalog.generate_for_pool(rng, expected.id, int(expected.item_level), sample.requested_rarity, "defense")
					_: actual = Catalog.generate(rng, expected.id, int(expected.item_level), sample.requested_rarity)
				_expect(JSON.parse_string(JSON.stringify(actual)) == expected and str(rng.state) == sample.rng_state, "Historical adapter preserves exact output and post-item RNG state")
				golden_samples += 1
	_expect(golden_samples == 2160, "Five historical stream contracts each exercise 432 frozen items")
	completed = true

func _metadata() -> void:
	_expect(Catalog.CURRENT_VOCABULARY == 9 and Catalog.CURRENT_LOOT_PROFILE_ID == "v0.13", "Current vocabulary and explicitly named dispatch advance together")
	_expect(Catalog.all_base_ids().size() == 9 and Catalog.all_affix_ids().size() == 19, "Exactly one local base and two local families join canonical listing")
	_expect(Catalog.pool_profile("local_weapon").min_save_version == 9 and Catalog.pool_profile("local_weapon").balance_origin == "original", "Local vocabulary fence and original numerical origin are explicit")
	var base: Dictionary = Catalog.base_definition("ashwood_bow")
	_expect(base.name == "白蜡长弓" and base.slot == "weapon" and base.size == Vector2i(2, 3) and base.stats.is_empty(), "Bow has agreed footprint and no global scalar intrinsic stats")
	_expect(Catalog._valid_local_weapon_base(base, "ashwood_bow"), "Authored local base passes semantic gate")
	var kinds: Dictionary = {"prefix":0, "suffix":0}
	for id: String in Catalog.pool_profile("local_weapon").affix_ids:
		_expect(Catalog.family_eligible(id, "ashwood_bow"), "Every local pool member is eligible")
		kinds[Catalog.affix_definition(id).kind] += 1
	_expect(kinds == {"prefix":6, "suffix":5}, "Six prefixes and five suffixes support all rare counts with shared prefix opportunity cost")
	for id: String in Catalog.LOCAL_WEAPON_AFFIXES:
		var family: Dictionary = Catalog.affix_definition(id)
		_expect(Catalog._valid_local_weapon_family(family) and family.stage == "weapon_local" and family.scope == "equipped_weapon" and family.kind == "prefix" and family.balance_origin == "original", "Local family scope, prefix cost and original balance metadata")
		for base_id: String in Catalog.all_base_ids():
			_expect(Catalog.family_eligible(id, base_id) == (base_id == "ashwood_bow"), "Local family cannot affect any old base")
		for tier: int in range(3):
			_expect(family.tiers[tier].tier == tier + 1 and family.tiers[tier].level == [1,8,16][tier] and family.tiers[tier].weight == [100,60,30][tier], "Original tier gates and weights are explicit")
		family.tiers[0].min = 999
		family.allowed_base_ids.clear()
		_expect(Catalog.affix_definition(id).tiers[0].min != 999 and Catalog.affix_definition(id).allowed_base_ids == ["ashwood_bow"], "Family metadata is deeply detached")
	var profiles: Dictionary = Catalog.loot_profiles()
	profiles["v0.11"][0].weight = 0
	var current: Array[Dictionary] = Catalog.current_loot_profile()
	current[0].weight = 0
	_expect(Catalog.loot_profile("v0.11")[0].weight == 60 and Catalog.current_loot_profile()[0].weight == 45, "Versioned loot profile reads are deeply detached")
	_expect(Catalog.loot_profile("unknown").is_empty(), "Unknown profile lookup fails closed")
	completed = true

func _samples() -> void:
	var rng := _rng(130001)
	var serial: int = 1
	var seen_values: Dictionary = {}
	for level: int in [1,7,8,15,16,30]:
		for rarity: String in ["normal","magic","rare"]:
			var seen_counts: Dictionary = {}
			var seen_tiers: Dictionary = {}
			for sample: int in range(250):
				var item: Dictionary = Catalog.generate_for_pool(rng, "gear_%06d" % serial, level, rarity, "local_weapon")
				serial += 1
				_expect(Catalog.validate_instance(item) and item.size() == 5 and item.base_id == "ashwood_bow" and item.rarity == rarity, "Local generator fulfills exact five-field request")
				if item.is_empty(): continue
				seen_counts[item.affixes.size()] = true
				var kinds: Dictionary = {"prefix":0,"suffix":0}
				var groups: Dictionary = {}
				var expected_flat: float = 0.0
				var expected_increased: float = 0.0
				for affix: Dictionary in item.affixes:
					var family: Dictionary = Catalog.affix_definition(affix.id)
					var tier: Dictionary = family.tiers[int(affix.tier) - 1]
					_expect(not groups.has(family.group) and level >= int(tier.level) and affix.value >= tier.min and affix.value <= tier.max, "All rolls obey group exclusivity, tier gates and inclusive integer ticks")
					groups[family.group] = true
					kinds[family.kind] += 1
					if not Catalog.LOCAL_WEAPON_AFFIXES.has(affix.id): continue
					seen_tiers[affix.tier] = true
					seen_values["%s:%d:%d" % [affix.id, affix.tier, affix.value]] = true
					if family.unit == "flat": expected_flat += float(affix.value)
					else: expected_increased += float(affix.value) / 100.0
				var rarity_rules: Dictionary = Catalog.RARITIES[rarity]
				_expect(kinds.prefix <= rarity_rules.max_prefixes and kinds.suffix <= rarity_rules.max_suffixes, "Local prefixes consume the ordinary rarity prefix cap")
				var profile: Dictionary = Catalog.weapon_profile(item)
				var resolved: Dictionary = Rules.resolve(profile)
				_expect(resolved.ok and profile.flat.physical == expected_flat and profile.increased.physical == expected_increased and is_equal_approx(resolved.components.physical, (float(Rules.BASE_PHYSICAL_BY_ID.ashwood_bow) + expected_flat) * (1.0 + expected_increased)), "Actual rolled profile resolves exactly one local physical stage")
				var stats: Dictionary = Catalog.get_stats(item)
				_expect(not stats.has("weapon_added_physical") and not stats.has("weapon_physical_increased") and not stats.has("damage"), "Local stats and intrinsic weapon base never leak into character modifiers")
				_expect(Catalog.validate_instance_for_version(item, 9) and not Catalog.validate_instance_for_version(item, 8), "Vocabulary9 alone admits new bow")
			for count: int in range(Catalog.RARITIES[rarity].min_affixes, Catalog.RARITIES[rarity].max_affixes + 1):
				_expect(seen_counts.has(count), "Every legal rarity affix count is reachable")
			if rarity != "normal":
				_expect(seen_tiers.size() == (1 if level < 8 else (2 if level < 16 else 3)), "All and only unlocked local tiers appear")
	for id: String in Catalog.LOCAL_WEAPON_AFFIXES:
		for tier: Dictionary in Catalog.LOCAL_WEAPON_AFFIXES[id].tiers:
			for value: int in range(tier.min, tier.max + 1):
				_expect(seen_values.has("%s:%d:%d" % [id, tier.tier, value]), "Every authored local tick is reachable")
	completed = true

func _current_loot() -> void:
	var rng := _rng(130002)
	var mirror := _rng(130002)
	var counts: Dictionary = {"legacy":0,"runewood":0,"defense":0,"local_weapon":0}
	for sample: int in range(4000):
		var roll: int = mirror.randi_range(1,100)
		var pool_id: String = "legacy" if roll <= 45 else ("runewood" if roll <= 70 else ("defense" if roll <= 85 else "local_weapon"))
		var id: String = "gear_%06d" % (sample + 1)
		var rarity: String = ["", "normal", "magic", "rare"][sample % 4]
		var expected: Dictionary = Catalog.generate_for_pool(mirror, id, 16, rarity, pool_id)
		var actual: Dictionary = Catalog.generate_current_loot(rng, id, 16, rarity)
		_expect(actual == expected and rng.state == mirror.state, "Current loot is exactly one 45/25/15/15 branch before the selected pool")
		counts[Catalog.pool_for_base(actual.base_id)] += 1
	_expect(abs(counts.legacy - 1800) < 180 and abs(counts.runewood - 1000) < 150 and abs(counts.defense - 600) < 120 and abs(counts.local_weapon - 600) < 120, "All four current branches occur at authored frequencies")
	completed = true

func _profiles_and_rejections() -> void:
	var normal: Dictionary = {"id":"gear_000001","base_id":"ashwood_bow","rarity":"normal","item_level":1,"affixes":[]}
	var definition: Dictionary = Catalog.definition(normal)
	_expect(definition.weapon_profile.size() == 7 and definition.weapon_damage == {"physical": Rules.BASE_PHYSICAL_BY_ID.ashwood_bow} and definition.stats.is_empty() and definition.effects.is_empty(), "Normal bow exposes intrinsic local damage without global stats or effects")
	_expect(definition.weapon_damage_summary.contains("本武器") and definition.weapon_damage_summary.contains("仅普攻与龙卷箭体"), "Local panel summary names the exact supported attacks")
	definition.weapon_profile.base.physical = 999.0
	definition.weapon_damage.physical = 999.0
	_expect(Catalog.definition(normal).weapon_damage.physical == Rules.BASE_PHYSICAL_BY_ID.ashwood_bow, "Definition profile and resolved panel are detached")
	var rare: Dictionary = normal.duplicate(true)
	rare.rarity = "rare"
	rare.item_level = 16
	rare.affixes = [{"id":"whetstone_edge","tier":3,"value":Catalog.LOCAL_WEAPON_AFFIXES.whetstone_edge.tiers[2].max}, {"id":"tempered_edge","tier":3,"value":Catalog.LOCAL_WEAPON_AFFIXES.tempered_edge.tiers[2].max}, {"id":"farweave","tier":3,"value":18}, {"id":"coalglow","tier":3,"value":20}]
	_expect(Catalog.validate_instance(rare) and Catalog.definition(rare).affix_lines[0].contains("本武器") and Catalog.definition(rare).affix_lines[1].contains("本武器"), "Two local prefixes share a legal rare with an ordinary third prefix")
	for base_id: String in Catalog.all_base_ids():
		if base_id == "ashwood_bow": continue
		var forged: Dictionary = rare.duplicate(true)
		forged.base_id = base_id
		_expect(not Catalog.validate_instance(forged) and Catalog.weapon_profile(forged).is_empty(), "Forged local affixes on any old base fail closed")
	for version: int in range(1,9):
		_expect(not Catalog.validate_instance_for_version(normal, version), "New base is fenced out of all older save vocabularies")
	for id: String in Catalog.LOCAL_WEAPON_AFFIXES:
		var family: Dictionary = Catalog.affix_definition(id)
		for field: String in ["stage","scope","stat","kind","unit","slots","allowed_base_ids","damage_type"]:
			for value: Variant in [null, true, 999, {}, [], "unknown"]:
				var bad: Dictionary = family.duplicate(true)
				bad[field] = value
				_expect(not Catalog._valid_local_weapon_family(bad), "Malformed local family metadata fails closed")
	var old: Dictionary = normal.duplicate(true)
	old.base_id = "cinder_reed"
	_expect(Catalog.weapon_profile(old).is_empty() and not Catalog.definition(old).has("weapon_profile") and Catalog.get_stats(old).damage == 3.0, "Old scalar damage retains old definition shape and meaning")
	var rng := _rng(130003)
	var before: int = rng.state
	_expect(Catalog.generate_loot_profile(rng, normal.id, 16, "rare", "unknown").is_empty() and rng.state == before, "Unknown loot version rejects before RNG")
	for args: Array in [["bad",16,"rare"],[normal.id,0,"rare"],[normal.id,31,"rare"],[normal.id,16,"unknown"]]:
		_expect(Catalog.generate_for_pool(rng,args[0],args[1],args[2],"local_weapon").is_empty() and Catalog.generate_loot_profile(rng,args[0],args[1],args[2],"v0.13").is_empty() and rng.state == before, "Invalid local request consumes no RNG")
	completed = true
