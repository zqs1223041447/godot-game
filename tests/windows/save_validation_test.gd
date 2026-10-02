extends SceneTree
const Sandbox = preload("res://tests/windows/save_sandbox.gd")
const Fixture = preload("res://tests/windows/save_fixture.gd")
var model_script: Variant
var checks: int = 0
var failures: int = 0
var changes: int = 0
var completed: bool = false
var cases: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SAVE_QA_FAIL: " + label)


func _changed() -> void:
	changes += 1


func _write(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Fixture opens in sandbox: " + path)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	_expect(ok, "Fixture writes completely: " + path)
	return ok


func _run() -> void:
	if not Sandbox.verify():
		quit(78)
		return
	model_script = load("res://scripts/build_state.gd")
	if model_script == null:
		quit(1)
		return
	_expect(model_script.SAVE_VERSION == 9, "This suite targets v0.13 schema9")
	_expect(DirAccess.make_dir_recursive_absolute("user://中文 存档") == OK, "Chinese and spaced save directory")
	for test: Callable in [_migration_matrix, _current_roundtrip, _rejected_sources, _backup_conflicts, _stale_source]:
		completed = false
		test.call()
		_expect(completed, "Case completed without script exceptions: " + test.get_method())
		cases.append(test.get_method())
	print("SAVE_QA_RESULT " + JSON.stringify({"case": "save-contracts", "checks": checks,
		"failures": failures, "completed": completed and cases.size() == 5,
		"cases": cases, "migration_encodings": 32}))
	quit(0 if failures == 0 else 1)


func _migration_matrix() -> void:
	for version: int in range(1, 9):
		for bom: bool in [false, true]:
			for crlf: bool in [false, true]:
				_migrate_one(version, bom, crlf)
	completed = true


func _migrate_one(version: int, bom: bool, crlf: bool) -> void:
	var tag: String = "v%d-bom%d-crlf%d" % [version, int(bom), int(crlf)]
	var path: String = "user://中文 存档/历史 " + tag + ".json"
	var backup: String = path + ".v%d-backup.json" % version
	var original: PackedByteArray = Fixture.bytes(version, bom, crlf)
	var legacy: Dictionary = Fixture.record(version)
	_expect(not legacy.is_empty() and legacy.version == version, tag + " literal historical version")
	_expect(original.slice(0, 3) == PackedByteArray([239, 187, 191]) if bom else original[0] == (13 if crlf else 10), tag + " explicit BOM variant")
	var text: String = original.get_string_from_utf8()
	_expect(text.contains("\r\n") == crlf and (not crlf or not text.replace("\r\n", "").contains("\n")), tag + " explicit line endings")
	if not _write(path, original):
		return
	var state: Variant = model_script.new()
	state.changed.connect(_changed)
	changes = 0
	if not state.load_build(path):
		_expect(false, tag + " load: " + state.last_load_error)
		return
	_expect(changes == 1 and state.get("migrated_from_v%d" % version), tag + " atomic migration and one change signal")
	var migrated: Dictionary = state._snapshot()
	_expect(migrated.version == 9 and migrated.size() == 16, tag + " current allowlisted schema")
	for field: String in legacy:
		if field in ["version", "talents"] or (version <= 2 and field in ["inventory", "backpack_positions", "talent_points"]):
			continue
		_expect(Fixture.equivalent(migrated[field], legacy[field]), tag + " preserves " + field)
	if version <= 2:
		for item: String in legacy.inventory:
			_expect(migrated.inventory.has(item), tag + " retains historical fixed item " + item)
		for item: String in ["prism_bow", "return_mantle", "detonation_charm"]:
			_expect(migrated.inventory.has(item), tag + " documented combat starter " + item)
		_expect(migrated.inventory.size() == legacy.inventory.size() + 3, tag + " only documented starter additions")
		if version == 1:
			_expect(migrated.talent_points == 8 and migrated.allocated_nodes == ["origin"], tag + " refunds five old ranks")
			_expect(migrated.next_jewel_id == 4 and migrated.jewel_inventory == ["jewel_000001", "jewel_000002", "jewel_000003"], tag + " historical starter jewels")
		else:
			_expect(migrated.talent_points == legacy.talent_points, tag + " does not refund v2 points")
			for key: String in legacy.backpack_positions:
				_expect(Fixture.equivalent(migrated.backpack_positions[key], legacy.backpack_positions[key]), tag + " preserves original cell " + key)
	if version < 4:
		_expect(migrated.equipment_instances.is_empty() and migrated.next_equipment_id == 1, tag + " no rerolled equipment")
	if version < 5:
		_expect(migrated.skill_supports.is_empty(), tag + " no implicit supports")
	_expect(FileAccess.get_file_as_bytes(path) == original and not FileAccess.file_exists(backup), tag + " read-only load preserves original")
	var copy_path: String = "user://中文 存档/另存 " + tag + ".json"
	_expect(state.save_build(copy_path) == OK, tag + " safe Save As")
	var copied: Variant = model_script.new()
	_expect(copied.load_build(copy_path) and copied._snapshot() == migrated, tag + " full Save As roundtrip")
	_expect(FileAccess.get_file_as_bytes(path) == original and not FileAccess.file_exists(backup), tag + " Save As retains pending original protection")
	changes = 0
	_expect(state.save_build(ProjectSettings.globalize_path(path)) == OK, tag + " absolute alias upgrade")
	_expect(changes == 0 and FileAccess.get_file_as_bytes(backup) == original, tag + " byte-exact backup and no save signal")
	_expect(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(backup + ".tmp"), tag + " no leftover temporary writes")
	var restored: Variant = model_script.new()
	_expect(restored.load_build(path) and restored._snapshot() == migrated and not restored.get("migrated_from_v%d" % version), tag + " exact v9 reload")
	_expect(restored.save_build(path) == OK and state.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == original, tag + " backup survives repeated saves")


func _current_roundtrip() -> void:
	var path: String = "user://中文 存档/当前 v9.json"
	var original: PackedByteArray = Fixture.bytes(9)
	if not _write(path, original):
		return
	var state: Variant = model_script.new()
	var loaded: bool = state.load_build(path)
	_expect(loaded and Fixture.equivalent(state._snapshot(), Fixture.record(9)), "Literal v9 preserves all 16 fields: " + state.last_load_error)
	if not loaded:
		completed = true
		return
	var expected: Dictionary = state._snapshot()
	var stats: Dictionary = state.get_stats()
	var combat: Dictionary = state.get_combat_snapshot()
	_expect(combat.has("weapon_profile"), "v9 fixture actually exercises local weapon profile")
	for iteration: int in range(3):
		_expect(state.save_build(path) == OK, "v9 replacement %d" % iteration)
		var restored: Variant = model_script.new()
		_expect(restored.load_build(path) and restored._snapshot() == expected, "v9 full roundtrip %d" % iteration)
		_expect(restored.get_stats() == stats and restored.get_combat_snapshot() == combat, "v9 derived values roundtrip %d" % iteration)
		state = restored
	_expect(not FileAccess.file_exists(path + ".v9-backup.json") and not FileAccess.file_exists(path + ".tmp"), "Current version creates no legacy backup or residual temp")
	completed = true


func _rejected_sources() -> void:
	var oversized: PackedByteArray = " ".repeat(model_script.MAX_SAVE_BYTES + 1).to_utf8_buffer()
	var sources: Dictionary = {"未来 v10": Fixture.bytes(10), "损坏 JSON": "\r\n  { invalid source bytes \r\n".to_utf8_buffer(), "超限": oversized}
	for label: String in sources:
		var path: String = "user://中文 存档/拒绝 " + label + ".json"
		var original: PackedByteArray = sources[label]
		if not _write(path, original):
			continue
		var state: Variant = model_script.new()
		state.changed.connect(_changed)
		var before: Dictionary = state._snapshot()
		changes = 0
		_expect(not state.load_build(path) and state._snapshot() == before and changes == 0, label + " rejects without partial commit")
		_expect(not state.save_block_reason(path).is_empty(), label + " protected source guard")
		state.add_xp(1)
		var dirty: Dictionary = state._snapshot()
		changes = 0
		_expect(state.save_build(path) == ERR_INVALID_DATA and state.save_build(ProjectSettings.globalize_path(path)) == ERR_INVALID_DATA, label + " guards both user and absolute aliases")
		_expect(state._snapshot() == dirty and changes == 0 and FileAccess.get_file_as_bytes(path) == original, label + " blocked writes preserve model and source bytes")
		_expect(state.save_build("user://中文 存档/安全副本 " + label + ".json") == OK and not state.save_block_reason(path).is_empty(), label + " Save As keeps original guard")
		_expect(not FileAccess.file_exists(path + ".tmp"), label + " blocked save never starts temporary write")
		_expect(_write(path, Fixture.bytes(9)) and state.load_build(path) and state.save_block_reason(path).is_empty(), label + " valid external restoration unlocks source")
		_expect(state.save_build(path) == OK, label + " restored save works")
	completed = true


func _backup_conflicts() -> void:
	for version: int in range(1, 9):
		var original: PackedByteArray = Fixture.bytes(version)
		var conflict_bytes: PackedByteArray = Fixture.bytes(version, false, false)
		for matching: bool in [false, true]:
			var path: String = "user://中文 存档/备份 v%d 匹配%d.json" % [version, int(matching)]
			var backup: String = path + ".v%d-backup.json" % version
			var backup_bytes: PackedByteArray = original if matching else conflict_bytes
			if not _write(path, original) or not _write(backup, backup_bytes):
				continue
			var state: Variant = model_script.new()
			_expect(state.load_build(path), "v%d backup fixture loads" % version)
			var expected: Dictionary = state._snapshot()
			var result: Error = state.save_build(path)
			_expect(result == (OK if matching else ERR_ALREADY_EXISTS), "v%d byte identity controls backup reuse" % version)
			_expect(state._snapshot() == expected and FileAccess.get_file_as_bytes(backup) == backup_bytes, "v%d existing backup stays byte exact" % version)
			if not matching:
				_expect(FileAccess.get_file_as_bytes(path) == original and not FileAccess.file_exists(path + ".tmp"), "v%d conflicting encoding protects both files" % version)
				_expect(DirAccess.remove_absolute(backup) == OK and state.save_build(path) == OK, "v%d explicit conflict resolution permits retry" % version)
				_expect(FileAccess.get_file_as_bytes(backup) == original, "v%d retry preserves true original" % version)
	completed = true


func _stale_source() -> void:
	for version: int in range(1, 9):
		var path: String = "user://中文 存档/并发修改 v%d.json" % version
		var original: PackedByteArray = Fixture.bytes(version)
		var rewritten: PackedByteArray = Fixture.bytes(version, false, false)
		if not _write(path, original):
			continue
		var state: Variant = model_script.new()
		_expect(state.load_build(path), "v%d stale fixture loads" % version)
		_expect(_write(path, rewritten), "v%d external source rewrite" % version)
		_expect(state.save_build(path) == ERR_FILE_ALREADY_IN_USE, "v%d external byte change blocks migration overwrite" % version)
		_expect(FileAccess.get_file_as_bytes(path) == rewritten and not FileAccess.file_exists(path + ".v%d-backup.json" % version), "v%d no mislabeled backup or overwrite" % version)
		_expect(_write(path, original) and state.save_build(path) == OK, "v%d exact source restoration permits safe retry" % version)
	completed = true
