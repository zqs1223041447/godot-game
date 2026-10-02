extends SceneTree
## Pure catalog tests: no player state, save paths, reference exports, or combat setup.

const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const BOUNDARY_LEVELS: Array[int] = [1, 7, 8, 15, 16, 30]
const SAMPLES_PER_COMBINATION: int = 5000
const EXPECTED_STATS: Array[String] = ["max_health", "max_mana", "max_shield", "spell_increased", "fire_increased", "cold_increased", "lightning_increased", "attack_elemental_increased", "mana_regen_increased", "move_speed_increased", "attack_speed_increased", "projectile_increased"]
var checks: int = 0
var failures: int = 0
var generated: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_catalog()
	_check_generated_samples()
	_check_determinism()
	_check_invalid_instances()
	_check_exact_values()
	print("Equipment catalog: %d generated instances, %d checks, %d failures" % [generated, checks, failures])
	quit(0 if failures == 0 else 1)


func _check_catalog() -> void:
	_expect(Catalog.BASES.size() == 6 and Catalog.AFFIXES.size() == 12, "Six original bases and twelve original families")
	var slots: Dictionary = {"weapon": 0, "armor": 0, "charm": 0}
	var sizes: Dictionary = {"weapon": Vector2i(1, 3), "armor": Vector2i(2, 3), "charm": Vector2i.ONE}
	var stats: Array[String] = []
	var groups: Dictionary = {}
	for id: String in Catalog.BASES:
		var base: Dictionary = Catalog.BASES[id]
		_expect(base.has_all(["name", "slot", "size", "description", "stats"]), "Base metadata complete: " + id)
		_expect(slots.has(base.slot) and base.size == sizes[base.slot], "Base uses supported slot footprint: " + id)
		slots[base.slot] += 1
		for stat: String in base.stats:
			_expect(float(base.stats[stat]) > 0.0 and is_finite(float(base.stats[stat])), "Base stat is finite and positive: " + id)
		var kinds: Dictionary = {"prefix": 0, "suffix": 0}
		for family: Dictionary in Catalog.AFFIXES.values():
			if family.slots.has(base.slot):
				kinds[family.kind] += 1
		_expect(kinds.prefix >= 3 and kinds.suffix >= 3, "Every base supports six-affix rare without underfill: " + id)
	_expect(slots == {"weapon": 2, "armor": 2, "charm": 2}, "Exactly two bases per slot")
	for id: String in Catalog.AFFIXES:
		var family: Dictionary = Catalog.AFFIXES[id]
		_expect(family.kind in ["prefix", "suffix"] and family.unit in ["flat", "percent"], "Family declares supported affix kind and units")
		_expect(not groups.has(family.group), "Original groups have no duplicate aliases")
		groups[family.group] = true
		_expect(EXPECTED_STATS.has(family.stat) and not stats.has(family.stat), "Exactly one original family per supported runtime stat")
		stats.append(family.stat)
		_expect(family.tiers.size() == 3 and not family.slots.is_empty(), "Three original tiers and explicit slot eligibility")
		var previous_max: int = 0
		for index: int in range(3):
			var tier: Dictionary = family.tiers[index]
			_expect(tier.tier == index + 1 and tier.level == [1, 8, 16][index], "Original tier progression and level gates")
			_expect(tier.min is int and tier.max is int and tier.min > previous_max and tier.min <= tier.max, "Positive bounded disjoint integer-tick ranges")
			_expect(tier.weight == [100, 60, 30][index], "Every eligible tier retains its explicit positive weight")
			previous_max = tier.max
	_expect(stats.size() == EXPECTED_STATS.size(), "No supported family omitted and no unsupported stat admitted")
	_expect(Catalog.AFFIXES.lanternveil.stat == "max_shield" and Catalog.AFFIXES.lanternveil.label.contains("全局"), "Shield is explicitly a flat global analogue")
	_expect(Catalog.AFFIXES.farweave.stat == "projectile_increased" and Catalog.AFFIXES.farweave.label.contains("不含独立爆炸"), "Projectile analogue exposes its real event scope")


func _check_generated_samples() -> void:
	var observed_pairs: Dictionary = {}
	var global_bases: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 500501
	for item_level: int in BOUNDARY_LEVELS:
		for rarity: String in Catalog.RARITIES:
			var observed_counts: Dictionary = {}
			var observed_bases: Dictionary = {}
			var observed_tiers: Dictionary = {}
			var rules: Dictionary = Catalog.RARITIES[rarity]
			for sample: int in range(SAMPLES_PER_COMBINATION):
				var id: String = "gear_%06d" % (generated + 1)
				var item: Dictionary = Catalog.generate(rng, id, item_level, rarity)
				generated += 1
				_expect(Catalog.validate_instance(item), "Generated instance validates at level %d rarity %s" % [item_level, rarity])
				if item.is_empty():
					continue
				_expect(item.id == id and item.item_level == item_level and item.rarity == rarity, "Generation preserves requested identity, level, rarity")
				_expect(item.item_level is int, "Generated item level uses an integer")
				observed_bases[item.base_id] = true
				global_bases[item.base_id] = true
				observed_counts[item.affixes.size()] = true
				var families: Dictionary = {}
				var groups: Dictionary = {}
				var counts: Dictionary = {"prefix": 0, "suffix": 0}
				var expected: Dictionary = Catalog.BASES[item.base_id].stats.duplicate(true)
				for affix: Dictionary in item.affixes:
					var family: Dictionary = Catalog.AFFIXES[affix.id]
					var tier: Dictionary = family.tiers[int(affix.tier) - 1]
					observed_pairs["%s:%d" % [affix.id, int(affix.tier)]] = true
					observed_tiers[affix.tier] = true
					_expect(not families.has(affix.id) and not groups.has(family.group), "No duplicate family or group")
					families[affix.id] = true
					groups[family.group] = true
					counts[family.kind] += 1
					_expect(affix.tier is int and affix.value is int and affix.value >= tier.min and affix.value <= tier.max, "Generated rolls are bounded integer ticks")
					_expect(item_level >= tier.level and family.slots.has(Catalog.BASES[item.base_id].slot), "Generated tier and slot are eligible")
					var amount: float = float(affix.value) / (100.0 if family.unit == "percent" else 1.0)
					expected[family.stat] = float(expected.get(family.stat, 0.0)) + amount
				_expect(item.affixes.size() >= rules.min_affixes and item.affixes.size() <= rules.max_affixes, "Rarity count is exact, never silently underfilled")
				_expect(counts.prefix <= rules.max_prefixes and counts.suffix <= rules.max_suffixes, "Rarity prefix and suffix caps respected")
				_expect(Catalog.get_stats(item) == expected, "Every affix contributes its actual runtime unit")
				# Metadata sampled in every combination; standalone exact-value tests cover every tier.
				if sample < 25:
					var definition: Dictionary = Catalog.definition(item)
					_expect(definition.has_all(["id", "name", "slot", "size", "description", "stats", "effects", "rarity", "item_level", "affix_lines", "base_name"]), "UI-compatible metadata complete")
					_expect(definition.id == id and definition.stats == expected and definition.effects.is_empty(), "Metadata has correct identity and no phantom mechanics")
					_expect(definition.affix_lines is Array[String] and definition.affix_lines.size() == item.affixes.size(), "One readable line per actual affix")
					_expect(definition.size == Catalog.BASES[item.base_id].size and not definition.description.is_empty() and not definition.name.is_empty(), "UI footprint and descriptions are usable")
					_expect(Catalog.validate_instance(JSON.parse_string(JSON.stringify(item))), "Generated records validate after lossless JSON roundtrip")
			_expect(observed_bases.size() == Catalog.BASES.size(), "Every boundary/rarity sample reaches all six bases")
			for count: int in range(int(rules.min_affixes), int(rules.max_affixes) + 1):
				_expect(observed_counts.has(count), "Every permitted affix count is reachable")
			if rarity != "normal":
				var tier_count: int = 1 if item_level < 8 else (2 if item_level < 16 else 3)
				_expect(observed_tiers.size() == tier_count, "All and only eligible tiers appear at each boundary")
	_expect(observed_pairs.size() == 36 and global_bases.size() == 6, "All 36 family/tier pairs and all bases reached")
	var random_rarities: Dictionary = {}
	for sample: int in range(5000):
		var item: Dictionary = Catalog.generate(rng, "gear_%06d" % (generated + 1), 30)
		generated += 1
		_expect(Catalog.validate_instance(item), "Automatic rarity generation validates")
		random_rarities[item.rarity] = int(random_rarities.get(item.rarity, 0)) + 1
	_expect(random_rarities.size() == 3, "Automatic rarity pool reaches normal, magic, rare")
	_expect(random_rarities.magic > random_rarities.normal and random_rarities.normal > random_rarities.rare, "Automatic rarity follows documented weighted ordering")


func _check_determinism() -> void:
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 704105
	second.seed = 704105
	for index: int in range(256):
		var id: String = "gear_%06d" % (index + 1)
		_expect(Catalog.generate(first, id, 1 + index % 30) == Catalog.generate(second, id, 1 + index % 30), "Same seed and call sequence yields identical instances")
	var state: int = first.state
	_expect(Catalog.generate(first, "bad", 10).is_empty(), "Invalid ID rejects before generation")
	_expect(Catalog.generate(first, "gear_000001", 0).is_empty() and Catalog.generate(first, "gear_000001", 31).is_empty(), "Levels outside 1–30 reject")
	_expect(Catalog.generate(first, "gear_000001", 1, "legendary").is_empty(), "Unknown rarity cannot enter pool")
	_expect(Catalog.generate(null, "gear_000001", 1).is_empty(), "Missing RNG rejects safely")
	_expect(first.state == state, "Rejected generation consumes no randomness")
	for serial: int in [1, 999999, 1000000, 999999999]:
		_expect(Catalog.serial_from_id("gear_%06d" % serial) == serial, "Canonical numeric identity accepts allowed boundary")
	for id: String in ["gear_", "gear_0", "gear_000000", "gear_1", "gear_0000001", "gear_+00001", "gear_-00001", "gear_000001 ", "gear_1.0", "gear_1000000000", "jewel_000001", "GEAR_000001", "gear_00000１"]:
		_expect(Catalog.serial_from_id(id) == 0, "Noncanonical numeric identity rejected: " + id)


func _check_invalid_instances() -> void:
	var valid: Dictionary = _single("runesong", 1, 4)
	_expect(Catalog.validate_instance(valid), "Mutation fixture begins valid")
	for value: Variant in [null, [], "equipment", 1, true, {}, {"id": "gear_000001"}]:
		_expect(not Catalog.validate_instance(value), "Malformed root rejects")
	for field: String in valid:
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(field)
		_reject(missing, "Missing instance field rejects: " + field)
	for field: String in ["id", "base_id", "rarity"]:
		for value: Variant in [true, null, 1, 1.0, [], {}, "unknown"]:
			var invalid: Dictionary = valid.duplicate(true)
			invalid[field] = value
			_reject(invalid, "Invalid instance string field rejects: " + field)
	var extra: Dictionary = valid.duplicate(true)
	extra["stats"] = {"damage": 99999}
	_reject(extra, "Unknown injected stats field rejects")
	for value: Variant in [true, null, "1", [], {}, NAN, INF, -INF, 0, 31, 1.5, 8.000000001]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.item_level = value
		_reject(invalid, "Malformed/out-of-range/nonintegral level rejects")
	for value: Variant in [true, null, "affixes", {}, 0]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes = value
		_reject(invalid, "Malformed affix array rejects")
	for value: Variant in [true, null, "affix", 0, [], {}, {"id": "runesong", "tier": 1}]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes = [value]
		_reject(invalid, "Malformed affix rejects")
	for field: String in ["id", "tier", "value"]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes[0].erase(field)
		_reject(invalid, "Missing affix field rejects: " + field)
	for value: Variant in [true, null, 1, [], {}, "local_weapon_physical_increased", "unknown"]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes[0].id = value
		_reject(invalid, "Unknown/malformed/unsupported affix family rejects")
	for value: Variant in [true, null, "1", [], {}, NAN, INF, -INF, 0, 4, 1.5, 1.000000001]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes[0].tier = value
		_reject(invalid, "Malformed or nonexistent tier rejects")
	for value: Variant in [true, null, "4", [], {}, NAN, INF, -INF, 3, 8, 4.5, 4.000000001, 999999999999]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid.affixes[0].value = value
		_reject(invalid, "Malformed/out-of-range/off-tick roll rejects")
	extra = valid.duplicate(true)
	extra.affixes[0]["damage"] = 99999
	_reject(extra, "Unknown affix field rejects")
	var duplicate: Dictionary = valid.duplicate(true)
	duplicate.affixes.append(duplicate.affixes[0].duplicate())
	_reject(duplicate, "Duplicate family/group rejects")
	var duplicate_tier: Dictionary = valid.duplicate(true)
	duplicate_tier.item_level = 30
	duplicate_tier.affixes.append({"id": "runesong", "tier": 2, "value": 8})
	_reject(duplicate_tier, "Different tiers cannot bypass family/group uniqueness")
	var wrong_slot: Dictionary = valid.duplicate(true)
	wrong_slot.base_id = "woven_bastion"
	_reject(wrong_slot, "Family from another slot pool rejects")
	var too_early: Dictionary = _single("runesong", 2, 8)
	too_early.item_level = 7
	_reject(too_early, "Tier 2 rejects one level before gate")
	too_early = _single("runesong", 3, 13)
	too_early.item_level = 15
	_reject(too_early, "Tier 3 rejects one level before gate")
	var empty_magic: Dictionary = valid.duplicate(true)
	empty_magic.affixes = []
	_reject(empty_magic, "Magic cannot have zero affixes")
	var normal: Dictionary = valid.duplicate(true)
	normal.rarity = "normal"
	_reject(normal, "Normal cannot have any affixes")
	var too_many: Dictionary = valid.duplicate(true)
	too_many.affixes.append({"id": "deepwell", "tier": 1, "value": 5})
	_reject(too_many, "Magic cannot have two prefixes")
	var two_suffixes: Dictionary = _single("coalglow", 1, 5)
	two_suffixes.affixes.append({"id": "rimeecho", "tier": 1, "value": 5})
	_reject(two_suffixes, "Magic cannot have two suffixes")
	var rare: Dictionary = valid.duplicate(true)
	rare.rarity = "rare"
	_reject(rare, "Rare cannot be underfilled")
	rare.affixes = [{"id": "rootwell", "tier": 1, "value": 8}, {"id": "deepwell", "tier": 1, "value": 5}, {"id": "lanternveil", "tier": 1, "value": 5}, {"id": "runesong", "tier": 1, "value": 4}]
	_reject(rare, "Rare cannot have four prefixes")
	rare.affixes = [{"id": "coalglow", "tier": 1, "value": 5}, {"id": "rimeecho", "tier": 1, "value": 5}, {"id": "sparkthread", "tier": 1, "value": 5}, {"id": "wellturn", "tier": 1, "value": 3}]
	_reject(rare, "Rare cannot have four suffixes")
	var rng := RandomNumberGenerator.new()
	rng.seed = 90
	var full: Dictionary = Catalog.generate(rng, "gear_000001", 30, "rare")
	while full.affixes.size() != 6:
		full = Catalog.generate(rng, "gear_000001", 30, "rare")
	full.affixes.append({"id": "coalglow", "tier": 1, "value": 5})
	_reject(full, "Rare cannot have seven affixes")
	var json_value: Dictionary = JSON.parse_string(JSON.stringify(valid))
	_expect(json_value.item_level is float and json_value.affixes[0].tier is float and json_value.affixes[0].value is float, "JSON fixture uses integral float encoding")
	_expect(Catalog.validate_instance(json_value) and Catalog.get_stats(json_value) == Catalog.get_stats(valid), "Whole JSON numerics preserve exact values and runtime stats")


func _check_exact_values() -> void:
	for id: String in Catalog.AFFIXES:
		var family: Dictionary = Catalog.AFFIXES[id]
		for tier: Dictionary in family.tiers:
			for amount: int in [int(tier.min), int(tier.max)]:
				var item: Dictionary = _single(id, int(tier.tier), amount)
				_expect(Catalog.validate_instance(item), "Every exact tier endpoint validates")
				var expected: float = float(amount) / (100.0 if family.unit == "percent" else 1.0)
				expected += float(Catalog.BASES[item.base_id].stats.get(family.stat, 0.0))
				var stats: Dictionary = Catalog.get_stats(item)
				_expect(is_equal_approx(stats[family.stat], expected), "Exact flat points or percentage tick conversion")
				var definition: Dictionary = Catalog.definition(item)
				_expect(definition.affix_lines[0].contains("T%d" % int(tier.tier)) and definition.affix_lines[0].contains(family.name), "Tier and original family name visible")
				_expect(definition.affix_lines[0].contains("+%d%s" % [amount, "%" if family.unit == "percent" else ""]), "Exact rolled amount and unit visible")
				_expect(definition.base_name == Catalog.BASES[item.base_id].name and definition.rarity == "magic", "UI metadata identifies base and rarity")
				stats[family.stat] = 1000000.0
				definition.stats[family.stat] = 2000000.0
				definition.affix_lines.clear()
				_expect(is_equal_approx(Catalog.get_stats(item)[family.stat], expected) and Catalog.definition(item).affix_lines.size() == 1, "Returned metadata cannot mutate catalog or instance")
				for bad_amount: int in [int(tier.min) - 1, int(tier.max) + 1]:
					var bad: Dictionary = _single(id, int(tier.tier), bad_amount)
					_reject(bad, "Each tier enforces its own endpoints")
	var normal: Dictionary = {"id": "gear_999999999", "base_id": "cinder_reed", "rarity": "normal", "item_level": 30, "affixes": []}
	_expect(Catalog.get_stats(normal) == {"damage": 3.0, "mana_regen": 0.25}, "Normal item contributes only modest original base stats")
	_expect(Catalog.definition(normal).affix_lines.is_empty() and Catalog.definition(normal).effects.is_empty(), "Normal item has no affixes or invented effects")


func _single(id: String, tier: int, amount: int) -> Dictionary:
	return {"id": "gear_000001", "base_id": "wayglass_token", "rarity": "magic", "item_level": [1, 8, 16][tier - 1], "affixes": [{"id": id, "tier": tier, "value": amount}]}


func _reject(value: Dictionary, message: String) -> void:
	_expect(not Catalog.validate_instance(value), message)
	_expect(Catalog.get_stats(value).is_empty() and Catalog.definition(value).is_empty(), "Rejected instances never leak partial stats or UI content")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
