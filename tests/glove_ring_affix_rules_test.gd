extends SceneTree
## Focused v46 catalog/Craft proof. Frozen v39 entrypoints and hashed unchanged
## authorities provide the baseline; no scene, save writes or long simulation.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Profile = preload("res://scripts/items/glove_ring_affix_profile.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Expand = preload("res://scripts/items/crafting_expansion_rules.gd")
const Targeted = preload("res://scripts/items/targeted_reforge_rules.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Hit = preload("res://scripts/combat/attack_hit_rules.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Old = preload("res://tests/fixtures/glove_ring_v46_frozen/equipment_catalog.gd")
const OldCraft = preload("res://tests/fixtures/glove_ring_v46_frozen/crafting_rules.gd")
const LEVELS: Array[int] = [1, 7, 8, 15, 16, 30]
const PREFIXES: Array[String] = ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis"]
const RING_SUFFIXES: Array[String] = ["ring_emberward", "ring_rimeward", "ring_stormward"]
var checks: int = 0
var failures: int = 0
var completed: bool = false
var historical_rolls: int = 0
var historical_plans: int = 0
var witnesses: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_metadata, _admission, _consumers, _generation, _crafting, _history]:
		completed = false
		test.call()
		_expect(completed, "Case completed: " + test.get_method())
	var path: String = OS.get_environment("GLOVE_RING_REPORT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		_expect(file != null, "QA report is writable")
		if file != null:
			file.store_string(JSON.stringify({"checks": checks, "failures": failures, "historical_item_and_rng_comparisons": historical_rolls,
				"historical_craft_plan_comparisons": historical_plans, "witnesses": witnesses}, "\t") + "\n")
			file.close()
	print("Glove/ring affixes: %d checks, %d failures; %d historical item+RNG comparisons, %d historical Craft plans" % [checks, failures, historical_rolls, historical_plans])
	quit(0 if failures == 0 else 1)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)


func _same(actual: Variant, expected: Variant, label: String) -> void:
	_expect(var_to_bytes(actual) == var_to_bytes(expected), label)


func _rng(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


func _item(base: String, ids: Array = [], rarity: String = "magic", level: int = 16, tier: int = 3) -> Dictionary:
	var affixes: Array = []
	for id: String in ids:
		affixes.append({"id": id, "tier": tier, "value": int(Catalog.affix_definition(id).tiers[tier - 1].max)})
	return {"id": "gear_000721", "base_id": base, "rarity": rarity, "item_level": level, "affixes": affixes}


func _has(item: Dictionary, id: String) -> bool:
	for affix: Dictionary in item.get("affixes", []):
		if affix.id == id: return true
	return false


func _metadata() -> void:
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/glove_ring_v46_frozen/provenance.json"))
	for path: String in provenance.shared_unchanged_authorities:
		_expect(FileAccess.get_sha256("res://" + path) == provenance.sha256[path], "Frozen oracle dependency is unchanged: " + path)
	_expect(Catalog.CURRENT_VOCABULARY == 46 and Catalog.CANONICAL_LOOT_PROFILE_ID == "canonical_v46" and Catalog.CURRENT_LOOT_PROFILE_ID == "canonical_v46", "Current vocabulary and loot are explicitly46")
	_same(Catalog.all_base_ids(), Old.all_base_ids(), "No base or slot expansion")
	_same(Catalog.all_affix_ids(), Old.all_affix_ids() + Profile.AFFIX_IDS, "Only four appended family IDs")
	_same(Catalog.RARITIES, Old.RARITIES, "Frozen rarity counts and prefix/suffix caps")
	for base: String in Old.all_base_ids(): _same(Catalog.base_definition(base), Old.base_definition(base), "Every original base remains byte-exact")
	for id: String in Old.all_affix_ids(): _same(Catalog.affix_definition(id), Old.affix_definition(id), "Every original family metadata record remains byte-exact")
	for id: String in Old.pool_profiles(): _same(Catalog.pool_profile(id), Old.pool_profile(id), "Historical pool order and metadata remain byte-exact")
	for id: String in Old.loot_profiles(): _same(Catalog.loot_profile(id), Old.loot_profile(id), "Historical loot profiles remain byte-exact")
	var expected: Array[Dictionary] = Old.current_loot_profile()
	expected[4].pool_id = "build_nine_slot_v46"
	_same(Catalog.current_loot_profile(), expected, "Only the existing30% five-base pool changes, with identical ordered weights")
	_same(Profile.POOL_PROFILE.base_ids, Old.pool_profile("build_nine_slot_v27").base_ids, "All five base IDs keep their original order")
	_same(Profile.POOL_PROFILE.affix_ids, Old.pool_profile("build_nine_slot_v27").affix_ids + Profile.AFFIX_IDS, "Four new families append after the frozen v27 families")
	_expect(Catalog.current_pool_for_base("emberhide_vest") == "defense_v39", "Vocabulary46 retains elemental and rating armour families")
	for id: String in Profile.AFFIX_IDS:
		var family: Dictionary = Catalog.affix_definition(id)
		_expect(Profile.valid_family(family), "New family metadata admits only supported semantics")
		if id != "glove_accuracy":
			var original: Dictionary = Old.affix_definition(Profile.RESISTANCE_SOURCE_IDS[id])
			original.slots = ["ring"]; original.allowed_base_ids = [Profile.RING_BASE_ID]
			_same(family, original, "Ring family derives the complete original resistance record and budget")
		var base: String = Profile.GLOVE_BASE_ID if id == "glove_accuracy" else Profile.RING_BASE_ID
		for candidate: String in Catalog.all_base_ids(): _expect(Catalog.family_eligible(id, candidate) == (candidate == base), "New family never expands other bases")
		for change: Dictionary in [{"scope": "equipped_weapon"}, {"slots": ["armor"]}, {"allowed_base_ids": ["emberhide_vest"]}, {"stat": "maximum_fire_resistance_add"}, {"group": "wrong"}, {"unit": "basis_points"}, {"stage": "burning"}, {"actors": ["player"]}]:
			var invalid: Dictionary = family.duplicate(true); invalid.merge(change, true)
			_expect(not Profile.valid_family(invalid), "Invalid new-family semantics reject")
		family.tiers[0].min = 999; family.allowed_base_ids.clear()
		_expect(Catalog.family_eligible(id, base) and Catalog.affix_definition(id).tiers[0].min != 999, "Definition lookups are deeply detached")
	var accuracy: Dictionary = Catalog.affix_definition("glove_accuracy")
	_expect(accuracy.name == "精瞄" and accuracy.label == "命中值" and accuracy.group == "accuracy_rating" and accuracy.stat == "accuracy" and accuracy.kind == "prefix" and accuracy.unit == "flat", "Exact authored glove identity and scalar")
	for index: int in range(3):
		_same(accuracy.tiers[index], {"tier": index + 1, "level": [1, 8, 16][index], "weight": [100, 60, 30][index], "min": [35, 70, 120][index], "max": [60, 110, 160][index]}, "Exact glove tiers, gates and weights")
	completed = true


func _admission() -> void:
	for id: String in Profile.AFFIX_IDS:
		var base: String = Profile.GLOVE_BASE_ID if id == "glove_accuracy" else Profile.RING_BASE_ID
		for level: int in LEVELS:
			for tier: int in [1, 2, 3]:
				var budget: Dictionary = Catalog.affix_definition(id).tiers[tier - 1]
				var item: Dictionary = _item(base, [id], "magic", level, tier)
				for value: int in [int(budget.min), int(budget.max)]:
					item.affixes[0].value = value
					_expect(Catalog.validate_instance(item) == (level >= budget.level), "Both endpoints obey all six tier boundaries")
				for value: Variant in [int(budget.min) - 1, int(budget.max) + 1, float(budget.min) + 0.5, true, str(budget.min), NAN, INF]:
					item.affixes[0].value = value
					_expect(not Catalog.validate_instance(item), "Malformed or out-of-range ticks reject")
		var item: Dictionary = _item(base, [id])
		_expect(Catalog.validate_instance(JSON.parse_string(JSON.stringify(item))), "Integral JSON rolls remain legal")
		for version: int in range(1, 46): _expect(not Catalog.validate_instance_for_version(item, version), "All pre46 vocabulary requests reject new families")
		for candidate: String in Catalog.all_base_ids():
			item.base_id = candidate
			_expect(Catalog.validate_instance(item) == (candidate == base), "Cross-base instances fail closed")
		for entry: Dictionary in Expand._pool(base, 30, _item(base, [id]).affixes):
			_expect(entry.group != Catalog.affix_definition(id).group, "Kept family excludes every tier in its group")
	var full: Dictionary = _item(Profile.RING_BASE_ID, PREFIXES + RING_SUFFIXES, "rare")
	_expect(Catalog.validate_instance(full) and full.affixes.size() == 6, "Hand-authored3prefix+3resistance ring is legal")
	_expect(not Craft.operation_quote(full, "augment").ok, "Full ring cannot receive a seventh affix")
	_expect(not Catalog.validate_instance(_item(Profile.RING_BASE_ID, ["ring_emberward", "ring_rimeward"])), "Magic still allows at most one suffix")
	_expect(not Catalog.validate_instance(_item(Profile.GLOVE_BASE_ID, ["glove_accuracy", PREFIXES[0]])), "Magic still allows at most one prefix")
	_expect(not Catalog.validate_instance(_item(Profile.RING_BASE_ID, PREFIXES + ["ring_emberward", "ring_emberward", "ring_stormward"], "rare")), "Duplicate family/group rejects")
	_expect(not Catalog.validate_instance(_item(Profile.RING_BASE_ID, [PREFIXES[0]] + RING_SUFFIXES + ["global_critical_chance"], "rare")), "Rare cannot carry four suffixes")
	_expect(not Catalog.validate_instance(_item(Profile.GLOVE_BASE_ID, PREFIXES + ["glove_accuracy", "nine_slot_suffix_stride"], "rare")), "Rare cannot carry four prefixes")
	witnesses["legal_six_affix_ring"] = full
	completed = true


func _consumers() -> void:
	var glove: Dictionary = _item(Profile.GLOVE_BASE_ID, ["glove_accuracy"])
	var ring: Dictionary = _item(Profile.RING_BASE_ID, PREFIXES + RING_SUFFIXES, "rare")
	var before: PackedByteArray = var_to_bytes([glove, ring])
	_expect(Catalog.get_stats(glove).accuracy == 160.0, "Flat accuracy remains160points without division")
	_expect(Catalog.affix_display(glove.affixes[0]).line == "命中值 +160", "Accuracy display has no percent sign")
	var stats: Dictionary = Catalog.get_stats(ring)
	for element: String in ["fire", "cold", "lightning"]:
		_expect(stats[element + "_resistance"] == 0.25 and not stats.has("maximum_" + element + "_resistance_add"), "Ring adds25% raw resistance without changing maximum")
	for actor: String in ["player", "monster"]:
		var profile: Dictionary = Defense.resistance_profile(stats, actor)
		_expect(profile.ok and profile.effective_resistances == {"fire": 0.25, "cold": 0.25, "lightning": 0.25} and profile.maximum_resistances == {"fire": 0.75, "cold": 0.75, "lightning": 0.75}, "Actual resistance consumer retains the default75% cap")
	var input: Dictionary = {"max_health": 100.0, "max_mana": 40.0, "max_shield": 0.0, "accuracy": 100.0 + Catalog.get_stats(glove).accuracy, "accuracy_increased": 0.5}
	var candidate: Dictionary = {"version": 46, "talents": {"class_id": 0, "allocated": [], "masteries": {}}, "locations": {}, "items": {}}
	var final_stats: Dictionary = Source.apply_stats(input, candidate)
	_expect(final_stats.accuracy == (260.0 + 2.0 * final_stats.dexterity) * 1.5, "Equipped flat accuracy enters the actual global source-tree final formula once")
	_expect(Hit.chance(final_stats.accuracy, 1000.0) > Hit.chance(100.0, 1000.0), "Actual attack admission benefits from glove accuracy")
	_same(var_to_bytes([glove, ring]), before, "Derived stats/display/consumers preserve item bytes")
	completed = true


func _generation() -> void:
	var seen: Dictionary = {}
	for level: int in LEVELS:
		var rng := _rng(720046 + level)
		var level_seen: Dictionary = {}
		for index: int in range(96):
			var item: Dictionary = Catalog.generate_for_pool(rng, "gear_000721", level, "rare", "build_nine_slot_v46")
			_expect(Catalog.validate_instance(item), "Current natural rare roll is legal")
			for affix: Dictionary in item.affixes:
				if Profile.AFFIX_IDS.has(affix.id):
					level_seen[affix.id] = true; seen[affix.id + ":" + str(affix.tier)] = true
					_expect(affix.tier <= (1 if level < 8 else 2 if level < 16 else 3), "Natural roll respects tier gate")
					if not witnesses.has(affix.id): witnesses[affix.id] = {"seed": 720046 + level, "ordinal": index, "item": item, "post_rng_state": str(rng.state)}
		_expect(level_seen.has_all(Profile.AFFIX_IDS), "All four new families have natural witnesses at each level boundary")
	for id: String in Profile.AFFIX_IDS:
		for tier: int in [1, 2, 3]: _expect(seen.has(id + ":" + str(tier)), "All twelve new family-tier pairs have natural witnesses")
	var now := _rng(460072); var mirror := _rng(460072)
	var current_seen: Dictionary = {}
	for index: int in range(256):
		var roll: int = mirror.randi_range(1, 100)
		var selected := ""
		for entry: Dictionary in Catalog.current_loot_profile():
			roll -= int(entry.weight)
			if roll <= 0: selected = entry.pool_id; break
		var expected: Dictionary = Catalog.generate_for_pool(mirror, "gear_000721", 16, "rare", selected)
		var actual: Dictionary = Catalog.generate_current_loot(now, "gear_000721", 16, "rare")
		_same([actual, now.state], [expected, mirror.state], "Current dispatcher preserves weighted selection and post-roll RNG")
		for id: String in Profile.AFFIX_IDS:
			if _has(actual, id): current_seen[id] = true
	_expect(current_seen.has_all(Profile.AFFIX_IDS), "All new families reach canonical current loot")
	completed = true


func _crafting() -> void:
	_same(Craft.operation_ids(), OldCraft.operation_ids(), "Existing six operations and four targets are unchanged")
	var seen: Dictionary = {}
	seed(720046); var next_global: int = randi(); seed(720046)
	for base: String in [Profile.GLOVE_BASE_ID, Profile.RING_BASE_ID]:
		var added: String = "glove_accuracy" if base == Profile.GLOVE_BASE_ID else "ring_emberward"
		var magic: Dictionary = _item(base, [added])
		var full: Dictionary = _item(base, PREFIXES + RING_SUFFIXES if base == Profile.RING_BASE_ID else ["glove_accuracy", PREFIXES[0], PREFIXES[1], "nine_slot_suffix_endurance", "global_critical_chance", "global_critical_multiplier"], "rare")
		var augment: Dictionary = _item(base, [PREFIXES[0]] if base == Profile.RING_BASE_ID else ["nine_slot_suffix_stride"])
		var sources := {"enchant": _item(base, [], "normal"), "elevate": magic, "augment": augment, "reforge": full}
		var costs := {"enchant": 8, "elevate": 24, "augment": 6, "reforge": 28}
		_expect(Craft.operation_plan(full, "salvage", 0).materials == {"calibration_shard": 21}, "Six T3 affixes retain21shard salvage")
		var recalibrated: Dictionary = Craft.operation_plan(full, "recalibrate", -72)
		_expect(recalibrated.ok and recalibrated.cost == {"calibration_shard": 42}, "New affixes use unchanged recalibration pricing")
		for index: int in range(full.affixes.size()):
			_same([recalibrated.instance.affixes[index].id, recalibrated.instance.affixes[index].tier], [full.affixes[index].id, full.affixes[index].tier], "Recalibrate preserves ordered family and tier")
		for operation: String in sources:
			var source: Dictionary = sources[operation]
			var original: PackedByteArray = var_to_bytes(source)
			var quote: Dictionary = Craft.operation_quote(source, operation)
			_expect(quote.ok and quote.cost == {"calibration_shard": costs[operation]} and quote.instance.is_empty(), "Existing operation quote stays economics-only")
			for value: int in range(32):
				var plan: Dictionary = Craft.operation_plan(source, operation, value)
				_expect(plan.ok and Catalog.validate_instance(plan.instance), "Current Craft produces legal items")
				_same(plan, Craft.operation_plan(source, operation, value), "Current Craft keeps deterministic seed replay")
				if operation in ["elevate", "augment"]:
					_same(plan.instance.affixes.slice(0, source.affixes.size()), source.affixes, "Preserving operations retain original roll bytes")
				for affix: Dictionary in plan.instance.affixes:
					if Profile.AFFIX_IDS.has(affix.id): seen[affix.id] = true
			_same(var_to_bytes(source), original, "Pure Craft never mutates its source")
		for operation: String in Targeted.operation_ids():
			var plan: Dictionary = Craft.operation_plan(full, operation, 72)
			if operation == "targeted_reforge_damage":
				_expect(not plan.ok and plan.code == "no_legal_target", "Accuracy and resistances do not become damage targets")
			else:
				_expect(plan.ok and Catalog.validate_instance(plan.instance) and plan.cost == {"calibration_shard": 40}, "Existing target guarantees and pricing still work")
				var guaranteed := false
				for id: String in Targeted.TARGETS[operation].families:
					if _has(plan.instance, id): guaranteed = true
				_expect(guaranteed, "Targeted reforge contains its promised family")
	_expect(seen.has_all(Profile.AFFIX_IDS), "All new families are reachable through existing Craft")
	_expect(randi() == next_global, "Quotes, rejected targets and local Craft plans never consume global RNG")
	completed = true


func _history() -> void:
	# Bounded representative rolls across every frozen pool/profile, with signed
	# seeds and boundary levels. Compare returned bytes AND caller RNG state.
	for method: String in ["pool", "loot"]:
		var ids: Array = Old.pool_profiles().keys() if method == "pool" else Old.loot_profiles().keys()
		for id: String in ids:
			var now := _rng(-720046); var old := _rng(-720046)
			for pair: Array in [[1, "normal"], [8, "magic"], [16, "rare"], [30, ""]]:
				var actual: Dictionary = Catalog.generate_for_pool(now, "gear_000721", pair[0], pair[1], id) if method == "pool" else Catalog.generate_loot_profile(now, "gear_000721", pair[0], pair[1], id)
				var expected: Dictionary = Old.generate_for_pool(old, "gear_000721", pair[0], pair[1], id) if method == "pool" else Old.generate_loot_profile(old, "gear_000721", pair[0], pair[1], id)
				_same([actual, now.state], [expected, old.state], "Frozen generation item and post-RNG state are byte-exact")
				historical_rolls += 1
	for base: String in Old.all_base_ids():
		var normal: Dictionary = _item(base, [], "normal")
		var magic: Dictionary = OldCraft.operation_plan(normal, "enchant", 72).instance
		for version: int in range(1, 46):
			_same(Catalog.pool_for_base_version(base, version), Old.pool_for_base_version(base, version), "Every pre46 pool lookup stays frozen")
			_expect(Catalog.validate_instance_for_version(magic, version) == Old.validate_instance_for_version(magic, version), "Every pre46 vocabulary preserves acceptance/rejection")
		for operation: String in Craft.operation_ids():
			var source: Dictionary = normal if operation == "enchant" else magic
			_same(Craft.operation_plan(source, operation, -72, 39), OldCraft.operation_plan(source, operation, -72, 39), "Explicit39 full Craft result stays byte-exact on every base/operation")
			historical_plans += 1
			if base not in [Profile.GLOVE_BASE_ID, Profile.RING_BASE_ID] or operation in ["salvage", "recalibrate"]:
				_same(Craft.operation_plan(source, operation, 0), OldCraft.operation_plan(source, operation, 0), "Unchanged current bases and fixed-family operations retain original seed result")
				historical_plans += 1
	# The modified five-base dispatch must still give byte-identical other-base
	# rolls when the same seed selects boots, belt or helmet.
	for value: int in range(24):
		var now := _rng(value); var old := _rng(value)
		var expected: Dictionary = Old.generate_for_pool(old, "gear_000721", 16, "rare", "build_nine_slot_v27")
		var actual: Dictionary = Catalog.generate_for_pool(now, "gear_000721", 16, "rare", "build_nine_slot_v46")
		if expected.base_id not in [Profile.GLOVE_BASE_ID, Profile.RING_BASE_ID]:
			_same([actual, now.state], [expected, old.state], "Other three current five-slot bases retain item and RNG bytes")
			historical_rolls += 1
	for version: int in range(1, 46):
		for base: String in [Profile.GLOVE_BASE_ID, Profile.RING_BASE_ID, "emberhide_vest"]:
			var source: Dictionary = _item(base, [], "normal")
			for operation: String in ["enchant", "targeted_reforge_damage"]:
				_same(Craft.operation_quote(source, operation, version), OldCraft.operation_quote(source, operation, version), "Historical quotes preserve original admission and reasons")
				_same(Craft.operation_plan(source, operation, 72, version), OldCraft.operation_plan(source, operation, 72, version), "All historical vocabularies preserve accepted and rejected plans")
				historical_plans += 1
	for version: int in [35, 36, 38, 40, 41, 42, 43, 44, 45, 47, 999]:
		var source: Dictionary = _item(Profile.RING_BASE_ID, [PREFIXES[0]])
		_expect(not Catalog.validate_instance(source, version) and not Catalog.validate_instance_for_version(source, version), "Source-only and unknown explicit vocabularies remain rejected")
		for operation: String in Craft.operation_ids():
			_same(Craft.operation_plan(source, operation, 72, version), OldCraft.operation_plan(source, operation, 72, version), "Every operation retains the same invalid-vocabulary rejection envelope")
			historical_plans += 1
	for operation: String in Craft.operation_ids():
		_expect(Craft.seed_rules_version(operation) == OldCraft.seed_rules_version(operation), "Current deterministic seed namespace is unchanged")
	completed = true
