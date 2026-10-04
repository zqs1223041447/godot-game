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
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);check(arena.save_build(),"Save isolated fixture")
	clean();arena._geometry.configure("broken_ruins",arena.ARENA);var wall:Rect2=arena._geometry.snapshot().walls[0]
	var origin:=Vector2(wall.position.x-24.0,wall.get_center().y)
	arena.player_pos=origin;var enemy:Dictionary=target();enemy.pos=Vector2(wall.end.x+24.0,wall.get_center().y)
	check(arena._geometry.is_clear(origin,arena.PLAYER_RADIUS) and arena._geometry.is_clear(enemy.pos,enemy.radius),"Both wall-side fixture positions are legal")
	var cast:Dictionary=meteor();var shield:float=enemy.shield
	arena._area_damage(origin,110.0,cast.packets.direct,Color.ORANGE,0.0,cast.snapshot)
	check(arena.burn_runtime.is_empty() and enemy.shield==shield,"Actual area consumer cannot burn through wall")
	arena._area_damage(enemy.pos,110.0,cast.packets.direct,Color.ORANGE,0.0,cast.snapshot)
	check(arena.burn_statuses().size()==1,"Visible admitted area attaches burning")
	enemy.pos=origin;arena.player_pos=Vector2(wall.end.x+24.0,wall.get_center().y);shield=enemy.shield
	arena.elapsed=0.5;arena._advance_monster_burns(0.5)
	check(enemy.shield<shield and not arena._terrain_visible(arena.player_pos,enemy.pos),"Attached burn continues behind cover without new spatial search")
	# Actual natural parent/split-child paths, with no second modifier application.
	clean();var snap:Dictionary=Combat.snapshot({"damage":100.0,"crit_base_chance":0.0,"crit_base_multiplier":1.5},["return_on_range","explode_on_flight_end"])
	var tornado:Dictionary=Compiler.compile_group("tornado",snap,["ignite"])
	for offset:Vector2 in [Vector2(80,0),Vector2(130,60),Vector2(180,0),Vector2(130,-60),Vector2(240,60),Vector2(240,-60)]:
		var e:Dictionary=target();e.pos=arena.player_pos+offset;e.radius=20.0;e.resistances.fire=0.0
	check(arena._execute_compiled(tornado),"Actual ignite tornado cast accepted")
	var roles:Dictionary={};var child_rate_seen:=false;var seen:Dictionary={}
	for index:int in range(100):
		arena.tick(1.0/60.0)
		for event:Dictionary in arena.combat_trace:
			if event.type=="hit":roles[event.role]=true
		for status:Dictionary in arena.burn_statuses():
			var rate:float=status.raw_dps
			check(is_equal_approx(rate,tornado.burn_profile.roles.parent.dps) or is_equal_approx(rate,tornado.burn_profile.roles.child.dps),"Actual carrier uses only frozen parent/child DPS")
			if is_equal_approx(rate,tornado.burn_profile.roles.child.dps):child_rate_seen=true
	check(roles.has("parent") and roles.has("child"),"Natural split produced actual parent and child hit events")
	check(child_rate_seen,"A target receives child-derived burning")
	# Attack evasion rejects attachment before any burning state is created.
	clean();enemy=target();enemy.evasion=1000000000.0;enemy.evasion_entropy=0.0;snap=Combat.snapshot({"damage":100.0},[]);snap.accuracy=1.0
	tornado=Compiler.compile_group("tornado",snap,["ignite"]);shield=enemy.shield
	arena._apply_damage_packet(enemy,tornado.packets.parent,tornado.snapshot,Color.ORANGE)
	check(enemy.shield==shield and arena.burn_runtime.is_empty() and not arena.attack_admission_trace.back().hit,"Evaded primary fire cannot ignite")
	# Existing explicit damage immunity is honored without granting new protection.
	for skill:String in ["dash","ward"]:
		clean();check(arena.burn_runtime.apply("player",0,999,100.0,3.0,0.0).ok,"Attach controlled existing burn")
		var utility:Dictionary=Compiler.compile_group(skill,Combat.snapshot({"damage":18.0},[]),[])
		check(arena._execute_compiled(utility),"Actual utility cast accepted")
		var duration:float=0.6 if skill=="dash" else 0.8;shield=arena.shield
		arena.tick(duration);near(arena.shield,shield,"Damage immunity skips burning interval")
		near(arena.burn_statuses()[0].remaining_seconds,3.0-duration,"Immune time still consumes duration")
		arena.tick(0.1);near(shield-arena.shield,10.0,"No catch-up damage after immunity expires")
		near(arena.invulnerable,0.0,"Burn doesn't renew invulnerability")
	clean();enemy=target("ember_guard",80.0);enemy.attack_timer=0.0;arena.invulnerable=1.0;arena._start_enemy_telegraphs();shield=arena.shield;arena.tick(0.7)
	check(arena.burn_runtime.is_empty() and arena.shield==shield,"Immune telegraphed hit cannot attach burning")
	# Status damage can end the run once without repeated hit feedback or RNG.
	clean();arena.health=1.0;arena.shield=0.0;arena.burn_runtime.apply("player",0,999,100.0,3.0,0.0)
	var rng:int=arena.rng.state;var crit:Dictionary=arena.critical_runtime.checkpoint();var frames:int=arena.floating_text.size()
	arena.tick(0.1)
	check(not arena.alive and arena.burn_runtime.is_empty() and arena.telegraphs.active_count()==0 and arena.projectiles.is_empty(),"Lethal burn clears run actions and all statuses")
	check(arena.rng.state==rng and arena.critical_runtime.checkpoint()==crit,"Lethal tick adds no hit RNG or critical draw")
	check(arena.floating_text.size()==frames,"DOT does not emit a per-tick hit number or hit flash")
	var disk:PackedByteArray=FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH);arena._advance_player_burn(10.0)
	check(FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==disk,"Dead status cannot repeat persistence")
	print("Ignite boundaries: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
