extends SceneTree
## Ordered pool compatibility and new defense vocabulary, independent of scene/UI.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Passives = preload("res://scripts/passive_data.gd")
var checks: int = 0
var failures: int = 0
var golden_samples: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_golden_streams()
	_profiles()
	_defense_samples()
	_current_loot()
	_rejections()
	print("Defense equipment catalog: %d frozen rolls; %d checks, %d failures" % [golden_samples, checks, failures])
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

func _golden_streams() -> void:
	for path: String in ["res://tests/fixtures/typed_affix_legacy_rng.json", "res://tests/fixtures/defense_prior_pools_rng.json"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		if path.ends_with("defense_prior_pools_rng.json"):
			_expect(fixture.source_version == "v0.10.0" and fixture.source_sha256 == "7b9e52356aced11f8809f6c07e4489951e05cd1e272e64d7822e74e3845ae720", "New fixture comes from frozen v0.10 source bytes")
			_expect(str_to_var(fixture.expansion_bases) == Catalog.EXPANSION_BASES and str_to_var(fixture.expansion_affixes) == Catalog.EXPANSION_AFFIXES, "Runewood base and family records remain exactly frozen")
		else:
			_expect(str_to_var(fixture.bases) == Catalog.BASES and str_to_var(fixture.affixes) == Catalog.AFFIXES and str_to_var(fixture.rarities) == Catalog.RARITIES, "All original records and rarity metadata remain exactly frozen")
		for sequence: Dictionary in fixture.sequences:
			var rng := _rng(int(sequence.seed))
			for sample: Dictionary in sequence.samples:
				var expected: Dictionary = sample.instance
				var actual: Dictionary
				match str(sequence.get("method", "generate")):
					"generate_expanded": actual = Catalog.generate_expanded(rng, expected.id, int(expected.item_level), sample.requested_rarity)
					"generate_loot": actual = Catalog.generate_loot(rng, expected.id, int(expected.item_level), sample.requested_rarity)
					_: actual = Catalog.generate(rng, expected.id, int(expected.item_level), sample.requested_rarity)
				_expect(JSON.parse_string(JSON.stringify(actual)) == expected and str(rng.state) == sample.rng_state, "Historical adapter preserves exact item and post-roll RNG state")
				golden_samples += 1
	_expect(golden_samples == 1296, "432 legacy, 432 runewood and 432 mixed frozen samples exercised")

func _profiles() -> void:
	_expect(Catalog.pool_profiles().keys() == ["legacy", "runewood", "defense"], "Ordered profiles are explicit and independent")
	_expect(Catalog.all_base_ids() == Catalog.BASES.keys() + Catalog.EXPANSION_BASES.keys() + ["emberhide_vest"], "Canonical base listing includes every profile exactly once")
	_expect(Catalog.all_affix_ids() == Catalog.AFFIXES.keys() + Catalog.EXPANSION_AFFIXES.keys() + ["emberward"], "Canonical affix listing includes every family exactly once")
	_expect(Catalog.pool_profile("legacy").min_save_version == 4 and Catalog.pool_profile("runewood").min_save_version == 6 and Catalog.pool_profile("defense").min_save_version == 8, "Each vocabulary has an explicit minimum save version")
	var profiles: Dictionary = Catalog.pool_profiles()
	profiles.legacy.base_ids.clear()
	profiles.defense.affix_ids.clear()
	var ids: Array[String] = Catalog.all_base_ids()
	ids.clear()
	var mix: Array[Dictionary] = Catalog.current_loot_profile()
	mix[0].weight = 0
	_expect(Catalog.pool_profile("legacy").base_ids.size() == 6 and Catalog.pool_profile("defense").affix_ids.size() == 9 and Catalog.all_base_ids().size() == 8 and Catalog.current_loot_profile()[0].weight == 60, "Nested metadata/list reads are deeply detached")
	_expect(Catalog.pool_profile("unknown").is_empty() and Catalog.pool_for_base("unknown").is_empty(), "Unknown profiles and bases fail closed")
	var base: Dictionary = Catalog.base_definition("emberhide_vest")
	_expect(base.name == "灰烬皮甲" and base.slot == "armor" and base.size == Vector2i(2, 3) and base.stats == {"max_health": 8.0, "fire_resistance": 0.15}, "Bounded original armor identity and intrinsic stats")
	_expect(Passives.describe_stats(base.stats).contains("火焰抗性 +15") and Passives.describe_stats(base.stats).contains("%"), "Runtime/catalog formatter displays a percent, not a raw fraction")
	for id: String in Catalog.all_base_ids():
		_expect(Catalog.family_eligible("emberward", id) == (id == "emberhide_vest"), "Defense suffix never leaks onto legacy or runewood bases")
	var kinds: Dictionary = {"prefix": 0, "suffix": 0}
	for id: String in Catalog.pool_profile("defense").affix_ids:
		_expect(Catalog.family_eligible(id, "emberhide_vest"), "Every defense pool family is eligible")
		kinds[Catalog.affix_definition(id).kind] += 1
	_expect(kinds == {"prefix": 3, "suffix": 6}, "Three old armor prefixes and six suffixes fill every legal rare count")

func _defense_samples() -> void:
	var rng := _rng(110001)
	var rolls: Dictionary = {}
	var serial: int = 1
	for level: int in [1, 7, 8, 15, 16, 30]:
		for rarity: String in ["normal", "magic", "rare"]:
			var counts: Dictionary = {}
			var tier_seen: Dictionary = {}
			for sample: int in range(300):
				var item: Dictionary = Catalog.generate_for_pool(rng, "gear_%06d" % serial, level, rarity, "defense")
				serial += 1
				_expect(Catalog.validate_instance(item) and item.size() == 5 and item.base_id == "emberhide_vest" and item.rarity == rarity, "Defense generation fulfills the exact requested contract")
				if item.is_empty(): continue
				counts[item.affixes.size()] = true
				var expected_resistance: float = 0.15
				for affix: Dictionary in item.affixes:
					if affix.id != "emberward": continue
					var tier: int = int(affix.tier)
					_expect(level >= [1, 8, 16][tier - 1] and int(affix.value) >= [8, 13, 19][tier - 1] and int(affix.value) <= [12, 18, 25][tier - 1], "Defense tier gate and inclusive integer tick ranges")
					tier_seen[tier] = true
					rolls["%d:%d" % [tier, int(affix.value)]] = true
					expected_resistance += float(affix.value) / 100.0
				_expect(is_equal_approx(Catalog.get_stats(item).fire_resistance, expected_resistance), "Intrinsic and rolled resistance add once as percent fractions")
				_expect(Catalog.validate_instance_for_version(item, 8) and not Catalog.validate_instance(item, true) and not Catalog.validate_instance(item, false), "New runtime vocabulary does not widen either historical boolean validation mode")
			var rules: Dictionary = Catalog.RARITIES[rarity]
			for count: int in range(int(rules.min_affixes), int(rules.max_affixes) + 1):
				_expect(counts.has(count), "Every legal affix count is reachable without rare underfill")
			if rarity != "normal":
				_expect(tier_seen.size() == (1 if level < 8 else (2 if level < 16 else 3)), "All and only unlocked defense tiers appear")
	_expect(rolls.size() == 18, "Every inclusive defense tick in all three tiers is reachable")

func _current_loot() -> void:
	var rng := _rng(110002)
	var mirror := _rng(110002)
	var counts: Dictionary = {"legacy": 0, "runewood": 0, "defense": 0}
	for sample: int in range(6000):
		var roll: int = mirror.randi_range(1, 100)
		var pool_id: String = "legacy" if roll <= 60 else ("runewood" if roll <= 85 else "defense")
		var rarity: String = ["", "normal", "magic", "rare"][sample % 4]
		var id: String = "gear_%06d" % (sample + 1)
		var expected: Dictionary = Catalog.generate_for_pool(mirror, id, 16, rarity, pool_id)
		var actual: Dictionary = Catalog.generate_current_loot(rng, id, 16, rarity)
		_expect(actual == expected and rng.state == mirror.state, "Current natural loot is exactly one 60/25/15 branch followed by its ordered pool")
		counts[Catalog.pool_for_base(actual.base_id)] += 1
	_expect(abs(counts.legacy - 3600) < 180 and abs(counts.runewood - 1500) < 150 and abs(counts.defense - 900) < 120, "Deterministic sample reaches the three authored weight branches at expected frequencies")

func _rejections() -> void:
	var rng := _rng(110003)
	var before: int = rng.state
	for id: String in ["bad", "gear_000000", "gear_1"]:
		_expect(Catalog.generate_for_pool(rng, id, 16, "rare", "defense").is_empty() and Catalog.generate_current_loot(rng, id, 16).is_empty() and rng.state == before, "Invalid identity consumes no RNG")
	for level: int in [0, 31]:
		_expect(Catalog.generate_for_pool(rng, "gear_000001", level, "rare", "defense").is_empty() and Catalog.generate_current_loot(rng, "gear_000001", level).is_empty() and rng.state == before, "Invalid level consumes no RNG")
	_expect(Catalog.generate_for_pool(rng, "gear_000001", 16, "rare", "unknown").is_empty() and Catalog.generate_current_loot(rng, "gear_000001", 16, "unknown").is_empty() and rng.state == before, "Unknown pool and rarity consume no RNG")
	var item: Dictionary = {"id": "gear_000001", "base_id": "emberhide_vest", "rarity": "magic", "item_level": 16, "affixes": [{"id": "emberward", "tier": 3, "value": 25}]}
	_expect(Catalog.validate_instance(item) and is_equal_approx(Catalog.get_stats(item).fire_resistance, 0.4), "Maximum new item fire resistance is 40 percent")
	for version: int in range(1, 8):
		_expect(not Catalog.validate_instance_for_version(item, version), "Older save vocabularies reject new base/affix")
	for id: String in Catalog.BASES.keys() + Catalog.EXPANSION_BASES.keys():
		var bad: Dictionary = item.duplicate(true)
		bad.base_id = id
		_expect(not Catalog.validate_instance(bad), "Forged defense suffix on another base rejects")
	for value: Variant in [null, true, NAN, INF, 18, 26, 19.1]:
		var bad: Dictionary = item.duplicate(true)
		bad.affixes[0].value = value
		_expect(not Catalog.validate_instance(bad), "Malformed/out-of-range/nonintegral defense ticks reject")
	var family: Dictionary = Catalog.affix_definition("emberward")
	for field: String in ["stage", "scope", "actors", "stat", "kind", "unit", "slots", "allowed_base_ids"]:
		var bad: Dictionary = family.duplicate(true)
		bad[field] = "untrusted"
		_expect(not Catalog._valid_defense_family(bad), "Unknown defense semantics fail closed: " + field)
		bad = family.duplicate(true)
		bad.erase(field)
		_expect(not Catalog._valid_defense_family(bad), "Missing defense semantics fail closed: " + field)
	var base: Dictionary = Catalog.base_definition("emberhide_vest")
	for field: String in ["stage", "scope", "actors", "slot", "stats"]:
		for value: Variant in [null, 1, [], {}, "untrusted"]:
			var bad: Dictionary = base.duplicate(true)
			bad[field] = value
			_expect(not Catalog._valid_defense_base(bad), "Malformed base semantics fail closed: " + field)
	for value: Variant in [null, true, NAN, INF, "0.15"]:
		var bad: Dictionary = base.duplicate(true)
		bad.stats.fire_resistance = value
		_expect(not Catalog._valid_defense_base(bad), "Invalid intrinsic fire defense fails shared numeric gate")
	var forged: Dictionary = item.duplicate(true)
	forged.affixes[0].stage = "local_weapon"
	_expect(not Catalog.validate_instance(forged) and Catalog.definition(forged).is_empty(), "Persisted items cannot inject semantic stages")
