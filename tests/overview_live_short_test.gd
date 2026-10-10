extends "res://tests/exploration_map_overview_test.gd"
## Short normal-processing probe, not a long-run performance benchmark.
var samples:Array=[]
var aim_evidence:Dictionary={}
var query_ms:Array=[]
func percentile(values:Array,fraction:float) -> float:
	var sorted:=values.duplicate();sorted.sort();return float(sorted[mini(sorted.size()-1,int(floor(sorted.size()*fraction)))])
func sample_window(label:String,opened:bool) -> void:
	if overview.visible!=opened:await key(KEY_TAB)
	check(overview.visible==opened and arena.is_processing() and arena.hud.is_processing() and not arena.hud.is_blocking(),label+": normal Main/HUD processing enabled")
	var frame_ms:Array=[];var process_ms:Array=[];var before:float=arena.elapsed
	for index:int in range(16):
		var start:=Time.get_ticks_usec();await process_frame
		frame_ms.append((Time.get_ticks_usec()-start)/1000.0)
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
	samples.append({"label":label,"open":opened,"frames":16,"frame_ms":frame_ms,"process_ms":process_ms,"frame_p50_ms":percentile(frame_ms,0.5),"frame_p95_ms":percentile(frame_ms,0.95),"process_p50_ms":percentile(process_ms,0.5),"process_p95_ms":percentile(process_ms,0.95),"actors":arena.enemies.size(),"sim_seconds":arena.elapsed-before})
	check(arena.elapsed>before and arena.alive,label+": real simulation advances while dense actors remain alive")
func mouse(down:bool) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(770,330);Input.parse_input_event(motion)
	var event:=InputEventMouseButton.new();event.position=motion.position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event)
func native_settle() -> void:
	for index:int in range(16):
		if not arena.map_preparation_pending() and not arena.hud._restart_pending:await process_frame;return
		await physics_frame
	check(false,"Native action settles in sixteen physics frames")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-overview-live-"):quit(78);return
	var model:=FaultModel.new();check(model.save_build("user://build_save.json")==OK,"Fresh canonical save")
	arena=load("res://scenes/main.tscn").instantiate();arena.state=model;arena.build_save_path="user://build_save.json"
	root.add_child(arena);pause();await settle();overview=arena.hud._exploration_overview
	if not formal_entry("ginkgo_arcade"):finish();return
	# Controlled runtime durability/placement keeps exactly the original37 actors
	# fighting during both A/B windows; no extra actors, canonical stats or saves.
	var original_max:float=arena._stats.max_health
	arena._stats.max_health=1000000.0;arena.health=1000000.0;arena.shield=0.0;arena.invulnerable=0.0
	for index:int in range(arena.enemies.size()):
		var enemy:Dictionary=arena.enemies[index]
		enemy.pos=arena._geometry.legal_point(arena.player_pos+Vector2.RIGHT.rotated(index*TAU/37.0)*(80+index%3*25),float(enemy.radius))
		enemy.health=1000000.0;enemy.max_health=1000000.0;enemy.spawn=0.0
	arena.auto_fire=true;arena.set_process(true);arena.hud.set_process(true)
	for index:int in range(8):await process_frame
	for index:int in range(12):
		var start:=Time.get_ticks_usec();arena.world_context();query_ms.append((Time.get_ticks_usec()-start)/1000.0)
	await sample_window("closed-A1",false)
	await sample_window("open-B1",true)
	await sample_window("open-B2",true)
	await sample_window("closed-A2",false)
	check(arena.enemies.size()==37 and not arena.incoming_damage_trace.is_empty(),"All37 actual actors persist and normal processing settles real incoming hits")
	await key(KEY_TAB);check(overview.visible,"Overview open for actual mouse aim")
	var before_projectile:int=arena.projectile_runtime.next_projectile_id
	arena.auto_fire=false;arena.attack_timer=0.0;mouse(true)
	for index:int in range(4):await process_frame
	var expected:Vector2=(arena.get_global_mouse_position()-arena.player_pos).normalized()
	aim_evidence={"held":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"dot":arena.player_facing.dot(expected),"next_id_before":before_projectile,"next_id_after":arena.projectile_runtime.next_projectile_id,"remaining_projectiles":arena.projectiles.size()}
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and arena.player_facing.dot(expected)>0.99 and arena.projectile_runtime.next_projectile_id>before_projectile,"Mouse held inside overview reaches original aim and projectile firing")
	mouse(false)
	# Let an original living melee actor kill through the normal frame loop.
	arena._stats.max_health=original_max;arena.health=1.0;arena.shield=0.0;arena.invulnerable=0.0
	for enemy:Dictionary in arena.enemies:
		if enemy.template_id=="crawler":enemy.pos=arena.player_pos+Vector2(8,0);break
	for index:int in range(60):
		if not arena.alive:break
		await process_frame
	check(not arena.alive and arena.health<=0.0 and not overview.visible and arena.hud._menu_routes.snapshot().death_latched,"Real enemy hit death closes overview through normal processing and opens original death panel")
	check(not arena.incoming_damage_trace.is_empty() and arena.incoming_damage_trace.back().remaining_health<=0.0,"Death has an actual incoming settlement record")
	check(arena.return_to_town(arena.world_context().revision).ok,"Return through original post-death transition")
	check(arena.craft_normal_map("ruins_garden",1,[],[],arena.map_draft().revision).ok,"Original native map draft")
	var entered:Dictionary=await arena.open_map(arena.map_draft().revision)
	if not check(entered.ok,"Actual native map prepared and entered"):finish();return
	arena.auto_fire=false;arena.set_process(true);arena.hud.set_process(true)
	for index:int in range(4):arena.hud.close_panel()
	await key(KEY_TAB);check(overview.visible,"Native overview opens during normal processing")
	arena.hud.open_panel("pause")
	var old_geometry:RefCounted=arena._geometry;var old_run:int=arena.run_revision
	var before:=var_to_bytes([model.snapshot(),FileAccess.get_file_as_bytes("user://build_save.json")])
	arena.hud._root.find_child("RestartButton",true,false).pressed.emit()
	check(arena.map_preparation_pending() and not overview.visible,"Real native retry button starts bounded preparation and closes overview")
	arena.hud.handle_menu_key(KEY_ESCAPE)
	await native_settle()
	check(arena.run_revision==old_run and arena._geometry==old_geometry and old_geometry.physics_ready() and var_to_bytes([model.snapshot(),FileAccess.get_file_as_bytes("user://build_save.json")])==before,"Cancelling pending native retry retains original geometry, run and exact saved character")
	check(arena.is_processing() and arena.hud.is_processing(),"Cancelled preparation restores normal processing")
	await key(KEY_TAB);check(overview.visible and overview.geometry==arena.world_geometry(),"Cancelled retry can reopen the still-current native overview")
	arena.hud.open_panel("pause");arena.hud._root.find_child("RestartButton",true,false).pressed.emit();await native_settle()
	check(arena.run_revision==old_run+1 and arena._geometry!=old_geometry and arena._geometry.physics_ready() and not overview.visible,"Successful native retry installs prepared geometry and discards old overview")
	await key(KEY_TAB)
	check(overview.visible and overview.geometry==arena.world_geometry() and overview.cleanup_hint.target.is_empty() and arena.is_processing(),"New native run opens current geometry without stale target while running")
	finish()
func finish() -> void:
	var output:={"checks":checks,"failures":failures,"failed_labels":labels,"display":DisplayServer.get_name(),"samples":samples,"aim":aim_evidence,"world_context_ms":query_ms,"method":"Normal Main/HUD processing for four16-frame dense A/B windows. Original37 map actors repositioned with runtime-only high durability. Actual mouse firing and enemy-hit death. Original native HUD retry/cancel. Bounded llvmpipe probe, not long-run gameplay or statistical performance assurance."}
	FileAccess.open(OS.get_environment("OVERVIEW_OUTPUT").path_join("live-report.json"),FileAccess.WRITE).store_string(JSON.stringify(output,"\t")+"\n")
	print("OVERVIEW_LIVE ",JSON.stringify({"checks":checks,"failures":failures,"failed_labels":labels}));quit(0 if failures==0 else 1)
