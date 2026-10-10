extends "res://tests/encircling_cleave_main_test.gd"
## Reuse the committed owned-cleave fixture, merchant, actor and cast helpers.
var comparisons := 0
var owned: Dictionary = {}
var impulse_samples: Array = []

func vector_near(actual: Vector2, expected: Vector2, label: String) -> bool:
	return check(actual.distance_to(expected)<0.002,label+": "+str(actual)+" / "+str(expected))

func compile_checks() -> void:
	var old = load("/tmp/godot-cleave-inward-baseline/skill_compiler.gd")
	for stats: Dictionary in [{"damage":26.0},{"damage":26.0,"attack_added_physical":5.0,"attack_added_fire":3.0,"melee_area_size_increased":0.25}]:
		var source: Dictionary = Compiler.Recipes.snapshot(stats,[])
		for skill: String in Compiler.Data.SKILLS:
			var choices: Array = [[]]
			for support: String in old.Supports.supports_for_skill(skill): choices.append([support])
			for links: Array in choices:
				var previous: Dictionary = old.compile_group(skill,source,links)
				check(previous.ok and var_to_bytes(previous)==var_to_bytes(Compiler.compile_group(skill,source,links)),"Old/current whole cast bytes: "+skill+str(links))
				comparisons+=1
		for links: Array in [[],["encircling_cleave"],["breadth"],["concentrate"],["encircling_cleave","breadth","physical_focus","efficiency"]]:
			var original: Dictionary = Compiler.compile_group("cleave",source,links)
			var selected := links+["inward_pull"]
			var pulled: Dictionary = Compiler.compile_group("cleave",source,selected)
			check(pulled.ok and not old.compile_group("cleave",source,selected).ok,"Explicit former rejection becomes supported melee control")
			if not pulled.ok: continue
			selected.reverse()
			check(var_to_bytes(pulled)==var_to_bytes(Compiler.compile_group("cleave",source,selected)),"Five-slot order independent")
			check(pulled.recipe==original.recipe and pulled.packets==original.packets and pulled.snapshot.modifiers==original.snapshot.modifiers,"Angle/radius/typed damage recipe and modifiers unchanged")
			check(pulled.cooldown==original.cooldown and pulled.get("critical",{})==original.get("critical",{}) and pulled.get("leech",{})==original.get("leech",{}),"Cooldown/critical/leech policy unchanged")
			near(pulled.mana,original.mana*1.2,"Mana multiplier only")
			check(pulled.snapshot.area_impulse_policy==pulled.area_impulse_profile,"Cast carries independent frozen impulse policy")
			check(pulled.packets.direct.tags==["hit","attack","melee","area"],"Cleave keeps actual attack/melee/area tags")
		for skill: String in ["nova","meteor"]:
			var links: Array = ["inward_pull","ambush","breadth","quickcast"]
			check(var_to_bytes(old.compile_group(skill,source,links))==var_to_bytes(Compiler.compile_group(skill,source,links)),"Old four-support spell/trap combination exact: "+skill)
			comparisons+=1

func link(ids: Array) -> bool:
	for uid: String in arena.state.skill_group(group_id).support_uids:
		if not uid.is_empty() and not accepted(arena.state.move_item(uid,arena.state.first_bag_position(uid),arena.state.revision(),arena.build_save_path),"Return linked exact UID to bag"): return false
	for index: int in range(ids.size()):
		if not check(owned.has(ids[index]),"Reuse actually owned support "+ids[index]): return false
		if not accepted(arena.state.move_item(owned[ids[index]],{"kind":"skill_support","group_id":group_id,"index":index},arena.state.revision(),arena.build_save_path),"Link exact UID "+ids[index]): return false
	return true

func park() -> void:
	for enemy: Dictionary in arena.enemies:
		enemy.pos=arena.ARENA.position+Vector2(3200,200);enemy.spawn=0.0;enemy.attack_timer=999.0;enemy.knockback=Vector2.ZERO

func sector_case(links: Array) -> bool:
	if not link(links): return false
	park();arena.player_pos=arena.ARENA.position+Vector2(600,1600)
	var offsets: Array[Vector2]=[Vector2(50,0),Vector2(-70,0),Vector2(140,0),Vector2(65,20),Vector2(60,-20)]
	for index: int in range(offsets.size()): prep_actor(arena.enemies[index],arena.player_pos+offsets[index],5.0)
	arena.enemies[3].spawn=0.5
	arena.enemies[4].evasion=1e10;arena.enemies[4].evasion_entropy=0.0
	var current: Dictionary=arena.state.get_group_cast(group_id)
	ready_cast();arena.mana=float(current.mana)-0.001
	var rejected:=spell_state()
	check(not arena.cast_group(group_id) and spell_state()==rejected,"Insufficient mana preserves actors, entropy, cooldown and disk")
	if links.has("inward_pull"):
		ready_cast()
		var invalid: Dictionary=current.duplicate(true)
		invalid.snapshot.area_impulse_policy.impulse_speed=191.0
		rejected=spell_state()
		check(not arena._execute_compiled(invalid,group_id,active_uid) and spell_state()==rejected,"Malformed impulse policy rejects before any payment or mutation")
	ready_cast();arena.attack_admission_trace.clear()
	var mana_before: float=arena.mana
	var oracle:=CritRuntime.new();oracle.restore(arena.critical_runtime.checkpoint())
	var frozen: Dictionary=oracle.freeze(current.snapshot)
	var expected: Dictionary=HitDamage.resolve(current.packets.direct,current.snapshot.modifiers,{},float(frozen.snapshot.get("critical_roll",{}).get("multiplier",1.0)))
	if not check(arena.cast_group(group_id),"Actual owned cleave cast "+str(links)): return false
	near(arena.mana,mana_before-float(current.mana),"Successful cast pays exact compiled mana once")
	var ring: bool=links.has("encircling_cleave")
	var pulling: bool=links.has("inward_pull")
	check(arena.damage_trace.size()==(2 if ring else 1),"Only original sector/circle geometry admits targets")
	check(arena.attack_admission_trace.size()==(3 if ring else 2),"Each eligible attack rolls accuracy exactly once")
	check(arena.critical_runtime.checkpoint()==oracle.checkpoint(),"One original critical freeze")
	for index: int in range(offsets.size()):
		var hit: bool=index==0 or (index==1 and ring)
		check((float(arena.enemies[index].health)<10000.0)==hit,"Actual hit, not geometry alone: target "+str(index))
		var impulse: Vector2 = -offsets[index].normalized()*190.0 if hit and pulling else Vector2.ZERO
		vector_near(arena.enemies[index].knockback,impulse,"Only settled hits receive pull")
	for record: Dictionary in arena.damage_trace:
		near(record.total,expected.total,"Unchanged real primary damage")
		check(record.tags==current.packets.direct.tags,"Actual hit retains melee damage classification")
	check(arena.projectiles.is_empty(),"No projectile/secondary carrier introduced")
	near(arena.group_cooldown_remaining(group_id),current.cooldown,"Original group cooldown")
	var before:=spell_state();check(not arena.cast_group(group_id) and spell_state()==before,"Cooldown denial remains atomic")
	impulse_samples.append({"links":links,"recipe":current.recipe,"damage":expected,"knockback":[arena.enemies[0].knockback,arena.enemies[1].knockback],"admissions":arena.attack_admission_trace.duplicate(true)})
	return failures==0

func movement_case() -> bool:
	if not link(["inward_pull"]): return false
	park();arena.player_pos=arena.ARENA.position+Vector2(600,1600)
	var enemy: Dictionary=arena.enemies[0]
	prep_actor(enemy,arena.player_pos+Vector2(70,0));enemy.speed=0.0
	ready_cast()
	if not check(arena.cast_group(group_id),"Actual cast starts inward movement"): return false
	var start: Vector2=enemy.pos
	if not link([]): return false
	vector_near(enemy.knockback,Vector2(-190,0),"Unlink does not erase the applied impulse")
	arena._update_enemies(0.1)
	vector_near(enemy.pos,start+Vector2(-19,0),"Original enemy motion consumes pull")
	vector_near(enemy.knockback,Vector2(-138,0),"Original 520 per-second decay")
	return failures==0

func wall_case() -> bool:
	if not link(["inward_pull","encircling_cleave"]): return false
	cast_ring=arena.state.get_group_cast(group_id)
	if not wall_probe_ring(): return false
	check(arena.enemies[1].knockback==Vector2.ZERO,"Wall-hidden target also receives no pull")
	if not link(["inward_pull"]): return false
	park()
	var wall: Rect2=arena.world_geometry().walls[0]
	arena.player_pos=Vector2(wall.position.x-16.0,wall.get_center().y)
	var enemy: Dictionary=arena.enemies[0]
	prep_actor(enemy,Vector2(wall.position.x-40.0,arena.player_pos.y));enemy.speed=0.0
	check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS) and arena._geometry.is_clear(enemy.pos,enemy.radius),"Actual wall uses legal actor positions")
	ready_cast()
	if not check(arena.cast_group(group_id),"Owned cleave pulls beside real wall"): return false
	vector_near(enemy.knockback,Vector2(190,0),"Cleave origin determines wall-side pull")
	var start: Vector2=enemy.pos
	check(not arena._geometry.is_clear(start+Vector2(38,0),enemy.radius),"Unclipped movement would enter wall")
	arena._update_enemies(0.2)
	check(arena._geometry.is_clear(enemy.pos,enemy.radius) and enemy.pos.x>start.x and enemy.pos.x<=wall.position.x-float(enemy.radius),"Existing swept body movement stops at wall")
	vector_near(enemy.knockback,Vector2(86,0),"Collision keeps original decay")
	return failures==0

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-cleave-inward-") or not OS.get_user_data_dir().begins_with(isolated+"/") or FileAccess.file_exists("user://build_save.json"): quit(78);return
	compile_checks()
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/v094-integration/owned-fixture.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	if not check(arena.world_context().normal_town and Rules.reason(arena.state.snapshot()).is_empty(),"Existing owned-cleave fixture migrates legally into formal town"): await finish();return
	active_uid=arena.state.skill_group(group_id).main_uid
	var balance: int=arena.state.crafting_balance()
	support_uid=purchase("support:inward_pull",4)
	if support_uid.is_empty(): await finish();return
	check(arena.state.location(support_uid).kind=="bag" and arena.state.crafting_balance()==balance-4,"Original paid acquisition reaches bag")
	for uid: String in arena.state.snapshot().items:
		var item: Dictionary=arena.state.item(uid)
		if item.kind=="support_gem": owned[item.definition_id.trim_prefix("support:")]=uid
	if not link([]): await finish();return
	cast_plain=arena.state.get_group_cast(group_id)
	if not link(["inward_pull"]): await finish();return
	var linked: Dictionary=arena.state.get_group_cast(group_id)
	var loaded:=Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.snapshot()==arena.state.snapshot() and loaded.get_group_cast(group_id)==linked,"Same-schema save/reload preserves bought UID and actual cast")
	check(arena.state.snapshot().version==61,"Schema61 unchanged")
	if not enter("old_garden"): await finish();return
	for links: Array in [[],["inward_pull"],["encircling_cleave","inward_pull"],["breadth","concentrate","physical_focus","efficiency","inward_pull"]]:
		if not sector_case(links): await finish();return
	if not movement_case(): await finish();return
	if not return_to_town("Return retains purchased support") or not enter("broken_ruins"): await finish();return
	if not wall_case(): await finish();return
	await finish()

func finish() -> void:
	var result: Dictionary={"checks":checks,"failures":failures,"labels":labels,"comparisons":comparisons,"samples":impulse_samples,"support_uid":support_uid,"active_uid":active_uid,"fixture_sha256":FileAccess.get_sha256("res://docs/qa/v094-integration/owned-fixture.json")}
	FileAccess.open(OS.get_environment("PULL_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print("CLEAVE_INWARD checks=%d failures=%d comparisons=%d"%[checks,failures,comparisons])
	if is_instance_valid(arena): arena.queue_free();await process_frame
	quit(1 if failures else 0)
