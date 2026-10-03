extends SceneTree
const Model = preload("res://scripts/build_state.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
var checks: int = 0
var failures: int = 0
var changes: int = 0
var completed: bool = false

func _initialize() -> void: call_deferred("_run")

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if OS.get_name() != "Linux" or not isolated.begins_with("/tmp/godot-crafting-qa-") or not OS.get_user_data_dir().simplify_path().begins_with(isolated + "/"):
		printerr("Crafting write tests refuse non-isolated/default user data")
		quit(78)
		return
	for test: Callable in [_natural_transactions, _write_failure_retry, _quote_authority, _migration_and_guards, _schema_and_capacity, _bounded_sequence]:
		completed = false
		test.call()
		_expect(completed, "Case completes: " + test.get_method())
	print("Crafting state: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _rng(value: int = 15001) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng

func _give(state: BuildState, rng: RandomNumberGenerator, rarity: String = "rare", pool: String = "current") -> String:
	var id: String = state.award_equipment(rng, 30, rarity, pool)
	_expect(not id.is_empty(), "Actual catalog reward obtains crafting input")
	return id

func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Artificial fixture opens inside isolated userdata")
	if file != null:
		file.store_buffer(bytes)
		file.close()

func _disk_matches(state: BuildState, path: String) -> bool:
	return FileAccess.get_file_as_string(path) == JSON.stringify(state._snapshot(), "\t", true, true)

func _execute(state: BuildState, operation: String, id: String, path: String) -> Dictionary:
	var quote: Dictionary = state.crafting_quote(operation, id, path)
	_expect(quote.ok, "Authoritative quote admits " + operation)
	if not quote.ok:
		return quote
	return state.execute_crafting(quote.handle, quote.source_instance)

func _changed() -> void: changes += 1

func _fund(state: BuildState, rng: RandomNumberGenerator, path: String, amount: int) -> void:
	for unused: int in range(200):
		if state.crafting_balance() >= amount: return
		var id: String = _give(state, rng)
		if id.is_empty(): return
		_expect(_execute(state, "salvage", id, path).ok, "Natural spare gear supplies the one crafting material")
	_expect(false, "Bounded funding loop reaches target")

func _natural_transactions() -> void:
	var state := Model.new()
	var rng := _rng()
	var path: String = "user://craft_natural.json"
	var target: String = _give(state, rng, "magic", "local_weapon")
	var spare: String = _give(state, rng)
	_expect(state.save_build(path) == OK, "Initial actual reward build saves")
	_expect(state.crafting_balance() == 0 and state.crafting.revision == 0, "Fresh build gets no free currency or crafts")
	var unaffordable: Dictionary = state.crafting_quote("recalibrate", target, path)
	_expect(not unaffordable.ok and unaffordable.code == "insufficient_materials", "No calibration before earning sufficient shards")
	var quote: Dictionary = state.crafting_quote("salvage", spare, path)
	var before: Dictionary = state._snapshot()
	var expected_gain: int = 3
	for affix: Dictionary in state.equipment_instances[spare].affixes: expected_gain += int(affix.tier)
	_expect(quote.ok and int(quote.materials.calibration_shard) == expected_gain and not quote.has("seed") and not quote.has("instance"), "Quote exposes exact tunable economics, no result or seed")
	state.changed.connect(_changed)
	changes = 0
	var writes: int = state.primary_save_attempt_count
	var result: Dictionary = state.execute_crafting(quote.handle, quote.source_instance)
	_expect(result.ok and state.crafting_balance() == expected_gain and state.crafting.revision == 1, "Salvage credits exact units and advances one successful sequence")
	_expect(changes == 1 and state.primary_save_attempt_count == writes + 1 and _disk_matches(state, path), "One signal follows one complete durable primary write")
	_expect(not state.inventory.has(spare) and not state.equipment_instances.has(spare) and not state.backpack_positions.has("item:" + spare), "Salvage removes exactly the instance, ownership and occupied cells")
	for field: String in ["jewels", "jewel_inventory", "socketed_jewels", "skill_supports", "allocated_nodes", "equipped", "next_equipment_id"]:
		_expect(state._snapshot()[field] == before[field], "Salvage preserves unrelated full-build field " + field)
	_expect(not state.execute_crafting(quote.handle, quote.source_instance).ok and state.crafting.revision == 1, "Repeated confirmation cannot spend or receive twice")
	_fund(state, rng, path, 20)
	var source: Dictionary = state.equipment_instances[target].duplicate(true)
	var balance: int = state.crafting_balance()
	var revision: int = state.crafting.revision
	var cost: int = int(Craft.recalibrate_plan(source, 0).cost.calibration_shard)
	result = _execute(state, "recalibrate", target, path)
	_expect(result.ok and state.crafting_balance() == balance - cost and state.crafting.revision == revision + 1, "Calibration consumes exact shards once")
	var changed: Dictionary = state.equipment_instances[target]
	for field: String in ["id", "base_id", "rarity", "item_level"]:
		_expect(changed[field] == source[field], "Calibration preserves " + field)
	for index: int in range(source.affixes.size()):
		_expect(changed.affixes[index].id == source.affixes[index].id and changed.affixes[index].tier == source.affixes[index].tier, "Affix family, order and tier never reroll")
	_expect(Catalog.validate_instance(changed) and _disk_matches(state, path), "Actual replacement remains catalog-valid and exactly saved")
	var restored := Model.new()
	_expect(restored.load_build(path) and restored._snapshot() == state._snapshot(), "Wallet, sequence, rolls and full ownership roundtrip")
	completed = true

func _write_failure_retry() -> void:
	var state := Model.new()
	var rng := _rng(15002)
	var path: String = "user://craft_fail.json"
	var target: String = _give(state, rng, "magic", "local_weapon")
	_fund(state, rng, path, 30)
	var before: Dictionary = state._snapshot()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var mirror_path: String = "user://craft_mirror.json"
	_write(mirror_path, bytes)
	var quote: Dictionary = state.crafting_quote("recalibrate", target, path)
	_expect(quote.ok, "Failure-path quote is valid before file fault")
	_expect(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create only this artificial temporary-path directory conflict")
	state.changed.connect(_changed)
	changes = 0
	seed(150099)
	var expected_rng: float = randf()
	seed(150099)
	var failed: Dictionary = state.execute_crafting(quote.handle, quote.source_instance)
	_expect(not failed.ok and failed.code == "save_failed", "Disk failure returns explicit rejected transaction")
	_expect(state._snapshot() == before and changes == 0 and FileAccess.get_file_as_bytes(path) == bytes, "Failed persistence preserves complete memory, wallet, sequence, original file and signals")
	_expect(randf() == expected_rng, "Crafting failures do not consume global RNG")
	_expect(DirAccess.dir_exists_absolute(path + ".tmp"), "Unrelated conflicting directory is not removed")
	_expect(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove this test-owned conflict")
	var succeeded: Dictionary = state.execute_crafting(quote.handle, quote.source_instance)
	_expect(succeeded.ok and changes == 1 and _disk_matches(state, path), "Same issued handle can safely retry after I/O recovery")
	var mirror := Model.new()
	_expect(mirror.load_build(mirror_path), "Independent pre-failure snapshot loads")
	var mirror_result: Dictionary = _execute(mirror, "recalibrate", target, mirror_path)
	_expect(mirror_result.ok and mirror.equipment_instances[target] == state.equipment_instances[target], "Failure/reload cannot choose a different seed or result for identical authoritative item/sequence")
	_expect(mirror.crafting == state.crafting, "Retry and direct success pay exactly the same cost and sequence")
	completed = true

func _quote_authority() -> void:
	var state := Model.new()
	var rng := _rng(15003)
	var path: String = "user://craft_quotes.json"
	var id: String = _give(state, rng)
	_expect(state.save_build(path) == OK, "Quote authority fixture saves")
	var quote: Dictionary = state.crafting_quote("salvage", id, path)
	var forged_source: Dictionary = quote.source_instance.duplicate(true)
	forged_source.affixes[0].value += 1
	var before: Dictionary = state._snapshot()
	_expect(not state.execute_crafting(quote.handle, forged_source).ok and state._snapshot() == before, "Caller cannot substitute source rolls")
	_expect(not state.execute_crafting("invented", quote.source_instance).ok, "Caller cannot invent quote handles")
	var other := Model.new()
	_expect(not other.execute_crafting(quote.handle, quote.source_instance).ok, "Quote belongs to its issuing model")
	state.add_xp(1)
	_expect(not state.execute_crafting(quote.handle, quote.source_instance).ok and state.inventory.has(id), "Full-build changes invalidate old quotes")
	quote = state.crafting_quote("salvage", id, path)
	state.cancel_crafting_quote(quote.handle)
	_expect(not state.execute_crafting(quote.handle, quote.source_instance).ok, "Cancelled quote is not an executable transaction")
	quote = state.crafting_quote("salvage", id, path)
	_expect(state.load_build(path) and not state.execute_crafting(quote.handle, quote.source_instance).ok, "Every successful load clears pending authority even if item data matches")
	quote = state.crafting_quote("salvage", id, path)
	_expect(not state.load_build("user://absent_craft_source.json") and not state.execute_crafting(quote.handle, quote.source_instance).ok, "Even failed loads clear pending quote authority")
	quote = state.crafting_quote("salvage", id, path)
	var changed_file: Dictionary = state._snapshot()
	changed_file.version = Model.SAVE_VERSION + 1
	var future: PackedByteArray = JSON.stringify(changed_file).to_utf8_buffer()
	_write(path, future)
	_expect(not state.execute_crafting(quote.handle, quote.source_instance).ok and FileAccess.get_file_as_bytes(path) == future, "External future replacement cannot be overwritten by a pending craft")
	_expect(not state.crafting_quote("salvage", id, path).ok and state.save_build(path) == ERR_INVALID_DATA, "Requoting and autosave cannot bypass newly detected source protection")
	completed = true

func _migration_and_guards() -> void:
	var literal: String = FileAccess.get_file_as_string("res://tests/fixtures/crafting_v10_build.json")
	var bytes: PackedByteArray = PackedByteArray([239,187,191])
	bytes.append_array(("\r\n " + literal.replace("\n", "\r\n") + "\r\n").to_utf8_buffer())
	var path: String = "user://craft_v10.json"
	_write(path, bytes)
	var state := Model.new()
	_expect(state.load_build(path) and state.migrated_from_v10 and state.crafting_balance() == 0 and state.crafting.revision == 0, "Literal v10 migrates to empty wallet without free materials or changing rolls")
	var expected: Dictionary = JSON.parse_string(literal)
	expected.version = Model.SAVE_VERSION
	expected.crafting = {"materials":{"calibration_shard":0},"revision":0}
	_expect(JSON.parse_string(JSON.stringify(state._snapshot())) == JSON.parse_string(JSON.stringify(expected)) and FileAccess.get_file_as_bytes(path) == bytes, "Read-only v10 migration preserves all historical fields and bytes")
	_expect(state.unequip("weapon"), "Historical local weapon can enter backpack normally")
	var result: Dictionary = _execute(state, "salvage", "gear_000042", ProjectSettings.globalize_path(path))
	_expect(result.ok and FileAccess.get_file_as_bytes(path + ".v10-backup.json") == bytes, "First crafting commit preserves exact legacy BOM/CRLF bytes through an absolute alias")
	_expect(_disk_matches(state,path) and state.crafting.revision == 1, "Migration and one craft persist together as one current snapshot")
	var restored := Model.new()
	_expect(restored.load_build(path) and restored._snapshot() == state._snapshot(), "Crafting migration reload includes wallet and historical jewel allocation")
	completed = true

func _schema_and_capacity() -> void:
	var state := Model.new()
	var rng := _rng(15004)
	var id: String = _give(state,rng)
	var normal: String = _give(state,rng,"normal")
	for candidate: String in ["ember_wand", normal, "not_owned"]:
		_expect(not state.crafting_quote("salvage",candidate).ok, "Fixed, normal and unowned items are excluded")
	_expect(state.equip(id) and not state.crafting_quote("salvage",id).ok and not state.crafting_quote("recalibrate",id).ok, "Worn gear cannot be consumed or recalibrated")
	_expect(state.unequip(state.get_item_definition(id).slot), "Return eligible item to backpack")
	var valid: Dictionary = state._snapshot()
	_expect(valid.size() == 17 and Model.SAVE_VERSION == 13 and not state._validate_snapshot(valid).is_empty(), "Exactly one versioned crafting field extends the save")
	for invalid: Variant in [-1, 0.5, true, "2", Model.MAX_CRAFT_MATERIALS+1, INF, NAN]:
		var bad: Dictionary = valid.duplicate(true)
		bad.crafting.materials.calibration_shard = invalid
		_expect(state._validate_snapshot(bad).is_empty(), "Malformed or out-of-range wallet rejects whole build")
	for invalid: Variant in [-1, 0.5, true, "2", Model.MAX_CRAFT_REVISION+1]:
		var bad: Dictionary = valid.duplicate(true)
		bad.crafting.revision = invalid
		_expect(state._validate_snapshot(bad).is_empty(), "Malformed sequence rejects whole build")
	var old: Dictionary = valid.duplicate(true)
	old.version = 10
	_expect(state._validate_snapshot(old).is_empty(), "Old schemas cannot inject a new wallet")
	old.erase("crafting")
	_expect(not state._validate_snapshot(old).is_empty(), "Real v10 shape remains supported")
	var overlap: Dictionary = valid.duplicate(true)
	overlap.backpack_positions["item:"+id] = overlap.backpack_positions["item:"+normal]
	_expect(state._validate_snapshot(overlap).is_empty(), "Full build validates layout beyond planner projection")
	state.crafting.materials.calibration_shard = Model.MAX_CRAFT_MATERIALS
	_expect(not state.crafting_quote("salvage",id).ok, "Wallet cap rejects gain before consuming gear")
	state.crafting.materials.calibration_shard = 0
	state.crafting.revision = Model.MAX_CRAFT_REVISION
	_expect(not state.crafting_quote("salvage",id).ok, "Sequence cap rejects before any candidate or write")
	completed = true

func _bounded_sequence() -> void:
	var state := Model.new()
	var rng := _rng(15005)
	var path: String = "user://craft_sequence.json"
	var id: String = _give(state,rng,"magic","local_weapon")
	_fund(state,rng,path,200)
	var original: Dictionary = state.equipment_instances[id].duplicate(true)
	var cost: int = Craft.recalibrate_plan(original,0).cost.calibration_shard
	var starting_balance: int = state.crafting_balance()
	var starting_revision: int = state.crafting.revision
	for index: int in range(15):
		var result: Dictionary = _execute(state,"recalibrate",id,path)
		_expect(result.ok and Catalog.validate_instance(state.equipment_instances[id]), "Every paid sequence result is catalog-valid")
		_expect(state.crafting_balance() == starting_balance-cost*(index+1) and state.crafting.revision == starting_revision+index+1, "No duplication or skipped costs across repeated requests")
		_expect(_disk_matches(state,path) and state.equipment_instances[id].affixes.size() == original.affixes.size(), "Every transaction saves the exact complete state")
	completed = true
