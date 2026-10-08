extends "res://tests/monster_system_test.gd"
## Reuse existing bounded death/lineage assertions; skip unrelated roll coverage.
func _run() -> void:
	_case(_test_splitter, "existing splitter and once-only death")
	_case(_test_brood, "existing multistage brood")
	_case(_test_budgets, "existing per-death/generation/lineage budgets")
	_case(_test_real_graph_budgets, "existing graph reaches finite boundaries")
	_case(_test_queue, "existing FIFO/capacity/deferred admission")
	_case(_test_collection, "existing cancellation/reset/identity cleanup")
	print("MAP_COMPLETION_SPLIT_BOUNDARIES checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
