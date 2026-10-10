extends SceneTree
## Real Main, formal II/III entry; fixture progression and lethal probes are QA controls.
const Fixture=preload("res://tests/fixtures/v083/ginkgo_journey_fixture.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
var arena:Node
var selected:Dictionary={}
var checks:=0
var failures:=0
var completed:=0
var report:Dictionary={"method":"Actual Main with genuine migrated v49 fixture. Prior-tier unlocks use existing model transactions. RNG seed, high player health, stationary nonselected actors and lethal settlements are controlled QA probes, not natural combat footage.","tiers":[]}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
	return ok
func actor(id:int)->Dictionary:
	for enemy:Dictionary in arena.enemies:
		if enemy.id==id:return enemy
	return {}
func prepare()->Dictionary:
	arena.telegraphs.reset();arena.freeze_runtime.reset();arena.burn_runtime.reset();arena.shock_runtime.reset();arena.chill_runtime.reset()
	arena.telegraph_trace.clear();arena.incoming_damage_trace.clear()
	arena.projectile_runtime.cancel_all(arena.projectiles)
	selected.pos=arena.map_spawn_records()[2].position;selected.spawn=0.0;selected.attack_timer=0.0;selected.knockback=Vector2.ZERO
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
func kill(enemy:Dictionary)->void:
	if enemy.health<=0.0:return
	enemy.spawn=0.0
	var result:=Defense.incoming_hit({"physical":1e9},{},enemy.shield,enemy.health,"monster")
	if check(result.ok,"Existing defense admits controlled lethal settlement"):arena._apply_enemy_settlement(enemy,result,Color.WHITE)
func probe(tier:int)->void:
	var ready:Dictionary=Fixture.prepare(arena.state,arena.build_save_path,tier)
	if not check(ready.ok,"Genuine fixture and real prior-tier transactions"):return
	var sequence:int=arena.state.normal_journey().next_run_id
	var found:=false
	# Bounded witness search changes only private QA RNG seed, never roster contents.
	for seed_value:int in range(1,17):
		arena.rng.seed=seed_value
		var plan:Dictionary=arena._prepare_camp_run(ready.profile,sequence)
		if plan.ok and plan.spawn_records[2].template_id=="storm_skitter" and plan.roots[2].rarity=="normal":found=true;break
	if not check(found,"Bounded actual-entry seed has target witness"):return
	var seed_before:int=arena.rng.seed;var rng_before:int=arena.rng.state
	var balance:int=arena.state.crafting_balance()
	if not check(arena.craft_normal_map("ginkgo_arcade",tier,[],[],arena.map_draft().revision).ok,"Actual formal draft"):return
	if not check(arena.start_map(arena.map_draft().revision).ok,"Actual formal entry"):return
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	for unused:int in range(4):arena.hud.close_panel()
	var records:Array=arena.map_spawn_records();selected=actor(records[2].actor_id)
	check(records.size()==37 and arena.enemies.size()==37 and arena._map_run.snapshot().admitted==36,"All unchanged root admissions")
	check(selected.template_id=="storm_skitter" and selected.map_outpost_id=="camp_west_1" and selected.generation==0 and selected.reward_eligible,"Actual third west root uses existing storm template")
	check(arena.rng.state==rng_before and arena.state.crafting_balance()==balance-int(ready.profile.fee),"Entry keeps gameplay RNG and existing exact fee")
	var roots_before:int=arena.state.normal_journey().normal_root_kills
	var rewards_before:int=arena.reward_kills
	for enemy:Dictionary in arena.enemies:enemy.speed=0.0;enemy.attack_timer=1000.0
	var attack:=prepare()
	if attack.is_empty():return
	check(attack.center==arena.player_pos and attack.profile.windup_seconds==0.7 and attack.profile.radius==65.0,"Existing 0.7 second radius65 warning locks initial player position")
	arena.tick(0.699)
	check(arena.telegraph_trace.is_empty() and arena.health==10000.0,"Warning deals no early damage")
	arena.tick(0.0011)
	check(arena.telegraph_trace.size()==1 and arena.telegraph_trace[0].applied and arena.health<10000.0,"Staying in warning takes one actual lightning hit")
	var shock:Dictionary=arena.shock_runtime.status_at("player",0,arena.elapsed)
	check(shock.ok and shock.active and shock.hit_damage_taken_increased==0.15,"Actual hit applies existing player shock")
	var stay:Array=arena.telegraph_trace.duplicate(true)
	attack=prepare()
	if attack.is_empty():return
	var start:Vector2=arena.player_pos
	Input.action_press("move_down")
	for step:int in range(30):arena.tick(1.0/60.0)
	Input.action_release("move_down")
	check(arena.player_pos.distance_to(start)>65.0+arena.PLAYER_RADIUS and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Held input leaves warning through actual legal movement")
	arena.tick(0.201)
	check(arena.telegraph_trace.size()==1 and not arena.telegraph_trace[0].applied and arena.health==10000.0,"Leaving locked circle avoids actual damage")
	var dodge:Array=arena.telegraph_trace.duplicate(true)
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
	report.tiers.append({"tier":tier,"rng_seed":seed_before,"selected_spawn_key":selected.map_spawn_key,"stay_trace":stay,"dodge_trace":dodge,"descendants":descendants,"root_rewards":37,"claimed_shards":claim.get("claimed_shards")})
	completed+=1
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-west-storm-main-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	for tier:int in [2,3]:probe(tier)
	check(completed==2,"Both full Main probes finish")
	report.checks=checks;report.failures=failures;report.completed=completed
	FileAccess.open("res://docs/qa/ginkgo-west-storm/main-result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true)+"\n")
	print("GINKGO_WEST_STORM_MAIN checks=%d failures=%d completed=%d"%[checks,failures,completed])
	arena.queue_free();quit(1 if failures else 0)
