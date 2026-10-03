extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Catalog=preload("res://scripts/monsters/monster_catalog.gd")
const MeleePath:Array[String]=["58833","2151","37690","48423","6204","63976","16775","46910","33740","15405","50862","44606","26523","58449","40535"]
const ChaosPath:Array[String]=["58833","2151","37690","48423","6204","63976","33479","10490","47251","7388","60398","46340","42760","36678","39841","63447","47949"]
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func run()->void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated+"/"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	for skill:String in ["cleave","shade_bolt"]:
		await scenario(skill,MeleePath if skill=="cleave" else ChaosPath)
	print("Offense skill gameplay: %d checks, %d failures"%[checks,failures])
	arena.queue_free();await process_frame;quit(1 if failures else 0)
func scenario(skill:String,path_nodes:Array[String])->void:
	var model:=Model.new();var path:="user://actual-"+skill+".json"
	# Isolated earned-budget fixture only. Every path step below uses the real
	# allocation command and persistence gates; no grant/stat value is injected.
	var setup:=model.snapshot();setup.progress.level=30;setup.talents.normal_points=34
	model._accept_memory(setup);check(model.save_build(path)==OK,"Valid earned-budget fixture saved")
	for node:String in path_nodes.slice(1,-1):
		check(model.allocate_passive(node,0,model.revision(),path).ok,"Actual connected source-tree path allocation: "+node)
	var gem:=model.award_gem("skill:"+skill);check(not gem.is_empty(),"Actual new gem instance admitted")
	check(model.move_item(gem,{"kind":"skill_main","group_id":"group_000009"},model.revision(),path).ok,"Gem moved through authoritative UID command")
	check(model.bind_group("group_000009",KEY_9,model.revision(),path).ok,"New skill gets an actual keyboard binding")
	arena.state=model;model.changed.connect(arena._on_build_changed);arena._stats=model.get_stats()
	arena.mana=arena._stats.max_mana;arena.group_cooldowns.reset();arena.enemies.clear();arena.projectiles.clear()
	var before:=model.get_group_cast("group_000009")
	var original_others:Dictionary={}
	for old:String in ["bolt","frost","nova","meteor","chain","tornado"]:original_others[old]=Compiler.compile_group(old,model.get_combat_snapshot(),[])
	var target_node:String=path_nodes.back()
	check(model.allocate_passive(target_node,0,model.revision(),path).ok,"Formerly zero-consumer source node is truly allocated")
	var after:=model.get_group_cast("group_000009")
	var role:="direct" if skill=="cleave" else "projectile"
	var raw_primary:float=before.packets[role].base.get("physical" if skill=="cleave" else "chaos",0.0)
	near(resolved(after,role)-resolved(before,role),raw_primary*0.12,"Exact source +12% increase has a real matching consumer")
	for old:String in original_others:check(original_others[old].packets==Compiler.compile_group(old,model.get_combat_snapshot(),[]).packets,"Nonmatching skill raw packets remain stable")
	# Modifiers legitimately include the new grant. Compare their resolved packets,
	# not the whole snapshot, because unmatched modifiers must remain visible there.
	for old:String in original_others:
		var current:=Compiler.compile_group(old,model.get_combat_snapshot(),[])
		var old_role:String="parent" if old=="tornado" else "projectile" if old in ["bolt","frost"] else "direct"
		if old=="chain":near(Damage.resolve(current.packets.bounces[0],current.snapshot.modifiers).total,Damage.resolve(original_others[old].packets.bounces[0],original_others[old].snapshot.modifiers).total,"Nonmatching chain actual damage unchanged")
		else:near(resolved(current,old_role),resolved(original_others[old],old_role),"Nonmatching old primary damage unchanged")
	var target:=enemy(900,Vector2(55,0));arena.enemies.append(target)
	var rear:=enemy(901,Vector2(-75,0));arena.enemies.append(rear)
	var mana_before:float=arena.mana;var health_before:float=target.health
	check(arena.cast_group("group_000009"),"Actual main cast admitted")
	near(arena.mana,mana_before-float(after.mana),"Actual cast charges compiled mana")
	near(arena.group_cooldown_remaining("group_000009"),float(after.cooldown),"Actual cast starts same compiled group/main UID cooldown")
	if skill=="shade_bolt":
		check(arena.projectiles.size()==1 and arena.projectiles[0].payload.base.has("chaos"),"Actual chaos projectile exists")
		var frozen:=var_to_bytes(arena.projectiles[0].payload)
		check(model.equip("storm_charm"),"Equipment changes after launch")
		check(var_to_bytes(arena.projectiles[0].payload)==frozen,"Flying projectile retains the original packet")
		arena._update_projectiles(0.2)
	else:
		var cue:Dictionary=arena.visual_cues.cues.back()
		check(cue.kind=="cleave" and cue.radius==after.recipe.radius and cue.half_angle==after.recipe.half_angle,"Actual sector cue receives the exact compiled hit geometry")
	near(health_before-float(target.health),resolved(after,role),"Real target takes the previewed before-defense hit at zero mitigation")
	near(float(rear.health),10000.0,"Rear target remains outside the forward attack/dart")
	var mana_now:float=arena.mana
	check(not arena.cast_group("group_000009") and arena.mana==mana_now,"Immediate repeated cast is rejected without charging")
	check(model.move_item(gem,{"kind":"skill_main","group_id":"group_000010"},model.revision(),path).ok,"Main UID moves to another row")
	check(not arena.cast_group("group_000010") and arena.mana==mana_now,"Moving a main gem does not reset its cooldown debt")
	var other:=model.award_gem("skill:"+skill)
	check(not other.is_empty() and other!=gem,"Same-name gem has a different stable UID")
	check(model.move_item(other,{"kind":"skill_main","group_id":"group_000009"},model.revision(),path).ok,"Fresh same-name gem can occupy the original row")
	check(not arena.cast_group("group_000009"),"Original row cooldown survives swapping gems")
	arena.group_cooldowns.advance(10.0);arena.mana=0.0
	var debts:Dictionary=arena.group_cooldowns.snapshot()
	check(not arena.cast_group("group_000010") and arena.group_cooldowns.snapshot()==debts,"Resource rejection does not create a debt")
	var reopened:=Model.new();check(reopened.load_build(path) and reopened.snapshot()==model.snapshot(),"Actual UID arrangement, passive path and binding survive save reload")
	model.changed.disconnect(arena._on_build_changed)
	await process_frame
func enemy(id:int,offset:Vector2)->Dictionary:
	var value:=Catalog.make_enemy(id,"crawler",1,arena.player_pos+offset)
	value.health=10000.0;value.max_health=10000.0;value.spawn=0.0;value.armour=0.0;value.evasion=0.0;value.evasion_entropy=50.0;value.shield=0.0
	return value
func resolved(cast:Dictionary,role:String)->float:return float(Damage.resolve(cast.packets[role],cast.snapshot.modifiers).total)
func near(actual:float,expected:float,label:String)->void:check(is_equal_approx(actual,expected),label+" %.8f / %.8f"%[actual,expected])
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
