extends SceneTree
## Run against the frozen v064 project, never against the schema41 worktree.
const FrozenStore = preload("res://scripts/save/canonical_build_store.gd")
const FrozenGame = preload("res://scripts/canonical_game_state.gd")
const FrozenRules = preload("res://scripts/save/canonical_build_rules.gd")
const FrozenEquipment = preload("res://scripts/items/equipment_catalog.gd")
const FrozenSource = preload("res://scripts/passives/source_tree_runtime.gd")
const OLD_POOLS := ["legacy", "nine_slot", "runewood", "defense", "local_weapon", "build_legacy_v27", "build_nine_slot_v27", "forgeblade_v34", "defense_v37", "defense_v39"]


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v065-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	if FrozenRules.VERSION != 40 or FrozenSource.CURRENT_SAVE_VERSION != 40 or FrozenEquipment.CURRENT_VOCABULARY != 39:
		push_error("This fixture must be serialized by frozen v064 schema40 production code")
		quit(1)
		return
	var store := FrozenStore.new()
	var value := store.snapshot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6540
	var recovery := 0
	for location: Dictionary in value.locations.values():
		if location.kind == "recovery": recovery += 1
	for pool: String in OLD_POOLS:
		var gear := FrozenEquipment.generate_for_pool(rng, "gear_%06d" % int(value.next_item_serial), 16, "rare", pool)
		value.items[gear.id] = FrozenStore.Items.wrap_equipment(gear)
		value.locations[gear.id] = {"kind":"recovery", "index":recovery}
		recovery += 1
		value.next_item_serial += 1
	var gear := {"id":"gear_%06d" % int(value.next_item_serial), "base_id":"emberhide_vest", "rarity":"rare", "item_level":16,
		"affixes":[{"id":"rootwell", "tier":3, "value":32}, {"id":"ironhide", "tier":3, "value":120}, {"id":"mistweave", "tier":3, "value":450},
			{"id":"emberward", "tier":3, "value":25}, {"id":"rimeward", "tier":3, "value":25}, {"id":"stormward", "tier":3, "value":25}]}
	value.items[gear.id] = FrozenStore.Items.wrap_equipment(gear)
	value.locations[gear.id] = {"kind":"equipment", "slot_id":"body_armour"}
	value.locations.guardian_robe = {"kind":"recovery", "index":recovery}
	value.next_item_serial += 1
	recovery += 1
	var currency_uid := "item_%06d" % int(value.next_item_serial)
	value.items[currency_uid] = FrozenStore.Currency.make_instance(currency_uid, 73)
	value.locations[currency_uid] = {"kind":"recovery", "index":recovery}
	value.next_item_serial += 1
	value.progress = {"level":37,"xp":9}
	value.talents.class_id = 4
	value.talents.allocated = ["50986", "39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544", "10661"]
	value.talents.normal_points = 29
	value.journey.best_tiers.sunwell_terrace = 2
	value.revision = 17
	value.crafting.revision = 3
	store._accept_memory(value)
	var path := OS.get_environment("V065_FROZEN40_OUTPUT")
	if path.is_empty() or not FrozenRules.reason(value).is_empty() or store.save_build(path) != OK:
		push_error("Frozen40 fixture validation or native serializer failed")
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	var stats := FrozenGame._stats_for(value)
	if float(stats.get("iron_reflexes", 0.0)) != 1.0 or stats.armour <= 0.0 or stats.evasion != 0.0 or stats.has("zealots_oath"):
		push_error("Frozen40 fixture must exercise existing Iron Reflexes and defensive equipment")
		quit(1)
		return
	var oracle := {"schema":40, "source_policy":40, "equipment_vocabulary":39, "stats":stats,
		"allocated":value.talents.allocated, "equipped_defense_item":gear.id, "currency_quantity":73}
	var oracle_path := OS.get_environment("V065_FROZEN40_ORACLE")
	var file := FileAccess.open(oracle_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(oracle,"\t",true,true)+"\n")
	file.close()
	print("Frozen v064 schema40 native save: %d bytes, %d items; Iron Reflexes armour %s" % [bytes.size(), value.items.size(), stats.armour])
	quit(0)
