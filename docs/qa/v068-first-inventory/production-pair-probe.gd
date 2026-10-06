extends SceneTree
## Actual production scripts loaded at runtime so startup timing includes the
## complete Main/HUD dependency load. No timed subclass or replacement UI.
var arena: Node
var state: RefCounted
var output := ""
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var changed := 0
var setup: Dictionary = {}
var first_view: Variant
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	if not ok:
		failures.append(label); push_error(label)
		write_report(); quit(1)
	return ok
func stable(value: Variant) -> Variant:
	if value is Resource: return {"resource_class":value.get_class(),"path":value.resource_path}
	if value is Dictionary:
		var result := {}
		for k: Variant in value: result[k] = stable(value[k])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value: result.append(stable(entry))
		return result
	return value
func frames(count: int = 2) -> void:
	for unused in range(count): await process_frame
func press_i() -> void:
	var event := InputEventKey.new(); event.physical_keycode=KEY_I; event.pressed=true
	arena._unhandled_key_input(event)
func mark() -> Dictionary:
	var p: Variant = arena.hud._inventory_panel
	return {"changed":changed,"refresh":p.refresh_generation if is_instance_valid(p) else 0,"saves":state.successful_saves,"shards":state.crafting_balance(),"revision":state.revision(),"items":state.snapshot().items.size()}
func measure(label: String, operation: Callable) -> void:
	var before := mark(); var start := Time.get_ticks_usec(); operation.call()
	var elapsed := Time.get_ticks_usec()-start; var after := mark()
	rows.append({"phase":label,"us":elapsed,"before":before,"after":after})
func write_report() -> void:
	if output.is_empty(): return
	var d := {"source":OS.get_environment("FIRST_I_SOURCE"),"engine":Engine.get_version_info().string,"setup":setup,"phases":rows,"failures":failures,"scope":"One fresh-process actual production Main/HUD panel path; startup load+ready and first-I separately measured, no production timing wrappers; headless CPU only"}
	FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify(d,"\t",true,true))
func run() -> void:
	output=OS.get_environment("FIRST_I_OUTPUT")
	var xdg:=OS.get_environment("XDG_DATA_HOME")
	if output.is_empty() or not xdg.begins_with("/tmp/godot-m1-v068-pair-") or not OS.get_user_data_dir().begins_with(xdg+"/") or FileAccess.file_exists("user://build_save.json"): quit(78); return
	root.size=Vector2i(1280,720)
	var fixture_start:=Time.get_ticks_usec()
	var model_script=load("res://scripts/canonical_game_state.gd")
	var items=load("res://scripts/items/unified_item_catalog.gd")
	state=model_script.new()
	var uid: String="gear_%06d"%int(state.snapshot().next_item_serial)
	if not check(state._admit_reward_item(items.wrap_equipment({"id":uid,"base_id":"cinder_reed","rarity":"magic","item_level":30,"affixes":[{"id":"deepwell","tier":1,"value":5}]})),"Legal selected item admitted"):return
	var candidate: Dictionary=state.snapshot()
	if not check(state._set_bag_currency_balance(candidate,100).ok and state.Rules.reason(candidate).is_empty(),"Fixture actual bag balance valid"):return
	state._accept_memory(candidate)
	if not check(state.save_build("user://build_save.json")==OK,"Fixture persisted before Main"):return
	setup.fixture_prepare_us=Time.get_ticks_usec()-fixture_start
	var start:=Time.get_ticks_usec()
	var main_script=load("res://scripts/main.gd")
	setup.main_script_load_us=Time.get_ticks_usec()-start
	start=Time.get_ticks_usec();arena=main_script.new();arena.state=state;root.add_child(arena)
	setup.main_new_ready_us=Time.get_ticks_usec()-start
	setup.main_load_and_ready_us=setup.main_script_load_us+setup.main_new_ready_us
	setup.engine_elapsed_to_ready_us=Time.get_ticks_usec()
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	if not check(arena.leave_normal_town(arena.world_context().revision).ok,"Enter real ordinary arena"):return
	for unused in range(3):arena.hud.close_panel()
	if not check(not arena.hud.is_blocking(),"Fixture unpaused"):return
	arena.rng.seed=500037;arena.enemies.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.spawn_timer=100000.0
	for index in range(20):
		var enemy: Dictionary=arena.monster_runtime.create_root("crawler",1,arena.player_pos+Vector2(80+index*3,0),"ordinary","normal",[],true)
		if not check(not enemy.is_empty() and enemy.reward_eligible,"Actual reward root admitted"):return
		enemy.spawn=0.0;arena.enemies.append(enemy)
	state.changed.connect(func():changed+=1)
	await frames(3)
	if not check(not is_instance_valid(arena.hud._inventory_panel),"First inventory not constructed yet"):return
	arena._begin_progress_transaction()
	for enemy:Dictionary in arena.enemies:arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+1,Color.WHITE)
	arena._end_progress_transaction();await frames()
	setup.grid_cached_before_first_I=ResourceLoader.has_cached("res://scripts/ui/unified_bag_grid.gd")
	measure("first_I_open",press_i);await frames()
	var panel: Variant=arena.hud._inventory_panel
	if not check(panel.visible and arena.hud.is_blocking() and panel.refresh_generation==1,"First I builds one dirty refresh"):return
	first_view=stable({"items":panel._grid._items,"layout":panel._bag_layout,"page":panel._bag_page,"metadata":panel._craft_metadata,"summary":panel._summary.text})
	var paused_before: Array=[arena.elapsed,arena.kills,arena.reward_kills,arena.total_shots,arena._simulation_accumulator]
	arena._process(1.0/60.0)
	if not check(paused_before==[arena.elapsed,arena.kills,arena.reward_kills,arena.total_shots,arena._simulation_accumulator],"Inventory pauses actual simulation"):return
	measure("select_item",func():panel._grid.item_selected.emit(uid));await frames()
	if not check(panel._selected_uid==uid,"Actual selection stored"):return
	for i in range(3):
		measure("warm_close_%d"%i,press_i);await frames();measure("warm_open_%d"%i,press_i);await frames()
		if not check(rows.back().before.refresh==rows.back().after.refresh,"Warm reopen stays clean"):return
	var controls: Variant=panel._craft_controls;var target_index: int=-1
	for i in range(controls._target_select.item_count):
		if controls._target_select.get_item_metadata(i)=="targeted_reforge_damage":target_index=i
	if not check(target_index>=0,"Real target option exists"):return
	controls._target_select.select(target_index);controls._target_select.item_selected.emit(target_index)
	if not check(not controls._target_button.disabled,"Valid selected recipe enabled"):return
	measure("request_quote",func():controls._target_button.button_down.emit();controls._target_button.pressed.emit());await frames()
	if not check(panel._craft_dialog.visible and panel._pending_craft.quote.operation=="targeted_reforge_damage","Current confirmation present"):return
	var debit:int=panel._pending_craft.quote.cost.calibration_shard
	measure("confirm_visible_craft",func():panel._craft_dialog.get_ok_button().pressed.emit());await frames()
	if not check(debit==16 and rows.back().before.shards-rows.back().after.shards==16 and rows.back().after.saves-rows.back().before.saves==1 and rows.back().after.refresh-rows.back().before.refresh==1,"Craft spends16 once, saves once, refreshes dirty once"):return
	var restored:RefCounted=model_script.new()
	if not check(restored.load_build("user://build_save.json") and restored.snapshot()==state.snapshot(),"Real save reload exact"):return
	var observation:Dictionary={"state":state.snapshot(),"rng":arena.rng.state,"flasks":arena.flask_runtime.snapshot(),"first_view":first_view,"final_items":stable(panel._grid._items),"selected_uid":panel._selected_uid,"metadata":panel._craft_metadata,"disk":FileAccess.get_file_as_bytes("user://build_save.json"),"changed":changed,"refresh":panel.refresh_generation}
	FileAccess.open(output+".bin",FileAccess.WRITE).store_buffer(var_to_bytes(observation))
	write_report();print("FIRST_I_PAIR_OK ",output);arena.queue_free();await frames(1);quit(0)
