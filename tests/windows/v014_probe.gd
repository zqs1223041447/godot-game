extends SceneTree
## Run in the tiny project before any production file is copied or imported.
const Sandbox = preload("res://tests/windows/v014_sandbox.gd")

func _initialize() -> void:
	quit(0 if Sandbox.verify() else 78)
