extends SceneTree
## Windows case-insensitive file identity must not bypass protected-source keys.
const Sandbox = preload("res://tests/windows/save_sandbox.gd")
const Fixture = preload("res://tests/windows/save_fixture.gd")
var model_script: Variant
var checks: int = 0
var failures: int = 0
var completed: bool = false
var reproductions: Array[Dictionary] = []
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
	_expect(DirAccess.make_dir_recursive_absolute("user://中文 存档/别名 子目录") == OK, "Alias dot components exist inside the sandbox")
	for test: Callable in [_future_case_alias, _legacy_case_alias, _future_alias_matrix,
		_legacy_alias_matrix, _alias_backup_conflicts, _alias_stale_sources,
		_alias_restoration, _missing_source_guard, _independent_copy]:
		completed = false
		test.call()
		_expect(completed, "Alias case completes without exceptions: " + test.get_method())
		cases.append(test.get_method())
	print("SAVE_QA_RESULT " + JSON.stringify({"case": "save-path-aliases", "checks": checks,
		"failures": failures, "completed": completed and reproductions.size() == 2 and cases.size() == 9,
		"reproductions": reproductions, "cases": cases, "legacy_alias_combinations": 48}))
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


func _aliases(path: String) -> Array[Dictionary]:
	var absolute: String = ProjectSettings.globalize_path(path)
	var user_dot: String = path.get_base_dir() + "/别名 子目录/.././" + path.get_file()
	var absolute_dot: String = ProjectSettings.globalize_path(user_dot)
	return [
		{"name": "user-to-absolute", "load": path, "save": absolute},
		{"name": "absolute-to-user", "load": absolute, "save": path},
		{"name": "user-dot", "load": path, "save": user_dot},
		{"name": "absolute-dot-to-user", "load": absolute_dot, "save": path},
		{"name": "backslash", "load": path, "save": absolute.replace("/", "\\")},
		{"name": "uppercase-dot", "load": absolute_dot.to_upper(), "save": absolute.to_upper()}
	]


func _future_alias_matrix() -> void:
	for index: int in range(6):
		var path: String = "user://中文 存档/Future 别名 %d.json" % index
		var alias: Dictionary = _aliases(path)[index]
		var original: PackedByteArray = Fixture.bytes(10, true, true)
		if not _write(path, original):
			return
		var state: Variant = model_script.new()
		var before: Dictionary = state._snapshot()
		_expect(not state.load_build(alias.load), "Future alias load rejects: " + alias.name)
		_expect(FileAccess.get_file_as_bytes(alias.save) == original, "Future alias resolves to original bytes: " + alias.name)
		_expect(not state.save_block_reason(alias.save).is_empty(), "Future guard follows alias: " + alias.name)
		_expect(state.save_build(alias.save) == ERR_INVALID_DATA, "Future alias overwrite rejects: " + alias.name)
		_expect(FileAccess.get_file_as_bytes(path) == original and state._snapshot() == before, "Future alias preserves source and live model: " + alias.name)
		_expect(not FileAccess.file_exists(alias.save + ".tmp"), "Rejected alias never creates a temporary save: " + alias.name)
	completed = true


func _legacy_alias_matrix() -> void:
	for version: int in range(1, 9):
		for index: int in range(6):
			var path: String = "user://中文 存档/Legacy v%d 别名 %d.json" % [version, index]
			var alias: Dictionary = _aliases(path)[index]
			var original: PackedByteArray = Fixture.bytes(version, true, true)
			var backup: String = path + ".v%d-backup.json" % version
			if not _write(path, original):
				return
			var state: Variant = model_script.new()
			_expect(state.load_build(alias.load), "Historical alias loads v%d %s" % [version, alias.name])
			var expected: Dictionary = state._snapshot()
			_expect(not FileAccess.file_exists(backup), "Read-only alias migration does not write backup")
			_expect(FileAccess.get_file_as_bytes(alias.save) == original, "Legacy save alias resolves to source")
			_expect(state.save_build(alias.save) == OK, "Legacy alias save upgrades v%d %s" % [version, alias.name])
			_expect(FileAccess.get_file_as_bytes(backup) == original, "Every legacy alias keeps the exact BOM/CRLF source backup")
			_expect(state.migration_backup_path == alias.load + ".v%d-backup.json" % version, "Backup diagnostic identifies the originally loaded source")
			var reloaded: Variant = model_script.new()
			_expect(reloaded.load_build(path) and Fixture.equivalent(reloaded._snapshot(), expected), "Alias upgrade roundtrip preserves migrated state")
			_expect(state.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == original, "Later canonical save keeps the first backup")
	completed = true


func _alias_backup_conflicts() -> void:
	for index: int in range(6):
		var path: String = "user://中文 存档/Conflict 别名 %d.json" % index
		var alias: Dictionary = _aliases(path)[index]
		var backup: String = path + ".v8-backup.json"
		var original: PackedByteArray = Fixture.bytes(8, true, true)
		var other: PackedByteArray = Fixture.bytes(8, false, false)
		if not _write(path, original) or not _write(backup, other):
			return
		var state: Variant = model_script.new()
		_expect(state.load_build(alias.load), "Conflicting-backup alias fixture loads")
		var before: Dictionary = state._snapshot()
		_expect(state.save_build(alias.save) == ERR_ALREADY_EXISTS, "Alias cannot bypass a different-byte backup")
		_expect(FileAccess.get_file_as_bytes(path) == original and FileAccess.get_file_as_bytes(backup) == other, "Alias conflict preserves source and independent backup")
		_expect(state._snapshot() == before and not FileAccess.file_exists(alias.save + ".tmp"), "Alias conflict leaves model and target staging unchanged")
		if not _write(backup, original):
			return
		_expect(state.save_build(alias.save) == OK and FileAccess.get_file_as_bytes(backup) == original, "Matching-byte backup permits alias retry")
	completed = true


func _alias_stale_sources() -> void:
	for index: int in range(6):
		var path: String = "user://中文 存档/Stale 别名 %d.json" % index
		var alias: Dictionary = _aliases(path)[index]
		var original: PackedByteArray = Fixture.bytes(8, true, true)
		var replacement: PackedByteArray = Fixture.bytes(8, false, false)
		if not _write(path, original):
			return
		var state: Variant = model_script.new()
		_expect(state.load_build(alias.load), "Stale-source alias fixture loads")
		if not _write(path, replacement):
			return
		_expect(state.save_build(alias.save) == ERR_FILE_ALREADY_IN_USE, "Alias cannot bypass externally changed source bytes")
		_expect(FileAccess.get_file_as_bytes(path) == replacement and not FileAccess.file_exists(path + ".v8-backup.json"), "Alias neither overwrites nor mislabels stale source")
		if not _write(path, original):
			return
		_expect(state.save_build(alias.save) == OK and FileAccess.get_file_as_bytes(path + ".v8-backup.json") == original, "Restored original bytes permit safe alias retry")
	completed = true


func _alias_restoration() -> void:
	var path: String = "user://中文 存档/Restore 别名.json"
	var other_path: String = "user://中文 存档/Restore 独立保护.json"
	if not _write(path, Fixture.bytes(10)) or not _write(other_path, Fixture.bytes(10)):
		return
	var state: Variant = model_script.new()
	for alias: Dictionary in _aliases(path):
		_expect(not state.load_build(alias.save), "Every rejected alias arms protection")
	_expect(not state.load_build(other_path), "Independent future source arms its own guard")
	if not _write(path, Fixture.bytes(9, true, true)):
		return
	for alias: Dictionary in _aliases(path):
		_expect(state.save_build(alias.save) == ERR_INVALID_DATA, "Unvalidated replacement cannot unlock an alias")
	_expect(state.load_build(_aliases(path)[2].save), "Valid restoration loads through dotted user alias")
	for alias: Dictionary in _aliases(path):
		_expect(state.save_block_reason(alias.save).is_empty(), "Successful same-file load clears every equivalent guard")
	_expect(state.save_build(path) == OK, "Restored canonical source resumes saving")
	_expect(not state.save_block_reason(other_path).is_empty() and state.save_build(other_path) == ERR_INVALID_DATA, "Restoration leaves unrelated source protected")
	_expect(FileAccess.get_file_as_bytes(other_path) == Fixture.bytes(10), "Unrelated future bytes remain intact")
	completed = true


func _missing_source_guard() -> void:
	var path: String = "user://中文 存档/Missing 别名.json"
	if not _write(path, Fixture.bytes(10)):
		return
	var state: Variant = model_script.new()
	_expect(not state.load_build(path), "Missing-source guard first rejects a real future fixture")
	_expect(DirAccess.remove_absolute(path) == OK, "Simulated external deletion only removes this sandbox fixture")
	for alias: Dictionary in _aliases(path):
		_expect(not state.save_block_reason(alias.save).is_empty(), "Parent-directory identity preserves guard after file deletion")
		_expect(state.save_build(alias.save) == ERR_INVALID_DATA and not FileAccess.file_exists(path), "Missing protected source cannot be silently recreated via alias")
	if not _write(path, Fixture.bytes(9)):
		return
	_expect(state.load_build(ProjectSettings.globalize_path(path).to_upper()) and state.save_build(path) == OK, "Explicit valid restored alias can unlock a missing source guard")
	completed = true


func _independent_copy() -> void:
	var path: String = "user://中文 存档/Protected 原件.json"
	var copy: String = "user://中文 存档/Independent 相同内容.json"
	var original: PackedByteArray = Fixture.bytes(10, true, true)
	if not _write(path, original) or not _write(copy, original):
		return
	var state: Variant = model_script.new()
	_expect(not state.load_build(path), "Independent-copy test protects only its rejected source")
	_expect(state.save_block_reason(copy).is_empty() and state.save_build(copy) == OK, "Byte-identical independent file remains a valid Save As destination")
	_expect(state.load_build(copy) and not state.save_block_reason(path).is_empty(), "Loading independent copy cannot clear original guard")
	_expect(state.save_build(ProjectSettings.globalize_path(path).to_upper()) == ERR_INVALID_DATA and FileAccess.get_file_as_bytes(path) == original, "Independent copy cannot unlock a case alias of the protected original")
	completed = true
