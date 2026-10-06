extends SceneTree
## Bounded v071 catalog and real-Main consumers. Fixed accuracy inputs are
## explicitly controlled combat fixtures; Resolute is allocated by the real API.
const Model = preload("res://scripts/canonical_game_state.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const OldMonsters = preload("res://docs/qa/v071-gameplay/frozen/monster_catalog_v070.gd")
const Attack = preload("res://scripts/combat/attack_hit_rules.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Encounter = preload("res://scripts/encounters/encounter_compiler.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const ROUTE = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "63282", "31961"]
var arena: Node
var checks := 0
var failures := 0
var completed := false
var sections := {}
var report := {}
var ordinary_snapshot := {}
var ordinary_cleave := {}
var resolute_cleave := {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual-expected)<=maxf(1e-8,absf(expected)*1e-9), "%s actual=%s expected=%s" % [label,actual,expected])
func accepted(value: Dictionary, label: String) -> bool:
	return check(value.get("ok",false),label+": "+JSON.stringify(value))
func section(test: Callable) -> bool:
	var before := checks
	completed = false
	test.call()
	check(completed,"Section returned normally: "+test.get_method())
	sections[test.get_method()] = checks-before
	return completed and failures==0
func watchdog() -> void:
	push_error("MIST_GAMEPLAY section watchdog")
	quit(124)

func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear(); arena.particles.clear(); arena.floating_text.clear(); arena.rings.clear()
	arena.monster_runtime=Runtime.new(); arena.telegraphs=arena.TelegraphRuntime.new()
	arena.projectile_runtime=arena.Projectiles.new(); arena.feedback_runtime=arena.FeedbackRuntime.new(); arena.visual_cues=arena.VisualCueRuntime.new()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.leech_runtime.clear(); arena._sync_flasks(true)
	arena.damage_trace.clear(); arena.incoming_damage_trace.clear(); arena.burn_trace.clear(); arena.combat_trace.clear(); arena.attack_admission_trace.clear()
	arena.telegraph_trace.clear(); arena.event_counts.clear(); arena._ember_deaths.clear(); arena._ember_projectile_clock.clear()
	arena.group_cooldowns.reset(); arena.elapsed=0.0; arena._burn_step_active=false; arena._burn_incoming_time=-1.0
	arena._burn_immunity_until=0.0; arena.alive=true; arena.invulnerable=0.0; arena.damage_delay=0.0
	arena.auto_fire=false; arena.spawn_timer=1000.0; arena._autosave_timer=0.0; arena.wave=1
	arena._simulation_accumulator=0.0; arena._world_mode="normal"; arena._geometry.configure("normal",arena.ARENA)
	arena._stats=arena.state.get_stats(); arena.health=float(arena._stats.max_health); arena.shield=0.0; arena.mana=float(arena._stats.max_mana)
	arena.kills=0; arena.reward_kills=0; arena.total_damage=0.0; arena.total_shots=0; arena.attack_timer=0.0
	arena._refresh_leech_caps(); arena.player_pos=arena.ARENA.get_center(); arena.player_facing=Vector2.RIGHT
	arena.rng.seed=710071; arena.critical_runtime.reset(710072); arena._player_evasion_entropy=50.0
	arena.hud._process(0.0); arena.hud.close_panel()
	check(not arena.hud.is_blocking(),"Actual-Main fixture unpaused")
	for id: String in arena.Data.SKILLS: arena.cooldowns[id]=0.0

func target(template: String="mist_skitter", rewards: bool=false, durable: bool=true) -> Dictionary:
	var enemy: Dictionary=arena._spawn_monster(template,arena.player_pos+Vector2(40,0),"ordinary","normal",[],rewards)
	if not check(not enemy.is_empty(),"Actual ordinary normal root admitted: "+template): return {}
	enemy.spawn=0.0
	if durable:
		enemy.health=10000.0; enemy.max_health=10000.0
	return enemy

func catalog_and_admission() -> void:
	check(Monsters.validate_templates(Monsters.TEMPLATES).is_empty(),"Current catalog validates")
	for wave: int in [1,7,15]:
		for id: String in OldMonsters.TEMPLATES:
			var context := "map_boss" if id=="rift_warden" else "ordinary"
			check(Monsters.make_enemy(1,id,wave,Vector2(30,40),context)==OldMonsters.make_enemy(1,id,wave,Vector2(30,40),context),"Frozen v070 complete original output unchanged: %s wave%d" % [id,wave])
		var mist:=Monsters.make_enemy(1,"mist_skitter",wave,Vector2(30,40))
		var old:=OldMonsters.make_enemy(1,"skitter",wave,Vector2(30,40))
		if not check(not mist.is_empty(),"Mist legal catalog output"): return
		near(mist.health,old.health*0.8,"Mist health multiplier")
		near(mist.max_health,old.max_health*0.8,"Mist maximum health multiplier")
		near(mist.damage,old.damage*0.85,"Mist contact damage multiplier")
		near(mist.evasion,1600.0,"Mist final evasion")
		for field: String in ["template_id","name","health","max_health","damage","evasion"]: mist.erase(field); old.erase(field)
		check(mist==old,"All remaining catalog fields including movement/radius/attack interval/XP/rewards/children exactly unchanged")
	for context: String in ["death_child","demo","map_boss","level_boss"]:
		check(Monsters.make_enemy(1,"mist_skitter",1,Vector2.ONE,context).is_empty(),"Reject mist context "+context)
	for rarity: String in ["magic","rare","boss","reserved"]:
		check(Monsters.make_enemy(1,"mist_skitter",1,Vector2.ONE,"ordinary",rarity).is_empty(),"Reject mist rarity "+rarity)
	check(Monsters.make_enemy(1,"mist_skitter",1,Vector2.ONE,"ordinary","normal",["gale_stride"]).is_empty(),"Reject mist mechanism override")
	var invalid:=Monsters.TEMPLATES.duplicate(true)
	invalid.splitter.death_spawns=[{"template":"mist_skitter","count":1}]
	check(not Monsters.validate_templates(invalid).is_empty(),"Reject mist death-child template edge")
	invalid=Monsters.TEMPLATES.duplicate(true); invalid.mist_skitter.rarity="magic"
	check(not Monsters.validate_templates(invalid).is_empty(),"Reject mutated mist template")
	var encounter:=Encounter.compile(["enemy_max_health_120","enemy_armour_80"])
	if not accepted(encounter,"Compile lawful encounter"): return
	var canonical:=Monsters.make_enemy(1,"mist_skitter",7,Vector2(30,40))
	var modified:=Encounter.apply_to_enemy(canonical,encounter.profile)
	if not accepted(modified,"Real encounter admits mist"): return
	near(modified.enemy.evasion,1600.0,"Encounter keeps final evasion")
	near(modified.enemy.health,canonical.health*1.2,"Encounter uses reduced mist base health")
	var map:=Maps.compile_normal("sunwell_terrace",2,["enemy_max_health_120","enemy_armour_80"],["elemental_aegis"])
	if not accepted(map,"Compile normal tier-II map"): return
	var admitted:=Admission.create_root(Runtime.new(),map.profile,"mist_skitter",map.profile.wave,Vector2(30,40),"ordinary","normal",[],true)
	if not accepted(admitted,"Real map plus encounter admission"): return
	arena._apply_source_actor_profile(admitted.enemy)
	near(admitted.enemy.evasion,1600.0,"Map and actor-profile consumers preserve final evasion")
	near(admitted.enemy.armour,80.0,"Existing armour modifier survives mist admission")
	check(admitted.enemy.has("map_defense_source") and admitted.enemy.has("encounter_source"),"Both real admission transforms applied")
	report.catalog={"base":"4166822","waves":[1,7,15],"old_templates":OldMonsters.TEMPLATES.size(),"map_enemy":admitted.enemy}
	completed=true

func normal_root_rewards() -> void:
	if not check(not arena._is_test_profile(),"Reward oracle runs on actual normal profile"): return
	var baseline: Dictionary=arena.state.snapshot()
	var results: Array=[]
	for template: String in ["skitter","mist_skitter"]:
		arena.state._accept_memory(baseline); clean(); arena.reward_kills=7
		var enemy:=target(template,true,false)
		if enemy.is_empty(): return
		var before: Dictionary=arena.state.snapshot(); var currency: int=arena.state.crafting_balance()
		var random_before: int=arena.rng.state
		arena._damage_enemy(enemy,1000000.0,Color.WHITE)
		if not check(enemy.death_processed and arena.kills==1 and arena.reward_kills==8,"One actual eligible root death "+template): return
		var after: Dictionary=arena.state.snapshot()
		check(int(after.journey.normal_root_kills)==int(before.journey.normal_root_kills)+1,"One normal journey root increment")
		near(after.progress.xp,before.progress.xp+3,"Exact normal skitter XP=3")
		check(arena.state.crafting_balance()==currency,"Death adds no new currency reward")
		check(after.items.size()==before.items.size()+1,"Existing eighth-kill equipment reward exactly once")
		check(enemy.death_spawns.is_empty() and arena.monster_runtime.queue.is_empty(),"No mist-specific descendants")
		var settled: Dictionary={"model":after,"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint(),"kills":arena.kills,"reward_kills":arena.reward_kills,"pickups":arena.pickups.duplicate(true),"currency":arena.state.crafting_balance()}
		arena._finish_enemy_death(enemy); arena._damage_enemy(enemy,1000000.0,Color.WHITE)
		check(arena.state.snapshot()==after and arena.rng.state==settled.rng and arena.kills==1 and arena.reward_kills==8,"Repeated death settles no XP/equipment/currency/RNG twice")
		results.append(settled)
		report[template+"_reward"]={"rng_before":random_before,"rng_after":settled.rng,"xp":after.progress.xp-before.progress.xp,"currency_delta":arena.state.crafting_balance()-currency,"item_delta":after.items.size()-before.items.size(),"root_delta":after.journey.normal_root_kills-before.journey.normal_root_kills}
	check(results[0]==results[1],"Controlled normal and mist deaths have identical full model/reward/pickup/private+shared RNG results")
	arena.state._accept_memory(baseline)
	completed=true

func legal_source_setup() -> void:
	if not accepted(arena.enter_town_test(arena.world_context().revision),"Proven test-town transition"): return
	if not accepted(arena.start_map(arena.map_draft().revision),"Proven test-map entry"): return
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	var item := {"id":uid,"base_id":"forgeblade","rarity":"normal","item_level":16,"affixes":[]}
	if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)),"Owned legal plain forgeblade admitted"): return
	if not accepted(arena.state.move_item(uid,{"kind":"equipment","slot_id":"weapon"},arena.state.revision(),arena.build_save_path),"Actual legal sword equip"): return
	var gem: String=arena.state.award_gem("skill:cleave")
	if not check(not gem.is_empty(),"Real owned cleave gem"): return
	if not accepted(arena.state.move_item(gem,{"kind":"skill_main","group_id":"group_000009"},arena.state.revision(),arena.build_save_path),"Actual cleave equip"): return
	var candidate: Dictionary=arena.state.snapshot()
	candidate.progress={"level":7,"xp":0}; candidate.talents.class_id=1; candidate.talents.allocated=[ROUTE[0]]
	candidate.talents.masteries={}; candidate.talents.normal_points=11; candidate.revision+=1
	if not check(Model.Rules.reason(candidate).is_empty(),"Proven lawful level-seven source-root fixture"): return
	if not accepted(arena.state._commit(candidate,arena.build_save_path),"Commit lawful earned points"): return
	for id: String in ROUTE.slice(1):
		if id=="31961":
			ordinary_snapshot=arena.state.get_combat_snapshot().duplicate(true)
			ordinary_cleave=arena.state.get_skill_cast("cleave")
		if not accepted(arena.state.allocate_passive(id,0,arena.state.revision(),arena.build_save_path),"Real connected allocation "+id): return
	resolute_cleave=arena.state.get_skill_cast("cleave")
	check(resolute_cleave.get("hit_policy",{}).get("hits_cannot_be_evaded",false),"Real Resolute source policy compiles")
	check(not ordinary_cleave.has("hit_policy"),"Pre-allocation attack remains ordinary")
	completed=true

func winning_seed(snapshot: Dictionary) -> int:
	var runtime:=Critical.new()
	for seed_value: int in range(10000):
		runtime.reset(seed_value)
		if runtime.freeze(snapshot).snapshot.get("critical_roll",{}).get("critical",false): return seed_value
	return -1

func attack_critical_and_resolute() -> void:
	var rows: Array=[]
	for values: Array in [[100.0,0.45],[284.0,0.77],[304.0,0.79]]:
		var snapshot:=ordinary_snapshot.duplicate(true); snapshot.accuracy=values[0]
		var cast:=Compiler.compile_skill("cleave",snapshot,[])
		if not accepted(cast,"Compile fixed final-accuracy attack"): return
		near(Attack.chance(values[0],1600.0),values[1],"Unchanged shared formula authored chance")
		var seed_value:=winning_seed(cast.snapshot)
		if not check(seed_value>=0,"Existing critical stream yields a genuine critical"): return
		for entropy: float in [0.0,99.0]:
			clean(); var enemy:=target()
			if enemy.is_empty(): return
			near(enemy.evasion,1600.0,"Actual Main spawn keeps authored evasion")
			enemy.evasion_entropy=entropy; arena.critical_runtime.reset(seed_value)
			if not check(arena._execute_compiled(cast),"Real cleave accepts fixed-accuracy cast"): return
			if not check(arena.attack_admission_trace.size()==1,"Exactly one real attack admission"): return
			var hit: bool=entropy==99.0
			check(arena.attack_admission_trace[0].hit==hit,"Critical does not bypass actual evasion")
			near(arena.attack_admission_trace[0].chance,values[1],"Actual Main chance equals shared formula")
			near(enemy.evasion_entropy,entropy+values[1]*100.0-(100.0 if hit else 0.0),"Actual Main advances defender entropy once")
			check(arena.critical_runtime.draws==1 and arena.critical_runtime.events==1,"Each accepted attack consumes exactly one private critical event")
			check(arena.damage_trace.size()==(1 if hit else 0),"Only admitted hit settles damage")
			if hit: check(arena.damage_trace[0].critical.critical,"Admitted attack retains actual critical result")
			else: near(enemy.health,10000.0,"Evaded critical leaves health untouched")
			rows.append({"accuracy":values[0],"entropy_before":entropy,"entropy_after":enemy.evasion_entropy,"admission":arena.attack_admission_trace.duplicate(true),"critical":arena.critical_runtime.checkpoint(),"damage":arena.damage_trace.duplicate(true)})
	clean(); var enemy:=target()
	if enemy.is_empty(): return
	enemy.evasion_entropy=13.25
	var checkpoint: Dictionary=arena.critical_runtime.checkpoint()
	if not check(arena._execute_compiled(resolute_cleave),"Actual source-derived Resolute cleave"): return
	check(arena.attack_admission_trace==[{"actor":"monster","target_id":enemy.id,"hit":true,"chance":1.0}],"Resolute reports guaranteed admission")
	near(enemy.evasion_entropy,13.25,"Resolute pauses defender entropy")
	check(arena.damage_trace.size()==1 and not arena.damage_trace[0].get("critical",{}).get("critical",false),"Resolute hit settles without critical")
	check(arena.critical_runtime.checkpoint()==checkpoint,"Resolute draws no critical event")
	# The actual equipped basic uses the same source-derived Resolute policy.
	clean(); enemy=target(); enemy.evasion_entropy=13.25; arena.auto_fire=true
	arena._update_auto_attack(); arena.auto_fire=false
	check(arena.damage_trace.size()==1 and arena.attack_admission_trace.size()==1,"Actual sword basic consumes shared hit admission")
	near(enemy.evasion_entropy,13.25,"Actual Resolute basic preserves entropy")
	clean(); var standard:=target("skitter")
	near(standard.evasion,320.0,"Original actual normal skitter retains old evasion default")
	report.attacks=rows
	completed=true

func spell_and_burn() -> void:
	var spell:=Compiler.compile_skill("nova",ordinary_snapshot,[])
	var ignite:=Compiler.compile_group("meteor",ordinary_snapshot,["ignite"])
	if not accepted(spell,"Compile existing spell") or not accepted(ignite,"Compile existing ignite meteor"): return
	var observations: Array=[]
	for template: String in ["skitter","mist_skitter"]:
		clean(); var enemy:=target(template)
		if enemy.is_empty(): return
		enemy.evasion_entropy=0.0
		if not check(arena._execute_compiled(spell),"Actual nova bypasses evasion: "+template): return
		check(arena.damage_trace.size()==1 and arena.attack_admission_trace.is_empty(),"Spell has one damage settlement and no fabricated attack admission")
		near(enemy.evasion_entropy,0.0,"Spell does not advance entropy")
		var spell_result: Dictionary={"damage":arena.damage_trace.duplicate(true),"health":enemy.health,"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint()}
		clean(); enemy=target(template); enemy.evasion_entropy=0.0
		arena._apply_damage_packet(enemy,ignite.packets.direct,ignite.snapshot,Color.ORANGE)
		var burn: Dictionary=arena.burn_runtime.status_for("monster",int(enemy.id))
		if not check(not burn.is_empty(),"Real meteor hit attaches existing ignite"): return
		var health_before: float=enemy.health; var shared_before: int=arena.rng.state
		var critical_before: Dictionary=arena.critical_runtime.checkpoint()
		arena.elapsed=0.5; arena._advance_monster_burns(0.5)
		check(enemy.health<health_before and arena.burn_trace.size()==1,"Actual DoT tick settles on evasive target")
		near(health_before-enemy.health,float(burn.raw_dps)*0.5,"DoT retains existing elapsed-time damage")
		near(enemy.evasion_entropy,0.0,"DoT does not advance attack entropy")
		check(arena.attack_admission_trace.is_empty() and arena.rng.state==shared_before and arena.critical_runtime.checkpoint()==critical_before,"DoT bypasses evasion and consumes no hit/critical/shared RNG")
		observations.append({"spell":spell_result,"burn":burn,"burn_trace":arena.burn_trace.duplicate(true),"health":enemy.health,"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint()})
	check(observations[0]==observations[1],"Controlled spell and DoT observations exactly equal original skitter")
	report.spell_burn=observations
	completed=true

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v071-mist-") or not OS.get_user_data_dir().begins_with(isolated+"/"):
		quit(78); return
	create_timer(35.0).timeout.connect(watchdog)
	arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire=false
	var selection:=OS.get_environment("MIST_GAMEPLAY_SECTIONS").split(",",false)
	for test: Callable in [catalog_and_admission,normal_root_rewards,legal_source_setup,attack_critical_and_resolute,spell_and_burn]:
		if not selection.is_empty() and not selection.has(test.get_method()) and test.get_method()!="legal_source_setup": continue
		if not section(test): break
	report.merge({"checks":checks,"failures":failures,"sections":sections,"scope":"Bounded actual Main and catalog consumers. Controlled final accuracy, genuine source-allocated Resolute, genuine ordinary roots and normal reward pipeline. No roster/UI/Windows/full-history/performance claim."})
	var output:=OS.get_environment("MIST_GAMEPLAY_REPORT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("MIST_GAMEPLAY ",JSON.stringify({"checks":checks,"failures":failures,"sections":sections}))
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
