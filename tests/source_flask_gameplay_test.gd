extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Presentation=preload("res://scripts/ui/unified_item_presentation.gd")
const LIFE_PATH=["58833","48828","33508","36881","35503","19144","16167","10829","18402"]
const MANA_PATH=["58833","48828","33508","36881","35503","19144","16167","10829","41967","17546"]
const GAIN_PATH=["58833","2151","37690","48423","6204","63976","33479","10490","47251","7388","60398","60648"]
var arena:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func model_for(nodes:Array,path:String)->RefCounted:
	var model:=Model.new();var candidate:=model.snapshot();candidate.progress.level=119;candidate.progress.xp=0;candidate.talents.allocated=nodes.duplicate();candidate.talents.normal_points=123-(nodes.size()-1)
	check(model.Rules.reason(candidate).is_empty(),"Isolated high-level connected prefix validates")
	model._accept_memory(candidate);check(model.save_build(path)==OK,"Real full candidate saves before actions");return model
func attach(model:RefCounted,path:String)->void:
	if arena.state.changed.is_connected(arena._on_build_changed):arena.state.changed.disconnect(arena._on_build_changed)
	arena.state=model;arena.build_save_path=path;model.changed.connect(arena._on_build_changed);arena._stats=model.get_stats();arena._sync_flasks(true)
	arena.enemies.clear();arena.projectiles.clear();arena.pickups.clear();arena.monster_runtime.reset();arena.spawn_timer=10000.0;arena.alive=true;arena.auto_fire=false;arena.demo_mode=false;arena.reward_kills=0;arena.kills=0;arena.wave=1;arena.elapsed=0.0
	arena.health=1.0;arena.mana=1.0;arena.shield=0.0;arena.player_pos=arena.ARENA.get_center();arena.rng.seed=350035
func bottle(resource:String)->Dictionary:
	for slot:Dictionary in arena.state.flask_slots():
		if slot.resource==resource:return slot
	return {}
func kill(template:String="crawler")->Dictionary:
	var target:Dictionary=arena._spawn_monster(template,arena.ARENA.position+Vector2(100,100),"ordinary","",[],true);target.spawn=0.0
	var result:=Defense.incoming_hit({"physical":20000.0},{},target.shield,target.health,"monster")
	arena._begin_progress_transaction();arena._apply_enemy_settlement(target,result,Color.WHITE);arena._end_progress_transaction();return target
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	while arena.hud.is_blocking():arena.hud.close_panel()
	for resource:String in ["health","mana"]:
		var nodes:Array=LIFE_PATH if resource=="health" else MANA_PATH;var path:="user://flask-"+resource+".json";var model:RefCounted=model_for(nodes.slice(0,-1),path);attach(model,path)
		check(model.allocate_passive(nodes.back(),0,model.revision(),path).ok,"Actual source recovery node allocated")
		var slot:=bottle(resource);var profile:Dictionary=model.get_flask_profile(slot.uid);var maximum:float=arena._stats.max_health if resource=="health" else arena._stats.max_mana
		check(profile.ok and is_equal_approx(profile.recovery_total,maximum*0.35*(1.1 if resource=="health" else 1.15)),"Profile derives true matching source node and current maximum")
		var view:=Presentation.view(model,slot.uid);check(view.preview_lines==Presentation.flask_preview_lines(profile) and view.preview_lines[0].contains("%.2f"%profile.recovery_total),"Root tooltip consumes actual model profile, keeping base values separate")
		var prior:Dictionary=model.snapshot();var saves:int=model.successful_saves
		check(arena.use_flask(slot.slot_id).ok and arena.flask_runtime.snapshot().charges_by_uid[slot.uid]==20,"Actual game use spends existing10 charges")
		check(model.snapshot()==prior and model.successful_saves==saves,"Use does not write source stats or flask state to save")
		var active:Dictionary=arena.flask_runtime.snapshot();check(not arena.use_flask(slot.slot_id).ok and arena.flask_runtime.snapshot()==active,"Active same-resource use rejects without another payment")
		check(model.refund_passive(nodes.back(),model.revision(),path).ok and arena.flask_runtime.snapshot()==active,"Refund preserves already-frozen recovery")
		check(model.move_item(slot.uid,model.first_bag_position(slot.uid),model.revision(),path).ok and arena.flask_runtime.snapshot()==active,"Moving active bottle to bag does not restart or cancel recovery")
		check(model.move_item(slot.uid,{"kind":"flask_slot","slot_id":"flask_3"},model.revision(),path).ok and arena.flask_runtime.snapshot()==active,"SameUID re-equip retains spent charge and active snapshot")
		var initial:float=arena.health if resource=="health" else arena.mana;var regen:float=arena._stats.life_regen if resource=="health" else arena._stats.mana_regen;var cap:float=arena._stats.max_health if resource=="health" else arena._stats.max_mana
		arena._tick(3.0);var recovered:float=arena.health if resource=="health" else arena.mana
		check(is_equal_approx(recovered,minf(cap,initial+regen*3.0+profile.recovery_total)) and arena.flask_runtime.snapshot().active_by_resource.is_empty(),"Real tick uses locked total after refund and current resource clamp")
	# Legal roots, duplicate deaths, rewardless descendants and real slot movement.
	var path:="user://flask-gain.json";var model:RefCounted=model_for(GAIN_PATH.slice(0,-1),path);attach(model,path)
	check(model.allocate_passive(GAIN_PATH.back(),0,model.revision(),path).ok,"Actual5percent gain node allocated")
	var slot:=bottle("health");check(arena.use_flask(slot.slot_id).ok,"Make real room for awarded charges");arena.flask_runtime.clear_effects()
	var root_enemy:=kill();var earned:Dictionary=arena.flask_runtime.snapshot()
	check(arena.reward_kills==1 and model.snapshot().progress.xp==int(root_enemy.xp_reward),"Actual reward-enabled root pays XP through existing settlement")
	check(earned.charges_by_uid[slot.uid]==21 and earned.charge_remainders_micro[slot.uid]==50000 and arena.reward_kills==1,"First legal root grants1.05 once")
	arena._apply_enemy_settlement(root_enemy,Defense.incoming_hit({"physical":20000.0},{},0.0,1.0,"monster"),Color.WHITE)
	check(arena.flask_runtime.snapshot()==earned and arena.reward_kills==1,"Repeated corpse cannot pay whole or fractional charge")
	check(model.move_item(slot.uid,model.first_bag_position(slot.uid),model.revision(),path).ok,"Move UID into true bag location")
	kill();check(arena.flask_runtime.snapshot()==earned,"Bag-owned but unequipped bottle gets no root charge and keeps prior carry")
	check(model.move_item(slot.uid,{"kind":"flask_slot","slot_id":"flask_3"},model.revision(),path).ok and arena.flask_runtime.snapshot()==earned,"Re-equip does not reset/copy the same fraction")
	var splitter:=kill("splitter");arena._flush_monster_spawns();var after_root:Dictionary=arena.flask_runtime.snapshot();var root_count:int=arena.reward_kills
	check(after_root.charges_by_uid[slot.uid]==22 and after_root.charge_remainders_micro[slot.uid]==100000,"Next valid root accumulates same UID fraction")
	var children:Array=arena.enemies.filter(func(enemy:Dictionary)->bool:return enemy.root_id==splitter.id and enemy.generation>0)
	check(not children.is_empty(),"Real death queue produces rewardless children")
	for child:Dictionary in children:
		child.spawn=0.0;arena._apply_enemy_settlement(child,Defense.incoming_hit({"physical":20000.0},{},child.shield,child.health,"monster"),Color.WHITE)
	check(arena.flask_runtime.snapshot()==after_root and arena.reward_kills==root_count,"All real descendants produce no charge, fraction or root reward")
	var loaded:=Model.new();check(loaded.load_build(path) and not loaded.snapshot().has("charge_remainders_micro") and loaded.snapshot()==model.snapshot(),"Runtime carry never becomes a persistent inventory field")
	arena.restart_run();check(not arena.flask_runtime.snapshot().has("charge_remainders_micro") and arena.flask_runtime.snapshot().charges_by_uid[slot.uid]==30,"Existing new-battle reset resets carry and charges together")
	# Identical controlled reward sequences isolate the new charge parameter only.
	var outcomes:Array=[]
	for gain:float in [0.0,0.15]:
		var reward_path:="user://rng-%.2f.json"%gain;var state:RefCounted=model_for(["58833"],reward_path);attach(state,reward_path);arena._stats.flask_charges_gained_increased=gain
		var life:=bottle("health");arena.use_flask(life.slot_id);arena.flask_runtime.clear_effects()
		for i:int in range(8):kill()
		check(arena.reward_kills==8 and state.snapshot().progress.xp>0,"Controlled sequence really paid eight legal root rewards")
		outcomes.append({"rng":arena.rng.state,"save":state.snapshot(),"kills":arena.reward_kills,"pickups":arena.pickups.duplicate(true)})
	check(outcomes[0]==outcomes[1],"Eight real root rewards preserve exact RNG, XP, equipment UID/output and pickups regardless of charge gain")
	print("Source flask gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
