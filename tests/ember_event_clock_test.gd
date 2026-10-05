extends SceneTree
const Clock=preload("res://scripts/combat/ember_event_clock.gd")
const Runtime=preload("res://scripts/combat/projectile_runtime.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v050-"):quit(78);return
	var times:Array=[0.008498710574771513,0.008495442978210952,0.008485886630782776]
	var events:Array=[]
	for t:float in times:events.append({"time":t})
	var bytes:=var_to_bytes(events)
	check(is_equal_approx(times[0],times[1]) and is_equal_approx(times[1],times[2]) and not is_equal_approx(times[0],times[2]),"Real non-transitive adjacent tie chain")
	var plan:=Clock.offsets(events)
	check(plan.ok and plan.offsets==[times[0],times[0],times[0]],"Tie chain has one nondecreasing burn clock")
	check(var_to_bytes(events)==bytes,"Raw event offsets remain exact")
	for invalid:Variant in [null,{},[{}],[{"time":true}],[{"time":NAN}],[{"time":INF}],[{"time":-0.001}],[{"time":0.01},{"time":0.009}]]:
		var rejected:=Clock.offsets(invalid)
		check(not rejected.ok and rejected.offsets.is_empty(),"Malformed or genuine reverse offset fails without partial plan")
	check(Clock.offsets([{"time":0.0}]).offsets==[0.0],"New batch resets prior tie chain")
	check(Clock.offsets([{"time":0.00001},{"time":0.2}]).offsets==[0.00001,0.2],"Strict forward events preserve original offsets")
	var fixture:Dictionary=bytes_to_var(FileAccess.get_file_as_bytes("res://docs/qa/v050-density/minimal-clock.bin"))
	for clock_start:float in [0.0,1000000.0]:
		var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
		arena._world_mode="normal";arena.auto_fire=false;arena._geometry.configure("old_garden",arena.ARENA)
		arena.enemies.assign(fixture.actors.duplicate(true));arena.player_pos=fixture.player_pos
		arena.projectiles.assign(fixture.shots.duplicate(true));arena.projectile_runtime=Runtime.new();arena.burn_runtime.reset();arena.critical_runtime.reset(508)
		var cast:Dictionary=Compiler.compile_group("tornado",arena.state.get_combat_snapshot(),["ember_proliferation"])
		check(cast.ok,"Actual current starter build compiles ember tornado")
		var critical:Dictionary=arena.critical_runtime.freeze(cast.snapshot)
		check(critical.ok,"Real shared cast critical snapshot")
		for shot:Dictionary in arena.projectiles:shot.payload=cast.packets.parent.duplicate(true);shot.snapshot=critical.snapshot.duplicate(true)
		var raw:Array[Dictionary]=[];raw.assign(arena.projectiles.duplicate(true))
		var expected:=Runtime.new().advance(raw,fixture.step,arena.enemies,arena.player_pos,arena.MAX_PROJECTILES,func(_shot:Dictionary,_id:int)->bool:return true)
		check(expected.size()==4,"Minimized legal runtime emits exactly four hit events")
		plan=Clock.offsets(expected)
		check(plan.ok,"Actual runtime output accepts only its adjacent raw-offset chain")
		arena.elapsed=clock_start+float(fixture.step);arena._burn_step_start=clock_start;arena._burn_step_active=true
		arena.rng.seed=50123
		arena._update_projectiles(fixture.step)
		check(arena._ember_projectile_clock.is_empty(),"Clock cleared at original batch end")
		check(arena.event_counts.get("hit",0)==4 and arena.burn_runtime.statuses().size()==3,"Actual main dispatches four contacts and attaches three real burns")
		check(arena.kills==0,"Legal current-build hits leave these real catalog actors alive")
		check(arena.combat_trace.size()==expected.size(),"Original event count remains")
		for i:int in range(expected.size()):
			var brief:Dictionary=expected[i].duplicate(true);brief.erase("snapshot");brief.erase("payload")
			check(var_to_bytes(brief)==var_to_bytes(arena.combat_trace[i]),"Raw event ordering and payload-independent trace exact")
		for status:Dictionary in arena.burn_runtime.statuses():
			print("CLOCK_VALUE ",clock_start," actual=%.20f expected=%.20f"%[float(status.last_time),clock_start+times[0]])
			check(float(status.last_time)==clock_start+float(plan.offsets.back()),"Every burn uses relative chain clock even at long uptime")
		check(not arena._ember_advancing,"Global advancement guard is released")
		arena.queue_free();await process_frame
	print("Ember event clock: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
