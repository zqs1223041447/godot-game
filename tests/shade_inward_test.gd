extends "res://tests/chain_ambush_test.gd"
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
var projectile_comparisons := 0
var shade_samples: Array=[]

func compile_and_carrier_checks() -> void:
	var old=load("/tmp/godot-shade-inward-baseline/skill_compiler.gd")
	var old_runtime=load("/tmp/godot-shade-inward-baseline/projectile_runtime.gd")
	for stats: Dictionary in [{"damage":26.0},{"damage":26.0,"spell_added_lightning":3.0}]:
		var source: Dictionary=Compiler.Recipes.snapshot(stats,[])
		for skill: String in Compiler.Data.SKILLS:
			var choices: Array=[[]]
			for support: String in old.Supports.supports_for_skill(skill):choices.append([support])
			for links: Array in choices:
				check(var_to_bytes(old.compile_group(skill,source,links))==var_to_bytes(Compiler.compile_group(skill,source,links)),"Whole old compile bytes "+skill+str(links));comparisons+=1
		for other: Array in [[],["pierce"],["pierce","heavy_projectiles","volley","efficiency"]]:
			var before: Dictionary=Compiler.compile_group("shade_bolt",source,other)
			check(var_to_bytes(before)==var_to_bytes(old.compile_group("shade_bolt",source,other)),"Old shade multi-support combination exact");comparisons+=1
			var selected: Array=other+["inward_pull"]
			var after: Dictionary=Compiler.compile_group("shade_bolt",source,selected)
			check(after.ok and not old.compile_group("shade_bolt",source,selected).ok,"Former rejection becomes explicit shade pull")
			if not after.ok:continue
			check(after.recipe==before.recipe and after.packets==before.packets and after.cooldown==before.cooldown,"Shade pull preserves original volley, pierce, slow, chaos packets and cooldown")
			near(after.mana,before.mana*1.2,"Original pull cost applied once")
			check(after.snapshot.area_impulse_policy==after.area_impulse_profile,"Independent compiled frozen policy")
			check(HitDamage.resolve(before.packets.projectile,before.snapshot.modifiers)==HitDamage.resolve(after.packets.projectile,after.snapshot.modifiers),"Every damage component remains identical")
			check(not after.has("freeze_profile") and not after.has("burn_profile"),"No freeze or burning policy added")
			selected.reverse();check(var_to_bytes(after)==var_to_bytes(Compiler.compile_group("shade_bolt",source,selected)),"Five-slot order canonical")
	for links: Array in [["inward_pull"],["inward_pull","frost_lock"],["inward_pull","pierce","heavy_projectiles","lingering_chill","efficiency"]]:
		var old_source: Dictionary=Compiler.Recipes.snapshot({"damage":26.0},[])
		check(var_to_bytes(old.compile_group("frost",old_source,links))==var_to_bytes(Compiler.compile_group("frost",old_source,links)),"Old frost pull compilation exact "+str(links));comparisons+=1
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


	# Selected frost's existing provenance-bearing carrier must also stay exact.
	var frost_cast: Dictionary=Compiler.compile_group("frost",source,["inward_pull"])
	var original_runtime=old_runtime.new();var current_runtime:=Projectiles.new()
	var original_shots: Array[Dictionary]=[];var current_shots: Array[Dictionary]=[]
	for pair: Array in [[original_runtime,original_shots],[current_runtime,current_shots]]:
		var shot: Dictionary=pair[0].make_projectile(Vector2(19,0),Vector2.RIGHT,frost_cast.recipe,frost_cast.packets.projectile,frost_cast.snapshot,1,Color.WHITE)
		shot.impulse_origin=Vector2.ZERO;pair[1].append(shot)
	for delta: float in [0.2,0.6,0.8]:
		var original_events: Array=original_runtime.advance(original_shots,delta,targets,Vector2(400,300),100)
		var current_events: Array=current_runtime.advance(current_shots,delta,targets,Vector2(400,300),100)
		check(var_to_bytes(original_events)==var_to_bytes(current_events) and var_to_bytes(original_shots)==var_to_bytes(current_shots),"Existing selected frost provenance and carrier bytes exact");projectile_comparisons+=1

func shade_setup() -> void:
	setup_trap();arena.player_facing=Vector2.RIGHT
	arena._stats.max_mana=float(arena.state.get_stats().max_mana);arena.mana=arena._stats.max_mana
	arena.freeze_runtime.reset()

func volley_case(links: Array, count: int) -> bool:
	if not link(links):return false
	shade_setup()
	var origin: Vector2=arena.player_pos
	var ids: Array=[]
	for i: int in range(count):
		var enemy: Dictionary=arena.enemies[i];prep_actor(enemy,origin+Vector2(160+i*90,0),3.0);enemy.speed=0.0;ids.append(enemy.id)
	var protected: Dictionary=arena.enemies[count];prep_actor(protected,origin+Vector2(100,0),3.0);protected.spawn=3.0;protected.speed=0.0
	var cast: Dictionary=arena.state.get_group_cast(group_id)
	var mana_before: float=arena.mana
	check(arena.cast_group(group_id) and arena.projectiles.size()==cast.initial_count,"Actual owned complete shade volley "+str(links))
	near(mana_before-arena.mana,cast.mana,"Exact one-time whole-volley cost")
	near(arena.group_cooldown_remaining(group_id),cast.cooldown,"Original cooldown")
	var denied:=var_to_bytes([spell_state(),arena.projectiles,arena.projectile_runtime.next_projectile_id,arena.rng.state])
	check(not arena.cast_group(group_id) and denied==var_to_bytes([spell_state(),arena.projectiles,arena.projectile_runtime.next_projectile_id,arena.rng.state]),"Cooldown refusal preserves existing flight and all charge/RNG state")
	var pulling: bool=links.has("inward_pull")
	for shot: Dictionary in arena.projectiles:
		check(shot.has("impulse_origin")==pulling,"Origin only added for selected shade")
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
			check(hit.skill_id=="shade_bolt" and hit.tags==["hit","projectile","spell"] and hit.components.keys()==["chaos"],"Actual targets receive original chaos spell projectile hit")
			var expected: Dictionary=HitDamage.resolve(cast.packets.projectile,cast.snapshot.modifiers,{},float(hit.get("critical",{}).get("multiplier",1.0)))
			near(hit.total,expected.total,"Exact frozen per-projectile damage")
			vector_near(target.knockback,(origin-Vector2(target.pos)).normalized()*190.0 if pulling else Vector2(45,0),"Selected pull replaces, original cast retains outgoing45")
			near(target.slow,cast.recipe.slow,"No slow is added")
		if seen.size()==count:break
	check(seen==ids,"Original projectile pierce hits distinct expected actors in order")
	check(protected.health==10000.0 and protected.knockback==Vector2.ZERO,"Protected target never receives hit or pull")
	check(arena.critical_runtime.checkpoint()==checkpoint,"In-flight contacts do not reroll the cast")
	near(arena.mana,mana_before-cast.mana,"No contact-time charge")
	arena.projectile_runtime.cancel_all(arena.projectiles)
	if pulling and not seen.is_empty():
		var last: Dictionary=actor(seen.back());var start: Vector2=last.pos
		arena._update_enemies(0.1)
		near(start.distance_to(last.pos),19.0,"Existing actual movement consumes190 pull over0.1 seconds")
		near(last.knockback.length(),138.0,"Original520 per-second decay retained")
	shade_samples.append({"links":links,"hits":seen.size(),"mana":cast.mana,"origin":origin,"moved_player":arena.player_pos,"slow":cast.recipe.slow,"pierce":cast.recipe.pierce})
	return failures==0

func secondary_scope() -> void:
	shade_setup()
	# Isolated carrier probe: opt into the existing explosion effect without
	# claiming the owned build has that equipment or changing its saved state.
	var source: Dictionary=arena.state.get_combat_snapshot()
	source.effects=["explode_on_flight_end"]
	var cast: Dictionary=Compiler.compile_group("shade_bolt",source,["inward_pull"])
	var frozen: Dictionary=arena.critical_runtime.freeze(cast.snapshot).snapshot
	var target: Dictionary=arena.enemies[0]
	prep_actor(target,arena.player_pos+Vector2(65,0),3.0);target.speed=0.0
	target.knockback=Vector2(7,9)
	var shot: Dictionary=arena.projectile_runtime.make_projectile(arena.player_pos,Vector2.RIGHT,{"speed":620.0,"range":25.0,"lifetime":1.7,"pierce":0,"slow":0.0},cast.packets.projectile,frozen,arena.projectile_runtime.new_cast(),Color.WHITE)
	shot.impulse_origin=arena.player_pos;arena.projectiles.append(shot)
	arena._update_projectiles(0.1)
	check(arena.damage_trace.size()==1 and arena.damage_trace[0].tags==["hit","area","secondary","explosion"],"Actual natural-end event resolves only independent explosion")
	check(arena.damage_trace[0].components.keys()==["fire"] and target.slow==0.0 and target.knockback==Vector2(7,9),"Independent fire explosion receives neither slow nor pull")
	shade_samples.append({"case":"isolated_existing_secondary_effect","damage":arena.damage_trace[0].total,"unchanged_impulse":target.knockback})

func atomic_and_cancel() -> bool:
	if not link(["inward_pull"]):return false
	shade_setup();var cast: Dictionary=arena.state.get_group_cast(group_id)
	arena.mana=cast.mana-0.01;var before:=spell_state()
	check(not arena.cast_group(group_id) and spell_state()==before,"Insufficient mana changes nothing")
	ready_cast();var bad: Dictionary=cast.duplicate(true);bad.snapshot.area_impulse_policy.impulse_speed=191.0;before=spell_state()
	check(not arena._execute_compiled(bad,group_id,active_uid) and spell_state()==before,"Malformed pull refuses before charge, IDs or RNG")
	# Count-only capacity fixture is never advanced; admission must fail before it is read.
	for unused: int in range(arena.MAX_PROJECTILES):arena.projectiles.append({})
	before=var_to_bytes([spell_state(),arena.projectiles,arena.projectile_runtime.next_projectile_id,arena.rng.state])
	check(not arena.cast_group(group_id) and before==var_to_bytes([spell_state(),arena.projectiles,arena.projectile_runtime.next_projectile_id,arena.rng.state]),"Full projectile capacity cannot admit or charge a single shade cast")
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
	shade_setup();var wall: Rect2=arena.world_geometry().walls[0]
	arena.player_pos=Vector2(wall.position.x-50,wall.get_center().y);arena.player_facing=Vector2.RIGHT
	var target: Dictionary=arena.enemies[0];prep_actor(target,Vector2(wall.end.x+30,wall.get_center().y),3.0);target.speed=0.0
	check(not arena._terrain_visible(arena.player_pos,target.pos),"Actual wall occludes target")
	check(arena.cast_group(group_id),"Actual shade volley toward wall")
	for unused: int in range(45):arena.tick(1.0/60.0)
	check(arena.damage_trace.is_empty() and target.knockback==Vector2.ZERO and target.health==10000.0,"Wall terminates shade with no damage or pull")
	return failures==0

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-shade-inward-") or not OS.get_user_data_dir().begins_with(isolated+"/") or FileAccess.file_exists("user://build_save.json"):quit(78);return
	compile_and_carrier_checks()
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/aim-overlap/owned-after.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	for group: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(group.id).skill_id=="shade_bolt":group_id=group.id
	if not check(not group_id.is_empty() and arena.state.skill_group(group_id).skill_id=="shade_bolt","Committed shade main remains owned"):await finish();return
	check(arena.world_context().normal_town and not arena.cast_group(group_id),"Current canonical town rejects combat casts")
	active_uid=arena.state.skill_group(group_id).main_uid
	support_uid=purchase("support:inward_pull",4)
	if support_uid.is_empty():await finish();return
	for uid: String in arena.state.snapshot().items:
		var item: Dictionary=arena.state.item(uid)
		if item.kind=="support_gem":owned[item.definition_id.trim_prefix("support:")]=uid
	if not link(["inward_pull"]):await finish();return
	owned_cast=arena.state.get_group_cast(group_id);var restored:=Model.new()
	check(restored.load_build(arena.build_save_path) and restored.snapshot()==arena.state.snapshot() and restored.get_group_cast(group_id)==owned_cast,"Paid ownership and new legal shade links survive strict reload")
	check(arena.state.snapshot().version==61,"Schema61 unchanged");saved_fixture=FileAccess.get_file_as_string(arena.build_save_path)
	if not enter("old_garden"):await finish();return
	if not volley_case([],1) or not volley_case(["inward_pull"],1) or not volley_case(["inward_pull","pierce"],3) or not volley_case(["inward_pull","pierce","heavy_projectiles","volley","efficiency"],3):await finish();return
	secondary_scope()
	if failures>0:await finish();return
	if not return_to_town("Retain paid shade build") or not enter("broken_ruins") or not wall_case() or not atomic_and_cancel():await finish();return
	await finish()

func finish() -> void:
	var output:=OS.get_environment("SHADE_PULL_REPORT")
	var result: Dictionary={"checks":checks,"failures":failures,"labels":labels,"old_cast_comparisons":comparisons,"old_projectile_batches":projectile_comparisons,"samples":shade_samples,"group_id":group_id,"main_uid":active_uid,"support_uid":support_uid,"owned_cast":owned_cast}
	if failures==0:
		FileAccess.open(output.get_base_dir().path_join("owned.json"),FileAccess.WRITE).store_string(saved_fixture)
		result["owned_sha256"]=FileAccess.get_sha256(output.get_base_dir().path_join("owned.json"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print("SHADE_INWARD checks=%d failures=%d old_casts=%d old_batches=%d"%[checks,failures,comparisons,projectile_comparisons])
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
