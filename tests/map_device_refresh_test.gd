extends SceneTree
## v081: real main, canonical transactions and connected UI signals. No combat.
const Maps = preload("res://scripts/world/map_compiler.gd")
const ISOLATION_ROOT := "/tmp/godot-m1-v081-map-refresh"

class ObservedArena extends "res://scripts/main.gd":
	var map_draft_calls := 0
	func map_draft() -> Dictionary:
		map_draft_calls += 1
		return super.map_draft()

var arena: ObservedArena
var panel: Control
var inventory: Control
var checks := 0
var failures := 0
var finished := false
var observations: Array[Dictionary] = []
var checkpoints: Array[Dictionary] = []
var bought: Array[String] = []

func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if OS.get_name() != "Linux" or not isolated.begins_with(ISOLATION_ROOT + "/") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		push_error("Refusing non-isolated userdata; use /tmp/godot-m1-v081-map-refresh/<attempt>/data")
		quit(78)
		return
	if FileAccess.file_exists("user://build_save.json") or FileAccess.file_exists("user://town_test_build_save.json"):
		push_error("Refusing a previously populated fixture profile")
		quit(78)
		return
	create_timer(45.0).timeout.connect(func() -> void:
		if not finished:
			check(false, "Focused UI fixture exceeded its 45-second guard")
			finish())
	call_deferred("run")

func run() -> void:
	arena = ObservedArena.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	await settle()
	panel = arena.hud._town_view
	var model: RefCounted = arena.state
	if not check(arena.world_context().normal_town and not arena.world_context().test_mode, "Actual main starts in the normal town"):
		finish(); return
	if not check(model.save_build(arena.build_save_path) == OK, "Fresh canonical profile has a real save receipt"):
		finish(); return
	# Trusted canonical journey transactions supply a valid unlocked save without combat.
	for map_id: String in ["old_garden", "broken_ruins"]:
		var compiled: Dictionary = Maps.compile_normal(map_id, 1, [], [])
		if not check(compiled.ok, "Catalog supplies legal tier-I fixture: " + map_id):
			finish(); return
		var admission: Dictionary = model.normal_start_map(compiled.profile, model.revision(), arena.build_save_path)
		if not check(admission.ok, "Canonical fixture admits tier I: " + map_id):
			finish(); return
		if not check(model.normal_complete_map(admission.run_id, model.revision(), arena.build_save_path).ok, "Trusted fixture completion unlocks tier II: " + map_id):
			finish(); return
		if not check(model.normal_claim_rewards(model.revision(), arena.build_save_path).ok, "Canonical claim resolves fixture pending reward: " + map_id):
			finish(); return
	check(model.crafting_balance() == 8 and model.Journey.reason(model.normal_journey()).is_empty(), "Both independent unlocks and eight real reward shards validate")
	panel.hide()
	await settle()
	arena.map_draft_calls = 0
	var uid := "item_%06d" % int(model.snapshot().next_item_serial)
	if not check(model._admit_reward_item(model.Items.calibration_shard(uid, 11)), "v044-style fixture admits a legal catalog shard item"):
		finish(); return
	for index: int in range(3): arena.world_context_changed.emit()
	await settle()
	check(arena.map_draft_calls == 0, "Hidden panel derives no map draft after real model mutation and world signals")
	check(model.crafting_balance() == 19 and model.save_build(arena.build_save_path) == OK, "Fixture has nineteen physical shards and current receipt")
	panel.open_service("skill_merchant")
	for index: int in range(2):
		var ids: Array = model.snapshot().items.keys()
		panel._request_gem_purchase("skill:bolt")
		if not check(panel._gem_dialog.visible and not panel._gem_pending.is_empty(), "Real merchant quotes fixture gem " + str(index + 1)):
			finish(); return
		panel._gem_dialog.confirmed.emit()
		for candidate: String in model.snapshot().items:
			if candidate not in ids and model.item(candidate).definition_id == "skill:bolt": bought.append(candidate)
	if not check(bought.size() == 2 and bought[0] != bought[1] and model.crafting_balance() == 3, "v044 purchase path leaves two separate legal gems and balance three"):
		finish(); return
	panel._gem_dialog.hide()
	arena.hud.open_panel("inventory")
	inventory = arena.hud._inventory_panel
	panel.open_service("map_device")
	await settle()
	check(panel.is_visible_in_tree() and inventory.is_visible_in_tree(), "Actual map device and canonical inventory are open together")
	var before := observe("before_queued_hide")
	arena.map_draft_calls = 0
	for index: int in range(3): arena.world_context_changed.emit()
	panel.hide()
	await settle()
	check(arena.map_draft_calls == 0, "Queued visible refresh checks visibility again and derives nothing after hide")
	check(observe("after_queued_hide") == before, "Queue then hide changes no snapshot, draft, RNG, save count or disk bytes")
	panel.open_service("map_device")
	if not select_option(panel._tier_select, 2, "Select unlocked tier II through OptionButton signal"):
		finish(); return
	var prepare := find_button("准备地图")
	if not check(prepare != null, "Actual normal prepare button exists"):
		finish(); return
	prepare.pressed.emit()
	await settle()
	var draft: Dictionary = arena.map_draft()
	if not check(draft.map_id == "old_garden" and draft.tier == 2 and draft.cost == 4 and not draft.can_start and not str(draft.reason).is_empty(), "Authority prepares tier II at cost four with insufficient-funds reason"):
		finish(); return
	var original_launch: Button = panel._map_launch
	var original_summary: Label = panel._map_summary
	var original_map: OptionButton = panel._map_select
	check(original_launch.disabled and original_summary.text.contains(str(draft.reason)), "Existing launch and reason reflect the three-shard authoritative draft")
	var prepared_revision: int = int(draft.revision)
	if not open_recycle(bought[0]):
		finish(); return
	inventory._craft_dialog.confirmed.emit()
	if not check(model.crafting_balance() == 4 and model.item(bought[0]).is_empty() and not model.item(bought[1]).is_empty(), "Real selected-gem recycle credits exactly one shard: three to four"):
		finish(); return
	var after_recycle := observe("immediate_after_first_recycle")
	check(int(after_recycle.draft.revision) == prepared_revision, "Recycle changes model state but does not increment map draft revision")
	arena.map_draft_calls = 0
	for index: int in range(5): arena.world_context_changed.emit()
	await settle()
	check(arena.map_draft_calls == 1, "Real model/world notification burst coalesces into one deferred map-draft read")
	check(observe("settled_after_first_recycle") == after_recycle, "Deferred affordability refresh has no transaction, snapshot, revision, RNG or save side effect")
	draft = arena.map_draft()
	check(panel._map_launch == original_launch and panel._map_summary == original_summary and panel._map_select == original_map, "Refresh retains original launch, summary and selection controls")
	check(draft.can_start and str(draft.reason).is_empty() and not original_launch.disabled, "Original launch enables from authoritative affordability without reopening")
	check(original_summary.text == expected_summary(draft) and not original_summary.text.contains("不足"), "Visible insufficient-funds reason clears and cost/reward remain authoritative")
	# Keep an affordable prepared draft, then edit all control categories without preparing.
	if not select_option(panel._map_select, "broken_ruins", "Change the map without preparing"):
		finish(); return
	if not select_option(panel._tier_select, 2, "Select the independently unlocked second-map tier II"):
		finish(); return
	var normal_id: String = str(arena.map_options().normal_modifiers[0].id)
	var special_id := "elemental_aegis"
	if not check(Maps.compile_normal("broken_ruins", 2, [normal_id], [special_id]).ok, "Dirty selections use legal ordinary and special catalog modifiers"):
		finish(); return
	panel._normal[normal_id].button_pressed = true
	panel._special[special_id].button_pressed = true
	var selected := selection()
	check(original_launch.disabled and panel._map_selection_dirty and arena.map_draft().can_start, "Unprepared selections disable launch while previous authority draft remains affordable")
	if not open_recycle(bought[1]):
		finish(); return
	inventory._craft_dialog.confirmed.emit()
	if not check(model.crafting_balance() == 5 and model.item(bought[1]).is_empty(), "Second real gem recycle supplies a balance-change event while selections are dirty"):
		finish(); return
	var dirty_after_trade := observe("immediate_after_dirty_recycle")
	arena.map_draft_calls = 0
	for index: int in range(5): arena.world_context_changed.emit()
	await settle()
	check(arena.map_draft_calls == 1, "Dirty selection model/world burst is also coalesced to one authority read")
	check(selection() == selected and panel._map_select == original_map and panel._map_launch == original_launch, "Balance and world refresh preserve map, tier, both modifiers and original controls")
	check(original_launch.disabled and panel._map_selection_dirty and arena.map_draft().can_start, "Refresh cannot enable the affordable old draft while selections are unprepared")
	check(observe("settled_after_dirty_recycle") == dirty_after_trade, "Dirty refresh leaves post-transaction model, draft, disk and save counters unchanged")
	before = observe("before_world_only_refresh")
	arena.map_draft_calls = 0
	for index: int in range(3): arena.world_context_changed.emit()
	await settle()
	check(arena.map_draft_calls == 1 and selection() == selected and original_launch.disabled, "World-only burst preserves unprepared controls and launch gate")
	check(observe("after_world_only_refresh") == before, "World-only refresh performs no model mutation, currency debit or save")
	prepare = find_button("准备地图")
	prepare.pressed.emit()
	await settle()
	draft = arena.map_draft()
	check(draft.map_id == selected.map_id and draft.tier == selected.tier and draft.normal_ids == selected.normal_ids and draft.special_ids == selected.special_ids, "Prepare commits the exact selected map, tier and modifiers through main")
	check(draft.revision == prepared_revision + 1 and draft.cost == 4 and draft.can_start and not panel._map_launch.disabled, "Explicit prepare alone advances draft revision and enables the legal cost-four launch")
	check(model.crafting_balance() == 5 and var_to_bytes(model.snapshot()) == before.state and FileAccess.get_file_as_bytes(arena.build_save_path) == before.disk and model.successful_saves == before.model_saves, "Preparation does not charge, alter canonical snapshot or save")
	var launch: Button = panel._map_launch
	var balance_before: int = model.crafting_balance()
	var next_run_before: int = model.normal_journey().next_run_id
	launch.pressed.emit()
	var after_launch := observe("after_first_launch")
	check(arena.world_context().mode == "map" and model.crafting_balance() == balance_before - int(draft.cost), "One real launch signal enters selected map and debits authority cost four exactly once")
	check(model.normal_journey().active_run.run_id == next_run_before and model.normal_journey().next_run_id == next_run_before + 1 and model.normal_journey().active_run.fee_paid == int(draft.cost), "One persisted run receipt records the exact selected fee")
	launch.pressed.emit()
	launch.pressed.emit()
	await settle()
	check(observe("after_duplicate_launch_signals") == after_launch, "Repeated captured launch signals cannot charge, save, issue a run or enter again")
	check(model.normal_journey().normal_root_kills == 0, "Focused fixture performs no combat or root-kill progression")
	finish()

func open_recycle(uid: String) -> bool:
	inventory._select_item(uid)
	if not check(not inventory._craft_controls._salvage_button.disabled, "Existing recycle button accepts the selected legal bag gem: " + uid): return false
	inventory._craft_controls._salvage_button.pressed.emit()
	return check(inventory._craft_dialog.visible and bool(inventory._pending_craft.get("gem", false)), "Existing recycle button opens the real gem confirmation: " + uid)

func select_option(button: OptionButton, metadata: Variant, label: String) -> bool:
	for index: int in range(button.item_count):
		if button.get_item_metadata(index) != metadata: continue
		if not check(not button.is_item_disabled(index), label): return false
		button.select(index)
		button.item_selected.emit(index)
		return true
	return check(false, label + ": option missing")

func find_button(label: String) -> Button:
	for child: Node in panel._content.get_children():
		if child is Button and child.text == label: return child
	return null

func selection() -> Dictionary:
	var normal_ids: Array = []
	var special_ids: Array = []
	for id: String in panel._normal:
		if panel._normal[id].button_pressed: normal_ids.append(id)
	for id: String in panel._special:
		if panel._special[id].button_pressed: special_ids.append(id)
	normal_ids.sort(); special_ids.sort()
	return {"map_id": panel._map_select.get_selected_metadata(), "tier": panel._tier_select.get_selected_metadata(), "normal_ids": normal_ids, "special_ids": special_ids}

func expected_summary(draft: Dictionary) -> String:
	var text_value: String = str(draft.summary) + "\n入场 %d 校准碎片 · 完成奖励 %d" % [int(draft.cost), int(draft.completion_reward)]
	if not str(draft.reason).is_empty(): text_value += "\n" + str(draft.reason)
	return text_value

func settle() -> void:
	await process_frame
	await process_frame

func observe(label: String) -> Dictionary:
	var value := {"state": var_to_bytes(arena.state.snapshot()), "draft": arena.map_draft(), "world": arena.world_context(),
		"disk": FileAccess.get_file_as_bytes(arena.build_save_path), "model_saves": arena.state.successful_saves,
		"model_save_attempts": arena.state.save_attempts, "main_saves": arena.progress_save_success_count,
		"main_save_attempts": arena.progress_save_attempt_count, "rng": arena.rng.state,
		"run": arena._map_run.snapshot(), "run_revision": arena.run_revision}
	checkpoints.append({"label": label, "balance": arena.state.crafting_balance(), "model_revision": arena.state.revision(),
		"draft": value.draft, "model_saves": value.model_saves, "model_save_attempts": value.model_save_attempts,
		"main_saves": value.main_saves, "main_save_attempts": value.main_save_attempts,
		"state_sha256": sha256(value.state), "disk_sha256": sha256(value.disk), "world_mode": value.world.mode,
		"world_revision": value.world.revision, "next_run_id": arena.state.normal_journey().next_run_id})
	return value

func sha256(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()

func check(value: bool, label: String) -> bool:
	checks += 1
	observations.append({"passed": value, "label": label})
	if not value:
		failures += 1
		push_error(label)
	return value

func finish() -> void:
	if finished: return
	finished = true
	var output := OS.get_environment("V081_QA_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks": checks, "failures": failures, "scope": "Linux headless real main/canonical/UI signals; no physical mouse, Windows performance, combat or export", "observations": observations, "checkpoints": checkpoints}, "\t"))
			file.close()
		else: check(false, "Cannot write focused QA JSON: " + output)
	print("Map device refresh: %d checks, %d failures" % [checks, failures])
	if is_instance_valid(arena): arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
