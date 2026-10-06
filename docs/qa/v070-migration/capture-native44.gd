extends SceneTree
## Run against the unchanged v069 source checkout, never against schema45.
const FrozenStore = preload("res://scripts/save/canonical_build_store.gd")
const FrozenGame = preload("res://scripts/canonical_game_state.gd")
const FrozenRules = preload("res://scripts/save/canonical_build_rules.gd")
const FrozenEquipment = preload("res://scripts/items/equipment_catalog.gd")
const FrozenSource = preload("res://scripts/passives/source_tree_runtime.gd")
const OLD_POOLS := ["legacy", "nine_slot", "runewood", "defense", "local_weapon", "build_legacy_v27", "build_nine_slot_v27", "forgeblade_v34", "defense_v37", "defense_v39"]


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v070-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	if FrozenRules.VERSION != 44 or FrozenSource.CURRENT_SAVE_VERSION != 44 or FrozenEquipment.CURRENT_VOCABULARY != 39:
		push_error("This fixture must be serialized by unchanged v069 schema44 production code")
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
	recovery += 1
	for placement: String in ["recovery", "skill_support"]:
		var gem_uid := "item_%06d" % int(value.next_item_serial)
		var gem := FrozenGame.Gems.create_instance(gem_uid,"support:ambush")
		if gem.is_empty():
			push_error("Native44 Ambush gem fixture creation failed")
			quit(1)
			return
		value.items[gem_uid] = gem
		value.locations[gem_uid] = {"kind":"skill_support", "group_id":"group_000007", "index":0} if placement == "skill_support" else {"kind":"recovery", "index":recovery}
		recovery += 1 if placement == "recovery" else 0
		value.next_item_serial += 1
	for placement: String in ["recovery", "skill_support"]:
		var gem_uid := "item_%06d" % int(value.next_item_serial)
		value.items[gem_uid] = FrozenGame.Gems.create_instance(gem_uid,"support:inward_pull")
		value.locations[gem_uid] = {"kind":"skill_support", "group_id":"group_000003", "index":0} if placement == "skill_support" else {"kind":"recovery", "index":recovery}
		recovery += 1 if placement == "recovery" else 0
		value.next_item_serial += 1
	value.progress = {"level":37,"xp":9}
	value.talents.class_id = 4
	value.talents.allocated = ["50986", "39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544", "10661"]
	value.talents.normal_points = 29
	value.journey.best_tiers.sunwell_terrace = 2
	value.revision = 17
	value.crafting.revision = 3
	var destination := OS.get_environment("V070_NATIVE44_DIRECTORY")
	var oracle := {"schema":44, "source_policy":44, "equipment_vocabulary":39, "fixtures":{}, "gem_definitions":FrozenGame.Journey.GEM_DEFINITIONS, "gem_milestones":[], "minimum_save_versions":{}}
	for ordinal: int in range(1,53): oracle.gem_milestones.append(FrozenGame.Journey.gem_definition(ordinal))
	for definition_id: String in FrozenGame.Gems.definitions(): oracle.minimum_save_versions[definition_id] = FrozenGame.Gems.minimum_save_version(definition_id)
	for label: String in ["ir", "zo", "conversion"]:
		var candidate := value.duplicate(true)
		if label == "zo":
			candidate.talents.class_id = 1
			candidate.talents.allocated = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "44202", "23027", "60472", "26270", "64210", "7444", "63425", "55649", "22285", "53793", "37884", "32482", "31033", "38906"]
			candidate.talents.normal_points = 18
			candidate.locations[gear.id] = candidate.locations.guardian_robe
			candidate.locations.guardian_robe = {"kind":"equipment", "slot_id":"body_armour"}
		if label == "conversion":
			candidate.talents.class_id = 1
			candidate.talents.allocated = ["47175","31628","9511","23881","26523","6446","10221","54396","2550","48267"]
			candidate.talents.masteries = {"48267":65020}
			candidate.talents.normal_points = 32
		var path := destination.path_join("v44-" + label + "-native-v069.json")
		store = FrozenStore.new()
		store._accept_memory(candidate)
		if destination.is_empty() or not FrozenRules.reason(candidate).is_empty() or store.save_build(path) != OK:
			push_error("Native44 fixture validation or native serializer failed: " + label + ": " + FrozenRules.reason(candidate))
			quit(1)
			return
		var stats := FrozenGame._stats_for(candidate)
		var game := FrozenGame.new()
		game._accept_memory(candidate)
		var snapshot := game.get_combat_snapshot()
		if (label == "ir" and (float(stats.get("iron_reflexes", 0.0)) != 1.0 or stats.armour <= 0.0 or stats.evasion != 0.0)) or (label == "zo" and (float(stats.get("zealots_oath", 0.0)) != 1.0 or stats.life_regen != 0.0 or stats.get("shield_regeneration_rate", 0.0) <= 10.0)):
			push_error("Native44 fixture did not exercise native " + label)
			quit(1)
			return
		if label == "conversion" and (not is_equal_approx(float(stats.get("physical_to_fire_conversion",0.0)),0.4) or not snapshot.has("physical_to_fire_conversion")):
			push_error("Native44 fixture did not exercise the original65020 consumer")
			quit(1)
			return
		var bytes := FileAccess.get_file_as_bytes(path)
		oracle.fixtures[label] = {"stats":stats, "stats_sha256":digest(var_to_bytes(stats)), "snapshot":snapshot, "snapshot_sha256":digest(var_to_bytes(snapshot)), "allocated":candidate.talents.allocated, "rating_item":gear.id, "currency_quantity":73}
		print("Frozen v069 schema44 native %s save: %d bytes, %d items" % [label, bytes.size(), candidate.items.size()])
	oracle.source_effects = {}
	for id: String in FrozenSource.Data.standard_ids():
		oracle.source_effects[id + ":0"] = digest(var_to_bytes(FrozenSource.node_effect(id,0,44)))
		for effect: Dictionary in FrozenSource.Data.node(id).mastery_effects:
			oracle.source_effects[id + ":" + str(int(effect.effect))] = digest(var_to_bytes(FrozenSource.node_effect(id,int(effect.effect),44)))
	var file := FileAccess.open(destination.path_join("v44-oracle.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(oracle,"\t",true,true)+"\n")
	file.close()
	quit(0)


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
