extends SceneTree
## Windows case-insensitive file identity must not bypass protected-source keys.
const Sandbox = preload("res://tests/windows/save_sandbox.gd")
const Fixture = preload("res://tests/windows/save_fixture.gd")
var model_script: Variant
var checks: int = 0
var failures: int = 0
var completed: bool = false
var reproductions: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SAVE_QA_FAIL: " + label)

func _write(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Alias reproduction fixture opens inside sandbox")
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	_expect(ok, "Alias reproduction bytes flush completely")
	return ok

func _run() -> void:
	if not Sandbox.verify():
		quit(78)
		return
	model_script = load("res://scripts/build_state.gd")
	if model_script == null:
		quit(1)
		return
	for test: Callable in [_future_case_alias, _legacy_case_alias]:
		completed = false
		test.call()
		_expect(completed, "Alias case completes without exceptions: " + test.get_method())
	print("SAVE_QA_RESULT " + JSON.stringify({"case": "save-path-aliases", "checks": checks,
		"failures": failures, "completed": completed and reproductions.size() == 2,
		"reproductions": reproductions}))
	quit(0 if failures == 0 else 1)

func _future_case_alias() -> void:
	var path: String = "user://中文 存档/未来 大小写别名.json"
	var original: PackedByteArray = Fixture.bytes(10)
	if not _write(path, original):
		return
	var state: Variant = model_script.new()
	_expect(not state.load_build(path) and not state.save_block_reason(path).is_empty(), "Future canonical source is rejected and guarded")
	var alias: String = ProjectSettings.globalize_path(path).to_upper()
	_expect(FileAccess.get_file_as_bytes(alias) == original, "Uppercase alias refers to the exact same Windows file")
	var result: Error = state.save_build(alias)
	_expect(result == ERR_INVALID_DATA, "Windows case alias cannot bypass future-version save guard")
	_expect(FileAccess.get_file_as_bytes(path) == original, "Future source bytes survive saving through a case alias")
	reproductions.append({"kind": "future-version-case-alias", "canonical": path, "absolute_alias": alias,
		"save_error": result, "alias_guard": state.save_block_reason(alias),
		"source_preserved": FileAccess.get_file_as_bytes(path) == original})
	completed = true

func _legacy_case_alias() -> void:
	var path: String = "user://中文 存档/历史 大小写别名.json"
	var original: PackedByteArray = Fixture.bytes(8)
	if not _write(path, original):
		return
	var state: Variant = model_script.new()
	_expect(state.load_build(path) and state.migrated_from_v8, "Historical v8 alias fixture migrates read-only")
	var alias: String = ProjectSettings.globalize_path(path).to_upper()
	_expect(FileAccess.get_file_as_bytes(alias) == original, "Legacy uppercase alias refers to the same source")
	var result: Error = state.save_build(alias)
	var backup: String = path + ".v8-backup.json"
	_expect(result == OK, "Case alias may upgrade a valid legacy source")
	_expect(FileAccess.file_exists(backup) and FileAccess.get_file_as_bytes(backup) == original, "Windows case alias cannot skip the required byte-exact legacy backup")
	reproductions.append({"kind": "legacy-backup-case-alias", "canonical": path, "absolute_alias": alias,
		"save_error": result, "backup_exists": FileAccess.file_exists(backup)})
	completed = true
