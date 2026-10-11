extends SceneTree
## Controlled Main deaths, not a natural combat/ownership demonstration.
## Run unchanged with REWARD_POLICY_MAIN pointing to HEAD's frozen main.gd,
## then with the candidate. REWARD_POLICY_ORACLE compares exact observations.
const Model = preload("res://scripts/canonical_game_state.gd")
class FaultModel extends Model:
	var fail_write := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_write else super._write_bytes(path,bytes)
var checks := 0
var failures := 0
var rows: Array = []
var arena: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func observation() -> Dictionary:
	return {"state":var_to_bytes(arena.state.snapshot()).hex_encode(),"rng":str(arena.rng.state),
		"kills":arena.kills,"reward_kills":arena.reward_kills,"charges":arena.flask_runtime.snapshot(),
		"runtime":var_to_bytes(arena.EncounterAdmission._snapshot(arena.monster_runtime)).hex_encode(),
		"pickups":var_to_bytes(arena.pickups).hex_encode(),"health":arena.health,"mana":arena.mana,
		"run":arena._map_run.snapshot(),"world_revision":arena._world_revision,
		"disk":FileAccess.get_file_as_bytes(arena.build_save_path).hex_encode() if FileAccess.file_exists(arena.build_save_path) else "",
		"saves":arena.state.successful_saves,"attempts":arena.state.save_attempts,"dirty":arena._progress_save_dirty}
func fresh(test_profile: bool) -> void:
	for path: String in ["user://build_save.json","user://town_test_build_save.json"]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var main_path: String=OS.get_environment("REWARD_POLICY_MAIN")
	arena=load("res://scripts/main.gd" if main_path.is_empty() else main_path).new()
	arena.state=FaultModel.new()
	arena.build_save_path="user://town_test_build_save.json" if test_profile else "user://build_save.json"
	root.add_child(arena)
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	arena.enemies.clear();arena.monster_runtime.reset();arena.telegraphs.reset()
	arena._world_mode="arena"
	arena.rng.seed=1771238
	arena.health=10.0;arena.mana=0.0
func kill(enemy: Dictionary) -> void:
	enemy.spawn=0.0
	arena._damage_enemy(enemy,float(enemy.health)+float(enemy.get("shield",0.0))+1.0,Color.WHITE)
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/reward-policy-"):
		printerr("Requires isolated /tmp/reward-policy-* XDG_DATA_HOME");quit(78);return
	for test_profile: bool in [false,true]:
		for initial: int in [0,58,118]:
			fresh(test_profile)
			arena.reward_kills=initial
			if not test_profile:
				var fixture: Dictionary=arena.state.snapshot()
				fixture.journey.normal_root_kills=initial
				arena.state._accept_memory(fixture)
			arena._sync_flasks()
			# Consume existing equipped charges without introducing inventory grants.
			for slot: Dictionary in arena.state.flask_slots():
				if not slot.uid.is_empty():arena.flask_runtime.use(slot.uid,0.0,100.0,arena._stats)
			arena.state.fail_write=initial==118
			arena._begin_progress_transaction()
			for i: int in range(8):
				var boss: bool=i%4==3
				var enemy: Dictionary=arena.monster_runtime.create_root("rift_warden" if boss else "crawler",1,Vector2(180+i*5,180),"level_boss" if boss else "ordinary",["normal","magic","rare","boss"][i%4],[],true)
				check(not enemy.is_empty(),"Controlled actor fixture is admitted")
				arena.enemies.append(enemy)
				if i==0:enemy.death_spawns=[{"template":"crawler","count":2}]
				kill(enemy)
				var once: Dictionary=observation()
				arena._finish_enemy_death(enemy)
				check(observation()==once,"Repeated death changes no reward, state, ledger or RNG")
				rows.append({"test":test_profile,"initial":initial,"death":i,"result":once})
			var rewards_before: int=arena.reward_kills
			for child: Dictionary in arena.monster_runtime.drain(10,arena.ARENA):kill(child)
			check(arena.reward_kills==rewards_before,"Derived actors receive no rewards")
			arena.demo_mode=true
			var demo: Dictionary=arena.monster_runtime.create_root("crawler",1,Vector2(240,180),"ordinary","rare",[],true)
			kill(demo)
			check(arena.reward_kills==rewards_before,"Demo roots receive no rewards")
			arena.demo_mode=false
			arena._end_progress_transaction()
			rows.append({"after_batch":observation()})
			if arena.state.fail_write:
				arena.state.fail_write=false
				check(arena._flush_progress(true),"Failed save retries through existing path")
				rows.append({"after_retry":observation()})
			arena.queue_free();await process_frame
	await map_rejections()
	await rewardless_malformed_xp()
	var serialized: String=JSON.stringify(rows,"\t",true,true)
	var output: String=OS.get_environment("REWARD_POLICY_OUTPUT")
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		check(file!=null,"Evidence file opens")
		if file!=null:file.store_string(serialized)
	var oracle: String=OS.get_environment("REWARD_POLICY_ORACLE")
	if not oracle.is_empty():check(serialized==FileAccess.get_file_as_string(oracle),"Exact HEAD/candidate state, RNG, charges, ledger, rewards and disk equivalence")
	print("KILL_REWARD_EQUIVALENCE checks=%d failures=%d observations=%d" % [checks,failures,rows.size()])
	quit(1 if failures else 0)
func map_rejections() -> void:
	fresh(false)
	arena._world_mode="normal"
	check(arena.enter_normal_town(arena.world_context().revision).ok,"Use current formal-town entry contract")
	check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok,"Draft free formal map")
	check(arena.start_map(arena.map_draft().revision).ok,"Admit actual formal birth records")
	if arena.enemies.is_empty():
		arena.queue_free();await process_frame;return
	arena.set_process(false);arena.hud.set_process(false);arena.rng.seed=1771238
	var enemy: Dictionary=arena.enemies[0]
	enemy.death_spawns=[{"template":"crawler","count":2}]
	var original_health: float=enemy.health
	var original_key: String=enemy.map_spawn_key
	enemy.health=0.0
	for route: Variant in ["future_unsupported",""]:
		arena._map_spawn_records[enemy.root_id].reward_route=route
		var before: Dictionary=observation()
		arena._finish_enemy_death(enemy)
		check(observation()==before and not enemy.death_processed and not arena._encounter_error.is_empty(),"Unknown route rejects before lineage, rewards, save or RNG")
		rows.append({"rejected_route":route,"result":observation()})
	# HEAD used an unsafe mixed-type comparison; candidate must explicitly reject
	# malformed routes too. These additional probes do not enter the shared oracle.
	if OS.get_environment("REWARD_POLICY_MAIN").is_empty():
		for route: Variant in [null,7,{},[]]:
			arena._map_spawn_records[enemy.root_id].reward_route=route
			var unchanged: Dictionary=observation()
			arena._finish_enemy_death(enemy)
			check(observation()==unchanged and not enemy.death_processed,"Malformed route rejects before all death/reward mutations")
	arena._map_spawn_records[enemy.root_id].reward_route="standard"
	enemy.map_spawn_key="tampered"
	var before: Dictionary=observation()
	arena._finish_enemy_death(enemy)
	check(observation()==before and not enemy.death_processed,"Tampered spawn binding rejects atomically")
	enemy.health=original_health;enemy.map_spawn_key=original_key;arena._encounter_error=""
	arena._begin_progress_transaction()
	for actor: Dictionary in arena.enemies:kill(actor)
	arena._end_progress_transaction()
	check(arena.reward_kills==25 and arena._map_run.defeated.size()==24,"Actual map roots advance independent finite progress and standard rewards")
	rows.append({"formal_roots":observation()})
	var rewards_before: int=arena.reward_kills
	for child: Dictionary in arena.monster_runtime.drain(10,arena.ARENA):
		child.map_spawn_key=original_key
		kill(child)
	check(arena.reward_kills==rewards_before,"Map descendants resolve original source without payout")
	rows.append({"formal_descendants":observation()})
	check(arena.return_to_town(arena.world_context().revision).ok,"Actual return clears the map")
	check(arena.map_spawn_records().is_empty() and arena.map_mechanism_state()=={"config":{},"optional_encounters":[]},"Map exit clears admitted sources and mechanism shell")
	rows.append({"returned":observation()})
	arena.queue_free();await process_frame

func rewardless_malformed_xp() -> void:
	for test_profile: bool in [false,true]:
		for demo: bool in [false,true]:
			fresh(test_profile)
			arena.demo_mode=demo
			var enemy: Dictionary=arena.monster_runtime.create_root("crawler",1,Vector2(180,180),"ordinary","normal",[],true)
			enemy.health=0.0
			if not demo:
				# A real reserved/drained descendant, not a manually flipped flag.
				enemy.death_spawns=[{"template":"crawler","count":1}]
				arena.monster_runtime.process_death(enemy)
				enemy=arena.monster_runtime.drain(1,arena.ARENA)[0]
				check(enemy.generation==1 and not enemy.reward_eligible,"Actual descendant is rewardless")
				enemy.health=0.0
			enemy.xp_reward={}
			var before: Dictionary=observation()
			arena._finish_enemy_death(enemy)
			var after: Dictionary=observation()
			check(enemy.death_processed and arena.kills==1 and arena.reward_kills==0,"Malformed unused XP does not interrupt rewardless death")
			check(after.state==before.state and after.disk==before.disk and after.charges==before.charges,"Rewardless death preserves state, saved bytes and charges")
			check(after.rng!=before.rng,"Rewardless death still executes original tail particle RNG")
			arena._finish_enemy_death(enemy)
			check(observation()==after,"Rewardless malformed XP death remains once-only")
			rows.append({"rewardless_malformed_xp":{"test":test_profile,"demo":demo,"result":after}})
			arena.queue_free();await process_frame
