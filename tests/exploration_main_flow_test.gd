extends SceneTree
## Actual Main, fresh formal character, controlled runtime checks and deaths.
## This is integration evidence, never natural-combat footage or a gear grant.
const Model = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Frost = preload("res://scripts/combat/frost_lock_rules.gd")

class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)

var arena: Node
var checks := 0
var failures := 0
var labels: Array[String] = []
var report: Dictionary = {"method":"Fresh Main formal town; four full entry rosters; real input/ticks; controlled status probes and deaths, not natural footage", "entries":[], "full_run":{}, "checks":0,"failures":0}

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		labels.append(label)
		printerr("FAIL: " + label)
	return value
func accepted(value: Dictionary, label: String) -> bool:
	return check(bool(value.get("ok",false)), label + ": " + JSON.stringify(value))
func near(actual: float, expected: float, label: String) -> bool:
	return check(absf(actual-expected)<0.00001, "%s: %.9f vs %.9f" % [label,actual,expected])
func pause() -> void:
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire=false
	for unused: int in range(4): arena.hud.close_panel()
func ids() -> Array[int]:
	var result: Array[int]=[]
	for enemy: Dictionary in arena.enemies: result.append(int(enemy.id))
	return result
func actor(id: int) -> Dictionary:
	for enemy: Dictionary in arena.enemies:
		if int(enemy.id)==id:return enemy
	return {}
func observation() -> Dictionary:
	return {"state":arena.state.snapshot(),"world":arena.world_context(),"draft":arena.map_draft(),
		"run":arena._map_run.snapshot(),"runtime":arena.EncounterAdmission._snapshot(arena.monster_runtime),
		"records":arena.map_spawn_records(),"mechanisms":arena.map_mechanism_state(),
		"enemies":arena.enemies.duplicate(true),"rng":arena.rng.state,"player":arena.player_pos,
		"camera":arena.get_node("WorldCamera").position,"arena":arena.ARENA,
		"projectile_id":arena.projectile_runtime.next_projectile_id,
		"disk":FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)}
func kill(enemy: Dictionary) -> void:
	if float(enemy.health)<=0.0:return
	enemy.spawn=0.0
	var settlement: Dictionary=Defense.incoming_hit({"physical":1e9},{},enemy.shield,enemy.health,"monster")
	if not accepted(settlement,"Controlled death uses actual defense settlement"):return
	arena._apply_enemy_settlement(enemy,settlement,Color.WHITE)
func write_json(name: String, value: Variant) -> void:
	var output: String=OS.get_environment("EXPLORATION_MAIN_OUTPUT")
	if output.is_empty():return
	var file:=FileAccess.open(output.path_join(name),FileAccess.WRITE)
	if not check(file!=null,"Evidence file opens: "+name):return
	file.store_string(JSON.stringify(value,"\t",true,true))
	file.close()

func enter(map_id: String, detailed: bool=false) -> bool:
	var balance_before: int=arena.state.crafting_balance()
	if not accepted(arena.craft_normal_map(map_id,1,[],[],arena.map_draft().revision),"Formal tierI draft: "+map_id):return false
	var before: Dictionary=observation()
	var opened: Dictionary=arena.start_map(arena.map_draft().revision)
	if not accepted(opened,"Formal Main entry: "+map_id):return false
	pause()
	var count: int=25 if map_id=="old_garden" else 37
	var world: Dictionary=arena.world_context()
	var records: Array=arena.map_spawn_records()
	check(arena.enemies.size()==count and records.size()==count and world.initial_monsters==count,"All ordinary roots plus boss exist immediately: "+map_id)
	check(arena.ARENA.size==Vector2(3600,2400) and arena.world_geometry().bounds==arena.ARENA,"Actual Main uses authoritative 3600x2400 bounds: "+map_id)
	check(world.encounter_mode=="exploration" and not world.exploration_description.is_empty(),"World context exposes exploration description: "+map_id)
	check(world.awake_monsters==0 and world.boss_phase=="resident","Entry actors sleep and boss is resident: "+map_id)
	check(arena._map_run.snapshot().admitted==count-1 and arena.ordinary_admissions==count-1 and arena._map_run.boss_id>0,"Finite ledger already owns entire initial roster: "+map_id)
	check(arena.monster_runtime.next_id==int(before.runtime.next_id)+count and arena.monster_runtime.queue.is_empty(),"All root IDs allocated once, no spawn queue: "+map_id)
	check(arena.rng.state==before.rng,"Detached layout does not consume gameplay RNG: "+map_id)
	check(world.fee_paid==0 and arena.state.crafting_balance()==balance_before,"Free tierI entry preserves existing balance: "+map_id)
	check(arena.player_pos==arena.world_geometry().landmarks.entry,"Actual player starts at authored exploration entrance: "+map_id)
	check(arena.get_node("WorldCamera").zoom==Vector2(0.65,0.65) and arena.get_node("WorldCamera").position.distance_to(View.follow_position(arena.player_pos,arena.ARENA))<0.001,"Main camera follows entry immediately at 0.65: "+map_id)
	check(arena.map_mechanism_state()=={"config":{},"optional_encounters":[]},"Empty future-mechanism shell remains empty: "+map_id)
	var seen: Dictionary={}
	var groups: Dictionary={}
	var roster_ok:=true
	for record: Dictionary in records:
		var enemy: Dictionary=actor(int(record.actor_id))
		var valid: bool=not enemy.is_empty() and enemy.id==record.root_id and enemy.root_id==record.root_id and enemy.generation==0 and enemy.reward_eligible and enemy.map_spawn_key==record.spawn_key and enemy.template_id==record.template_id and enemy.pos==record.position and record.reward_route=="standard" and record.encounter_id=="" and not seen.has(record.spawn_key) and arena._geometry.is_clear(enemy.pos,enemy.radius)
		roster_ok=roster_ok and valid
		seen[record.spawn_key]=true
		groups[record.source_group]=int(groups.get(record.source_group,0))+1
		if detailed:check(valid,"Initial root record binds actual identity, template, position and standard route: "+str(record.spawn_key))
	check(roster_ok and seen.size()==count,"All spawn records are unique, complete and detached from proximity: "+map_id)
	check(groups.get("boss",0)==1 and groups.get("camp_west",0)==(count-1)/3 and groups.get("camp_north",0)==(count-1)/3 and groups.get("camp_east",0)==(count-1)/3,"Three full source groups and one boss: "+map_id)
	var copied: Array=arena.map_spawn_records()
	copied[0].reward_route="mutated_copy"
	check(arena.map_spawn_records()==records,"Record query cannot mutate authoritative route: "+map_id)
	var initial_ids: Array=ids()
	var first_position: Vector2=arena.enemies[0].pos
	# The full normal tick runs; neither viewport culling nor old camp triggers admit roots.
	arena.auto_fire=true
	arena.tick(0.7)
	check(ids()==initial_ids and arena.monster_runtime.next_id==before.runtime.next_id+count and arena.enemies[0].pos==first_position and arena.world_context().awake_monsters==0 and arena.projectiles.is_empty(),"Default auto-fire idle tick leaves all resident roots asleep with no projectiles or new IDs: "+map_id)
	arena.auto_fire=false
	check(arena.enemies[0].spawn==0.0 and world.initial_monsters==arena.world_context().initial_monsters,"Distant birth protection advances without extra admissions: "+map_id)
	report.entries.append({"map_id":map_id,"world":world,"records":records,"ids":initial_ids,"entry":arena.player_pos})
	return true

func return_to_town(label: String) -> bool:
	if not accepted(arena.return_to_town(arena.world_context().revision),label):return false
	check(arena.world_context().normal_town and arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty(),"Real town return clears actors and deferred children")
	check(arena.map_spawn_records().is_empty() and arena.world_context().initial_monsters==0 and arena.world_context().encounter_mode=="","Spawn provenance clears only on town return")
	check(arena.ARENA==View.WORLD_ARENA and arena.get_node("WorldCamera").position.distance_to(View.WORLD_ARENA.get_center())<0.001,"Town restores original fixed camera and arena")
	return true

func wall_probe() -> bool:
	var target: Dictionary=arena.enemies[0]
	var wall: Rect2=arena.world_geometry().walls[0]
	var original: Vector2=target.pos
	target.pos=Vector2(wall.position.x-float(target.radius)-8.0,wall.get_center().y)
	arena.player_pos=Vector2(wall.end.x+arena.PLAYER_RADIUS+8.0,wall.get_center().y)
	var before_ids: Array=ids()
	check(arena._geometry.is_clear(target.pos,target.radius) and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS) and Vector2(target.pos).distance_to(arena.player_pos)<450.0 and not arena._terrain_visible(target.pos,arena.player_pos),"Controlled wall probe uses legal opposite-wall points within 450")
	arena.tick(0.1)
	check(not target.exploration_awake and ids()==before_ids,"Blocked LOS prevents actual proximity wake without spawning")
	arena.player_pos=target.pos+Vector2(-200,0)
	var before: Vector2=target.pos
	arena.tick(0.1)
	check(target.exploration_awake and Vector2(target.pos).distance_to(arena.player_pos)<before.distance_to(arena.player_pos),"Same resident actor wakes and pursues on clear LOS")
	check(ids()==before_ids and arena.map_spawn_records()[0].position==original,"Wall probe preserves initial ID and historical spawn position")
	return true

func active_probes() -> bool:
	var records: Array=arena.map_spawn_records()
	var before_ids: Array=ids()
	var boss: Dictionary=actor(arena._map_run.boss_id)
	if not check(not boss.is_empty(),"Full run already has natural boss before any root death"):return false
	check(not View.visible_world_rect(arena).has_point(boss.pos) and Vector2(boss.pos).distance_to(arena.player_pos)>450.0,"Natural boss is outside viewport and aggro range")
	# Controlled resource/status probes modify runtime only, never character ownership.
	var shield_rate: float=float(boss.get("shield_recharge_rate",boss.shield_regen))
	check(boss.max_shield>2.0 and shield_rate>0.0,"Natural boss supplies genuine shield recharge")
	boss.shield=float(boss.max_shield)-2.0
	boss.damage_delay=0.05
	boss.attack_timer=0.8
	var shield_before: float=boss.shield
	arena.tick(0.1)
	near(boss.shield,shield_before+shield_rate*0.05,"Sleeping offscreen boss recovers shield after exact delay")
	near(boss.attack_timer,0.7,"Sleeping offscreen cooldown continues")
	check(not boss.exploration_awake,"Recovery never wakes a remote actor")
	var frozen: Dictionary=arena.freeze_runtime.apply(boss.id,boss.rarity,arena.elapsed,Frost.PLAYER_POLICY,{"skill_id":"frost","phase":"controlled_runtime"})
	if not accepted(frozen,"Controlled valid freeze attaches to existing far boss"):return false
	var original: Vector2=boss.pos
	boss.knockback=Vector2(80,0)
	arena.tick(0.1)
	near(boss.attack_timer,0.7,"Far frozen actor retains paused cooldown")
	check(boss.pos!=original and not boss.exploration_awake and boss.knockback.length()<80.0,"Far sleeping frozen actor still receives external impulse and its decay")
	arena.tick(0.2)
	near(boss.attack_timer,0.6,"Far actor resumes remaining cooldown after exact thaw prefix")
	check(not arena.freeze_runtime.is_frozen(boss.id,arena.elapsed),"Far freeze expires on actual elapsed clock")
	# Real shield-only settlement wakes an unseen actor; no viewport-based skip.
	var health_before: float=boss.health
	shield_before=boss.shield
	arena._damage_enemy(boss,0.25,Color.WHITE)
	check(boss.exploration_awake and boss.health==health_before and boss.shield<shield_before,"Actual offscreen shield loss wakes boss without requiring health loss")
	check(arena.world_context().boss_phase=="active","Boss phase changes resident to active on damage")
	original=boss.pos
	arena.tick(0.1)
	check(Vector2(boss.pos).distance_to(arena.player_pos)<original.distance_to(arena.player_pos),"Awakened remote boss pursues beyond 450 instead of going dormant")
	var target: Dictionary=arena.enemies[12]
	check(not target.exploration_awake and not View.visible_world_rect(arena).has_point(target.pos),"Burn probe starts on a sleeping offscreen original root")
	var resources_before: float=float(target.health)+float(target.shield)
	var burned: Dictionary=arena.burn_runtime.apply("monster",target.id,0,0.5,1.0,arena.elapsed,{"skill_id":"meteor","phase":"controlled_runtime"})
	if not accepted(burned,"Controlled valid burn attaches through existing runtime"):return false
	arena.tick(0.1)
	check(float(target.health)+float(target.shield)<resources_before and target.exploration_awake and not arena.burn_trace.is_empty(),"Actual far burn tick settles resources and wakes original actor")
	var a: Dictionary=arena.enemies[16]
	var b: Dictionary=arena.enemies[17]
	a.pos=arena.ARENA.position+Vector2(2600,2050)
	b.pos=a.pos+Vector2(2,0)
	var separation_before: float=Vector2(a.pos).distance_to(b.pos)
	arena.tick(0.1)
	check(not a.exploration_awake and not b.exploration_awake and Vector2(a.pos).distance_to(b.pos)>separation_before,"Far sleeping pair still receives crowd separation")
	check(ids()==before_ids and arena.map_spawn_records()==records,"Far shield/freeze/burn/force/separation ticks never create roots or mutate spawn provenance")
	# Approach a still-sleeping original actor with actual held movement and ticks.
	target=arena.enemies[0]
	arena.player_pos=target.pos+Vector2(-451,0)
	arena.tick(0.0)
	check(not target.exploration_awake,"451-unit clear LOS remains outside wake radius")
	var player_before: Vector2=arena.player_pos
	var elapsed_before: float=arena.elapsed
	Input.action_press("move_right")
	arena.tick(1.0/60.0)
	Input.action_release("move_right")
	check(arena.player_pos.x>player_before.x and arena.elapsed>elapsed_before and target.exploration_awake,"Real held movement tick crosses 450 and wakes existing root")
	check(ids()==before_ids and arena.world_context().awake_monsters>=3,"Approach changes awake states without adding identities")
	arena.player_pos=arena.ARENA.get_center()
	Input.action_press("move_right")
	arena.tick(1.0/60.0)
	Input.action_release("move_right")
	check(arena.get_node("WorldCamera").position.distance_to(arena.player_pos)<0.001,"Main real movement tick follows interior player")
	mouse_probe()
	return true

func mouse_metrics(mouse: Vector2) -> Dictionary:
	return {"pressed":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"requested_screen":mouse,
		"player_screen":View.world_to_screen(arena,arena.player_pos),"viewport_mouse":root.get_mouse_position(),
		"global_mouse":arena.get_global_mouse_position(),"expected_global":View.screen_to_world(arena,mouse),
		"aim":arena._aim_direction(),"player":arena.player_pos,"camera":arena.get_node("WorldCamera").position,
		"window_size":root.size,"content_scale_size":root.content_scale_size,"screen_transform":str(root.get_screen_transform())}

func mouse_probe() -> void:
	var mouse: Vector2=View.world_to_screen(arena,arena.player_pos)+Vector2(160,0)
	# Input.parse_input_event takes native-window coordinates, unlike View's
	# logical viewport coordinates. Headless uses a 64x64 letterboxed window.
	var native_mouse: Vector2=root.get_screen_transform()*mouse
	var motion:=InputEventMouseMotion.new()
	motion.position=native_mouse
	motion.global_position=native_mouse
	Input.parse_input_event(motion)
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.position=native_mouse
	click.global_position=native_mouse
	click.pressed=true
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	report.mouse={"native_event_position":native_mouse,"after_input_parse":mouse_metrics(mouse)}
	print("EXPLORATION_MOUSE_DIAGNOSTIC "+JSON.stringify(report.mouse))
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and arena._aim_direction().dot(Vector2.RIGHT)>0.99,"Actual mouse state aims correctly through followed Main camera")
	arena.attack_timer=0.0
	var elapsed_before: float=arena.elapsed
	arena.tick(1.0/60.0)
	var release:=InputEventMouseButton.new()
	release.button_index=MOUSE_BUTTON_LEFT
	release.position=native_mouse
	release.global_position=native_mouse
	release.pressed=false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	check(arena.attack_timer>0.0 and arena.elapsed>elapsed_before,"Actual mouse attack executes inside a progressing Main tick")
	arena.projectile_runtime.cancel_all(arena.projectiles)

func complete_boss_first() -> bool:
	var records: Array=arena.map_spawn_records()
	var boss: Dictionary=actor(arena._map_run.boss_id)
	var root_count: int=arena.state.normal_journey().normal_root_kills
	var original_boss: Dictionary=boss.duplicate(true)
	arena._begin_progress_transaction()
	kill(boss)
	arena._end_progress_transaction()
	check(arena.reward_kills==1 and arena._map_run.snapshot().ordinary_kills==0 and arena.world_context().boss_phase=="defeated","Boss can die first and rewards exactly one root")
	check(arena.monster_runtime.queue.size()==4,"Natural boss queues its original four descendants")
	arena._check_map_complete()
	check(arena.world_context().mode=="map" and not arena._map_run.complete,"Boss-first death cannot finish while ordinary roots or queued descendants remain")
	var reward_before: int=arena.reward_kills
	var rng_before: int=arena.rng.state
	arena._finish_enemy_death(boss)
	check(arena.reward_kills==reward_before and arena.rng.state==rng_before,"Repeated death does not duplicate root reward or consume RNG")
	arena._flush_monster_spawns()
	var children: Array=[]
	for enemy: Dictionary in arena.enemies:
		if enemy.root_id==boss.id and enemy.generation>0:children.append(enemy)
	check(children.size()==4 and arena.enemies.size()==28,"All four boss children coexist with all24 ordinary roots")
	for child: Dictionary in children:
		check(not child.reward_eligible and child.xp_reward==0 and child.map_spawn_key==boss.map_spawn_key and not child.has("map_boss_attack_id"),"Actual child inherits root spawn key and no root reward or boss policy")
	# Retain one live child while killing roots to prove the living-child boundary.
	var held_id: int=children[0].id
	arena._begin_progress_transaction()
	for enemy: Dictionary in arena.enemies.duplicate():
		if int(enemy.id)!=held_id:kill(enemy)
	arena._end_progress_transaction()
	arena._check_map_complete()
	check(arena._map_run.snapshot().ordinary_kills==24 and arena.reward_kills==25,"Every ordinary root and boss settle once through the original reward ledger")
	check(arena.world_context().mode=="map" and not arena._map_run.complete,"All roots dead still cannot finish while a living child remains")
	var before_children: int=arena.reward_kills
	var iterations:=0
	while iterations<8:
		iterations+=1
		arena._flush_monster_spawns()
		var any_alive:=false
		arena._begin_progress_transaction()
		for enemy: Dictionary in arena.enemies.duplicate():
			if float(enemy.health)>0.0:
				any_alive=true
				check(enemy.generation>0 and not enemy.reward_eligible and enemy.map_spawn_key==arena._map_spawn_records[enemy.root_id].spawn_key,"Remaining actual descendant retains existing root provenance")
				kill(enemy)
		arena._end_progress_transaction()
		if not any_alive and arena.monster_runtime.queue.is_empty():break
	check(iterations<8 and arena.monster_runtime.queue.is_empty(),"Actual bounded lineage queue drains completely")
	arena._flush_monster_spawns()
	arena._check_map_complete()
	check(arena.world_context().mode=="map_complete" and arena._map_run.complete and arena.enemies.is_empty(),"Map finishes only after all roots, boss, live children and queue clear")
	check(arena.reward_kills==before_children and arena.state.normal_journey().normal_root_kills-root_count==25,"Descendant deaths never earn root progression or root rewards")
	check(arena.map_spawn_records()==records,"Initial source records survive every death and completion until town")
	var journey: Dictionary=arena.state.normal_journey()
	check(journey.best_tiers.old_garden==1 and journey.pending_map_reward.shards==4,"Original tier unlock and four-shard completion reward remain intact")
	var before: Dictionary=observation()
	arena._check_map_complete()
	check(observation()==before,"Repeated completion preserves state, reward receipt, RNG and exact save bytes")
	var denied: Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	check(not denied.ok and observation()==before,"Claim before town is atomic rejection")
	report.full_run={"boss_before":original_boss,"records":records,"journey":journey,"reward_kills":arena.reward_kills,"descendant_rounds":iterations}
	if not return_to_town("Actual completed run returns to formal town"):return false
	if not accepted(arena.craft_normal_map("old_garden",2,[],[],arena.map_draft().revision),"Actual completion unlocks tierII draft"):return false
	before=observation()
	denied=arena.start_map(arena.map_draft().revision)
	check(not denied.ok and observation()==before,"Unclaimed reward atomically blocks new map")
	var claimed: Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	if not accepted(claimed,"Actual formal town claim"):return false
	check(claimed.claimed_shards==4 and arena.state.crafting_balance()==4,"Existing shard items receive exactly four once")
	before=observation()
	denied=arena.claim_normal_rewards(arena.world_context().revision)
	check(not denied.ok and observation()==before,"Second claim cannot repeat credit, RNG, IDs or save")
	return true

func paid_atomic_reentry() -> bool:
	var model:=FaultModel.new()
	if not check(model.load_build(arena.NORMAL_BUILD_PATH),"Write-failure model reads actual earned character save"):return false
	check(model.snapshot()==arena.state.snapshot(),"Fault seam copies lawful earned character without equipment, currency or unlock edits")
	arena._replace_build(model,arena.NORMAL_BUILD_PATH)
	if not accepted(arena.craft_normal_map("old_garden",2,[],[],arena.map_draft().revision),"Paid reentry prepares through real unlocked draft"):return false
	check(arena.map_draft().cost==4 and arena.map_draft().completion_reward==8,"Original tierII cost and reward unchanged")
	var before: Dictionary=observation()
	for config: Variant in [{"future":true},{"reward_route":"standard"},[],null]:
		var denied: Dictionary=arena.start_map(arena.map_draft().revision,config)
		check(not denied.ok and observation()==before,"Unsupported mechanism config rejects before fee, save, RNG and IDs: "+str(config))
	model.fail_save=true
	var denied: Dictionary=arena.start_map(arena.map_draft().revision)
	check(not denied.ok and observation()==before,"Failed paid entry save leaves full character, actors, records, geometry, camera, RNG, IDs and disk unchanged")
	model.fail_save=false
	var opened: Dictionary=arena.start_map(arena.map_draft().revision)
	if not accepted(opened,"Actual paid reentry succeeds after write fault removed"):return false
	pause()
	check(arena.state.crafting_balance()==0 and arena.world_context().fee_paid==4 and arena.wave==4,"Successful retry of entry charges exactly one original fee")
	check(arena.enemies.size()==25 and arena.map_spawn_records().size()==25 and arena.monster_runtime.next_id==before.runtime.next_id+25,"Paid reentry admits complete roster with fresh monotonic IDs")
	check(arena.state.normal_journey().active_run.run_id==before.state.journey.next_run_id and arena.state.normal_journey().next_run_id==before.state.journey.next_run_id+1,"Successful entry allocates exactly one formal run ID")
	before=observation()
	denied=arena.start_map(arena.map_draft().revision)
	check(not denied.ok and observation()==before,"Already-in-map entry cannot double charge or duplicate roots")
	# Birth-protected hits are evaluated by the normal packet settlement path.
	var basic: Dictionary=arena.state.get_basic_cast()
	if not accepted(basic,"Actual unmodified character compiles its owned basic attack"):return false
	var enemy: Dictionary=arena.enemies[0]
	var packet: Dictionary=basic.packets.get("direct",basic.packets.get("projectile",{}))
	var resources: Vector2=Vector2(enemy.health,enemy.shield)
	arena._apply_damage_packet(enemy,packet,basic.snapshot,Color.WHITE)
	check(Vector2(enemy.health,enemy.shield)==resources and not enemy.exploration_awake,"Actual spawn-protected hit does not wake or damage a resident root")
	arena.tick(0.7)
	check(enemy.spawn==0.0 and not enemy.exploration_awake,"Real tick expires far spawn protection without proximity wake")
	# Fail-closed future route probe: the existing root cannot fall back to rewards.
	var record: Dictionary=arena._map_spawn_records[enemy.root_id]
	record.reward_route="future_unsupported"
	resources=Vector2(enemy.health,enemy.shield)
	enemy.health=0.0
	var state_before: Dictionary=arena.state.snapshot()
	var runtime_before: Dictionary=arena.EncounterAdmission._snapshot(arena.monster_runtime)
	var rng_before: int=arena.rng.state
	arena._finish_enemy_death(enemy)
	check(arena.reward_kills==0 and arena.kills==0 and arena.state.snapshot()==state_before and arena.EncounterAdmission._snapshot(arena.monster_runtime)==runtime_before and arena.rng.state==rng_before,"Unknown reward route cannot fall through to standard reward, death queue or RNG")
	check(not arena._encounter_error.is_empty() and not enemy.death_processed,"Unknown route surfaces explicit failure before death ledger")
	record.reward_route="standard"
	enemy.health=resources.x
	enemy.shield=resources.y
	arena._encounter_error=""
	if not return_to_town("Paid reopened run returns without refund"):return false
	check(arena.state.crafting_balance()==0 and arena.state.normal_journey().active_run.is_empty(),"Abandonment preserves paid fee and clears only active receipt")
	check(Rules.reason(arena.state.snapshot()).is_empty() and arena.state.snapshot().version==Rules.VERSION,"Final character remains valid current formal schema")
	write_json("formal-final-save.json",arena.state.snapshot())
	return true

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v086-exploration-"):
		printerr("Requires fresh isolated /tmp/godot-m1-v086-exploration-* XDG_DATA_HOME")
		quit(78)
		return
	if FileAccess.file_exists("user://build_save.json"):
		printerr("Fresh-user proof refuses an existing build_save.json")
		quit(78)
		return
	arena=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	pause()
	check(arena.world_context().normal_town and not arena.world_context().test_mode and arena.enemies.is_empty(),"Default Main starts genuine fresh formal town")
	check(arena.build_save_path=="user://build_save.json" and arena.state.normal_journey().normal_root_kills==0,"Fresh profile uses normal save path and no granted progression")
	check(arena.state.snapshot().version==Rules.VERSION and Rules.reason(arena.state.snapshot()).is_empty(),"Current formal schema and original ownership validate at first launch")
	if not check(arena.save_build(),"Actual Main saves fresh profile before admission"):
		finish()
		return
	if OS.get_environment("EXPLORATION_MAIN_SAVE_ONLY")=="1":
		# Earn the paid-entry prerequisite through the original root/reward path.
		# Keep all paid atomicity checks; skip unrelated maps and active probes.
		if enter("old_garden") and complete_boss_first():paid_atomic_reentry()
		finish()
		return
	if OS.get_environment("EXPLORATION_MAIN_INPUT_ONLY")=="1":
		if not accepted(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision),"Input-only lawful tierI draft"):finish();return
		if not accepted(arena.start_map(arena.map_draft().revision),"Input-only lawful Main start"):finish();return
		pause()
		arena.player_pos=arena.ARENA.get_center()
		var before_move: Vector2=arena.player_pos
		Input.action_press("move_right")
		arena.tick(1.0/60.0)
		Input.action_release("move_right")
		check(arena.player_pos.x>before_move.x and arena.get_node("WorldCamera").position.distance_to(arena.player_pos)<0.001,"Input-only actual movement tick updates followed camera")
		mouse_probe()
		finish()
		return
	var before: Dictionary=observation()
	var denied: Dictionary=arena.craft_normal_map("old_garden",2,[],[],arena.map_draft().revision)
	check(not denied.ok and observation()==before,"Fresh user's locked tierII draft rejects atomically")
	for map_id: String in ["broken_ruins","sunwell_terrace","ginkgo_arcade"]:
		if not enter(map_id):finish();return
		if map_id=="broken_ruins":wall_probe()
		if not return_to_town("Formal town loop abandons "+map_id):finish();return
	if enter("old_garden",true) and active_probes() and complete_boss_first():paid_atomic_reentry()
	finish()

func finish() -> void:
	report.checks=checks+(0 if OS.get_environment("EXPLORATION_MAIN_OUTPUT").is_empty() else 1)
	report.failures=failures
	report.failed_labels=labels
	write_json("input-result.json" if OS.get_environment("EXPLORATION_MAIN_INPUT_ONLY")=="1" else "main-result.json",report)
	print("EXPLORATION_MAIN_FLOW checks=%d failures=%d entries=%d" % [checks,failures,report.entries.size()])
	if is_instance_valid(arena):arena.queue_free()
	quit(1 if failures else 0)
