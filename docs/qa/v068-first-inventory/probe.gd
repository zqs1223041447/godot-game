extends SceneTree
## CPU-only diagnostic of the production root/HUD/model path. No timing gates.
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")

class TimedState extends "res://scripts/canonical_game_state.gd":
	var times: Dictionary = {}
	var counts: Dictionary = {}
	func mark(key: String, began: int) -> void:
		times[key] = int(times.get(key, 0)) + Time.get_ticks_usec() - began
		counts[key] = int(counts.get(key, 0)) + 1
	func item_definition(uid: String) -> Dictionary:
		var began := Time.get_ticks_usec(); var value := super.item_definition(uid)
		mark("item_definition", began); return value
	func snapshot() -> Dictionary:
		var began := Time.get_ticks_usec(); var value := super.snapshot()
		mark("snapshot", began); return value
	func add_normal_root_xp(amount: int) -> bool:
		var t := Time.get_ticks_usec(); var value := super.add_normal_root_xp(amount)
		mark("normal_root_xp_including_changed", t); return value
	func award_equipment(random: RandomNumberGenerator, level: int, rarity: String = "", pool: String = "current") -> String:
		var t := Time.get_ticks_usec(); var value := super.award_equipment(random, level, rarity, pool)
		mark("equipment_reward_including_changed", t); return value
	func award_jewel(random: RandomNumberGenerator) -> String:
		var t := Time.get_ticks_usec(); var value := super.award_jewel(random)
		mark("jewel_reward_including_changed", t); return value
	func crafting_operations(uid: Variant, path: String = "user://build_save.json") -> Array[Dictionary]:
		var t := Time.get_ticks_usec(); var value := super.crafting_operations(uid, path)
		mark("crafting_operations_metadata", t); return value
	func crafting_quote(operation: Variant, uid: Variant, path: String = "user://build_save.json") -> Dictionary:
		var t := Time.get_ticks_usec(); var value := super.crafting_quote(operation, uid, path)
		mark("crafting_quote", t); return value
	func execute_crafting(handle: Variant, source: Variant) -> Dictionary:
		var t := Time.get_ticks_usec(); var value := super.execute_crafting(handle, source)
		mark("execute_crafting_including_commit_changed", t); return value
	func _commit(candidate: Dictionary, path: String) -> Dictionary:
		var t := Time.get_ticks_usec(); var value := super._commit(candidate, path)
		mark("commit_including_persist_changed", t); return value
	func save_build(path: String = "user://build_save.json") -> Error:
		var t := Time.get_ticks_usec(); var value := super.save_build(path)
		mark("save_validation_serialize_write", t); return value
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		var t := Time.get_ticks_usec(); var value := super._write_bytes(path, bytes)
		mark("atomic_write_including_close", t); return value
	func _ensure_cache() -> void:
		var t := Time.get_ticks_usec(); super._ensure_cache(); mark("cache_checks_inclusive", t)

class TimedArena extends "/workspace/scratch/a51485f153de/v068-inventory-read-audit/main.gd":
	var times: Dictionary = {}
	var counts: Dictionary = {}
	func mark(key: String, began: int) -> void:
		times[key] = int(times.get(key, 0)) + Time.get_ticks_usec() - began
		counts[key] = int(counts.get(key, 0)) + 1
	func _on_build_changed() -> void:
		var t := Time.get_ticks_usec(); super._on_build_changed(); mark("changed_callback", t)
	func _flush_progress(force_save: bool = false) -> bool:
		var t := Time.get_ticks_usec(); var value := super._flush_progress(force_save)
		mark("progress_flush_HUD_save", t); return value
	func _sync_flasks(reset_run: bool = false) -> void:
		var t := Time.get_ticks_usec(); super._sync_flasks(reset_run); mark("sync_flasks", t)

var arena: TimedArena
var state: TimedState
var selected_uid := ""
var changed_count := 0
var rows: Array[Dictionary] = []
var first_view: Variant
var death_us := 0
var flush_us := 0

func _initialize() -> void: call_deferred("run")

func frames(count: int = 2) -> void:
	for unused: int in range(count): await process_frame

func marker() -> Dictionary:
	var panel = arena.hud._inventory_panel
	return {"changed":changed_count, "panel_exists":is_instance_valid(panel),
		"panel_visible":is_instance_valid(panel) and panel.is_visible_in_tree(),
		"refresh_generation":panel.refresh_generation if is_instance_valid(panel) else 0,
		"hud_blocking":arena.hud.is_blocking(), "kills":arena.kills, "reward_kills":arena.reward_kills,
		"normal_root_kills":int(state.normal_journey().normal_root_kills), "items":state.snapshot().items.size(),
		"shards":state.crafting_balance(), "crafting_revision":int(state.snapshot().crafting.revision),
		"successful_saves":state.successful_saves, "progress_hud_refreshes":arena.progress_hud_refresh_count,
		"progress_save_attempts":arena.progress_save_attempt_count}

func measure(label: String, operation: Callable) -> void:
	var before := marker()
	state.times.clear(); state.counts.clear(); arena.times.clear(); arena.counts.clear()
	var began := Time.get_ticks_usec(); operation.call(); var elapsed_us := Time.get_ticks_usec() - began
	var after := marker()
	rows.append({"phase":label, "synchronous_us":elapsed_us, "before":before, "after":after,
		"changed_signals":after.changed-before.changed, "panel_refreshes":after.refresh_generation-before.refresh_generation,
		"dropdown_rebuilds_inferred_from_UI_metadata_calls":int(state.counts.get("crafting_operations_metadata",0)),
		"state_nested_nonadditive_us":state.times.duplicate(), "state_calls":state.counts.duplicate(),
		"arena_nested_nonadditive_us":arena.times.duplicate(), "arena_calls":arena.counts.duplicate()})

func stable(value: Variant) -> Variant:
	if value is Resource: return {"resource_class":value.get_class(),"path":value.resource_path}
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[key]=stable(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(stable(item))
		return result
	return value

func press_i() -> void:
	var event := InputEventKey.new(); event.physical_keycode = KEY_I; event.pressed = true
	arena._unhandled_key_input(event)

func kill_roots() -> void:
	assert(not arena.hud.is_blocking() and not arena.demo_mode and not arena._is_test_profile())
	arena._begin_progress_transaction()
	var began := Time.get_ticks_usec()
	for enemy: Dictionary in arena.enemies:
		arena._damage_enemy(enemy, float(enemy.health)+float(enemy.shield)+1.0, Color.WHITE)
	death_us = Time.get_ticks_usec()-began; began = Time.get_ticks_usec()
	arena._end_progress_transaction(); flush_us = Time.get_ticks_usec()-began

func run() -> void:
	var data := OS.get_environment("XDG_DATA_HOME")
	var config := OS.get_environment("XDG_CONFIG_HOME")
	var cache := OS.get_environment("XDG_CACHE_HOME")
	var output := OS.get_environment("INVENTORY_PROFILE_OUT")
	if not data.begins_with("/tmp/godot-m1-v068-") or not config.begins_with("/tmp/godot-m1-v068-") \
			or not cache.begins_with("/tmp/godot-m1-v068-") or output.is_empty() \
			or not OS.get_user_data_dir().begins_with(data+"/") or FileAccess.file_exists("user://build_save.json"):
		push_error("Use fresh isolated /tmp/godot-m1-v068-* XDG roots and INVENTORY_PROFILE_OUT"); quit(78); return
	root.size = Vector2i(1280,720)
	state = TimedState.new()
	selected_uid = "gear_%06d" % int(state.snapshot().next_item_serial)
	assert(state._admit_reward_item(Items.wrap_equipment({"id":selected_uid,"base_id":"cinder_reed","rarity":"magic",
		"item_level":30,"affixes":[{"id":"deepwell","tier":1,"value":5}]})))
	var candidate: Dictionary = state.snapshot()
	assert(state._set_bag_currency_balance(candidate,100).ok)
	assert(Rules.reason(candidate).is_empty()); state._accept_memory(candidate)
	assert(state.save_build("user://build_save.json") == OK)
	arena = TimedArena.new(); arena.state = state
	root.add_child(arena); arena.set_process(false); arena.set_physics_process(false); arena.hud.set_process(false)
	assert(arena.leave_normal_town(arena.world_context().revision).ok)
	while arena.hud.is_blocking(): arena.hud.close_panel()
	arena.rng.seed = 500037; arena.enemies.clear(); arena.monster_runtime.reset(); arena.telegraphs.reset()
	arena.auto_fire = false; arena.spawn_timer = 100000.0
	for index: int in range(20):
		var enemy: Dictionary = arena.monster_runtime.create_root("crawler",1,arena.player_pos+Vector2(80+index*3,0),"ordinary","normal",[],true)
		assert(not enemy.is_empty() and enemy.reward_eligible and int(enemy.root_id)==int(enemy.id))
		enemy.spawn = 0.0; arena.enemies.append(enemy)
	state.changed.connect(func(): changed_count += 1)
	await frames(3)
	assert(not is_instance_valid(arena.hud._inventory_panel))
	var grid_cached_before := ResourceLoader.has_cached("res://scripts/ui/unified_bag_grid.gd")
	measure("twenty_normal_root_deaths_bag_closed",kill_roots)
	rows.back()["death_reward_before_flush_us"] = death_us; rows.back()["final_flush_us"] = flush_us
	assert(arena.reward_kills == 20 and arena.kills == 20 and int(state.normal_journey().normal_root_kills) == 20)
	assert(int(rows.back().state_calls.get("normal_root_xp_including_changed",0)) == 20)
	assert(int(rows.back().state_calls.get("equipment_reward_including_changed",0)) == 2)
	assert(int(rows.back().state_calls.get("jewel_reward_including_changed",0)) == 1)
	assert(int(rows.back().arena_calls.get("progress_flush_HUD_save",0)) == 1)
	assert(rows.back().after.successful_saves-rows.back().before.successful_saves == 1)
	await frames()
	measure("first_I_open",press_i); await frames()
	var panel = arena.hud._inventory_panel
	rows.back()["panel_nested_nonadditive_us"] = panel.audit_times.duplicate()
	rows.back()["panel_calls"] = panel.audit_counts.duplicate()
	assert(panel.is_visible_in_tree() and arena.hud.is_blocking())
	first_view = stable({"items":panel._grid._items,"layout":panel._bag_layout,"page":panel._bag_page,"metadata":panel._craft_metadata,"summary":panel._summary.text})
	var paused_before := [arena.elapsed,arena.kills,arena.reward_kills,arena.total_shots,arena._simulation_accumulator]
	measure("paused_main_process_no_simulation",func(): arena._process(1.0/60.0))
	assert(paused_before == [arena.elapsed,arena.kills,arena.reward_kills,arena.total_shots,arena._simulation_accumulator])
	measure("select_legal_magic_item",func(): panel._grid.item_selected.emit(selected_uid)); await frames()
	assert(panel._selected_uid == selected_uid)
	for repeat: int in range(3):
		measure("warm_close_%d" % (repeat+1),press_i); await frames()
		measure("warm_reopen_%d" % (repeat+1),press_i); await frames()
	var controls = panel._craft_controls
	var target_index := -1
	for index: int in range(controls._target_select.item_count):
		if controls._target_select.get_item_metadata(index) == "targeted_reforge_damage": target_index = index
	assert(target_index >= 0)
	measure("select_damage_target",func():
		controls._target_select.select(target_index); controls._target_select.item_selected.emit(target_index))
	assert(not controls._target_button.disabled and panel.is_visible_in_tree())
	measure("request_one_targeted_quote",func():
		controls._target_button.button_down.emit(); controls._target_button.pressed.emit())
	assert(panel._craft_dialog.visible and panel._pending_craft.quote.operation == "targeted_reforge_damage")
	var debit: int = panel._pending_craft.quote.cost.calibration_shard
	var balance_before := state.crafting_balance()
	await frames()
	measure("confirm_one_visible_targeted_craft",func(): panel._craft_dialog.get_ok_button().pressed.emit())
	await frames()
	assert(state.crafting_balance() == balance_before-debit and debit == 16)
	assert(int(rows.back().state_calls.get("execute_crafting_including_commit_changed",0)) == 1)
	assert(int(rows.back().state_calls.get("atomic_write_including_close",0)) == 1)
	assert(int(rows.back().after.crafting_revision)-int(rows.back().before.crafting_revision) == 1)
	assert(Rules.reason(state.snapshot()).is_empty())
	var reloaded := TimedState.new(); assert(reloaded.load_build("user://build_save.json"))
	assert(reloaded.snapshot() == state.snapshot())
	var observation: Dictionary={"state":state.snapshot(),"rng":arena.rng.state,"flasks":arena.flask_runtime.snapshot(),"first_view":first_view,"final_items":stable(panel._grid._items),"selected_uid":panel._selected_uid,"final_metadata":panel._craft_metadata,"disk":FileAccess.get_file_as_bytes("user://build_save.json"),"changed":changed_count,"refresh_generation":panel.refresh_generation}
	FileAccess.open(output+".bin",FileAccess.WRITE).store_buffer(var_to_bytes(observation))
	var report := {"source_revision":OS.get_environment("INVENTORY_PROFILE_SOURCE"),
		"engine":Engine.get_version_info().string, "display_server":DisplayServer.get_name(), "user_data_dir":OS.get_user_data_dir(),
		"grid_cached_before_first_I":grid_cached_before,
		"scope":"One current production-copied main/HUD/panel diagnostic; only timing and dependency redirection added, no UI behavior changes. One starter-size current-schema fixture; synchronous production root/HUD/model CPU callbacks. Inclusive nested timings are nonadditive; no rendered frame, GPU, Windows FPS, threshold or large-inventory claim.",
		"fixture":{"selected_uid":selected_uid,"base_id":"cinder_reed","rarity":"magic","item_level":30,"initial_shards":100,"seed":500037},
		"dropdown_count_method":"Only the real inventory panel invokes crafting_operations during measured phases. Each such call feeds set_operations_context -> _refresh -> _refresh_targeted, which clears/repopulates the real OptionButton. The count is inferred from this source path, not an independently instrumented dropdown.",
		"normal_profile":not arena._is_test_profile(), "paused_process_unchanged":true, "persisted_snapshot_verified":true,
		"targeted_operation":"targeted_reforge_damage", "targeted_debit":debit, "phases":rows}
	var file := FileAccess.open(output,FileAccess.WRITE); assert(file != null)
	file.store_string(JSON.stringify(report,"\t",true,true)); file.close()
	print("INVENTORY_REWARD_PROFILE_COMPLETE ", output)
	arena.queue_free(); await frames(1); quit()
