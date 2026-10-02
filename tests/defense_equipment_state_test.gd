extends SceneTree
## Schema8 roundtrips, historical vocabulary fences, raw-byte guards and awards.
const Model = preload("res://scripts/build_state.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
var checks: int = 0
var failures: int = 0
var changes: int = 0
var completed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for test: Callable in [_migration, _roundtrip_and_awards, _tamper, _capacity]:
		completed = false
		test.call()
		_expect(completed, "Case completes without exceptions: " + test.get_method())
	print("Defense equipment state: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _changed() -> void:
	changes += 1

func _rng(seed_value: int = 110008) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Disposable fixture opens")
	if file != null:
		file.store_buffer(bytes)
		file.close()

func _literal_v7() -> Dictionary:
	# Literal old encoding, not a re-versioned current snapshot. It deliberately
	# carries serial gaps, rolled runewood, supports, a special jewel and remote node.
	return {"version":7,"inventory":["gear_000042","gear_000044"],"equipped":{"weapon":"gear_000042"},
		"equipment_instances":{
			"gear_000042":{"id":"gear_000042","base_id":"runewood_focus","rarity":"magic","item_level":16,"affixes":[{"id":"attack_added_physical","tier":3,"value":6},{"id":"coalglow","tier":2,"value":13}]},
			"gear_000044":{"id":"gear_000044","base_id":"wayglass_token","rarity":"normal","item_level":1,"affixes":[]}},
		"next_equipment_id":48,"skill_slots":["tornado","frost","nova","dash","ward"],"skill_supports":{"tornado":["focus","volley"]},
		"level":4,"xp":7,"talent_points":4,"allocated_nodes":["origin","ember_1_0","ember_2_0","ember_3_0","ember_3_2"],
		"jewels":{
			"jewel_000009":{"id":"jewel_000009","base":"emberheart","rarity":"magic","affixes":[{"id":"force","value":4.0},{"id":"tempo","value":0.08}]},
			"jewel_000011":{"id":"jewel_000011","base":"branchfinder","rarity":"special","affixes":[]}},
		"jewel_inventory":["jewel_000009"],"socketed_jewels":{"ember_3_0":"jewel_000011"},"next_jewel_id":20,
		"backpack_positions":{"item:gear_000044":[10,6],"jewel:jewel_000009":[11,7]}}

func _raw(legacy: Dictionary) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray([239,187,191])
	bytes.append_array(("\r\n  " + JSON.stringify(legacy, "  ", false, true).replace("\n", "\r\n") + "\r\n\r\n").to_utf8_buffer())
	return bytes

func _migration() -> void:
	var legacy: Dictionary = _literal_v7()
	var bytes: PackedByteArray = _raw(legacy)
	var path: String = "user://defense_v7.json"
	var backup: String = path + ".v7-backup.json"
	DirAccess.remove_absolute(backup)
	_write(path, bytes)
	var state := Model.new()
	state.changed.connect(_changed)
	changes = 0
	_expect(state.load_build(path) and state.migrated_from_v7 and changes == 1, "Literal v7 with special remote node migrates atomically once")
	var expected: Dictionary = legacy.duplicate(true)
	expected.version = 8
	_expect(state._snapshot() == expected and not state.migration_message.is_empty(), "Migration changes version only; every item roll, identity, support, jewel, allocation and location survives")
	_expect(state.get_stats().fire_resistance == 0.0 and state.equipment_instances.size() == 2, "Old save gets no free defense item or resistance")
	_expect(FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(backup), "Load is read-only and preserves original BOM/CRLF")
	_expect(state.save_build("user://defense_save_as.json") == OK and not FileAccess.file_exists(backup) and FileAccess.get_file_as_bytes(path) == bytes, "Save-as preserves pending source-byte protection")
	_expect(state.save_build(ProjectSettings.globalize_path(path)) == OK and FileAccess.get_file_as_bytes(backup) == bytes, "Absolute path alias creates the exact raw v7 backup before overwrite")
	var restored := Model.new()
	_expect(restored.load_build(path) and restored._snapshot() == expected and not restored.migrated_from_v7, "V8 reload is exact and does not migrate again")
	_expect(restored.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == bytes, "Subsequent writes preserve original backup")
	var conflict_path: String = "user://defense_conflict.json"
	_write(conflict_path, bytes)
	_write(conflict_path + ".v7-backup.json", JSON.stringify(legacy).to_utf8_buffer())
	var conflict := Model.new()
	_expect(conflict.load_build(conflict_path) and conflict.save_build(conflict_path) == ERR_ALREADY_EXISTS and FileAccess.get_file_as_bytes(conflict_path) == bytes, "Semantically equal but differently encoded backup conflicts fail closed")
	var stale_path: String = "user://defense_stale.json"
	_write(stale_path, bytes)
	var stale := Model.new()
	_expect(stale.load_build(stale_path), "Stale source fixture loads")
	var rewritten: PackedByteArray = JSON.stringify(legacy).to_utf8_buffer()
	_write(stale_path, rewritten)
	_expect(stale.save_build(stale_path) == ERR_FILE_ALREADY_IN_USE and FileAccess.get_file_as_bytes(stale_path) == rewritten, "Externally reformatted source cannot be overwritten during migration")
	completed = true

func _roundtrip_and_awards() -> void:
	var state := Model.new()
	var initial: Dictionary = state._snapshot()
	state.changed.connect(_changed)
	changes = 0
	var rng := _rng()
	var expected_rng := _rng()
	var expected: Dictionary = Catalog.generate_for_pool(expected_rng, "gear_000001", 16, "rare", "defense")
	var id: String = state.award_equipment(rng, 16, "rare", "defense")
	_expect(id == "gear_000001" and state.equipment_instances[id] == expected and rng.state == expected_rng.state and changes == 1, "Override grants one rare from defense pool with exact generator RNG")
	_expect(state.equipped == initial.equipped and state.next_equipment_id == 2 and state.inventory.size() == initial.inventory.size() + 1, "One award consumes one serial and never auto-equips")
	_expect(state.get_stats().fire_resistance == 0.0 and state.equip(id), "Unworn armor grants no resistance; equip succeeds")
	_expect(is_equal_approx(state.get_stats().fire_resistance, Catalog.get_stats(expected).fire_resistance), "Equipped armor reaches actual player stats")
	var snapshot: Dictionary = state._snapshot()
	_expect(Model.SAVE_VERSION == 8 and snapshot.size() == 16 and snapshot.equipment_instances[id].size() == 5, "V8 retains the exact 16-field save and five-field item schemas")
	var path: String = "user://defense_v8.json"
	_expect(state.save_build(path) == OK, "New defense gear saves")
	var restored := Model.new()
	_expect(restored.load_build(path) and restored._snapshot() == snapshot and restored.get_stats() == state.get_stats() and restored.get_item_definition(id) == state.get_item_definition(id), "V8 roundtrip preserves display, stat values and exact ownership without rerolling")
	var modes: Dictionary = {"legacy": "legacy", "expanded": "runewood", "runewood": "runewood", "defense": "defense"}
	for mode: String in modes:
		var single := Model.new()
		var actual_rng := _rng()
		var mirror := _rng()
		var item: Dictionary = Catalog.generate_for_pool(mirror, "gear_000001", 8, "magic", modes[mode])
		var granted: String = single.award_equipment(actual_rng, 8, "magic", mode)
		_expect(single.equipment_instances[granted] == item and actual_rng.state == mirror.state, "Named award mode preserves generator semantics: " + mode)
	for mode: String in ["loot", "current"]:
		var single := Model.new()
		var actual_rng := _rng()
		var mirror := _rng()
		var item: Dictionary = Catalog.generate_loot(mirror, "gear_000001", 8, "magic") if mode == "loot" else Catalog.generate_current_loot(mirror, "gear_000001", 8, "magic")
		var granted: String = single.award_equipment(actual_rng, 8, "magic", mode)
		_expect(single.equipment_instances[granted] == item and actual_rng.state == mirror.state, "Historical versus current mix dispatch is explicit: " + mode)
	var defaults := Model.new()
	var default_rng := _rng()
	var mirror := _rng()
	var default_id: String = defaults.award_equipment(default_rng, 8, "rare")
	_expect(defaults.equipment_instances[default_id] == Catalog.generate(mirror, default_id, 8, "rare") and default_rng.state == mirror.state, "Existing generic default remains legacy for old callers")
	completed = true

func _reject(state: Model, value: Dictionary, label: String) -> void:
	var path: String = "user://defense_reject.json"
	var bytes: PackedByteArray = _raw(value)
	_write(path, bytes)
	var before: Dictionary = state._snapshot()
	var signals_before: int = changes
	_expect(not state.load_build(path) and state._snapshot() == before and changes == signals_before, "Tampered load is atomic and silent: " + label)
	_expect(state.save_build(ProjectSettings.globalize_path(path)) == ERR_INVALID_DATA and FileAccess.get_file_as_bytes(path) == bytes, "Rejected file and its absolute alias remain protected: " + label)

func _tamper() -> void:
	var state := Model.new()
	state.changed.connect(_changed)
	var id: String = state.award_equipment(_rng(), 16, "normal", "defense")
	var valid: Dictionary = state._snapshot()
	for version: int in range(1, 8):
		var bad: Dictionary = valid.duplicate(true)
		bad.version = version
		_reject(state, bad, "New base injected into version %d" % version)
	var bad: Dictionary = valid.duplicate(true)
	bad.equipment_instances[id].base_id = "woven_bastion"
	bad.equipment_instances[id].rarity = "magic"
	bad.equipment_instances[id].affixes = [{"id":"emberward","tier":1,"value":10}]
	for version: int in [4, 5, 6, 7, 8]:
		bad.version = version
		_reject(state, bad, "Defense suffix on original armor in version %d" % version)
	bad = valid.duplicate(true)
	bad.version = 9
	_reject(state, bad, "Future schema")
	for field: String in ["fire_resistance", "stats", "stage", "pool_id"]:
		bad = valid.duplicate(true)
		bad.equipment_instances[id][field] = 999
		_reject(state, bad, "Unexpected executable item field " + field)
	var before: Dictionary = state._snapshot()
	var rng := _rng()
	var rng_before: int = rng.state
	var signals_before: int = changes
	_expect(state.award_equipment(rng, 16, "rare", "unknown").is_empty() and state.award_equipment(rng, 31, "rare", "defense").is_empty() and state.award_equipment(rng, 16, "mythic", "current").is_empty(), "Invalid award requests reject")
	_expect(state._snapshot() == before and rng.state == rng_before and changes == signals_before, "Invalid request rejection preserves RNG, serial, ownership and signals")
	completed = true

func _capacity() -> void:
	var state := Model.new()
	state.inventory.clear()
	state.equipped.clear()
	state.jewels.clear()
	state.jewel_inventory.clear()
	# Twelve body armors plus twenty-four charms reserve every cell, even with worn gear.
	for serial: int in range(1, 37):
		var id: String = "gear_%06d" % serial
		state.equipment_instances[id] = {"id":id,"base_id":"woven_bastion" if serial <= 12 else "wayglass_token","rarity":"normal","item_level":1,"affixes":[]}
		state.inventory.append(id)
	state.next_equipment_id = 37
	state.equipped["armor"] = "gear_000001"
	state._sync_backpack()
	state.changed.connect(_changed)
	changes = 0
	var before: Dictionary = state._snapshot()
	_expect(not state._validate_snapshot(before).is_empty(), "Full reserved grid is a valid save")
	var rng := _rng()
	var mirror := _rng()
	Catalog.generate_for_pool(mirror, "gear_000037", 16, "rare", "defense")
	_expect(state.award_equipment(rng, 16, "rare", "defense").is_empty() and state._snapshot() == before and changes == 0, "Full ownership rejects exactly one attempted reward without consuming identity or item state")
	_expect(rng.state == mirror.state, "Post-roll capacity rejection preserves the historical consumed-roll RNG contract")
	state.next_equipment_id = Model.MAX_EQUIPMENT_ID + 1
	var rng_before: int = rng.state
	_expect(state.award_equipment(rng, 16, "rare", "defense").is_empty() and rng.state == rng_before, "Exhausted serial refuses before any RNG draw")
	completed = true
