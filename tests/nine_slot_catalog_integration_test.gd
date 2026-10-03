extends SceneTree
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 14009
	var categories := {}
	var additional := 0
	for level: int in [1,7,8,15,16,30]:
		for rarity: String in ["normal","magic","rare"]:
			for index: int in range(90):
				var instance := Catalog.generate_for_pool(rng, "gear_000001", level, rarity, "nine_slot")
				check(Catalog.validate_instance(instance), "actual catalog generation valid")
				if instance.is_empty(): continue
				check(not Catalog.validate_instance_for_version(instance, 13), "prior vocabulary rejects new equipment")
				var entry := Items.wrap_equipment(instance)
				var metadata := Items.metadata_for_instance(entry)
				categories[metadata.category] = true
				check(not Slots.targets_for_category(metadata.category).is_empty(), "actual canonical equip target exists")
				check(Items.decode_instance(JSON.parse_string(JSON.stringify(entry))) == entry, "canonical instance roundtrip")
				var stats := Catalog.get_stats(instance)
				if stats.has("additional_skill_slots"):
					additional += 1
					check(stats.additional_skill_slots == 1 and metadata.category in ["belt","helmet"], "bounded extra row only eligible slots")
				if rarity != "normal":
					var quote := Craft.salvage_quote(instance)
					var reroll := Craft.recalibrate_plan(instance, 37)
					check(quote.ok and reroll.ok, "same old crafting consumers accept actual valid item")
	check(categories.size() == 5 and additional > 0, "all five naturally generated categories plus extra row rolls")
	var seen := {}
	for index: int in range(500):
		var instance := Catalog.generate_loot_profile(rng, "gear_000002", 16, "rare", "canonical_v14")
		check(Catalog.validate_instance(instance), "new ordinary loot profile valid")
		seen[Catalog.pool_for_base(instance.base_id)] = true
	check(seen.size() == 5, "all old and new pools remain obtainable")
	print("Nine-slot catalog integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
