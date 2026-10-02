extends SceneTree
## Focused Linux compatibility check; this is not a Windows runner entrypoint.
const Fixture = preload("res://tests/windows/save_fixture.gd")
var model_script: Variant
var checks: int = 0
var failures: int = 0
var completed: bool = false
var cases: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _normalized(path: String) -> String:
	return path.simplify_path().trim_suffix("/")

func _gate() -> bool:
	var root: String = _normalized(OS.get_environment("GODOT_SAVE_QA_ROOT"))
	var token: String = OS.get_environment("GODOT_SAVE_QA_TOKEN")
	var project: String = _normalized(ProjectSettings.globalize_path("res://"))
	var userdata: String = _normalized(OS.get_user_data_dir())
	var ok: bool = OS.get_name() == "Linux" and root.is_absolute_path() and token.length() == 32
	ok = ok and project.begins_with(root + "/") and userdata.begins_with(root + "/")
	ok = ok and project == _normalized(OS.get_environment("GODOT_SAVE_QA_PROJECT"))
	ok = ok and userdata == _normalized(OS.get_environment("GODOT_SAVE_QA_USERDATA"))
	ok = ok and _normalized(ProjectSettings.globalize_path("user://")) == userdata
	ok = ok and ProjectSettings.get_setting("application/config/name", "") == "Linux Save QA " + token
	ok = ok and ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	ok = ok and ProjectSettings.get_setting("application/config/custom_user_dir_name", "") == "存档 沙箱 " + token
	print("SAVE_QA_GATE " + JSON.stringify({"ok": ok, "os": OS.get_name(), "sandbox": root,
		"token": token, "project": project, "user_data_dir": userdata}))
	return ok

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SAVE_QA_FAIL: " + label)

func _write(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Linux fixture opens inside sandbox")
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	_expect(ok, "Linux fixture bytes flush")
	return ok

func _version_bytes(version: int) -> PackedByteArray:
	var record: Dictionary = Fixture.record(9)
	record.version = version
	if version >= 11:
		record.crafting = {"materials":{"calibration_shard":0},"revision":0}
	return JSON.stringify(record, "\t").to_utf8_buffer()

func _run() -> void:
	if not _gate():
		quit(78)
		return
	if OS.get_cmdline_user_args() == PackedStringArray(["probe"]):
		quit(0)
		return
	if OS.get_environment("GODOT_SAVE_QA_PROBE_VERIFIED") != OS.get_environment("GODOT_SAVE_QA_TOKEN"):
		printerr("SAVE_QA_BLOCKED: Complete the independent userdata probe first.")
		quit(78)
		return
	model_script = load("res://scripts/build_state.gd")
	if model_script == null:
		quit(1)
		return
	_expect(DirAccess.make_dir_recursive_absolute("user://中文 存档/子目录") == OK, "Linux Chinese/spaced dot directory")
	for test: Callable in [_case_sensitive_guard, _dotted_legacy_migrations, _legacy_independent_case_copy]:
		completed = false
		test.call()
		_expect(completed, "Linux identity case completes: " + test.get_method())
		cases.append(test.get_method())
	print("SAVE_QA_RESULT " + JSON.stringify({"case": "linux-save-identity", "checks": checks,
		"failures": failures, "completed": completed and cases.size() == 3, "cases": cases}))
	quit(0 if failures == 0 else 1)

func _case_sensitive_guard() -> void:
	var upper: String = "user://中文 存档/Case.json"
	var lower: String = "user://中文 存档/case.json"
	var original: PackedByteArray = _version_bytes(model_script.SAVE_VERSION + 1)
	if not _write(upper, original) or not _write(lower, _version_bytes(model_script.SAVE_VERSION)):
		return
	var filesystem: DirAccess = DirAccess.open(ProjectSettings.globalize_path("user://中文 存档"))
	_expect(filesystem != null and filesystem.is_case_sensitive("."), "This Linux regression requires a case-sensitive native test filesystem")
	var state: Variant = model_script.new()
	_expect(not state.load_build(upper), "Linux future Case.json rejects")
	_expect(state.save_block_reason(lower).is_empty() and state.save_build(lower) == OK, "Independent case.json remains a permitted Save As destination")
	_expect(state.load_build(lower) and not state.save_block_reason(upper).is_empty(), "Lowercase valid file does not unlock uppercase future source")
	var dot: String = ProjectSettings.globalize_path("user://中文 存档/子目录/.././Case.json")
	_expect(state.save_build(dot) == ERR_INVALID_DATA and FileAccess.get_file_as_bytes(upper) == original, "Linux dot and absolute aliases cannot bypass a future guard")
	_expect(DirAccess.remove_absolute(upper) == OK, "Linux external deletion removes only this artificial source")
	_expect(state.save_build(dot) == ERR_INVALID_DATA and not FileAccess.file_exists(upper), "Missing future path remains protected through dot alias")
	_expect(state.save_build(lower) == OK, "Missing uppercase source never casefolds an independent lowercase path")
	if not _write(upper, _version_bytes(model_script.SAVE_VERSION)):
		return
	_expect(state.load_build(dot) and state.save_block_reason(upper).is_empty() and state.save_build(upper) == OK, "Validated same-file restoration unlocks Linux aliases")
	completed = true

func _dotted_legacy_migrations() -> void:
	for version: int in range(1, model_script.SAVE_VERSION):
		var path: String = "user://中文 存档/Legacy v%d.json" % version
		var original: PackedByteArray = Fixture.bytes(version, true, true)
		if not _write(path, original):
			return
		var state: Variant = model_script.new()
		_expect(state.load_build(path), "Linux historical source loads v%d" % version)
		var alias: String = ProjectSettings.globalize_path(path.get_base_dir() + "/子目录/.././" + path.get_file())
		_expect(state.save_build(alias) == OK, "Linux dotted legacy save upgrades")
		_expect(FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % version) == original, "Linux dotted alias retains byte-exact historical backup")
		var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_expect(disk is Dictionary and disk.version == model_script.SAVE_VERSION, "Linux alias writes the current schema")
	completed = true

func _legacy_independent_case_copy() -> void:
	var upper: String = "user://中文 存档/History.json"
	var lower: String = "user://中文 存档/history.json"
	var original: PackedByteArray = Fixture.bytes(8, true, true)
	if not _write(upper, original) or not _write(lower, original):
		return
	var state: Variant = model_script.new()
	_expect(state.load_build(upper) and state.save_build(lower) == OK, "Linux byte-identical lowercase destination is independent Save As")
	_expect(FileAccess.get_file_as_bytes(upper) == original and not FileAccess.file_exists(upper + ".v8-backup.json"), "Independent copy neither consumes nor backs up original migration")
	_expect(state.save_build(ProjectSettings.globalize_path(upper)) == OK, "Original Linux source can still complete pending migration")
	_expect(FileAccess.get_file_as_bytes(upper + ".v8-backup.json") == original, "Original Linux source keeps its own exact backup")
	completed = true
