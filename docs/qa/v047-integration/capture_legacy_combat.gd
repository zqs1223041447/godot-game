extends SceneTree
var arena:Node
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	var results:Array=[]
	for support:String in ["","ignite"]:
		arena.enemies.clear();arena.projectiles.clear();arena.monster_runtime.reset();arena.burn_runtime.reset();arena.burn_trace.clear();arena.damage_trace.clear();arena.combat_trace.clear();arena.event_counts.clear();arena.feedback_runtime.reset();arena.leech_runtime.clear();arena.telegraphs.reset();arena.particles.clear();arena.pickups.clear();arena.floating_text.clear();arena.rings.clear()
		arena.elapsed=0.0;arena.kills=0;arena.total_damage=0.0;arena.spawn_timer=1000.0;arena.auto_fire=false;arena.alive=true;arena.demo_mode=false;arena.rng.seed=123498;arena.critical_runtime.reset(123498);arena._world_mode="normal";arena._geometry.configure("old_garden",arena.ARENA);arena.player_pos=arena.ARENA.get_center();arena.hud.close_panel();arena.health=10000.0;arena.shield=5000.0;arena.mana=10000.0
		for i:int in range(12):
			var e:Dictionary=arena._spawn_monster("brute",arena.player_pos+Vector2(60+i*12,20*(i%3)),"ordinary","",[],false)
			e.spawn=0.0;e.health=75.0+i*15;e.max_health=e.health;e.shield=float(i%2)*25.0;e.armour=20.0;e.speed=0.0;e.attack_timer=1000.0;e.shield_recharge_rate=0.0
		var compiler:Script=load("res://scripts/combat/skill_compiler.gd");var combat:Script=load("res://scripts/combat/combat_data.gd")
		var snapshot:Dictionary=combat.snapshot({"damage":15.0,"crit_base_chance":0.0,"crit_base_multiplier":1.5},[])
		var selected:Array=[] if support.is_empty() else [support]
		for id:String in ["meteor","tornado"]:
			arena.cooldowns[id]=0.0
			assert(arena._execute_compiled(compiler.compile_group(id,snapshot,selected)))
		for i:int in range(120):arena.tick(1.0/60.0)
		results.append({"enemies":arena.enemies.duplicate(true),"shots":arena.projectiles.duplicate(true),"burn":arena.burn_runtime.statuses(),"burn_trace":arena.burn_trace.duplicate(true),"damage_trace":arena.damage_trace.duplicate(true),"combat_trace":arena.combat_trace.duplicate(true),"events":arena.event_counts.duplicate(true),"rng":arena.rng.state,"critical_rng":arena.critical_runtime.checkpoint(),"leech":arena.leech_runtime.snapshot(),"kills":arena.kills,"total_damage":arena.total_damage,"health":arena.health,"shield":arena.shield,"mana":arena.mana,"particles":arena.particles.duplicate(true),"pickups":arena.pickups.duplicate(true),"feedback":arena.damage_feedback()})
	var output:String=OS.get_environment("EMBER_LEGACY_OUTPUT")
	var file:=FileAccess.open(output,FileAccess.WRITE);assert(file!=null);file.store_buffer(var_to_bytes(results));file.close()
	print("EMBER_LEGACY_CAPTURE_COMPLETE scenarios=2 ticks_each=120 bytes=%d"%FileAccess.get_file_as_bytes(output).size())
	arena.queue_free();await process_frame;quit(0)
