extends SceneTree
## Real ownership, raw local snapshot isolation and schema9 migration byte guards.
const Model = preload("res://scripts/build_state.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Rules = preload("res://scripts/items/weapon_local_rules.gd")
var checks: int = 0
var failures: int = 0
var changes: int = 0
var completed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for test: Callable in [_migration, _ownership_and_profiles, _roundtrip_and_awards, _tamper, _capacity]:
		completed = false
		test.call()
		_expect(completed, "Case completes without exceptions: " + test.get_method())
	print("Local weapon state: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _changed() -> void:
	changes += 1

func _rng(seed_value: int = 130008) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Disposable fixture opens")
	if file != null:
		file.store_buffer(bytes)
		file.close()

func _literal_v8() -> Dictionary:
	# Independent historical encoding with old rolled defenses, serial gaps,
	# supports and special-jewel allocation. Never derived from current snapshot.
	return {"version":8,"inventory":["gear_000042","gear_000044","gear_000045"],"equipped":{"weapon":"gear_000042","armor":"gear_000045"},
		"equipment_instances":{
			"gear_000042":{"id":"gear_000042","base_id":"runewood_focus","rarity":"magic","item_level":16,"affixes":[{"id":"attack_added_physical","tier":3,"value":6},{"id":"coalglow","tier":2,"value":13}]},
			"gear_000044":{"id":"gear_000044","base_id":"wayglass_token","rarity":"normal","item_level":1,"affixes":[]},
			"gear_000045":{"id":"gear_000045","base_id":"emberhide_vest","rarity":"magic","item_level":16,"affixes":[{"id":"emberward","tier":3,"value":25}]}},
		"next_equipment_id":48,"skill_slots":["tornado","frost","nova","dash","ward"],"skill_supports":{"tornado":["focus","volley"]},
		"level":4,"xp":7,"talent_points":4,"allocated_nodes":["origin","ember_1_0","ember_2_0","ember_3_0","ember_3_2"],
		"jewels":{
			"jewel_000009":{"id":"jewel_000009","base":"emberheart","rarity":"magic","affixes":[{"id":"force","value":4.0},{"id":"tempo","value":0.08}]},
			"jewel_000011":{"id":"jewel_000011","base":"branchfinder","rarity":"special","affixes":[]}},
		"jewel_inventory":["jewel_000009"],"socketed_jewels":{"ember_3_0":"jewel_000011"},"next_jewel_id":20,
		"backpack_positions":{"item:gear_000044":[10,6],"jewel:jewel_000009":[11,7]}}

func _raw(legacy: Dictionary) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray([239,187,191])
	bytes.append_array(("\r\n  " + JSON.stringify(legacy,"  ",false,true).replace("\n","\r\n") + "\r\n\r\n").to_utf8_buffer())
	return bytes

func _migration() -> void:
	var legacy: Dictionary = _literal_v8()
	var bytes: PackedByteArray = _raw(legacy)
	var path: String = "user://local_v8.json"
	var backup: String = path + ".v8-backup.json"
	DirAccess.remove_absolute(backup)
	_write(path, bytes)
	var state := Model.new()
	state.changed.connect(_changed)
	changes = 0
	_expect(state.load_build(path) and state.migrated_from_v8 and changes == 1, "Literal v8 with defenses and remote special allocation migrates atomically once")
	var expected: Dictionary = legacy.duplicate(true)
	expected.version = Model.SAVE_VERSION
	expected.crafting = {"materials":{"calibration_shard":0},"revision":0}
	_expect(state._snapshot() == expected and state.migration_message.contains("白蜡长弓"), "Only save version changes; ownership, identities, rolls, supports, nodes and locations are preserved")
	_expect(not state.get_combat_snapshot().has("weapon_profile") and state.equipment_instances.size() == 3 and is_equal_approx(state.get_stats().fire_resistance,0.4), "Migration grants no bow or local stats and retains old resistance")
	_expect(FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(backup), "Read-only migration preserves original BOM and CRLF bytes")
	_expect(state.save_build("user://local_save_as.json") == OK and not FileAccess.file_exists(backup) and FileAccess.get_file_as_bytes(path) == bytes, "Save-as preserves pending source protection")
	_expect(state.save_build(ProjectSettings.globalize_path(path)) == OK and FileAccess.get_file_as_bytes(backup) == bytes, "Absolute path alias creates an exact v8 byte backup before overwrite")
	var restored := Model.new()
	_expect(restored.load_build(path) and not restored.migrated_from_v8 and restored._snapshot() == expected, "V9 reload keeps canonical identity and never migrates again")
	_expect(restored.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == bytes, "Subsequent writes never alter historical backup")
	var conflict_path: String = "user://local_conflict.json"
	_write(conflict_path,bytes)
	_write(conflict_path + ".v8-backup.json",JSON.stringify(legacy).to_utf8_buffer())
	var conflict := Model.new()
	_expect(conflict.load_build(conflict_path) and conflict.save_build(conflict_path) == ERR_ALREADY_EXISTS and FileAccess.get_file_as_bytes(conflict_path) == bytes, "Semantically equal but differently encoded backup conflicts fail closed")
	var stale_path: String = "user://local_stale.json"
	_write(stale_path,bytes)
	var stale := Model.new()
	_expect(stale.load_build(stale_path), "Stale source fixture loads")
	var rewritten: PackedByteArray = JSON.stringify(legacy).to_utf8_buffer()
	_write(stale_path,rewritten)
	_expect(stale.save_build(stale_path) == ERR_FILE_ALREADY_IN_USE and FileAccess.get_file_as_bytes(stale_path) == rewritten, "Externally rewritten source cannot be overwritten during migration")
	completed = true

func _ownership_and_profiles() -> void:
	var state := Model.new()
	_expect(not state.get_combat_snapshot().has("weapon_profile"), "Starter weapons retain the absent-profile historical snapshot")
	var normal_id: String = state.award_equipment(_rng(),16,"normal","local_weapon")
	var before: Dictionary = state.get_stats()
	_expect(not normal_id.is_empty() and not state.get_combat_snapshot().has("weapon_profile") and state.get_stats() == before, "Owned but unworn local bow contributes nothing")
	var definition: Dictionary = state.get_item_definition(normal_id)
	_expect(definition.weapon_profile.base.physical == Rules.BASE_PHYSICAL_BY_ID.ashwood_bow and definition.weapon_profile.flat.physical == 0.0 and definition.weapon_profile.increased.physical == 0.0, "Actual awarded normal item owns a base-only local profile")
	state.unequip("weapon")
	var without_weapon: Dictionary = state.get_stats()
	_expect(state.equip(normal_id) and state.get_stats() == without_weapon, "Equipped normal local bow changes no global character stat")
	var snapshot: Dictionary = state.get_combat_snapshot()
	_expect(snapshot.weapon_profile == definition.weapon_profile and snapshot.weapon_profile.size() == 7, "Equipped weapon snapshot contains the raw seven-key item-derived profile")
	snapshot.weapon_profile.base.physical = 999.0
	snapshot.weapon_profile.flat.physical = 999.0
	snapshot.weapon_profile.increased.physical = 999.0
	snapshot.weapon_profile.sources.append({"affix_id":"forged","stat":"weapon_added_physical","value":999.0})
	_expect(state.get_combat_snapshot().weapon_profile == definition.weapon_profile, "Every nested snapshot term and source list is detached from owned items")
	_expect(state.unequip("weapon") and not state.get_combat_snapshot().has("weapon_profile"), "Unequip completely removes the optional local profile key")
	# Award actual rare items until both local prefixes coexist; preserve only the
	# selected result so backpack capacity cannot masquerade as generation failure.
	var selected: String = ""
	var rng := _rng(130009)
	for unused: int in range(400):
		var id: String = state.award_equipment(rng,16,"rare","local_weapon")
		if id.is_empty(): break
		if state.get_item_definition(id).weapon_profile.sources.size() == 2:
			selected = id
			break
		state.discard_equipment(id)
	_expect(not selected.is_empty(), "Natural rare generation reaches both local prefixes within shared prefix cap")
	if selected.is_empty(): return
	_expect(state.equip(selected), "Owned affixed bow equips")
	var item: Dictionary = state.equipment_instances[selected]
	var profile: Dictionary = Catalog.weapon_profile(item)
	var resolved: Dictionary = Rules.resolve(profile)
	_expect(state.get_combat_snapshot().weapon_profile == profile and state.get_item_definition(selected).weapon_damage == resolved.components, "Real affixed equipment reaches raw combat input and separately resolved item panel")
	_expect(not state.get_stats().has("weapon_added_physical") and not state.get_stats().has("weapon_physical_increased") and state.get_stats().damage == without_weapon.damage, "Local modifiers never enter BASE_STATS or character damage")
	var detached: Dictionary = state.get_combat_snapshot()
	detached.weapon_profile.sources[0].value = 999.0
	_expect(state.get_combat_snapshot().weapon_profile == profile, "Affix source dictionaries are detached too")
	var fake_id: String = "gear_999999"
	state.equipment_instances[fake_id] = item.duplicate(true)
	state.equipment_instances[fake_id].id = fake_id
	_expect(not state.equip(fake_id) and state.equipped.weapon == selected, "Unowned instance cannot become the equipped local source")
	state.equipment_instances.erase(fake_id)
	_expect(state.equip("prism_bow") and not state.get_combat_snapshot().has("weapon_profile"), "Old bow's effects retain their old meaning without acquiring new local damage")
	completed = true

func _roundtrip_and_awards() -> void:
	var state := Model.new()
	state.changed.connect(_changed)
	changes = 0
	var rng := _rng()
	var mirror := _rng()
	var expected: Dictionary = Catalog.generate_for_pool(mirror,"gear_000001",16,"rare","local_weapon")
	var id: String = state.award_equipment(rng,16,"rare","local_weapon")
	_expect(id == "gear_000001" and state.equipment_instances[id] == expected and rng.state == mirror.state and changes == 1, "Explicit local award creates one canonical item with exact pool RNG and one signal")
	_expect(state.next_equipment_id == 2 and state.equipped.weapon == "ember_wand" and state.equip(id), "Award consumes one serial without auto-equipping")
	var snapshot: Dictionary = state._snapshot()
	_expect(Model.SAVE_VERSION == 11 and snapshot.size() == 17 and snapshot.equipment_instances[id].size() == 5, "Current schema preserves exact seventeen-field save and five-field item encoding")
	var path: String = "user://local_v9.json"
	_expect(state.save_build(path) == OK, "New local weapon saves")
	var restored := Model.new()
	_expect(restored.load_build(path) and restored._snapshot() == snapshot and restored.get_combat_snapshot() == state.get_combat_snapshot() and restored.get_item_definition(id) == state.get_item_definition(id), "V9 roundtrip preserves raw profile, resolved display, rolls and ownership without re-roll")
	var defaults := Model.new()
	var default_rng := _rng()
	var legacy_rng := _rng()
	var default_id: String = defaults.award_equipment(default_rng,16,"rare")
	_expect(defaults.equipment_instances[default_id] == Catalog.generate(legacy_rng,default_id,16,"rare") and default_rng.state == legacy_rng.state, "Generic award default remains the historical legacy pool")
	completed = true

func _reject(state: Model, value: Dictionary, label: String) -> void:
	var path: String = "user://local_reject.json"
	var bytes: PackedByteArray = _raw(value)
	_write(path,bytes)
	var before: Dictionary = state._snapshot()
	var signal_before: int = changes
	_expect(not state.load_build(path) and state._snapshot() == before and changes == signal_before, "Malformed load rejects atomically and silently: " + label)
	_expect(state.save_build(ProjectSettings.globalize_path(path)) == ERR_INVALID_DATA and FileAccess.get_file_as_bytes(path) == bytes, "Rejected path alias stays protected from autosave: " + label)

func _tamper() -> void:
	var state := Model.new()
	state.changed.connect(_changed)
	var id: String = state.award_equipment(_rng(),16,"normal","local_weapon")
	var valid: Dictionary = state._snapshot()
	for version: int in range(1,9):
		var bad: Dictionary = valid.duplicate(true)
		bad.version = version
		bad.erase("crafting")
		_reject(state,bad,"New local base forged into version%d" % version)
	for base_id: String in ["cinder_reed","gale_spindle","runewood_focus","emberhide_vest"]:
		var bad: Dictionary = valid.duplicate(true)
		bad.equipment_instances[id].base_id = base_id
		bad.equipment_instances[id].rarity = "magic"
		bad.equipment_instances[id].affixes = [{"id":"whetstone_edge","tier":1,"value":Catalog.LOCAL_WEAPON_AFFIXES.whetstone_edge.tiers[0].min}]
		for version: int in [8,9]:
			bad.version = version
			bad.erase("crafting")
			_reject(state,bad,"Local prefix on old base in version%d" % version)
	var bad: Dictionary = valid.duplicate(true)
	bad.version = Model.SAVE_VERSION + 1
	_reject(state,bad,"Unknown future version")
	for field: String in ["weapon_profile","weapon_damage","weapon_added_physical","stats","stage","pool_id"]:
		bad = valid.duplicate(true)
		bad.equipment_instances[id][field] = 999
		_reject(state,bad,"Unpersisted executable field " + field)
	var before: Dictionary = state._snapshot()
	var rng := _rng()
	var rng_before: int = rng.state
	var signal_before: int = changes
	_expect(state.award_equipment(rng,31,"rare","local_weapon").is_empty() and state.award_equipment(rng,16,"mythic","current").is_empty() and state.award_equipment(rng,16,"rare","unknown").is_empty(), "Invalid award requests reject")
	_expect(state._snapshot() == before and rng.state == rng_before and changes == signal_before, "Rejected award preserves RNG, serials, ownership and signals")
	completed = true

func _capacity() -> void:
	var state := Model.new()
	state.inventory.clear()
	state.equipped.clear()
	state.jewels.clear()
	state.jewel_inventory.clear()
	for serial: int in range(1,37):
		var id: String = "gear_%06d" % serial
		state.equipment_instances[id] = {"id":id,"base_id":"woven_bastion" if serial <= 12 else "wayglass_token","rarity":"normal","item_level":1,"affixes":[]}
		state.inventory.append(id)
	state.next_equipment_id = 37
	state.equipped["armor"] = "gear_000001"
	state._sync_backpack()
	state.changed.connect(_changed)
	changes = 0
	var before: Dictionary = state._snapshot()
	_expect(not state._validate_snapshot(before).is_empty(), "Full reserved backpack is a valid save")
	var rng := _rng()
	var mirror := _rng()
	Catalog.generate_for_pool(mirror,"gear_000037",16,"rare","local_weapon")
	_expect(state.award_equipment(rng,16,"rare","local_weapon").is_empty() and state._snapshot() == before and changes == 0, "Full backpack rejects rolled bow without identity or ownership mutation")
	_expect(rng.state == mirror.state, "Post-roll capacity refusal retains historical consumed-RNG contract")
	completed = true
