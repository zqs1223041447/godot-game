extends SceneTree
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
	return ok
func accepted(value:Dictionary,label:String)->bool:return check(bool(value.get("ok",false)),label+": "+str(value.get("reason","")))
func pause()->void:
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	for unused:int in range(4):arena.hud.close_panel()
func save_bytes()->PackedByteArray:return FileAccess.get_file_as_bytes(arena.build_save_path)
func run()->void:
	# Reuse the previously accepted actual Main/UI crafting save. Its ordinary
	# jewel and currency are labeled isolated fixture data, never a user grant.
	var source:String="res://docs/qa/v091-root-ui/main-after-reforge.json"
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	if not check(file!=null,"Isolated formal fixture path writable"):quit(1);return
	file.store_buffer(FileAccess.get_file_as_bytes(source));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	if not check(arena.world_context().normal_town,"Merged Main opens actual formal town"):await finish();return
	var uid:String=""
	for id:String in arena.state.snapshot().items:
		var item:Dictionary=arena.state.item(id)
		if item.kind=="jewel" and item.payload.base=="emberheart" and arena.state.location(id).kind=="bag":uid=id;break
	if not check(not uid.is_empty(),"Accepted actual UI fixture supplies its lawful ordinary bag jewel"):await finish();return
	var balance:int=arena.state.crafting_balance()
	var quote:Dictionary=arena.state.crafting_quote("reforge",uid,arena.build_save_path)
	if not accepted(quote,"Issue ordinary jewel quote before map transition"):await finish();return
	if not accepted(arena.craft_normal_map("ginkgo_arcade",1,[],[],arena.map_draft().revision),"Prepare merged ginkgo route"):await finish();return
	if not accepted(arena.start_map(arena.map_draft().revision),"Open six-outpost map with jewel crafting model"):await finish();return
	pause();check(arena.enemies.size()==37 and arena.world_context().outpost_states.size()==6,"All37 actors and6 outposts survive model integration")
	check(arena.map_spawn_records().size()==37 and arena._camp_landmarks.route_segments.size()==18,"Route records retain complete initial roster and authored paths")
	var before:PackedByteArray=save_bytes()
	var rejected:Dictionary=arena.state.execute_crafting(quote.handle,quote.source_instance)
	check(not rejected.ok and save_bytes()==before and arena.state.crafting_balance()==balance,"Map transition invalidates old quote without charging")
	if not accepted(arena.return_to_town(arena.world_context().revision),"Return to formal crafter"):await finish();return
	pause();quote=arena.state.crafting_quote("reforge",uid,arena.build_save_path)
	if not accepted(quote,"Fresh quote after return"):await finish();return
	var original:Dictionary=arena.state.item(uid).payload.duplicate(true)
	if not accepted(arena.state.execute_crafting(quote.handle,quote.source_instance),"Execute ordinary jewel reforge on merged route source"):await finish();return
	check(arena.state.crafting_balance()==balance-8 and arena.state.item(uid).payload.base==original.base,"Exact cost and same ordinary jewel identity/base")
	if not accepted(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision),"Prepare second route after crafting"):await finish();return
	if not accepted(arena.start_map(arena.map_draft().revision),"Enter with newly derived jewel stats"):await finish();return
	pause();check(arena.enemies.size()==25 and arena.world_context().outpost_states.size()==6,"Second map keeps25 actors and six3/5 outposts")
	check(arena._stats==arena.state.get_stats(),"Actual new map reads the crafted canonical stats")
	check(arena.state.crafting_balance()==balance-8,"TierI map adds no unapproved material cost")
	if not accepted(arena.return_to_town(arena.world_context().revision),"Second return"):await finish();return
	pause();var recycle:Dictionary=arena.state.crafting_quote("salvage",uid,arena.build_save_path)
	if not accepted(recycle,"Quote same selected jewel for recycling"):await finish();return
	if not accepted(arena.state.execute_crafting(recycle.handle,recycle.source_instance),"Recycle through merged canonical transaction"):await finish();return
	check(arena.state.item(uid).is_empty() and arena.state.crafting_balance()==balance-7,"One selected jewel gone and only one shard credited")
	check(arena.world_context().normal_town and arena._outpost_states().is_empty(),"Town contains no stale outpost state")
	await finish()
func finish()->void:
	var result:Dictionary={"checks":checks,"failures":failures,"scope":"Merged Main route entry/return with accepted actual crafting fixture, quote invalidation, reforge-derived stats and single recycle; prior independent suites reused"}
	FileAccess.open("res://docs/qa/v091-integration/main-result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print("ROUTE_JEWEL ",checks," checks ",failures," failures")
	arena.queue_free();await process_frame;quit(1 if failures else 0)
