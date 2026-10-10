extends "res://tests/resistance_targeted_reforge_test.gd"
func _initialize()->void:
	# Current operation-list contract only. Historical whole-closure audit is recorded separately.
	_test_metadata()
	print("RESISTANCE_CURRENT_METADATA checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
