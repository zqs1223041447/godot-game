extends SceneTree
const Burn=preload("res://scripts/combat/burn_runtime.gd")
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func origin(at:float,duration:float)->Dictionary:return {"ember_generation":0,"ember_expiry":at+duration,"skill_id":"meteor","cast_id":1}
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v050-"):quit(78);return
	var burn:=Burn.new()
	check(burn.monster_ids_at_time(0.0).is_empty(),"No cached finished timestamp for empty runtime")
	check(burn.apply("monster",10,0,1.0,0.3,0.1,origin(0.1,0.3)).ok,"Ten admitted")
	check(burn.apply("monster",2,0,1.0,0.3,0.1).ok,"Two admitted")
	check(burn.apply("player",0,2,1.0,3.0,1.0).ok,"Player has independent later clock")
	var ids:=burn.monster_ids_at_time(0.1);check(ids==[2,10],"Numeric detached monster order, player clock excluded")
	ids.clear();check(burn.monster_ids_at_time(0.1)==[2,10],"Returned IDs cannot alter cache")
	check(burn.monster_ids_at_time(false).is_empty() and burn.monster_ids_at_time(INF).is_empty(),"Invalid time cannot establish proof")
	check(burn.monster_ids_at_time(0.2).is_empty(),"Positive width retains full advancement")
	check(burn.advance_target("monster",2,0.2).ok and burn.monster_ids_at_time(0.2).is_empty(),"One advanced target cannot falsely prove the other clock")
	check(burn.apply("monster",10,0,2.0,0.3,0.2).ok and burn.monster_ids_at_time(0.2)==[2,10],"Replacement uses live state, never stale cached dictionary")
	var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
	arena.enemies.clear();arena.monster_runtime.reset();arena.burn_runtime.reset();arena._world_mode="normal"
	var a:Dictionary=arena.monster_runtime.create_root("brute",6,arena.ARENA.get_center(),"ordinary","",[],true)
	var b:Dictionary=arena.monster_runtime.create_root("brute",6,arena.ARENA.get_center()+Vector2(40,0),"ordinary","",[],true)
	a.spawn=0.0;b.spawn=0.0;arena.enemies.assign([a,b])
	check(arena.burn_runtime.apply("monster",a.id,0,1.0,3.0,0.2,origin(0.2,3.0)).ok,"Live fixture burn")
	check(arena.burn_runtime.apply("monster",b.id,0,1.0,3.0,0.2,origin(0.2,3.0)).ok,"Dead body fixture burn")
	check(arena.burn_runtime.apply("monster",99,0,1.0,3.0,0.2,origin(0.2,3.0)).ok,"Missing body fixture burn")
	b.health=0.0
	var before:Dictionary=arena.burn_runtime.status_for("monster",a.id);var rng:int=arena.rng.state;var state:Dictionary=arena.state.snapshot()
	arena._advance_proliferating_burns(0.2)
	check(arena.burn_runtime.statuses().size()==1 and arena.burn_runtime.status_for("monster",b.id).is_empty() and arena.burn_runtime.status_for("monster",99).is_empty(),"Same-time proof still cleans dead and missing bodies")
	check(var_to_bytes(arena.burn_runtime.status_for("monster",a.id))==var_to_bytes(before),"Live same-time state remains bit exact")
	check(arena.rng.state==rng and arena.state.snapshot()==state and arena.kills==0,"Cleanup creates no hits, kills, rewards or RNG")
	var stronger:Dictionary=before.duplicate(true);stronger.raw_dps=5.0
	arena._ember_deaths.append({"id":99,"origin":a.pos+Vector2(10,0),"at":0.2,"status":stronger})
	arena._advance_proliferating_burns(0.2)
	var received:Dictionary=arena.burn_runtime.status_for("monster",a.id)
	check(arena._ember_deaths.is_empty() and received.raw_dps==5.0 and received.provenance.ember_generation==1,"Same-time path still flushes queued one-hop transfer")
	check(received.provenance.ember_expiry==before.provenance.ember_expiry and a.health==95.0*1.8,"Transfer retains deadline and causes no instant damage")
	check(not arena._ember_advancing and not arena._ember_defer_deaths,"All guards released")
	arena.queue_free();await process_frame
	print("Burn same-time cleanup: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
