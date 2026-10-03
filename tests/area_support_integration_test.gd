extends SceneTree
const Model = preload("res://scripts/build_state.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Data = preload("res://scripts/game_data.gd")
var arena: Node
var checks: int = 0
var failures: int = 0
var completed: bool = false
var budget_rows: Array[Dictionary] = []
const FRESH: String = "user://area_fresh.json"
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func near(actual: float, expected: float, label: String) -> void:
	expect(absf(actual-expected)<0.0001,"%s %.9f / %.9f" % [label,actual,expected])
func run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if OS.get_name()!="Linux" or not isolated.begins_with("/tmp/godot-") or not OS.get_user_data_dir().simplify_path().begins_with(isolated+"/"):
		printerr("Area write tests require disposable Linux XDG roots")
		quit(78)
		return
	var fresh := Model.new()
	expect(fresh.save_build()==OK and fresh.save_build(FRESH)==OK,"Fresh isolated scene save")
	arena=load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	for test: Callable in [_boundaries, _admission, _sequential_and_detached, _placement_budget, _migration]:
		completed=false
		test.call()
		expect(completed,"Case returned normally: " + test.get_method())
	print("AREA_BUDGET " + JSON.stringify(budget_rows))
	print("Area support integration: %d checks, %d failures" % [checks,failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
func prepare(skill: String, wide: bool) -> void:
	expect(arena.state.load_build(FRESH),"Restore complete build")
	arena.restart_run()
	arena.auto_fire=false
	arena.spawn_timer=9999.0
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.player_pos=Vector2(700,350)
	arena.player_facing=Vector2.RIGHT
	arena.hud.close_panel()
	expect(arena.state.slot_skill(0,skill),"Slot tested skill")
	var links: Array = ["breadth"] if wide else []
	if arena.state.get_skill_supports(skill)!=links:
		expect(arena.state.set_skill_supports(skill,links),"Set actual support transaction")
	expect(arena.state.get_skill_supports(skill)==links,"Prepared links match fixture")
	arena.mana=100
	arena.cooldowns[skill]=0.0
func target(at: Vector2, birth: bool=false) -> Dictionary:
	var e: Dictionary=arena._spawn_monster("crawler",at,"ordinary","normal",[])
	expect(not e.is_empty(),"Real catalog target admitted")
	e.health=10000.0
	e.max_health=10000.0
	e.shield=0.0
	e.spawn=1.0 if birth else 0.0
	return e
func pulse(skill: String) -> Dictionary:
	for cue: Dictionary in arena.visual_cues.cues:
		if cue.kind==skill: return cue
	return {}
func _boundaries() -> void:
	for skill: String in ["nova","meteor"]:
		for wide: bool in [false,true]:
			prepare(skill,wide)
			var cast: Dictionary=arena.state.get_skill_cast(skill)
			var center: Vector2=arena.player_pos
			var core: Dictionary=target(center)
			var r: float=cast.recipe.radius
			var body: float=core.radius
			var inside: Dictionary=target(center+Vector2(r+body-0.01,0))
			var edge: Dictionary=target(center+Vector2(0,r+body))
			var outside: Dictionary=target(center-Vector2(r+body+0.01,0))
			var born: Dictionary=target(center+Vector2(2,0),true)
			expect(arena.cast_skill(0),"Actual area cast accepted")
			var total: float=Damage.resolve(cast.packets.direct,cast.snapshot.modifiers).total
			for e: Dictionary in [core,inside,edge]:
				near(10000.0-e.health,total,"Inclusive radius plus actual body hit")
				near(e.slow,0.6 if skill=="nova" else 0.0,"Original per-skill slow retained")
			for e: Dictionary in [outside,born]:
				near(e.health,10000.0,"Outside and birth-protected targets untouched")
			near(arena.mana,100.0-cast.mana,"Exact compiled mana paid once")
			near(arena.cooldowns[skill],cast.cooldown,"Original cooldown paid once")
			near(pulse(skill).radius,r,"Visual pulse uses same compiled radius")
			expect(arena.projectiles.is_empty(),"Area cast creates no projectile")
			var before: float=core.health
			expect(not arena.cast_skill(0) and core.health==before,"Repeated key while cooling does not double hit")
	completed=true
func _admission() -> void:
	for skill: String in ["nova","meteor"]:
		prepare(skill,true)
		var cast: Dictionary=arena.state.get_skill_cast(skill)
		var enemy: Dictionary=target(arena.player_pos)
		arena.mana=cast.mana-0.001
		var mana_before: float=arena.mana
		expect(not arena.cast_skill(0) and arena.mana==mana_before and arena.cooldowns[skill]==0 and enemy.health==10000,"Insufficient mana rejects atomically")
		arena.state.skill_supports[skill]=["breadth","breadth"]
		arena.mana=100
		expect(not arena.cast_skill(0) and arena.mana==100 and arena.cooldowns[skill]==0,"Invalid runtime links reject before payment")
		arena.state.skill_supports[skill]=["breadth"]
		arena.mana=cast.mana
		expect(arena.cast_skill(0),"Exact cost admits")
		near(arena.mana,0,"No display rounding in payment")
	completed=true
func _sequential_and_detached() -> void:
	for skill: String in ["nova","meteor"]:
		prepare(skill,true)
		var old: Dictionary=arena.state.get_skill_cast(skill)
		var frozen: Dictionary=old.duplicate(true)
		var enemy: Dictionary=target(arena.player_pos)
		expect(arena.cast_skill(0),"First cast accepted")
		var old_cue: Dictionary=pulse(skill).duplicate(true)
		var first_damage: float=10000-enemy.health
		expect(arena.state.equip("swift_blade"),"Equip a different actual weapon")
		expect(arena.state.remove_skill_support(skill,"breadth"),"Take off area support")
		expect(old==frozen and pulse(skill)==old_cue,"Old compiled packet and already emitted pulse stay frozen")
		near(first_damage,Damage.resolve(old.packets.direct,old.snapshot.modifiers).total,"First hit retains old equipment and support")
		var fresh: Dictionary=arena.state.get_skill_cast(skill)
		expect(fresh.snapshot.base_damage!=old.snapshot.base_damage,"Equipment switch changes next cast base")
		arena.visual_cues.reset()
		arena.cooldowns[skill]=0
		arena.mana=100
		expect(arena.cast_skill(0),"Next cast accepted after cooldown fixture reset")
		near(10000-enemy.health-first_damage,Damage.resolve(fresh.packets.direct,fresh.snapshot.modifiers).total,"Next actual pulse uses new equipment and no support")
		near(pulse(skill).radius,155 if skill=="nova" else 110,"Next pulse uses original radius")
	completed=true
func _placement_budget() -> void:
	for skill: String in ["nova","meteor"]:
		for layout: String in ["single","cluster","outer_band"]:
			var rows: Dictionary={"skill":skill,"layout":layout}
			for wide: bool in [false,true]:
				prepare(skill,wide)
				var cast: Dictionary=arena.state.get_skill_cast(skill)
				var base_r: float=155 if skill=="nova" else 110
				var targets: Array[Dictionary]=[target(arena.player_pos)]
				if layout!="single":
					for i: int in range(1,5):
						var distance: float=base_r*0.55 if layout=="cluster" else base_r*1.15+12.0
						targets.append(target(arena.player_pos+Vector2.RIGHT.rotated(i*TAU/4.0)*distance))
				expect(arena.cast_skill(0),"Budget uses actual scene settlement")
				var hits: int=0
				var total: float=0
				for e: Dictionary in targets:
					if e.health<10000: hits+=1
					total+=10000-e.health
				rows["wide" if wide else "base"]={"hits":hits,"total":total,"mana":cast.mana,"radius":cast.recipe.radius}
			if layout=="outer_band":
				expect(rows.base.hits==1 and rows.wide.hits==5,"Only expanded coverage reaches outer band")
			else:
				expect(rows.base.hits==rows.wide.hits,"Covered cluster does not invent extra hits")
				near(rows.wide.total,rows.base.total*0.85,"Sparse and already-covered group lose 15% total hit damage")
			budget_rows.append(rows)
	completed=true
func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	expect(file!=null,"Write isolated fixture")
	if file!=null: file.store_buffer(bytes)
func _migration() -> void:
	var text: String=FileAccess.get_file_as_string("res://tests/fixtures/area_v11_build.json")
	var bytes: PackedByteArray=PackedByteArray([239,187,191])
	bytes.append_array(("\r\n"+text.replace("\n","\r\n")+"\r\n").to_utf8_buffer())
	var path: String="user://area_legacy_v11.json"
	write_bytes(path,bytes)
	var state:=Model.new()
	expect(state.load_build(path) and state.migrated_from_v11,"Literal v11 rich build migrates")
	var expected: Dictionary=JSON.parse_string(text)
	expected.version=Model.SAVE_VERSION
	for key: String in ["next_equipment_id", "level", "xp", "talent_points", "next_jewel_id"]:
		expected[key]=int(expected[key])
	for item: Dictionary in expected.equipment_instances.values():
		item.item_level=int(item.item_level)
		for affix: Dictionary in item.affixes:
			affix.tier=int(affix.tier)
			affix.value=int(affix.value)
	for key: String in expected.backpack_positions:
		var position: Array=expected.backpack_positions[key]
		expected.backpack_positions[key]=[int(position[0]),int(position[1])]
	expected.crafting={"materials":{"calibration_shard":17},"revision":7}
	expect(state._snapshot()==expected,"All 17 fields, wallet revision, gear, special remote nodes and old links unchanged")
	expect(state.save_build(path)==OK and FileAccess.get_file_as_bytes(path+".v11-backup.json")==bytes,"Migration saves exact original BOM/CRLF bytes before replacement")
	expect(state.set_skill_supports("nova",["breadth"]) and state.set_skill_supports("meteor",["breadth"]),"Independent per-skill supports persist")
	expect(state.save_build(path)==OK,"Current schema saves links")
	var current: Dictionary=state._snapshot()
	var again:=Model.new()
	expect(again.load_build(path) and not again.migrated_from_v11 and again._snapshot()==current,"Current roundtrip does not remigrate or add rewards")
	expect(FileAccess.get_file_as_bytes(path+".v11-backup.json")==bytes,"Original migration backup remains immutable")
	var quote: Dictionary=again.crafting_quote("salvage","gear_000045",path)
	# Worn equipment correctly refuses; load still clears any issued handles.
	expect(not quote.ok,"Legacy worn item still obeys crafting ownership")
	again._craft_quotes["stale"]={}
	expect(again.load_build(path) and again._craft_quotes.is_empty(),"Loading clears ephemeral quotes")
	var injected: Dictionary=current.duplicate(true)
	injected.version=11
	var rejected: String="user://area_injected_v11.json"
	var raw: PackedByteArray=JSON.stringify(injected).to_utf8_buffer()
	write_bytes(rejected,raw)
	var untouched: Dictionary=again._snapshot()
	expect(not again.load_build(rejected) and again._snapshot()==untouched,"v11 injected new ID rejects whole candidate")
	expect(again.save_build(rejected)!=OK and FileAccess.get_file_as_bytes(rejected)==raw,"Rejected source is write protected")
	injected.version=Model.SAVE_VERSION+1
	var future: String="user://area_future_v13.json"
	raw=JSON.stringify(injected).to_utf8_buffer()
	write_bytes(future,raw)
	expect(not again.load_build(future) and again.save_build(future)!=OK and FileAccess.get_file_as_bytes(future)==raw,"Future schema cannot be overwritten")
	completed=true
