extends SceneTree
## Actual Main, fresh formal map, held-input dodge and controlled status/death probes.
## Runtime setup positions/resources are explicit QA controls, not natural footage.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Frost = preload("res://scripts/combat/frost_lock_rules.gd")
var arena: Node
var boss: Dictionary = {}
var birth := Vector2.ZERO
var started_at := 0.0
var checks := 0
var failures := 0
var labels: Array[String] = []
var group := "entry"
var report: Dictionary = {"method":"Actual main.tscn, current lawful fresh formal character and full resident roster. Held-input leave/reenter uses real ticks. Boundary, wall, freeze, health and death controls are integration probes, not natural combat footage.","groups":{},"entries":[]}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		labels.append(group + ": " + label)
		printerr("FAIL [%s]: %s" % [group,label])
	return ok
func accepted(value: Dictionary, label: String) -> bool:
	return check(bool(value.get("ok",false)),label+": "+JSON.stringify(value))
func near(actual: float, expected: float, label: String) -> bool:
	return check(absf(actual-expected)<0.00001,"%s: %.9f vs %.9f" % [label,actual,expected])
func pause() -> void:
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire=false
	for unused: int in range(4): arena.hud.close_panel()
func actor(id: int) -> Dictionary:
	for enemy: Dictionary in arena.enemies:
		if int(enemy.id)==id:return enemy
	return {}
func ids() -> Array[int]:
	var result: Array[int]=[]
	for enemy: Dictionary in arena.enemies:result.append(int(enemy.id))
	return result
func save_json(name: String, value: Variant) -> bool:
	var file:=FileAccess.open(OS.get_environment("GINKGO_RING_MAIN_OUTPUT").path_join(name),FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(json_value(value),"\t",true,true));file.close();return true
func json_value(value: Variant) -> Variant:
	if value is Vector2:return [value.x,value.y]
	if value is Rect2:return {"position":json_value(value.position),"size":json_value(value.size)}
	if value is Array:
		var array: Array=[]
		for item: Variant in value:array.append(json_value(item))
		return array
	if value is Dictionary:
		var object: Dictionary={}
		for key: Variant in value:object[key]=json_value(value[key])
		return object
	return value
func capture(extra: Dictionary = {}) -> void:
	var row: Dictionary={"trace":arena.telegraph_trace.duplicate(true),"damage":arena.incoming_damage_trace.duplicate(true),"attack":arena.telegraphs.state_for(int(boss.get("id",0))),"player":arena.player_pos,"elapsed":arena.elapsed,"health":arena.health,"shield":arena.shield}
	row.merge(extra,true);report.groups[group]=row
func enter() -> bool:
	var next_id: int=arena.monster_runtime.next_id
	var rng_before: int=arena.rng.state
	if not accepted(arena.craft_normal_map("ginkgo_arcade",1,[],[],arena.map_draft().revision),"Formal free tierI draft"):return false
	if not accepted(arena.start_map(arena.map_draft().revision),"Actual formal map entry"):return false
	pause()
	boss=actor(arena._map_run.boss_id)
	if not check(not boss.is_empty(),"Resident natural boss exists"):return false
	birth=arena.world_geometry().landmarks.boss.center
	var records: Array=arena.map_spawn_records()
	check(arena.enemies.size()==37 and records.size()==37 and arena.world_context().initial_monsters==37,"All 36 ordinary roots and boss are resident at entry")
	check(arena.monster_runtime.next_id==next_id+37 and arena.rng.state==rng_before,"Formal initial allocation keeps exact root count and gameplay RNG")
	check(boss.pos==birth and birth-arena.ARENA.position==Vector2(3180,320),"Authored boss birth remains relative (3180,320)")
	check(arena._map_run.snapshot().admitted==36 and arena.world_context().awake_monsters==0,"Original finite ledger and sleeping admission remain intact")
	check(boss.map_boss_attack_id=="ginkgo_shelter_slam" and boss.generation==0 and boss.root_id==boss.id and boss.reward_eligible,"Original authoritative root owns the Ginkgo policy")
	for record: Dictionary in records:
		var enemy: Dictionary=actor(record.actor_id)
		if not check(not enemy.is_empty(),"Spawn record resolves existing root"):return false
		check(enemy.id==record.root_id and enemy.map_spawn_key==record.spawn_key and enemy.pos==record.position and record.reward_route=="standard" and enemy.generation==0 and enemy.reward_eligible,"Actual spawn identity, geometry and standard reward route preserved")
	report.entries.append({"boss":boss.duplicate(true),"policy":Monsters.telegraph_policy(boss),"records":records,"ids":ids(),"rng":rng_before,"schema":arena.state.snapshot().version,"wave":arena.wave})
	if report.entries.size()==1:check(save_json("formal-initial-save.json",arena.state.snapshot()),"Isolated lawful initial model snapshot retained for read-only documentation")
	# Birth protection elapses through Main. Remote roots remain present and asleep.
	arena.tick(0.7)
	check(boss.spawn==0.0 and not boss.exploration_awake,"Actual tick expires natural boss birth protection without waking it")
	# Stationary surrounding actors are a bounded fixture control, never deletions.
	for enemy: Dictionary in arena.enemies:
		if enemy.id!=boss.id:enemy.speed=0.0;enemy.attack_timer=1000.0
	return true
func prepare(source: Vector2 = Vector2.INF, distance: float = 100.0) -> Dictionary:
	arena.telegraphs.reset();arena.freeze_runtime.reset();arena.burn_runtime.reset();arena.shock_runtime.reset();arena.chill_runtime.reset()
	arena.projectile_runtime.cancel_all(arena.projectiles)
	arena.telegraph_trace.clear();arena.incoming_damage_trace.clear()
	boss.pos=birth if source==Vector2.INF else source
	boss.spawn=0.0;boss.attack_timer=0.0;boss.knockback=Vector2.ZERO
	arena.player_pos=boss.pos+Vector2(0,distance)
	arena._stats=arena.state.get_stats()
	for field: String in ["life_regen","mana_regen","shield_regen","shield_regeneration_rate","shield_recharge_rate"]:arena._stats[field]=0.0
	arena._stats.max_health=10000.0;arena._stats.max_shield=1000.0;arena._stats.evasion=0.0
	arena.health=10000.0;arena.shield=5.0;arena.invulnerable=0.0;arena.damage_delay=0.0;arena._player_evasion_entropy=99.0
	arena._burn_immunity_until=arena.elapsed
	if not check(arena._geometry.is_clear(boss.pos,boss.radius) and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Controlled initial actor positions are legal"):return {}
	var rng_before: int=arena.rng.state
	# Zero-width actual tick wakes by proximity/LOS and performs real attack admission.
	arena.tick(0.0)
	var attack: Dictionary=arena.telegraphs.state_for(boss.id)
	if not check(boss.exploration_awake and not attack.is_empty(),"Actual Main wakes and locks living natural boss"):return {}
	check(arena.rng.state==rng_before,"Actual wake and telegraph start consume no gameplay RNG")
	check(attack.center==boss.pos and attack.visual_pattern=="ginkgo_shelter_slam","Self-at-start center and sequence authority lock once")
	boss.attack_timer=1000.0 # Prevent a fresh action after this action's recovery.
	started_at=arena.elapsed
	return attack
func tick_to(age: float) -> void:
	var remaining: float=started_at+age-arena.elapsed
	if remaining>0.0:arena.tick(remaining)
func events(count: int, label: String) -> bool:
	return check(arena.telegraph_trace.size()==count,label)
func pair() -> bool:
	if not events(2,"Exactly two sequence events"):return false
	var first: Dictionary=arena.telegraph_trace[0]
	var second: Dictionary=arena.telegraph_trace[1]
	check(first.type=="circle_attack" and first.shape=="circle" and first.radius==130.0 and first.pulse_index==0,"First event is radius130 inner circle")
	check(second.type=="annulus_attack" and second.shape=="annulus" and second.inner_radius==130.0 and second.radius==240.0 and second.pulse_index==1,"Second event is the 130-to-240 annulus")
	check(first.attack_id==second.attack_id and first.source_id==boss.id and second.source_id==boss.id and first.center==second.center,"Both phases preserve one attack, source and frozen center")
	near(first.attack_age,1.4,"First local deadline remains 1.4")
	near(second.attack_age,2.4,"Second local deadline remains 2.4")
	var contact: Dictionary=Monsters.contact_components(boss)
	for element: String in contact:
		near(first.packet.base[element],contact[element]*0.6,"First frozen component budget: "+element)
		near(second.packet.base[element],contact[element]*0.6,"Second frozen component budget: "+element)
	return true
func walk_vertical(target_y: float) -> Dictionary:
	var before: Vector2=arena.player_pos
	var ticks:=0
	var action: String="move_down" if target_y>before.y else "move_up"
	Input.action_press(action)
	while absf(arena.player_pos.y-target_y)>0.001 and ticks<180:
		var delta: float=minf(1.0/60.0,absf(target_y-arena.player_pos.y)/float(arena._stats.move_speed))
		arena.tick(delta);ticks+=1
	Input.action_release(action)
	check(ticks>0 and ticks<180 and absf(arena.player_pos.y-target_y)<0.01,"Held movement input reaches requested legal point through Main ticks")
	return {"action":action,"ticks":ticks,"from":before,"to":arena.player_pos,"arrived_age":arena.elapsed-started_at}
func route_probe() -> void:
	group="held_input_leave_reenter"
	var attack:=prepare()
	if attack.is_empty():return
	near(attack.profile.radius,130.0,"Initial visual authority is radius130")
	near(attack.profile.windup_seconds,1.4,"Initial visual authority gives full first warning")
	near(attack.profile.recovery_seconds,1.9*Monsters.BASE_ATTACK_SPEED/maxf(0.2,boss.attack_speed),"Original final-recovery attack-speed formula")
	var movements: Array=[walk_vertical(birth.y+180.0)]
	check(arena.elapsed-started_at<1.4,"Held input leaves inner circle before first deadline")
	tick_to(1.399)
	events(0,"Initial phase does not resolve before its full warning")
	tick_to(1.4)
	if not events(1,"First full warning settles exactly once"):return
	check(not arena.telegraph_trace[0].inside and not arena.telegraph_trace[0].applied,"Leaving inner circle avoids first damage")
	var second: Dictionary=arena.telegraphs.state_for(boss.id)
	if not check(not second.is_empty(),"Outer warning remains active after first settlement"):return
	check(second.get("shape")=="annulus" and second.get("inner_radius")==130.0 and second.get("pulse_index")==1,"Actual visual snapshot switches to outer warning")
	near(second.profile.radius,240.0,"Second visual authority is radius240")
	near(second.profile.windup_seconds,1.0,"Second visual authority gives additional 1.0 warning")
	movements.append(walk_vertical(birth.y+100.0))
	check(arena.elapsed-started_at<2.4 and arena.player_pos.distance_to(birth)+arena.PLAYER_RADIUS<130.0,"Real input reenters fully safe inner area before outer deadline")
	tick_to(2.399)
	events(1,"Outer phase does not resolve early")
	tick_to(2.4)
	if pair():check(not arena.telegraph_trace[1].inside and arena.incoming_damage_trace.is_empty(),"Held leave/reenter route avoids both actual damage settlements")
	capture({"movements":movements,"initial_attack":attack,"outer_snapshot":second})
func point_probe(name: String, distance: float, hit_first: bool, hit_second: bool) -> void:
	group=name
	var attack:=prepare()
	if attack.is_empty():return
	arena.player_pos=birth+Vector2(0,distance)
	check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Controlled boundary point is legal")
	var expected: Dictionary={"remaining_shield":arena.shield,"remaining_health":arena.health}
	for applies: bool in [hit_first,hit_second]:
		if applies:
			expected=Defense.incoming_source_hit(attack.packet.base,arena._stats,expected.remaining_shield,expected.remaining_health,"player")
			if not accepted(expected,"Existing defense predicts exact admitted hit"):return
	arena.tick(2.4)
	if pair():
		check(arena.telegraph_trace[0].applied==hit_first and arena.telegraph_trace[1].applied==hit_second,"Body overlap decides expected circle/annulus hits")
		near(arena.health,expected.remaining_health,"Shared defense exact resulting health")
		near(arena.shield,expected.remaining_shield,"Shared defense exact resulting shield")
	capture({"distance":distance,"target_radius":arena.PLAYER_RADIUS,"expected_first":hit_first,"expected_second":hit_second})
func immunity_probe(initial_immunity: float, expected_first: bool, expected_second: bool) -> void:
	group="large_delta_immunity_"+str(initial_immunity)
	var attack:=prepare(Vector2.INF,130.0)
	if attack.is_empty():return
	arena.invulnerable=initial_immunity
	arena.tick(2.8)
	if pair():
		check(arena.telegraph_trace[0].applied==expected_first and arena.telegraph_trace[1].applied==expected_second,"Large delta respects immunity at each actual event time")
		near(arena.telegraph_trace[0].step_time,1.4,"First within-tick event time")
		near(arena.telegraph_trace[1].step_time,2.4,"Second within-tick event time")
		check(arena.incoming_damage_trace.size()==int(expected_first)+int(expected_second),"Large delta creates no duplicate damage packets")
	arena.tick(10.0)
	check(arena.telegraph_trace.size()==2 and arena.telegraphs.active_count()==0,"Long recovery advance never duplicates either event")
	capture({"initial_immunity":initial_immunity})
func knockback_probe() -> void:
	group="frozen_center_and_packet"
	var attack:=prepare()
	if attack.is_empty():return
	boss.knockback=Vector2(180,0)
	var movement:=walk_vertical(birth.y+180.0)
	var moved: Dictionary=arena.telegraphs.state_for(boss.id)
	if not check(not moved.is_empty(),"Moved source retains active sequence"):return
	check(boss.pos!=birth and moved.center==birth and arena.player_pos!=attack.center,"Real external impulse and held player movement retain start center")
	check(moved.packet==attack.packet,"Source movement preserves frozen damage packet")
	tick_to(2.4)
	if pair():check(arena.telegraph_trace[0].center==birth and arena.telegraph_trace[1].center==birth,"Both actual events settle at original center after knockback")
	capture({"source_after":boss.pos,"movement":movement,"locked":attack})
func freeze_probe(at_age: float) -> void:
	group="partial_freeze_at_"+str(at_age)
	var attack:=prepare(Vector2.INF,180.0)
	if attack.is_empty():return
	tick_to(at_age)
	var before: Dictionary=arena.telegraphs.state_for(boss.id)
	if not check(not before.is_empty(),"Selected phase is still active before freeze"):return
	var frozen: Dictionary=arena.freeze_runtime.apply(boss.id,boss.rarity,arena.elapsed,Frost.PLAYER_POLICY,{"skill_id":"frost","phase":"controlled_main_probe"})
	if not accepted(frozen,"Existing valid freeze runtime applies to living natural boss") or not check(bool(frozen.get("applied",false)),"Freeze accepted as a new status"):return
	var freeze_state: Dictionary=arena.freeze_runtime.state_for(boss.id)
	var duration: float=Frost.PLAYER_POLICY.duration_by_rarity.boss
	arena.tick(duration+0.1)
	var after: Dictionary=arena.telegraphs.state_for(boss.id)
	if not check(not after.is_empty(),"Partially thawed action remains active"):return
	check(after.attack_id==before.attack_id and after.center==before.center and after.phase==before.phase and after.pulse_index==before.pulse_index,"Partial freeze preserves phase, attack identity and locked center")
	near(after.elapsed,float(before.elapsed)+0.1,"Only thawed suffix advances current phase clock")
	var total: float=2.4+float(attack.profile.recovery_seconds)+duration
	tick_to(total-0.001)
	check(not arena.telegraphs.state_for(boss.id).is_empty(),"Freeze extends complete action through final recovery without reset")
	tick_to(total+0.001)
	check(arena.telegraphs.state_for(boss.id).is_empty(),"Final recovery finishes after exact freeze delay")
	pair()
	capture({"frozen":freeze_state,"before":before,"after_partial_thaw":after,"expected_total_duration":total})
func wall_probe() -> void:
	group="controlled_legal_wall"
	var wall: Rect2=arena.world_geometry().walls[2]
	var source:=Vector2(wall.position.x-float(boss.radius)-2.0,wall.position.y+50.0)
	var attack:=prepare(source,-100.0)
	if attack.is_empty():return
	var blocked:=Vector2(wall.position.x+145.0,wall.position.y-arena.PLAYER_RADIUS-2.0)
	arena.player_pos=blocked
	var ring: Dictionary={"shape":"annulus","center":source,"inner_radius":130.0,"radius":240.0}
	check(arena._geometry.is_clear(source,boss.radius) and arena._geometry.is_clear(blocked,arena.PLAYER_RADIUS) and Runtime.overlaps(ring,blocked,arena.PLAYER_RADIUS) and not arena._terrain_visible(source,blocked),"Explicit relocated wall fixture uses legal band point blocked by real planter")
	arena.tick(2.4)
	if pair():check(not arena.telegraph_trace[1].inside and not arena.telegraph_trace[1].applied and arena.incoming_damage_trace.is_empty(),"Real terrain LOS blocks annulus settlement after actual warning lock")
	capture({"control":"Boss relocated after natural admission for legal corner LOS probe; not a natural-birth shelter claim","source":source,"player":blocked,"wall":wall})
func return_probe() -> bool:
	group="return_cancels_sequence"
	var attack:=prepare()
	if attack.is_empty():return false
	arena.tick(1.6)
	if not check(not arena.telegraphs.state_for(boss.id).is_empty(),"Return starts during pending outer phase"):return false
	if not accepted(arena.return_to_town(arena.world_context().revision),"Actual formal town return"):return false
	check(arena.telegraphs.active_count()==0 and arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty() and arena.map_spawn_records().is_empty(),"Town clears both phases, actors, lineage queue and spawn metadata")
	var count: int=arena.telegraph_trace.size()
	arena._advance_enemy_telegraphs(10.0)
	check(arena.telegraph_trace.size()==count,"Canceled outer event never settles after return")
	capture({"canceled_attack_id":attack.attack_id})
	return true
func kill(enemy: Dictionary) -> bool:
	if float(enemy.health)<=0.0:return true
	enemy.spawn=0.0
	var settlement: Dictionary=Defense.incoming_hit({"physical":1e9},{},enemy.shield,enemy.health,"monster")
	if not accepted(settlement,"Controlled death uses existing actual defense"):return false
	arena._apply_enemy_settlement(enemy,settlement,Color.WHITE)
	return true
func lineage_probe() -> void:
	group="death_lineage"
	var attack:=prepare()
	if attack.is_empty():return
	var records: Array=arena.map_spawn_records()
	var roots_before: int=arena.state.normal_journey().normal_root_kills
	var rewards_before: int=arena.reward_kills
	arena._begin_progress_transaction()
	var killed:=kill(boss)
	arena._end_progress_transaction()
	if not killed:return
	check(arena.telegraphs.state_for(boss.id).is_empty() and arena.reward_kills==rewards_before+1 and arena.monster_runtime.queue.size()==4,"Actual source death cancels both phases, rewards once and queues original four children")
	var rng_before: int=arena.rng.state
	arena._finish_enemy_death(boss)
	check(arena.reward_kills==rewards_before+1 and arena.rng.state==rng_before,"Repeated real death cannot duplicate reward or consume RNG")
	arena._advance_enemy_telegraphs(10.0)
	check(arena.telegraph_trace.is_empty(),"Dead source never settles delayed circle or ring")
	arena._flush_monster_spawns()
	var children: Array=[]
	for enemy: Dictionary in arena.enemies:
		if enemy.root_id==boss.id and enemy.generation>0:children.append(enemy)
	if not check(children.size()==4,"Actual four boss descendants materialize"):return
	var children_before: Array=children.duplicate(true)
	for child: Dictionary in children:
		check(not child.reward_eligible and child.xp_reward==0 and child.map_spawn_key==boss.map_spawn_key and not child.has("map_boss_attack_id"),"Every child preserves original spawn lineage and lacks root rewards/boss policy")
	arena._begin_progress_transaction()
	for child: Dictionary in children:kill(child)
	arena._end_progress_transaction()
	check(arena.reward_kills==rewards_before+1 and arena.state.normal_journey().normal_root_kills==roots_before+1,"Descendant deaths never add root reward or progression")
	check(arena.map_spawn_records()==records and not arena._map_run.complete and arena._map_run.snapshot().ordinary_kills==0,"Initial metadata survives boss-first lineage; ordinary roster still gates completion")
	check(Rules.reason(arena.state.snapshot()).is_empty() and arena.state.snapshot().version==Rules.VERSION,"Actual formal ownership and current save schema remain lawful")
	capture({"children":children_before,"boss":boss.duplicate(true),"records":records,"root_rewards":arena.reward_kills-rewards_before})
	accepted(arena.return_to_town(arena.world_context().revision),"Lineage probe returns through actual formal town")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v101-") or OS.get_environment("GINKGO_RING_MAIN_OUTPUT").is_empty():quit(78);return
	if FileAccess.file_exists("user://build_save.json"):printerr("Fresh isolated profile required");quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	pause()
	check(arena.world_context().normal_town and arena.state.normal_journey().normal_root_kills==0 and Rules.reason(arena.state.snapshot()).is_empty(),"Fresh actual Main starts lawful formal town without progression grants")
	if not check(arena.save_build(),"Actual Main saves fresh character") or not enter():finish();return
	var selected: String=OS.get_environment("GINKGO_RING_MAIN_GROUP")
	if selected.is_empty() or selected=="routes":
		route_probe()
		point_probe("remain_outer_band",180.0,false,true)
		point_probe("far_outside",240.0+arena.PLAYER_RADIUS+1.0,false,false)
		point_probe("inner_tangent",130.0-arena.PLAYER_RADIUS,true,true)
		point_probe("fully_inner_safe",130.0-arena.PLAYER_RADIUS-0.01,true,false)
		point_probe("outer_tangent",240.0+arena.PLAYER_RADIUS,false,true)
	if selected.is_empty() or selected=="timing":
		immunity_probe(0.0,true,true)
		immunity_probe(1.5,false,true)
		immunity_probe(2.5,false,false)
		knockback_probe()
		for at_age: float in [0.5,1.6,2.6]:freeze_probe(at_age)
	if selected.is_empty() or selected=="wall":wall_probe()
	if selected.is_empty() or selected=="lifecycle":
		if return_probe() and enter():lineage_probe()
	finish()
func finish() -> void:
	report.checks=checks;report.failures=failures;report.failed_labels=labels
	if not save_json("main-result.json",report):printerr("Could not write evidence");failures+=1
	print("GINKGO_RING_MAIN checks=%d failures=%d groups=%d" % [checks,failures,report.groups.size()])
	if is_instance_valid(arena):arena.queue_free()
	quit(1 if failures else 0)
