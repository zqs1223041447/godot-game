extends SceneTree
## Two complete formal runs, controlled deaths/static actors, not combat footage.
const Fixture = preload("res://docs/qa/v083-gameplay/ginkgo_fixture.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
var arena: Node
var checks := 0
var failures := 0
var report: Dictionary = {"method":"Actual main.tscn; controlled full-roster deaths and static actors; not natural combat footage","runs":[],"attacks":{}}
var freeze_source: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok
func accepted(value: Dictionary, label: String) -> bool:
	return check(value.get("ok",false), label + ": " + JSON.stringify(value))
func near(actual: float, expected: float, label: String) -> bool:
	return check(absf(actual-expected) <= maxf(1e-8,absf(expected)*1e-8), "%s actual=%.12f expected=%.12f" % [label,actual,expected])
func save_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "Evidence opens: " + path): return false
	file.store_string(JSON.stringify(value,"\t",true,true))
	file.close()
	return true
func export_path(name: String) -> String:
	return OS.get_environment("GINKGO_GAMEPLAY_OUTPUT").path_join(name)
func settle_roots() -> void:
	arena._begin_progress_transaction()
	for enemy: Dictionary in arena.enemies.duplicate():
		if int(enemy.generation) == 0: Fixture.kill(arena, enemy)
	arena._end_progress_transaction()
func prepare_attack(boss: Dictionary, source: Vector2, player: Vector2) -> void:
	arena.telegraphs.reset(); arena.freeze_runtime.reset()
	arena.telegraph_trace.clear(); arena.incoming_damage_trace.clear()
	arena.projectiles.clear(); arena.projectile_runtime.cancel_all(arena.projectiles)
	boss.spawn=0.0; boss.attack_timer=0.0; boss.pos=source; boss.knockback=Vector2.ZERO
	arena.player_pos=player
	arena._stats=arena.state.get_stats()
	for field: String in ["life_regen","mana_regen","shield_regen","shield_regeneration_rate","shield_recharge_rate"]: arena._stats[field]=0.0
	arena._stats.max_health=10000.0; arena._stats.max_shield=1000.0
	arena.health=10000.0; arena.shield=5.0; arena.invulnerable=0.0; arena.damage_delay=0.0
	arena._player_evasion_entropy=99.0; arena._stats.evasion=0.0
	arena._burn_immunity_until=arena.elapsed
func start_attack(boss: Dictionary) -> Dictionary:
	var before: int = arena.rng.state
	arena._start_enemy_telegraphs()
	var attack: Dictionary = arena.telegraphs.state_for(boss.id)
	check(not attack.is_empty() and arena.rng.state==before, "Actual boss starts without consuming RNG")
	return attack
func verify_attack(boss: Dictionary, tier: int) -> bool:
	var source: Vector2 = arena.world_geometry().landmarks.boss.center
	if tier == 2:
		var unmodified: Dictionary = Monsters.make_enemy(1,"rift_warden",6,source,"map_boss")
		near(boss.damage,unmodified.damage*1.15,"Actual paidII fierce modifier changes natural boss damage")
		near(boss.attack_speed,unmodified.attack_speed*1.1,"Actual paidII rapid modifier changes natural boss attack speed")
	prepare_attack(boss,source,source+Vector2(0,100))
	var attack := start_attack(boss)
	if attack.is_empty(): return false
	check(attack.center==source and attack.visual_pattern=="ginkgo_shelter_slam" and not attack.has("pulse_count"),"Single shared scheduler locks source-at-start")
	near(attack.profile.radius,240.0,"Authoritative radius240")
	near(attack.profile.windup_seconds,1.4,"Full windup1.4")
	near(attack.profile.damage_multiplier,1.2,"Contact component multiplier1.2")
	near(attack.profile.recovery_seconds,1.9*Monsters.BASE_ATTACK_SPEED/maxf(0.2,boss.attack_speed),"Original attack-speed recovery scaling")
	var contact: Dictionary = Monsters.contact_components(boss)
	for element: String in contact: near(attack.packet.base[element],contact[element]*1.2,"Frozen component budget: "+element)
	var visual: Array = arena.telegraph_visual_states()
	check(visual.size()==1 and visual[0].center==attack.center and visual[0].profile==attack.profile,"Visual snapshot reads actual frozen authority")
	report.attacks[str(tier)] = {"boss":boss.duplicate(true),"attack":attack.duplicate(true),"visual":visual.duplicate(true)}
	var expected := Defense.incoming_source_hit(attack.packet.base,arena._stats,arena.shield,arena.health,"player")
	arena._advance_enemy_telegraphs(1.399)
	check(arena.telegraph_trace.is_empty() and arena.incoming_damage_trace.is_empty(),"No early settlement before full warning")
	arena._advance_enemy_telegraphs(0.001)
	check(arena.telegraph_trace.size()==1 and arena.telegraph_trace[0].inside and arena.telegraph_trace[0].applied,"Unobstructed inside position pays exactly one real hit")
	near(arena.health,expected.remaining_health,"Shared defense exact health")
	near(arena.shield,expected.remaining_shield,"Shared defense spends shield first")
	arena._advance_enemy_telegraphs(10.0)
	check(arena.telegraph_trace.size()==1 and arena.telegraphs.active_count()==0,"Recovery never schedules another pulse")
	if tier != 1: return true
	# Original natural boss coordinate is within radius of both sides of east plinth.
	var wall: Rect2 = arena.world_geometry().walls[2]
	var sheltered := Vector2(wall.position.x-arena.PLAYER_RADIUS-2.0,source.y)
	prepare_attack(boss,source,sheltered)
	check(arena._geometry.is_clear(sheltered,arena.PLAYER_RADIUS) and source.distance_to(sheltered)<240.0 and not arena._terrain_visible(source,sheltered),"Legal in-radius source/player positions have blocked start LOS")
	arena._start_enemy_telegraphs()
	check(arena.telegraphs.active_count()==0,"Wall blocks actual attack admission")
	prepare_attack(boss,source,source+Vector2(0,100))
	attack=start_attack(boss)
	arena.player_pos=sheltered
	check(Runtime.overlaps({"shape":"circle","center":attack.center,"radius":240.0},sheltered,arena.PLAYER_RADIUS),"After-warning shelter remains geometrically inside circle")
	arena._advance_enemy_telegraphs(1.4)
	check(arena.telegraph_trace.size()==1 and not arena.telegraph_trace[0].inside and arena.incoming_damage_trace.is_empty(),"Moving behind real planter blocks actual settlement")
	prepare_attack(boss,source,source+Vector2(0,100))
	attack=start_attack(boss)
	arena.player_pos=source+Vector2(0,240.0+arena.PLAYER_RADIUS+1.0)
	check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Outside-circle safety point is legal")
	arena._advance_enemy_telegraphs(1.4)
	check(arena.telegraph_trace.size()==1 and not arena.telegraph_trace[0].inside and arena.incoming_damage_trace.is_empty(),"Outside circle stays safe")
	prepare_attack(boss,source,source+Vector2(0,100))
	attack=start_attack(boss)
	boss.knockback=Vector2(180,0)
	arena.tick(0.1)
	check(boss.pos!=source and arena.telegraphs.state_for(boss.id).center==source,"Real external impulse moves actor without dragging locked center")
	# Real cold packet from a separately owned legal Frost Lock +14209 build.
	prepare_attack(boss,source,source+Vector2(0,100))
	attack=start_attack(boss)
	arena.tick(0.5)
	var cast: Dictionary = freeze_source.cast
	arena._apply_damage_packet(boss,cast.packets.projectile,cast.snapshot,Color.WHITE,float(cast.recipe.slow),{"cast_id":8301,"projectile_id":8301,"phase":"projectile"})
	var frozen: Dictionary = arena.freeze_runtime.state_for(boss.id)
	if not check(not frozen.is_empty() and boss.health>0.0,"Actual lawful cold hit freezes living natural boss"): return false
	near(frozen.frozen_until-frozen.frozen_from,0.24,"Lawful14209 boss freeze0.24")
	var identity: int = int(attack.attack_id)
	arena.tick(0.24)
	var paused: Dictionary = arena.telegraphs.state_for(boss.id)
	check(paused.attack_id==identity and paused.center==source and paused.phase=="windup","Freeze preserves existing attack identity and locked center")
	near(paused.elapsed,0.5,"Freeze preserves prior progress")
	arena.tick(0.899)
	check(arena.telegraph_trace.is_empty(),"Resumed warning still waits original remaining duration")
	arena.tick(0.001)
	check(arena.telegraph_trace.size()==1 and arena.telegraph_trace[0].attack_id==identity and arena.telegraph_trace[0].applied,"Exact thaw-adjusted boundary resolves once")
	arena._advance_enemy_telegraphs(10.0)
	check(arena.telegraph_trace.size()==1 and arena.telegraphs.active_count()==0,"Frozen attack completes without duplicate resolution")
	report.attacks.freeze={"state":frozen,"paused":paused,"resolved":arena.telegraph_trace.duplicate(true)}
	return true

func formal_run(tier: int, order: Array, normal: Array, special: Array) -> bool:
	var before_roots: int = arena.state.normal_journey().normal_root_kills
	var before_fee: int = arena.state.crafting_balance()
	if not accepted(arena.craft_normal_map("ginkgo_arcade",tier,normal,special,arena.map_draft().revision),"Formal draft tier%d"%tier): return false
	var draft: Dictionary=arena.map_draft()
	if not accepted(arena.start_map(draft.revision),"Actual formal map start tier%d"%tier): return false
	Fixture.pause(arena)
	var completed_profile: Dictionary=arena._map_run.profile.duplicate(true)
	check(arena.state.crafting_balance()==before_fee-(tier-1)*4 and arena.world_context().fee_paid==(tier-1)*4,"Successful entry pays exact existing shard cost once")
	check(arena.wave==([3,6,10][tier-1]) and arena._map_run.profile.normal_ids==normal and arena._map_run.profile.special_ids==special,"Actual tier wave and selected modifiers reach Main")
	var geometry: Dictionary=arena.world_geometry()
	var marks: Dictionary=geometry.landmarks
	check(geometry.id=="ginkgo_arcade" and geometry.obstacle_style=="ginkgo_planters" and geometry.walls.size()==3,"Actual map has three physical ginkgo planters")
	check(arena.enemies.is_empty() and arena._map_run.snapshot().ordinary_target==36 and arena.player_pos==marks.entry,"Entry starts all36 roots dormant")
	arena.player_pos=marks.boss.trigger_center; arena._update_map_spawning(0.0)
	check(arena._map_run.boss_id==0,"Boss entrance is sealed before root kills")
	var roster: Dictionary=arena._map_camps.checkpoint()
	for index: int in order:
		arena.player_pos=marks.camps[index].trigger_center
		var before: int=arena.enemies.size()
		var rng_before: int=arena.rng.state
		arena._update_map_spawning(0.0)
		if not check(arena.enemies.size()==before+12,"Free-order trigger admits whole12-root camp"): return false
		check(arena.rng.state==rng_before,"Actual camp activation preserves gameplay RNG")
		for enemy: Dictionary in arena.enemies.slice(before):
			check(enemy.spawn==0.6 and enemy.reward_eligible and enemy.generation==0 and arena._geometry.is_clear(enemy.pos,enemy.radius),"Unreduced root retains spawn warning/reward/geometry")
		arena._update_map_spawning(0.0)
		check(arena.enemies.size()==before+12,"Repeated trigger does not duplicate camp")
	check(arena.enemies.size()==36 and arena._map_run.snapshot().admitted==36,"All three full groups coexist before any kill")
	if tier == 2:
		var frost_count := 0
		var brute_count := 0
		for enemy: Dictionary in arena.enemies:
			if enemy.template_id == "frost_guard": frost_count += 1
			if enemy.template_id == "brute": brute_count += 1
		check(frost_count>0 and brute_count==0,"PaidII frost patrol reaches actual admitted species")
	settle_roots()
	check(arena._map_run.snapshot().ordinary_kills==36 and arena.world_context().boss_phase=="ready","Exactly36 defeated roots unlock boss")
	Fixture.clear_descendants(arena)
	arena.player_pos=marks.boss.trigger_center; arena._update_map_spawning(0.0)
	var boss: Dictionary={}
	for enemy: Dictionary in arena.enemies:
		if int(enemy.id)==arena._map_run.boss_id: boss=enemy
	if not check(not boss.is_empty() and boss.map_boss_attack_id=="ginkgo_shelter_slam","Registered natural map boss owns new policy"): return false
	if not verify_attack(boss,tier): return false
	prepare_attack(boss,marks.boss.center,marks.boss.center+Vector2(0,100))
	var pending:=start_attack(boss)
	var reward_before: int=arena.reward_kills
	var resolution_before: int=int(arena.event_counts.get("enemy_telegraph_resolved",0))
	arena._begin_progress_transaction(); Fixture.kill(arena,boss); arena._end_progress_transaction()
	check(arena.telegraphs.state_for(boss.id).is_empty() and arena.reward_kills==reward_before+1,"Actual source death cancels warning and rewards once")
	arena._advance_enemy_telegraphs(10.0)
	check(int(arena.event_counts.get("enemy_telegraph_resolved",0))==resolution_before,"Canceled attack never settles later")
	arena._check_map_complete()
	check(arena.world_context().mode=="map" and not arena._map_run.complete,"Dead boss alone cannot complete while children remain queued")
	arena._flush_monster_spawns()
	var children: Array=arena.enemies.filter(func(enemy: Dictionary)->bool:return enemy.health>0.0 and enemy.root_id==boss.id and enemy.generation>0)
	check(children.size()==4,"Original boss still creates four descendants")
	for child: Dictionary in children: check(not child.reward_eligible and not child.has("map_boss_attack_id"),"Descendants gain neither root rewards nor boss policy")
	Fixture.clear_descendants(arena)
	arena._check_map_complete()
	check(arena.world_context().mode=="map_complete" and arena._map_run.complete,"Only complete full descendant cleanup completes map")
	var journey: Dictionary=arena.state.normal_journey()
	check(journey.normal_root_kills-before_roots==37 and arena.reward_kills==37,"Exactly36 roots plus boss earn progression and rewards")
	check(journey.best_tiers.ginkgo_arcade==tier and journey.pending_map_reward.shards==tier*4+normal.size()+2*special.size(),"Actual completion unlocks next tier and freezes correct pending reward")
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes(arena.build_save_path)
	arena._check_map_complete()
	check(arena.state.normal_journey()==journey and FileAccess.get_file_as_bytes(arena.build_save_path)==bytes,"Repeated completion does not settle or save twice")
	check(not arena.claim_normal_rewards(arena.world_context().revision).ok,"Pending map reward requires real town return")
	if not accepted(arena.return_to_town(arena.world_context().revision),"Actual return to formal town"): return false
	check(arena.enemies.is_empty() and arena.world_context().camp_states.is_empty() and arena.telegraphs.active_count()==0,"Town clears actors/camps/attacks")
	accepted(arena.craft_normal_map("ginkgo_arcade",mini(tier+1,3),[],[],arena.map_draft().revision),"Newly unlocked draft can be prepared")
	check(not arena.start_map(arena.map_draft().revision).ok and arena.state.normal_journey()==journey,"Pending reward blocks new run without mutation")
	var before_claim: int=arena.state.crafting_balance()
	var claimed: Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	if not accepted(claimed,"Actual map reward claim"): return false
	check(claimed.claimed_shards==tier*4+normal.size()+2*special.size() and arena.state.crafting_balance()==before_claim+claimed.claimed_shards,"Claim deposits exact reward into existing shard items")
	var after_claim: Dictionary=arena.state.snapshot()
	var repeated: Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	check(not repeated.ok and arena.state.snapshot()==after_claim,"Second claim cannot duplicate reward")
	check(Model.Rules.reason(after_claim).is_empty() and arena.state.pending_items().is_empty(),"Formal run exports fully lawful ownership model")
	save_json(export_path("formal-tier%d.json"%tier),after_claim)
	report.runs.append({"tier":tier,"profile":completed_profile,"roster":roster,"pending":journey.pending_map_reward,"claim":claimed,"roots":37,"coexisting_roots":36,"boss_children":children.size(),"draft_before_start":draft,"canceled_attack_id":pending.attack_id})
	return true

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v083-ginkgo-") or OS.get_environment("GINKGO_GAMEPLAY_OUTPUT").is_empty(): quit(78); return
	freeze_source=Fixture.lawful_freeze_source("user://lawful-freeze-source.json")
	if not accepted(freeze_source,"Same-source lawful Frost Lock fixture"): quit(1); return
	save_json(export_path("freeze-source.json"),freeze_source.model)
	save_json(export_path("freeze-cast.json"),{"cast":freeze_source.cast,"stats":freeze_source.stats})
	arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	Fixture.pause(arena)
	if not check(arena.save_build(),"Fresh formal profile saved through actual Main before admission"):
		arena.queue_free(); await process_frame; quit(1); return
	check(arena.world_context().normal_town and arena.state.normal_journey().best_tiers.ginkgo_arcade==0,"Fresh formal profile begins in town with only tierI unlocked")
	check(not arena.craft_normal_map("ginkgo_arcade",2,[],[],arena.map_draft().revision).ok and not arena.craft_normal_map("ginkgo_arcade",3,[],[],arena.map_draft().revision).ok,"Actual Main rejects initially lockedII/III")
	if formal_run(1,[2,0,1],[],[]):
		formal_run(2,[1,2,0],["enemy_attack_speed_110","enemy_damage_115"],["frost_patrol"])
	# The next successful start proves claim reopened admission without requiring
	# another redundant full battle; existing III model/economics are tested elsewhere.
	if failures==0:
		accepted(arena.craft_normal_map("ginkgo_arcade",1,[],[],arena.map_draft().revision),"Reopen completed map draft")
		accepted(arena.start_map(arena.map_draft().revision),"Claimed reward permits actual next map")
		accepted(arena.return_to_town(arena.world_context().revision),"Bounded reopened run cleanly returns")
	report.checks=checks; report.failures=failures
	save_json(export_path("main-result.json"),report)
	print("GINKGO_MAP_GAMEPLAY checks=%d failures=%d completed_runs=%d"%[checks,failures,report.runs.size()])
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
