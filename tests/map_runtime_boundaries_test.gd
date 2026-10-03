extends SceneTree
const Compiler=preload("res://scripts/world/map_compiler.gd")
const Catalog=preload("res://scripts/world/map_catalog.gd")
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	seed(2828);var next:=randi();seed(2828)
	for map_id:String in Catalog.MAPS:
		for normal:Array in [[],["enemy_max_health_120"],["enemy_move_speed_110"],["enemy_max_health_120","enemy_move_speed_110"]]:
			for special:Array in [[],["frost_patrol"],["storm_patrol"]]:
				var profile:=Compiler.compile(map_id,normal,special)
				var allowed:bool=map_id=="broken_ruins" or special!=["storm_patrol"]
				check(profile.ok==allowed,"Map level limits actual special consumer")
				if profile.ok:
					check(Compiler.profile_reason(profile.profile).is_empty(),"Compiled map self-validates")
					for species:String in ["crawler","brute","skitter"]:
						var roll:Dictionary={"template":species,"rarity":"normal","mechanisms":[]};var before:=roll.duplicate(true)
						var result:=Compiler.special_template(profile.profile,roll)
						var expected:="frost_guard" if special==["frost_patrol"] and species=="brute" else "storm_skitter" if special==["storm_patrol"] and species=="skitter" else ""
						check(result==expected and roll==before,"Special replaces only matching original species without editing roll")
	for args:Array in [["bad",[],[]],["old_garden",["unknown"],[]],["old_garden",[],["frost_patrol","frost_patrol"]],["old_garden",[],[true]],["old_garden",["enemy_max_health_120","enemy_max_health_120"],[]]]:
		check(not Compiler.compile(args[0],args[1],args[2]).ok,"Invalid map clause atomically rejected")
	check(randi()==next,"Draft compilation and rejected clauses use no global RNG")
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false)
	var rng_before:int=arena.rng.state;var id_before:int=arena.monster_runtime.next_id
	check(not arena.enter_town_test(true).ok and arena.rng.state==rng_before and arena.monster_runtime.next_id==id_before,"Boolean revision cannot enter town")
	check(arena.enter_town_test(arena.world_context().revision).ok,"Enter explicit test profile")
	check(not arena.cast_group("group_000001") and not arena.use_flask("flask_1").ok,"Safe town does not consume attacks or flasks")
	var draft:Dictionary=arena.map_draft();rng_before=arena.rng.state;id_before=arena.monster_runtime.next_id
	check(not arena.craft_map("bad",[],[],draft.revision).ok and arena.map_draft()==draft and arena.rng.state==rng_before and arena.monster_runtime.next_id==id_before,"Rejected craft precedes RNG/IDs and preserves draft")
	var profiles:Dictionary={}
	for special:String in ["","frost_patrol","storm_patrol"]:
		check(arena.craft_map("broken_ruins",["enemy_max_health_120","enemy_move_speed_110"],[] if special.is_empty() else [special],arena.map_draft().revision).ok,"Craft combined clauses")
		arena.rng.seed=282801
		check(arena.start_map(arena.map_draft().revision).ok,"Start complete profile")
		while arena._map_run.can_admit():
			if arena._spawn_enemy().is_empty():check(false,"Ordinary admission must succeed");break
		profiles[special]={"enemies":arena.enemies.duplicate(true),"rng":arena.rng.state}
		check(arena._map_run.admitted.size()==36,"Finite36 target independent of modifier selection")
		var unchanged:Dictionary=arena.world_context();var snapshot:Dictionary=arena.state.snapshot()
		arena.start_monster_demo();arena.start_density_demo();arena.restore_standard_run()
		check(arena.world_context()==unchanged and arena.enemies.size()==36 and arena.state.snapshot()==snapshot,"Old demo controls cannot replace active map")
		rng_before=arena.rng.state;id_before=arena.monster_runtime.next_id
		check(arena._spawn_monster("missing_template").is_empty() and arena.rng.state==rng_before and arena.monster_runtime.next_id==id_before,"Factory failure rolls back random position and identity")
		var world_revision:int=arena.world_context().revision
		arena.alive=false;arena.restart_run()
		check(arena.alive and arena._map_run.admitted.size()==3 and arena._map_run.defeated.is_empty() and arena.world_context().revision>world_revision,"Death retry starts fresh finite map without stale target counters")
		check(not arena.return_to_town(world_revision).ok,"Prior confirmation invalid after retry")
		check(arena.return_to_town(arena.world_context().revision).ok,"Abandon/retry can return after saving")
	for special:String in ["frost_patrol","storm_patrol"]:
		var changed:=0
		check(profiles[special].rng==profiles[""].rng,"Special mapping adds no random draws")
		for index:int in range(36):
			var original:Dictionary=profiles[""].enemies[index];var modified:Dictionary=profiles[special].enemies[index]
			for field:String in ["kind","rarity","health","max_health","shield","max_shield","damage","speed","xp_reward","pos","reward_eligible","generation","mechanisms"]:
				check(original.get(field)==modified.get(field),"Special preserves rolled actor budget/rarity/mechanisms: "+field)
			if original.template_id=="ember_guard":check(modified.template_id=="ember_guard","Grey ash fixed admission retained")
			if original.template_id!=modified.template_id:
				changed+=1;check(modified.template_id==("frost_guard" if special=="frost_patrol" else "storm_skitter"),"Actual natural special template reached")
		check(changed>0,"Special has a real natural spawn consumer")
	arena.test_supply_enabled=false
	check(not arena.town_buy("skill:bolt",arena.state.revision()).ok,"Supply switch actually blocks authority")
	for row:Dictionary in arena.town_stock("skill_merchant"):check(not row.available,"Disabled test supply reflected in metadata")
	print("Map runtime boundaries: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
