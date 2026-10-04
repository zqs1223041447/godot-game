extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const CriticalRuntime=preload("res://scripts/combat/critical_strike_runtime.gd")
const PATH=["50986","47389","42911","40867","476","24865","6741","14056","34400","24914","38664"]
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var model:=Model.new();var uid:String=model.award_gem("skill:cleave");var candidate:=model.snapshot()
	candidate.locations[uid]={"kind":"skill_main","group_id":"group_000009"};candidate.progress.level=119;candidate.progress.xp=0;candidate.talents.class_id=4;candidate.talents.allocated=PATH.slice(0,-1);candidate.talents.normal_points=124-candidate.talents.allocated.size()
	check(model.Rules.reason(candidate).is_empty(),"Real equipped cleave plus connected path accepted")
	model._accept_memory(candidate);var path:="user://melee.json";check(model.save_build(path)==OK,"Melee build persisted")
	var before:=model.get_skill_cast("cleave");var ranged:=model.get_skill_cast("tornado");var spell:=model.get_skill_cast("nova")
	check(model.allocate_passive("38664",0,model.revision(),path).ok,"Real melee chance node allocated")
	var after:=model.get_skill_cast("cleave")
	check(is_equal_approx(after.critical.primary.chance-before.critical.primary.chance,0.01),"20percent melee increased raises 5percent base by one percentage point")
	check(model.get_skill_cast("tornado").critical==ranged.critical and model.get_skill_cast("nova").critical==spell.critical,"Non-melee actual casts unchanged")
	check(model.allocate_passive("56460",0,model.revision(),path).ok,"Real adjacent multiplier node allocated")
	var current:=model.get_skill_cast("cleave")
	check(is_equal_approx(current.critical.primary.multiplier-after.critical.primary.multiplier,0.1),"10percent melee multiplier adds ten points to actual cleave")
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	while arena.hud.is_blocking():arena.hud.close_panel()
	arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.player_pos=arena.ARENA.get_center();arena.mana=10000.0;arena.auto_fire=false
	var target:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(60,0),"ordinary","",[],false);target.spawn=0.0;target.health=1000000.0;target.max_health=target.health;target.evasion=0.0;target.armour=0.0
	var rt:=CriticalRuntime.new();var seed_value:=-1
	for n:int in range(10000):
		rt.reset(n)
		if rt.freeze(current.snapshot).snapshot.critical_roll.critical:seed_value=n;break
	arena.critical_runtime.reset(seed_value)
	check(arena._execute_compiled(current) and arena.damage_trace.size()==1,"Current source-boosted real cleave reaches an actual enemy")
	check(arena.damage_trace[0].critical.critical and arena.damage_trace[0].critical.multiplier==current.critical.primary.multiplier,"Actual hit consumes source-adjusted multiplier")
	var normal:Dictionary=arena.Damage.resolve(current.packets.direct,current.snapshot.modifiers,target.resistances)
	check(is_equal_approx(arena.damage_trace[0].total,float(normal.total)*float(current.critical.primary.multiplier)),"Observed hit gain equals frozen critical multiplier")
	print("Critical melee source: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
