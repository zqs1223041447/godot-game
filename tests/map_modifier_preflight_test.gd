extends SceneTree
## Fresh canonical fixtures, actual panel signals and bounded launch/cancel checks.
const Maps = preload("res://scripts/world/map_compiler.gd")
class ObservedArena extends "res://scripts/main.gd":
	var normal_prepares := 0
	var test_prepares := 0
	func craft_normal_map(map_id: Variant, tier: Variant, normals: Variant, specials: Variant, revision: Variant) -> Dictionary:
		normal_prepares += 1
		return super.craft_normal_map(map_id, tier, normals, specials, revision)
	func craft_map(map_id: Variant, normals: Variant, specials: Variant, revision: Variant) -> Dictionary:
		test_prepares += 1
		return super.craft_map(map_id, normals, specials, revision)
var arena: ObservedArena
var panel: Control
var checks := 0
var failures: Array[String] = []
var states: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); push_error(label)
	return ok
func accepted(result: Dictionary, label: String) -> bool:
	return check(bool(result.ok), label + ": " + str(result.get("reason", "")))
func settle() -> void:
	await process_frame
	await process_frame
func observe() -> PackedByteArray:
	return var_to_bytes([arena.state.snapshot(), arena.map_draft(), arena.world_context(), arena.rng.state,
		arena.state.successful_saves, arena.state.save_attempts, arena.progress_save_success_count, arena.progress_save_attempt_count,
		FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH), FileAccess.get_file_as_bytes(arena.TOWN_TEST_BUILD_PATH),
		arena._map_run.snapshot(), arena.run_revision])
func select_option(option: OptionButton, value: Variant) -> bool:
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == value and not option.is_item_disabled(index):
			option.select(index); option.item_selected.emit(index); return true
	return check(false, "Missing selectable option " + str(value))
func capture(label: String) -> void:
	states.append({"case": label, "gate_text": panel._map_gate_status.text, "prepare_disabled": panel._map_prepare.disabled,
		"launch_disabled": panel._map_launch.disabled, "invalid_selected": panel._map_ineligible_selected.duplicate(),
		"draft": arena.map_draft(), "balance": arena.state.crafting_balance()})
func check_preview(testing: bool) -> void:
	var before := observe()
	for map_id: String in Maps.Catalog.MAPS:
		for tier: int in range(1, 4):
			var preview: Dictionary = arena.map_modifier_availability(map_id, tier)
			var expected: Dictionary = Maps.compile(map_id, [], []) if testing else Maps.compile_normal(map_id, tier, [], [])
			check(preview.ok and preview.wave == expected.profile.wave, "Preview uses authority wave: %s/%d/%s" % [map_id, tier, testing])
			for row: Dictionary in preview.special_modifiers:
				var compiled: Dictionary = Maps.compile(map_id, [], [row.id]) if testing else Maps.compile_normal(map_id, tier, [], [row.id])
				check(row.available == compiled.ok and row.reason == compiled.reason and row.minimum_wave == Maps.Catalog.SPECIAL[row.id].minimum_wave,
					"Special availability equals existing compiler: %s/%d/%s/%s" % [map_id, tier, row.id, testing])
	check(not arena.map_modifier_availability("missing", 1).ok, "Unknown preview rejects")
	if not testing: check(not arena.map_modifier_availability("old_garden", 0).ok, "Malformed formal tier rejects")
	check(observe() == before, "All pure previews preserve snapshot, disk, saves, draft, world and RNG")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-map-modifier-preflight.") or FileAccess.file_exists("user://build_save.json"):
		printerr("Use a fresh isolated /tmp/godot-m1-map-modifier-preflight.* directory"); quit(78); return
	arena = ObservedArena.new(); root.add_child(arena)
	arena.set_process(false); arena.set_physics_process(false); arena.hud.set_process(false); arena.auto_fire = false
	await settle()
	if not check(arena.save_build(), "Save fresh canonical normal fixture"): await finish(); return
	# Canonical UI fixture only: unlock lawful selectors with trusted transactions,
	# without claiming earned combat, root kills or new economic balance evidence.
	for pair: Array in [["old_garden", 1], ["old_garden", 2], ["broken_ruins", 1]]:
		var profile: Dictionary = Maps.compile_normal(pair[0], pair[1], [], []).profile
		var started: Dictionary = arena.state.normal_start_map(profile, arena.state.revision(), arena.build_save_path)
		if not accepted(started, "Trusted fixture admission"): await finish(); return
		if not accepted(arena.state.normal_complete_map(started.run_id, arena.state.revision(), arena.build_save_path), "Trusted fixture unlock"): await finish(); return
		if not accepted(arena.state.normal_claim_rewards(arena.state.revision(), arena.build_save_path), "Trusted fixture claim"): await finish(); return
	check_preview(false)
	panel = arena.hud._town_view; panel.open_service("map_device"); await settle()
	check(panel._map_gate_status.text == "当前挑战强度 1", "Formal tier I immediately shows actual wave one")
	for check_box: CheckBox in panel._special.values():
		check(check_box.disabled and not check_box.button_pressed and check_box.text.contains("最低强度") and check_box.text.contains("当前不可用") and check_box.tooltip_text.contains("最低强度") and check_box.tooltip_text.contains("当前挑战强度 1"), "Low-tier unavailable option visibly disabled without selection")
	check(not panel._map_prepare.disabled and not panel._map_gate_cancel.visible, "Unavailable unselected options do not block plain map preparation")
	var before := observe()
	select_option(panel._tier_select, 2); await settle()
	check(panel._map_gate_status.text == "当前挑战强度 4" and not panel._special.elemental_aegis.disabled and panel._special.storm_patrol.disabled, "Tier II recalculates exact wave-four/five boundary")
	select_option(panel._tier_select, 3); await settle()
	check(not panel._special.storm_patrol.disabled and panel._map_gate_status.text == "当前挑战强度 8", "Higher tier makes wave-five special available")
	panel._normal.enemy_damage_115.button_pressed = true
	panel._special.storm_patrol.button_pressed = true; await settle()
	select_option(panel._tier_select, 1); await settle()
	check(panel._special.storm_patrol.button_pressed and panel._special.storm_patrol.disabled, "Downgrade retains checked special and disables unavailable checkbox")
	check(panel._map_prepare.disabled and panel._map_launch.disabled and panel._map_gate_cancel.visible
		and panel._map_gate_status.text.contains("已选词缀不适用") and panel._map_gate_status.text.contains("雷纹巡逻（最低强度 5）"), "Retained invalid selection explains remediation and blocks prepare/launch")
	check(observe() == before, "Changing tier and modifier controls never mutates or charges authority")
	capture("formal_downgrade_retained")
	if DisplayServer.get_name() != "headless":
		var scroll := panel._content.get_parent() as ScrollContainer
		scroll.scroll_vertical = int(panel._map_gate_status.position.y)
		await process_frame; await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/qa/map-modifier-preflight/downgrade.png") == OK, "Capture native downgrade warning in existing scroll viewport")
	var normal_calls := arena.normal_prepares
	panel._map_prepare.pressed.emit(); panel._map_launch.pressed.emit(); await settle()
	check(arena.normal_prepares == normal_calls and observe() == before, "Forced invalid prepare/launch signals never reach transactions or charge")
	for unused: int in range(3): arena.world_context_changed.emit()
	await settle()
	check(panel._special.storm_patrol.button_pressed and panel._map_prepare.disabled and observe() == before, "World refresh preserves invalid user choice and block")
	select_option(panel._map_select, "broken_ruins"); await settle()
	check(panel._map_gate_status.text.contains("当前挑战强度 2") and panel._special.storm_patrol.button_pressed and panel._map_prepare.disabled, "Map change preserves invalid choice and recomputes tier-I wave")
	select_option(panel._tier_select, 2); await settle()
	check(panel._map_gate_status.text == "当前挑战强度 5" and not panel._special.storm_patrol.disabled and not panel._map_prepare.disabled
		and not panel._map_gate_cancel.visible and panel._special.storm_patrol.button_pressed, "New map high tier restores existing choice without clearing it")
	panel._map_prepare.pressed.emit(); await settle()
	var prepared: Dictionary = arena.map_draft()
	check(prepared.map_id == "broken_ruins" and prepared.tier == 2 and prepared.special_ids == ["storm_patrol"] and prepared.normal_ids == ["enemy_damage_115"]
		and arena.normal_prepares == normal_calls + 1 and arena.test_prepares == 0, "Valid normal prepare routes once with exact retained choice")
	check(not panel._map_selection_dirty and not panel._map_launch.disabled and arena.state.crafting_balance() == 12, "Preparation restores clean launch and keeps all fixture shards")
	capture("formal_prepared")
	before = observe()
	select_option(panel._tier_select, 1); await settle()
	panel._map_gate_cancel.pressed.emit(); await settle()
	check(not panel._special.storm_patrol.button_pressed and panel._normal.enemy_damage_115.button_pressed and panel._special.storm_patrol.disabled and not panel._map_prepare.disabled
		and not panel._map_gate_cancel.visible and panel._map_launch.disabled and panel._map_selection_dirty, "Explicit cancel removes only invalid selection; old prepared draft remains blocked")
	check(observe() == before, "Cancelling invalid selection changes no authority, draft or balance")
	panel.hide(); panel.open_service("map_device"); await settle()
	check(panel._tier_select.get_selected_metadata() == 2 and panel._special.storm_patrol.button_pressed and not panel._map_launch.disabled,
		"Close/reopen cancels edits and restores authoritative prepared selection")
	# Existing asynchronous native-entry preparation must cancel on panel hide.
	select_option(panel._map_select, "ruins_garden"); panel._map_gate_cancel.pressed.emit(); await settle()
	panel._map_prepare.pressed.emit(); await settle()
	before = observe()
	panel._map_launch.pressed.emit()
	check(arena.map_preparation_pending(), "Native-map launch enters existing asynchronous terrain preparation")
	panel.hide()
	for unused: int in range(12):
		if not arena.map_preparation_pending(): break
		await physics_frame
	await settle()
	check(not arena.map_preparation_pending() and arena.world_context().normal_town and observe() == before,
		"Hide cancels native-entry preparation before admission, fee or run mutation")
	if not accepted(arena.enter_town_test(arena.world_context().revision), "Enter existing independent test profile"): await finish(); return
	await settle(); panel.open_service("map_device"); await settle()
	check_preview(true)
	check(not panel._tier_select.visible and panel._map_gate_status.text == "当前挑战强度 4"
		and not panel._special.elemental_aegis.disabled and panel._special.storm_patrol.disabled, "Test old garden uses fixed wave four, independent of formal tier I")
	check(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision).code == "not_in_normal_town", "Formal prepare API rejects test profile")
	select_option(panel._map_select, "broken_ruins"); await settle()
	panel._special.storm_patrol.button_pressed = true; await settle()
	check(not panel._special.storm_patrol.disabled and panel._map_gate_status.text == "当前挑战强度 5", "Test map switch recomputes fixed wave five")
	before = observe(); normal_calls = arena.normal_prepares
	panel._map_prepare.pressed.emit(); await settle()
	check(arena.test_prepares == 1 and arena.normal_prepares == normal_calls and arena.map_draft().special_ids == ["storm_patrol"], "Test prepare routes solely through existing free test API")
	check(arena.state.crafting_balance() == 12 and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH) == bytes_at_normal_save(before), "Test preparation preserves normal save and existing shard balance")
	capture("test_prepared")
	before = observe(); select_option(panel._map_select, "old_garden"); await settle()
	check(panel._special.storm_patrol.button_pressed and panel._special.storm_patrol.disabled and panel._map_prepare.disabled, "Test downgrade also retains invalid special and blocks preparation")
	panel._map_prepare.pressed.emit(); await settle()
	check(arena.test_prepares == 1 and observe() == before, "Invalid test preparation performs no free transaction or state mutation")
	panel._map_gate_cancel.pressed.emit(); await settle()
	check(not panel._map_prepare.disabled and not panel._special.storm_patrol.button_pressed, "Explicit test cancel restores plain-map preparation")
	if not accepted(arena.leave_town_test(arena.world_context().revision), "Return to normal profile"): await finish(); return
	await settle(); panel.open_service("map_device"); await settle()
	check(panel._tier_select.visible and panel._map_gate_status.text == "当前挑战强度 1" and arena.map_draft().map_id == "ruins_garden", "Normal entry restores its own draft, actual tier and gates")
	check(arena.craft_map("old_garden", [], [], arena.map_draft().revision).code == "not_in_test_town", "Test prepare API rejects normal profile")
	check(arena.state.normal_journey().normal_root_kills == 0, "UI fixture performs no gameplay or root kills")
	await finish()
func bytes_at_normal_save(snapshot: PackedByteArray) -> PackedByteArray:
	return bytes_to_var(snapshot)[8]
func finish() -> void:
	var hashes: Dictionary = {}
	for path: String in ["scripts/main.gd", "scripts/ui/town_service_panel.gd", "scripts/world/map_compiler.gd", "scripts/world/map_catalog.gd", "scripts/world/normal_map_catalog.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	var report := {"checks": checks, "failures": failures.size(), "failed_labels": failures, "states": states, "source_sha256": hashes,
		"display": DisplayServer.get_name(), "method": "Fresh canonical trusted UI fixtures, actual Main/panel/signals; no combat, model assets, migration or long-run test"}
	var target := OS.get_environment("MAP_PREFLIGHT_REPORT")
	if not target.is_empty():
		var output := FileAccess.open(target, FileAccess.WRITE)
		output.store_string(JSON.stringify(report, "\t") + "\n"); output.close()
	print("MAP_MODIFIER_PREFLIGHT " + JSON.stringify(report))
	if is_instance_valid(arena): arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
