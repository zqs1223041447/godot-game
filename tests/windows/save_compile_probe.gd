extends SceneTree
const Sandbox = preload("res://tests/windows/save_sandbox.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not Sandbox.verify():
		quit(78)
		return
	var model_script: Variant = load("res://scripts/build_state.gd")
	if model_script == null:
		quit(1)
		return
	var state: Variant = model_script.new()
	var ok: bool = model_script.SAVE_VERSION == 9 and state._snapshot().size() == 16
	print("SAVE_QA_RESULT " + JSON.stringify({"case": "compile-model", "checks": 2,
		"failures": 0 if ok else 1, "completed": true}))
	quit(0 if ok else 1)
