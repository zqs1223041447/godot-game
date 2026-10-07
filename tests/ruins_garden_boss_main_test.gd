extends SceneTree
## Actual Main with a fresh lawful schema54 character and formal ASYNC native entry.
## Held-input dodge uses real ticks. Other positions, resources, status and death
## controls are explicitly bounded integration probes, not natural combat footage.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Frost = preload("res://scripts/combat/frost_lock_rules.gd")
var arena: Node
var boss: Dictionary = {}
var birth := Vector2.ZERO
var center := Vector2.ZERO
var started_at := 0.0
var checks := 0
var failures: Array[String] = []
var group := "entry"
var report: Dictionary = {"method":"Actual main.tscn, fresh lawful schema54 character, formal ASYNC ruins_garden entry and all25 resident roots. Held-input leave/reenter uses real Main ticks. Boundary, native wall LOS, freeze, resources and source-death controls are integration probes, not natural combat footage. No migrated save, old snapshot, full clear or long combat run.","groups":{},"entries":[]}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(group + ": " + label)
		printerr("RUINS_BOSS_MAIN_FAIL [%s]: %s" % [group,label])
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
func json_value(value: Variant) -> Variant:
	if value is Vector2:return [value.x,value.y]
	if value is Rect2:return {"position":json_value(value.position),"size":json_value(value.size)}
	if value is Array or value is PackedVector2Array:
		var array: Array=[]
		for item: Variant in value:array.append(json_value(item))
		return array
	if value is Dictionary:
		var object: Dictionary={}
		for key: Variant in value:object[key]=json_value(value[key])
		return object
	return value
func save_json(name: String, value: Variant) -> bool:
	var file:=FileAccess.open(OS.get_environment("RUINS_BOSS_MAIN_OUTPUT").path_join(name),FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(json_value(value),"\t",true,true)+"\n");file.close();return true
func capture(extra: Dictionary = {}) -> void:
	var row: Dictionary={"trace":arena.telegraph_trace.duplicate(true),"damage":arena.incoming_damage_trace.duplicate(true),"attack":arena.telegraphs.state_for(int(boss.get("id",0))),"player":arena.player_pos,"elapsed":arena.elapsed,"health":arena.health,"shield":arena.shield}
	row.merge(extra,true);report.groups[group]=row
func enter() -> bool:
	var next_id: int=arena.monster_runtime.next_id
	var rng_before: int=arena.rng.state
	if not accepted(arena.craft_normal_map("ruins_garden",1,[],[],arena.map_draft().revision),"Formal free tierI draft"):return false
	if not accepted(await arena.open_map(arena.map_draft().revision),"Actual formal ASYNC native map entry"):return false
	pause()
	boss=actor(arena._map_run.boss_id)
	if not check(not boss.is_empty(),"Resident natural boss exists"):return false
	birth=arena.world_geometry().landmarks.boss.center
	var records: Array=arena.map_spawn_records()
	check(arena.world_context().map_id=="ruins_garden" and arena.world_geometry().id=="ruins_garden" and arena.world_geometry().source_map_id=="ruins_garden" and arena._geometry.physics_ready(),"Formal map, collision identity and ready native authority all remain ruins_garden")
	check(arena.enemies.size()==25 and records.size()==25 and arena.world_context().initial_monsters==25,"All24 ordinary roots and boss are resident at entry")
	check(arena.monster_runtime.next_id==next_id+25 and arena.rng.state==rng_before,"Formal initial allocation keeps exact root count and gameplay RNG")
	check(boss.pos==birth and birth-arena.ARENA.position==Vector2(3180,320),"Authored boss birth remains relative (3180,320)")
	check(arena._map_run.snapshot().admitted==24 and arena.world_context().awake_monsters==0,"Original finite ledger and sleeping admission remain intact")
	check(boss.map_boss_attack_id=="ruins_garden_slam" and boss.generation==0 and boss.root_id==boss.id and boss.reward_eligible,"Natural root owns strict ruins_garden_slam policy")
	var policy: Dictionary=Monsters.telegraph_policy(boss)
	check(policy.name=="庭园缠印" and policy.target_rule=="player_at_start" and policy.trigger_distance==420.0,"Actual boss resolves distinct attack name, player-at-start target and420 trigger")
	for record: Dictionary in records:
		var enemy: Dictionary=actor(record.actor_id)
		if not check(not enemy.is_empty(),"Spawn record resolves existing root"):return false
		check(enemy.id==record.root_id and enemy.map_spawn_key==record.spawn_key and enemy.pos==record.position and record.reward_route=="standard" and enemy.generation==0 and enemy.reward_eligible,"Actual spawn identity, geometry and standard reward route preserved")
	report.entries.append({"boss":boss.duplicate(true),"policy":policy,"records":records,"rng":rng_before,"schema":arena.state.snapshot().version,"wave":arena.wave,"geometry":arena.world_geometry()})
	if report.entries.size()==1:check(save_json("main-formal-initial-save.json",arena.state.snapshot()),"Fresh lawful initial snapshot retained for read-only documentation")
	arena.tick(0.7)
	check(boss.spawn==0.0 and not boss.exploration_awake,"Actual tick expires natural boss birth protection without waking it")
	# Keep every other admitted actor in place and unable to attack during probes.
	for enemy: Dictionary in arena.enemies:
		if enemy.id!=boss.id:enemy.speed=0.0;enemy.attack_timer=1000.0
	return true
func prepare(source: Vector2 = Vector2.INF, target: Vector2 = Vector2.INF) -> Dictionary:
	arena.telegraphs.reset();arena.freeze_runtime.reset();arena.burn_runtime.reset();arena.shock_runtime.reset();arena.chill_runtime.reset()
	arena.projectile_runtime.cancel_all(arena.projectiles)
	arena.telegraph_trace.clear();arena.incoming_damage_trace.clear()
	boss.pos=birth if source==Vector2.INF else source
	boss.spawn=0.0;boss.attack_timer=0.0;boss.knockback=Vector2.ZERO
	arena.player_pos=boss.pos+Vector2(0,100.0) if target==Vector2.INF else target
	center=arena.player_pos
	arena._stats=arena.state.get_stats()
	for field: String in ["life_regen","mana_regen","shield_regen","shield_regeneration_rate","shield_recharge_rate"]:arena._stats[field]=0.0
	arena._stats.max_health=10000.0;arena._stats.max_shield=1000.0;arena._stats.evasion=0.0
	arena.health=10000.0;arena.shield=5.0;arena.invulnerable=0.0;arena.damage_delay=0.0;arena._player_evasion_entropy=99.0
	arena._burn_immunity_until=arena.elapsed
	if not check(arena._geometry.is_clear(boss.pos,boss.radius) and arena._geometry.is_clear(center,arena.PLAYER_RADIUS) and arena._terrain_visible(boss.pos,center),"Controlled initial actor positions and admission LOS are legal"):return {}
	var rng_before: int=arena.rng.state
	arena.tick(0.0)
	var attack: Dictionary=arena.telegraphs.state_for(boss.id)
	if not check(boss.exploration_awake and not attack.is_empty(),"Actual Main wakes and locks living natural boss"):return {}
	check(arena.rng.state==rng_before,"Actual wake and telegraph start consume no gameplay RNG")
	check(attack.center==center and attack.center!=boss.pos and attack.visual_pattern=="ruins_garden_slam","First center is exactly player-at-start and explicitly differs from boss position")
	boss.attack_timer=1000.0
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
	check(first.type=="circle_attack" and first.shape=="circle" and first.radius==90.0 and first.pulse_index==0,"First event is radius90 inner circle")
	check(second.type=="annulus_attack" and second.shape=="annulus" and second.inner_radius==90.0 and second.radius==210.0 and second.pulse_index==1,"Second event is90-to210 annulus")
	check(first.attack_id==second.attack_id and first.source_id==boss.id and second.source_id==boss.id and first.center==center and second.center==center,"Both phases preserve one attack, source and frozen player-at-start center")
	near(first.attack_age,1.15,"First full warning deadline is1.15")
	near(second.attack_age,2.15,"Second deadline adds full1.0 warning")
	var contact: Dictionary=Monsters.contact_components(boss)
	for element: String in contact:
		near(first.packet.base[element],contact[element]*0.65,"First frozen component budget: "+element)
		near(second.packet.base[element],contact[element]*0.65,"Second frozen component budget: "+element)
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
	near(attack.profile.radius,90.0,"Initial visual authority radius90")
	near(attack.profile.windup_seconds,1.15,"Initial visual authority full1.15 warning")
	near(attack.profile.recovery_seconds,1.9*Monsters.BASE_ATTACK_SPEED/maxf(0.2,boss.attack_speed),"Final recovery retains base1.9 attack-speed scaling")
	var movements: Array=[walk_vertical(center.y+150.0)]
	check(arena.elapsed-started_at<1.15,"Held input exits circle before first deadline")
	check(arena.telegraphs.state_for(boss.id).center==center and arena.player_pos!=center,"Telegraph never follows moving player")
	tick_to(1.149);events(0,"Circle does not settle before full warning")
	tick_to(1.15)
	if not events(1,"Circle settles once at full warning"):return
	check(not arena.telegraph_trace[0].inside and not arena.telegraph_trace[0].applied,"Leaving circle avoids first settlement")
	var second: Dictionary=arena.telegraphs.state_for(boss.id)
	if not check(not second.is_empty(),"Outer warning remains active after first settlement"):return
	check(second.shape=="annulus" and second.inner_radius==90.0 and second.pulse_index==1 and second.center==center,"Second visual state changes shape but preserves player-at-start center")
	near(second.profile.radius,210.0,"Outer visual radius210")
	near(second.profile.windup_seconds,1.0,"Outer visual full additional1.0 warning")
	movements.append(walk_vertical(center.y))
	check(arena.elapsed-started_at<2.15 and arena.player_pos.distance_to(center)+arena.PLAYER_RADIUS<90.0,"Held input returns fully into safe inner area before outer deadline")
	tick_to(2.149);events(1,"Annulus does not settle early")
	tick_to(2.15)
	if pair():check(not arena.telegraph_trace[1].inside and arena.incoming_damage_trace.is_empty(),"Real held-input out-and-in dodge avoids both damage settlements")
	tick_to(2.15+float(attack.profile.recovery_seconds)-0.001)
	check(not arena.telegraphs.state_for(boss.id).is_empty(),"Final recovery stays active through full scaled duration")
	tick_to(2.15+float(attack.profile.recovery_seconds)+0.001)
	check(arena.telegraphs.state_for(boss.id).is_empty() and arena.telegraph_trace.size()==2,"Recovery finishes without a duplicate event")
	capture({"movements":movements,"initial_attack":attack,"outer_snapshot":second})
func trigger_probe() -> void:
	group="actual_trigger_boundary"
	var attack:=prepare()
	if attack.is_empty():return
	arena.telegraphs.reset();arena.telegraph_trace.clear()
	boss.attack_timer=0.0
	arena.player_pos=birth+Vector2(0,420.01)
	check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS) and arena._terrain_visible(birth,arena.player_pos),"Trigger boundary uses legal clear native space")
	arena.tick(0.0)
	check(arena.telegraphs.state_for(boss.id).is_empty(),"Actual Main does not admit beyond420 trigger")
	arena.player_pos=birth+Vector2(0,420.0)
	arena.tick(0.0)
	var admitted: Dictionary=arena.telegraphs.state_for(boss.id)
	check(not admitted.is_empty() and admitted.center==arena.player_pos,"Actual Main admits at exact420 and locks player center")
	boss.attack_timer=1000.0
	capture({"outside_distance":420.01,"boundary_distance":420.0})
func point_probe(name: String, distance: float, hit_first: bool, hit_second: bool, immunity: float = 0.0) -> void:
	group=name
	var attack:=prepare()
	if attack.is_empty():return
	arena.player_pos=center+Vector2(0,distance)
	arena.invulnerable=immunity
	check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Controlled boundary point is legal")
	var expected: Dictionary={"remaining_shield":arena.shield,"remaining_health":arena.health}
	for applies: bool in [hit_first,hit_second]:
		if applies:
			expected=Defense.incoming_source_hit(attack.packet.base,arena._stats,expected.remaining_shield,expected.remaining_health,"player")
			if not accepted(expected,"Existing defense predicts exact admitted hit"):return
	arena.tick(2.15)
	if pair():
		check(arena.telegraph_trace[0].applied==hit_first and arena.telegraph_trace[1].applied==hit_second,"Actual overlap and existing protection select expected hits")
		near(arena.health,expected.remaining_health,"Shared defense exact resulting health")
		near(arena.shield,expected.remaining_shield,"Shared defense exact resulting shield")
		check(arena.incoming_damage_trace.size()==int(hit_first)+int(hit_second),"Each admitted pulse settles at most one damage packet")
	capture({"distance":distance,"target_radius":arena.PLAYER_RADIUS,"expected_first":hit_first,"expected_second":hit_second,"initial_immunity":immunity})
func freeze_probe() -> void:
	group="outer_phase_freeze"
	var attack:=prepare()
	if attack.is_empty():return
	arena.player_pos=center+Vector2(0,150)
	tick_to(1.4)
	var before: Dictionary=arena.telegraphs.state_for(boss.id)
	if not check(not before.is_empty() and before.pulse_index==1,"Freeze begins during actual outer warning"):return
	var frozen: Dictionary=arena.freeze_runtime.apply(boss.id,boss.rarity,arena.elapsed,Frost.PLAYER_POLICY,{"skill_id":"frost","phase":"controlled_main_probe"})
	if not accepted(frozen,"Existing freeze applies to living natural boss") or not check(bool(frozen.get("applied",false)),"Freeze is accepted as a new status"):return
	var duration: float=Frost.PLAYER_POLICY.duration_by_rarity.boss
	arena.tick(duration+0.1)
	var after: Dictionary=arena.telegraphs.state_for(boss.id)
	if not check(not after.is_empty(),"Partially thawed outer warning remains active"):return
	check(after.attack_id==before.attack_id and after.center==center and after.phase==before.phase and after.pulse_index==1,"Freeze preserves phase, identity and frozen center")
	near(after.elapsed,float(before.elapsed)+0.1,"Only thawed suffix advances phase clock")
	var total: float=2.15+float(attack.profile.recovery_seconds)+duration
	tick_to(total-0.001);check(not arena.telegraphs.state_for(boss.id).is_empty(),"Freeze extends action through final recovery")
	tick_to(total+0.001);check(arena.telegraphs.state_for(boss.id).is_empty(),"Recovery completes after exact freeze delay")
	pair();capture({"before":before,"after_partial_thaw":after,"freeze_duration":duration,"expected_duration":total})
func native_wall_points() -> Dictionary:
	# Search authored contour edges, accepting points only through original native
	# circle/ray queries. No substitute geometry, walls or collision installation.
	for polygon: PackedVector2Array in arena.world_geometry().module_polygons:
		for index: int in range(polygon.size()):
			var a: Vector2=polygon[index]
			var b: Vector2=polygon[(index+1)%polygon.size()]
			var midpoint: Vector2=(a+b)*0.5
			var edge: Vector2=(b-a).normalized()
			for side: float in [-1.0,1.0]:
				var normal:=Vector2(-edge.y,edge.x)*side
				for first_offset: float in [30.0,60.0,90.0]:
					var locked: Vector2=midpoint+normal*first_offset
					var source: Vector2=locked+normal*100.0
					if not arena._geometry.is_clear(locked,arena.PLAYER_RADIUS) or not arena._geometry.is_clear(source,boss.radius) or not arena._terrain_visible(source,locked):continue
					for other_offset: float in [80.0,110.0,140.0]:
						var target: Vector2=midpoint-normal*other_offset
						var ring: Dictionary={"shape":"annulus","center":locked,"inner_radius":90.0,"radius":210.0}
						if arena._geometry.is_clear(target,arena.PLAYER_RADIUS) and Runtime.overlaps(ring,target,arena.PLAYER_RADIUS) and locked.distance_to(target)>105.0 and not arena._terrain_visible(locked,target):
							return {"source":source,"center":locked,"target":target,"edge_start":a,"edge_end":b,"native_ray":arena._geometry.sweep(locked,target,0.0)}
	return {}
func wall_probe() -> void:
	group="actual_native_wall_los"
	var geometry_id: int=arena._geometry.get_instance_id()
	var points:=native_wall_points()
	if not check(not points.is_empty(),"Find legal annulus point occluded by an original native contour"):return
	var attack:=prepare(points.source,points.center)
	if attack.is_empty():return
	arena.player_pos=points.target
	check(arena._geometry.get_instance_id()==geometry_id and arena._geometry.physics_ready() and points.native_ray.hit,"Original prepared native collision remains sole geometry authority")
	arena.tick(2.15)
	if pair():check(not arena.telegraph_trace[1].inside and not arena.telegraph_trace[1].applied and arena.incoming_damage_trace.is_empty(),"Real native terrain LOS suppresses annulus damage at legal overlapping target")
	capture({"control":"Natural source relocated after formal admission to probe original contour LOS; target relocation is explicit and is not a walking claim","points":points,"geometry_id":geometry_id})
func death_probe() -> void:
	group="source_death_cancels_outer"
	var attack:=prepare()
	if attack.is_empty():return
	arena.player_pos=center+Vector2(0,150)
	tick_to(1.2)
	if not events(1,"First pulse settles before controlled source death"):return
	var settlement: Dictionary=Defense.incoming_hit({"physical":1e9},{},boss.shield,boss.health,"monster")
	if not accepted(settlement,"Controlled death uses existing actual defense"):return
	arena._begin_progress_transaction();arena._apply_enemy_settlement(boss,settlement,Color.WHITE);arena._end_progress_transaction()
	check(float(boss.health)<=0.0 and arena.telegraphs.state_for(boss.id).is_empty(),"Actual source death immediately cancels pending outer phase")
	arena._advance_enemy_telegraphs(10.0)
	events(1,"Dead source never emits delayed annulus")
	check(Rules.reason(arena.state.snapshot()).is_empty() and arena.state.snapshot().version==54,"Controlled death preserves current lawful schema54 model")
	capture({"canceled_attack_id":attack.attack_id,"source_health":boss.health})
func return_probe() -> void:
	group="formal_return_removes_source"
	var attack:=prepare()
	if attack.is_empty():return
	arena.player_pos=center+Vector2(0,150);tick_to(1.3)
	if not check(not arena.telegraphs.state_for(boss.id).is_empty(),"Return starts during pending outer phase"):return
	if not accepted(arena.return_to_town(arena.world_context().revision),"Actual formal town return"):return
	check(arena.telegraphs.active_count()==0 and arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty() and arena.map_spawn_records().is_empty(),"Formal removal clears both phases, all sources, queue and metadata")
	var count: int=arena.telegraph_trace.size();arena._advance_enemy_telegraphs(10.0)
	check(arena.telegraph_trace.size()==count,"Removed source never settles pending outer phase")
	capture({"canceled_attack_id":attack.attack_id})
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v120-") or OS.get_environment("RUINS_BOSS_MAIN_OUTPUT").is_empty():quit(78);return
	if FileAccess.file_exists("user://build_save.json"):printerr("Fresh isolated profile required");quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	pause()
	check(arena.world_context().normal_town and arena.state.normal_journey().normal_root_kills==0 and Rules.reason(arena.state.snapshot()).is_empty() and arena.state.snapshot().version==54,"Fresh actual Main starts lawful schema54 formal town without progression grants")
	if not check(arena.save_build(),"Actual Main saves fresh character") or not await enter():finish();return
	trigger_probe()
	route_probe()
	point_probe("center_safe_outer",0.0,true,false)
	point_probe("remain_outer_band",150.0,false,true)
	point_probe("inner_tangent",90.0-arena.PLAYER_RADIUS,true,true)
	point_probe("inner_clearance",90.0-arena.PLAYER_RADIUS-0.01,true,false)
	point_probe("outer_tangent",210.0+arena.PLAYER_RADIUS,false,true)
	point_probe("outside_clearance",210.0+arena.PLAYER_RADIUS+0.01,false,false)
	point_probe("protection_expires_between_pulses",90.0-arena.PLAYER_RADIUS,false,true,1.3)
	freeze_probe()
	wall_probe()
	return_probe()
	group="fresh_reentry"
	if await enter():death_probe()
	finish()
func finish() -> void:
	for action: String in ["move_up","move_down","move_left","move_right"]:Input.action_release(action)
	report.checks=checks;report.failures=failures.size();report.failed_labels=failures
	if not save_json("main-result.json",report):printerr("Could not write evidence");failures.append("evidence write")
	print("RUINS_BOSS_MAIN checks=%d failures=%d groups=%d" % [checks,failures.size(),report.groups.size()])
	if is_instance_valid(arena):arena.queue_free()
	quit(1 if not failures.is_empty() else 0)
