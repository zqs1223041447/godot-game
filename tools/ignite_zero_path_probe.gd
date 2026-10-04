extends SceneTree
var arena:Node
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("IGNITE_ZERO_PROBE_OUTPUT")
	if output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	assert(arena.save_build())
	assert(arena.leave_normal_town(arena.world_context().revision).ok)
	arena.rng.seed=282827;arena.restart_run()
	arena.enemies.clear();arena.monster_runtime.reset();arena.monster_runtime.next_id=0
	arena.player_pos=arena.ARENA.get_center()
	for index:int in range(9):arena._spawn_monster(["crawler","skitter","brute"][index%3],arena.player_pos+Vector2(100+index*15,30 if index%2 else -30))
	for enemy:Dictionary in arena.enemies:enemy.spawn=0.0
	var hashes:Array[String]=[]
	var aggregate:=HashingContext.new();aggregate.start(HashingContext.HASH_SHA256)
	for tick:int in range(180):
		if tick in [0,60,120]:arena.cast_group("group_000001")
		if tick in [10,130]:arena.cast_group("group_000002")
		if tick==20:arena.cast_group("group_000003")
		arena.tick(1.0/60.0)
		var snapshot:Dictionary=arena.state.snapshot();snapshot.version=0
		aggregate.update(var_to_bytes([arena.enemies,arena.projectiles,arena.monster_runtime.queue,arena.monster_runtime.roots,arena.rng.state,snapshot,arena.health,arena.mana,arena.shield,arena.combat_trace,arena.damage_trace,arena.incoming_damage_trace,arena.group_cooldowns.snapshot(),arena.flask_runtime.snapshot(),arena.critical_runtime.checkpoint(),arena.leech_runtime.snapshot()]))
	var report:Dictionary={"digest":aggregate.finish().hex_encode(),"ticks":180,"kills":arena.kills,"reward_kills":arena.reward_kills,"enemies":arena.enemies.size(),"projectiles":arena.projectiles.size(),"random_state":arena.rng.state,"ordinary_admissions":arena.ordinary_admissions,"cast_events":arena.combat_trace.size(),"damage_events":arena.damage_trace.size()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));arena.queue_free();await process_frame;quit()
