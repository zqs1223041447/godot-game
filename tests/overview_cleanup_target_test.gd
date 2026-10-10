extends "res://tests/exploration_map_overview_test.gd"
## Existing bounded formal encounter/death helpers, with controlled live positions.
var last_target_position:=Vector2.ZERO
func refresh_target(label:String) -> Dictionary:
	var before:=strict_observation()
	arena.hud._tick_cleanup_hint(0.21)
	check(strict_observation()==before,label+": sharing the HUD query is read-only including saved bytes and RNG")
	check(overview.cleanup_hint==arena.exploration_cleanup_hint(),label+": overview uses the existing exact target authority")
	return overview.cleanup_hint
func record_target(name:String,expect_marker:bool) -> void:
	arena.hud._process(4.0);await settle();await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image()
	check(marker_visible(rendered,last_target_position,Color("f5aad5"))==expect_marker,name+": rendered target cross matches state")
	check(rendered.save_png(OS.get_environment("OVERVIEW_OUTPUT").path_join(name+".png"))==OK,"Rendered screenshot "+name)
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-overview-target-"):quit(78);return
	var model:=FaultModel.new();check(model.save_build("user://build_save.json")==OK,"Fresh canonical save")
	arena=load("res://scenes/main.tscn").instantiate();arena.state=model;arena.build_save_path="user://build_save.json"
	root.add_child(arena);pause();await settle();overview=arena.hud._exploration_overview
	arena.rng.seed=90090
	if not formal_entry("ginkgo_arcade"):finish();return
	await key(KEY_TAB)
	var original:=refresh_target("Initial roster")
	check(overview.visible and original.kind=="overview" and original.target.is_empty(),"Full roster shows original sites without exposing a new radar")
	var splitter:Dictionary={};var kept:Array[int]=[]
	for enemy:Dictionary in arena.enemies:
		if int(enemy.id)!=arena._map_run.boss_id and not enemy.get("death_spawns",[]).is_empty():splitter=enemy;break
	if not check(not splitter.is_empty(),"Existing root has real descendants"):finish();return
	kept.append(int(splitter.id))
	for enemy:Dictionary in arena.enemies:
		if int(enemy.id)!=arena._map_run.boss_id and enemy.get("death_spawns",[]).is_empty():kept.append(int(enemy.id))
		if kept.size()==6:break
	if not check(kept.size()==6 and drain_except(kept),"Six original living roots retained"):finish();return
	check(refresh_target("Six roots").kind=="overview","Six remaining actors still have no target marker")
	arena._begin_progress_transaction();kill(actor(kept.pop_back()));arena._end_progress_transaction()
	arena.tick(0.0) # Original loop clears the dead array entry before the screenshot.
	for id:int in kept:actor(id).pos=arena._geometry.legal_point(arena.ARENA.position+Vector2(2900,500),float(actor(id).radius))
	var target:Dictionary=actor(kept[1])
	target.pos=arena._geometry.legal_point(arena.player_pos+Vector2(500,-280),float(target.radius))
	var first:=refresh_target("Five roots")
	check(first.kind=="target" and first.living_count==5 and first.target.id==target.id,"Existing five-actor threshold selects the actual nearest living actor")
	last_target_position=target.pos;await record_target("nearest-target",true)
	var previous_position:Vector2=target.pos
	target.pos=arena._geometry.legal_point(target.pos+Vector2(150,-180),float(target.radius))
	var moved:=refresh_target("Moved target")
	check(moved.target.position==target.pos and moved.target.position!=previous_position,"Moving actor marker follows actor position, not its original outpost")
	last_target_position=target.pos;await record_target("moved-target",true)
	# The view owns detached display data and cannot edit Main's result.
	overview.cleanup_hint.target.position=Vector2(-999,-999)
	check(arena.exploration_cleanup_hint().target.position==target.pos,"Mutating display snapshot cannot alter the actor or query")
	refresh_target("Restore view")
	arena._begin_progress_transaction();kill(target);arena._end_progress_transaction()
	var switched:=refresh_target("Target death")
	check(switched.kind=="target" and switched.target.id!=target.id,"Dead target switches using original living membership")
	if not drain_except([int(splitter.id)]):finish();return
	refresh_target("Last splitter");last_target_position=splitter.pos
	arena._begin_progress_transaction();kill(splitter);arena._end_progress_transaction()
	var waiting:=refresh_target("Queued descendants")
	check(waiting.kind=="waiting" and waiting.target.is_empty() and overview.cleanup_status().contains("待出现"),"Queued-only descendants remove old marker and explain waiting")
	await record_target("waiting-descendants",false)
	arena._flush_monster_spawns()
	var children:=refresh_target("Real descendants")
	check(children.kind=="target" and children.target.root_id==splitter.id and children.target.id!=splitter.id,"Real spawned descendant becomes target with original lineage")
	last_target_position=children.target.position;await record_target("descendant-target",true)
	check(arena.retry_normal_map(arena.world_context().revision).ok,"Original retry succeeds")
	check(not overview.visible and overview.cleanup_hint.kind=="overview" and overview.cleanup_hint.target.is_empty(),"Same-map retry immediately clears cached target before next polling tick")
	pause();await key(KEY_TAB)
	check(overview.visible and overview.cleanup_hint.kind=="overview" and overview.cleanup_hint.target.is_empty(),"Immediate reopen cannot expose preceding run target")
	check(arena.return_to_town(arena.world_context().revision).ok and not overview.visible,"Original return closes target view")
	check(overview.cleanup_hint.kind=="inactive" and overview.cleanup_hint.target.is_empty(),"Town transition clears target snapshot")
	check(model.snapshot().version==59,"No schema change")
	finish()
func finish() -> void:
	var output:={"checks":checks,"failures":failures,"failed_labels":labels,"display":DisplayServer.get_name(),"method":"Fresh canonical formal ginkgo I; original bounded settlements and descendants. Controlled positions; original six/five actor threshold. Exact state/RNG/save comparisons and screenshot pixel assertions; not natural play."}
	FileAccess.open(OS.get_environment("OVERVIEW_OUTPUT").path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(output,"\t")+"\n")
	print("OVERVIEW_CLEANUP_TARGET ",JSON.stringify(output));quit(0 if failures==0 else 1)
