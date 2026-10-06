extends SceneTree
## Focused vocabulary39 proof: authored metadata, admission, pure consumers,
## natural rolls and Craft. No save, scene, UI or long-running simulation.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Profile = preload("res://scripts/items/defense_rating_affix_profile.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Hit = preload("res://scripts/combat/attack_hit_rules.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Expand = preload("res://scripts/items/crafting_expansion_rules.gd")
const Targeted = preload("res://scripts/items/targeted_reforge_rules.gd")
const Old = preload("res://docs/qa/v062-rules/frozen/scripts/items/equipment_catalog.gd")
const OldCraft = preload("res://docs/qa/v062-rules/frozen/scripts/items/crafting_rules.gd")
const LEVELS: Array[int] = [1, 7, 8, 15, 16, 30]
const FULL_IDS: Array[String] = ["rootwell", "ironhide", "mistweave", "emberward", "rimeward", "stormward"]
const PREFIX_IDS: Array[String] = ["rootwell", "deepwell", "lanternveil", "ironhide", "mistweave"]
var checks: int = 0
var failures: int = 0
var old_rolls: int = 0
var old_crafts: int = 0
var completed: bool = false
var witnesses: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_metadata, _admission, _derived_consumers, _natural_generation, _crafting, _historical_generation, _historical_crafting]:
		completed = false
		test.call()
		_expect(completed, "Case completes without exceptions: " + test.get_method())
	var report := {"checks": checks, "failures": failures, "old_item_and_rng_comparisons": old_rolls,
		"old_craft_plan_comparisons": old_crafts, "witnesses": witnesses}
	var path: String = OS.get_environment("DEFENSE_RATING_REPORT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		_expect(file != null, "Result report is writable")
		report.checks = checks; report.failures = failures
		if file != null: file.store_string(JSON.stringify(report, "\t") + "\n"); file.close()
	print("Defense rating affixes: %d checks, %d failures; %d old item+RNG comparisons, %d old Craft plans" % [checks, failures, old_rolls, old_crafts])
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


func _item(rarity: String = "normal", ids: Array = [], level: int = 16, tier: int = 3, base_id: String = "emberhide_vest") -> Dictionary:
	var affixes: Array = []
	for id: String in ids:
		var budget: Dictionary = Catalog.affix_definition(id).tiers[tier - 1]
		affixes.append({"id": id, "tier": tier, "value": int(budget.max)})
	return {"id": "gear_000621", "base_id": base_id, "rarity": rarity, "item_level": level, "affixes": affixes}


func _has(item: Dictionary, id: String) -> bool:
	for affix: Dictionary in item.affixes:
		if affix.id == id: return true
	return false


func _metadata() -> void:
	_expect(Catalog.CURRENT_VOCABULARY == 39 and Catalog.CURRENT_LOOT_PROFILE_ID == "canonical_v39" and Catalog.CANONICAL_LOOT_PROFILE_ID == "canonical_v39" and Catalog.CURRENT_DEFENSE_POOL_ID == "defense_v39", "All current selectors are explicit39")
	_same(Catalog.all_base_ids(), Old.all_base_ids(), "No new bases or slots")
	_same(Catalog.all_affix_ids(), Old.all_affix_ids() + Profile.AFFIX_IDS, "Exactly two appended families")
	_same(Catalog.DEFENSE_BASES, Old.DEFENSE_BASES, "Frozen intrinsic fire15 and base metadata")
	_same(Catalog.DEFENSE_AFFIXES, Old.DEFENSE_AFFIXES, "Frozen fire family")
	_same(Catalog.RARITIES, Old.RARITIES, "Unchanged0/1-2/4-6 and prefix/suffix budgets")
	for id: String in Old.all_base_ids(): _same(Catalog.base_definition(id), Old.base_definition(id), "All old bases remain byte-exact")
	for id: String in Old.all_affix_ids(): _same(Catalog.affix_definition(id), Old.affix_definition(id), "All old families remain byte-exact")
	for id: String in Old.pool_profiles():
		_same(Catalog.pool_profile(id), Old.pool_profile(id), "All old ordered pool records are frozen")
		for added: String in Profile.AFFIX_IDS: _expect(not Catalog.pool_profile(id).affix_ids.has(added), "No historical pool contains new families")
	for id: String in Old.loot_profiles(): _same(Catalog.loot_profile(id), Old.loot_profile(id), "All historical loot profiles are frozen")
	var expected: Array[Dictionary] = Old.loot_profile("canonical_v37")
	expected[2].pool_id = "defense_v39"
	_same(Catalog.current_loot_profile(), expected, "Only the10% defense dispatch changes; order and all six weights stay fixed")
	_same(Profile.POOL_PROFILE.affix_ids, Old.pool_profile("defense_v37").affix_ids + ["ironhide", "mistweave"], "Eleven frozen37 ordered families then two new prefixes")
	var bounds := {"ironhide": [[30, 50], [55, 80], [85, 120]], "mistweave": [[200, 260], [270, 350], [360, 450]]}
	for id: String in Profile.AFFIX_IDS:
		var family: Dictionary = Catalog.affix_definition(id)
		_expect(Profile.valid_family(family), "New metadata has only the supported rating semantics")
		for index: int in range(3):
			_same(family.tiers[index], {"tier": index + 1, "level": [1, 8, 16][index], "weight": [100, 60, 30][index], "min": bounds[id][index][0], "max": bounds[id][index][1]}, "Authored integer ranges/gates/weights")
		for base: String in Catalog.all_base_ids(): _expect(Catalog.family_eligible(id, base) == (base == "emberhide_vest"), "New family exclusive to emberhide/body armour")
		for change: Dictionary in [{"stat": "max_shield"}, {"stat": "armour_increased"}, {"stat": "evasion_increased"}, {"group": "life_capacity"}, {"unit": "percent"}, {"kind": "suffix"}, {"scope": "equipped_weapon"}, {"stage": "burning"}, {"actors": ["player"]}, {"slots": ["charm"]}, {"allowed_base_ids": ["woven_bastion"]}]:
			var invalid: Dictionary = family.duplicate(true)
			invalid.merge(change, true)
			_expect(not Profile.valid_family(invalid), "Unsupported rating-family semantics fail closed")
		family.tiers[0].min = 999; family.allowed_base_ids.clear()
		_expect(Catalog.affix_definition(id).tiers[0].min == bounds[id][0][0] and Catalog.family_eligible(id, "emberhide_vest"), "Metadata reads are deeply detached")
	for version: int in range(1, 39): _expect(Catalog.pool_for_base_version("emberhide_vest", version) == Old.pool_for_base_version("emberhide_vest", version), "Every explicit old version retains exact pool lookup including37/38")
	_expect(Catalog.current_pool_for_base("emberhide_vest") == "defense_v39" and Catalog.pool_for_base("emberhide_vest") == "defense", "Current pool advances while original base lookup stays frozen")
	completed = true


func _admission() -> void:
	for id: String in Profile.AFFIX_IDS:
		for level: int in LEVELS:
			for tier: int in [1, 2, 3]:
				var budget: Dictionary = Catalog.affix_definition(id).tiers[tier - 1]
				for value: int in [int(budget.min), int(budget.max)]:
					var item: Dictionary = _item("magic", [id], level, tier)
					item.affixes[0].value = value
					_expect(Catalog.validate_instance(item) == (level >= budget.level), "Both roll endpoints obey ilvl1/7/8/15/16/30 tier gates")
				for invalid: Variant in [int(budget.min) - 1, int(budget.max) + 1, float(budget.min) + 0.5, true, str(budget.min), NAN, INF]:
					var item: Dictionary = _item("magic", [id], level, tier); item.affixes[0].value = invalid
					_expect(not Catalog.validate_instance(item), "Out-of-range, fractional or malformed ticks reject")
		var json_item: Dictionary = JSON.parse_string(JSON.stringify(_item("magic", [id])))
		_expect(Catalog.validate_instance(json_item), "Integral JSON numeric ticks validate")
		for base: String in Catalog.all_base_ids():
			if base != "emberhide_vest": _expect(not Catalog.validate_instance(_item("magic", [id], 16, 3, base)), "Instance validation rejects every other base")
		for version: int in range(1, 39): _expect(not Catalog.validate_instance_for_version(_item("magic", [id]), version), "New prefix rejects all historical equipment vocabularies")
		var duplicate: Dictionary = _item("rare", ["rootwell", id, id, "emberward"])
		_expect(not Catalog.validate_instance(duplicate), "Duplicate family/group rejects")
		var kept: Array = _item("magic", [id]).affixes
		for candidate: Dictionary in Expand._pool("emberhide_vest", 30, kept): _expect(candidate.group != Catalog.affix_definition(id).group, "Every tier of a retained group is excluded from Craft")
	_expect(not Catalog.validate_instance(_item("magic", ["ironhide", "mistweave"])), "Magic cannot carry two prefixes")
	_expect(Catalog.validate_instance(_item("magic", ["ironhide", "rimeward"])), "Magic accepts one rating prefix and one existing suffix")
	_expect(not Catalog.validate_instance(_item("rare", ["rootwell", "deepwell", "ironhide", "mistweave", "emberward"])), "Rare cannot carry four prefixes")
	_expect(not Catalog.validate_instance(_item("rare", ["ironhide", "emberward", "rimeward", "stormward", "wellturn"])), "Rare cannot carry four suffixes")
	var combinations: int = 0
	for first: int in range(5):
		for second: int in range(first + 1, 5):
			for third: int in range(second + 1, 5):
				var ids: Array = [PREFIX_IDS[first], PREFIX_IDS[second], PREFIX_IDS[third], "emberward", "rimeward", "stormward"]
				var full: Dictionary = _item("rare", ids)
				_expect(Catalog.validate_instance(full), "Every choice of three from five prefixes is legal with3suffixes")
				_expect(not Craft.operation_quote(full, "augment").ok, "Every legal six-affix combination stays full")
				combinations += 1
	_expect(combinations == 10, "All ten distinct full-cap prefix combinations checked")
	var prefix_ids: Array[String] = []
	for row: Dictionary in Catalog._profile_eligible_tiers("emberhide_vest", 16, "prefix", Profile.POOL_PROFILE):
		if not prefix_ids.has(row.id): prefix_ids.append(row.id)
	_same(prefix_ids, PREFIX_IDS, "Five ordered eligible prefixes compete for the unchanged three-prefix cap")
	for version: int in [35, 36, 38, 40, 999]:
		_expect(not Catalog.validate_instance_for_version(_item(), version) and not Catalog.validate_instance(_item(), version), "Unknown/source-only explicit equipment vocabulary remains rejected")
	completed = true


func _derived_consumers() -> void:
	var full: Dictionary = _item("rare", FULL_IDS)
	var original: PackedByteArray = var_to_bytes(full)
	var stats: Dictionary = Catalog.get_stats(full)
	_same(stats, {"max_health": 40.0, "fire_resistance": 0.4, "armour": 120.0, "evasion": 450.0, "cold_resistance": 0.25, "lightning_resistance": 0.25}, "Actual two rating families become same-valued float points exactly once")
	for pair: Array in [["ironhide", "护甲", 120], ["mistweave", "闪避值", 450]]:
		var affix := {"id": pair[0], "tier": 3, "value": pair[2]}
		var display: Dictionary = Catalog.affix_display(affix)
		_expect(display.ok and display.label == pair[1] and display.value_text == "+" + str(pair[2]) and display.line == pair[1] + " +" + str(pair[2]), "Formatter shows flat points without percentage or division")
		_expect(Catalog.affix_stat_value(Catalog.affix_definition(pair[0]), pair[2]) == float(pair[2]), "Flat tick conversion is identity")
	var definition: Dictionary = Catalog.definition(full)
	_same(definition.stats, stats, "Definition uses the canonical validated stats")
	_expect(definition.description.contains("护甲 +120") and definition.description.contains("闪避值 +450"), "Derived definition uses canonical rating formatter")
	for actor: String in ["player", "monster"]:
		var profile: Dictionary = Defense.source_profile(stats, actor)
		_expect(profile.ok and profile.armour == 120.0, "Actual source consumer receives120armour points")
		var hit: Dictionary = Defense.incoming_source_hit({"physical": 100.0}, stats, 0.0, 1000.0, actor)
		_expect(hit.ok and is_equal_approx(hit.damage_total, 100.0 * (1.0 - 120.0 / 620.0)), "Actual physical hit uses rating as points in hit-size formula")
	var chance: float = Hit.chance(100.0, stats.evasion)
	_expect(chance > 0.0 and chance < Hit.chance(100.0, 0.0), "Actual attack admission uses450evasion points")
	_expect(Hit.resolve(100.0, stats.evasion, 50.0).ok, "Rating passes actual attack admission validation")
	_same(var_to_bytes(full), original, "Derivation and consumers never mutate the item")
	witnesses["six_affix_maximum"] = {"instance": full, "stats": stats, "hit_chance_against_accuracy100": chance}
	completed = true


func _natural_generation() -> void:
	var seen: Dictionary = {}
	for level: int in LEVELS:
		var level_seen: Dictionary = {}
		for rarity: String in ["normal", "magic", "rare"]:
			var rng := _rng(620000 + level)
			var counts: Dictionary = {}
			for index: int in range(96):
				var item: Dictionary = Catalog.generate_for_pool(rng, "gear_000621", level, rarity, "defense_v39")
				_expect(Catalog.validate_instance(item), "Every natural rarity roll validates")
				counts[item.affixes.size()] = true
				for affix: Dictionary in item.affixes:
					if Profile.AFFIX_IDS.has(affix.id):
						level_seen[affix.id] = true
						seen[affix.id + ":" + str(affix.tier)] = true
						_expect(int(affix.tier) <= (1 if level < 8 else 2 if level < 16 else 3), "Natural prefix respects tier gate")
				if item.affixes.size() == 6 and _has(item, "ironhide") and _has(item, "mistweave"):
					witnesses["natural_six_affix"] = {"seed": 620000 + level, "ordinal": index, "instance": item, "post_rng_state": str(rng.state)}
			for count: int in range(Catalog.RARITIES[rarity].min_affixes, Catalog.RARITIES[rarity].max_affixes + 1): _expect(counts.has(count), "Every rarity count remains reachable")
		_expect(level_seen.has_all(Profile.AFFIX_IDS), "Both new families naturally reach every level boundary")
	for id: String in Profile.AFFIX_IDS:
		for tier: int in [1, 2, 3]: _expect(seen.has(id + ":" + str(tier)), "Each new tier has a natural-roll witness")
	_expect(witnesses.has("natural_six_affix"), "Natural rare generation reaches both rating prefixes with six affixes")
	var rng := _rng(620039)
	var mirror := _rng(620039)
	var current_seen: Dictionary = {}
	for index: int in range(256):
		var roll: int = mirror.randi_range(1, 100)
		var selected := ""
		for entry: Dictionary in Catalog.current_loot_profile():
			roll -= entry.weight
			if roll <= 0: selected = entry.pool_id; break
		var expected: Dictionary = Catalog.generate_for_pool(mirror, "gear_000621", 16, "rare", selected)
		var actual: Dictionary = Catalog.generate_current_loot(rng, "gear_000621", 16, "rare")
		_same([actual, rng.state], [expected, mirror.state], "Current loot uses unchanged weighted dispatch algorithm")
		for id: String in Profile.AFFIX_IDS:
			if _has(actual, id): current_seen[id] = true
	_expect(current_seen.has_all(Profile.AFFIX_IDS), "Canonical39 natural rewards expose both new families")
	completed = true


func _crafting() -> void:
	var full: Dictionary = _item("rare", FULL_IDS)
	var original: PackedByteArray = var_to_bytes(full)
	var salvage: Dictionary = Craft.operation_plan(full, "salvage", 0)
	_expect(salvage.ok and salvage.materials == {"calibration_shard": 21} and salvage.consumes_item, "Six T3 affixes retain21-shard salvage formula")
	var calibration: Dictionary = Craft.operation_plan(full, "recalibrate", 4927)
	_expect(calibration.ok and calibration.cost == {"calibration_shard": 42}, "Recalibration keeps original42-shard cost")
	for index: int in range(full.affixes.size()):
		_expect(calibration.instance.affixes[index].id == full.affixes[index].id and calibration.instance.affixes[index].tier == 3, "Recalibration preserves ordered families and tiers")
	_expect(not Craft.operation_quote(full, "augment").ok, "Full six-affix rare cannot augment")
	var sources := {"enchant": _item(), "elevate": _item("magic", ["emberward"]), "augment": _item("rare", ["rootwell", "deepwell", "emberward", "rimeward"]), "reforge": full, "targeted_reforge_damage": full}
	var costs := {"enchant": 8, "elevate": 24, "augment": 6, "reforge": 28, "targeted_reforge_damage": 40}
	seed(620039); var expected_global: int = randi(); seed(620039)
	for operation: String in Craft.operation_ids():
		var quoted: Dictionary = Craft.operation_quote(sources.get(operation, full), operation)
		_expect(quoted.instance.is_empty() and quoted.definition.is_empty(), "Quotes do not roll or expose a replacement")
	_expect(randi() == expected_global, "All successful and rejected quotes preserve global RNG")
	seed(620039)
	for operation: String in sources:
		var seen: Dictionary = {}
		for value: int in range(128):
			var result: Dictionary = Craft.operation_plan(sources[operation], operation, value)
			_expect(result.ok and result.cost == {"calibration_shard": costs[operation]} and Catalog.validate_instance(result.instance), "All existing allocating operations accept current vocabulary with frozen costs")
			for id: String in Profile.AFFIX_IDS:
				if _has(result.instance, id): seen[id] = true
			if operation in ["elevate", "augment"]:
				_same(result.instance.affixes.slice(0, sources[operation].affixes.size()), sources[operation].affixes, "Retained affixes keep original identity/tier/ticks")
			if operation == "targeted_reforge_damage":
				var damage: bool = _has(result.instance, "coalglow") or _has(result.instance, "rimeecho") or _has(result.instance, "sparkthread")
				_expect(damage and not (_has(result.instance, "emberward") and _has(result.instance, "rimeward") and _has(result.instance, "stormward")), "Damage targeting reserves a damage suffix so triple-resistance is unreachable")
		_expect(seen.has_all(Profile.AFFIX_IDS), "Both new families are reachable through " + operation)
		witnesses[operation + "_new_families"] = seen.keys()
	_expect(randi() == expected_global, "Pure Craft operations preserve global RNG")
	for id: String in Profile.AFFIX_IDS:
		var magic: Dictionary = _item("magic", [id])
		var elevated: Dictionary = Craft.operation_plan(magic, "elevate", 620)
		_expect(elevated.ok and Catalog.validate_instance(elevated.instance), "An existing new-family magic item can elevate")
		_same(elevated.instance.affixes[0], magic.affixes[0], "Elevating an existing rating retains exact family/tier/points")
		var augmented: Dictionary = Craft.operation_plan(magic, "augment", 620)
		_expect(augmented.ok and Catalog.validate_instance(augmented.instance), "A magic rating prefix leaves only one suffix slot")
		_expect(Catalog.affix_definition(augmented.instance.affixes[1].id).kind == "suffix", "Magic augmentation cannot add a second prefix")
	for operation: String in ["targeted_reforge_critical", "targeted_reforge_life_leech", "targeted_reforge_mana_leech"]:
		_expect(Craft.operation_quote(full, operation).code == "no_legal_target", "Other targets remain unavailable on emberhide")
	_same(var_to_bytes(full), original, "Quotes/plans never mutate source item")
	completed = true


func _historical_generation() -> void:
	for method: String in ["pool", "loot_profile"]:
		var ids: Array = Old.pool_profiles().keys() if method == "pool" else Old.loot_profiles().keys()
		for id: String in ids:
			for seed_value: int in [0, 4927, -817]:
				var now := _rng(seed_value); var before := _rng(seed_value)
				for level: int in LEVELS:
					for rarity: String in ["", "normal", "magic", "rare"]:
						var actual: Dictionary = Catalog.generate_for_pool(now, "gear_000621", level, rarity, id) if method == "pool" else Catalog.generate_loot_profile(now, "gear_000621", level, rarity, id)
						var expected: Dictionary = Old.generate_for_pool(before, "gear_000621", level, rarity, id) if method == "pool" else Old.generate_loot_profile(before, "gear_000621", level, rarity, id)
						_same([actual, now.state], [expected, before.state], "Every frozen pool/profile item and post-RNG state remains byte-exact")
						old_rolls += 1
						for added: String in Profile.AFFIX_IDS: _expect(not _has(actual, added), "Historical generation never gains armour/evasion rating prefixes")
	for methods: Array in [[Catalog.generate, Old.generate], [Catalog.generate_expanded, Old.generate_expanded], [Catalog.generate_loot, Old.generate_loot]]:
		var now := _rng(-620); var before := _rng(-620)
		for level: int in LEVELS:
			_same([methods[0].call(now, "gear_000621", level, "rare"), now.state], [methods[1].call(before, "gear_000621", level, "rare"), before.state], "Legacy adapters preserve item and RNG bytes")
			old_rolls += 1
	completed = true


func _historical_crafting() -> void:
	for base: String in Old.all_base_ids():
		var normal: Dictionary = _item("normal", [], 16, 3, base)
		var magic: Dictionary = OldCraft.operation_plan(normal, "enchant", 621, 37).instance
		var rare: Dictionary = OldCraft.operation_plan(magic, "elevate", 622, 37).instance
		for source: Dictionary in [normal, magic, rare]:
			for operation: String in Craft.operation_ids():
				for value: int in [0, -817]:
					_same(Craft.operation_plan(source, operation, value, 37), OldCraft.operation_plan(source, operation, value, 37), "Explicit37 Craft preserves full typed envelope for every base/rarity/operation")
					old_crafts += 1
				if base != "emberhide_vest" or operation in ["salvage", "recalibrate"]:
					_same(Craft.operation_plan(source, operation, 4927), OldCraft.operation_plan(source, operation, 4927), "Unchanged current pools and legacy salvage/calibration retain default plan bytes")
					old_crafts += 1
	var sources: Array = [_item(), _item("magic", ["emberward"]), _item("magic", ["rimeward"]), _item("rare", ["rootwell", "deepwell", "lanternveil", "emberward", "rimeward", "stormward"])]
	for version: int in range(1, 39):
		for source: Dictionary in sources:
			_expect(Catalog.validate_instance_for_version(source, version) == Old.validate_instance_for_version(source, version), "Every explicit old vocabulary preserves acceptance/rejection, including35/36/38")
			for operation: String in Craft.operation_ids():
				_same(Craft.operation_quote(source, operation, version), OldCraft.operation_quote(source, operation, version), "Explicit1..38 preserve typed economics-only quotes")
				_same(Craft.operation_plan(source, operation, 4927, version), OldCraft.operation_plan(source, operation, 4927, version), "Explicit1..38 preserve exact Craft results, including source-only35/36/38 rejection")
				_expect(Craft.seed_rules_version(operation, version) == OldCraft.seed_rules_version(operation, version), "Historical deterministic seed namespace is unchanged")
				old_crafts += 1
	for operation: String in Craft.operation_ids(): _expect(Craft.seed_rules_version(operation) == OldCraft.seed_rules_version(operation), "Current seed namespaces are unchanged")
	completed = true
