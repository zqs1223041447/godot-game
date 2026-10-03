extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.demo_mode=false;arena.enemies.clear();arena.health=10.0;arena.mana=0.0
	while arena.hud.is_blocking():arena.hud.close_panel()
	check(arena.use_flask("flask_1").ok and arena.use_flask("flask_2").ok,"Both equipped bottles begin belowfull")
	var charges:Dictionary=arena.flask_runtime.snapshot().charges_by_uid
	var parent:Dictionary=arena._spawn_monster("splitter",arena.player_pos+Vector2(80,0));parent.spawn=0.0
	arena._begin_progress_transaction();arena._damage_enemy(parent,parent.health+parent.shield+1.0,Color.WHITE);arena._end_progress_transaction()
	check(arena.reward_kills==1 and arena.monster_runtime.queue.size()>0,"True splitter root generates actual pending descendants")
	var after_root:Dictionary=arena.flask_runtime.snapshot()
	for uid:String in charges:check(after_root.charges_by_uid[uid]==int(charges[uid])+1,"Root grants exactlyone to equipped bottle")
	arena._flush_monster_spawns();check(arena.enemies.size()==3,"Actual death queue emits two crawlers andone skitter")
	var snapshot:Dictionary=arena.state.snapshot();var saves:int=arena.state.successful_saves
	for child:Dictionary in arena.enemies.duplicate():
		check(not child.reward_eligible and child.root_id==parent.id and child.generation==1,"Actual descendant has inherited zero-reward lineage")
		child.spawn=0.0
		arena._begin_progress_transaction();arena._damage_enemy(child,child.health+child.shield+1.0,Color.WHITE);arena._end_progress_transaction()
	check(arena.reward_kills==1 and arena.flask_runtime.snapshot()==after_root,"Real descendants cannot add any charge")
	check(arena.state.snapshot()==snapshot and arena.state.successful_saves==saves,"Descendants create no item/XP/save transaction")
	arena.enemies.clear();arena.reward_kills=119
	var enemy:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(100,0));enemy.spawn=0.0
	var before:Dictionary=arena.state.snapshot()
	arena._begin_progress_transaction();arena._damage_enemy(enemy,enemy.health+1.0,Color.WHITE);arena._end_progress_transaction()
	var new_flasks:Array=[]
	for uid:String in arena.state.snapshot().items:
		if not before.items.has(uid) and arena.state.item(uid).kind=="flask":new_flasks.append(arena.state.item(uid))
	check(new_flasks.size()==1 and new_flasks[0].definition_id=="flask:mana","Actual120throot grants alternating mana bottle")
	test_capacity()
	print("Flask reward boundaries: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
func test_capacity()->void:
	var full:=Model.new();var count:=0
	while count<300:
		if full.award_gem("skill:bolt").is_empty():break
		count+=1
	check(count>0 and count<300,"Fill actual finite240bagcells")
	var before:=full.snapshot();var bytes:=var_to_bytes(before)
	check(full.award_flask("flask:life").is_empty() and var_to_bytes(full.snapshot())==bytes,"Fullbag reward rejection preserves UID allocator/revision/allitems")
	var cells:Dictionary={}
	for uid:String in before.items:
		if before.items[uid].kind!="skill_gem" or before.locations[uid].kind!="bag":continue
		var p:Dictionary=before.locations[uid];cells["%d:%d:%d"%[p.page,p.x,p.y]]=uid
	for vertical:bool in [false,true]:
		var selected:Array[String]=[]
		for key:String in cells:
			var parts:=key.split(":");var page:=int(parts[0]);var x:=int(parts[1]);var y:=int(parts[2])
			var other:="%d:%d:%d"%[page,x+(0 if vertical else 1),y+(1 if vertical else 0)]
			if cells.has(other):selected.assign([cells[key],cells[other]]);break
		check(selected.size()==2,"Find real two-gem adjacent cells")
		var candidate:=Model.new();candidate._accept_memory(before);var path:="user://capacity-%s.json"%str(vertical)
		check(candidate.save_build(path)==OK,"Save isolated fullbag fixture")
		for uid:String in selected:check(candidate.discard_item(uid,candidate.revision(),path).ok,"Free exacttestcell through real discard transaction")
		var free_before:=candidate.snapshot();var flask:String=candidate.award_flask("flask:life")
		check((not flask.is_empty())==vertical,"1x2 flask needs vertical space rather than merely two cells")
		if not vertical:check(candidate.snapshot()==free_before,"Fragmented capacity failure is fully atomic")
		else:check(candidate.item_definition(flask).size==Vector2i(1,2) and candidate.location(flask).kind=="bag","Accepted flask consumes actual1x2 footprint")
