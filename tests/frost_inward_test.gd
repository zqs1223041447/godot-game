extends "res://tests/chain_ambush_test.gd"
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
var projectile_comparisons := 0
var frost_samples: Array=[]

func compile_and_carrier_checks() -> void:
	var old=load("/tmp/godot-frost-inward-baseline/skill_compiler.gd")
	var old_runtime=load("/tmp/godot-frost-inward-baseline/projectile_runtime.gd")
	for stats: Dictionary in [{"damage":26.0},{"damage":26.0,"cold_ailment_duration_increased":0.2,"spell_added_lightning":3.0}]:
		var source: Dictionary=Compiler.Recipes.snapshot(stats,[])
		for skill: String in Compiler.Data.SKILLS:
			var choices: Array=[[]]
			for support: String in old.Supports.supports_for_skill(skill):choices.append([support])
			for links: Array in choices:
				check(var_to_bytes(old.compile_group(skill,source,links))==var_to_bytes(Compiler.compile_group(skill,source,links)),"Whole old compile bytes "+skill+str(links));comparisons+=1
		for other: Array in [[],["frost_lock"],["pierce","heavy_projectiles","lingering_chill","efficiency"]]:
			var before: Dictionary=Compiler.compile_group("frost",source,other)
			check(var_to_bytes(before)==var_to_bytes(old.compile_group("frost",source,other)),"Old frost multi-support combination exact");comparisons+=1
			var selected: Array=other+["inward_pull"]
			var after: Dictionary=Compiler.compile_group("frost",source,selected)
			check(after.ok and not old.compile_group("frost",source,selected).ok,"Former rejection becomes explicit frost pull")
			if not after.ok:continue
			check(after.recipe==before.recipe and after.packets==before.packets and after.cooldown==before.cooldown,"Frost pull preserves original volley, pierce, slow, cold packets and cooldown")
			near(after.mana,before.mana*1.2,"Original pull cost applied once")
			check(after.snapshot.area_impulse_policy==after.area_impulse_profile,"Independent compiled frozen policy")
			check(HitDamage.resolve(before.packets.projectile,before.snapshot.modifiers)==HitDamage.resolve(after.packets.projectile,after.snapshot.modifiers),"Every damage component remains identical")
			check(before.get("freeze_profile",{})==after.get("freeze_profile",{}),"Existing frost lock timing untouched")
			selected.reverse();check(var_to_bytes(after)==var_to_bytes(Compiler.compile_group("frost",source,selected)),"Five-slot order canonical")
	var source: Dictionary=Compiler.Recipes.snapshot({"damage":26.0},[])
	var targets: Array[Dictionary]=[{"id":1,"pos":Vector2(100,0),"radius":5.0,"health":1000.0,"spawn":0.0},{"id":2,"pos":Vector2(220,0),"radius":5.0,"health":1000.0,"spawn":0.0}]
	for skill: String in ["bolt","frost","shade_bolt","tornado"]:
		var a=old_runtime.new();var b:=Projectiles.new();var aa: Array[Dictionary]=[];var bb: Array[Dictionary]=[]
		var cast: Dictionary=Compiler.compile_group(skill,source,[])
		if skill=="tornado":
			a.spawn_tornado(aa,Vector2.ZERO,Vector2.RIGHT,cast.snapshot,100);b.spawn_tornado(bb,Vector2.ZERO,Vector2.RIGHT,cast.snapshot,100)
		else:
			aa.append(a.make_projectile(Vector2(19,0),Vector2.RIGHT,cast.recipe,cast.packets.projectile,cast.snapshot,1,Color.WHITE))
			bb.append(b.make_projectile(Vector2(19,0),Vector2.RIGHT,cast.recipe,cast.packets.projectile,cast.snapshot,1,Color.WHITE))
		check(var_to_bytes(aa)==var_to_bytes(bb),"Original projectile storage exact "+skill)
		for delta: float in [0.2,0.6,0.8]:
			var old_events: Array=a.advance(aa,delta,targets,Vector2.ZERO,100)
			var events: Array=b.advance(bb,delta,targets,Vector2.ZERO,100)
			check(var_to_bytes(old_events)==var_to_bytes(events) and var_to_bytes(aa)==var_to_bytes(bb),"Original event bytes, hits and termination exact "+skill);projectile_comparisons+=1

func frost_setup() -> void:
	setup_trap();arena.player_facing=Vector2.RIGHT
	arena._stats.max_mana=float(arena.state.get_stats().max_mana);arena.mana=arena._stats.max_mana
	arena.freeze_runtime.reset()

func volley_case(links: Array, count: int) -> bool:
	if not link(links):return false
	frost_setup()
	var origin: Vector2=arena.player_pos
	var ids: Array=[]
	for i: int in range(count):
		var enemy: Dictionary=arena.enemies[i];prep_actor(enemy,origin+Vector2(160+i*90,0),3.0);enemy.speed=0.0;ids.append(enemy.id)
	var protected: Dictionary=arena.enemies[count];prep_actor(protected,origin+Vector2(100,0),3.0);protected.spawn=3.0;protected.speed=0.0
	var cast: Dictionary=arena.state.get_group_cast(group_id)
	var mana_before: float=arena.mana
	check(arena.cast_group(group_id) and arena.projectiles.size()==cast.initial_count,"Actual owned complete frost volley "+str(links))
	near(mana_before-arena.mana,cast.mana,"Exact one-time whole-volley cost")
	near(arena.group_cooldown_remaining(group_id),cast.cooldown,"Original cooldown")
	var pulling: bool=links.has("inward_pull")
	for shot: Dictionary in arena.projectiles:
		check(shot.has("impulse_origin")==pulling,"Origin only added for selected frost")
		if pulling:check(shot.impulse_origin==origin,"All muzzle offsets retain the same original feet position")
	var frozen:=var_to_bytes(arena.projectiles)
	if pulling:
		if not link([]):return false
		check(var_to_bytes(arena.projectiles)==frozen,"Actual unlink preserves all in-flight packets, policy and origin")
	arena._stats.mana_regen=0.0 # Canonical unlink refreshes runtime stats; isolate contact payment again.
	arena.player_pos=origin+Vector2(500,400)
	var seen: Array=[]
	var checkpoint: Dictionary=arena.critical_runtime.checkpoint()
	for unused: int in range(105):
		arena.tick(1.0/60.0)
		for hit: Dictionary in arena.damage_trace:
			if seen.has(hit.target_id):continue
			seen.append(hit.target_id)
			var target: Dictionary=actor(hit.target_id)
			check(hit.skill_id=="frost" and hit.tags==["hit","projectile","spell"] and hit.components.keys()==["cold"],"Actual targets receive original cold spell projectile hit")
			var expected: Dictionary=HitDamage.resolve(cast.packets.projectile,cast.snapshot.modifiers,{},float(hit.get("critical",{}).get("multiplier",1.0)))
			near(hit.total,expected.total,"Exact frozen per-projectile damage")
			vector_near(target.knockback,(origin-Vector2(target.pos)).normalized()*190.0 if pulling else Vector2(45,0),"Selected pull replaces, original cast retains outgoing45")
			near(target.slow,cast.recipe.slow,"Original cold slow survives pull")
		if seen.size()==count:break
	check(seen==ids,"Original center-pellet pierce hits distinct expected actors in order")
	check(protected.health==10000.0 and protected.knockback==Vector2.ZERO,"Protected target never receives hit or pull")
	check(arena.critical_runtime.checkpoint()==checkpoint,"In-flight contacts do not reroll the cast")
	near(arena.mana,mana_before-cast.mana,"No contact-time charge")
	arena.projectile_runtime.cancel_all(arena.projectiles)
	if pulling and not seen.is_empty():
		var last: Dictionary=actor(seen.back());var start: Vector2=last.pos
		arena._update_enemies(0.1)
		near(start.distance_to(last.pos),19.0,"Existing actual movement consumes190 pull over0.1 seconds")
		near(last.knockback.length(),138.0,"Original520 per-second decay retained")
	frost_samples.append({"links":links,"hits":seen.size(),"mana":cast.mana,"origin":origin,"moved_player":arena.player_pos,"slow":cast.recipe.slow,"pierce":cast.recipe.pierce})
	return failures==0

func secondary_scope() -> void:
	frost_setup()
	# Isolated carrier probe: opt into the existing explosion effect without
	# claiming the owned build has that equipment or changing its saved state.
	var source: Dictionary=arena.state.get_combat_snapshot()
	source.effects=["explode_on_flight_end"]
	var cast: Dictionary=Compiler.compile_group("frost",source,["inward_pull"])
	var frozen: Dictionary=arena.critical_runtime.freeze(cast.snapshot).snapshot
	var target: Dictionary=arena.enemies[0]
	prep_actor(target,arena.player_pos+Vector2(65,0),3.0);target.speed=0.0
	target.knockback=Vector2(7,9)
	var shot: Dictionary=arena.projectile_runtime.make_projectile(arena.player_pos,Vector2.RIGHT,{"speed":520.0,"range":25.0,"lifetime":1.7,"pierce":0,"slow":3.0},cast.packets.projectile,frozen,arena.projectile_runtime.new_cast(),Color.WHITE)
	shot.impulse_origin=arena.player_pos;arena.projectiles.append(shot)
	arena._update_projectiles(0.1)
	check(arena.damage_trace.size()==1 and arena.damage_trace[0].tags==["hit","area","secondary","explosion"],"Actual natural-end event resolves only independent explosion")
	check(arena.damage_trace[0].components.keys()==["fire"] and target.slow==0.0 and target.knockback==Vector2(7,9),"Independent fire explosion receives neither frost slow nor pull")
	frost_samples.append({"case":"isolated_existing_secondary_effect","damage":arena.damage_trace[0].total,"unchanged_impulse":target.knockback})

func atomic_and_cancel() -> bool:
	if not link(["inward_pull"]):return false
	frost_setup();var cast: Dictionary=arena.state.get_group_cast(group_id)
	arena.mana=cast.mana-0.01;var before:=spell_state()
	check(not arena.cast_group(group_id) and spell_state()==before,"Insufficient mana changes nothing")
	ready_cast();var bad: Dictionary=cast.duplicate(true);bad.snapshot.area_impulse_policy.impulse_speed=191.0;before=spell_state()
	check(not arena._execute_compiled(bad,group_id,active_uid) and spell_state()==before,"Malformed pull refuses before charge, IDs or RNG")
	# Count-only capacity fixture is never advanced; admission must fail before it is read.
	for unused: int in range(arena.MAX_PROJECTILES-4):arena.projectiles.append({})
	before=var_to_bytes([spell_state(),arena.projectiles,arena.projectile_runtime.next_projectile_id,arena.rng.state])
	check(not arena.cast_group(group_id) and before==var_to_bytes([spell_state(),arena.projectiles,arena.projectile_runtime.next_projectile_id,arena.rng.state]),"Four free places cannot admit or charge a five-pellet cast")
	arena.projectiles.clear();ready_cast()
	check(arena.cast_group(group_id),"Restart cancellation has real in-flight pull volley")
	var ownership: Dictionary=arena.state.snapshot().items.duplicate(true)
	arena.restart_run();pause()
	check(arena.projectiles.is_empty(),"Actual restart cancels every in-flight carrier")
	var old_damage:=var_to_bytes(arena.damage_trace);arena._update_projectiles(0.5)
	check(var_to_bytes(arena.damage_trace)==old_damage and arena.state.snapshot().items==ownership,"Cancelled volley never hits or alters owned gems")
	return failures==0

func wall_case() -> bool:
	if not link(["inward_pull"]):return false
	frost_setup();var wall: Rect2=arena.world_geometry().walls[0]
	arena.player_pos=Vector2(wall.position.x-50,wall.get_center().y);arena.player_facing=Vector2.RIGHT
	var target: Dictionary=arena.enemies[0];prep_actor(target,Vector2(wall.end.x+30,wall.get_center().y),3.0);target.speed=0.0
	check(not arena._terrain_visible(arena.player_pos,target.pos),"Actual wall occludes target")
	check(arena.cast_group(group_id),"Actual frost volley toward wall")
	for unused: int in range(45):arena.tick(1.0/60.0)
	check(arena.damage_trace.is_empty() and target.knockback==Vector2.ZERO and target.health==10000.0,"Wall terminates frost with no damage or pull")
	return failures==0

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-frost-inward-") or not OS.get_user_data_dir().begins_with(isolated+"/") or FileAccess.file_exists("user://build_save.json"):quit(78);return
	compile_and_carrier_checks()
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/nova-lingering/owned.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	for group: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(group.id).skill_id=="frost":group_id=group.id
	active_uid=arena.state.skill_group(group_id).main_uid
	support_uid=purchase("support:inward_pull",4)
	if support_uid.is_empty():await finish();return
	for uid: String in arena.state.snapshot().items:
		var item: Dictionary=arena.state.item(uid)
		if item.kind=="support_gem":owned[item.definition_id.trim_prefix("support:")]=uid
	if not link(["inward_pull"]):await finish();return
	owned_cast=arena.state.get_group_cast(group_id);var restored:=Model.new()
	check(restored.load_build(arena.build_save_path) and restored.snapshot()==arena.state.snapshot() and restored.get_group_cast(group_id)==owned_cast,"Paid ownership and new legal frost links survive strict reload")
	check(arena.state.snapshot().version==61,"Schema61 unchanged");saved_fixture=FileAccess.get_file_as_string(arena.build_save_path)
	if not enter("old_garden"):await finish();return
	if not volley_case([],3) or not volley_case(["inward_pull"],3) or not volley_case(["inward_pull","pierce","heavy_projectiles","lingering_chill","efficiency"],5):await finish();return
	secondary_scope()
	if failures>0:await finish();return
	if not return_to_town("Retain paid frost build") or not enter("broken_ruins") or not wall_case() or not atomic_and_cancel():await finish();return
	await finish()

func finish() -> void:
	var output:=OS.get_environment("FROST_PULL_REPORT")
	var result: Dictionary={"checks":checks,"failures":failures,"labels":labels,"old_cast_comparisons":comparisons,"old_projectile_batches":projectile_comparisons,"samples":frost_samples,"group_id":group_id,"main_uid":active_uid,"support_uid":support_uid,"owned_cast":owned_cast}
	if failures==0:
		FileAccess.open(output.get_base_dir().path_join("owned.json"),FileAccess.WRITE).store_string(saved_fixture)
		result["owned_sha256"]=FileAccess.get_sha256(output.get_base_dir().path_join("owned.json"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print("FROST_INWARD checks=%d failures=%d old_casts=%d old_batches=%d"%[checks,failures,comparisons,projectile_comparisons])
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
