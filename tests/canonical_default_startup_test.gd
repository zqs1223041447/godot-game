extends SceneTree
const Legacy=preload("res://scripts/build_state.gd")
const Canonical=preload("res://scripts/canonical_game_state.gd")
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var legacy:=Legacy.new()
	var raw:String="\ufeff  "+JSON.stringify(legacy._snapshot(),"\t",true,true)+"\n"
	var path:="user://build_save.json"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(raw.to_utf8_buffer());file.close()
	var arena:Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	check(arena.state is Canonical,"actual default main owns canonical model")
	check(arena.state.migrated_from_legacy and arena.state.last_load_error.is_empty(),"actual startup migrates legacy source")
	check(arena.state.snapshot().version==14 and arena.state.snapshot().skill_groups.size()==10,"actual saved schema and ten groups")
	check(FileAccess.get_file_as_bytes(path+".v13-backup.json")==raw.to_utf8_buffer(),"first startup keeps exact BOM/whitespace original bytes")
	check(arena.state.location("guardian_robe")=={"kind":"equipment","slot_id":"body_armour"} and arena.state.location("azure_charm")=={"kind":"equipment","slot_id":"amulet"},"old equipped identity preserved at new targets")
	for panel:String in ["inventory","skills","talents","combat","monsters","pause","settings"]:
		arena.hud.open_panel(panel)
		await process_frame
		check(arena.hud.is_blocking(),"default independent root blocks simulation: "+panel)
		arena.hud.close_panel()
	var before_count:int=arena.state.snapshot().items.size()
	var rng:=RandomNumberGenerator.new();rng.seed=917
	var jewel:String=arena.state.award_jewel(rng)
	var special:String=arena.state.award_special_jewel()
	check(not jewel.is_empty() and not special.is_empty() and arena.state.snapshot().items.size()==before_count+2,"actual main model receives both jewel reward types")
	check(arena.state.jewels[jewel].id==jewel and arena.state.location(jewel).kind=="bag","single owner and detached legacy read projection")
	arena.equip_tornado_example()
	check(arena.state.skill_slots[0]=="tornado" and arena.state.equipped.weapon=="prism_bow","F6 existing example uses owned gem and gear")
	check(arena.state.get_combat_snapshot().effects.has("return_on_range") and arena.state.get_combat_snapshot().effects.has("explode_on_flight_end"),"old return/explosion example preserved")
	check(arena.save_build(),"default migrated game persists authoritative changes")
	var snapshot:Dictionary=arena.state.snapshot()
	arena.queue_free();await process_frame
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false)
	check(not arena.state.migrated_from_legacy and arena.state.snapshot()==snapshot,"second actual startup loads once-migrated state exactly")
	arena.queue_free();await process_frame
	var future:="{\"version\":15,\"untouched\":true}"
	file=FileAccess.open(path,FileAccess.WRITE);file.store_string(future);file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false)
	check(not arena.state.last_load_error.is_empty() and not arena.save_build(),"actual future-version startup stays write protected")
	check(FileAccess.get_file_as_string(path)==future,"future bytes not overwritten by new main")
	arena.queue_free();await process_frame
	print("Canonical default startup: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
