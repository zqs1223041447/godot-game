extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Presentation=preload("res://scripts/ui/unified_item_presentation.gd")
const SkillPanel=preload("res://scripts/ui/canonical_skill_panel.gd")
const PREFIX=["58833","2151","37690","48423","6204","63976","33479","10490","45680"]
var arena:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func observe()->Dictionary:
	return {"mana":arena.mana,"state":arena.state.snapshot(),"shots":arena.projectiles.duplicate(true),"ids":[arena.projectile_runtime.next_projectile_id,arena.projectile_runtime.next_cast_id],"rng":arena.rng.state,"debts":arena.group_cooldowns.snapshot(),"saves":arena.state.successful_saves}
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var model:=Model.new();var setup:=model.snapshot();setup.progress.level=119;setup.progress.xp=0;setup.talents.allocated=PREFIX.duplicate();setup.talents.normal_points=115
	check(model.Rules.reason(setup).is_empty(),"Isolated earned-budget prefix is a legal source build")
	model._accept_memory(setup);var path:="user://resource-live.json";check(model.save_build(path)==OK,"Real prefix saved")
	var base_cost:float=model.get_skill_cast("nova").mana
	check(model.allocate_passive("25237",0,model.revision(),path).ok and is_equal_approx(model.get_skill_cast("nova").mana,base_cost/1.08),"Actual efficiency allocation changes compiled mana")
	check(model.allocate_passive("25714",0,model.revision(),path).ok and is_equal_approx(model.get_skill_cast("nova").mana,base_cost*1.05/1.08),"Actual maximum-mana tradeoff node also increases cost")
	for id:String in ["cleave","shade_bolt"]:
		var uid:String=model.award_gem("skill:"+id);check(not uid.is_empty(),"New active gem admitted through existing acquisition")
		check(model.move_item(uid,{"kind":"skill_main","group_id":"group_000009" if id=="cleave" else "group_000010"},model.revision(),path).ok,"Real main UID placed into existing empty row")
	var efficiency_uid:String=model.award_gem("support:efficiency");var quickcast_uid:String=model.award_gem("support:quickcast")
	check(not efficiency_uid.is_empty() and not quickcast_uid.is_empty(),"Two real support instances acquired")
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	if arena.state.changed.is_connected(arena._on_build_changed):arena.state.changed.disconnect(arena._on_build_changed)
	arena.state=model;arena.build_save_path=path;model.changed.connect(arena._on_build_changed);arena._stats=model.get_stats();arena.enemies.clear();arena.spawn_timer=10000.0
	var skill_ids:Array=[]
	for group:Dictionary in model.snapshot().skill_groups:
		var group_id:String=group.id;var content:Dictionary=model.skill_group(group_id)
		check(model.move_item(efficiency_uid,{"kind":"skill_support","group_id":group_id,"index":0},model.revision(),path).ok and model.move_item(quickcast_uid,{"kind":"skill_support","group_id":group_id,"index":1},model.revision(),path).ok,"Actual two-support ownership links for "+content.skill_id)
		var cast:=model.get_group_cast(group_id);skill_ids.append(cast.skill_id)
		check(cast.ok and cast.support_ids==["efficiency","quickcast"] and is_equal_approx(cast.mana,float(cast.cost_factors.support_mana)*1.05/1.08),"Current group cast has the authoritative combined cost")
		var no_resource:=model.get_combat_snapshot();no_resource.erase("resource_modifiers")
		var baseline:=Compiler.compile_group(cast.skill_id,no_resource,["quickcast","efficiency"])
		check(cast.cooldown==baseline.cooldown and cast.packets==baseline.packets and cast.recipe==baseline.recipe,"Source cost does not alter support cooldown or skill effects")
		var view:=Presentation.view(model,content.main_uid)
		check(view.preview_lines[0].contains(str(cast.mana)) and view.preview_lines[0].contains(str(cast.cooldown)),"Real gem tooltip reads exact current cost/cooldown, separately from base stats")
		arena.projectiles.clear();arena.group_cooldowns.reset();arena.player_pos=arena.ARENA.get_center();arena.alive=true;arena.mana=float(cast.mana)-0.000001
		var before:=observe();check(not arena.cast_group(group_id) and observe()==before,"Insufficient mana rejects before payment, identity, RNG, debt or save")
		if cast.initial_count>0:
			arena.projectiles.resize(arena.MAX_PROJECTILES)
			for i:int in range(arena.MAX_PROJECTILES):arena.projectiles[i]={}
			arena.mana=float(cast.mana)+10.0;before=observe()
			check(not arena.cast_group(group_id) and observe()==before,"Full projectile budget rejects without consuming source-adjusted cost")
			arena.projectiles.clear()
		arena.mana=cast.mana;var saved:Dictionary=model.snapshot();var saves:int=model.successful_saves;var legacy:Dictionary=arena.cooldowns.duplicate(true)
		check(arena.cast_group(group_id) and is_zero_approx(arena.mana),"Exactly enough final mana is admitted through real group entry: "+cast.skill_id)
		check(is_equal_approx(arena.group_cooldown_remaining(group_id),cast.cooldown) and is_equal_approx(arena.group_cooldowns.remaining("another_group",content.main_uid),cast.cooldown),"Both actual group and main UID retain configured cooldown debt")
		check(model.snapshot()==saved and model.successful_saves==saves and arena.cooldowns==legacy,"Resource payment is runtime-only and preserves legacy timer route")
		arena.mana=10000.0;before=observe();check(not arena.cast_group(group_id) and observe()==before,"Repeated cooling cast rejects without a second payment")
	check(skill_ids.size()==10 and skill_ids.has("dash") and skill_ids.has("ward") and skill_ids.has("cleave") and skill_ids.has("shade_bolt"),"All ten actual active entries exercised")
	var panel:=SkillPanel.new();panel.setup(model,path)
	for row:Dictionary in panel._rows._rows:
		var current:=model.get_group_cast(row.group_id);check(row.preview.begins_with("%.2f 魔力 · %.2fs"%[current.mana,current.cooldown]),"Existing K row summary consumes final rounded values")
	panel.free()
	var debt:Dictionary=arena.group_cooldowns.snapshot()
	check(model.refund_passive("25714",model.revision(),path).ok and model.refund_passive("25237",model.revision(),path).ok and arena.group_cooldowns.snapshot()==debt,"Refund changes future prices without resetting current cooldown debt")
	check(model.get_skill_cast("nova").mana==base_cost,"Refund restores exact old no-support mana path")
	var loaded:=Model.new();check(loaded.load_build(path) and loaded.snapshot()==model.snapshot() and loaded.get_group_cast("group_000010")==model.get_group_cast("group_000010"),"Saved item/support ownership and new cost projection reread consistently")
	print("Source resource gameplay: %d checks, %d failures; ten active entries"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
