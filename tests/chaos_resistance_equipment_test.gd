extends SceneTree
## Focused v93 catalog, frozen seed and six-operation supply proof.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Profile = preload("res://scripts/items/chaos_resistance_affix_profile.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Expand = preload("res://scripts/items/crafting_expansion_rules.gd")
const Old = preload("res://tests/fixtures/chaos_v50_frozen/equipment_catalog.gd")
const OldCraft = preload("res://tests/fixtures/chaos_v50_frozen/crafting_rules.gd")
const LEVELS: Array[int] = [1, 7, 8, 15, 16, 30]
var checks := 0
var failures := 0
var historical_rolls := 0
var historical_plans := 0
var witnesses := {}


## Shared by actual-Main/UI tests; magic has exactly one suffix and no hidden grant.
static func legal_ring(uid: String, tier: int = 3, value: int = 25) -> Dictionary:
	return {"id": uid, "base_id": Profile.RING_BASE_ID, "rarity": "magic", "item_level": [1, 8, 16][tier - 1],
		"affixes": [{"id": "ring_voidward", "tier": tier, "value": value}]}


static func legal_rare_ring(uid: String = "gear_000721") -> Dictionary:
	var ring := legal_ring(uid)
	ring.rarity = "rare"
	for id: String in ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis", "ring_emberward", "ring_rimeward"]:
		ring.affixes.append({"id": id, "tier": 3, "value": int(Catalog.affix_definition(id).tiers[2].max)})
	return ring


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)


func same(actual: Variant, expected: Variant, label: String) -> void:
	check(var_to_bytes(actual) == var_to_bytes(expected), label)


func rng_for(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value; return rng


func has_chaos(item: Dictionary) -> bool:
	for affix: Dictionary in item.get("affixes", []):
		if affix.id == "ring_voidward": return true
	return false


func _metadata_and_admission() -> void:
	check(Catalog.CURRENT_VOCABULARY == 51 and Catalog.CURRENT_LOOT_PROFILE_ID == "canonical_v51" and Catalog.CANONICAL_LOOT_PROFILE_ID == "canonical_v51", "Explicit current51 vocabulary and rewards")
	same(Catalog.all_base_ids(), Old.all_base_ids(), "No base or slot expansion")
	same(Catalog.all_affix_ids(), Old.all_affix_ids() + Profile.AFFIX_IDS, "One appended family")
	same(Catalog.RARITIES, Old.RARITIES, "Original affix capacities")
	for base: String in Old.all_base_ids(): same(Catalog.base_definition(base), Old.base_definition(base), "Old base metadata order is byte exact")
	for id: String in Old.all_affix_ids(): same(Catalog.affix_definition(id), Old.affix_definition(id), "Old family metadata order is byte exact")
	for id: String in Old.pool_profiles(): same(Catalog.pool_profile(id), Old.pool_profile(id), "Old pool metadata order is byte exact")
	for id: String in Old.loot_profiles(): same(Catalog.loot_profile(id), Old.loot_profile(id), "Old loot metadata order is byte exact")
	var expected := Old.current_loot_profile(); expected[4].pool_id = "build_nine_slot_v51"
	same(Catalog.current_loot_profile(), expected, "Only existing30% nine-slot pool changes")
	same(Profile.POOL_PROFILE.affix_ids, Old.pool_profile("build_nine_slot_v46").affix_ids + ["ring_voidward"], "Existing family order retained")
	var family := Catalog.affix_definition("ring_voidward")
	check(Profile.valid_family(family), "Exact chaos family semantics")
	for index: int in range(3):
		same(family.tiers[index], {"tier": index + 1, "level": [1, 8, 16][index], "weight": [100, 60, 30][index], "min": [8, 13, 19][index], "max": [12, 18, 25][index]}, "Authored tier gates weights and ticks")
	for base: String in Catalog.all_base_ids(): check(Catalog.family_eligible("ring_voidward", base) == (base == Profile.RING_BASE_ID), "Only etched ring admits chaos")
	for change: Dictionary in [{"stat":"chaos_increased"}, {"group":"fire_resistance"}, {"unit":"basis_points"}, {"kind":"prefix"}, {"damage_type":"fire"}, {"slots":["armor"]}, {"allowed_base_ids":["emberhide_vest"]}, {"actors":["player"]}, {"stage":"burning"}, {"scope":"equipped_weapon"}]:
		var bad := family.duplicate(true); bad.merge(change, true); check(not Profile.valid_family(bad), "Invalid family fails closed")
	for level: int in LEVELS:
		for tier: int in [1, 2, 3]:
			var budget: Dictionary = family.tiers[tier - 1]
			var item := legal_ring("gear_000721", tier, int(budget.max)); item.item_level = level
			for value: int in [int(budget.min), int(budget.max)]:
				item.affixes[0].value = value
				check(Catalog.validate_instance(item) == (level >= budget.level), "Inclusive tick endpoints and ilvl gates")
			for value: Variant in [int(budget.min) - 1, int(budget.max) + 1, 8.5, true, "12", NAN, INF]:
				item.affixes[0].value = value; check(not Catalog.validate_instance(item), "Malformed tick rejects")
	var ring := legal_ring("gear_000721")
	for version: int in range(1, 51): check(not Catalog.validate_instance_for_version(ring, version), "All old vocabularies reject chaos family")
	for base: String in Catalog.all_base_ids():
		var wrong := ring.duplicate(true); wrong.base_id = base
		check(Catalog.validate_instance(wrong) == (base == Profile.RING_BASE_ID), "Cross-base instance rejects")
	check(Catalog.validate_instance(JSON.parse_string(JSON.stringify(ring))), "Integral JSON ticks accepted")
	check(Catalog.get_stats(ring).chaos_resistance == 0.25 and Catalog.affix_display(ring.affixes[0]).line == "混沌抗性 +25%", "One percent conversion and authored label")
	var full := legal_rare_ring()
	check(Catalog.validate_instance(full) and not Craft.operation_quote(full, "augment").ok, "Rare ring retains six affixes and three suffix cap")
	var four := full.duplicate(true); four.affixes.remove_at(1); four.affixes.append({"id":"ring_stormward", "tier":3, "value":25})
	check(not Catalog.validate_instance(four), "Fourth suffix cannot displace a prefix")
	var duplicate := full.duplicate(true); duplicate.affixes[5] = ring.affixes[0].duplicate(true)
	check(not Catalog.validate_instance(duplicate), "Duplicate chaos group rejects")
	var magic := ring.duplicate(true); magic.affixes.append({"id":"ring_emberward", "tier":3, "value":25})
	check(not Catalog.validate_instance(magic), "Magic still permits only one suffix")
	for entry: Dictionary in Expand._pool(Profile.RING_BASE_ID, 30, ring.affixes): check(entry.group != "chaos_resistance", "Kept chaos excludes all tiers in group")
	family.allowed_base_ids.clear(); family.tiers[0].max = 999
	check(Catalog.family_eligible("ring_voidward", Profile.RING_BASE_ID) and Catalog.affix_definition("ring_voidward").tiers[0].max == 12, "Detached family metadata")


func _history() -> void:
	for vocabulary: int in range(1, 51):
		for base: String in Old.all_base_ids():
			same(Catalog.pool_for_base_version(base, vocabulary), Old.pool_for_base_version(base, vocabulary), "Every explicit old vocabulary keeps pool dispatch")
	for pool: String in Old.pool_profiles():
		for level: int in [1, 8, 16]:
			var now := rng_for(935001 + level); var old := rng_for(935001 + level)
			for index: int in range(12):
				var a := Catalog.generate_for_pool(now, "gear_000721", level, "", pool)
				var b := Old.generate_for_pool(old, "gear_000721", level, "", pool)
				same([a, now.state], [b, old.state], "Frozen pool item and post-RNG stream")
				historical_rolls += 1
	for profile: String in Old.loot_profiles():
		var now := rng_for(935050); var old := rng_for(935050)
		for index: int in range(32):
			same([Catalog.generate_loot_profile(now, "gear_000721", 16, "rare", profile), now.state], [Old.generate_loot_profile(old, "gear_000721", 16, "rare", profile), old.state], "Frozen named loot and post-RNG stream")
			historical_rolls += 1
	var item := legal_ring("gear_000721"); item.affixes[0].id = "ring_emberward"
	for vocabulary: int in range(1, 51):
		for operation: String in Craft.operation_ids():
			same(Craft.operation_plan(item, operation, 935050, vocabulary), OldCraft.operation_plan(item, operation, 935050, vocabulary), "Explicit old craft plans and rejections remain exact")
			historical_plans += 1
	same(Craft.operation_ids(), OldCraft.operation_ids(), "Six existing operations and four targets unchanged")


func _supply_and_crafting() -> void:
	var seen := {}
	for level: int in LEVELS:
		var rng := rng_for(935100 + level)
		for index: int in range(160):
			var item := Catalog.generate_for_pool(rng, "gear_000721", level, "rare", "build_nine_slot_v51")
			check(Catalog.validate_instance(item), "Current natural rare roll legal")
			for affix: Dictionary in item.affixes:
				if affix.id == "ring_voidward":
					seen[affix.tier] = true
					if not witnesses.has(str(level)): witnesses[str(level)] = {"seed":935100 + level, "ordinal":index, "item":item, "post_rng":str(rng.state)}
		check(witnesses.has(str(level)), "Chaos appears naturally at each level boundary")
	check(seen.has_all([1, 2, 3]), "All three tiers witnessed naturally")
	var current := rng_for(935051); var mirror := rng_for(935051); var current_has := false
	for index: int in range(192):
		var roll := mirror.randi_range(1, 100); var pool := ""
		for entry: Dictionary in Catalog.current_loot_profile():
			roll -= int(entry.weight)
			if roll <= 0: pool = entry.pool_id; break
		var expected := Catalog.generate_for_pool(mirror, "gear_000721", 16, "rare", pool)
		var actual := Catalog.generate_current_loot(current, "gear_000721", 16, "rare")
		same([actual, current.state], [expected, mirror.state], "Current dispatch uses exact ordered weights")
		current_has = current_has or has_chaos(actual)
	check(current_has, "Chaos reaches actual current loot")
	var normal := legal_ring("gear_000721"); normal.rarity = "normal"; normal.affixes.clear()
	var prefix := legal_ring("gear_000721"); prefix.affixes = [{"id":"nine_slot_prefix_vitality", "tier":3, "value":12}]
	var full := legal_rare_ring()
	var sources := {"enchant":normal, "elevate":prefix, "augment":prefix, "reforge":full}
	for operation: String in sources:
		var supplied := false
		for seed_value: int in range(128):
			var plan := Craft.operation_plan(sources[operation], operation, seed_value)
			check(plan.ok and Catalog.validate_instance(plan.instance), "Existing operation produces legal current51 output")
			if has_chaos(plan.instance): supplied = true
		check(supplied, "Existing active operation can supply chaos: " + operation)
	var ring := legal_ring("gear_000721")
	check(Craft.operation_quote(ring, "salvage").ok, "Existing salvage accepts chaos")
	var recalibrated := Craft.operation_plan(ring, "recalibrate", 93)
	check(recalibrated.ok and recalibrated.instance.affixes[0].id == "ring_voidward" and recalibrated.instance.affixes[0].tier == 3, "Calibration keeps family and tier")


func _run() -> void:
	_metadata_and_admission()
	_history()
	_supply_and_crafting()
	var report := {"checks":checks, "failures":failures, "historical_item_and_rng_comparisons":historical_rolls, "historical_craft_plan_comparisons":historical_plans, "natural_witnesses":witnesses}
	var path := OS.get_environment("V093_EQUIPMENT_REPORT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(report, "\t") + "\n"); file.close()
	print("Chaos equipment: %d checks, %d failures; %d old item/RNG and %d craft plans" % [checks, failures, historical_rolls, historical_plans])
	quit(1 if failures else 0)
