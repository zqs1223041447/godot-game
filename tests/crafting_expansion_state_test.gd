extends "res://tests/crafting_state_test.gd"
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
func _run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if OS.get_name() != "Linux" or not isolated.begins_with("/tmp/godot-crafting-qa-") or not OS.get_user_data_dir().simplify_path().begins_with(isolated + "/"):
		quit(78)
		return
	for pool: String in ["legacy", "runewood", "defense", "local_weapon"]:
		for operation: String in ["enchant", "elevate", "augment", "reforge"]:
			_case(pool, operation)
	print("Crafting expansion state: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
func _case(pool: String, operation: String) -> void:
	var state := Model.new()
	var rng := _rng(20001 + pool.length() * 5 + operation.length())
	var path: String = "user://growth_%s_%s.json" % [pool, operation]
	var rarity: String = "normal" if operation == "enchant" else "magic"
	var id: String = _give(state, rng, rarity, pool)
	if operation == "augment" and state.equipment_instances[id].affixes.size() == 2:
		# Explicit legal one-affix fixture; no custom illegal field or free wallet.
		state.equipment_instances[id].affixes.resize(1)
	_expect(Catalog.validate_instance(state.equipment_instances[id]), "Stage input is a valid actual catalog item")
	_fund(state, rng, path, 100)
	_expect(state.save_build(path) == OK, "Pre-operation full snapshot saved")
	var before: Dictionary = state._snapshot()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var quote: Dictionary = state.crafting_quote(operation, id, path)
	_expect(quote.ok and not quote.has("seed") and not quote.has("instance"), "Issued quote hides random result and seed")
	var cancelled: String = quote.handle
	state.cancel_crafting_quote(cancelled)
	_expect(not state.execute_crafting(cancelled, quote.source_instance).ok and state._snapshot() == before, "Cancel preserves all state")
	quote = state.crafting_quote(operation, id, path)
	var rejected: Dictionary = quote.source_instance.duplicate(true)
	rejected.item_level = 1
	_expect(not state.execute_crafting(quote.handle, rejected).ok and state._snapshot() == before, "Forged source rejected atomically")
	_expect(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Test-owned write fault installed")
	state.changed.connect(_changed)
	changes = 0
	var attempts: int = state.primary_save_attempt_count
	var failure: Dictionary = state.execute_crafting(quote.handle, quote.source_instance)
	_expect(not failure.ok and failure.code == "save_failed", "Write failure reported")
	_expect(changes == 0 and state._snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Failure preserves memory, currency, revision and old bytes")
	_expect(DirAccess.remove_absolute(path + ".tmp") == OK, "Only test-owned fault removed")
	var result: Dictionary = state.execute_crafting(quote.handle, quote.source_instance)
	_expect(result.ok and changes == 1 and state.primary_save_attempt_count == attempts + 2, "Failed attempt plus exactly one successful write/notification")
	_expect(_disk_matches(state, path) and not state._validate_snapshot(state._snapshot()).is_empty(), "Whole schema13 result persists and validates")
	_expect(state.crafting.revision == before.crafting.revision + 1 and state.crafting_balance() == int(before.crafting.materials.calibration_shard) - int(quote.cost.calibration_shard), "Exact cost and one revision")
	var repeated: Dictionary = state._snapshot()
	_expect(not state.execute_crafting(quote.handle, quote.source_instance).ok and state._snapshot() == repeated, "Repeated confirmation rejected")
	var after_item: Dictionary = state.equipment_instances[id]
	for field: String in ["id", "base_id", "item_level"]:
		_expect(after_item[field] == before.equipment_instances[id][field], "Identity/base/ilvl preserved")
	for field: String in ["allocated_nodes", "jewels", "socketed_jewels", "backpack_positions", "next_equipment_id", "skill_supports", "equipped"]:
		_expect(state._snapshot()[field] == before[field], "Unrelated full-build data survives")
	var restored := Model.new()
	_expect(restored.load_build(path) and restored._snapshot() == state._snapshot(), "Full saved output reloads under same schema")
	var mirror_path: String = path + ".mirror"
	_write(mirror_path, bytes)
	var mirror := Model.new()
	_expect(mirror.load_build(mirror_path), "Exact pre-failure snapshot reloads")
	var mirror_result: Dictionary = _execute(mirror, operation, id, mirror_path)
	_expect(mirror_result.ok and mirror.equipment_instances[id] == after_item and mirror.crafting == state.crafting, "Failure, cancel and reload cannot change authoritative roll")
	_expect(state.equip(id), "Crafted result equips through real model")
	var snapshot: Dictionary = state.get_combat_snapshot()
	for skill: String in ["tornado", "bolt", "meteor"]:
		var compiled: Dictionary = Compiler.compile_skill(skill, snapshot, [])
		_expect(compiled.get("error", "").is_empty(), "Crafted item consumed by actual skill compiler")
	_expect(state.get_item_definition(id) == Catalog.definition(after_item), "Actual UI equipment definition is same-source")
