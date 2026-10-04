extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const Runtime=preload("res://scripts/combat/critical_strike_runtime.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var model:Model=arena.state;model.equip("detonation_charm")
	var uid:String=model.award_gem("skill:shade_bolt");var path:="user://secondary.json";arena.build_save_path=path
	check(not uid.is_empty() and model.move_item(uid,{"kind":"skill_main","group_id":"group_000010"},model.revision(),path).ok,"Real dark projectile stone and explosion item equipped")
	var cast:=model.get_skill_cast("shade_bolt")
	check(cast.ok and cast.snapshot.effects.has("explode_on_flight_end") and Combat.event_packet(cast.snapshot,"shade_bolt","projectile")==cast.packets.projectile and Combat.secondary_packet(cast.snapshot,"shade_bolt")==cast.packets.secondary,"Frozen shade-bolt whitelist returns both authoritative packets")
	var cleave_uid:String=model.award_gem("skill:cleave")
	check(model.move_item(cleave_uid,{"kind":"skill_main","group_id":"group_000009"},model.revision(),path).ok,"Real cleave gem equipped")
	var cleave:=model.get_skill_cast("cleave")
	check(Combat.event_packet(cleave.snapshot,"cleave","direct")==cleave.packets.direct and Combat.secondary_packet(cleave.snapshot,"cleave").is_empty(),"Cleave accepts direct role but never invents a secondary packet")
	arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.event_counts.clear();arena.mana=10000.0;arena.player_pos=arena.ARENA.get_center();arena.player_facing=Vector2.RIGHT
	var oracle:=Runtime.new();var chosen:=-1
	for seed_value:int in range(10000):
		oracle.reset(seed_value);var primary:Dictionary=oracle.freeze(cast.snapshot).snapshot;var secondary:Dictionary=oracle.freeze(primary,"secondary").snapshot
		if secondary.critical_roll.critical:chosen=seed_value;break
	check(chosen>=0,"Deterministic independent secondary critical sample exists")
	arena.critical_runtime.reset(chosen)
	check(arena.cast_group("group_000010") and arena.projectiles.size()==1,"Actual bound dark projectile emits its normal carrier")
	var shot:Dictionary=arena.projectiles[0];var frozen:Dictionary=shot.snapshot.duplicate(true)
	var end:Vector2=Vector2(shot.pos)+Vector2(shot.velocity).normalized()*minf(float(shot.range),float(shot.speed)*float(shot.lifetime))
	for offset:Vector2 in [Vector2(0,45),Vector2(0,-45)]:
		var enemy:Dictionary=arena._spawn_monster("crawler",end+offset,"ordinary","",[],false);enemy.spawn=0.0;enemy.health=1000000.0;enemy.max_health=enemy.health;enemy.radius=6.0;enemy.evasion=0.0;enemy.armour=0.0;enemy.shield=0.0
	arena._update_projectiles(2.0)
	check(arena.projectiles.is_empty() and int(arena.event_counts.get("explosion",0))==1 and int(arena.event_counts.get("hit",0))==0,"Unobstructed actual shade bolt expires once and causes its equipped explosion")
	check(arena.damage_trace.size()==2 and arena.critical_runtime.events==2 and arena.critical_runtime.draws==2,"One accepted cast plus one independent explosion, shared by two actual targets")
	for record:Dictionary in arena.damage_trace:
		check(record.tags==cast.packets.secondary.tags and record.critical.critical and record.critical.chance==cast.critical.secondary.chance and record.critical.multiplier==cast.critical.secondary.multiplier,"Real secondary damage consumes the frozen global-only critical profile")
	check(shot.snapshot==frozen,"Explosion resolution leaves original carrier snapshot unchanged")
	var saved:=Model.new();check(saved.load_build(path) and saved.snapshot()==model.snapshot(),"Item effect and new gem UID survive save without runtime roll persistence")
	print("Critical secondary skill: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
