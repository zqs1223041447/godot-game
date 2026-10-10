extends "res://tests/cleave_inward_test.gd"
## Reuse actual owned skills and map fixtures; exercise aim through Main casts.
var groups: Dictionary = {}
var observations: Array = []
var regular: Dictionary = {}
var phase: String = OS.get_environment("AIM_PHASE")

func prepare_target(offset: Vector2, facing: Vector2) -> void:
	park();arena.player_pos=arena.ARENA.position+Vector2(600,1600)
	prep_actor(arena.enemies[0],arena.player_pos+offset,5.0);arena.enemies[0].speed=0.0
	arena.player_facing=facing
	arena.projectile_runtime.cancel_all(arena.projectiles)
	arena.critical_runtime.reset(810810)
	ready_cast()

func projectile_case(skill: String, offset: Vector2, facing: Vector2, overlap: bool) -> void:
	prepare_target(offset,facing)
	var group: String=groups[skill]
	var compiled: Dictionary=arena.state.get_group_cast(group)
	var mana_before: float=arena.mana
	var origin: Vector2=arena.player_pos
	var accepted_cast: bool=arena.cast_group(group)
	check(accepted_cast,"Actual owned cast accepted: "+skill)
	near(mana_before-arena.mana,compiled.mana,"Exact original mana: "+skill)
	near(arena.group_cooldown_remaining(group),compiled.cooldown,"Original cooldown: "+skill)
	check(arena.projectiles.size()==compiled.initial_count,"Original full volley count: "+skill)
	var expected_facing: Vector2=facing if overlap else offset.normalized()
	if expected_facing.is_zero_approx():expected_facing=Vector2.RIGHT
	vector_near(arena.player_facing,expected_facing,"Finite cast-facing preserves valid direction: "+skill)
	var shapes: Array=[]
	for index: int in range(arena.projectiles.size()):
		var shot: Dictionary=arena.projectiles[index]
		var spread: float=compiled.recipe.spread
		var direction:=expected_facing.rotated((index-(compiled.initial_count-1)*0.5)*spread).normalized()
		var speed: float=compiled.recipe.parent.speed if skill=="tornado" else compiled.recipe.speed
		vector_near(shot.velocity,direction*speed,"Actual carrier velocity retains fan: "+skill+str(index))
		vector_near(shot.pos,origin+direction*19.0,"Original muzzle offset: "+skill+str(index))
		shapes.append({"position":Vector2(shot.pos)-origin,"velocity":shot.velocity,"payload":shot.payload,"snapshot":shot.snapshot,"speed":shot.speed,"range":shot.range,"lifetime":shot.lifetime,"pierce":shot.pierce,"slow":shot.slow})
	observations.append({"skill":skill,"overlap":overlap,"requested_facing":facing,"cast_facing":arena.player_facing,"mana":compiled.mana,"cooldown":compiled.cooldown,"shapes":shapes})
	if not overlap:regular[skill]=observations.back()

func dash_case(overlap: bool) -> void:
	prepare_target(Vector2.ZERO if overlap else Vector2(0,-60),Vector2.UP)
	var start: Vector2=arena.player_pos
	check(arena.cast_group(groups.dash),"Actual idle-input dash admitted")
	vector_near(arena.player_pos,start+Vector2(0,-175),"Idle-input dash keeps original displacement with coincident target")
	observations.append({"skill":"dash","overlap":overlap,"from":start,"to":arena.player_pos,"facing":arena.player_facing})
	if not overlap:regular.dash=observations.back()

func additional_cases() -> void:
	prepare_target(Vector2.ZERO,Vector2.UP)
	mouse_probe()
	prepare_target(Vector2.ZERO,Vector2.UP)
	check(arena.state.get_basic_attack_profile().delivery=="projectile","Fixture uses original ranged basic attack")
	arena.auto_fire=true;arena.attack_timer=0.0
	arena._update_auto_attack();arena.auto_fire=false
	check(arena.projectiles.size()==1 and arena.attack_timer>0.0,"Automatic basic attack emits one normal projectile")
	if not arena.projectiles.is_empty():vector_near(Vector2(arena.projectiles[0].velocity).normalized(),Vector2.UP,"Basic attack shares finite retained facing")
	prepare_target(Vector2.ZERO,Vector2.ZERO)
	vector_near(arena._aim_direction(),Vector2.RIGHT,"No valid previous direction uses right fallback")
	park();arena.player_facing=Vector2.LEFT
	vector_near(arena._aim_direction(),Vector2.LEFT,"No target retains existing direction")
	for skill: String in ["bolt","frost","shade_bolt","tornado"]:
		prepare_target(Vector2.ZERO,Vector2.UP)
		var target: Dictionary=arena.enemies[1]
		prep_actor(target,arena.player_pos+Vector2(0,-90),5.0);target.speed=0.0
		var cast: Dictionary=arena.state.get_group_cast(groups[skill])
		check(arena.cast_group(groups[skill]),"Real collision probe launches "+skill)
		for unused: int in range(12):arena.tick(1.0/60.0)
		check(not arena.damage_trace.is_empty(),"Actual carrier reaches forward target "+skill)
		for hit: Dictionary in arena.damage_trace:
			check(hit.target_id==target.id and hit.skill_id==skill,"Actual forward carrier hit, no direct settlement injection")
			var packet: Dictionary=cast.packets.parent if skill=="tornado" else cast.packets.projectile
			var expected: Dictionary=HitDamage.resolve(packet,cast.snapshot.modifiers,{},float(hit.get("critical",{}).get("multiplier",1.0)))
			near(hit.total,expected.total,"Unchanged actual typed damage "+skill)
			check(hit.components==expected.components and hit.tags==packet.tags,"Original damage components and tags "+skill)
	# Existing owned auxiliary gems pass through the same heading before fan rotation.
	for uid: String in arena.state.snapshot().items:
		var item: Dictionary=arena.state.item(uid)
		if item.kind=="support_gem":owned[item.definition_id.trim_prefix("support:")]=uid
	for skill: String in ["bolt","frost","tornado"]:
		group_id=groups[skill]
		if not link(["volley","swift_projectiles"]):return
		projectile_case(skill,Vector2.ZERO,Vector2.UP,true)
		if not link([]):return
	if not return_to_town("Return with all owned skill identities") or not enter("broken_ruins"):return
	park()
	var wall: Rect2=arena.world_geometry().walls[0]
	arena.player_pos=Vector2(wall.position.x-50,wall.get_center().y);arena.player_facing=Vector2.RIGHT
	prep_actor(arena.enemies[0],arena.player_pos,5.0)
	ready_cast();arena.invulnerable=0.0
	var start: Vector2=arena.player_pos
	check(arena.cast_group(groups.dash),"Coincident-target dash beside actual wall")
	check(arena.player_pos.x>start.x and arena.player_pos.x<=wall.position.x-arena.PLAYER_RADIUS and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Recovered dash displacement still sweeps and stops on original wall side")
	near(arena.invulnerable,0.6,"Original plain dash protection unchanged")
	var rejected:=spell_state();var position: Vector2=arena.player_pos
	check(not arena.cast_group(groups.dash) and arena.player_pos==position and spell_state()==rejected,"Cooldown rejection still leaves movement and resources intact")
	var reloaded:=Model.new()
	check(reloaded.load_build(arena.build_save_path) and reloaded.snapshot()==arena.state.snapshot(),"Paid skill UID and original build still reload exactly")

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-aim-overlap-") or not OS.get_user_data_dir().begins_with(isolated+"/") or FileAccess.file_exists("user://build_save.json"):quit(78);return
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/v094-integration/owned-fixture.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	check(arena.world_context().normal_town and Rules.reason(arena.state.snapshot()).is_empty(),"Reuse existing legally owned fixture")
	for group: Dictionary in arena.state.snapshot().skill_groups:
		var current: Dictionary=arena.state.skill_group(group.id)
		groups[current.skill_id]=group.id
	if not groups.has("shade_bolt"):
		var vacant: String=groups.get("", "")
		if not check(not vacant.is_empty(),"Reuse existing empty skill group"):await finish();return
		var uid:=purchase("skill:shade_bolt",8)
		if uid.is_empty() or not accepted(arena.state.move_item(uid,{"kind":"skill_main","group_id":vacant},arena.state.revision(),arena.build_save_path),"Formally bought shade bolt equips in existing empty group"):await finish();return
		groups.shade_bolt=vacant
	for skill: String in ["bolt","frost","shade_bolt","tornado","dash"]:
		if not check(groups.has(skill),"Existing owned skill group "+skill):await finish();return
		for uid: String in arena.state.skill_group(groups[skill]).support_uids:
			if not uid.is_empty():accepted(arena.state.move_item(uid,arena.state.first_bag_position(uid),arena.state.revision(),arena.build_save_path),"Use plain owned skill "+skill)
	if not enter("old_garden"):await finish();return
	for skill: String in ["bolt","frost","shade_bolt","tornado"]:
		projectile_case(skill,Vector2(0,-60),Vector2.RIGHT,false)
		projectile_case(skill,Vector2.ZERO,Vector2.UP,true)
	dash_case(false);dash_case(true)
	if phase=="after":
		var before: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/aim-overlap/before.json"))
		check(JSON.parse_string(JSON.stringify(regular,"",true,true))==before.regular,"All non-overlap actual carriers and dash results match pre-fix exactly")
		additional_cases()
	await finish()

func finish() -> void:
	var result: Dictionary={"checks":checks,"failures":failures,"labels":labels,"phase":phase,"regular":regular,"observations":observations}
	FileAccess.open(OS.get_environment("AIM_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print("AIM_OVERLAP phase=%s checks=%d failures=%d"%[phase,checks,failures])
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
