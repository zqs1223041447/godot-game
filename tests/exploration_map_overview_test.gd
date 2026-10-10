extends "res://tests/exploration_cleanup_hint_test.gd"
## Actual formal Main entries; finite controlled deaths use existing settlement.
## No art extraction, imports, natural-play claim, currency grant or new save fields.
var overview: Control
func settle() -> void: await process_frame; await process_frame
func key(code: int, echo_value: bool = false) -> void:
	for down: bool in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode=code; event.keycode=code; event.pressed=down; event.echo=echo_value
		Input.parse_input_event(event)
	await settle()
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	# Advance only existing HUD presentation so startup toasts expire and labels refresh.
	arena.hud._process(4.0)
	await settle(); await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image()
	check(marker_visible(rendered,overview.player_position,Color("8bdeed")),name+": actual rendered player marker visible")
	check(marker_visible(rendered,overview.geometry.landmarks.boss.center,Color("86c4a0") if overview.context.boss_phase=="defeated" else Color("f68b70")),name+": actual rendered boss marker visible")
	check(rendered.save_png(OS.get_environment("OVERVIEW_OUTPUT").path_join(name+".png"))==OK,"Rendered screenshot "+name)
func marker_visible(rendered:Image,world_point:Vector2,color:Color) -> bool:
	var point:Vector2=overview.get_global_transform_with_canvas()*overview.project(world_point)
	for y:int in range(maxi(0,int(point.y)-11),mini(rendered.get_height(),int(point.y)+12)):
		for x:int in range(maxi(0,int(point.x)-11),mini(rendered.get_width(),int(point.x)+12)):
			var pixel:=rendered.get_pixel(x,y)
			if absf(pixel.r-color.r)+absf(pixel.g-color.g)+absf(pixel.b-color.b)<0.025:return true
	return false
func view_state(id: String) -> Dictionary:
	for state: Dictionary in overview.context.outpost_states:
		if state.id == id:return state
	return {}
func readonly_probe(label: String) -> void:
	var before := strict_observation()
	for index: int in range(5): arena.hud._tick_overview(0.21)
	check(strict_observation()==before,label+": HUD refresh preserves all observed simulation state, RNG and exact saved bytes")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-map-overview-"):quit(78);return
	var model := FaultModel.new()
	check(model.save_build("user://build_save.json")==OK,"Fresh canonical schema59 save")
	arena=load("res://scenes/main.tscn").instantiate();arena.state=model;arena.build_save_path="user://build_save.json"
	root.add_child(arena);pause();await settle();overview=arena.hud._exploration_overview
	await key(KEY_TAB);check(not overview.visible,"Town Tab cannot open map")
	var maps:Array=["old_garden"] if OS.get_environment("OVERVIEW_SMOKE")=="1" else ["old_garden","broken_ruins","sunwell_terrace","ginkgo_arcade","ruins_garden"]
	for map_id: String in maps:
		check(arena.craft_normal_map(map_id,1,[],[],arena.map_draft().revision).ok,"Existing free tierI draft "+map_id)
		var entry: Dictionary=await arena.open_map(arena.map_draft().revision)
		check(entry.ok,"Existing actual formal entry "+map_id+": "+str(entry.get("reason","")))
		if not entry.ok:finish();return
		pause();await settle()
		var before := strict_observation()
		await key(KEY_TAB)
		check(overview.visible and not arena.hud.is_blocking(),map_id+": physical Tab opens without pause")
		check(strict_observation()==before,map_id+": opening is read-only")
		check(overview.geometry==arena.world_geometry() and overview.context.outpost_states==arena.world_context().outpost_states,map_id+": exact live geometry and authoritative outpost state")
		check(overview.geometry.landmarks.outposts.size()==6 and overview.player_position==arena.player_pos,map_id+": six original landmarks and current player")
		check(overview.project(overview.geometry.bounds.position).is_equal_approx(overview.map_rect().position) and overview.project(overview.geometry.bounds.end).is_equal_approx(overview.map_rect().end),map_id+": nonzero-origin world projects inside fitted map bounds")
		if map_id=="ruins_garden":
			var vertices:=0
			for polygon:PackedVector2Array in overview.geometry.module_polygons:vertices+=polygon.size()
			check(overview.geometry.walls.is_empty() and overview.geometry.module_polygons.size()==4 and vertices==99,"Native map keeps all four real polygons /99 vertices without rectangle substitutes")
		readonly_probe(map_id)
		await capture(map_id)
		if map_id=="broken_ruins":await boundaries_and_clear()
		check(arena.return_to_town(arena.world_context().revision).ok,"Existing return "+map_id)
		check(not overview.visible,"Leaving map immediately closes previous geometry")
		await key(KEY_TAB);check(not overview.visible,"No old map reopened from town")
		if arena.world_context().can_claim_normal_rewards:check(arena.claim_normal_rewards(arena.world_context().revision).ok,"Existing pending reward claim before next entry")
	check(model.snapshot().version==59,"Schema unchanged")
	finish()
func boundaries_and_clear() -> void:
	await key(KEY_TAB);check(not overview.visible,"Second Tab closes overview")
	await key(KEY_TAB)
	var mana_before:float=arena.mana
	await key(KEY_1)
	check(overview.visible and arena.mana<mana_before and not arena.projectiles.is_empty(),"Physical skill key casts through the open overview")
	await key(KEY_TAB,true);check(overview.visible,"Key echo cannot double toggle")
	await key(KEY_ESCAPE);check(not overview.visible and not arena.hud.is_blocking(),"Escape closes overview before pause menu")
	await key(KEY_TAB);await key(KEY_K)
	check(not overview.visible and arena.hud.is_blocking(),"K closes overview and opens original skill panel")
	await key(KEY_TAB);check(not overview.visible,"Tab in menu retains UI focus behavior")
	arena.hud.close_panel();await key(KEY_TAB)
	var before_pos:Vector2=arena.player_pos;var elapsed:float=arena.elapsed
	Input.action_press("move_right");arena.tick(1.0/60.0);Input.action_release("move_right")
	arena.hud._tick_overview(0.21)
	check(arena.player_pos.x>before_pos.x and arena.elapsed>elapsed and overview.player_position==arena.player_pos,"Actual movement and simulation time continue while overview follows player")
	arena.alive=false;arena.hud._tick_overview(0.01)
	check(not overview.visible,"Death closes overview")
	await key(KEY_TAB);check(not overview.visible,"Dead character cannot reopen overview")
	arena.alive=true;await key(KEY_TAB)
	arena.hud._world_action();arena.hud._tick_overview(0.01)
	check(not overview.visible and arena.hud._return_dialog.visible,"Return confirmation closes overview")
	arena.hud._return_dialog.hide();await key(KEY_TAB)
	var splitter:Dictionary={};var home:Dictionary={}
	for outpost:Dictionary in arena._camp_landmarks.outposts:
		for id:int in outpost.root_ids:
			if not actor(id).get("death_spawns",[]).is_empty():splitter=actor(id);home=outpost;break
		if not splitter.is_empty():break
	if check(not splitter.is_empty(),"Existing generated root supplies descendant test"):
		# Kill only this outpost through original settlement; other sites remain.
		arena._begin_progress_transaction()
		for enemy:Dictionary in arena.enemies.duplicate():
			if int(enemy.root_id) in home.root_ids:kill(enemy)
		arena._end_progress_transaction();arena.hud._tick_overview(0.21)
		var pending:Dictionary=view_state(home.id)
		check(pending.pending_descendants>0 and pending.state!="cleared","Queued descendants keep original outpost uncleared on map")
		for round_index:int in range(5):
			arena._flush_monster_spawns();arena._begin_progress_transaction()
			for enemy:Dictionary in arena.enemies.duplicate():
				if int(enemy.root_id) in home.root_ids:kill(enemy)
			arena._end_progress_transaction()
			if arena.monster_runtime.queue.is_empty():break
		arena.hud._tick_overview(0.21)
		check(view_state(home.id).state=="cleared","Actual finite descendant deaths turn original outpost green")
		check(overview.context.outpost_states==arena.world_context().outpost_states,"Map never maintains separate clearance authority")
		await capture("cleared-outpost")
	var prior_scale:float=arena.hud._preferences.ui_scale
	arena.hud._preferences.ui_scale=1.1;arena.hud._apply_presentation();arena.hud._tick_overview(0.21)
	check(Rect2(Vector2.ZERO,arena.hud._root.size).encloses(overview.get_rect()),"Overview layout respects existing UI scale")
	arena.hud._preferences.ui_scale=prior_scale;arena.hud._apply_presentation()
	var previous_run:int=arena.run_revision
	check(arena.retry_normal_map(arena.world_context().revision).ok,"Original retry transaction")
	arena.hud._tick_overview(0.21)
	check(not overview.visible and arena.run_revision>previous_run,"Retry closes the old run's overview")
	pause();await key(KEY_TAB)
	check(overview.visible and overview.context.outpost_states.all(func(state:Dictionary)->bool:return state.state=="resident"),"Reopening shows fresh run without old cleared markers")
	check(drain_except([]),"Bounded original full clear for completed-map presentation")
	arena._check_map_complete()
	arena.hud._tick_overview(0.21)
	check(arena.world_context().mode=="map_complete" and overview.visible and overview.context.boss_phase=="defeated" and overview.context.outpost_states.all(func(state:Dictionary)->bool:return state.state=="cleared"),"Completed map retains current overview with authoritative cleared markers")
	await capture("map-complete")
func finish() -> void:
	var output:={"checks":checks,"failures":failures,"failed_labels":labels,"display":DisplayServer.get_name(),"method":"Fresh schema59, five real free formal entries including native geometry. Physical keys; explicit movement tick. Controlled deaths through original settlement, not natural combat footage."}
	FileAccess.open(OS.get_environment("OVERVIEW_OUTPUT").path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(output,"\t")+"\n")
	print("EXPLORATION_OVERVIEW ",JSON.stringify(output));quit(0 if failures==0 else 1)
