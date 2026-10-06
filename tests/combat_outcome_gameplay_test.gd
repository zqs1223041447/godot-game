extends SceneTree
## New bounded v077 actual-Main fixture. Legacy mode runs the identical file
## against the unchanged v076 project; no source projection or test doubles.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const ROUTE = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "63282", "31961"]
var arena: Node
var checks := 0
var failures := 0
var completed := false
var sections := {}
var report := {}
var blade := ""
var bow := ""
var ordinary_snapshot := {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual-expected) <= maxf(1e-9, absf(expected)*1e-9), "%s got=%s expected=%s" % [label,actual,expected])
func accepted(value: Dictionary, label: String) -> bool:
	return check(value.get("ok",false), label+": "+JSON.stringify(value))
func section(test: Callable) -> bool:
	var before := checks
	completed = false
	print("OUTCOME_SECTION_BEGIN ", test.get_method())
	test.call()
	check(completed, "Section returned normally: "+test.get_method())
	sections[test.get_method()] = checks-before
	print("OUTCOME_SECTION_END ",test.get_method()," checks=",checks-before," failures=",failures)
	return completed and failures == 0
func watchdog() -> void:
	push_error("OUTCOME_GAMEPLAY section watchdog")
	quit(124)

func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear(); arena.particles.clear(); arena.floating_text.clear(); arena.rings.clear()
	arena.monster_runtime = arena.MonsterLifecycle.new(); arena.telegraphs = arena.TelegraphRuntime.new()
	arena.projectile_runtime = arena.Projectiles.new(); arena.feedback_runtime = arena.FeedbackRuntime.new(); arena.visual_cues = arena.VisualCueRuntime.new()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.freeze_runtime.reset(); arena.leech_runtime.clear(); arena._sync_flasks(true)
	arena.damage_trace.clear(); arena.incoming_damage_trace.clear(); arena.burn_trace.clear(); arena.combat_trace.clear(); arena.attack_admission_trace.clear()
	arena.telegraph_trace.clear(); arena.event_counts.clear(); arena._ember_deaths.clear(); arena._ember_projectile_clock.clear()
	arena.group_cooldowns.reset(); arena.elapsed=0.0; arena._burn_step_active=false; arena._burn_incoming_time=-1.0
	arena._burn_immunity_until=0.0; arena.alive=true; arena.invulnerable=0.0; arena.damage_delay=0.0
	arena.auto_fire=false; arena.spawn_timer=1000.0; arena._autosave_timer=0.0; arena.wave=1; arena.demo_mode=false
	arena._simulation_accumulator=0.0; arena._world_mode="normal"; arena._geometry.configure("old_garden",arena.ARENA)
	arena._stats=arena.state.get_stats()
	for field: String in ["life_regen","mana_regen","shield_regen","shield_recharge_rate"]: arena._stats[field]=0.0
	arena.health=float(arena._stats.max_health); arena.shield=0.0; arena.mana=float(arena._stats.max_mana)
	arena.kills=0; arena.reward_kills=0; arena.total_damage=0.0; arena.total_shots=0; arena.attack_timer=0.0
	arena._refresh_leech_caps(); arena.player_pos=arena.ARENA.get_center(); arena.player_facing=Vector2.RIGHT
	arena.rng.seed=770076; arena.critical_runtime.reset(770077); arena._player_evasion_entropy=0.0
	arena.hud._process(0.0)
	for index: int in range(4):
		if arena.hud.is_blocking(): arena.hud.close_panel()
	check(not arena.hud.is_blocking(),"Actual Main fixture unpaused")
	for id: String in arena.Data.SKILLS: arena.cooldowns[id]=0.0

func target(offset: Vector2=Vector2(40,0), template: String="mist_skitter", rewarding: bool=false) -> Dictionary:
	var enemy: Dictionary=arena._spawn_monster(template,arena.player_pos+offset,"ordinary","normal",[],rewarding)
	if not check(not enemy.is_empty(),"Legal real ordinary root "+template): return {}
	enemy.spawn=0.0; enemy.health=10000.0; enemy.max_health=10000.0; enemy.shield=0.0; enemy.max_shield=0.0
	enemy.speed=0.0; enemy.attack_timer=1000.0; enemy.shield_regen=0.0; enemy.shield_recharge_rate=0.0
	enemy.evasion_entropy=0.0
	return enemy
func equip(uid: String) -> bool:
	if arena.state.equipped_items().get("weapon","") == uid: return true
	return accepted(arena.state.move_item(uid,{"kind":"equipment","slot_id":"weapon"},arena.state.revision(),arena.build_save_path),"Legal actual weapon equip")
func own(base: String) -> String:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	var item := {"id":uid,"base_id":base,"rarity":"normal","item_level":16,"affixes":[]}
	if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)),"Existing validated plain gear fixture "+base): return ""
	return uid
func cast(skill: String) -> Dictionary:
	return Compiler.compile_skill(skill,ordinary_snapshot,[])
func outcomes(kind: String="") -> Array:
	var result: Array=[]
	for value: Dictionary in arena.combat_outcomes():
		if kind.is_empty() or value.outcome==kind: result.append(value)
	return result
func feedback(kind: String) -> Array:
	var result: Array=[]
	for value: Dictionary in arena.damage_feedback():
		if value.kind==kind: result.append(value)
	return result
func packet_hit(enemy: Dictionary, amount: float, provenance: Dictionary={}) -> void:
	var packet := {"skill_id":"nova","role":"direct","tags":["spell","hit","area"],"base":{"lightning":amount}}
	arena._apply_damage_packet(enemy,packet,ordinary_snapshot,Color.WHITE,0.0,provenance)
func labels(node: Node) -> String:
	var result := str(node.text)+"\n" if node is Label else ""
	for child: Node in node.get_children(): result += labels(child)
	return result

func legal_source_setup() -> void:
	if not accepted(arena.enter_town_test(arena.world_context().revision),"Actual existing test-town fixture transition"): return
	if not accepted(arena.start_map(arena.map_draft().revision),"Actual existing test-map fixture transition"): return
	blade=own("forgeblade"); bow=own("ashwood_bow")
	if blade.is_empty() or bow.is_empty() or not equip(blade): return
	var candidate: Dictionary=arena.state.snapshot()
	candidate.progress={"level":7,"xp":0}; candidate.talents.class_id=1; candidate.talents.allocated=[ROUTE[0]]
	candidate.talents.masteries={}; candidate.talents.normal_points=11; candidate.revision+=1
	if not check(arena.state.Rules.reason(candidate).is_empty(),"Previously proven lawful level-seven connected source fixture"): return
	if not accepted(arena.state._commit(candidate,arena.build_save_path),"Commit lawful earned points fixture"): return
	for id: String in ROUTE.slice(1,ROUTE.size()-1):
		if not accepted(arena.state.allocate_passive(id,0,arena.state.revision(),arena.build_save_path),"Actual source path "+id): return
	ordinary_snapshot=arena.state.get_combat_snapshot().duplicate(true)
	ordinary_snapshot.accuracy=100.0
	check(not ordinary_snapshot.has("resolute_technique"),"Ordinary frozen source has no Resolute policy")
	completed=true

func real_attack_paths() -> void:
	if not equip(blade): return
	clean(); var enemy:=target(); arena.elapsed=3.25
	var before: Dictionary=enemy.duplicate(true)
	arena.auto_fire=true; arena._update_auto_attack(); arena.auto_fire=false
	if not check(arena.attack_admission_trace.size()==1 and not arena.attack_admission_trace[0].hit,"Actual ordinary sword basic misses authored mist target"): return
	if not check(outcomes("evaded").size()==1,"One actual basic miss produces one observation"): return
	var miss: Dictionary=outcomes("evaded")[0]
	near(miss.chance,arena.attack_admission_trace[0].chance,"Observation reads authoritative admission chance")
	near(enemy.evasion_entropy,miss.chance*100.0,"Basic miss advances entropy exactly once")
	check(enemy.health==before.health and enemy.shield==before.shield and arena.damage_trace.is_empty(),"Miss has no actual loss or damage trace")
	check(miss.target_kind=="monster" and miss.target_id==enemy.id and miss.cast_id>0 and miss.projectile_id==0 and miss.at==3.25,"Known basic provenance plus observation clock retained")
	check(arena.damage_feedback().is_empty(),"Miss presentation waits existing short window")
	arena.feedback_runtime.advance(0.2)
	check(feedback("evaded").size()==1 and not feedback("evaded")[0].has("amount"),"Miss marker contains no fabricated numeric loss")
	var detached: Array=arena.combat_outcomes(); detached[0].chance=-1.0
	check(arena.combat_outcomes()[0].chance>=0.0,"Main outcomes accessor is detached")
	if not equip(bow): return
	clean(); enemy=target(Vector2(100,0)); arena.auto_fire=true; arena._update_auto_attack(); arena.auto_fire=false
	if not check(arena.projectiles.size()==1,"Actual ordinary bow launches one owned-gear projectile"): return
	var shot: Dictionary=arena.projectiles[0].duplicate(true)
	arena._update_projectiles(0.25)
	if not check(outcomes("evaded").size()==1,"Actual ordinary projectile miss is observed once"): return
	miss=outcomes("evaded")[0]
	check(miss.projectile_id==shot.id and miss.cast_id==shot.cast_id,"Real ordinary shot provenance preserved")
	check(int(arena.event_counts.get("evaded",0))==1 and arena.damage_trace.is_empty(),"Original projectile evaded event retained without settlement")
	clean(); enemy=target(Vector2(60,0))
	if not check(arena._execute_compiled(cast("tornado")),"Actual compiled tornado launch"): return
	arena._update_projectiles(0.2)
	var misses := 0
	var hits := 0
	for admission: Dictionary in arena.attack_admission_trace:
		if admission.hit: hits+=1
		else: misses+=1
	check(misses>0 and outcomes("evaded").size()==misses and int(arena.event_counts.get("evaded",0))==misses,"Each actual tornado parent miss is observed exactly once")
	check(arena.damage_trace.size()==hits,"Only admitted tornado parents produce numeric damage")
	near(enemy.evasion_entropy,45.0*float(hits+misses)-100.0*float(hits),"Tornado advances entropy once per actual admission")
	for observed: Dictionary in outcomes("evaded"):
		var matches := 0
		for event: Dictionary in arena.combat_trace:
			if event.type=="evaded" and event.projectile_id==observed.projectile_id and event.cast_id==observed.cast_id and event.target_id==observed.target_id: matches+=1
		check(matches==1 and observed.target_id==enemy.id and observed.chance==0.45,"Every tornado observation matches exactly one original refused-contact event and authoritative chance")
	report.attack_paths={"tornado_outcomes":arena.combat_outcomes(),"events":arena.event_counts.duplicate(true)}
	completed=true

func resolute_and_spell() -> void:
	if not accepted(arena.state.allocate_passive("31961",0,arena.state.revision(),arena.build_save_path),"Actual final Resolute allocation"): return
	for weapon: String in [blade,bow]:
		if not equip(weapon): return
		clean(); var enemy:=target(Vector2(40,0) if weapon==blade else Vector2(100,0)); enemy.evasion_entropy=13.25
		var critical: Dictionary=arena.critical_runtime.checkpoint()
		arena.auto_fire=true; arena._update_auto_attack(); arena.auto_fire=false
		if weapon==bow: arena._update_projectiles(0.25)
		check(arena.damage_trace.size()==1 and outcomes().is_empty(),"Actual Resolute weapon hits without any miss observation")
		near(enemy.evasion_entropy,13.25,"Actual Resolute preserves target entropy")
		check(arena.critical_runtime.checkpoint()==critical,"Resolute does not draw critical RNG")
	clean(); var enemy:=target(Vector2(60,0)); enemy.evasion_entropy=13.25
	if not check(arena._execute_compiled(arena.state.get_skill_cast("tornado")),"Real source-derived Resolute tornado"): return
	arena._update_projectiles(0.2)
	check(not arena.damage_trace.is_empty() and outcomes("evaded").is_empty(),"Resolute tornado never receives a miss marker")
	near(enemy.evasion_entropy,13.25,"Resolute tornado preserves entropy")
	if not accepted(arena.state.refund_passive("31961",arena.state.revision(),arena.build_save_path),"Actual Resolute refund"): return
	clean(); enemy=target()
	if not check(arena._execute_compiled(cast("nova")),"Actual spell cast against mist"): return
	check(arena.damage_trace.size()==1 and arena.attack_admission_trace.is_empty() and outcomes().is_empty(),"Spell bypass is never mislabeled as evasion")
	near(enemy.evasion_entropy,0.0,"Spell leaves entropy unchanged")
	completed=true

func invalid_zero_and_tiny() -> void:
	var attack:=cast("tornado")
	for malformed: Dictionary in [{"accuracy":-1.0},{"accuracy":INF},{"resolute_technique":0.5},{"precise_technique":0.5}]:
		clean(); var enemy:=target(); var snapshot:=ordinary_snapshot.duplicate(true); snapshot.merge(malformed,true)
		var before := var_to_bytes(enemy)
		arena._apply_damage_packet(enemy,attack.packets.parent,snapshot,Color.WHITE)
		check(arena.damage_trace.is_empty() and arena.attack_admission_trace.is_empty() and outcomes().is_empty(),"Invalid accuracy/policy never becomes a real evasion: "+str(malformed))
		check(var_to_bytes(enemy)==before,"Invalid admission leaves target byte-exact")
	# The original projectile runtime may call refusal `evaded`; invalid input
	# must still stay out of the new authoritative observation stream.
	clean(); var enemy:=target(Vector2(80,0)); var invalid:=ordinary_snapshot.duplicate(true); invalid.accuracy=-1.0
	var shot: Dictionary=arena.projectile_runtime.make_projectile(arena.player_pos,Vector2.RIGHT,{"speed":400.0,"range":500.0,"lifetime":2.0,"pierce":-1,"radius":6.0},attack.packets.parent,invalid,arena.projectile_runtime.new_cast(),Color.WHITE)
	arena.projectiles.append(shot); arena._update_projectiles(0.3)
	check(int(arena.event_counts.get("evaded",0))==1 and outcomes().is_empty(),"Legacy invalid projectile refusal is not falsely observed as evasion")
	clean(); enemy=target(); packet_hit(enemy,0.0)
	check(arena.damage_trace.size()==1 and outcomes("zero_damage").size()==1,"Successful zero settlement is observed while original damage record remains")
	check(arena.damage_trace[0].shield_spent==0.0 and arena.damage_trace[0].health_lost==0.0,"Zero means exact settled resource loss")
	check(outcomes()[0].cast_id==0 and outcomes()[0].projectile_id==0,"Unknown provenance stays zero")
	check(arena.damage_feedback().is_empty(),"Zero damage creates no floating number or miss marker")
	clean(); enemy=target(); packet_hit(enemy,0.001)
	check(arena.damage_trace.size()==1 and arena.damage_trace[0].health_lost>0.0 and outcomes().is_empty(),"Positive 0.001 actual loss is never classified as zero")
	arena.feedback_runtime.advance(0.2)
	check(feedback("hit").size()==1 and feedback("hit")[0].amount>0.0,"Tiny actual positive damage remains visible as positive")
	completed=true

func actual_wall_and_protection() -> void:
	if not equip(bow): return
	clean(); arena._geometry.configure("broken_ruins",arena.ARENA)
	var wall: Rect2=arena._geometry.snapshot().walls[0]
	arena.player_pos=Vector2(wall.position.x-106,wall.get_center().y)
	var attack:=cast("tornado")
	var shot: Dictionary=arena.projectile_runtime.make_projectile(arena.player_pos,Vector2.RIGHT,{"speed":400.0,"range":500.0,"lifetime":2.0,"pierce":-1,"radius":6.0},attack.packets.parent,attack.snapshot,arena.projectile_runtime.new_cast(),Color.WHITE)
	arena.projectiles.append(shot); arena._update_projectiles(0.5)
	if not check(outcomes("terrain_blocked").size()==1 and int(arena.event_counts.get("terrain_hit",0))==1,"Actual geometry sweep and original wall event produce one observation"): return
	var blocked: Dictionary=outcomes()[0]
	check(blocked.target_kind=="environment" and blocked.target_id==0 and blocked.projectile_id==shot.id and blocked.cast_id==shot.cast_id,"Wall observation has environment identity and actual shot only")
	check(not blocked.has("chance") and arena.damage_trace.is_empty() and arena.projectiles.is_empty(),"Wall has no invented monster, probability or damage")
	clean(); var enemy:=target(); enemy.spawn=0.5
	packet_hit(enemy,10.0,{"cast_id":71})
	check(outcomes("spawn_protected").size()==1 and outcomes()[0].cast_id==71,"Actual valid settlement entry records birth rejection")
	check(arena.damage_trace.is_empty() and arena.attack_admission_trace.is_empty(),"Birth rejection settles no damage and consumes no admission")
	if not equip(blade): return
	clean(); enemy=target(); enemy.spawn=0.5; arena.auto_fire=true; arena._update_auto_attack(); arena.auto_fire=false
	check(outcomes().is_empty() and arena.damage_trace.is_empty(),"Ordinary melee candidate birth filter stays silent")
	if not equip(bow): return
	clean(); enemy=target(Vector2(80,0)); enemy.spawn=0.5
	shot=arena.projectile_runtime.make_projectile(arena.player_pos,Vector2.RIGHT,{"speed":400.0,"range":500.0,"lifetime":2.0,"pierce":-1,"radius":6.0},attack.packets.parent,attack.snapshot,arena.projectile_runtime.new_cast(),Color.WHITE)
	arena.projectiles.append(shot); arena._update_projectiles(0.3)
	check(outcomes().is_empty() and arena.attack_admission_trace.is_empty(),"Ordinary projectile birth contact filter stays silent")
	completed=true

func death_pause_reset_and_caps() -> void:
	clean(); var enemy:=target(); var attack:=cast("tornado")
	arena._apply_damage_packet(enemy,attack.packets.parent,attack.snapshot,Color.WHITE)
	check(outcomes("evaded").size()==1,"Death cleanup fixture starts with real miss")
	packet_hit(enemy,20000.0)
	check(enemy.death_processed and feedback("hit").size()==1 and feedback("evaded").is_empty(),"Death flush publishes damage and drops stale pending miss marker")
	var death_bytes := var_to_bytes([arena.damage_feedback(),arena.combat_outcomes()])
	arena._finish_enemy_death(enemy)
	check(var_to_bytes([arena.damage_feedback(),arena.combat_outcomes()])==death_bytes,"Repeated death does not add either receipt")
	clean(); enemy=target(); arena._apply_damage_packet(enemy,attack.packets.parent,attack.snapshot,Color.WHITE)
	arena.feedback_runtime.advance(0.2)
	var paused := var_to_bytes([arena.damage_feedback(),arena.combat_outcomes()])
	arena.hud.open_panel("inventory"); arena._process(0.8)
	check(var_to_bytes([arena.damage_feedback(),arena.combat_outcomes()])==paused,"Actual menu pause freezes miss marker age and receipt clock")
	arena.hud.close_panel(); arena._world_mode="map_complete"; arena.tick(0.8)
	check(arena.damage_feedback().is_empty() and outcomes("evaded").size()==1,"Completed-map display ages out while historical result stays queryable")
	arena.restart_run()
	check(arena.damage_feedback().is_empty() and outcomes().is_empty(),"Actual restart clears old outcomes and visual marker queues")
	clean()
	for index: int in range(35):
		enemy=target(Vector2(40,index)); arena._apply_damage_packet(enemy,attack.packets.parent,attack.snapshot,Color.WHITE)
	check(outcomes().size()==32 and arena.feedback_runtime._observation_pending.size()==24,"Real admissions bound history at 32 and pending markers at 24")
	arena.feedback_runtime.advance(0.2)
	check(feedback("evaded").size()==8,"Real admission burst displays at most eight miss markers")
	for index: int in range(45): packet_hit(target(Vector2(100,index),"brute"),1.0)
	arena.feedback_runtime.advance(0.2)
	check(feedback("hit").size()==45 and feedback("evaded").size()==3 and arena.damage_feedback().size()==48,"Damage receives first 45 rows and only three spare marker slots")
	for index: int in range(4): packet_hit(target(Vector2(120,index),"brute"),1.0)
	arena.feedback_runtime.advance(0.2)
	check(feedback("hit").size()==48 and feedback("evaded").is_empty() and arena.damage_feedback().size()==48,"Full legacy damage queue suppresses every marker without losing a damage row")
	completed=true

func visibility_and_f6() -> void:
	var samples: Array=[]
	for enabled: bool in [true,false]:
		clean(); arena.visual_settings.damage_numbers=enabled; var enemy:=target(); var attack:=cast("tornado")
		arena._apply_damage_packet(enemy,attack.packets.parent,attack.snapshot,Color.WHITE)
		packet_hit(enemy,0.001,{"cast_id":72}); arena.feedback_runtime.advance(0.2)
		var before := var_to_bytes([enemy,arena.combat_outcomes(),arena.damage_trace,arena.rng.state,arena.critical_runtime.checkpoint()])
		check(arena.hud.handle_menu_key(KEY_F6) and arena.hud.is_blocking(),"Actual F6 opens combat inspection with numbers "+str(enabled))
		var text := labels(arena.hud)
		check(text.contains("命中判定结果") and text.contains("被闪避") and text.contains("<0.01"),"Actual F6 keeps true miss and tiny positive loss inspectable")
		check(var_to_bytes([enemy,arena.combat_outcomes(),arena.damage_trace,arena.rng.state,arena.critical_runtime.checkpoint()])==before,"F6 read does not mutate result, resources, traces or RNG")
		arena.hud.close_panel()
		samples.append([enemy.duplicate(true),arena.combat_outcomes(),arena.damage_feedback(),arena.damage_trace.duplicate(true),arena.rng.state,arena.critical_runtime.checkpoint()])
	check(samples[0]==samples[1],"Visibility toggle leaves all authoritative and presentation observations exact")
	completed=true

func legacy_snapshot() -> Dictionary:
	return {"enemies":arena.enemies.duplicate(true),"projectiles":arena.projectiles.duplicate(true),
		"queue":arena.monster_runtime.queue.duplicate(true),"roots":arena.monster_runtime.roots.duplicate(true),
		"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint(),"model":arena.state.snapshot(),
		"resources":[arena.health,arena.mana,arena.shield],"damage":arena.damage_trace.duplicate(true),
		"incoming":arena.incoming_damage_trace.duplicate(true),"admission":arena.attack_admission_trace.duplicate(true),
		"combat":arena.combat_trace.duplicate(true),"burn":arena.burn_trace.duplicate(true),"events":arena.event_counts.duplicate(true),
		"shots":arena.total_shots,"kills":arena.kills,"reward_kills":arena.reward_kills,"damage_total":arena.total_damage,
		"timer":arena.attack_timer,"cooldowns":arena.cooldowns.duplicate(true),"groups":arena.group_cooldowns.snapshot(),
		"flasks":arena.flask_runtime.snapshot(),"leech":arena.leech_runtime.snapshot(),"pickups":arena.pickups.duplicate(true),
		"particles":arena.particles.duplicate(true),"text":arena.floating_text.duplicate(true),
		"damage_feedback":[arena.feedback_runtime._time,arena.feedback_runtime._pending.duplicate(true),arena.feedback_runtime._visible.duplicate(true)],
		"saves":arena.state.successful_saves,"disk":FileAccess.get_file_as_bytes(arena.build_save_path)}

func legacy_probe(output: String) -> void:
	clean(); ordinary_snapshot=arena.state.get_combat_snapshot().duplicate(true)
	if not check(not arena._is_test_profile(),"Frozen oracle starts actual normal source profile"): return
	if not check(arena.save_build(),"Legacy initial actual save"): return
	var initial_items: int=arena.state.snapshot().items.size()
	var samples: Array=[]
	# Eight actual normal-root deaths cross real equipment reward cadence.
	for index: int in range(8):
		var enemy:=target(Vector2(60+index*5,0),"crawler",true); enemy.health=1.0; enemy.max_health=1.0
		arena._damage_enemy(enemy,100.0,Color.WHITE); samples.append(legacy_snapshot())
	check(arena.kills==8 and arena.reward_kills==8 and arena.state.snapshot().items.size()>initial_items,"Frozen oracle exercises real death, XP and equipment reward")
	arena.enemies.clear()
	var mist:=target(Vector2(75,0)); var sturdy:=target(Vector2(155,0),"brute"); sturdy.health=10000.0
	for step: int in range(60):
		if step==0: check(arena.hit_player_components({"physical":5.0},100.0,["hit","attack"]),"Legacy real incoming attack admitted")
		if step==0: check(arena._execute_compiled(arena.state.get_skill_cast("tornado")),"Legacy real tornado cast")
		if step==15: check(arena._execute_compiled(arena.state.get_skill_cast("nova")),"Legacy real spell cast")
		arena.auto_fire=true; arena.tick(1.0/60.0); samples.append(legacy_snapshot())
	check(arena.total_shots>0 and not arena.damage_trace.is_empty() and not arena.incoming_damage_trace.is_empty() and not arena.attack_admission_trace.is_empty(),"Frozen oracle covers shots, damage, incoming and attack traces")
	# Explicit successful zero, protected entry and real terrain collision are
	# included in the unchanged legacy state, not just the positive-hit flow.
	packet_hit(mist,0.0); samples.append(legacy_snapshot())
	mist.spawn=0.5; packet_hit(mist,10.0); samples.append(legacy_snapshot()); mist.spawn=0.0
	arena.projectiles.clear(); arena._geometry.configure("broken_ruins",arena.ARENA)
	var wall: Rect2=arena._geometry.snapshot().walls[0]; var attack:=cast("tornado")
	var shot: Dictionary=arena.projectile_runtime.make_projectile(Vector2(wall.position.x-106,wall.get_center().y),Vector2.RIGHT,{"speed":400.0,"range":500.0,"lifetime":2.0,"pierce":-1,"radius":6.0},attack.packets.parent,attack.snapshot,arena.projectile_runtime.new_cast(),Color.WHITE)
	arena.projectiles.append(shot); arena._update_projectiles(0.5); samples.append(legacy_snapshot())
	check(int(arena.event_counts.get("terrain_hit",0))==1,"Frozen oracle includes actual projectile wall event")
	if not check(arena.save_build(),"Legacy final actual save"): return
	FileAccess.open(output+".bin",FileAccess.WRITE).store_buffer(var_to_bytes(samples))
	FileAccess.open(output+".save",FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
	report={"ticks":60,"samples":samples.size(),"kills":arena.kills,"reward_kills":arena.reward_kills,"shots":arena.total_shots,
		"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint(),"events":arena.event_counts.duplicate(true),
		"checks":checks,"failures":failures,"mist_entropy":mist.evasion_entropy,"source_mode":"actual normal with unprojected save and original records"}
	FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	completed=true

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v077-") or not OS.get_user_data_dir().begins_with(isolated+"/"):
		quit(78); return
	create_timer(35.0).timeout.connect(watchdog)
	arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire=false
	var output:=OS.get_environment("OUTCOME_LEGACY_OUTPUT")
	if not output.is_empty():
		legacy_probe(output); check(completed,"Frozen legacy probe returned normally")
	else:
		var selected:=OS.get_environment("OUTCOME_GAMEPLAY_SECTIONS").split(",",false)
		for test: Callable in [legal_source_setup,real_attack_paths,resolute_and_spell,invalid_zero_and_tiny,actual_wall_and_protection,death_pause_reset_and_caps,visibility_and_f6]:
			if not selected.is_empty() and not selected.has(test.get_method()) and test.get_method()!="legal_source_setup": continue
			if not section(test): break
		report.merge({"checks":checks,"failures":failures,"sections":sections,"scope":"Bounded actual Main, real legal gear/source APIs and isolated disk; no screenshot, export, full-history or performance claim"})
		output=OS.get_environment("OUTCOME_GAMEPLAY_REPORT")
		if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("OUTCOME_GAMEPLAY ",JSON.stringify({"checks":checks,"failures":failures,"sections":sections}))
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
