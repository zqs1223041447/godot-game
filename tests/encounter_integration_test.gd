extends SceneTree
const Compiler = preload("res://scripts/encounters/encounter_compiler.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const BOTH: Array[String] = ["enemy_max_health_120","enemy_move_speed_110"]
var arena: Node2D
var checks: int = 0
var failures: int = 0

class FaultRuntime extends "res://scripts/monsters/monster_runtime.gd":
	var fault: String = ""
	func create_root(template_id: String, wave: int, position: Vector2, context: String = "ordinary", rarity: String = "", mechanisms: Array = [], rewards: bool = true) -> Dictionary:
		var result: Dictionary = super.create_root(template_id,wave,position,context,rarity,mechanisms,rewards)
		if fault == "root" and not result.is_empty(): result.health = float(result.max_health)+1.0
		return result
	func drain(available: int, bounds: Rect2) -> Array[Dictionary]:
		var result: Array[Dictionary] = super.drain(available,bounds)
		if fault == "child" and not result.is_empty(): result.back().speed = -1.0
		return result

func _initialize() -> void: call_deferred("_run")
func _expect(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _near(actual: float,expected: float,label: String) -> void:
	_expect(is_finite(actual) and absf(actual-expected)<0.00001,"%s: %.8f / %.8f" %[label,actual,expected])

func _run() -> void:
	if OS.get_name()!="Linux" or not OS.get_data_dir().begins_with("/tmp/godot-"):
		push_error("Encounter integration requires isolated Linux XDG storage")
		quit(78)
		return
	arena=load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_test_selection()
	_test_real_admission()
	_test_descendants()
	_test_failures()
	_test_scope_and_reset()
	arena.free()
	print("Encounter integration: %d checks, %d failures" %[checks,failures])
	quit(1 if failures else 0)

func _setup(ids: Array = []) -> void:
	arena.monster_runtime=Runtime.new()
	_expect(arena.start_encounter(ids,int(arena.run_revision)),"Valid selection starts a fresh run")
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.auto_fire=false
	arena.spawn_timer=99999.0
	arena.player_pos=arena.ARENA.get_center()
	arena.invulnerable=99999.0
	arena.rng.seed=170017
	arena.wave=3
	arena.ordinary_admissions=0

func _runtime() -> Dictionary:
	return {"roots":arena.monster_runtime.roots.duplicate(true),"queue":arena.monster_runtime.queue.duplicate(true),"trace":arena.monster_runtime.trace.duplicate(true),"next_id":arena.monster_runtime.next_id}
func _snapshot() -> Dictionary:
	return {"runtime":_runtime(),"rng":arena.rng.state,"admissions":arena.ordinary_admissions,"enemies":arena.enemies.duplicate(true),
		"profile":arena._encounter_profile.duplicate(true),"selected":arena.encounter_selection(),"build":arena.state._snapshot(),
		"revision":arena.run_revision,"elapsed":arena.elapsed,"wave":arena.wave,"kills":arena.kills,"projectiles":arena.projectiles.duplicate(true)}

func _test_selection() -> void:
	_setup()
	var before: Dictionary=_snapshot()
	for invalid: Variant in [null,true,{},"enemy_max_health_120",["unknown"],[BOTH[0],BOTH[0]],[BOTH[0],BOTH[1],"third"]]:
		_expect(not arena.start_encounter(invalid,arena.run_revision),"Invalid selection is refused")
		_expect(_snapshot()==before,"Invalid selection consumes no RNG, identity, build state or run")
	_expect(not arena.start_encounter(BOTH,int(arena.run_revision)-1) and _snapshot()==before,"Stale confirmation cannot replace a newer run")
	for invalid_revision: Variant in [null,true,float(arena.run_revision),str(arena.run_revision)]:
		_expect(not arena.start_encounter(BOTH,invalid_revision) and _snapshot()==before,"Revision is an exact integer, not a coerced value")
	var build: Dictionary=arena.state._snapshot()
	var saved: PackedByteArray=FileAccess.get_file_as_bytes("user://build_save.json") if FileAccess.file_exists("user://build_save.json") else PackedByteArray()
	_expect(arena.start_encounter([BOTH[1],BOTH[0]],arena.run_revision),"Reverse-order selection starts")
	_expect(arena.encounter_selection()==BOTH and arena._encounter_profile.is_read_only(),"Run owns one canonical frozen profile")
	var copy: Array=arena.encounter_selection();copy.clear()
	_expect(arena.encounter_selection()==BOTH,"Selection getter cannot mutate the active run")
	_expect(arena.state._snapshot()==build,"Challenge restart preserves every build field including crafting")
	var after_saved: PackedByteArray=FileAccess.get_file_as_bytes("user://build_save.json") if FileAccess.file_exists("user://build_save.json") else PackedByteArray()
	_expect(after_saved==saved,"Selecting challenge does not persist a new field or rewrite build")
	_expect(arena.enemies.size()==3 and arena.elapsed==0.0 and arena.kills==0,"Accepted challenge restarts real opening admissions")
	for enemy: Dictionary in arena.enemies:
		_expect(enemy.has("encounter_source") and enemy.encounter_source.profile==arena._encounter_profile,"Opening source receives selected profile once")

func _test_real_admission() -> void:
	var observations: Array[Dictionary]=[]
	for ids: Array in [[],[BOTH[0]],[BOTH[1]],BOTH]:
		_setup(ids)
		var compiled: Dictionary=Compiler.compile(ids)
		for index: int in range(16):
			var enemy: Dictionary=arena._spawn_enemy()
			_expect(not enemy.is_empty(),"Natural root admission succeeds")
			_expect((enemy.template_id=="ember_guard")==((index+1)%8==0),"Challenge retains natural guard cadence")
			var canonical: Dictionary=Catalog.make_enemy(enemy.id,enemy.template_id,enemy.wave,enemy.pos,"ordinary",enemy.rarity,enemy.mechanism_ids)
			_near(enemy.max_health,float(canonical.max_health)*float(compiled.profile.multipliers.max_health),"Root life uses one post-catalog multiplier")
			_near(enemy.speed,float(canonical.speed)*float(compiled.profile.multipliers.speed),"Root movement uses one post-catalog multiplier")
			for field: String in ["damage","attack_speed","shield","max_shield","resistances","contact_weights","radius","xp_reward","reward_eligible"]:
				_expect(enemy[field]==canonical[field],"Challenge preserves root "+field)
			_expect(enemy.has("encounter_source")==not ids.is_empty(),"Ordinary run has no new marker; challenge has exactly one")
			if not ids.is_empty():
				_expect(not Compiler.apply_to_enemy(enemy,compiled.profile).ok,"Live challenged source refuses a second transform")
		observations.append({"rng":arena.rng.state,"templates":arena.enemies.map(func(e: Dictionary)->String:return e.template_id),"admissions":arena.ordinary_admissions})
	for sample: Dictionary in observations:
		_expect(sample==observations[0],"Application adds no RNG calls or natural admission differences")
	_setup(BOTH)
	var moving: Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(200,0))
	moving.spawn=0.0
	var x: float=moving.pos.x
	arena._update_enemies(0.1)
	# Vector2 stores float32 coordinates near world x=1200: two position ULPs
	# are smaller than 0.0002 units, far below the 0.682-unit speed difference.
	_expect(absf(x-float(moving.pos.x)-float(moving.speed)*0.1)<0.0002,"Actual AI consumes challenged movement speed within float32 position precision")
	var guard: Dictionary=arena._spawn_monster("ember_guard",arena.player_pos+Vector2(130,0))
	guard.spawn=0.0;guard.attack_timer=0.0
	arena._start_enemy_telegraphs()
	var attack: Dictionary=arena.telegraphs.state_for(guard.id)
	_expect(not attack.is_empty(),"Challenged guard uses real v0.16 warning")
	_near(attack.profile.windup_seconds,0.7,"Challenge cannot shorten warning")
	_near(attack.packet.base.fire,float(guard.damage)*0.7,"Health/movement challenge leaves typed heavy damage unchanged")

func _test_descendants() -> void:
	_setup(BOTH)
	var root_enemy: Dictionary=arena._spawn_monster("brood_host",arena.player_pos+Vector2(100,0))
	root_enemy.spawn=0.0
	arena._damage_enemy(root_enemy,root_enemy.health+root_enemy.shield+1.0,Color.WHITE)
	var build: Dictionary=arena.state._snapshot()
	var rewarded: int=arena.reward_kills
	arena._flush_monster_spawns()
	_expect(arena.enemies.size()==2 and rewarded==1,"Root death retains one reward and two children")
	var total: int=1
	while not arena.enemies.is_empty():
		var round: Array=arena.enemies.duplicate()
		for enemy: Dictionary in round:
			_expect(enemy.encounter_source.profile==arena._encounter_profile and not enemy.reward_eligible and enemy.xp_reward==0,"Each real descendant receives frozen challenge without rewards")
			_near(enemy.max_health,float(enemy.encounter_source.before.max_health)*1.2,"Descendant scales its own fresh canonical life once")
			enemy.spawn=0.0
			arena._damage_enemy(enemy,enemy.health+enemy.shield+1.0,Color.WHITE)
			total+=1
		arena._flush_monster_spawns()
	_expect(total==9 and arena.reward_kills==rewarded,"Real child/grandchild lifecycle has nine actors and one reward")
	_expect(arena.state._snapshot()==build,"All descendant kills add no XP, material, equipment or jewel rewards")
	_expect(arena.monster_runtime.roots.is_empty() and arena.monster_runtime.queue.is_empty(),"Completed challenged lineage releases its bounded state")

func _test_failures() -> void:
	_setup(BOTH)
	var valid: Dictionary=arena._encounter_profile
	var malformed: Dictionary=valid.duplicate(true);malformed.multipliers.max_health=1.21
	arena._encounter_profile=malformed
	var before: Dictionary=_snapshot()
	_expect(arena._spawn_enemy().is_empty() and _snapshot()==before,"Tampered profile rejects before RNG, root identity and natural counters")
	arena._encounter_profile=Compiler.compile([]).profile
	before=_snapshot()
	_expect(arena._spawn_enemy().is_empty() and _snapshot()==before,"Valid but mismatched profile cannot silently degrade to ordinary enemies")
	arena._encounter_profile=valid
	var faulty:=FaultRuntime.new()
	arena.monster_runtime=faulty
	faulty.fault="root"
	before=_snapshot()
	_expect(arena._spawn_enemy().is_empty(),"Post-factory invalid root is rejected")
	_expect(_snapshot()==before,"Failed root restores RNG, IDs, roots, traces and all progression")
	faulty.fault=""
	var parent: Dictionary=arena._spawn_monster("brood_host",arena.player_pos+Vector2(100,0))
	parent.spawn=0.0
	arena._damage_enemy(parent,parent.health+parent.shield+1.0,Color.WHITE)
	var runtime_before: Dictionary=_runtime()
	var rng_before: int=arena.rng.state
	var build: Dictionary=arena.state._snapshot()
	faulty.fault="child"
	arena._flush_monster_spawns()
	_expect(arena.enemies.is_empty() and _runtime()==runtime_before,"Any child transform failure rolls back the entire drain batch")
	_expect(arena.rng.state==rng_before and arena.state._snapshot()==build,"Failed drain grants nothing and consumes no RNG")
	faulty.fault=""
	arena._flush_monster_spawns()
	_expect(arena.enemies.size()==2 and arena.monster_runtime.next_id==int(runtime_before.next_id)+2,"Retry admits original children with no identity gaps from failed batch")
	_expect(arena.enemies[0].id==int(runtime_before.next_id)+1 and arena.enemies[1].id==int(runtime_before.next_id)+2,"Retry preserves original FIFO identity order")
	_setup(BOTH)
	parent=arena._spawn_monster("splitter",arena.player_pos+Vector2(100,0));parent.spawn=0.0
	arena._damage_enemy(parent,parent.health+parent.shield+1.0,Color.WHITE)
	arena.monster_runtime.queue[0].template="missing_template"
	runtime_before=_runtime()
	arena._flush_monster_spawns()
	_expect(arena.enemies.is_empty() and _runtime()==runtime_before,"Factory omission cannot silently discard a failed queued child")

func _test_scope_and_reset() -> void:
	_setup(BOTH)
	for index: int in range(100):
		_expect(not arena._spawn_monster("crawler",arena.player_pos+Vector2(300,0)).is_empty(),"Challenge admits a real source below capacity")
	var before: Dictionary=_snapshot()
	_expect(arena._spawn_enemy().is_empty() and _snapshot()==before,"101st challenged source consumes no RNG or identity")
	var build: Dictionary=arena.state._snapshot()
	arena.restart_run()
	_expect(arena.encounter_selection()==BOTH and arena.enemies.size()==3,"Ordinary retry retains this run's selection")
	for enemy: Dictionary in arena.enemies: _expect(enemy.has("encounter_source"),"Retried opening sources retain challenge")
	arena.restore_standard_run()
	_expect(arena.encounter_selection().is_empty(),"Explicit restore-standard clears selection")
	for enemy: Dictionary in arena.enemies: _expect(not enemy.has("encounter_source"),"Restored ordinary sources preserve legacy shape")
	for method: String in ["start_monster_demo","start_density_demo"]:
		arena.start_encounter(BOTH,arena.run_revision)
		arena.call(method)
		_expect(arena.encounter_selection().is_empty(),"Demo modes explicitly clear challenge: "+method)
		for enemy: Dictionary in arena.enemies: _expect(not enemy.has("encounter_source") and not enemy.reward_eligible,"Demo source remains canonical and rewardless")
	_expect(arena.state._snapshot()==build,"All run transitions preserve the complete build")
	var fresh=load("res://scenes/main.tscn").instantiate()
	fresh.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(fresh);fresh.set_process(false)
	_expect(fresh.encounter_selection().is_empty(),"A newly loaded scene starts with ordinary selection; challenges are not saved")
	fresh.free()
