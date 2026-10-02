extends SceneTree
## Run only in a probed disposable copy of schema10 integration sources.
const Sandbox = preload("res://tests/windows/save_sandbox.gd")
const Fixture = preload("res://tests/windows/save_fixture.gd")
var model_script: Variant
var checks: int = 0
var failures: int = 0
var completed: bool = false
var cases: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SAVE_QA_FAIL: " + label)

func _write(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Schema10 fixture opens inside sandbox")
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	_expect(ok, "Schema10 fixture bytes flush")
	return ok

func _run() -> void:
	if not Sandbox.verify():
		quit(78)
		return
	model_script = load("res://scripts/build_state.gd")
	if model_script == null:
		quit(1)
		return
	_expect(model_script.SAVE_VERSION == 10, "Extra integration regression uses schema10")
	_expect(DirAccess.make_dir_recursive_absolute("user://中文 存档/集成 子目录") == OK, "Integration aliases stay inside sandbox")
	for test: Callable in [_future_v11, _legacy_v8_v9, _backup_conflict, _stale_source]:
		completed = false
		test.call()
		_expect(completed, "Schema10 alias case completes: " + test.get_method())
		cases.append(test.get_method())
	print("SAVE_QA_RESULT " + JSON.stringify({"case": "schema10-save-aliases", "checks": checks,
		"failures": failures, "completed": completed and cases.size() == 4, "cases": cases}))
	quit(0 if failures == 0 else 1)

func _future_v11() -> void:
	var path: String = "user://中文 存档/Future v11.json"
	var future: Dictionary = Fixture.record(10)
	future.version = 11
	var bytes: PackedByteArray = PackedByteArray([239, 187, 191])
	bytes.append_array((JSON.stringify(future, "\t").replace("\n", "\r\n") + "\r\n").to_utf8_buffer())
	if not _write(path, bytes):
		return
	var state: Variant = model_script.new()
	var alias: String = ProjectSettings.globalize_path(path).to_upper()
	_expect(not state.load_build(path), "Schema10 rejects future v11")
	_expect(FileAccess.get_file_as_bytes(alias) == bytes, "v11 uppercase alias reads the original source")
	_expect(not state.save_block_reason(alias).is_empty(), "v11 uppercase alias remains protected")
	_expect(state.save_build(alias) == ERR_INVALID_DATA and FileAccess.get_file_as_bytes(path) == bytes, "v11 uppercase save cannot overwrite future source")
	completed = true

func _legacy_v8_v9() -> void:
	for version: int in [8, 9]:
		for dotted: bool in [false, true]:
			var path: String = "user://中文 存档/Legacy v%d dot%d.json" % [version, int(dotted)]
			var source: PackedByteArray = Fixture.bytes(version, true, true)
			var backup: String = path + ".v%d-backup.json" % version
			if not _write(path, source):
				return
			var state: Variant = model_script.new()
			_expect(state.load_build(path), "Schema10 loads historical v%d" % version)
			var expected: Dictionary = state._snapshot()
			var alias: String = ProjectSettings.globalize_path(path).to_upper()
			if dotted:
				alias = ProjectSettings.globalize_path(path.get_base_dir() + "/集成 子目录/.././" + path.get_file()).to_upper()
			_expect(FileAccess.get_file_as_bytes(alias) == source and not FileAccess.file_exists(backup), "Schema10 legacy alias is a read-only migration")
			_expect(state.save_build(alias) == OK, "Schema10 legacy uppercase alias upgrades")
			_expect(FileAccess.get_file_as_bytes(backup) == source, "Schema10 keeps exact original v%d backup" % version)
			var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			_expect(disk is Dictionary and disk.version == 10, "Alias upgrade writes schema10")
			var reloaded: Variant = model_script.new()
			_expect(reloaded.load_build(path) and Fixture.equivalent(reloaded._snapshot(), expected), "Schema10 alias roundtrip retains equipment and supports")
			_expect(state.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == source, "Schema10 later save preserves the first raw backup")
	completed = true

func _backup_conflict() -> void:
	for version: int in [8, 9]:
		var path: String = "user://中文 存档/Conflict v%d.json" % version
		var original: PackedByteArray = Fixture.bytes(version, true, true)
		var other: PackedByteArray = Fixture.bytes(version, false, false)
		var backup: String = path + ".v%d-backup.json" % version
		if not _write(path, original) or not _write(backup, other):
			return
		var state: Variant = model_script.new()
		_expect(state.load_build(path), "Schema10 conflict fixture loads")
		var alias: String = ProjectSettings.globalize_path(path).to_upper()
		_expect(state.save_build(alias) == ERR_ALREADY_EXISTS, "Schema10 uppercase alias cannot bypass backup conflict")
		_expect(FileAccess.get_file_as_bytes(path) == original and FileAccess.get_file_as_bytes(backup) == other, "Schema10 conflict preserves both raw files")
	completed = true

func _stale_source() -> void:
	for version: int in [8, 9]:
		var path: String = "user://中文 存档/Stale v%d.json" % version
		var original: PackedByteArray = Fixture.bytes(version, true, true)
		var replacement: PackedByteArray = Fixture.bytes(version, false, false)
		if not _write(path, original):
			return
		var state: Variant = model_script.new()
		_expect(state.load_build(path), "Schema10 stale fixture loads")
		if not _write(path, replacement):
			return
		var alias: String = ProjectSettings.globalize_path(path).to_upper()
		_expect(state.save_build(alias) == ERR_FILE_ALREADY_IN_USE, "Schema10 uppercase alias cannot bypass source replacement")
		_expect(FileAccess.get_file_as_bytes(path) == replacement and not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Schema10 stale source remains unchanged and unbacked-up")
	completed = true
