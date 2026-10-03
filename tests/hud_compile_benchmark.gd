extends SceneTree
## Descriptive CPU probe, never a Windows FPS or rendering claim.
var arena: Node2D
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m0-perf-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	var fresh := preload("res://scripts/build_state.gd").new()
	assert(fresh.save_build() == OK)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	await process_frame
	var rows: Array = []
	for mode: String in ["default", "two_supports"]:
		if mode == "two_supports":
			arena.equip_tornado_example()
			arena.state.skill_slots.assign(["tornado", "frost", "chain", "nova", "ward"])
			arena.state.skill_supports = {"tornado": ["volley", "focus"], "frost": ["heavy_projectiles", "lingering_chill"],
				"chain": ["chain_extension", "chain_reach"], "nova": ["breadth", "concentrate"], "ward": ["efficiency", "quickcast"]}
			arena.state.changed.emit()
		arena.hud.close_panel()
		var before: Dictionary = arena.state._snapshot()
		var rng_before: int = arena.rng.state
		for unused: int in range(10): arena.hud._update_live()
		var samples: Array[int] = []
		for unused: int in range(240):
			var started: int = Time.get_ticks_usec()
			arena.hud._update_live()
			samples.append(Time.get_ticks_usec() - started)
		assert(arena.state._snapshot() == before and arena.rng.state == rng_before)
		samples.sort()
		var total: int = 0
		for value: int in samples: total += value
		var row: Dictionary = {"scenario": mode, "samples": samples.size(), "mean_ms": total / (samples.size() * 1000.0),
			"p50_ms": samples[119] / 1000.0, "p95_ms": samples[227] / 1000.0, "p99_ms": samples[237] / 1000.0,
			"max_ms": samples.back() / 1000.0, "hud_hz": 20, "skill_rows": 5, "build_unchanged": true, "rng_unchanged": true}
		if arena.state.has_method("cache_diagnostics"):
			row["cache"] = arena.state.cache_diagnostics()
		rows.append(row)
	var report: Dictionary = {"engine": Engine.get_version_info().string, "platform": OS.get_name(), "processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(), "display": DisplayServer.get_name(), "rendering_measured": false,
		"windows_target_measured": false, "five_supports_measured": false, "rows": rows}
	print("HUD_CPU_PROBE=" + JSON.stringify(report))
	var output: String = OS.get_environment("M0_PERF_OUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	arena.queue_free()
	await process_frame
	quit(0)
