extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	check(arena.save_build(),"Fresh normal profile saved")
	var model:RefCounted=arena.state;var original_gems:int=0
	for owned:Dictionary in model.snapshot().items.values():
		if owned.definition_id=="support:ignite":original_gems+=1
	check(original_gems==0,"New support is not silently gifted")
	var offer:Dictionary={}
	for row:Dictionary in arena.normal_gem_offers():
		if row.definition_id=="support:ignite":offer=row
	check(not offer.is_empty() and offer.cost==4 and not offer.available,"Real normal merchant lists priced support and checks funds")
	var candidate:Dictionary=model.snapshot();check(model._set_bag_currency_balance(candidate,4).ok,"Four existing currency items budget admitted")
	candidate.revision+=1;check(model._commit(candidate,arena.NORMAL_BUILD_PATH).ok,"Currency fixture is a full validated save")
	var issued:Dictionary=arena.normal_gem_trade_quote("buy","support:ignite",model.revision())
	check(issued.ok and issued.cost.calibration_shard==4,"New definition reaches authoritative paid quote")
	var result:Dictionary=arena.execute_normal_gem_trade(issued.get("handle",""),"support:ignite")
	check(result.ok and model.crafting_balance()==0,"Purchase deducts physical shards")
	var uid:String=result.get("uid","")
	check(model.item(uid).payload=={"level":1,"quality":0} and model.item(uid).definition_id=="support:ignite","Real purchased UID has fixed supported payload")
	var meteor_group:="";var bolt_group:=""
	for group:Dictionary in model.snapshot().skill_groups:
		var contents:Dictionary=model.skill_group(group.id)
		if contents.skill_id=="meteor":meteor_group=group.id
		elif contents.skill_id=="bolt":bolt_group=group.id
	check(not meteor_group.is_empty() and not bolt_group.is_empty(),"Real starter groups available")
	var before:Dictionary=model.snapshot();var disk:PackedByteArray=FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	check(not model.move_item(uid,{"kind":"skill_support","group_id":bolt_group,"index":0},model.revision(),arena.NORMAL_BUILD_PATH).ok and model.snapshot()==before and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==disk,"Non-native-fire group rejects bought gem atomically")
	check(model.move_item(uid,{"kind":"skill_support","group_id":meteor_group,"index":0},model.revision(),arena.NORMAL_BUILD_PATH).ok,"Same bought UID moves into legal support slot")
	var compiled:Dictionary=model.get_group_cast(meteor_group)
	check(compiled.ok and compiled.has("burn_profile") and compiled.support_ids.has("ignite"),"Actual model/compiler projects burning recipe")
	var loaded:=Model.new();check(loaded.load_build(arena.NORMAL_BUILD_PATH) and loaded.snapshot()==model.snapshot(),"Equipped new UID reloads strictly as schema28")
	check(loaded.get_group_cast(meteor_group)==compiled,"Reloaded cast fields are exactly the same")
	check(not FileAccess.get_file_as_string(arena.NORMAL_BUILD_PATH).contains('"burn_runtime"'),"Transient status is not serialized")
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Actual formal profile enters combat practice")
	arena.enemies.clear();arena.monster_runtime.reset();arena.player_pos=arena.ARENA.get_center();arena.mana=1000.0;arena.hud.close_panel()
	var enemy:Dictionary=arena._spawn_monster("brute",arena.player_pos+Vector2(100,0));enemy.spawn=0.0;enemy.health=100000.0;enemy.max_health=100000.0
	var mana:float=arena.mana;check(arena.cast_group(meteor_group),"Bound actual group containing purchased gem casts")
	check(is_equal_approx(mana-arena.mana,compiled.mana) and arena.group_cooldowns.remaining(meteor_group,model.skill_group(meteor_group).main_uid)>0.0,"Normal mana and UID/group cooldown apply")
	check(arena.burn_statuses().size()==1 and arena.burn_statuses()[0].raw_dps>0.0,"Purchased/equipped support produces actual target burning")
	print("Ignite acquisition: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
