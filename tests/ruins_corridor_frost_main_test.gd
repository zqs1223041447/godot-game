extends "res://tests/ginkgo_west_storm_main_test.gd"
## Reuse existing Main test check/actor/kill helpers; this fixture targets a cold corridor.
const Maps=preload("res://scripts/world/map_compiler.gd")
const Frost=preload("res://scripts/world/broken_ruins_roster_rules.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const ORACLE="res://docs/qa/ruins-corridor-frost/map_camp_state_8740385.gd.txt"
var old_script:GDScript
var selected_record:=-1
func prepare()->Dictionary:
	arena.telegraphs.reset();arena.freeze_runtime.reset();arena.burn_runtime.reset();arena.shock_runtime.reset();arena.chill_runtime.reset()
	arena.telegraph_trace.clear();arena.incoming_damage_trace.clear()
	arena.projectile_runtime.cancel_all(arena.projectiles)
	selected.pos=arena.map_spawn_records()[selected_record].position;selected.spawn=0.0;selected.attack_timer=0.0;selected.knockback=Vector2.ZERO
	arena.player_pos=selected.pos+Vector2(0,100)
	arena._stats=arena.state.get_stats()
	for field:String in ["life_regen","mana_regen","shield_regen","shield_regeneration_rate","shield_recharge_rate"]:arena._stats[field]=0.0
	arena._stats.max_health=10000.0;arena._stats.max_shield=0.0;arena._stats.evasion=0.0
	arena.health=10000.0;arena.shield=0.0;arena.invulnerable=0.0;arena._player_evasion_entropy=99.0;arena._burn_immunity_until=arena.elapsed
	arena.tick(0.0)
	var attack:Dictionary=arena.telegraphs.state_for(selected.id)
	check(not attack.is_empty() and selected.exploration_awake,"Proximity wakes actual selected root and starts existing attack")
	selected.attack_timer=1000.0
	return attack
func combination_probe()->Dictionary:
	var ember:Dictionary=actor(arena.map_spawn_records()[23].actor_id)
	if not check(ember.template_id=="ember_guard" and ember.map_outpost_id==selected.map_outpost_id,"Original reserved ember shares the selected eight-root outpost"):return {}
	prepare();arena.telegraphs.reset();arena.telegraph_trace.clear()
	arena.player_pos=(selected.pos+ember.pos)*0.5
	selected.attack_timer=0.0;ember.spawn=0.0;ember.attack_timer=1000.0
	arena.tick(0.0);selected.attack_timer=1000.0
	if not check(not arena.telegraphs.state_for(selected.id).is_empty(),"Natural pair positions admit frost at the midpoint"):return {}
	arena.tick(0.9001)
	if not check(not arena.chill_runtime.status(arena.elapsed).is_empty(),"Pair probe first receives actual cold slow"):return {}
	ember.attack_timer=0.0;arena.tick(0.0);ember.attack_timer=1000.0
	var fire:Dictionary=arena.telegraphs.state_for(ember.id)
	if not check(not fire.is_empty() and fire.center==arena.player_pos,"Existing reserved ember locks subsequent fire warning at natural pair positions"):return {}
	var start:Vector2=arena.player_pos;var at:float=arena.elapsed;var speed:float=arena._stats.move_speed
	Input.action_press("move_right")
	for step:int in range(41):arena.tick(1.0/60.0)
	Input.action_release("move_right")
	check(not arena.chill_runtime.status(arena.elapsed).is_empty(),"Player remains slowed throughout follow-up dodge")
	check(arena.player_pos.distance_to(start)>float(fire.profile.radius)+arena.PLAYER_RADIUS,"Slowed held movement still clears the original fire circle before its deadline")
	arena.tick(0.017)
	var frost_event:Dictionary={};var fire_event:Dictionary={}
	for event:Dictionary in arena.telegraph_trace:
		if event.source_id==selected.id:frost_event=event
		if event.source_id==ember.id:fire_event=event
	check(not frost_event.is_empty() and frost_event.applied and not fire_event.is_empty() and not fire_event.applied,"Actual same-outpost combination resolves frost hit and avoidable subsequent fire")
	return {"frost_id":selected.id,"ember_id":ember.id,"from":start,"to":arena.player_pos,"base_move_speed":speed,"elapsed":arena.elapsed-at,"events":arena.telegraph_trace.duplicate(true)}
func wall_probe()->void:
	arena.telegraphs.reset();arena.telegraph_trace.clear()
	var wall:Rect2=arena.world_geometry().walls[0]
	selected.pos=Vector2(wall.end.x+selected.radius+2.0,wall.get_center().y)
	arena.player_pos=Vector2(wall.position.x-arena.PLAYER_RADIUS-2.0,wall.get_center().y)
	selected.spawn=0.0;selected.attack_timer=0.0
	check(arena._geometry.is_clear(selected.pos,selected.radius) and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Real opposite-wall positions fit original geometry")
	check(selected.pos.distance_to(arena.player_pos)<150.0 and not arena._terrain_visible(selected.pos,arena.player_pos),"Original wall blocks LOS inside frost trigger range")
	arena._start_enemy_telegraphs()
	check(arena.telegraphs.state_for(selected.id).is_empty(),"Existing wall prevents actual frost attack admission")
	selected.pos=arena.map_spawn_records()[selected_record].position;selected.attack_timer=1000.0
func probe(tier:int)->void:
	var ready:Dictionary=Fixture.prepare(arena.state,arena.build_save_path,1)
	if not check(ready.ok,"Genuine migrated fixture"):return
	for prior:int in range(1,tier):
		var prior_profile:Dictionary=Maps.compile_normal("broken_ruins",prior,[],[]).profile
		var opened:Dictionary=arena.state.normal_start_map(prior_profile,arena.state.revision(),arena.build_save_path)
		if not check(opened.ok,"Existing prior-tier start transaction"):return
		if not check(arena.state.normal_complete_map(opened.run_id,arena.state.revision(),arena.build_save_path).ok,"Existing prior-tier completion transaction"):return
		if not check(arena.state.normal_claim_rewards(arena.state.revision(),arena.build_save_path).ok,"Existing prior-tier reward transaction"):return
	ready.profile=Maps.compile_normal("broken_ruins",tier,[],[]).profile
	var sequence:int=arena.state.normal_journey().next_run_id
	var found:=false
	for seed_value:int in range(1,17):
		arena.rng.seed=seed_value
		var plan:Dictionary=arena._prepare_camp_run(ready.profile,sequence)
		if not plan.ok:continue
		var old:RefCounted=old_script.new()
		if not old.begin(ready.profile,plan.landmarks,plan.state.checkpoint().seed,Monsters.CURRENT_ROLL_POLICY).ok:continue
		var candidate:int=Frost.corridor_frost_index(ready.profile,"camp_north",old.entries("camp_north"))
		if candidate>=0:selected_record=12+candidate;found=true;break
	if not check(found,"Bounded seed has actual newly changed corridor root"):return
	var seed_before:int=arena.rng.seed;var rng_before:int=arena.rng.state
	var balance:int=arena.state.crafting_balance()
	if not check(arena.craft_normal_map("broken_ruins",tier,[],[],arena.map_draft().revision).ok,"Actual formal draft"):return
	if not check(arena.start_map(arena.map_draft().revision).ok,"Actual formal entry"):return
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	for unused:int in range(4):arena.hud.close_panel()
	var records:Array=arena.map_spawn_records();selected=actor(records[selected_record].actor_id)
	check(records.size()==37 and arena.enemies.size()==37 and arena._map_run.snapshot().admitted==36,"All unchanged root admissions")
	check(selected.template_id=="frost_guard" and selected.map_outpost_id=="camp_north_2" and selected.generation==0 and selected.reward_eligible,"Actual selected corridor root uses existing frost template")
	check(arena.rng.state==rng_before and arena.state.crafting_balance()==balance-int(ready.profile.fee),"Entry keeps gameplay RNG and existing exact fee")
	var roots_before:int=arena.state.normal_journey().normal_root_kills
	var rewards_before:int=arena.reward_kills
	for enemy:Dictionary in arena.enemies:enemy.speed=0.0;enemy.attack_timer=1000.0
	var attack:=prepare()
	if attack.is_empty():return
	check(attack.center==arena.player_pos and attack.profile.windup_seconds==0.9 and attack.profile.radius==90.0,"Existing 0.9 second radius90 warning locks initial player position")
	arena.tick(0.899)
	check(arena.telegraph_trace.is_empty() and arena.health==10000.0,"Warning deals no early damage")
	arena.tick(0.0011)
	check(arena.telegraph_trace.size()==1 and arena.telegraph_trace[0].applied and arena.health<10000.0,"Staying in warning takes one actual cold hit")
	var chill:Dictionary=arena.chill_runtime.status(arena.elapsed)
	if not check(not chill.is_empty(),"Actual cold loss applies existing chill"):return
	check(chill.movement_multiplier==0.75 and is_equal_approx(chill.expires_at-chill.applied_at,1.2),"Existing chill is25percent for1.2seconds, without freeze")
	var slow_start:Vector2=arena.player_pos
	var speed:float=arena._stats.move_speed
	Input.action_press("move_down");arena.tick(0.2);Input.action_release("move_down")
	check(absf(arena.player_pos.distance_to(slow_start)-speed*0.2*0.75)<0.01,"Real movement pays exact existing25percent slow")
	check(arena.freeze_runtime.is_empty(),"Frost guard does not introduce freezing")
	var stay:Array=arena.telegraph_trace.duplicate(true)
	attack=prepare()
	if attack.is_empty():return
	var start:Vector2=arena.player_pos
	Input.action_press("move_down")
	for step:int in range(45):arena.tick(1.0/60.0)
	Input.action_release("move_down")
	check(arena.player_pos.distance_to(start)>90.0+arena.PLAYER_RADIUS and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Held input leaves warning through actual legal movement")
	arena.tick(0.151)
	check(arena.telegraph_trace.size()==1 and not arena.telegraph_trace[0].applied and arena.health==10000.0,"Leaving locked circle avoids actual damage")
	var dodge:Array=arena.telegraph_trace.duplicate(true)
	var combination:=combination_probe()
	if not check(not combination.is_empty(),"Combination probe completes"):return
	wall_probe()
	arena._begin_progress_transaction();kill(selected);arena._end_progress_transaction()
	check(arena.reward_kills==rewards_before+1 and arena.state.normal_journey().normal_root_kills==roots_before+1,"Selected root pays ordinary reward and progression once")
	var reward_rng:int=arena.rng.state
	arena._finish_enemy_death(selected)
	check(arena.reward_kills==rewards_before+1 and arena.rng.state==reward_rng,"Repeated selected death cannot duplicate drops or RNG")
	arena._begin_progress_transaction()
	for enemy:Dictionary in arena.enemies.duplicate():kill(enemy)
	arena._flush_monster_spawns();arena._check_map_complete()
	var descendants:=0
	for enemy:Dictionary in arena.enemies:
		if enemy.generation>0 and enemy.health>0.0:
			descendants+=1
			check(not enemy.reward_eligible and enemy.xp_reward==0,"Death descendants retain nonreward lineage")
	check(descendants>=4 and not arena._map_run.complete,"Living descendants block clear after every root dies")
	for pass_index:int in range(3):
		for enemy:Dictionary in arena.enemies.duplicate():kill(enemy)
		arena._flush_monster_spawns()
	arena._check_map_complete();arena._end_progress_transaction()
	check(arena._map_run.complete and arena.world_context().mode=="map_complete" and arena.monster_runtime.queue.is_empty(),"All roots and descendants settle actual complete map")
	check(arena.reward_kills==rewards_before+37 and arena.state.normal_journey().normal_root_kills==roots_before+37,"Exactly37 root rewards; descendants do not multiply progression")
	check(arena.map_spawn_records()==records,"All initial spawn identities persist through death")
	check(arena.world_context().pending_map_reward.shards==int(ready.profile.completion_reward),"Existing tier completion reward is unchanged")
	check(Rules.reason(arena.state.snapshot()).is_empty() and arena.state.snapshot().version==61,"Current schema61 remains valid without migration")
	check(arena.return_to_town(arena.world_context().revision).ok,"Actual return to formal town")
	var claim:Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	check(claim.ok and claim.claimed_shards==int(ready.profile.completion_reward),"Existing reward claim once")
	var after:int=arena.state.crafting_balance()
	var repeat:Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	check(int(repeat.get("claimed_shards",0))==0 and arena.state.crafting_balance()==after,"Repeated claim cannot duplicate shards")
	report.tiers.append({"tier":tier,"rng_seed":seed_before,"selected_spawn_key":selected.map_spawn_key,"combination":combination,"chill":chill,"stay_trace":stay,"dodge_trace":dodge,"descendants":descendants,"root_rewards":37,"claimed_shards":claim.get("claimed_shards")})
	completed+=1
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-ruins-frost-main-"):quit(78);return
	if not check(FileAccess.get_sha256(ORACLE)=="5b49600164356fa94fdbb10115d3b07b7d9193aa9212db6d85dbb0a79e86174b","Exact pre-change entry oracle"):quit(1);return
	old_script=GDScript.new();old_script.source_code=FileAccess.get_file_as_string(ORACLE).replace("class_name MapCampState\n","")
	if not check(old_script.reload()==OK,"Entry witness oracle loads"):quit(1);return
	report.method="Actual Main formal broken_ruins II/III with genuine migrated fixture and model-transaction prior unlocks. Seed selection, health, stationary actors, wall-side placement and lethal settlements are QA controls, not natural footage."
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	for tier:int in [2,3]:probe(tier)
	check(completed==2,"Both full Main probes finish")
	report.checks=checks;report.failures=failures;report.completed=completed
	FileAccess.open("res://docs/qa/ruins-corridor-frost/main-result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true)+"\n")
	print("RUINS_CORRIDOR_FROST_MAIN checks=%d failures=%d completed=%d"%[checks,failures,completed])
	arena.queue_free();quit(1 if failures else 0)
