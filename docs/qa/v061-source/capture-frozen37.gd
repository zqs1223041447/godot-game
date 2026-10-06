extends SceneTree
## Run against the frozen v060 project, never against the schema38 worktree.
const FrozenStore = preload("res://scripts/save/canonical_build_store.gd")
const FrozenRules = preload("res://scripts/save/canonical_build_rules.gd")
const FrozenEquipment = preload("res://scripts/items/equipment_catalog.gd")
const FrozenSource = preload("res://scripts/passives/source_tree_runtime.gd")
const OLD_POOLS := ["legacy", "nine_slot", "runewood", "defense", "local_weapon", "build_legacy_v27", "build_nine_slot_v27", "forgeblade_v34"]


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v061-source-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	if FrozenRules.VERSION != 37 or FrozenSource.CURRENT_SAVE_VERSION != 36:
		push_error("This fixture must be serialized by frozen v060 schema37 production code")
		quit(1)
		return
	var store := FrozenStore.new()
	var value := store.snapshot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6137
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
		"affixes":[{"id":"rootwell", "tier":3, "value":32}, {"id":"deepwell", "tier":3, "value":22}, {"id":"lanternveil", "tier":3, "value":22},
			{"id":"emberward", "tier":3, "value":25}, {"id":"rimeward", "tier":3, "value":25}, {"id":"stormward", "tier":3, "value":25}]}
	value.items[gear.id] = FrozenStore.Items.wrap_equipment(gear)
	value.locations[gear.id] = {"kind":"recovery", "index":recovery}
	value.next_item_serial += 1
	value.progress = {"level":37,"xp":9}
	value.talents.normal_points = 41
	value.journey.best_tiers.sunwell_terrace = 2
	value.revision = 17
	value.crafting.revision = 3
	store._accept_memory(value)
	var path := OS.get_environment("V061_FROZEN37_OUTPUT")
	if path.is_empty() or not FrozenRules.reason(value).is_empty() or store.save_build(path) != OK:
		push_error("Frozen37 fixture validation or native serializer failed")
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	var oracle := {"schema":37, "source_policy":36, "full_nodes":{}, "full_masteries":{}}
	for id: String in FrozenSource.Data.standard_ids():
		var effect := FrozenSource.node_effect(id)
		if effect.status == "full": oracle.full_nodes[id] = effect.grants
		for mastery: Dictionary in FrozenSource.Data.node(id).mastery_effects:
			var selected := FrozenSource.node_effect(id, int(mastery.effect))
			if selected.status == "full": oracle.full_masteries[id + ":" + str(int(mastery.effect))] = selected.grants
	var oracle_path := OS.get_environment("V061_FROZEN37_ORACLE")
	var file := FileAccess.open(oracle_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(oracle,"\t",true,true)+"\n")
	file.close()
	print("Frozen v060 schema37 native save: %d bytes, %d items; full nodes %d" % [bytes.size(), value.items.size(), oracle.full_nodes.size()])
	quit(0)
