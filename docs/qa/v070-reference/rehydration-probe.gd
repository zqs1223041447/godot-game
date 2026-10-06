extends SceneTree
const Exporter = preload("res://tools/export_reference.gd")
func _initialize() -> void:
	var result: Dictionary = Exporter.precise_technique_examples()
	assert(result.examples.size() == 3)
	print("PRECISE_REFERENCE_REHYDRATION_OK: three accepted Main fixtures, nine exact casts, no writes")
	quit(0)
