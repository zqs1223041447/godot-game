extends SceneTree
## Pure profile contract tests; never attach this data to BuildState or loot.

const Profile = preload("res://scripts/items/nine_slot_equipment_profile.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const LEGACY_GOLDEN_PATH: String = "res://tests/fixtures/typed_affix_legacy_rng.json"
const CATEGORIES: Array[String] = ["ring", "boots", "belt", "gloves", "helmet"]
const BASE_IDS: Array[String] = ["nine_slot_etched_ring", "nine_slot_trail_boots", "nine_slot_folded_belt", "nine_slot_threaded_gloves", "nine_slot_slate_helmet"]
const PREFIX_IDS: Array[String] = ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis"]
const SUFFIX_IDS: Array[String] = ["nine_slot_suffix_endurance", "nine_slot_suffix_mana_flow", "nine_slot_suffix_stride"]
const ADDITIONAL_SLOT_AFFIX_ID: String = "nine_slot_suffix_skill_row"
const LEVELS: Array[int] = [1, 8, 16]
const BASE_STATS: Array[String] = ["max_health", "max_mana", "max_shield", "mana_regen", "move_speed"]
const AFFIX_STATS: Array[String] = ["max_health", "max_mana", "max_shield", "mana_regen_increased", "move_speed_increased", "additional_skill_slots"]
const BASE_FIELDS: Array[String] = ["name", "slot", "size", "description", "stats"]
const AFFIX_FIELDS: Array[String] = ["name", "kind", "group", "stat", "unit", "label", "slots", "tiers"]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_profile_shape()
	_check_bases()
	_check_affixes()
	_check_rare_reachability()
	_check_additional_skill_slot()
	_check_deep_copies()
	_check_legacy_catalog_and_rng()
	print("Nine-slot equipment profile: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_profile_shape() -> void:
	var profile: Dictionary = Profile.pool_profile()
	_expect(profile.size() == 3 and profile.has_all(["base_ids", "affix_ids", "min_save_version"]), "Pool profile matches EquipmentCatalog shape")
	_expect(profile.min_save_version is int and profile.min_save_version == 14, "New vocabulary starts at save version 14")
	_expect(profile.base_ids == BASE_IDS and profile.base_ids.size() == 5, "Stable pool lists exactly the five new bases")
	_expect(profile.affix_ids == PREFIX_IDS + SUFFIX_IDS + [ADDITIONAL_SLOT_AFFIX_ID], "Stable pool lists only new affix IDs")
	var bases: Dictionary = Profile.bases()
	var affixes: Dictionary = Profile.affixes()
	_expect(bases.size() == 5 and affixes.size() == 7, "Profile contains five bases and seven families")
	for id: String in bases:
		_expect(not Catalog.BASES.has(id) and not Catalog.EXPANSION_BASES.has(id) and not Catalog.DEFENSE_BASES.has(id) and not Catalog.LOCAL_WEAPON_BASES.has(id), "Base ID does not override any existing definition: " + id)
	for id: String in affixes:
		_expect(not Catalog.AFFIXES.has(id) and not Catalog.EXPANSION_AFFIXES.has(id) and not Catalog.DEFENSE_AFFIXES.has(id) and not Catalog.LOCAL_WEAPON_AFFIXES.has(id), "Affix ID does not override any existing definition: " + id)


func _check_bases() -> void:
	var bases: Dictionary = Profile.bases()
	var observed_categories: Array[String] = []
	for id: String in BASE_IDS:
		var base: Dictionary = bases[id]
		_expect(base.size() == BASE_FIELDS.size() and base.has_all(BASE_FIELDS), "Base record follows the existing five-field shape: " + id)
		_expect(CATEGORIES.has(base.slot) and not observed_categories.has(base.slot), "Base declares one distinct equipment category: " + id)
		observed_categories.append(base.slot)
		_expect(base.size is Vector2i and base.size.x > 0 and base.size.y > 0 and base.size.x <= 2 and base.size.y <= 2, "Base footprint is a positive supported backpack size: " + id)
		_expect(base.stats is Dictionary and not base.stats.is_empty(), "Base declares intrinsic stats: " + id)
		for stat: String in base.stats:
			var amount: float = float(base.stats[stat])
			_expect(BASE_STATS.has(stat) and is_finite(amount) and amount > 0.0, "Base uses only an existing allowed positive stat: " + id + "/" + stat)
	var every_category_seen: bool = observed_categories.size() == CATEGORIES.size()
	for category: String in CATEGORIES:
		every_category_seen = every_category_seen and observed_categories.has(category)
	_expect(every_category_seen, "All five requested categories have a base")
	_expect(bases[BASE_IDS[0]].stats == {"max_health": 4.0, "max_mana": 2.0}, "Ring prototype values match the QA rationale")
	_expect(bases[BASE_IDS[1]].stats == {"max_health": 3.0, "move_speed": 1.0}, "Boot prototype values match the QA rationale")
	_expect(bases[BASE_IDS[2]].stats == {"max_health": 4.0, "max_shield": 2.0}, "Belt prototype values match the QA rationale")
	_expect(bases[BASE_IDS[3]].stats == {"max_mana": 2.0, "mana_regen": 0.1}, "Glove prototype values match the QA rationale")
	_expect(bases[BASE_IDS[4]].stats == {"max_health": 4.0, "max_shield": 2.0}, "Helmet prototype values match the QA rationale")


func _check_affixes() -> void:
	var affixes: Dictionary = Profile.affixes()
	var expected_groups: Dictionary = {}
	_expect(affixes.size() == 7, "Exactly three prefixes, three base suffixes and one dedicated skill-slot suffix")
	for id: String in affixes:
		var family: Dictionary = affixes[id]
		_expect(family.size() == AFFIX_FIELDS.size() and family.has_all(AFFIX_FIELDS), "Affix record follows the existing eight-field shape: " + id)
		_expect(family.kind in ["prefix", "suffix"] and family.unit in ["flat", "percent"], "Affix declares a recognized kind and unit: " + id)
		_expect(AFFIX_STATS.has(family.stat), "Affix uses an existing stat or the explicit skill-slot consumer field: " + id)
		_expect(family.group is String and not family.group.is_empty() and not expected_groups.has(family.group), "Every affix has a distinct mutual-exclusion group: " + id)
		expected_groups[family.group] = true
		_expect(family.slots is Array and not family.slots.is_empty(), "Affix declares category eligibility: " + id)
		_expect(family.tiers is Array and family.tiers.size() == 3, "Affix declares three tiers: " + id)
		for index: int in range(3):
			var tier: Dictionary = family.tiers[index]
			_expect(tier.size() == 5 and tier.has_all(["tier", "level", "weight", "min", "max"]), "Tier follows the existing five-field shape: " + id)
			_expect(tier.tier is int and tier.tier == index + 1 and tier.level is int and tier.level == LEVELS[index], "Tier gates use T1/T2/T3 at item levels 1/8/16: " + id)
			_expect(tier.weight is int and tier.weight > 0, "Tier weight is a positive integer: " + id)
			_expect(tier.min is int and tier.max is int and tier.min > 0 and tier.min <= tier.max, "Tier rolls are positive bounded integers: " + id)
			if id != ADDITIONAL_SLOT_AFFIX_ID and index > 0:
				_expect(tier.min > int(family.tiers[index - 1].max), "Tier integer ranges do not overlap: " + id)
	_expect(expected_groups.size() == affixes.size(), "All groups remain mutually exclusive without aliases")
	for id: String in PREFIX_IDS:
		_expect(affixes[id].kind == "prefix" and affixes[id].slots == CATEGORIES, "Each shared prefix is eligible on all five bases: " + id)
	for id: String in SUFFIX_IDS:
		_expect(affixes[id].kind == "suffix" and affixes[id].slots == CATEGORIES, "Each shared suffix is eligible on all five bases: " + id)


func _check_rare_reachability() -> void:
	var bases: Dictionary = Profile.bases()
	var affixes: Dictionary = Profile.affixes()
	var rare_rules: Dictionary = Catalog.RARITIES["rare"]
	_expect(rare_rules.max_prefixes == 3 and rare_rules.max_suffixes == 3 and rare_rules.max_affixes == 6, "Rare rarity allows three prefixes and three suffixes")
	for base_id: String in BASE_IDS:
		var base: Dictionary = bases[base_id]
		for item_level: int in LEVELS:
			var selected: Array[String] = PREFIX_IDS + SUFFIX_IDS
			var groups: Dictionary = {}
			var counts: Dictionary = {"prefix": 0, "suffix": 0}
			var valid: bool = true
			for affix_id: String in selected:
				var family: Dictionary = affixes[affix_id]
				var tier: Dictionary = _tier_at_level(family, item_level)
				valid = valid and not tier.is_empty() and family.slots.has(base.slot) and not groups.has(family.group)
				if tier.is_empty():
					continue
				valid = valid and tier.weight > 0 and tier.min is int and tier.max is int and tier.min > 0 and tier.min <= tier.max
				groups[family.group] = true
				counts[family.kind] = int(counts[family.kind]) + 1
			_expect(valid and selected.size() == rare_rules.max_affixes and counts.prefix == rare_rules.max_prefixes and counts.suffix == rare_rules.max_suffixes, "%s ilvl%d has a legal rare 3-prefix/3-suffix witness" % [base.slot, item_level])
			_expect(groups.size() == 6, "%s ilvl%d witness uses six non-conflicting groups" % [base.slot, item_level])


func _check_additional_skill_slot() -> void:
	var family: Dictionary = Profile.affixes()[ADDITIONAL_SLOT_AFFIX_ID]
	_expect(family.kind == "suffix" and family.stat == "additional_skill_slots" and family.unit == "flat", "Additional skill row is represented as a flat suffix")
	_expect(family.slots == ["belt", "helmet"], "Additional skill row is eligible only on belt and helmet")
	for tier: Dictionary in family.tiers:
		_expect(tier.min == 1 and tier.max == 1, "Additional skill row can only roll exactly +1")
	for category: String in CATEGORIES:
		_expect(family.slots.has(category) == (category in ["belt", "helmet"]), "Additional skill row category gate is exact: " + category)


func _check_deep_copies() -> void:
	var detached_bases: Dictionary = Profile.bases()
	detached_bases[BASE_IDS[0]].stats.max_health = 999.0
	_expect(Profile.bases()[BASE_IDS[0]].stats.max_health == 4.0, "Base lookup deep-copies nested stats")
	var detached_affixes: Dictionary = Profile.affixes()
	detached_affixes[PREFIX_IDS[0]].tiers[0].min = 999
	detached_affixes[PREFIX_IDS[0]].slots.clear()
	_expect(Profile.affixes()[PREFIX_IDS[0]].tiers[0].min == 4 and Profile.affixes()[PREFIX_IDS[0]].slots == CATEGORIES, "Affix lookup deep-copies tiers and eligibility arrays")
	var detached_profile: Dictionary = Profile.pool_profile()
	detached_profile.base_ids.clear()
	detached_profile.affix_ids[0] = "legacy_overwrite"
	detached_profile.min_save_version = 1
	var fresh_profile: Dictionary = Profile.pool_profile()
	_expect(fresh_profile.base_ids == BASE_IDS and fresh_profile.affix_ids[0] == PREFIX_IDS[0] and fresh_profile.min_save_version == 14, "Pool profile deep-copies nested ID arrays")


func _check_legacy_catalog_and_rng() -> void:
	var legacy_bases_before: Dictionary = Catalog.BASES.duplicate(true)
	var legacy_affixes_before: Dictionary = Catalog.AFFIXES.duplicate(true)
	var legacy_pool_before: Dictionary = Catalog.pool_profile("legacy")
	var expected_legacy_pool: Dictionary = {
		"base_ids": ["cinder_reed", "gale_spindle", "woven_bastion", "tidebound_coat", "wayglass_token", "pulse_seed"],
		"affix_ids": ["rootwell", "deepwell", "lanternveil", "runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread", "wellturn", "trailstep", "beatlink"],
		"min_save_version": 4,
	}
	_expect(legacy_pool_before == expected_legacy_pool, "Original legacy pool retains its frozen IDs and save gate")
	var expected_next_rng := RandomNumberGenerator.new()
	var actual_next_rng := RandomNumberGenerator.new()
	expected_next_rng.seed = 718403
	actual_next_rng.seed = 718403
	var expected_roll: int = expected_next_rng.randi_range(1, 100000)
	Profile.bases()
	Profile.affixes()
	Profile.pool_profile()
	var actual_roll: int = actual_next_rng.randi_range(1, 100000)
	_expect(actual_roll == expected_roll, "Pure profile access does not consume caller RNG state")
	_expect(Catalog.BASES == legacy_bases_before and Catalog.AFFIXES == legacy_affixes_before and Catalog.pool_profile("legacy") == legacy_pool_before, "Pure profile calls leave the original catalog and pool unchanged")

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_GOLDEN_PATH))
	_expect(parsed is Dictionary, "Frozen legacy directory/RNG fixture is readable")
	if not parsed is Dictionary:
		return
	var fixture: Dictionary = parsed
	_expect(Catalog.BASES == str_to_var(fixture.bases) and Catalog.AFFIXES == str_to_var(fixture.affixes), "Original base and affix definitions match the frozen directory bytes")
	_expect(Catalog.RARITIES == str_to_var(fixture.rarities), "Original rarity definition matches frozen bytes")
	var samples: int = 0
	for sequence: Dictionary in fixture.sequences:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(sequence.seed)
		for sample: Dictionary in sequence.samples:
			var expected: Dictionary = sample.instance
			var actual: Dictionary = Catalog.generate(rng, expected.id, int(expected.item_level), sample.requested_rarity)
			_expect(JSON.parse_string(JSON.stringify(actual)) == expected, "Original equipment roll remains fixture-identical")
			_expect(str(rng.state) == sample.rng_state, "Original equipment RNG state remains fixture-identical")
			samples += 1
	_expect(samples == 432, "All 432 frozen original RNG samples were checked")


func _tier_at_level(family: Dictionary, item_level: int) -> Dictionary:
	var selected: Dictionary = {}
	for tier: Dictionary in family.tiers:
		if int(tier.level) <= item_level:
			selected = tier
	return selected


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
