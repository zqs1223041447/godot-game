extends SceneTree
## Focused vocabulary37 proof: authored metadata, admission, pure consumers,
## natural rolls and Craft. No save, scene, UI or long-running simulation.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Profile = preload("res://scripts/items/elemental_defense_affix_profile.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Expand = preload("res://scripts/items/crafting_expansion_rules.gd")
const Targeted = preload("res://scripts/items/targeted_reforge_rules.gd")
const Old = preload("res://docs/qa/v060-rules/frozen/equipment_catalog_v059.gd")
const OldCraft = preload("res://docs/qa/v060-rules/frozen/crafting_rules_v059.gd")
const LEVELS: Array[int] = [1, 7, 8, 15, 16, 30]
const FULL_IDS: Array[String] = ["rootwell", "deepwell", "lanternveil", "emberward", "rimeward", "stormward"]
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
	var path: String = OS.get_environment("ELEMENTAL_AFFIX_REPORT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		_expect(file != null, "Result report is writable")
		report.checks = checks; report.failures = failures
		if file != null: file.store_string(JSON.stringify(report, "\t") + "\n"); file.close()
	print("Elemental defense affixes: %d checks, %d failures; %d old item+RNG comparisons, %d old Craft plans" % [checks, failures, old_rolls, old_crafts])
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
	return {"id": "gear_000601", "base_id": base_id, "rarity": rarity, "item_level": level, "affixes": affixes}


func _has(item: Dictionary, id: String) -> bool:
	for affix: Dictionary in item.affixes:
		if affix.id == id: return true
	return false


func _metadata() -> void:
	_expect(Catalog.CURRENT_VOCABULARY == 37 and Catalog.CURRENT_LOOT_PROFILE_ID == "canonical_v37" and Catalog.CANONICAL_LOOT_PROFILE_ID == "canonical_v37" and Catalog.CURRENT_DEFENSE_POOL_ID == "defense_v37", "All current selectors are explicit37")
	_same(Catalog.all_base_ids(), Old.all_base_ids(), "No new bases or slots")
	_same(Catalog.all_affix_ids(), Old.all_affix_ids() + Profile.AFFIX_IDS, "Exactly two appended families")
	_same(Catalog.DEFENSE_BASES, Old.DEFENSE_BASES, "Frozen intrinsic fire15 and base metadata")
	_same(Catalog.DEFENSE_AFFIXES, Old.DEFENSE_AFFIXES, "Frozen fire family")
	_same(Catalog.RARITIES, Old.RARITIES, "Unchanged 0/1-2/4-6 and prefix/suffix budgets")
	for id: String in Old.all_base_ids(): _same(Catalog.base_definition(id), Old.base_definition(id), "All old bases remain byte-exact")
	for id: String in Old.all_affix_ids(): _same(Catalog.affix_definition(id), Old.affix_definition(id), "All old families remain byte-exact")
	for id: String in Old.pool_profiles():
		_same(Catalog.pool_profile(id), Old.pool_profile(id), "All old ordered pool records are frozen")
		for added: String in Profile.AFFIX_IDS: _expect(not Catalog.pool_profile(id).affix_ids.has(added), "No historical pool contains new families")
	for id: String in Old.loot_profiles(): _same(Catalog.loot_profile(id), Old.loot_profile(id), "All historical loot profiles are frozen")
	var expected: Array[Dictionary] = Old.loot_profile("canonical_v34")
	expected[2].pool_id = "defense_v37"
	_same(Catalog.current_loot_profile(), expected, "Only the10% defense dispatch changes; order and all six weights stay fixed")
	_same(Profile.POOL_PROFILE.affix_ids, Old.pool_profile("defense").affix_ids + ["rimeward", "stormward"], "Nine old ordered families then two new suffixes")
	for id: String in Profile.AFFIX_IDS:
		var family: Dictionary = Catalog.affix_definition(id)
		_expect(Profile.valid_family(family), "New metadata closes over actual source consumers")
		_same(family.tiers, Old.affix_definition("emberward").tiers, "Exact fire-mirrored gates/ranges/weights")
		for base: String in Catalog.all_base_ids(): _expect(Catalog.family_eligible(id, base) == (base == "emberhide_vest"), "New family exclusive to emberhide/body armour")
		for change: Dictionary in [{"stat": "all_resistance"}, {"stat": "maximum_cold_resistance_add"}, {"stat": "fire_resistance"}, {"group": "fire_resistance"}, {"unit": "flat"}, {"kind": "prefix"}, {"scope": "equipped_weapon"}, {"stage": "burning"}, {"damage_type": "fire"}, {"actors": ["player"]}, {"slots": ["charm"]}, {"allowed_base_ids": ["woven_bastion"]}]:
			var invalid: Dictionary = family.duplicate(true)
			invalid.merge(change, true)
			_expect(not Profile.valid_family(invalid), "Unsupported elemental-family semantics fail closed")
		family.tiers[0].min = 999; family.allowed_base_ids.clear()
		_expect(Catalog.affix_definition(id).tiers[0].min == 8 and Catalog.family_eligible(id, "emberhide_vest"), "Metadata reads are deeply detached")
	for version: int in range(1, 37): _expect(Catalog.pool_for_base_version("emberhide_vest", version) == "defense", "Every explicit old version keeps its old pool lookup")
	_expect(Catalog.current_pool_for_base("emberhide_vest") == "defense_v37" and Catalog.pool_for_base("emberhide_vest") == "defense", "Current pool advances while original base lookup stays frozen")
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
		for invalid: Variant in [18, 26, 24.5, true, "25", NAN, INF]:
			var item: Dictionary = _item("magic", [id]); item.affixes[0].value = invalid
			_expect(not Catalog.validate_instance(item), "Out-of-range, fractional or malformed ticks reject")
		var json_item: Dictionary = JSON.parse_string(JSON.stringify(_item("magic", [id])))
		_expect(Catalog.validate_instance(json_item), "Integral JSON numeric ticks validate")
		for base: String in Catalog.all_base_ids():
			if base != "emberhide_vest": _expect(not Catalog.validate_instance(_item("magic", [id], 16, 3, base)), "Instance validation rejects every other base")
		for version: int in range(1, 37): _expect(not Catalog.validate_instance_for_version(_item("magic", [id]), version), "New suffix rejects all historical equipment vocabularies")
		var duplicate: Dictionary = _item("rare", ["rootwell", "deepwell", id, id])
		_expect(not Catalog.validate_instance(duplicate), "Duplicate family/group rejects")
		var kept: Array = _item("magic", [id]).affixes
		for candidate: Dictionary in Expand._pool("emberhide_vest", 30, kept): _expect(candidate.group != Catalog.affix_definition(id).group, "Every tier of a retained group is excluded from Craft")
	_expect(not Catalog.validate_instance(_item("magic", ["rimeward", "stormward"])), "Magic cannot carry two suffixes")
	_expect(not Catalog.validate_instance(_item("rare", ["rootwell", "emberward", "rimeward", "stormward", "wellturn"])), "Rare cannot carry four suffixes")
	_expect(Catalog.validate_instance(_item("rare", FULL_IDS)), "Six-affix3prefix3suffix tri-resistance witness validates")
	for version: int in [35, 36, 38, 999]:
		_expect(not Catalog.validate_instance_for_version(_item(), version) and not Catalog.validate_instance(_item(), version), "Unknown/source-only explicit equipment vocabulary remains rejected")
	completed = true


func _derived_consumers() -> void:
	var full: Dictionary = _item("rare", FULL_IDS)
	var original: PackedByteArray = var_to_bytes(full)
	var stats: Dictionary = Catalog.get_stats(full)
	_same(stats, {"max_health": 40.0, "fire_resistance": 0.4, "max_mana": 22.0, "max_shield": 22.0, "cold_resistance": 0.25, "lightning_resistance": 0.25}, "Six-affix maxima derive40/25/25 raw once; no extra stats")
	for pair: Array in [["rimeward", "冰霜抗性"], ["stormward", "闪电抗性"]]:
		var affix := {"id": pair[0], "tier": 3, "value": 25}
		var display: Dictionary = Catalog.affix_display(affix)
		_expect(display.ok and display.label == pair[1] and display.value_text == "+25%" and display.line == pair[1] + " +25%", "Formatter shows25percent instead of fractional ticks")
		_expect(Catalog.affix_stat_value(Catalog.affix_definition(pair[0]), 25) == 0.25, "Percent converts exactly once")
	_expect(Catalog.definition(full).description.contains("冰霜抗性 +25%") and Catalog.definition(full).description.contains("闪电抗性 +25%"), "Derived definition uses canonical formatter")
	for actor: String in ["player", "monster"]:
		var profile: Dictionary = Defense.source_profile(stats, actor)
		_same(profile.raw_resistances, {"fire": 0.4, "cold": 0.25, "lightning": 0.25}, "Source consumer receives all three raw values")
		_same(profile.effective_resistances, profile.raw_resistances, "Below-cap values apply unchanged")
		var hit: Dictionary = Defense.incoming_source_hit({"fire": 100.0, "cold": 100.0, "lightning": 100.0}, stats, 0.0, 1000.0, actor)
		_expect(hit.ok and hit.damage_total == 210.0 and hit.health_lost == 210.0, "Actual source hit uses60+75+75 after elemental defenses")
		_expect(not Defense.supports_stat("cold_resistance", actor) and not Defense.supports_stat("lightning_resistance", actor), "Frozen supports_stat remains fire-only")
		_expect(not Defense.defense_profile({"cold_resistance": 0.25}, actor).ok, "Frozen defense_profile remains fire-only")
	_same(var_to_bytes(full), original, "Derivation and consumers never mutate the item")
	witnesses["six_affix_maximum"] = {"instance": full, "stats": stats}
	completed = true


func _natural_generation() -> void:
	var seen: Dictionary = {}
	for level: int in LEVELS:
		var level_seen: Dictionary = {}
		for rarity: String in ["normal", "magic", "rare"]:
			var rng := _rng(600000 + level)
			var counts: Dictionary = {}
			for index: int in range(96):
				var item: Dictionary = Catalog.generate_for_pool(rng, "gear_000601", level, rarity, "defense_v37")
				_expect(Catalog.validate_instance(item), "Every natural rarity roll validates")
				counts[item.affixes.size()] = true
				for affix: Dictionary in item.affixes:
					if Profile.AFFIX_IDS.has(affix.id):
						level_seen[affix.id] = true
						seen[affix.id + ":" + str(affix.tier)] = true
						_expect(int(affix.tier) <= (1 if level < 8 else 2 if level < 16 else 3), "Natural suffix respects tier gate")
				if item.affixes.size() == 6 and _has(item, "emberward") and _has(item, "rimeward") and _has(item, "stormward"):
					witnesses["natural_six_affix"] = {"seed": 600000 + level, "ordinal": index, "instance": item, "post_rng_state": str(rng.state)}
			for count: int in range(Catalog.RARITIES[rarity].min_affixes, Catalog.RARITIES[rarity].max_affixes + 1): _expect(counts.has(count), "Every rarity count remains reachable")
		_expect(level_seen.has_all(Profile.AFFIX_IDS), "Both new families naturally reach every level boundary")
	for id: String in Profile.AFFIX_IDS:
		for tier: int in [1, 2, 3]: _expect(seen.has(id + ":" + str(tier)), "Each new tier has a natural-roll witness")
	_expect(witnesses.has("natural_six_affix"), "Natural rare generation reaches all three resistance suffixes")
	var rng := _rng(600037)
	var mirror := _rng(600037)
	var current_seen: Dictionary = {}
	for index: int in range(256):
		var roll: int = mirror.randi_range(1, 100)
		var selected := ""
		for entry: Dictionary in Catalog.current_loot_profile():
			roll -= entry.weight
			if roll <= 0: selected = entry.pool_id; break
		var expected: Dictionary = Catalog.generate_for_pool(mirror, "gear_000601", 16, "rare", selected)
		var actual: Dictionary = Catalog.generate_current_loot(rng, "gear_000601", 16, "rare")
		_same([actual, rng.state], [expected, mirror.state], "Current loot uses unchanged weighted dispatch algorithm")
		for id: String in Profile.AFFIX_IDS:
			if _has(actual, id): current_seen[id] = true
	_expect(current_seen.has_all(Profile.AFFIX_IDS), "Canonical37 natural rewards expose both new families")
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
	var sources := {"enchant": _item(), "elevate": _item("magic", ["rimeward"]), "augment": _item("rare", ["rootwell", "deepwell", "lanternveil", "emberward"]), "reforge": full, "targeted_reforge_damage": full}
	var costs := {"enchant": 8, "elevate": 24, "augment": 6, "reforge": 28, "targeted_reforge_damage": 40}
	seed(600037); var expected_global: int = randi(); seed(600037)
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
						var actual: Dictionary = Catalog.generate_for_pool(now, "gear_000601", level, rarity, id) if method == "pool" else Catalog.generate_loot_profile(now, "gear_000601", level, rarity, id)
						var expected: Dictionary = Old.generate_for_pool(before, "gear_000601", level, rarity, id) if method == "pool" else Old.generate_loot_profile(before, "gear_000601", level, rarity, id)
						_same([actual, now.state], [expected, before.state], "Every frozen pool/profile item and post-RNG state remains byte-exact")
						old_rolls += 1
						for added: String in Profile.AFFIX_IDS: _expect(not _has(actual, added), "Historical generation never gains cold/lightning resistance")
	for methods: Array in [[Catalog.generate, Old.generate], [Catalog.generate_expanded, Old.generate_expanded], [Catalog.generate_loot, Old.generate_loot]]:
		var now := _rng(-600); var before := _rng(-600)
		for level: int in LEVELS:
			_same([methods[0].call(now, "gear_000601", level, "rare"), now.state], [methods[1].call(before, "gear_000601", level, "rare"), before.state], "Legacy adapters preserve item and RNG bytes")
			old_rolls += 1
	completed = true


func _historical_crafting() -> void:
	for base: String in Old.all_base_ids():
		var normal: Dictionary = _item("normal", [], 16, 3, base)
		var magic: Dictionary = OldCraft.operation_plan(normal, "enchant", 601, 34).instance
		var rare: Dictionary = OldCraft.operation_plan(magic, "elevate", 602, 34).instance
		for source: Dictionary in [normal, magic, rare]:
			for operation: String in Craft.operation_ids():
				for value: int in [0, -817]:
					_same(Craft.operation_plan(source, operation, value, 34), OldCraft.operation_plan(source, operation, value, 34), "Explicit34 Craft preserves full typed envelope for every base/rarity/operation")
					old_crafts += 1
				if base != "emberhide_vest" or operation in ["salvage", "recalibrate"]:
					_same(Craft.operation_plan(source, operation, 4927), OldCraft.operation_plan(source, operation, 4927), "Unchanged current pools and legacy salvage/calibration retain default plan bytes")
					old_crafts += 1
	var sources: Array = [_item(), _item("magic", ["emberward"]), _item("rare", ["rootwell", "deepwell", "lanternveil", "emberward"])]
	for version: int in range(1, 37):
		for source: Dictionary in sources:
			_expect(Catalog.validate_instance_for_version(source, version) == Old.validate_instance_for_version(source, version), "Every explicit old vocabulary preserves acceptance/rejection, including35/36")
			for operation: String in Craft.operation_ids():
				_same(Craft.operation_plan(source, operation, 4927, version), OldCraft.operation_plan(source, operation, 4927, version), "Explicit1..36 preserve exact Craft results, including source-only35/36 rejection")
				_expect(Craft.seed_rules_version(operation, version) == OldCraft.seed_rules_version(operation, version), "Historical deterministic seed namespace is unchanged")
				old_crafts += 1
	for operation: String in Craft.operation_ids(): _expect(Craft.seed_rules_version(operation) == OldCraft.seed_rules_version(operation), "Current seed namespaces are unchanged")
	completed = true
