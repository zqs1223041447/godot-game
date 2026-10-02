extends SceneTree
## Run before importing/loading production resources. No fixture or user:// I/O.
const Sandbox = preload("res://tests/windows/save_sandbox.gd")

func _initialize() -> void:
	quit(0 if Sandbox.verify() else 78)
