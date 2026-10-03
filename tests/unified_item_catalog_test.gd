extends SceneTree
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Data = preload("res://scripts/game_data.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77014
	for fixed_id: String in Data.ITEMS:
		var item := Items.fixed_equipment(fixed_id, fixed_id)
		check(Items.validate_instance(item), "fixed equipment envelope")
		check(Items.metadata_for_instance(item).kind == "equipment", "fixed metadata")
		check(Items.decode_instance(JSON.parse_string(JSON.stringify(item))) == item, "fixed roundtrip")
	for pool: String in Gear.pool_profiles():
		for rarity: String in ["normal", "magic", "rare"]:
			var raw := Gear.generate_for_pool(rng, "gear_000044", 30, rarity, pool)
			var item := Items.wrap_equipment(raw)
			check(Items.validate_instance(item), "rolled gear valid")
			check(Items.decode_instance(JSON.parse_string(JSON.stringify(item))) == item, "gear numeric exact roundtrip")
			var copy := Items.definition_for_instance(item)
			copy.stats.clear()
			check(item.payload == raw, "metadata cannot mutate instance")
	for raw: Dictionary in Jewels.starter_jewels().values():
		var item := Items.wrap_jewel(raw)
		check(Items.decode_instance(JSON.parse_string(JSON.stringify(item))) == item, "fractional jewel exact")
		check(Items.metadata_for_instance(item) == {"kind":"jewel","category":"","size":[1,1]}, "jewel footprint")
	for id: String in Gems.definitions():
		var item := Gems.create_instance("item_000077", id)
		check(Items.decode_instance(JSON.parse_string(JSON.stringify(item))) == item, "gem integer normalization")
		check(Items.metadata_for_instance(item).size == [1,1], "gem footprint")
	var gem := Gems.create_instance("item_000001", "skill:bolt")
	for bad: Variant in [true, 1.1, 2, -1, "1", null, INF, NAN]:
		var value := gem.duplicate(true)
		value.payload.level = bad
		check(Items.decode_instance(value).is_empty(), "reject malformed integer")
	for value: Variant in [{"kind":"bag","x":0.0,"y":1.0},{"kind":"skill_support","group_id":"row", "index":4.0}]:
		var decoded := Items.decode_location(value)
		check(not decoded.is_empty(), "explicit location integers restored")
	for value: Variant in [{"kind":"bag","x":true,"y":1},{"kind":"bag","x":0.1,"y":1},{"kind":"bag","x":0,"y":1,"hack":1}, {"kind":"bogus"}]:
		check(Items.decode_location(value).is_empty(), "malformed location rejected")
	var forged := Items.wrap_jewel(Jewels.starter_jewels().values()[0])
	forged.uid = "different"
	check(not Items.validate_instance(forged), "payload UID cannot alias")
	print("Unified item catalog: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
