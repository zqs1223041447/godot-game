extends SceneTree
## Standalone contract suite; no scene, wallet, save files or generated catalog.
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Weapon = preload("res://scripts/items/weapon_local_rules.gd")
var checks: int = 0
var failures: int = 0
var plans: int = 0
var eligible_pairs: int = 0
var family_tiers: Dictionary = {}
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_metadata, _all_families, _rarities_and_levels, _local_weapon,
			_rejections, _seed_and_rng, _detachment, _economy]:
		completed = false
		test.call()
		_expect(completed, "Case completed without a script exception: " + test.get_method())
	print("Crafting rules: %d bases, %d families, %d eligible pairs, %d family tiers, %d plans; %d checks, %d failures" % [
		Catalog.all_base_ids().size(), Catalog.all_affix_ids().size(), eligible_pairs,
		family_tiers.size(), plans, checks, failures])
	quit(0 if failures == 0 else 1)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _item(base_id: String, level: int, affixes: Array, rarity: String = "magic") -> Dictionary:
	return {"id": "gear_000123", "base_id": base_id, "rarity": rarity,
		"item_level": level, "affixes": affixes.duplicate(true)}


func _roll(id: String, tier: int = 1, maximum: bool = false) -> Dictionary:
	var range_info: Dictionary = Catalog.affix_definition(id).tiers[tier - 1]
	return {"id": id, "tier": tier, "value": range_info.max if maximum else range_info.min}


func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _metadata() -> void:
	var info: Dictionary = Craft.metadata()
	_expect(info.origin == "original" and info.status == "prototype" and not info.mutates_state,
		"Metadata identifies original, pure prototype rules")
	_expect(info.rules_version == Craft.RULES_VERSION and info.catalog_vocabulary == Catalog.CURRENT_VOCABULARY,
		"Metadata identifies exact rule and catalog versions")
	_expect(info.catalog_source == "res://scripts/items/equipment_catalog.gd", "Catalog remains the single content source")
	_expect(info.base_ids == Catalog.all_base_ids() and info.affix_ids == Catalog.all_affix_ids(), "Metadata lists all actual content")
	_expect(info.base_ids.size() == 9 and info.affix_ids.size() == 19, "v0.13 coverage includes nine bases and nineteen families")
	_expect(info.rarities == ["normal", "magic", "rare"] and info.salvage_rarities == ["magic", "rare"] and info.materials.has("calibration_shard"), "Metadata declares supported rarities and material")
	_expect(info.operations.salvage.consumes_item and not info.operations.recalibrate.consumes_item,
		"Salvage consumes an item only when the caller commits")
	_expect(info.operations.recalibrate.can_roll_same_values and info.persistence_owner == "main_integration",
		"Rerolls may match; transaction/persistence ownership is explicit")
	for base_id: String in info.base_ids:
		for id: String in info.affix_ids:
			_expect(info.eligible_families_by_base[base_id].has(id) == Catalog.family_eligible(id, base_id),
				"Metadata eligibility equals the catalog: " + base_id + "/" + id)
	completed = true


func _verify_plan(item: Dictionary, seed_value: int) -> Dictionary:
	var before: PackedByteArray = var_to_bytes(item)
	var result: Dictionary = Craft.recalibrate_plan(item, seed_value)
	plans += 1
	_expect(result.ok and result.code.is_empty() and result.reason.is_empty(), "Valid input produces a complete success")
	if not result.ok:
		return {}
	_expect(var_to_bytes(item) == before, "Input remains byte-identical")
	_expect(result.source_instance == item and result.operation == "recalibrate", "Plan carries an unchanged source snapshot")
	_expect(not result.consumes_item and result.materials.is_empty() and not result.cost.is_empty(), "Recalibration charges only material")
	var output: Dictionary = result.instance
	_expect(output.size() == 5 and Catalog.validate_instance(output), "Output contains only legal canonical fields")
	_expect(Catalog.validate_instance(_json(output)), "Output survives catalog-valid JSON roundtrip")
	for key: String in ["id", "base_id", "rarity", "item_level"]:
		_expect(var_to_bytes(output[key]) == var_to_bytes(item[key]), "Identity and stored level type are preserved: " + key)
	_expect(output.affixes.size() == item.affixes.size(), "No affix is added or removed")
	for index: int in range(item.affixes.size()):
		var old: Dictionary = item.affixes[index]
		var next: Dictionary = output.affixes[index]
		var family: Dictionary = Catalog.affix_definition(old.id)
		var tier: Dictionary = family.tiers[int(old.tier) - 1]
		_expect(next.id == old.id and var_to_bytes(next.tier) == var_to_bytes(old.tier), "Affix order, family and exact tier survive")
		_expect(next.size() == 3 and next.value is int and next.value >= tier.min and next.value <= tier.max,
			"Only integer values inside the ORIGINAL tier may change")
		_expect(Catalog.family_eligible(next.id, output.base_id), "Output family remains eligible")
	_expect(result.definition == Catalog.definition(output), "Preview is derived from the output by the existing catalog")
	_expect(result == Craft.recalibrate_plan(item, seed_value), "Same input and seed reproduce the complete plan")
	_expect(_json(output) == _json(Craft.recalibrate_plan(_json(item), seed_value).instance), "JSON numeric representation preserves rolls")
	var quote: Dictionary = Craft.salvage_quote(item)
	_expect(quote.ok and quote.consumes_item and quote.cost.is_empty(), "Valid affixed item has a free salvage quote")
	_expect(quote.source_instance == item and quote.instance.is_empty() and quote.definition.is_empty(), "Salvage does not invent a replacement")
	_expect(var_to_bytes(item) == before, "Both APIs leave original input untouched")
	return result


func _all_families() -> void:
	var seen_bases: Dictionary = {}
	var seen_families: Dictionary = {}
	for base_id: String in Catalog.all_base_ids():
		for id: String in Catalog.all_affix_ids():
			if not Catalog.family_eligible(id, base_id):
				continue
			eligible_pairs += 1
			seen_bases[base_id] = true
			seen_families[id] = true
			for tier: Dictionary in Catalog.affix_definition(id).tiers:
				family_tiers["%s:%d" % [id, tier.tier]] = true
				for bad_value: int in [int(tier.min) - 1, int(tier.max) + 1]:
					var invalid: Dictionary = _item(base_id, tier.level, [{"id": id, "tier": tier.tier, "value": bad_value}])
					_reject(invalid)
				_reject(_item(base_id, int(tier.level) - 1, [_roll(id, tier.tier)]))
				for maximum: bool in [false, true]:
					# Both authored endpoints at both tier unlock and maximum ilvl.
					for level: int in [int(tier.level), Catalog.MAX_ITEM_LEVEL]:
						var item: Dictionary = _item(base_id, level, [_roll(id, tier.tier, maximum)])
						_expect(Catalog.validate_instance(item), "Endpoint fixture is valid: " + base_id + "/" + id)
						_verify_plan(item, 0 if maximum else -17)
	_expect(seen_bases.size() == Catalog.all_base_ids().size(), "Every actual base exercised")
	_expect(seen_families.size() == Catalog.all_affix_ids().size() and family_tiers.size() == 57, "Every actual family and tier exercised")
	# Each authored tick, including both endpoints, is reachable; no exclusive max
	# or forced 'different value' implementation can pass these checks.
	for id: String in Catalog.all_affix_ids():
		var base_id: String = ""
		for candidate: String in Catalog.all_base_ids():
			if Catalog.family_eligible(id, candidate):
				base_id = candidate
				break
		for tier: Dictionary in Catalog.affix_definition(id).tiers:
			var seen: Dictionary = {}
			for seed_value: int in range(256):
				var result: Dictionary = Craft.recalibrate_plan(_item(base_id, tier.level, [_roll(id, tier.tier)]), seed_value)
				_expect(result.ok, "Reachability plan succeeds")
				if result.ok:
					seen[result.instance.affixes[0].value] = true
			for value: int in range(tier.min, tier.max + 1):
				_expect(seen.has(value), "Every integer tick reachable: %s T%d value %d" % [id, tier.tier, value])
	completed = true


func _rarities_and_levels() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261002
	var observed: Dictionary = {}
	for base_id: String in Catalog.all_base_ids():
		for level: int in [1, 7, 8, 15, 16, 30]:
			var prefixes: Array = []
			var suffixes: Array = []
			var tier: int = 1 if level < 8 else (2 if level < 16 else 3)
			for id: String in Catalog.all_affix_ids():
				if Catalog.family_eligible(id, base_id):
					if Catalog.affix_definition(id).kind == "prefix": prefixes.append(_roll(id, tier))
					else: suffixes.append(_roll(id, tier))
			for split: Array in [[1, 0], [0, 1], [1, 1], [1, 3], [2, 2], [3, 1], [2, 3], [3, 2], [3, 3]]:
				var affixes: Array = prefixes.slice(0, split[0]) + suffixes.slice(0, split[1])
				var rarity: String = "magic" if affixes.size() <= 2 else "rare"
				var item: Dictionary = _item(base_id, level, affixes, rarity)
				_expect(Catalog.validate_instance(item), "All legal count/cap fixture is valid")
				_verify_plan(item, 46)
				observed[affixes.size()] = true
	# Also exercise mixed tiers and naturally generated family/order combinations.
	for pool_id: String in Catalog.pool_profiles():
		for level: int in [1, 7, 8, 15, 16, 30]:
			for rarity: String in ["magic", "rare"]:
				for sample: int in range(16):
					var item: Dictionary = Catalog.generate_for_pool(rng, "gear_%06d" % (sample + 1), level, rarity, pool_id)
					_expect(Catalog.validate_instance(item), "Generated fixture is valid")
					var state: int = rng.state
					_verify_plan(item, sample)
					_expect(rng.state == state, "Caller loot RNG state is unchanged")
	for count: int in [1, 2, 4, 5, 6]:
		_expect(observed.has(count), "All supported affix counts covered")
	completed = true


func _local_weapon() -> void:
	var item: Dictionary = _item("ashwood_bow", 16, [
		_roll("whetstone_edge", 3), _roll("tempered_edge", 2),
		_roll("farweave", 1), _roll("coalglow", 3)], "rare")
	var changed: bool = false
	var initial_w: float = Catalog.definition(item).weapon_damage.physical
	for seed_value: int in range(64):
		var plan: Dictionary = _verify_plan(item, seed_value)
		if plan.is_empty(): continue
		var output: Dictionary = plan.instance
		var profile: Dictionary = Catalog.weapon_profile(output)
		var resolved: Dictionary = Weapon.resolve(profile)
		var expected_w: float = (4.0 + float(output.affixes[0].value)) * (1.0 + float(output.affixes[1].value) / 100.0)
		_expect(resolved.ok and is_equal_approx(resolved.components.physical, expected_w), "Existing parser derives current local W from rerolled values")
		_expect(plan.definition.weapon_profile == profile and plan.definition.weapon_damage == resolved.components,
			"Plan exposes rederived W instead of stale original values")
		_expect(not output.has("weapon_profile") and not output.has("weapon_damage"), "W is never persisted on the five-field item")
		var stats: Dictionary = plan.definition.stats
		_expect(not stats.has("weapon_added_physical") and not stats.has("weapon_physical_increased") and not stats.has("damage"),
			"Local rolls never become global character damage")
		_expect(is_equal_approx(stats.projectile_increased, float(output.affixes[2].value) / 100.0)
			and is_equal_approx(stats.fire_increased, float(output.affixes[3].value) / 100.0), "Global percentages still use catalog tick conversion")
		_expect(Catalog.validate_instance_for_version(output, 9) and not Catalog.validate_instance_for_version(output, 8), "Recalibration cannot bypass local vocabulary fence")
		changed = changed or not is_equal_approx(initial_w, expected_w)
	_expect(changed, "At least one seed actually changes W")
	completed = true


func _reject(value: Variant, expected_code: String = "invalid_instance") -> void:
	var before: PackedByteArray = var_to_bytes(value) if value is Dictionary else PackedByteArray()
	for result: Dictionary in [Craft.salvage_quote(value), Craft.recalibrate_plan(value, 123)]:
		_expect(not result.ok and result.code == expected_code and not result.reason.is_empty(), "Rejected input has actionable stable failure code")
		for key: String in ["cost", "materials", "source_instance", "instance", "definition"]:
			_expect(result[key].is_empty(), "Failure exposes no partial transaction payload: " + key)
		_expect(not result.consumes_item, "Rejected input never requests consumption")
	if value is Dictionary:
		_expect(var_to_bytes(value) == before, "Rejected dictionary input remains byte-identical")


func _rejections() -> void:
	for value: Variant in [null, false, true, 0, 1.0, "gear_000123", [], {}, RefCounted.new()]:
		_reject(value)
	var valid: Dictionary = _item("cinder_reed", 16, [_roll("deepwell", 2)])
	for key: String in valid:
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(key)
		_reject(missing)
		for value: Variant in [null, true, {}, [], "unknown"]:
			var wrong: Dictionary = valid.duplicate(true)
			wrong[key] = value
			_reject(wrong)
	var extra: Dictionary = valid.duplicate(true)
	extra.weapon_damage = {"physical": 999.0}
	_reject(extra)
	for id: String in ["gear_0", "gear_000000", "gear_123", "gear_000000123", "gear_1000000000", "fixed_ember_wand"]:
		var bad: Dictionary = valid.duplicate(true)
		bad.id = id
		_reject(bad)
	for number: Variant in [-1, 0, 31, 1.5, NAN, INF, -INF, true, "16"]:
		var bad: Dictionary = valid.duplicate(true)
		bad.item_level = number
		_reject(bad)
	for key: String in ["id", "tier", "value"]:
		var missing: Dictionary = valid.duplicate(true)
		missing.affixes[0].erase(key)
		_reject(missing)
		for value: Variant in [null, false, true, [], {}, "unknown", -1, 0, 99, 1.25, NAN, INF, -INF]:
			var bad: Dictionary = valid.duplicate(true)
			bad.affixes[0][key] = value
			_reject(bad)
	var unknown_affix_key: Dictionary = valid.duplicate(true)
	unknown_affix_key.affixes[0].scope = "equipped_weapon"
	_reject(unknown_affix_key)
	var bad_entry: Dictionary = valid.duplicate(true)
	bad_entry.affixes = [null]
	_reject(bad_entry)
	_reject(_item("cinder_reed", 7, [_roll("deepwell", 2)]))
	_reject(_item("cinder_reed", 15, [_roll("deepwell", 3)]))
	_reject(_item("cinder_reed", 16, [_roll("deepwell"), _roll("deepwell", 2)]))
	_reject(_item("cinder_reed", 16, [_roll("deepwell"), _roll("runesong")]))
	_reject(_item("cinder_reed", 16, [_roll("coalglow"), _roll("rimeecho")]))
	_reject(_item("cinder_reed", 16, [_roll("deepwell")], "rare"))
	_reject(_item("cinder_reed", 16, [_roll("deepwell")], "normal"))
	_reject(_item("cinder_reed", 16, [], "magic"))
	_reject(_item("cinder_reed", 16, [], "rare"))
	_reject(_item("cinder_reed", 16, [_roll("deepwell"), _roll("runesong"), _roll("prismedge"), _roll("farweave")], "rare"))
	_reject(_item("cinder_reed", 16, [_roll("deepwell"), _roll("runesong"), _roll("prismedge"),
		_roll("coalglow"), _roll("rimeecho"), _roll("sparkthread"), _roll("wellturn")], "rare"))
	for base_id: String in Catalog.all_base_ids():
		var normal: Dictionary = _item(base_id, 16, [], "normal")
		_expect(Catalog.validate_instance(normal), "Normal item is catalog-valid but outside crafting scope")
		_reject(normal, "no_affixes")
		for id: String in Catalog.all_affix_ids():
			if not Catalog.family_eligible(id, base_id):
				_reject(_item(base_id, 16, [_roll(id)]))
	completed = true


func _global_samples() -> Array:
	var result: Array = []
	for unused: int in range(12):
		result.append(randi())
		result.append(randf())
	return result


func _seed_and_rng() -> void:
	var item: Dictionary = _item("cinder_reed", 16, [_roll("deepwell", 3), _roll("coalglow", 2)])
	for seed_value: int in [0, 1, -1, 9223372036854775807, -9223372036854775807 - 1]:
		_verify_plan(item, seed_value)
	for bad_seed: Variant in [null, false, true, 0.0, 1.0, 1.25, NAN, INF, "1", [], {}, RefCounted.new()]:
		var before: PackedByteArray = var_to_bytes(item)
		var rejected: Dictionary = Craft.recalibrate_plan(item, bad_seed)
		_expect(not rejected.ok and rejected.code == "invalid_seed" and not rejected.reason.is_empty(), "Seed type must be exact integer")
		for key: String in ["cost", "materials", "instance", "source_instance", "definition"]:
			_expect(rejected[key].is_empty(), "Invalid seed cannot expose a partial plan")
		_expect(var_to_bytes(item) == before, "Invalid seed leaves input unchanged")
	seed(61002)
	var expected: Array = _global_samples()
	seed(61002)
	Craft.metadata()
	for local_seed: int in range(64):
		Craft.salvage_quote(item)
		Craft.recalibrate_plan(item, local_seed)
		Craft.salvage_quote({})
		Craft.recalibrate_plan({}, local_seed)
		Craft.recalibrate_plan(item, "bad")
		Craft.salvage_quote(_item("ashwood_bow", 1, [], "normal"))
	_expect(_global_samples() == expected, "Success, rejection and metadata never advance/reseed global RNG")
	var fixed: Dictionary = Craft.recalibrate_plan(item, 431)
	seed(99)
	_global_samples()
	_expect(Craft.recalibrate_plan(item, 431) == fixed, "Ambient global RNG cannot affect seeded output")
	var maxed: Dictionary = item.duplicate(true)
	for affix: Dictionary in maxed.affixes:
		affix.value = Catalog.affix_definition(affix.id).tiers[int(affix.tier) - 1].max
	_expect(Craft.recalibrate_plan(maxed, 431).instance == fixed.instance, "Old values do not bias new rolls")
	var narrow: Dictionary = _item("runewood_focus", 1, [_roll("attack_added_physical")])
	var unchanged: bool = false
	var changed: bool = false
	for seed_value: int in range(64):
		var output: Dictionary = Craft.recalibrate_plan(narrow, seed_value).instance
		unchanged = unchanged or output == narrow
		changed = changed or output != narrow
	_expect(unchanged and changed, "Both same-value and changed rolls are possible")
	completed = true


func _detachment() -> void:
	var item: Dictionary = _item("ashwood_bow", 16, [_roll("whetstone_edge", 3)])
	var before: Dictionary = item.duplicate(true)
	var plan: Dictionary = Craft.recalibrate_plan(item, 9)
	var pristine: Dictionary = plan.duplicate(true)
	plan.source_instance.affixes[0].value = -1
	_expect(plan.instance == pristine.instance and item == before, "Source snapshot is detached from both original and replacement")
	plan.instance.affixes[0].value = -2
	_expect(plan.definition == pristine.definition and item == before, "Replacement is detached from both original and preview")
	plan.definition.weapon_profile.sources[0].value = 999.0
	plan.definition.weapon_damage.physical = 999.0
	plan.cost[Craft.MATERIAL_ID] = -1
	_expect(Craft.recalibrate_plan(item, 9) == pristine, "Mutating returned nested payloads cannot affect subsequent plans")
	var quote: Dictionary = Craft.salvage_quote(item)
	quote.materials[Craft.MATERIAL_ID] = -1
	quote.source_instance.affixes.clear()
	_expect(item == before and Craft.salvage_quote(item).materials[Craft.MATERIAL_ID] == 4, "Quote material and source are detached")
	item.affixes.clear()
	_expect(pristine.instance.affixes.size() == 1 and pristine.source_instance.affixes.size() == 1, "Later caller mutation cannot change earlier plans")
	var info: Dictionary = Craft.metadata()
	var info_before: Dictionary = info.duplicate(true)
	info.balance.salvage_rarity_units.magic = 999
	info.materials[Craft.MATERIAL_ID].name = "changed"
	info.operations.recalibrate.preserves.clear()
	info.eligible_families_by_base.ashwood_bow.clear()
	info.base_ids.clear()
	info.affix_ids.clear()
	_expect(Craft.metadata() == info_before, "All nested metadata is detached")
	_expect(Catalog.base_definition("ashwood_bow").name == "白蜡长弓"
		and Catalog.affix_definition("whetstone_edge").tiers[2].min == 5, "Metadata and result mutations never reach catalog constants")
	completed = true


func _economy() -> void:
	var cases: Array = [
		{"item": _item("cinder_reed", 1, [_roll("deepwell")]), "yield": 2, "cost": 4},
		{"item": _item("cinder_reed", 16, [_roll("deepwell", 3), _roll("coalglow", 3)]), "yield": 7, "cost": 14},
		{"item": _item("ashwood_bow", 16, [_roll("whetstone_edge", 3), _roll("tempered_edge", 2),
			_roll("farweave"), _roll("coalglow", 3)], "rare"), "yield": 12, "cost": 24},
		{"item": _item("cinder_reed", 16, [_roll("deepwell", 3), _roll("runesong", 3), _roll("prismedge", 3),
			_roll("coalglow", 3), _roll("rimeecho", 3), _roll("sparkthread", 3)], "rare"), "yield": 21, "cost": 42},
	]
	var balance: Dictionary = Craft.metadata().balance
	for entry: Dictionary in cases:
		var quote: Dictionary = Craft.salvage_quote(entry.item)
		var plan: Dictionary = Craft.recalibrate_plan(entry.item, 37)
		_expect(quote.materials == {"calibration_shard": entry["yield"]} and quote.cost.is_empty(), "Independent prototype salvage arithmetic")
		_expect(plan.cost == {"calibration_shard": entry.cost} and plan.materials.is_empty(), "Independent prototype cost arithmetic")
		var metadata_units: int = int(balance.salvage_rarity_units[entry.item.rarity])
		for affix: Dictionary in entry.item.affixes:
			metadata_units += int(affix.tier) * int(balance.salvage_units_per_tier)
		_expect(metadata_units == entry["yield"] and metadata_units * int(balance.recalibrate_cost_multiplier) == entry.cost,
			"Metadata prices and execution share actual balance parameters")
		_expect(Craft.salvage_quote(plan.instance).materials == quote.materials, "Reroll never increases salvage payout")
		_expect(plan.cost.calibration_shard > quote.materials.calibration_shard, "Single reroll then salvage cannot mint net material")
		var leveled: Dictionary = entry.item.duplicate(true)
		leveled.item_level = 30
		_expect(Craft.salvage_quote(leveled).materials == quote.materials, "Item level does not silently change original tier-based prototype economy")
	completed = true
