extends "res://tests/exploration_main_flow_test.gd"
## Reuse the accepted formal-map fixture and original actual death helper.
var transitions:Array=[]
func post(id:String)->Dictionary:
	for row:Dictionary in arena._outpost_states():
		if row.id==id:return row
	return {}
func kill_with_commit(enemy:Dictionary)->void:
	arena._begin_progress_transaction();kill(enemy);arena._end_progress_transaction()
func outpost_flow()->bool:
	var chosen:Dictionary={}
	for site:Dictionary in arena._camp_landmarks.outposts:
		for id:int in site.root_ids:
			if not actor(id).get("death_spawns",[]).is_empty():chosen=site;break
		if not chosen.is_empty():break
	if not check(not chosen.is_empty(),"Actual seeded map contains a natural splitting outpost root"):return false
	var old_records:Array=arena.map_spawn_records()
	var old_ids:Array=ids()
	var target:Dictionary=actor(int(chosen.root_ids[0]))
	arena._wake_exploration_enemy(target);arena._sync_camp_presentation()
	check(post(chosen.id).state=="active" and post(chosen.id).awake_count==1,"Actual awake root marks only its resident outpost active")
	check(arena.static_environment._camp_signs._states.get(chosen.id)=="active","Existing world presentation receives outpost identities")
	var root_kills:int=arena.reward_kills
	for id:int in chosen.root_ids:kill_with_commit(actor(id))
	var state:Dictionary=post(chosen.id)
	check(state.roots_defeated==chosen.root_count and state.pending_descendants>0 and state.state!="cleared","Defeated root count cannot clear an outpost with original descendants queued")
	var queued:int=state.pending_descendants
	arena._flush_monster_spawns();state=post(chosen.id)
	check(state.pending_descendants==0 and state.living_count==queued and state.state=="active","Admitted descendants stay attributed through original root lineage")
	check(arena.reward_kills==root_kills+chosen.root_count,"Each outpost root earns reward once before descendant cleanup")
	var rounds:=0
	while rounds<5 and post(chosen.id).state!="cleared":
		rounds+=1
		for enemy:Dictionary in arena.enemies.duplicate():
			if chosen.root_ids.has(int(enemy.root_id)) and float(enemy.health)>0.0:kill_with_commit(enemy)
		arena._flush_monster_spawns()
	check(rounds<5 and post(chosen.id).state=="cleared","Only complete original lineage cleanup marks the outpost clear")
	check(arena.reward_kills==root_kills+chosen.root_count and arena.map_spawn_records()==old_records,"Descendants never change root reward count or initial spawn records")
	arena._sync_camp_presentation()
	check(arena.static_environment._camp_signs._states.get(chosen.id)=="cleared","Final outpost state reaches retained sign layer")
	var cleared:=0
	for row:Dictionary in arena._outpost_states():
		if row.state=="cleared":cleared+=1
	check(cleared==1 and not arena._map_run.complete,"One finished outpost leaves the rest resident and the map incomplete")
	transitions.append({"outpost":chosen.id,"initial_root_ids":chosen.root_ids,"before_total":old_ids.size(),"pending_descendants":queued,"final":post(chosen.id)})
	return true
func finish_route()->void:
	var result:Dictionary={"checks":checks,"failures":failures,"failed_labels":labels,"entries":report.entries,"transitions":transitions,"full_run":report.full_run,"method":"Actual formal Main entry for all four maps, natural splitter outpost lifecycle and one original boss-first full-clear/claim helper; controlled lethal receipts, not natural combat footage"}
	FileAccess.open("res://docs/qa/v090-routes/main-result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print("OUTPOST_MAIN ",checks," checks ",failures," failures")
	arena.queue_free();await process_frame;quit(1 if failures else 0)
func run()->void:
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	if not check(arena.save_build(),"Save legitimate fresh formal build"):await finish_route();return
	arena.rng.seed=90090
	for map_id:String in ["broken_ruins","sunwell_terrace","ginkgo_arcade"]:
		if not enter(map_id):await finish_route();return
		var states:Array=arena._outpost_states()
		check(states.size()==6 and arena.world_context().outpost_states==states,"Actual world context has six detached authoritative outpost states")
		var ids_seen:Dictionary={}
		for row:Dictionary in states:
			check(row.state=="resident" and row.roots_spawned==row.root_count and row.roots_defeated==0,"Every outpost starts fully resident")
			ids_seen[row.id]=true
		check(ids_seen.size()==6 and arena.static_environment._camp_signs._states.size()==6,"Six unique outpost flags replace three source bookkeeping flags")
		var copied:Array=arena._outpost_states();copied[0].state="tampered"
		check(arena._outpost_states()==states,"Editing queried outpost state never mutates simulation")
		if map_id=="ginkgo_arcade" and not outpost_flow():await finish_route();return
		if not return_to_town("Return from route entry"):await finish_route();return
		check(arena._outpost_states().is_empty(),"Returning clears outpost presentation")
	# Ginkgo probe earned items normally; the existing old-garden helper assumes
	# zero initial shards only, not an empty character or discarded possessions.
	if not accepted(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision),"Old garden formal draft"):await finish_route();return
	if not accepted(arena.start_map(arena.map_draft().revision),"Old garden formal start"):await finish_route();return
	pause();check(arena.enemies.size()==25 and arena._outpost_states().size()==6,"Old garden retains25 actors across six3/5 outposts")
	if not complete_boss_first():await finish_route();return
	check(arena.world_context().normal_town and arena._outpost_states().is_empty(),"Original full clear returns and cleans all outpost runtime data")
	await finish_route()
