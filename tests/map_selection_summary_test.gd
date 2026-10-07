extends SceneTree
## Small real-panel regression: selection wording, model refresh and launch only.
const Maps = preload("res://scripts/world/map_compiler.gd")
const DIRTY := "配置已更改 · 请准备地图"
const SAVE := "user://build_save.json"
var arena: Node2D
var panel: Control
var checks := 0
var failures: Array[String] = []
var summaries: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("MAP_SUMMARY_FAIL: " + label)
	return ok
func accepted(result: Dictionary, label: String) -> bool:
	return check(result.get("ok", false), label + ": " + str(result.get("reason", "")))
func settle() -> void:
	await process_frame
	await process_frame
func select_value(option: OptionButton, value: Variant) -> bool:
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == value and not option.is_item_disabled(index):
			option.select(index)
			option.item_selected.emit(index)
			return true
	return false
func observe_dirty(label: String, revision: int) -> void:
	check(panel._map_selection_dirty and panel._map_summary.text == DIRTY, label + " shows only the explicit unprepared message")
	check(panel._map_launch.disabled and arena.map_draft().revision == revision, label + " keeps launch disabled without changing the authoritative draft")
	summaries.append({"case": label, "text": panel._map_summary.text, "launch_disabled": panel._map_launch.disabled})
func reopen() -> void:
	panel.hide()
	panel.open_service("map_device")
	await settle()
func prepare_button() -> Button:
	for child: Node in panel._content.get_children():
		if child is Button and child.text == "准备地图": return child
	return null
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v117-") or FileAccess.file_exists(SAVE):
		printerr("MAP_SUMMARY_BLOCKED: use fresh isolated /tmp/godot-m1-v117-* storage")
		quit(78); return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	await settle()
	for unused in range(4): arena.hud.close_panel()
	if not check(arena.save_build(), "Fresh current-schema fixture saves normally"): finish(); return
	# Existing canonical transactions create one pending receipt and unlocked
	# old-map tierII strictly as a UI fixture. No earned-combat claim is made.
	var model: RefCounted = arena.state
	var started: Dictionary = model.normal_start_map(Maps.compile_normal("old_garden", 1, [], []).profile, model.revision(), SAVE)
	if not accepted(started, "Controlled pending-reward UI fixture starts"): finish(); return
	if not accepted(model.normal_complete_map(started.run_id, model.revision(), SAVE), "Controlled pending receipt unlocks the old-map tier selector"): finish(); return
	panel = arena.hud._town_view
	panel.open_service("map_device")
	await settle()
	var original: Dictionary = arena.map_draft()
	check(not panel._map_selection_dirty and panel._map_summary.text.contains("旧庭试炼"), "Initial clean summary shows the actual old-garden draft")
	if not check(select_value(panel._map_select, "ruins_garden"), "Select native map through actual OptionButton signal"): finish(); return
	await settle()
	observe_dirty("map selection", original.revision)
	check(not panel._map_summary.text.contains("旧庭") and not panel._map_summary.text.contains("入场"), "Unprepared map selection does not display the previous name or fee")
	if not accepted(arena.claim_normal_rewards(arena.world_context().revision), "Actual public claim changes the model's shard balance"): finish(); return
	await settle()
	check(model.crafting_balance() == 4, "Real canonical balance changes from zero to four")
	observe_dirty("currency refresh", original.revision)
	check(panel._map_select.get_selected_metadata() == "ruins_garden", "Model refresh preserves the user's unprepared selection")
	await reopen()
	check(not panel._map_selection_dirty and panel._map_select.get_selected_metadata() == "old_garden"
		and panel._map_summary.text.contains("旧庭试炼") and panel._map_summary.text.contains("入场 0"), "Close/reopen restores the current authoritative draft and cost")
	if not check(select_value(panel._tier_select, 2), "Select actually unlocked tierII"): finish(); return
	await settle()
	observe_dirty("tier selection", original.revision)
	await reopen()
	panel._normal.enemy_damage_115.button_pressed = true
	await settle()
	observe_dirty("normal modifier", original.revision)
	await reopen()
	panel._special.elemental_aegis.button_pressed = true
	await settle()
	observe_dirty("special modifier", original.revision)
	await reopen()
	check(select_value(panel._map_select, "ruins_garden"), "Select native map again for actual preparation")
	await settle()
	var prepare := prepare_button()
	if not check(prepare != null, "Actual prepare button exists"): finish(); return
	prepare.pressed.emit()
	await settle()
	var prepared: Dictionary = arena.map_draft()
	check(prepared.map_id == "ruins_garden" and prepared.revision == original.revision + 1, "Actual prepare commits exactly the selected new draft")
	check(not panel._map_selection_dirty and panel._map_summary.text == prepared.summary + "\n入场 0 校准碎片 · 完成奖励 4"
		and not panel._map_launch.disabled, "Preparation restores the new authoritative name, fee, reward and enabled launch")
	summaries.append({"case": "prepared", "text": panel._map_summary.text, "launch_disabled": panel._map_launch.disabled})
	await reopen()
	check(not panel._map_selection_dirty and panel._map_select.get_selected_metadata() == "ruins_garden"
		and panel._map_summary.text.contains("遗迹庭园"), "Reopening preserves the newly prepared draft rather than the original old map")
	panel._map_launch.pressed.emit()
	for unused: int in range(12):
		if not arena.map_preparation_pending(): break
		await physics_frame
	check(not arena.map_preparation_pending() and arena.world_context().map_id == "ruins_garden"
		and arena.world_context().mode == "map" and arena.enemies.size() == 25, "Actual launch reaches the selected native map with its25-root roster")
	check(not panel.visible and model.crafting_balance() == 4, "Successful free launch closes the panel and preserves the existing balance")
	finish()
func finish() -> void:
	var result := {"checks": checks, "failures": failures.size(), "failed_labels": failures, "summaries": summaries,
		"method": "Fresh current-schema real Main/panel, actual selection/button signals and one controlled pending-reward claim; no migration suite, combat, screenshots or rendering"}
	var output := FileAccess.open("res://docs/qa/v117-map-selection-summary/result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n"); output.close()
	print("MAP_SUMMARY_RESULT " + JSON.stringify(result))
	if is_instance_valid(arena): arena.queue_free()
	quit(1 if not failures.is_empty() else 0)
