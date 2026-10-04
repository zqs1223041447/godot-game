extends SceneTree
const Combat=preload("res://scripts/combat/combat_data.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	arena.enter_town_test(arena.world_context().revision);arena.craft_map("broken_ruins",[],[],arena.map_draft().revision);arena.start_map(arena.map_draft().revision)
	arena.enemies.clear();arena.monster_runtime.reset();arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var wall:Rect2=arena.world_geometry().walls[0]
	arena.player_pos=Vector2(wall.end.x+200,wall.get_center().y)
	for index:int in range(100):
		var point:=Vector2(wall.position.x-25-(index%5)*30,wall.position.y-60+int(index/5)*25)
		var actor:Dictionary=arena._spawn_monster(["crawler","skitter","brute"][index%3],point,"demo","",[],false);actor.spawn=0.0
	var identity:Array=[]
	for actor:Dictionary in arena.enemies:identity.append([actor.id,actor.root_id,actor.radius,actor.max_health,actor.xp_reward,actor.reward_eligible])
	var valid:=true;var maximum_graphs:=0
	for tick:int in range(180):
		arena._update_enemies(1.0/60.0)
		maximum_graphs=maxi(maximum_graphs,arena._geometry._routes.size())
		for actor:Dictionary in arena.enemies:valid=valid and arena._geometry.is_clear(actor.pos,actor.radius)
	var after:Array=[]
	for actor:Dictionary in arena.enemies:after.append([actor.id,actor.root_id,actor.radius,actor.max_health,actor.xp_reward,actor.reward_eligible])
	check(arena.enemies.size()==100 and valid,"100 real catalog actors stay outside walls under routing and mutual separation")
	check(identity==after,"Terrain crowd movement preserves all identities, body sizes and reward budgets")
	check(maximum_graphs<=3,"Stationary goal shares only three exact-radius route graphs, not one path graph per enemy")
	arena.enemies.clear();arena.monster_runtime.reset();arena.projectiles.clear();arena.combat_trace.clear()
	var center:=Vector2(wall.position.x-10,wall.get_center().y)
	var hidden:Dictionary=arena._spawn_monster("crawler",Vector2(wall.end.x+14,center.y),"demo","",[],false);hidden.spawn=0.0
	var visible:Dictionary=arena._spawn_monster("crawler",center+Vector2(-60,0),"demo","",[],false);visible.spawn=0.0
	var health:float=hidden.health;var other_health:float=visible.health
	var snapshot:Dictionary=Combat.snapshot({"damage":10.0},["explode_on_flight_end"])
	var spec:Dictionary={"speed":100.0,"range":500.0,"lifetime":0.01,"radius":4.5,"pierce":-1,"role":"child","split":false}
	var projectile:Dictionary=arena.projectile_runtime.make_projectile(center,Vector2.UP,spec,Combat.tornado_packet(snapshot,"child"),snapshot,arena.projectile_runtime.new_cast(),Color.WHITE)
	arena.projectiles.append(projectile);arena._update_projectiles(0.02)
	check(projectile.end_reason=="lifetime_expired" and int(arena.event_counts.get("explosion",0))==1,"Genuine expiry near a wall still triggers exactly one explosion")
	check(hidden.health==health and visible.health<other_health,"Actual explosion consumer blocks the hidden side while applying visible-side damage")
	print("Terrain crowd and blast: %d checks, %d failures; max route graphs %d"%[checks,failures,maximum_graphs]);arena.queue_free();await process_frame;quit(1 if failures else 0)
