extends SceneTree
const Sandbox = preload("res://tests/windows/save_sandbox.gd")
const Fixture = preload("res://tests/windows/save_fixture.gd")
var model_script: Variant
var checks: int = 0
var failures: int = 0
var changes: int = 0
var completed: bool = false
var save_error: int = -1

func _initialize() -> void:
	call_deferred("_run")


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SAVE_QA_FAIL: " + label)


func _changed() -> void:
	changes += 1


func _run() -> void:
	if not Sandbox.verify():
		quit(78)
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0] in ["destination-lock", "temporary-lock", "rename-directory", "retry-destination-lock", "retry-temporary-lock", "retry-rename-directory"]:
		printerr("SAVE_QA_BLOCKED: Unknown fault case")
		quit(78)
		return
	model_script = load("res://scripts/build_state.gd")
	if model_script == null:
		quit(1)
		return
	var case_name: String = args[0]
	var retry: bool = case_name.begins_with("retry-")
	var base_case: String = case_name.trim_prefix("retry-")
	var path: String = "user://中文 存档/" + base_case + " 锁定.json"
	var original: PackedByteArray = Fixture.bytes(9)
	var state: Variant = model_script.new()
	if base_case == "rename-directory":
		# Destination is a directory with a sentinel, not an unreadable model file.
		_expect(state.load_build(Fixture.DIRECTORY + "save_v9.json"), "Independent current fixture loads")
	else:
		_expect(state.load_build(path), "Read sharing permits loading a locked destination")
		_expect(FileAccess.get_file_as_bytes(path) == original, "Original target bytes are exact before attempted save")
	state.add_xp(1)
	var pending: Dictionary = state._snapshot()
	state.changed.connect(_changed)
	changes = 0
	save_error = state.save_build(path)
	_expect(state._snapshot() == pending and changes == 0, "Save attempt preserves pending model and emits no change signal")
	if retry:
		_expect(save_error == OK, "Released fault permits successful retry")
		var restored: Variant = model_script.new()
		_expect(restored.load_build(path) and restored._snapshot() == pending, "Retry persists the exact pending build")
		_expect(not FileAccess.file_exists(path + ".tmp"), "Retry leaves no temporary file")
	else:
		_expect(save_error != OK, "Real Windows fault must reject save")
		if base_case == "rename-directory":
			_expect(DirAccess.dir_exists_absolute(path), "Rename failure retains destination directory")
			_expect(FileAccess.get_file_as_string(path + "/sentinel.txt") == "existing directory must survive\r\n", "Rename failure retains directory sentinel")
		else:
			_expect(FileAccess.get_file_as_bytes(path) == original, "Failure leaves destination byte-for-byte unchanged")
		if base_case == "temporary-lock":
			# Parent holds FileShare.None and verifies the inaccessible sentinel after release.
			_expect(save_error != OK, "Exclusive temporary-file lock must reject opening the writer")
		else:
			_expect(not FileAccess.file_exists(path + ".tmp"), "Failed rename removes only its own temporary write")
	completed = true
	print("SAVE_QA_RESULT " + JSON.stringify({"case": case_name, "checks": checks,
		"failures": failures, "completed": completed, "save_error": save_error}))
	quit(0 if failures == 0 else 1)
