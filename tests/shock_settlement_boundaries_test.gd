extends SceneTree
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Rules=preload("res://scripts/combat/shock_rules.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
var checks:=0
var failures:=0
var arena:Node
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func adjacent(value:float,direction:int)->float:
	var bytes:=PackedByteArray();bytes.resize(8);bytes.encode_double(0,value);bytes.encode_s64(0,bytes.decode_s64(0)+direction);return bytes.decode_double(0)
func _initialize()->void:call_deferred("run")
func clean()->Dictionary:
	arena.enemies.clear();arena.projectiles.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.shock_runtime.reset();arena.burn_runtime.reset();arena.damage_trace.clear();arena.combat_trace.clear();arena.event_counts.clear();arena._ember_deaths.clear();arena._ember_projectile_clock.clear()
	arena._world_mode="normal";arena._geometry.configure("old_garden",arena.ARENA);arena.auto_fire=false;arena.alive=true;arena.elapsed=0.0;arena._burn_step_active=false;arena.rng.seed=520079
	var enemy:Dictionary=arena._spawn_monster("brute",arena.ARENA.get_center()+Vector2(100,0),"ordinary","",[],false)
	enemy.spawn=0.0;enemy.health=100000.0;enemy.shield=0.0;enemy.armour=0.0;enemy.resistances={};return enemy
func events_for(enemy:Dictionary,times:Array)->Array[Dictionary]:
	var cast:Dictionary=Compiler.compile_group("bolt",Combat.snapshot({"damage":10.0,"crit_base_chance":0.0,"crit_base_multiplier":1.5},[]),["shock"])
	var result:Array[Dictionary]=[]
	for t:float in times:
		result.append({"type":"hit","time":t,"sequence":result.size()+1,"target_id":enemy.id,"payload":cast.packets.projectile.duplicate(true),"snapshot":cast.snapshot.duplicate(true),"color":Color.WHITE,"slow":0.0,"direction":Vector2.RIGHT})
	return result
func observation()->PackedByteArray:
	return var_to_bytes([arena.enemies,arena.combat_trace,arena.damage_trace,arena.event_counts,arena.rng.state,arena.critical_runtime.checkpoint(),arena.leech_runtime.snapshot(),arena.state.snapshot(),arena.state.successful_saves,arena.shock_runtime._states,arena.shock_runtime._previous_intervals,arena.shock_runtime.read_floor()])
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v052-"):quit(78);return
	var raw:Dictionary=Damage.resolve(Damage.packet({"physical":25.0,"lightning":40.0},["hit"],"test"),[],{"lightning":0.5})
	raw=Defense.apply_armour(raw,100.0);var bytes:=var_to_bytes(raw)
	var boosted:Dictionary=Defense.apply_hit_damage_taken(raw,0.15)
	check(var_to_bytes(raw)==bytes,"Shared adapter leaves input untouched")
	for key:String in raw.components:check(boosted.components[key]==float(raw.components[key])*1.15,"Each mitigated component uses exact single multiplier")
	for i:int in raw.details.size():check(boosted.details[i].before_defense==raw.details[i].before_defense and boosted.details[i].resistance==raw.details[i].resistance,"Offensive baseline and resistance stay original")
	check(var_to_bytes(Defense.apply_hit_damage_taken(raw,0.0))==bytes,"Explicit zero adapter preserves exact bytes")
	for value:Variant in [true,false,"0.15",null,NAN,INF,-0.1,1.01]:check(Defense.apply_hit_damage_taken(raw,value).is_empty(),"Invalid increased factor rejected")
	var malformed:Array=[]
	var a:Dictionary=raw.duplicate(true);a.total+=1.0;malformed.append(a)
	a=raw.duplicate(true);a.details[0].final+=1.0;malformed.append(a)
	a=raw.duplicate(true);a.details.append(a.details[0]);malformed.append(a)
	a=raw.duplicate(true);a.details.clear();malformed.append(a)
	a=raw.duplicate(true);a.details[0].before_defense=-1.0;malformed.append(a)
	for bad:Dictionary in malformed:check(Defense.apply_hit_damage_taken(bad,0.15).is_empty(),"Scaling cannot hide malformed original resolved packet")
	var adapter=Defense.new()
	for method:String in ["incoming_hit","incoming_source_hit"]:
		var base:Dictionary=adapter.call(method,{"lightning":10.0},{},3.0,100.0,"player")
		check(var_to_bytes(base)==var_to_bytes(adapter.call(method,{"lightning":10.0},{},3.0,100.0,"player",0.0)),"Old omitted and zero hit path exact")
		for bad:Variant in [true,false,"0",NAN,INF,-0.1]:check(not adapter.call(method,{"lightning":10.0},{},3.0,100.0,"player",bad).ok,"Public adapter rejects malformed status factor")
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.hud.close_panel()
	var enemy:=clean();arena._burn_step_active=true;arena._burn_step_start=1.0;arena.elapsed=1.01
	var events:=events_for(enemy,[0.000002,0.000001,0.000002]);var original:=var_to_bytes(events)
	check(arena._settle_projectile_events(events,0.01),"Legal near-tie batch admitted")
	check(not arena.damage_trace[0].has("shock") and not arena.damage_trace[1].has("shock") and arena.damage_trace[2].has("shock"),"Future first application cannot influence earlier hit, exact-time later hit can")
	check(var_to_bytes(events)==original,"Original event batch remains unchanged")
	enemy=clean();check(arena.shock_runtime.apply("monster",int(enemy.id),0,0.0,Rules.PLAYER_POLICY).ok,"Old interval installed")
	arena._burn_step_active=true;arena._burn_step_start=0.0;arena.elapsed=2.1
	events=events_for(enemy,[adjacent(2.0,1),adjacent(2.0,-1)])
	check(arena._settle_projectile_events(events,2.1),"Expiry-crossing tied batch admitted")
	check(not arena.damage_trace[0].has("shock") and arena.damage_trace[1].has("shock"),"One retained old interval covers prior-ULP hit without filling expiry gap")
	for invalid:Array in [[0.001,0.000999],[0.001,0.0005]]:
		enemy=clean();arena.shock_runtime.apply("monster",int(enemy.id),0,0.0,Rules.PLAYER_POLICY);arena.shock_runtime.prune(1.0)
		arena._burn_step_active=true;arena._burn_step_start=0.999;arena.elapsed=1.01;events=events_for(enemy,invalid);var before:=observation()
		check(not arena._settle_projectile_events(events,0.011),"Whole invalid history/order batch rejected before first hit")
		check(observation()==before,"Rejected complete batch leaves health, traces, RNG, rewards, save and status bytes exact")
	enemy=clean();arena._burn_step_active=true;arena._burn_step_start=0.0;arena.elapsed=4.0
	check(arena._settle_projectile_events(events_for(enemy,[0.0,2.0,4.0]),4.0),"Forward large-delta batch works without arbitrary history support")
	check(arena.damage_trace.size()==3 and arena.shock_runtime.status_at("monster",int(enemy.id),4.0).active,"Large forward batch fully settles and refreshes")
	for start:float in [1.0,1000000.0]:
		enemy=clean();arena._burn_step_active=true;arena._burn_step_start=start;arena.elapsed=start+1.0/60.0
		check(arena._settle_projectile_events(events_for(enemy,[1.0/60.0]),1.0/60.0),"Exact original-delta contact survives cumulative-time subtraction rounding")
	print("Shock settlement boundaries: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
