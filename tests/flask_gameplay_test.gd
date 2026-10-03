extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
var arena:Node
var checks:=0
var failures:=0
var changes:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func near(a:float,b:float,label:String)->void:check(is_equal_approx(a,b),label+" %.8f / %.8f"%[a,b])
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.demo_mode=true;arena.spawn_timer=9999.0;arena.enemies.clear()
	while arena.hud.is_blocking():arena.hud.close_panel()
	check(arena.flask_statuses().size()==5,"Actual main exposes five authoritative slots")
	var slots:Array=arena.state.flask_slots();var life:String=slots[0].uid;var mana:String=slots[1].uid
	arena.state.changed.connect(func():changes+=1)
	var save_count:int=arena.state.successful_saves
	var build:Dictionary=arena.state.snapshot()
	check(not arena.use_flask("flask_1").ok,"Full actual resource refuses")
	arena.health=10.0;arena.mana=0.0;arena.invulnerable=0.0
	var key:=InputEventKey.new();key.physical_keycode=KEY_1;key.keycode=KEY_1;key.pressed=true;key.alt_pressed=true
	arena._unhandled_key_input(key)
	check(arena.flask_runtime.snapshot().charges_by_uid[life]==20 and arena.projectiles.is_empty(),"Alt1 routes to flask and never also casts bound skill")
	check(arena.use_flask("flask_2").ok,"Actual mana use admitted concurrently")
	check(changes==0 and arena.state.successful_saves==save_count and arena.state.snapshot()==build,"Flask use never mutates or saves persistent build")
	var health_max:float=arena._stats.max_health;var mana_max:float=arena._stats.max_mana
	arena.tick(1.0)
	near(arena.health,10.0+health_max*0.35/3.0+float(arena._stats.life_regen),"First real tick combines authored flask rate with unchanged regen")
	check(arena.state.move_item(life,{"kind":"flask_slot","slot_id":"flask_3"},arena.state.revision(),"user://build_save.json").ok,"True slot move commits")
	check(arena.flask_runtime.snapshot().charges_by_uid[life]==20 and not arena.use_flask("flask_3").ok,"Slot move preserves charge and active resource debt")
	var changed_after_move:int=changes;save_count=arena.state.successful_saves
	arena.tick(1.0);arena.tick(1.0)
	near(arena.health,10.0+health_max*0.35+float(arena._stats.life_regen)*3.0,"Actual life restoration completes exact locked35percent")
	near(arena.mana,mana_max*0.35+float(arena._stats.mana_regen)*3.0,"Actual mana restoration separate from passive regen")
	check(changes==changed_after_move and arena.state.successful_saves==save_count,"Recovery frames emit no changed/save")
	arena.hud.open_panel("inventory");var paused:Dictionary=arena.flask_runtime.snapshot()
	check(not arena.use_flask("flask_3").ok and arena.flask_runtime.snapshot()==paused,"Paused UI rejects without charge")
	arena._process(1.0);check(arena.flask_runtime.snapshot()==paused,"Pause freezes recovery clock")
	while arena.hud.is_blocking():arena.hud.close_panel()
	var bag:Dictionary=arena.state.first_bag_position(life)
	check(arena.state.move_item(life,bag,arena.state.revision(),"user://build_save.json").ok,"Bottle can be unequipped into real bag")
	arena.flask_runtime.charge_rewarded_kill([mana]);check(arena.flask_runtime.snapshot().charges_by_uid[life]==20,"Unequipped bottle cannot gain charge")
	check(arena.state.move_item(life,{"kind":"flask_slot","slot_id":"flask_3"},arena.state.revision(),"user://build_save.json").ok,"SameUID can equip again")
	check(arena.flask_runtime.snapshot().charges_by_uid[life]==20,"Unequip/re-equip is not refill")
	test_root_reward(life,mana)
	arena.health=10;arena.invulnerable=0;check(arena.use_flask("flask_3").ok,"Recovery can begin again after expiry")
	arena.hit_player_components({"physical":100000.0},0,["hit","spell"])
	check(not arena.alive and arena.flask_runtime.snapshot().active_by_resource.is_empty(),"Actual death clears recovery")
	check(not arena.use_flask("flask_3").ok,"Dead character cannot spend charges")
	arena.restart_run();check(arena.flask_runtime.snapshot().charges_by_uid[life]==30,"Actual new battle reset refills owned UID")
	print("Flask gameplay: %d checks, %d failures"%[checks,failures])
	arena.queue_free();await process_frame;quit(1 if failures else 0)
func test_root_reward(life:String,mana:String)->void:
	arena.demo_mode=false;arena.reward_kills=59;arena.enemies.clear();arena.rng.seed=260060
	var expected:=Model.new();expected._accept_memory(arena.state.snapshot());var oracle:=RandomNumberGenerator.new();oracle.state=arena.rng.state
	var enemy:Dictionary=arena.monster_runtime.create_root("crawler",1,arena.player_pos+Vector2(45,0));enemy.spawn=0;arena.enemies.append(enemy)
	# Exact old reward path draws and awards, without the new deterministic bottle.
	for unused:int in 9:oracle.randf()
	expected.add_xp(enemy.xp_reward);expected.award_jewel(oracle);expected.award_random_gem(oracle)
	for unused:int in 16:oracle.randf()
	var charges:Dictionary=arena.flask_runtime.snapshot().charges_by_uid;var saves:int=arena.state.successful_saves
	arena._begin_progress_transaction();arena._damage_enemy(enemy,enemy.health+1.0,Color.WHITE);arena._end_progress_transaction()
	check(arena.rng.state==oracle.state,"Adding deterministic bottle preserves existing reward and feedback RNG state")
	var after:Dictionary=arena.state.snapshot();var before_items:Dictionary=expected.snapshot().items
	for uid:String in before_items:check(after.items[uid]==before_items[uid],"All original reward instances/rolls preserved "+uid)
	var added:Array=[]
	for uid:String in after.items:
		if not before_items.has(uid):added.append(after.items[uid])
	check(added.size()==1 and added[0].kind=="flask" and added[0].definition_id=="flask:life","Sixtieth valid root admits one actual life flask")
	check(arena.state.successful_saves==saves+1,"XP and all rewards commit once")
	check(arena.flask_runtime.snapshot().charges_by_uid[life]==int(charges[life])+1 and arena.flask_runtime.snapshot().charges_by_uid[mana]==int(charges[mana])+1,"Eligible real root gives equipped bottles one charge")
	var locked:Dictionary=arena.flask_runtime.snapshot();var snapshot:Dictionary=arena.state.snapshot();var rng_state:int=arena.rng.state
	arena._damage_enemy(enemy,1.0,Color.WHITE)
	check(arena.flask_runtime.snapshot()==locked and arena.state.snapshot()==snapshot and arena.rng.state==rng_state,"Duplicate corpse cannot charge/drop again")
	var child:Dictionary=arena.monster_runtime.create_root("crawler",1,arena.player_pos+Vector2(55,0),"ordinary","",[],false);child.spawn=0.0;arena.enemies.append(child)
	arena._begin_progress_transaction();arena._damage_enemy(child,child.health+1.0,Color.WHITE);arena._end_progress_transaction()
	check(arena.flask_runtime.snapshot()==locked and arena.state.snapshot()==snapshot,"Zero-reward source cannot charge bottles or grant XP/items")
	var reloaded:=Model.new();check(reloaded.load_build() and reloaded.snapshot()==after,"Actual bottle UID and old rewards persist in same save")
