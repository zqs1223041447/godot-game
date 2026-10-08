extends SceneTree
## Actual HUD signals, real native preparation and canonical fee/save transactions.
## Death/readiness/write faults are controlled fixtures; no balance/unlock injection.
const Model = preload("res://scripts/canonical_game_state.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const FIXTURE := "res://docs/qa/v115-native-map-entry/earned-v114-save.json"
const SAVE := "user://build_save.json"

class FaultModel extends Model:
	var fail_writes := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path, bytes)

class ObservedMain extends "res://scripts/main.gd":
	var native_calls := 0
	var normal_calls := 0
	var last_native_result: Dictionary = {}
	func retry_native_map(expected_revision: Variant) -> Dictionary:
		native_calls += 1
		last_native_result = await super.retry_native_map(expected_revision)
		return last_native_result
	func retry_normal_map(expected_revision: Variant) -> Dictionary:
		normal_calls += 1
		return super.retry_normal_map(expected_revision)

var arena: Node2D
var model: FaultModel
var town_seed := PackedByteArray()
var checks := 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var group := "setup"
var original_fixture_sha := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	evidence.append({"case": group, "ok": ok, "label": label})
	if not ok: failures.append(group + ": " + label); push_error(group + ": " + label)
	return ok
func accepted(result: Dictionary, label: String) -> bool:
	return check(bool(result.get("ok", false)), label + ": " + str(result.get("reason", "")))
func disk() -> PackedByteArray: return FileAccess.get_file_as_bytes(SAVE)
func snapshot() -> Dictionary:
	return {"state": model.snapshot(), "disk": disk(), "world": arena.world_context(),
		"draft": arena.map_draft(), "rng": arena.rng.state, "run_revision": arena.run_revision,
		"runtime": Encounter._snapshot(arena.monster_runtime), "enemies": arena.enemies.duplicate(true),
		"geometry": arena.world_geometry(), "geometry_id": arena._geometry.get_instance_id(),
		"saves": model.successful_saves, "alive": arena.alive, "health": arena.health,
		"mana": arena.mana, "processing": arena.is_processing()}
func pause() -> void:
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	for unused: int in range(4): arena.hud.close_panel()
func dispose() -> void:
	if is_instance_valid(arena): arena.queue_free(); await process_frame
	arena = null; model = null
func load_arena(bytes: PackedByteArray) -> bool:
	await dispose()
	var output := FileAccess.open(SAVE, FileAccess.WRITE)
	if not check(output != null, "Open only isolated suite save"): return false
	output.store_buffer(bytes); output.close()
	arena = load("res://scenes/main.tscn").instantiate(); arena.set_script(ObservedMain)
	model = FaultModel.new(); arena.state = model
	root.add_child(arena); pause(); await process_frame
	arena.rng.seed = 116550
	return check(arena.world_context().normal_town and Model.Rules.reason(model.snapshot()).is_empty(), "Actual Main opens legal formal town")
func settle() -> void:
	for unused: int in range(16):
		if not arena.map_preparation_pending() and not arena.hud._restart_pending:
			await process_frame; return
		await physics_frame
	check(false, "Native HUD operation settles within sixteen physics frames")
func retry_button(overlay: String) -> Button:
	return arena.hud._root.find_child("RetryButton" if overlay == "death" else "RestartButton", true, false) as Button
func open_overlay(overlay: String) -> void:
	if overlay == "death":
		arena.health = 0.0; arena._finish_player_death()
	else: arena.hud.open_panel("pause")
func released(candidate: RefCounted) -> bool:
	return not candidate._space.is_valid() and candidate._bodies.is_empty() and candidate._shapes.is_empty() and not candidate.physics_ready()
func create_seed() -> bool:
	# Reuse the immutable earned four-shard save. Clear one actual finite native
	# tier-I map to earn four more and unlock tier II through current gameplay.
	original_fixture_sha = FileAccess.get_sha256(FIXTURE)
	if not await load_arena(FileAccess.get_file_as_bytes(FIXTURE)): return false
	if not check(model.crafting_balance() == 4, "Original earned fixture contains four physical shards"): return false
	if not accepted(arena.craft_normal_map("ruins_garden", 1, [], [], arena.map_draft().revision), "Prepare actual native tier-I seed map"): return false
	if not accepted(await arena.open_map(arena.map_draft().revision), "Enter existing native map"): return false
	arena._begin_progress_transaction()
	for unused: int in range(8):
		for enemy: Dictionary in arena.enemies.duplicate():
			if float(enemy.health) > 0.0:
				enemy.spawn = 0.0
				arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 10000.0, Color.WHITE)
		arena._flush_monster_spawns()
	arena._check_map_complete(); arena._end_progress_transaction()
	if not check(arena.world_context().mode == "map_complete" and arena.reward_kills == 25, "Bounded genuine 25-root map completes through original death ledger"): return false
	if not accepted(arena.return_to_town(arena.world_context().revision), "Original native completion returns to town"): return false
	if not accepted(arena.claim_normal_rewards(arena.world_context().revision), "Original claim earns four more shards"): return false
	if not check(model.crafting_balance() == 8 and model.normal_journey().best_tiers.ruins_garden == 1, "Earned eight-shard town and unlocked native tier II; no grant fixture"): return false
	town_seed = disk()
	return true
func fresh(overlay: String, map_id: String = "ruins_garden") -> bool:
	if not await load_arena(town_seed): return false
	if not accepted(arena.craft_normal_map(map_id, 2, [], [], arena.map_draft().revision), "Select lawful paid tier-II map"): return false
	if not accepted(await arena.open_map(arena.map_draft().revision), "Existing entry starts this map"): return false
	if not check(model.crafting_balance() == 4 and arena.world_context().mode == "map", "Original entry charges four once"): return false
	open_overlay(overlay)
	return check(str(arena.hud._menu_routes.snapshot().overlay) == overlay and retry_button(overlay) != null, "Actual named HUD retry button is visible in " + overlay)
func button_cases() -> void:
	for overlay: String in ["pause", "death"]:
		for fault: String in ["none", "write", "native_readiness"]:
			group = overlay + " / " + fault
			if not await fresh(overlay): return
			var before := snapshot()
			var menu: RefCounted = arena.hud._menu_routes
			var old_geometry: RefCounted = arena._geometry
			var button := retry_button(overlay)
			model.fail_writes = fault == "write"
			button.pressed.emit()
			if not check(arena.map_preparation_pending() and arena.hud._restart_pending, "Actual button dispatch waits for existing native preparation"): return
			var candidate: RefCounted = arena._native_entry_session._entry.geometry_ref()
			check(button.disabled and button.text == "准备地形…" and arena._geometry == old_geometry, "Pending UI disables retry and keeps original live geometry")
			button.pressed.emit(); button.pressed.emit()
			arena.hud.refresh_build()
			button = retry_button(overlay)
			check(button.disabled and button.text == "准备地形…", "Menu rebuild retains pending button state")
			button.pressed.emit()
			if fault == "native_readiness": candidate._release_native()
			await settle()
			check(arena.native_calls == 1 and arena.normal_calls == 0, "Repeated real signals dispatch one native call and no synchronous retry")
			if fault == "none":
				check(arena.last_native_result.ok and model.crafting_balance() == 0 and arena._normal_run_id == before.state.journey.active_run.run_id + 1 and model.successful_saves == before.saves + 1, "Successful HUD retry charges four once and creates one saved run")
				check(arena._geometry == candidate and candidate.physics_ready() and released(old_geometry), "Install same fully prepared candidate; release original native owner")
				check(arena.alive and not arena.hud.is_blocking() and arena.hud._menu_routes.snapshot().overlay == "" and not arena.hud._menu_routes.snapshot().death_latched, "Only success closes current menu and restores playable life")
				check(model.normal_journey().normal_root_kills == before.state.journey.normal_root_kills and model.snapshot().next_item_serial == before.state.next_item_serial and arena.enemies.size() == 25, "Retry preserves reward counters/UID serial and original finite roster")
			else:
				check(not arena.last_native_result.ok and snapshot() == before, "Failed native/readiness or save transaction preserves full original gameplay, money, RNG and disk")
				check(arena.hud._menu_routes == menu and str(menu.snapshot().overlay) == overlay and arena.hud.is_blocking(), "Failure keeps the original pause/death menu")
				button = retry_button(overlay)
				check(not button.disabled and button.text != "准备地形…", "Failure restores original retry label and enabled state")
				var reason: String = str(arena.last_native_result.reason)
				check(not reason.is_empty() and (arena.hud._panel_footer.text == reason or arena.hud._panel_footer.tooltip_text.contains(reason)), "Existing visible feedback presents real transaction reason")
				check(arena._geometry == old_geometry and old_geometry.physics_ready() and released(candidate), "Failure disposes detached candidate while retaining original native geometry")
			model.fail_writes = false
			var restored := Model.new()
			check(restored.load_build(SAVE) and restored.snapshot() == model.snapshot(), "Result reloads as exact canonical snapshot")
			if fault != "none":
				retry_button(overlay).pressed.emit()
				check(arena.map_preparation_pending(), "Same failure menu can request a healthy retry after fault clears")
				await settle()
				check(arena.last_native_result.ok and arena.native_calls == 2 and arena.normal_calls == 0 and model.crafting_balance() == 0 and model.successful_saves == before.saves + 1, "Retry after failure charges/saves once, without reviving discarded candidate")
				check(arena.alive and not arena.hud.is_blocking() and released(old_geometry) and arena._geometry.physics_ready(), "Recovered pause/death request closes menu and adopts valid native map")
func context_cases() -> void:
	for change: String in ["close", "close_reopen", "settings", "death_return", "world_return", "model_change"]:
		group = "waiting / " + change
		var overlay := "death" if change == "death_return" else "pause"
		if not await fresh(overlay): return
		var before := snapshot()
		var old_geometry: RefCounted = arena._geometry
		retry_button(overlay).pressed.emit()
		if not check(arena.map_preparation_pending(), "Actual button begins waiting before user context change"): return
		var candidate: RefCounted = arena._native_entry_session._entry.geometry_ref()
		if change in ["close", "close_reopen"]:
			arena.hud.close_panel()
			if change == "close_reopen": arena.hud.open_panel("pause")
		elif change == "settings": arena.hud.open_panel("settings")
		elif change == "death_return":
			arena.hud._root.find_child("DeathReturnTown", true, false).pressed.emit()
		elif change == "world_return":
			accepted(arena.return_to_town(arena.world_context().revision), "Original return during native wait")
		else:
			var discard_uid := ""
			for uid: String in model.snapshot().items:
				if model.location(uid).kind == "bag" and model.item(uid).kind in ["skill_gem", "support_gem", "flask"]:
					discard_uid = uid; break
			if not check(not discard_uid.is_empty(), "Earned inventory contains a real discardable context-change item"): return
			accepted(model.discard_item(discard_uid, model.revision(), SAVE), "Actual canonical edit changes prepared context")
		var expected := snapshot()
		var expected_menu: Dictionary = arena.hud._menu_routes.snapshot()
		arena.hud.notify("后续操作提示")
		await settle()
		check(not arena.last_native_result.ok and snapshot() == expected, "Waiting operation cannot commit after cancel/context change or overwrite newer gameplay")
		check(arena.native_calls == 1 and arena.normal_calls == 0 and model.crafting_balance() == 4 and model.normal_journey().next_run_id == before.state.journey.next_run_id, "Cancelled/stale result makes no second run or fee")
		check(arena.hud._menu_routes.snapshot() == expected_menu, "Late result does not close/reopen/replace newer menu")
		if change == "model_change":
			check(arena.hud._panel_footer.text == arena.last_native_result.reason, "Same menu receives true prepared-context failure reason")
		else:
			check(arena.hud._panel_footer.text == "后续操作提示" if arena.hud.is_blocking() else arena.hud._toast_label.text == "后续操作提示", "Cancelled/obsolete result does not overwrite later user feedback")
		check(released(candidate), "Cancelled/stale detached native resources are released")
		if change not in ["death_return", "world_return"]:
			check(arena._geometry == old_geometry and old_geometry.physics_ready(), "Menu/context cancellation keeps original map native owner")
		else:
			check(arena.world_context().normal_town and model.normal_journey().active_run.is_empty() and arena.alive, "Return stays in lawful town instead of re-entering old map")
func ordinary_cases() -> void:
	for overlay: String in ["pause", "death"]:
		group = "ordinary / " + overlay
		if not await fresh(overlay, "old_garden"): return
		var before := snapshot()
		retry_button(overlay).pressed.emit()
		check(arena.native_calls == 0 and arena.normal_calls == 1 and not arena.map_preparation_pending() and not arena.hud._restart_pending, "Actual ordinary HUD button retains original synchronous route")
		check(model.crafting_balance() == 0 and model.successful_saves == before.saves + 1 and arena._normal_run_id == before.state.journey.active_run.run_id + 1, "Ordinary retry retains one lawful fee/save/run")
		check(arena.alive and not arena.hud.is_blocking() and arena.world_context().map_id == "old_garden", "Ordinary success still closes menu and restores original map")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-ruins-hud-retry."): quit(78); return
	if await create_seed():
		await button_cases()
		await context_cases()
		await ordinary_cases()
	check(checks > 100, "All bounded actual-button groups executed")
	check(FileAccess.get_sha256(FIXTURE) == original_fixture_sha, "Original earned fixture is byte-identical")
	await dispose()
	var hashes: Dictionary = {}
	for path: String in ["scripts/game_hud.gd", "scripts/main.gd", "scripts/studies/modular_study_session.gd", "scripts/world/prepared_map_entry.gd", "scripts/ui/docked_menu_state.gd", "scripts/save/canonical_build_store.gd", "scripts/save/canonical_build_rules.gd", "tests/ruins_hud_retry_test.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	var report := {"checks": checks, "failures": failures.size(), "failed_labels": failures, "evidence": evidence, "source_sha256": hashes,
		"earned_fixture_sha256": original_fixture_sha, "display": DisplayServer.get_name(), "schema": Model.Rules.VERSION,
		"method": "Actual HUD pressed signals; original earned four-shard fixture plus one bounded native-map completion creates eight-shard lawful setup; no currency/unlock injection; controlled death, readiness and write faults"}
	var target := OS.get_environment("RUINS_HUD_RETRY_REPORT")
	if not target.is_empty():
		var output := FileAccess.open(target, FileAccess.WRITE); output.store_string(JSON.stringify(report, "\t") + "\n"); output.close()
	print("RUINS_HUD_RETRY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
