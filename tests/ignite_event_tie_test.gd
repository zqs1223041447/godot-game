extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const Burn=preload("res://scripts/combat/burn_rules.gd")
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func near(a:float,b:float,label:String)->void:check(absf(a-b)<0.00001*maxf(1.0,absf(b)),label)
func clean()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.burn_runtime.reset();arena.burn_trace.clear();arena.damage_trace.clear()
	arena.elapsed=0.0;arena._burn_step_active=false;arena._burn_immunity_until=0.0;arena.alive=true;arena.invulnerable=0.0;arena.damage_delay=0.0;arena.auto_fire=false;arena.spawn_timer=1000.0
	arena._world_mode="normal";arena._geometry.configure("old_garden",arena.ARENA);arena._stats=arena.state.get_stats();arena._stats.max_health=10000.0;arena._stats.max_shield=5000.0;arena._stats.life_regen=0.0;arena._stats.shield_recharge_rate=0.0;arena._stats.shield_regen=0.0;arena._stats.fire_resistance=0.0
	arena.health=10000.0;arena.shield=5000.0;arena.mana=1000.0;arena.player_pos=arena.ARENA.get_center();arena.hud.close_panel()
	for id:String in arena.Data.SKILLS:arena.cooldowns[id]=0.0
func target(id:String="brute",distance:float=100.0,rewards:bool=false)->Dictionary:
	var e:Dictionary=arena._spawn_monster(id,arena.player_pos+Vector2(distance,0),"ordinary","",[],rewards)
	e.spawn=0.0;e.max_health=10000.0;e.health=10000.0;e.max_shield=5000.0;e.shield=5000.0;e.armour=10000.0;e.resistances.fire=0.25;e.speed=0.0;e.attack_timer=1000.0;e.shield_regen=0.0;e.shield_recharge_rate=0.0
	return e
func meteor(critical:bool=false)->Dictionary:
	return Compiler.compile_group("meteor",Combat.snapshot({"damage":100.0,"fire_increased":0.5,"global_increased":0.2,"crit_base_chance":1.0 if critical else 0.0,"crit_base_multiplier":2.0},[]),["ignite"])
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	clean();var enemy:Dictionary=target();var cast:Dictionary=Compiler.compile_group("tornado",Combat.snapshot({"damage":100.0},[]),["ignite"])
	check(arena.burn_runtime.last_time_for("monster",enemy.id)==-1.0,"Empty clock is a read-only sentinel")
	var shots:Array[Dictionary]=[]
	for offset:float in [0.0,0.001]:
		shots.append(arena.projectile_runtime.make_projectile(arena.player_pos+Vector2(20.0+offset,0),Vector2.RIGHT,cast.recipe.parent,cast.packets.parent,cast.snapshot,77,Color.ORANGE))
	arena.projectiles=shots;arena._burn_step_active=true;arena._burn_step_start=0.0;arena.elapsed=0.25
	arena._update_projectiles(0.25);arena._advance_monster_burns(0.25);arena._burn_step_active=false
	var hits:Array=[]
	for event:Dictionary in arena.combat_trace:
		if event.type=="hit":hits.append(event)
	print("Tie hit times: ",hits.map(func(e:Dictionary)->Array:return [e.projectile_id,e.time]))
	check(hits.size()==2,"Both actual near-equal contacts delivered")
	check(hits[0].projectile_id<hits[1].projectile_id and hits[0].time>hits[1].time and is_equal_approx(hits[0].time,hits[1].time),"Historical near-equal time tie uses projectile ID")
	check(arena.burn_statuses().size()==1,"Single target survives tie and receives one status")
	check(arena.damage_trace.size()==2,"Both old primary hits preserve their delivery order")
	near(arena.burn_runtime.last_time_for("monster",enemy.id),0.25,"Final monotonic target clock")
	var states:PackedByteArray=var_to_bytes(arena.burn_runtime.statuses())
	check(not arena.burn_runtime.advance_target("monster",enemy.id,0.24).ok and var_to_bytes(arena.burn_runtime.statuses())==states,"Core still rejects real backwards time atomically")
	print("Ignite event ties: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
