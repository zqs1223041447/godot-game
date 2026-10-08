extends "res://tests/ruins_hud_retry_test.gd"
## Supplement only: normal Main/HUD processing, two successes and one failed retry.
## Reuses fault/observation helpers, but never invokes the 216-check suite.
class FrameMain extends "res://scripts/main.gd":
	var process_calls := 0
	var native_calls := 0
	var last_native_result: Dictionary = {}
	func _process(delta: float) -> void:
		process_calls += 1
		super._process(delta)
	func retry_native_map(expected_revision: Variant) -> Dictionary:
		native_calls += 1
		last_native_result = await super.retry_native_map(expected_revision)
		return last_native_result

var frame_records: Array[Dictionary] = []
var input_method := "Control.pressed signal (no mouse-hit claim)"
var screenshot := ""

func pause() -> void:
	# Keep frame processing enabled. Only ordinary menus pause gameplay.
	arena.auto_fire = false
	for unused: int in range(4): arena.hud.close_panel()

func load_arena(bytes: PackedByteArray) -> bool:
	await dispose()
	var output := FileAccess.open(SAVE, FileAccess.WRITE)
	if not check(output != null, "Open only isolated frame-smoke save"): return false
	output.store_buffer(bytes); output.close()
	arena = load("res://scenes/main.tscn").instantiate(); arena.set_script(FrameMain)
	model = FaultModel.new(); arena.state = model
	root.add_child(arena); pause(); await process_frame
	arena.rng.seed = 116551
	return check(arena.is_processing() and arena.hud.is_processing() and arena.world_context().normal_town, "Main and HUD normal processing enabled")

func show_frames() -> void:
	var calls: int = arena.process_calls
	var hud_clocks: Array[float] = []
	# The refresh clock resets at 50 ms and can read zero every software-render
	# frame. Observe the actual HUD countdown instead of that periodic clock.
	# process_frame precedes node processing, so the initial sample may be 100.
	arena.hud._toast_left = 100.0
	for unused: int in range(5):
		await process_frame
		hud_clocks.append(float(arena.hud._toast_left))
	check(arena.is_processing() and arena.hud.is_processing() and arena.process_calls > calls,
		"Normal Main process runs before/after request")
	check(hud_clocks[0] <= 100.0 and hud_clocks[-1] < hud_clocks[0], "Normal HUD process advances countdown across real frames")
	frame_records.append({"case": group, "main_calls_before": calls, "main_calls_after": arena.process_calls,
		"main_enabled": arena.is_processing(), "hud_enabled": arena.hud.is_processing(), "hud_countdown_samples": hud_clocks})

func press_actual(overlay: String, take_image: bool = false) -> void:
	var button := retry_button(overlay)
	check(button != null and button.is_visible_in_tree(), "Actual visible " + overlay + " retry control")
	await process_frame; await process_frame
	arena.hud._panel_scroll.ensure_control_visible(button)
	await process_frame; await process_frame
	if take_image and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		screenshot = "docs/qa/ruins-hud-retry/normal-frames.png"
		check(root.get_texture().get_image().save_png("res://" + screenshot) == OK, "Capture one actual native death-menu screenshot")
	var expected: int = arena.native_calls + 1
	var request_path := OS.get_environment("RUINS_HUD_CLICK_REQUEST")
	if request_path.is_empty(): button.pressed.emit()
	else:
		input_method = "Native X11 XTest pointer motion/button press+release at actual control coordinates"
		var center: Vector2 = button.get_global_rect().get_center()
		var window: Vector2i = DisplayServer.window_get_position()
		check(Rect2(Vector2.ZERO, Vector2(root.size)).has_point(center), "Scrolled retry center is inside visible viewport")
		var output := FileAccess.open(request_path, FileAccess.WRITE)
		output.store_string(JSON.stringify({"sequence": expected, "x": roundi(center.x) + window.x, "y": roundi(center.y) + window.y, "case": group}))
		output.close()
		for unused: int in range(120):
			if arena.native_calls >= expected: break
			await process_frame
	check(arena.native_calls == expected, "Actual input dispatches exactly one native retry")
	await settle()

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-ruins-hud-frames."): quit(78); return
	group = "frame setup"
	original_fixture_sha = FileAccess.get_sha256(FIXTURE)
	if await load_arena(FileAccess.get_file_as_bytes(FIXTURE)):
		accepted(arena.craft_normal_map("ruins_garden", 1, [], [], arena.map_draft().revision), "Select existing free native map")
		accepted(await arena.open_map(arena.map_draft().revision), "Enter native map through existing preparation")
		check(model.crafting_balance() == 4, "Original earned currency preserved; free tier-I smoke")
		for overlay: String in ["pause", "death"]:
			group = "normal frames / " + overlay + " success"
			open_overlay(overlay); await show_frames()
			var run_id: int = arena._normal_run_id
			var saves: int = model.successful_saves
			await press_actual(overlay, overlay == "death")
			check(arena.last_native_result.ok and arena._normal_run_id == run_id + 1 and model.successful_saves == saves + 1,
				"Real-frame success creates and saves exactly one retry run")
			check(arena.alive and not arena.hud.is_blocking() and not arena.hud._menu_routes.snapshot().death_latched,
				"Real-frame success closes menu and clears death latch")
			await show_frames()
		group = "normal frames / failure then retry"
		open_overlay("pause"); await show_frames()
		var before := snapshot()
		model.fail_writes = true
		await press_actual("pause")
		check(not arena.last_native_result.ok and snapshot() == before, "Failed save preserves original map/state/disk/RNG with processing enabled")
		check(arena.hud.is_blocking() and arena.hud._menu_routes.snapshot().overlay == "pause", "Failure retains real pause menu")
		var reason: String = arena.last_native_result.reason
		check(not reason.is_empty() and (arena.hud._panel_footer.text == reason or arena.hud._panel_footer.tooltip_text.contains(reason)), "Real save failure reason remains visible")
		await show_frames()
		model.fail_writes = false
		await press_actual("pause")
		check(arena.last_native_result.ok and arena._normal_run_id == before.state.journey.active_run.run_id + 1 and model.successful_saves == before.saves + 1,
			"Healthy same-button retry commits once after failure")
		check(arena.alive and not arena.hud.is_blocking() and model.crafting_balance() == 4, "Recovery resumes native map with original currency")
		await show_frames()
	check(FileAccess.get_sha256(FIXTURE) == original_fixture_sha, "Original earned fixture unchanged")
	var hashes: Dictionary = {}
	for path: String in ["scripts/game_hud.gd", "scripts/main.gd", "tests/ruins_hud_retry_test.gd", "tests/ruins_hud_retry_frames_smoke.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	var report := {"checks": checks, "failures": failures.size(), "failed_labels": failures, "evidence": evidence,
		"frame_records": frame_records, "input_method": input_method, "display": DisplayServer.get_name(), "screenshot": screenshot,
		"source_sha256": hashes, "earned_fixture_sha256": original_fixture_sha, "method": "Short normal-frame supplement only; no 216-check rerun; Main temporarily held only by existing native transaction"}
	var target := OS.get_environment("RUINS_HUD_FRAMES_REPORT")
	if not target.is_empty():
		var output := FileAccess.open(target, FileAccess.WRITE); output.store_string(JSON.stringify(report, "\t") + "\n"); output.close()
	await dispose()
	print("RUINS_HUD_NORMAL_FRAMES checks=%d failures=%d input=%s" % [checks, failures.size(), input_method])
	quit(0 if failures.is_empty() else 1)
