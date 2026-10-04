extends SceneTree
# Read-only production audit: isolated runtime instances, no production writes.
class CountGeometry extends "res://scripts/world/map_geometry.gd":
	var count:Dictionary={}
	var usec:Dictionary={}
	func mark(k:String,t:int)->void:count[k]=int(count.get(k,0))+1;usec[k]=int(usec.get(k,0))+Time.get_ticks_usec()-t
	func visible(a:Vector2,b:Vector2,r:float=0.0)->bool:
		var t:=Time.get_ticks_usec();var v:=super.visible(a,b,r);mark("visible",t);return v
	func direction(a:Vector2,b:Vector2,r:float,s:float=0.0)->Vector2:
		var t:=Time.get_ticks_usec();var v:=super.direction(a,b,r,s);mark("direction",t);return v
	func move(a:Vector2,b:Vector2,r:float)->Vector2:
		var t:=Time.get_ticks_usec();var v:=super.move(a,b,r);mark("move",t);return v
class CountTelegraphs extends "res://scripts/combat/telegraphed_area_runtime.gd":
	var reads:=0
	var nonempty:=0
	var copy_us:=0
	var advance_us:=0
	func state_for(id:int)->Dictionary:
		var t:=Time.get_ticks_usec();var v:=super.state_for(id);copy_us+=Time.get_ticks_usec()-t;reads+=1
		if not v.is_empty():nonempty+=1
		return v
	func advance(d:float,enemies:Variant)->Array[Dictionary]:
		var t:=Time.get_ticks_usec();var v:=super.advance(d,enemies);advance_us+=Time.get_ticks_usec()-t;return v
class CountArena extends "res://scripts/main.gd":
	var ai_us:=0
	var start_us:=0
	func _update_enemies(d:float)->void:
		var t:=Time.get_ticks_usec();super._update_enemies(d);ai_us+=Time.get_ticks_usec()-t
	func _start_enemy_telegraphs()->void:
		var t:=Time.get_ticks_usec();super._start_enemy_telegraphs();start_us+=Time.get_ticks_usec()-t
func summary(values:Array[int])->Dictionary:
	var v:=values.duplicate();v.sort();var total:=0.0
	for x:int in v:total+=x
	return {"mean_us":total/v.size(),"p95_us":v[int(v.size()*0.95)],"max_us":v.back()}
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v038-audit"):quit(78);return
	var rows:Array=[]
	for scenario:String in ["normal","normal_10_guards","ruins_10_guards"]:
		var arena:=CountArena.new();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
		arena.start_density_demo();while arena.hud.is_blocking():arena.hud.close_panel()
		arena.invulnerable=100000.0;arena.rng.seed=380038
		var geometry:=CountGeometry.new();geometry.configure("broken_ruins" if scenario.begins_with("ruins") else "normal",arena.ARENA);arena._geometry=geometry
		var attacks:=CountTelegraphs.new();arena.telegraphs=attacks
		if scenario!="normal":
			for i:int in range(10):
				var enemy:Dictionary=arena.monster_runtime.create_root("ember_guard",1,arena.player_pos+Vector2(90+i*5,30),"demo","",[],false)
				enemy.spawn=0.0;arena.enemies[i]=enemy
		for enemy:Dictionary in arena.enemies:enemy.pos=geometry.legal_point(enemy.pos,enemy.radius)
		for i:int in range(30):arena.tick(1.0/60.0)
		geometry.count.clear();geometry.usec.clear();attacks.reads=0;attacks.nonempty=0;attacks.copy_us=0;attacks.advance_us=0;arena.ai_us=0;arena.start_us=0
		var ticks:Array[int]=[];var hud:Array[int]=[];var visual:Array[int]=[];var separation:=0
		for i:int in range(180):
			var t:=Time.get_ticks_usec();arena.tick(1.0/60.0);ticks.append(Time.get_ticks_usec()-t);separation+=arena.separation_candidate_visits
			t=Time.get_ticks_usec();arena.telegraph_visual_states();visual.append(Time.get_ticks_usec()-t)
			t=Time.get_ticks_usec();arena.hud._process(1.0/60.0);hud.append(Time.get_ticks_usec()-t)
		rows.append({"fixture":scenario,"ticks":180,"enemies":arena.enemies.size(),"tick":summary(ticks),"hud":summary(hud),"telegraph_visual_snapshot":summary(visual),"enemy_ai_mean_us":arena.ai_us/180.0,"telegraph_start_mean_us":arena.start_us/180.0,"telegraph_advance_mean_us":attacks.advance_us/180.0,"state_reads":attacks.reads,"state_nonempty_deep_copies":attacks.nonempty,"state_copy_mean_us":attacks.copy_us/180.0,"geometry_call_counts":geometry.count.duplicate(),"geometry_nested_total_us":geometry.usec.duplicate(),"separation_visits":separation,"active_end":attacks.active_count(),"alive":arena.alive})
		arena.queue_free();await process_frame
	var report={"source":"f074c2614540f0842964ced961b3430871adce57","runtime_unchanged":true,"ticks_per_sample":180,"scope":"100 real catalog enemies, no shooting/rewards;10 guards and wall geometry deliberately isolated fixtures. Timings include instrumentation overhead; nested totals overlap. Headless CPU only, not Windows FPS or rendering.","samples":rows}
	FileAccess.open("/workspace/scratch/a51485f153de/v038-diagnostics/frame-paths.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));quit()
