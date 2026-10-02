extends SceneTree
## Isolated catalog contract: no save paths, combat state, or runtime item grants.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const LEVELS: Array[int] = [1, 7, 8, 15, 16, 30]
const EXPANDED_SAMPLES_PER_COMBINATION: int = 1000
const LOOT_SAMPLES: int = 12000
const GOLDEN_PATH: String = "res://tests/fixtures/typed_affix_legacy_rng.json"
const EXPECTED_ADDITIONS: Dictionary = {
	"attack_added_physical": ["attack", "physical"], "attack_added_fire": ["attack", "fire"],
	"spell_added_cold": ["spell", "cold"], "spell_added_lightning": ["spell", "lightning"],
}
var checks: int = 0
var failures: int = 0
var expanded_samples: int = 0
var loot_samples: int = 0
var legacy_samples: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_legacy_golden()
	_check_definitions()
	_check_expanded_samples()
	_check_loot_and_determinism()
	_check_invalid_requests()
	_check_invalid_instances()
	_check_metadata_fail_closed()
	_check_exact_values_and_sources()
	print("Typed affix catalog: %d expanded, %d mixed loot, %d frozen legacy; %d checks, %d failures" % [expanded_samples, loot_samples, legacy_samples, checks, failures])
	quit(0 if failures == 0 else 1)


func _check_legacy_golden() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	_expect(parsed is Dictionary, "Frozen v0.6 fixture is available")
	if not parsed is Dictionary:
		return
	var fixture: Dictionary = parsed
	_expect(fixture.source_sha256 == "3f0b5aedb83ffb6543001fbc12bcaeaa3db27b9421b8e93b8d5c2f2d63dbf7c9", "Fixture identifies the frozen v0.6 catalog bytes")
	_expect(Catalog.BASES.size() == 6 and Catalog.BASES == str_to_var(fixture.bases), "All six legacy bases and every metadata field remain unchanged")
	_expect(Catalog.AFFIXES.size() == 12 and Catalog.AFFIXES == str_to_var(fixture.affixes), "All twelve legacy families and all tiers/metadata remain unchanged")
	_expect(Catalog.RARITIES == str_to_var(fixture.rarities), "Legacy rarity definitions remain unchanged")
	var observed_bases: Dictionary = {}
	var observed_rarities: Dictionary = {}
	for sequence: Dictionary in fixture.sequences:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(sequence.seed)
		for sample: Dictionary in sequence.samples:
			var expected: Dictionary = sample.instance
			var actual: Dictionary = Catalog.generate(rng, expected.id, int(expected.item_level), sample.requested_rarity)
			legacy_samples += 1
			_expect(JSON.parse_string(JSON.stringify(actual)) == expected, "Legacy generate retains frozen exact rolls and call sequence")
			_expect(str(rng.state) == sample.rng_state, "Legacy generate retains exact RNG state after every item")
			_expect(Catalog.validate_instance(actual, false), "Every frozen legacy item validates in pre-v6 vocabulary")
			_expect(Catalog.BASES.has(actual.base_id), "Legacy generator never selects expansion base")
			_expect(Catalog.definition(actual).added_sources.is_empty(), "Legacy rolls never invent typed addition sources")
			observed_bases[actual.base_id] = true
			observed_rarities[actual.rarity] = true
			for affix: Dictionary in actual.affixes:
				_expect(Catalog.AFFIXES.has(affix.id), "Legacy generator never selects expansion family")
	_expect(legacy_samples == 432 and observed_bases.size() == 6 and observed_rarities.size() == 3, "Frozen sequences exercise all old bases and rarities")


func _check_definitions() -> void:
	_expect(Catalog.EXPANSION_BASES.size() == 1 and Catalog.EXPANSION_BASES.has("runewood_focus"), "Exactly one bounded expansion base")
	var base: Dictionary = Catalog.base_definition("runewood_focus")
	_expect(base.name == "符木法器" and base.slot == "weapon" and base.size == Vector2i(1, 3), "Focus identity and inventory footprint")
	_expect(base.stats == {"max_mana": 8.0, "mana_regen": 0.25}, "Focus does not reinterpret old scalar/local weapon damage")
	_expect(Catalog.EXPANSION_AFFIXES.size() == 4, "Exactly four expansion families")
	var groups: Dictionary = {}
	var kinds: Dictionary = {"prefix": 0, "suffix": 0}
	for id: String in Catalog.AFFIXES:
		groups[Catalog.AFFIXES[id].group] = true
		if Catalog.AFFIXES[id].slots.has("weapon"):
			kinds[Catalog.AFFIXES[id].kind] += 1
	for id: String in EXPECTED_ADDITIONS:
		var family: Dictionary = Catalog.affix_definition(id)
		_expect(family.kind == "prefix" and family.stat == id and family.unit == "flat", "Typed additions are fixed-point prefixes")
		_expect(not groups.has(family.group), "Expansion groups are distinct from each other and all legacy groups")
		groups[family.group] = true
		kinds.prefix += 1
		_expect(family.stage == "skill_added_damage" and family.scope == "equipped_character", "Explicit executable stage and equipped-character scope")
		_expect(family.required_tags == ["hit", EXPECTED_ADDITIONS[id][0]] and family.damage_type == EXPECTED_ADDITIONS[id][1], "Exact hit plus attack/spell and damage-type eligibility")
		_expect(family.allowed_base_ids == ["runewood_focus"] and family.slots == ["weapon"], "Typed prefix has explicit single-base allowlist")
		_expect(Catalog._valid_expansion_family(family), "Authored metadata passes fail-closed semantic validation")
		for index: int in range(3):
			_expect(family.tiers[index] == {"tier": index + 1, "level": [1, 8, 16][index], "weight": [100, 60, 30][index], "min": 1 + 2 * index, "max": 2 + 2 * index}, "Original fixed-point tier ranges, gates and weights")
	_expect(kinds.prefix == 8 and kinds.suffix == 5, "Focus supports eight compatible prefixes and five suffixes, enough for six-affix rare")
	for id: String in Catalog.BASES.keys() + Catalog.EXPANSION_BASES.keys():
		var detached: Dictionary = Catalog.base_definition(id)
		detached.stats.clear()
		detached.name = "mutated"
		_expect(not Catalog.base_definition(id).stats.is_empty() and Catalog.base_definition(id).name != "mutated", "Base lookup is deeply detached")
	for id: String in Catalog.AFFIXES.keys() + Catalog.EXPANSION_AFFIXES.keys():
		var detached: Dictionary = Catalog.affix_definition(id)
		detached.tiers[0].weight = 0
		detached.slots.clear()
		if detached.has("allowed_base_ids"):
			detached.allowed_base_ids.clear()
		_expect(Catalog.affix_definition(id).tiers[0].weight == 100 and not Catalog.affix_definition(id).slots.is_empty(), "Affix lookup is deeply detached")
	_expect(Catalog.base_definition("unknown").is_empty() and Catalog.affix_definition("unknown").is_empty(), "Unknown lookups reject cleanly")


func _check_expanded_samples() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 703002
	var typed_pairs: Dictionary = {}
	var old_pairs: Dictionary = {}
	for level: int in LEVELS:
		for rarity: String in Catalog.RARITIES:
			var rules: Dictionary = Catalog.RARITIES[rarity]
			var seen_counts: Dictionary = {}
			var seen_tiers: Dictionary = {}
			for sample: int in range(EXPANDED_SAMPLES_PER_COMBINATION):
				var id: String = "gear_%06d" % (expanded_samples + 1)
				var item: Dictionary = Catalog.generate_expanded(rng, id, level, rarity)
				expanded_samples += 1
				_expect(not item.is_empty() and Catalog.validate_instance(item), "Every expanded sample validates without underfill")
				if item.is_empty():
					continue
				_expect(item.size() == 5 and item.id == id and item.base_id == "runewood_focus" and item.item_level == level and item.rarity == rarity, "Expanded generation preserves the exact old five-field instance schema")
				_expect(not Catalog.validate_instance(item, false), "Pre-v6 validation rejects expansion vocabulary even on normal items")
				_expect(item.affixes.size() >= rules.min_affixes and item.affixes.size() <= rules.max_affixes, "Normal/magic/rare affix counts stay in exact bounds")
				seen_counts[item.affixes.size()] = true
				var counts: Dictionary = {"prefix": 0, "suffix": 0}
				var families: Dictionary = {}
				var groups: Dictionary = {}
				var expected_stats: Dictionary = {"max_mana": 8.0, "mana_regen": 0.25}
				for affix: Dictionary in item.affixes:
					var family: Dictionary = Catalog.affix_definition(affix.id)
					var tier: Dictionary = family.tiers[affix.tier - 1]
					_expect(affix.size() == 3 and affix.has_all(["id", "tier", "value"]) and affix.tier is int and affix.value is int, "Affixes retain exact three-field integer-tick encoding")
					_expect(affix.value >= tier.min and affix.value <= tier.max and level >= tier.level, "Only valid tier gates and integer roll ranges are generated")
					_expect(not families.has(affix.id) and not groups.has(family.group), "No duplicate family/group in an expanded item")
					families[affix.id] = true
					groups[family.group] = true
					counts[family.kind] += 1
					seen_tiers[affix.tier] = true
					var pair: String = "%s:%d" % [affix.id, affix.tier]
					if Catalog.EXPANSION_AFFIXES.has(affix.id):
						typed_pairs[pair] = true
						_expect(family.allowed_base_ids.has(item.base_id), "Expanded prefix eligibility is base-specific")
					else:
						old_pairs[pair] = true
						_expect(family.slots.has("weapon"), "Only compatible legacy affixes enter expansion pool")
					var amount: float = float(affix.value) / (100.0 if family.unit == "percent" else 1.0)
					expected_stats[family.stat] = float(expected_stats.get(family.stat, 0.0)) + amount
				_expect(counts.prefix <= rules.max_prefixes and counts.suffix <= rules.max_suffixes, "Per-kind caps are never exceeded")
				_expect(Catalog.get_stats(item) == expected_stats, "New and compatible old affixes resolve to actual runtime stats")
				var roundtrip: Variant = JSON.parse_string(JSON.stringify(item))
				_expect(Catalog.validate_instance(roundtrip) and Catalog.get_stats(roundtrip) == expected_stats, "Every sample survives JSON integral-float roundtrip")
				if sample < 20:
					var definition: Dictionary = Catalog.definition(item)
					_expect(definition.base_id == "runewood_focus" and definition.stats == expected_stats and definition.affix_lines.size() == item.affixes.size(), "UI metadata resolves both vocabularies")
					_expect(definition.size == Vector2i(1, 3) and definition.base_name == "符木法器" and definition.effects.is_empty(), "Expansion UI remains compatible without invented mechanics")
			for count: int in range(int(rules.min_affixes), int(rules.max_affixes) + 1):
				_expect(seen_counts.has(count), "Every allowed count is reachable at each level/rarity, including six-affix rares")
			if rarity != "normal":
				_expect(seen_tiers.size() == (1 if level < 8 else (2 if level < 16 else 3)), "All and only unlocked tiers appear at each level boundary")
	_expect(expanded_samples == 18000, "At least 18,000 expanded samples cover all level/rarity boundaries")
	_expect(typed_pairs.size() == 12, "All four typed families times three tiers are reachable")
	_expect(old_pairs.size() == 27, "All nine weapon-compatible legacy families times three tiers are reachable")


func _check_loot_and_determinism() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 703003
	var base_counts: Dictionary = {}
	var rarity_counts: Dictionary = {}
	for index: int in range(LOOT_SAMPLES):
		var item: Dictionary = Catalog.generate_loot(rng, "gear_%06d" % (index + 1), 30)
		loot_samples += 1
		_expect(Catalog.validate_instance(item), "Natural mixed loot validates")
		base_counts[item.base_id] = int(base_counts.get(item.base_id, 0)) + 1
		rarity_counts[item.rarity] = int(rarity_counts.get(item.rarity, 0)) + 1
		if Catalog.BASES.has(item.base_id):
			for affix: Dictionary in item.affixes:
				_expect(not Catalog.EXPANSION_AFFIXES.has(affix.id), "Natural legacy bases never roll new families")
	var expanded_count: int = int(base_counts.get("runewood_focus", 0))
	_expect(base_counts.size() == 7, "Natural loot reaches six legacy bases and one expansion base")
	_expect(expanded_count >= 2760 and expanded_count <= 3240, "Natural pool distribution is consistent with 75% legacy / 25% expanded")
	for id: String in Catalog.BASES:
		_expect(base_counts[id] >= 1260 and base_counts[id] <= 1740, "Each legacy base remains roughly 12.5% of natural loot")
	_expect(rarity_counts.normal > 3240 and rarity_counts.normal < 3960 and rarity_counts.magic > 6120 and rarity_counts.magic < 7080 and rarity_counts.rare > 1440 and rarity_counts.rare < 2160, "Pool choice does not alter 30/55/15 rarity weights")
	for method: String in ["generate", "generate_expanded", "generate_loot"]:
		var first := RandomNumberGenerator.new()
		var second := RandomNumberGenerator.new()
		first.seed = 703004
		second.seed = 703004
		var forced_bases: Dictionary = {}
		for index: int in range(256):
			var rarity: String = ["", "normal", "magic", "rare"][index % 4]
			var id: String = "gear_%06d" % (index + 1)
			var left: Dictionary = _generate(method, first, id, 1 + index % 30, rarity)
			var right: Dictionary = _generate(method, second, id, 1 + index % 30, rarity)
			_expect(left == right and first.state == second.state, "Deterministic item and RNG state for " + method)
			_expect(rarity.is_empty() or left.rarity == rarity, "Forced rarity is never rerolled by pool choice")
			if rarity == "rare":
				forced_bases[left.base_id] = true
		if method == "generate_loot":
			_expect(forced_bases.has("runewood_focus") and forced_bases.size() > 1, "Forced rare natural loot still uses both pools")
	# Check exact pool-roll dispatch, rather than inferring the contract only statistically.
	var actual_rng := RandomNumberGenerator.new()
	var expected_rng := RandomNumberGenerator.new()
	actual_rng.seed = 703005
	expected_rng.seed = 703005
	for index: int in range(256):
		var id: String = "gear_%06d" % (index + 1)
		var expanded: bool = expected_rng.randi_range(1, 100) <= 25
		var expected: Dictionary = Catalog.generate_expanded(expected_rng, id, 16, "rare") if expanded else Catalog.generate(expected_rng, id, 16, "rare")
		_expect(Catalog.generate_loot(actual_rng, id, 16, "rare") == expected and actual_rng.state == expected_rng.state, "Natural dispatch is exactly one 25%-threshold pool roll followed by unchanged generator")


func _check_invalid_requests() -> void:
	for method: String in ["generate", "generate_expanded", "generate_loot"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 703006
		var state: int = rng.state
		for id: String in ["bad", "gear_0", "gear_000000", "gear_1", "gear_0000001", "gear_+00001", "gear_1000000000", "gear_000001 "]:
			_expect(_generate(method, rng, id, 16, "rare").is_empty() and rng.state == state, "Invalid identity consumes no randomness in " + method)
		for level: int in [-1, 0, 31, 100]:
			_expect(_generate(method, rng, "gear_000001", level, "rare").is_empty() and rng.state == state, "Out-of-range level consumes no randomness in " + method)
		_expect(_generate(method, rng, "gear_000001", 16, "mythic").is_empty() and rng.state == state, "Unknown rarity consumes no randomness in " + method)
		_expect(_generate(method, null, "gear_000001", 16, "rare").is_empty(), "Missing RNG fails closed in " + method)


func _check_invalid_instances() -> void:
	var valid: Dictionary = _single("attack_added_physical", 1, 1)
	_expect(Catalog.validate_instance(valid), "Mutation fixture starts valid")
	for value: Variant in [null, [], "item", 1, true, {}]:
		_expect(not Catalog.validate_instance(value), "Malformed root rejects")
	for field: String in valid:
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(field)
		_reject(missing, "Missing required instance field rejects")
	for base_id: String in Catalog.BASES:
		for id: String in EXPECTED_ADDITIONS:
			var invalid: Dictionary = _single(id, 1, 1)
			invalid.base_id = base_id
			_reject(invalid, "Every old base rejects every new prefix, even weapon bases")
	for id: String in ["rootwell", "lanternveil", "trailstep"]:
		var invalid: Dictionary = _single(id, 1, int(Catalog.affix_definition(id).tiers[0].min))
		_reject(invalid, "Focus rejects legacy armor/charm-only affixes")
	for field: String in ["id", "base_id", "rarity"]:
		for value: Variant in [null, true, 1, [], {}, "unknown"]:
			var invalid: Dictionary = valid.duplicate(true)
			invalid[field] = value
			_reject(invalid, "Malformed/unknown instance identifier rejects")
	for value: Variant in [null, true, "1", [], {}, NAN, INF, -INF, 0, 31, 1.25, 8.000000001]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.item_level = value
		_reject(invalid, "Malformed/nonfinite/nonintegral/out-of-range item level rejects")
	for value: Variant in [null, true, "affix", {}, 1]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes = value
		_reject(invalid, "Malformed affix array rejects")
	for value: Variant in [null, true, "affix", [], {}, 1]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes = [value]
		_reject(invalid, "Malformed affix entry rejects")
	for field: String in ["id", "tier", "value"]:
		var missing: Dictionary = valid.duplicate(true)
		missing.affixes[0].erase(field)
		_reject(missing, "Missing required affix field rejects")
	for value: Variant in [null, true, 1, [], {}, "attack_added_chaos", "unknown"]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes[0].id = value
		_reject(invalid, "Malformed/unknown typed affix rejects")
	for value: Variant in [null, true, "1", [], {}, NAN, INF, -INF, 0, 4, 1.25, 1.000000001]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes[0].tier = value
		_reject(invalid, "Malformed/nonfinite/nonintegral/nonexistent tier rejects")
	for value: Variant in [null, true, "1", [], {}, NAN, INF, -INF, 0, 3, 1.25, 1.000000001]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes[0].value = value
		_reject(invalid, "Malformed/nonfinite/nonintegral/out-of-range fixed points reject")
	for field: String in ["stage", "scope", "damage_type", "stats", "added_sources", "min", "max"]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid[field] = "forged"
		_reject(invalid, "Unexpected instance metadata cannot bypass authored semantics")
		invalid = valid.duplicate(true)
		invalid.affixes[0][field] = "forged"
		_reject(invalid, "Unexpected affix metadata cannot bypass authored semantics")
	for tier: int in [2, 3]:
		var early: Dictionary = _single("spell_added_cold", tier, 2 * tier - 1)
		early.item_level -= 1
		_reject(early, "One level before each typed tier gate rejects")
	var duplicate: Dictionary = valid.duplicate(true)
	duplicate.affixes.append(duplicate.affixes[0].duplicate(true))
	_reject(duplicate, "Duplicate typed family/group rejects")
	var normal: Dictionary = valid.duplicate(true)
	normal.rarity = "normal"
	_reject(normal, "Normal items cannot have a typed affix")
	var empty_magic: Dictionary = valid.duplicate(true)
	empty_magic.affixes = []
	_reject(empty_magic, "Magic items cannot be empty")
	var underfilled: Dictionary = valid.duplicate(true)
	underfilled.rarity = "rare"
	_reject(underfilled, "Rare items cannot be underfilled")
	var excess_prefixes: Dictionary = valid.duplicate(true)
	excess_prefixes.rarity = "rare"
	excess_prefixes.affixes = []
	for id: String in EXPECTED_ADDITIONS:
		excess_prefixes.affixes.append({"id": id, "tier": 1, "value": 1})
	_reject(excess_prefixes, "Rare items cannot take four typed prefixes")
	var two_prefixes: Dictionary = valid.duplicate(true)
	two_prefixes.affixes.append({"id": "spell_added_cold", "tier": 1, "value": 1})
	_reject(two_prefixes, "Magic typed prefixes retain one-prefix cap")


func _check_metadata_fail_closed() -> void:
	var authored: Dictionary = Catalog.affix_definition("attack_added_physical")
	var mutations: Dictionary = {
		"stage": ["local_weapon", "hit_base", "unknown", "", null, 1, [], {}],
		"scope": ["global", "attack", "weapon", "unknown", null, 1, [], {}],
		"damage_type": ["cold", "chaos", "unknown", "", null, 1, [], {}],
		"stat": ["damage", "attack_added_chaos", "unknown", null, 1, [], {}],
		"required_tags": [["attack"], ["hit"], ["hit", "spell"], ["hit", "attack", "dot"], ["hit", "attack", "attack"], "attack", null, []],
		"allowed_base_ids": [[], ["cinder_reed"], ["runewood_focus", "cinder_reed"], "runewood_focus", null],
		"slots": [["armor"], ["weapon", "charm"], [], "weapon", null],
		"kind": ["suffix", "unknown", null], "unit": ["percent", "unknown", null],
	}
	for field: String in mutations:
		var missing: Dictionary = authored.duplicate(true)
		missing.erase(field)
		_expect(not Catalog._valid_expansion_family(missing), "Missing semantic metadata fails closed")
		for value: Variant in mutations[field]:
			var invalid: Dictionary = authored.duplicate(true)
			invalid[field] = value
			_expect(not Catalog._valid_expansion_family(invalid), "Unknown/mismatched stage, type, scope or applicability fails closed: " + field)


func _check_exact_values_and_sources() -> void:
	for id: String in EXPECTED_ADDITIONS:
		var family: Dictionary = Catalog.affix_definition(id)
		for tier: Dictionary in family.tiers:
			for amount: int in [int(tier.min), int(tier.max)]:
				var item: Dictionary = _single(id, tier.tier, amount)
				var stats: Dictionary = Catalog.get_stats(item)
				_expect(Catalog.validate_instance(item) and stats == {"max_mana": 8.0, "mana_regen": 0.25, id: float(amount)}, "Each tier endpoint adds exact fixed points without scalar conversion")
				var definition: Dictionary = Catalog.definition(item)
				var expected_source: Dictionary = {"item_id": "gear_000001", "affix_id": id, "stat": id, "scope": EXPECTED_ADDITIONS[id][0], "damage_type": EXPECTED_ADDITIONS[id][1], "value": float(amount)}
				_expect(definition.added_sources is Array and definition.added_sources == [expected_source] and definition.added_sources[0].value is float, "Exact six-field detached typed source record")
				_expect(definition.base_id == "runewood_focus" and definition.affix_lines[0].contains("T%d" % int(tier.tier)) and definition.affix_lines[0].contains("+%d" % amount) and definition.affix_lines[0].contains(family.label), "UI identifies tier, fixed value and attack/spell damage type")
				var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(item))
				_expect(roundtrip.item_level is float and roundtrip.affixes[0].tier is float and roundtrip.affixes[0].value is float, "Fixture really exercises JSON numeric conversion")
				_expect(Catalog.definition(roundtrip).added_sources == [expected_source], "Sources survive JSON roundtrip without rerolling")
				definition.added_sources[0].value = 9999.0
				definition.stats[id] = 9999.0
				definition.affix_lines.clear()
				_expect(Catalog.definition(item).added_sources == [expected_source] and Catalog.get_stats(item)[id] == amount and Catalog.definition(item).affix_lines.size() == 1, "Caller mutation cannot alter stored rolls, sources or catalog")
			for amount: int in [int(tier.min) - 1, int(tier.max) + 1]:
				_reject(_single(id, tier.tier, amount), "Each typed tier rejects outside its own endpoints")
	var normal: Dictionary = {"id": "gear_000001", "base_id": "runewood_focus", "rarity": "normal", "item_level": 1, "affixes": []}
	_expect(Catalog.validate_instance(normal) and Catalog.get_stats(normal) == {"max_mana": 8.0, "mana_regen": 0.25} and Catalog.definition(normal).added_sources.is_empty(), "Normal focus has only intrinsic mana stats and no fabricated addition")
	var mixed: Dictionary = {"id": "gear_000002", "base_id": "runewood_focus", "rarity": "rare", "item_level": 16, "affixes": [{"id": "attack_added_fire", "tier": 3, "value": 6}, {"id": "spell_added_cold", "tier": 2, "value": 3}, {"id": "runesong", "tier": 1, "value": 4}, {"id": "coalglow", "tier": 1, "value": 5}, {"id": "rimeecho", "tier": 1, "value": 5}, {"id": "wellturn", "tier": 1, "value": 3}]}
	_expect(Catalog.validate_instance(mixed) and Catalog.definition(mixed).added_sources.size() == 2, "Six-affix rare mixes typed and legacy families; source records include only typed additions")


func _generate(method: String, rng: RandomNumberGenerator, id: String, level: int, rarity: String) -> Dictionary:
	match method:
		"generate_expanded": return Catalog.generate_expanded(rng, id, level, rarity)
		"generate_loot": return Catalog.generate_loot(rng, id, level, rarity)
	return Catalog.generate(rng, id, level, rarity)


func _single(id: String, tier: int, amount: int) -> Dictionary:
	return {"id": "gear_000001", "base_id": "runewood_focus", "rarity": "magic", "item_level": [1, 8, 16][tier - 1], "affixes": [{"id": id, "tier": tier, "value": amount}]}


func _reject(value: Dictionary, message: String) -> void:
	_expect(not Catalog.validate_instance(value), message)
	_expect(Catalog.get_stats(value).is_empty() and Catalog.definition(value).is_empty(), "Rejected instance exposes no partial stats or UI")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
