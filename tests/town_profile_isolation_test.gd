extends SceneTree
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func write(path:String,bytes:PackedByteArray)->void:
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_buffer(bytes);f.close()
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false)
	var normal=arena.state
	check(arena.save_build(),"Normal base saved")
	var normal_bytes:=FileAccess.get_file_as_bytes("user://build_save.json")
	var bad_test:="user://town_test_build_save.json";write(bad_test,"{broken".to_utf8_buffer())
	var world:Dictionary=arena.world_context();var next_id:int=arena.monster_runtime.next_id;var rng:int=arena.rng.state
	check(not arena.enter_town_test(world.revision).ok and arena.state==normal and arena.world_context()==world and arena.rng.state==rng and arena.monster_runtime.next_id==next_id,"Corrupt test save cannot replace original model or reset battle")
	check(FileAccess.get_file_as_bytes("user://build_save.json")==normal_bytes and FileAccess.get_file_as_string(bad_test)=="{broken","Rejected test file is never overwritten with a clone")
	DirAccess.remove_absolute(bad_test)
	var source:Dictionary={"id":"gear_%06d"%int(normal.snapshot().next_item_serial),"base_id":"cinder_reed","rarity":"magic","item_level":30,"affixes":[{"id":"deepwell","tier":1,"value":5}]}
	check(normal._admit_reward_item(normal.Items.wrap_equipment(source)) and arena.save_build(),"Actual normal source prepared")
	var pending:Dictionary=normal.crafting_quote("salvage",source.id,"user://build_save.json")
	check(pending.ok,"Normal quote issued before switch")
	check(arena.enter_town_test(arena.world_context().revision).ok,"Explicit first entry succeeds")
	normal_bytes=FileAccess.get_file_as_bytes("user://build_save.json")
	var normal_snapshot:Dictionary=normal.snapshot()
	check(not normal.execute_crafting(pending.handle,pending.source_instance).ok,"Retired profile cancels stale craft authority")
	check(not normal.move_item("swift_blade",{"kind":"equipment","slot_id":"weapon"},normal.revision(),"user://build_save.json").ok and normal.snapshot()==normal_snapshot,"Delayed old panel transfer cannot mutate retired original")
	check(normal.save_build("user://build_save.json")!=OK and FileAccess.get_file_as_bytes("user://build_save.json")==normal_bytes,"Retired profile cannot write via stale save callback")
	var test=arena.state;var test_bytes:=FileAccess.get_file_as_bytes(bad_test)
	check(arena.town_buy("currency:calibration_shard",test.revision()).ok,"Test-only real currency admitted")
	check(FileAccess.get_file_as_bytes("user://build_save.json")==normal_bytes,"Test trade leaves original untouched")
	check(arena.start_map(arena.map_draft().revision).ok,"Map start saves test profile first")
	world=arena.world_context();var memory:Dictionary=arena.state.snapshot();test_bytes=FileAccess.get_file_as_bytes(bad_test)
	write(bad_test,JSON.stringify(memory,"  ").to_utf8_buffer());var changed:=FileAccess.get_file_as_bytes(bad_test)
	check(not arena.return_to_town(world.revision).ok and arena.world_context()==world and arena.state.snapshot()==memory and FileAccess.get_file_as_bytes(bad_test)==changed,"External test-file edit blocks return before clear/reset")
	write(bad_test,test_bytes)
	check(arena.return_to_town(world.revision).ok,"Restored expected bytes allow explicit retry")
	var town_snapshot:Dictionary=arena.state.snapshot();test=arena.state
	write("user://build_save.json","{broken".to_utf8_buffer());world=arena.world_context()
	check(not arena.leave_town_test(world.revision).ok and arena.state==test and arena.world_context()==world and arena.state.snapshot()==town_snapshot,"Invalid original save blocks exit without losing active test profile")
	write("user://build_save.json",normal_bytes)
	check(arena.leave_town_test(world.revision).ok and arena.state.snapshot()==normal_snapshot,"Original restored and test remains separate")
	check(not test.discard_item(source.id,test.revision(),bad_test).ok,"Old test model retired after exit")
	print("Town profile isolation: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
