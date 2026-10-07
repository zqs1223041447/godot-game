extends SceneTree
const Current=preload("res://scripts/main.gd")
const Previous=preload("res://docs/qa/v089-empty-projectiles/main_before.gd")
const Shock=preload("res://scripts/combat/shock_rules.gd")
const Freeze=preload("res://scripts/combat/frost_lock_rules.gd")
var arena:Node2D
var checks:=0
var failures:=0
var mode:String
var output:String
var report:Dictionary={"cases":[],"flow":[]}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)
	return ok
func accepted(value:Dictionary,label:String)->bool:return check(bool(value.get("ok",false)),label+" "+str(value.get("reason","")))
func capture()->PackedByteArray:
	return var_to_bytes([arena.enemies,arena.projectiles,arena.health,arena.mana,arena.shield,arena.elapsed,arena.rng.state,arena.critical_runtime.checkpoint(),arena._player_evasion_entropy,arena.attack_timer,arena.cooldowns,arena.group_cooldowns.snapshot(),arena.burn_runtime._states,arena.shock_runtime._states,arena.shock_runtime._previous_intervals,arena.shock_runtime._discarded_until,arena.freeze_runtime._states,arena.freeze_runtime._last_settlement_at,arena.chill_runtime._state,arena.monster_runtime.roots,arena.monster_runtime.queue,arena.monster_runtime.trace,arena.monster_runtime.next_id,arena.projectile_runtime.next_projectile_id,arena.projectile_runtime.next_cast_id,arena.projectile_runtime._sequence,arena.event_counts,arena.combat_trace,arena.damage_trace,arena.attack_admission_trace,arena.feedback_runtime._pending,arena.feedback_runtime._visible,arena._map_run.snapshot(),arena.map_spawn_records(),arena.state.snapshot(),arena.state.successful_saves,FileAccess.get_file_as_bytes(arena.build_save_path)])
func digest(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func enter(map_id:String)->bool:
	if arena._world_mode!="town":
		if not accepted(arena.return_to_town(arena.world_context().revision),"return"):return false
	arena.rng.seed=89089
	if not accepted(arena.craft_map(map_id,[],[],arena.map_draft().revision),"craft"):return false
	if not accepted(arena.start_map(arena.map_draft().revision),"start"):return false
	arena.set_process(false);arena.hud.set_process(false)
	for unused:int in range(4):arena.hud.close_panel()
	arena.auto_fire=true;arena.rng.seed=89089;arena.critical_runtime.reset(89089)
	return true
func shoot(direction:Vector2,speed:float)->bool:
	var cast:Dictionary=arena.state.get_skill_cast("bolt")
	if not accepted(cast,"compile existing bolt"):return false
	return check(arena._shoot(arena.player_pos,direction,cast.packets.projectile,Color.WHITE,0,0.0,speed,{"snapshot":cast.snapshot}),"existing Main shoot")
func measure(label:String,map_id:String,active:bool)->bool:
	if not enter(map_id):return false
	if active:
		arena.auto_fire=false
		for unused:int in range(4):
			if not shoot(Vector2.RIGHT,100.0):return false
	var rows:Array=[];var hashes:Array[String]=[]
	for n:int in range(60):
		var began:int=Time.get_ticks_usec();arena.tick(1.0/60.0);var usec:int=Time.get_ticks_usec()-began
		rows.append(usec);hashes.append(digest(capture()))
		if not check(arena.projectiles.size()==(4 if active else 0),label+" expected shot count"):return false
	FileAccess.open(output.path_join(label+".bin"),FileAccess.WRITE).store_buffer(capture())
	report.cases.append({"label":label,"map":map_id,"actors":arena.enemies.size(),"samples_us":rows,"frame_sha256":hashes,"snapshot_sha256":digest(capture())})
	return true
func record(label:String)->void:
	var bytes:PackedByteArray=capture();FileAccess.open(output.path_join(label+".bin"),FileAccess.WRITE).store_buffer(bytes);report.flow.append({"label":label,"sha256":digest(bytes),"actors":arena.enemies.size(),"queue":arena.monster_runtime.queue.size(),"events":arena.event_counts})
func flow()->bool:
	if not enter("ginkgo_arcade"):return false
	arena.auto_fire=false
	var target:Dictionary=arena.enemies[0]
	# Existing actual resident and authoritative runtime policies; controlled
	# placement/resources exercise status and projectile transition consumers.
	target.spawn=0.0;target.speed=0.0;target.attack_timer=100.0
	if not accepted(arena.burn_runtime.apply("monster",int(target.id),0,2.0,3.0,arena.elapsed),"attach controlled burn"):return false
	if not accepted(arena.shock_runtime.apply("monster",int(target.id),0,arena.elapsed,Shock.PLAYER_POLICY),"attach controlled shock"):return false
	if not accepted(arena.freeze_runtime.apply(int(target.id),str(target.rarity),arena.elapsed,Freeze.PLAYER_POLICY),"attach controlled freeze"):return false
	var before_resources:float=float(target.health)+float(target.get("shield",0.0));var before_time:float=arena.elapsed
	arena.tick(0.2)
	check(arena.elapsed==before_time+0.2 and float(target.health)+float(target.get("shield",0.0))<before_resources,"Empty-projectile tick still advances statuses and real burn damage")
	record("empty_status_tick")
	# Preserve the pre-existing pause gate before simulation, rather than adding
	# a new empty-shot notion of pause inside the projectile runtime.
	arena.hud.open_panel("pause");var paused:PackedByteArray=capture();arena._process(0.25)
	check(capture()==paused,"Blocking HUD pause leaves authoritative state unchanged")
	arena.hud.close_panel()
	# Force the original bounded lineage producer to leave deferred children;
	# the next empty projectile update must keep its original flush entry.
	var parent:Dictionary={}
	for enemy:Dictionary in arena.enemies:
		if not enemy.get("death_spawns",[]).is_empty():parent=enemy;break
	if not check(not parent.is_empty(),"Real pregenerated roster contains a splitter parent"):return false
	parent.health=0.0;var death:Dictionary=arena.monster_runtime.process_death(parent)
	if not check(bool(death.processed) and int(death.queued)>0,"Original lineage producer queues bounded children"):return false
	var expected:int=arena.enemies.size()-1+int(death.queued)
	arena._update_projectiles(1.0/60.0)
	check(arena.monster_runtime.queue.is_empty() and arena.enemies.size()==expected,"Empty event settlement still removes corpse and flushes exact descendants")
	record("empty_lineage_flush")
	# A newly fired projectile must see the latest position/radius and ID table.
	target.pos=arena.player_pos+Vector2(100,0);target.radius+=1.0;target.spawn=0.0
	var previous_hits:int=int(arena.event_counts.get("hit",0))+int(arena.event_counts.get("evaded",0))
	if not shoot(Vector2.RIGHT,600.0):return false
	arena.tick(0.2)
	check(int(arena.event_counts.get("hit",0))+int(arena.event_counts.get("evaded",0))>previous_hits,"First carrier after empty batches reaches the changed real target admission")
	record("first_projectile_after_idle")
	return true
func run()->void:
	mode=OS.get_environment("PROBE_MODE");output=OS.get_environment("PROBE_OUT")
	if mode not in ["before","after"] or output.is_empty():quit(78);return
	arena=Previous.new() if mode=="before" else Current.new();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
	if not accepted(arena.enter_town_test(arena.world_context().revision),"test town"):return
	if not measure("empty25","old_garden",false):quit(1);return
	if OS.get_environment("PROBE_CASE")=="empty25_only":
		report.checks=checks;report.failures=failures;report.mode=mode
		FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("EMPTY25_FIXED ",checks," checks ",failures," failures")
		arena.queue_free();await process_frame;quit(1 if failures else 0);return
	if not measure("empty37","ginkgo_arcade",false):quit(1);return
	if not measure("active37","ginkgo_arcade",true):quit(1);return
	if not flow():quit(1);return
	report.checks=checks;report.failures=failures;report.mode=mode
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("EMPTY_MAIN ",checks," checks ",failures," failures")
	arena.queue_free();await process_frame;quit(1 if failures else 0)
