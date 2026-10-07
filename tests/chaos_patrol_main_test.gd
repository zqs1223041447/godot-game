extends "res://tests/exploration_main_flow_test.gd"
const RingFixture = preload("res://tests/chaos_resistance_equipment_test.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
var guard: Dictionary = {}
var rows: Array = []
var ring_ids: Array[String] = []

func run() -> void:
	var file := FileAccess.open("user://build_save.json",FileAccess.WRITE)
	if not check(file!=null,"Isolated former Main/UI save writable"):quit(1);return
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/v091-root-ui/main-after-reforge.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	if not check(arena.world_context().normal_town and arena.state.pending_items().is_empty(),"Actual normal town loaded prior lawful fixture and migration"):await finish();return
	if not setup():await finish();return
	arena.rng.seed=93001
	var balance: int=arena.state.crafting_balance()
	if not accepted(arena.craft_normal_map("ginkgo_arcade",2,[],["chaos_patrol"],arena.map_draft().revision),"Formal optional chaos patrol draft"):await finish();return
	check(arena.map_draft().cost==4 and arena.map_draft().completion_reward==10,"Original tierII fee4 and special completion8+2")
	if not accepted(arena.start_map(arena.map_draft().revision),"Formal staged chaos map entry"):await finish();return
	pause()
	check(arena.state.crafting_balance()==balance-4,"Map charges tier fee exactly once")
	check(arena.enemies.size()==37 and arena.map_spawn_records().size()==37 and arena.world_context().outpost_states.size()==6,"All37 initial roots plus six outpost state records")
	check(arena.world_context().awake_monsters==0 and arena._map_run.boss_id>0,"Complete roster sleeps; boss already resident")
	for enemy: Dictionary in arena.enemies:
		if enemy.template_id=="chaos_guard" and guard.is_empty():guard=enemy
	if not check(not guard.is_empty(),"Actual seeded map contains optional guardian"):await finish();return
	check(guard.resistances.chaos==0.25 and guard.contact_weights=={"chaos":1.0},"Actual guardian carries only authored chaos attack and resistance")
	check(guard.root_id==guard.id and guard.generation==0 and guard.reward_eligible,"Replacement owns original root reward identity")
	var ids_before: Array=ids();var records_before: Array=arena.map_spawn_records()
	arena.tick(0.7)
	check(ids()==ids_before and arena.world_context().awake_monsters==0 and arena.reward_kills==0,"Entry idle advances birth protection without new spawn or combat")
	if not offensive_probe():await finish();return
	if not incoming_probes():await finish();return
	check(ids()==ids_before and arena.map_spawn_records()==records_before,"Controlled actual consumers retain all original entity IDs and spawn records")
	if not completion_probe():await finish();return
	await finish()

func setup() -> bool:
	# Controlled progression and legal generated-item fixtures, not natural loot.
	var candidate: Dictionary=arena.state.snapshot()
	candidate.journey.best_tiers.ginkgo_arcade=1;candidate.revision+=1
	if not accepted(arena.state._commit(candidate,arena.build_save_path),"Lawful isolated tierII progress fixture"):return false
	for slot: String in ["ring_1","ring_2"]:
		if arena.state.equipped_items().has(slot):
			var old_uid: String=arena.state.equipped_items()[slot]
			if not accepted(arena.state.move_item(old_uid,arena.state.first_bag_position(old_uid),arena.state.revision(),arena.build_save_path),"Move existing ring safely to bag"):return false
		var uid: String="gear_%06d" % int(arena.state.snapshot().next_item_serial)
		var item: Dictionary=RingFixture.legal_ring(uid)
		if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)),"Same legal ring fixture used by rule/model checks"):return false
		if not accepted(arena.state.move_item(uid,{"kind":"equipment","slot_id":slot},arena.state.revision(),arena.build_save_path),"Real guarded equip to "+slot):return false
		ring_ids.append(uid)
	check(arena.state.get_chaos_resistance_profile().effective==0.5,"Two actual rings supply50%, not75%")
	check(arena._stats.chaos_resistance==0.5 and arena._stats==arena.state.get_stats(),"Main changed signal consumes exact canonical gear stats")
	FileAccess.open("res://docs/qa/v093-integration/equipped-fixture.json",FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
	return failures==0

func offensive_probe() -> bool:
	var cast: Dictionary=Compiler.compile_skill("shade_bolt",arena.state.get_combat_snapshot(),[])
	if not accepted(cast,"Existing shade bolt uses genuine current compiler"):return false
	var packet: Dictionary=cast.packets.projectile
	var before: Dictionary=Damage.resolve(packet,cast.snapshot.modifiers,{})
	var expected: Dictionary=Damage.resolve(packet,cast.snapshot.modifiers,guard.resistances)
	guard.spawn=0.0;guard.health=1000.0;guard.max_health=1000.0;guard.shield=100.0;guard.max_shield=100.0
	arena._apply_damage_packet(guard,packet,cast.snapshot,Color.WHITE)
	if not check(not arena.damage_trace.is_empty(),"Actual player damage receipt recorded"):return false
	var receipt: Dictionary=arena.damage_trace[-1]
	near(receipt.total,expected.total,"Player attack uses guardian resistance exactly once")
	near(receipt.components.chaos,before.components.chaos*0.75,"Existing chaos component reduced25%")
	near(guard.shield,100.0-expected.total,"Chaos damage still consumes guardian shield first")
	near(guard.health,1000.0,"No implicit chaos bypass")
	check(guard.exploration_awake,"Actual distant damage wakes existing guardian")
	rows.append({"probe":"shade_bolt","packet":packet,"before":before,"expected":expected,"receipt":receipt})
	return failures==0

func reset_attack() -> void:
	arena.telegraphs.reset();arena.freeze_runtime.reset();arena.invulnerable=0.0
	arena._burn_immunity_until=arena.elapsed;arena._burn_incoming_time=-1.0
	arena._stats=arena.state.get_stats();arena._stats.evasion=0.0
	# Controlled resource ceiling only; the50% resistance remains real equipment.
	arena._stats.max_health=500.0;arena._stats.max_shield=500.0;arena._stats.max_mana=500.0
	arena.health=500.0;arena.shield=5.0;arena.mana=200.0;arena.alive=true
	for enemy: Dictionary in arena.enemies:enemy.attack_timer=999.0
	guard.spawn=0.0;guard.attack_timer=0.0;guard.exploration_awake=true
	guard.pos=arena.ARENA.position+Vector2(1200,2150)
	arena.player_pos=guard.pos+Vector2(40,0)

func incoming_probes() -> bool:
	reset_attack();arena._start_enemy_telegraphs()
	var started: Dictionary=arena.telegraphs.state_for(guard.id)
	if not check(not started.is_empty(),"Actual active guardian starts existing scheduler"):return false
	check(started.visual_pattern=="chaos_guard" and started.packet.base.keys()==["chaos"],"Visual identity and authoritative packet are frozen together")
	var expected: Dictionary=Defense.incoming_source_hit(started.packet.base,arena._stats,5.0,500.0,"player")
	arena._advance_enemy_telegraphs(0.4)
	check(arena.shield==5.0 and arena.health==500.0,"Readable windup has no early damage")
	arena._advance_enemy_telegraphs(0.6)
	if not check(not arena.incoming_damage_trace.is_empty(),"Real telegraph applies incoming receipt"):return false
	near(arena.shield,expected.remaining_shield,"Equipment chaos resistance then actual shield consumption")
	near(arena.health,expected.remaining_health,"Only unabsorbed post-resistance damage reaches life")
	rows.append({"probe":"guardian_hit","expected":expected,"receipt":arena.incoming_damage_trace[-1]})
	reset_attack();arena._start_enemy_telegraphs();var center: Vector2=arena.telegraphs.state_for(guard.id).center
	arena.player_pos=center+Vector2(130,0);arena._advance_enemy_telegraphs(1.0)
	check(arena.shield==5.0 and arena.health==500.0 and not arena.telegraph_trace[-1].inside,"Walking out of locked circle avoids hit")
	reset_attack();var corner: Vector2=arena.world_geometry().walls[0].position
	guard.pos=corner+Vector2(-70,40);arena.player_pos=corner+Vector2(-15,40)
	check(arena._geometry.is_clear(guard.pos,guard.radius) and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Wall probe starts at legal external positions")
	arena._start_enemy_telegraphs();started=arena.telegraphs.state_for(guard.id)
	if not check(not started.is_empty(),"Guardian sees and locks first side of real wall"):return false
	arena.player_pos=corner+Vector2(40,-15)
	check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS) and arena.TelegraphRuntime.overlaps({"shape":"circle","radius":started.profile.radius,"center":started.center},arena.player_pos,arena.PLAYER_RADIUS) and not arena._terrain_visible(started.center,arena.player_pos),"Player remains in radius across occluding corner")
	arena._advance_enemy_telegraphs(1.0)
	check(arena.health==500.0 and arena.shield==5.0 and not arena.telegraph_trace[-1].applied,"Actual wall LOS blocks chaos attack")
	reset_attack();arena._start_enemy_telegraphs();arena._advance_enemy_telegraphs(0.4)
	var locked: Dictionary=arena.telegraphs.state_for(guard.id)
	# Reuse existing actual freeze-derived prefix contract, no new timing rules.
	arena._advance_enemy_telegraphs(0.8,{int(guard.id):0.6})
	near(arena.telegraphs.state_for(guard.id).elapsed,0.6,"Frozen prefix pauses local action and resumes remaining delta")
	check(arena.telegraphs.state_for(guard.id).center==locked.center and arena.health==500.0,"Freeze does not retarget or hit early")
	arena._advance_enemy_telegraphs(0.4)
	check(arena.health<500.0 and arena.telegraph_trace[-1].applied,"Existing action finishes after preserved remaining windup")
	return failures==0

func completion_probe() -> bool:
	arena.telegraphs.reset();arena.invulnerable=100.0
	var killed_before: int=arena.reward_kills
	arena._begin_progress_transaction()
	kill(actor(arena._map_run.boss_id))
	arena._end_progress_transaction()
	check(arena._map_run.boss_defeated and not arena._map_run.complete,"Optional patrol still permits boss-first without premature completion")
	arena._begin_progress_transaction()
	for enemy: Dictionary in arena.enemies.duplicate():kill(enemy)
	arena._end_progress_transaction()
	for iteration: int in range(8):
		arena._flush_monster_spawns()
		if arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty():break
		arena._begin_progress_transaction()
		for enemy: Dictionary in arena.enemies.duplicate():kill(enemy)
		arena._end_progress_transaction()
	arena._flush_monster_spawns();arena._check_map_complete()
	if not check(arena._map_run.complete and arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty(),"All initial actors and bounded descendants complete optional map"):return false
	check(arena.reward_kills-killed_before==37,"Guardian roots receive exactly original one-time rewards; children none")
	check(arena.state.normal_journey().pending_map_reward.shards==10,"Actual optional map awards original8+2completion budget")
	var frozen: Dictionary=observation();arena._check_map_complete();check(observation()==frozen,"Duplicate completion has no state, save or RNG effect")
	if not return_to_town("Complete chaos encounter returns to town"):return false
	var balance: int=arena.state.crafting_balance()
	var claimed: Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	if not accepted(claimed,"Claim actual optional completion reward once"):return false
	check(claimed.claimed_shards==10 and arena.state.crafting_balance()==balance+10,"Exact10shards credited")
	frozen=observation();var repeat: Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	check(not repeat.ok and observation()==frozen,"Repeated reward request is atomic no-op")
	return failures==0

func finish() -> void:
	var out: Dictionary={"checks":checks,"failures":failures,"labels":labels,"rings":ring_ids,"receipts":rows,"scope":"Actual Main formal map, lawful two-ring/progression fixture, controlled combat probes and deaths; not natural play or FPS"}
	FileAccess.open("res://docs/qa/v093-integration/main-result.json",FileAccess.WRITE).store_string(JSON.stringify(out,"\t",true,true))
	print("CHAOS_MAIN ",checks," checks, ",failures," failures")
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
