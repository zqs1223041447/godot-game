extends SceneTree
## Focused v098 compiler and actual-Main controls. A legal checked-in profile is
## loaded once; runtime positioning/resource resets are explicit controlled probes.
## This is not natural-combat, DPS, frame-rate or platform acceptance evidence.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Legacy = preload("res://docs/qa/v098-runtime/legacy_skill_compiler_d2d188a.gd")
const Registry = preload("res://scripts/combat/support_registry.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Rules = preload("res://scripts/combat/long_stride_support_rules.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const GROUP := "group_000008"
const POLICY := {"enabled":true,"requested_distance":280.0,"base_distance":175.0,"immunity_grant":0.0,"base_immunity_grant":0.6,"mana_multiplier":1.2}
const COMBINATIONS := [["long_stride"],["long_stride","efficiency"],["long_stride","quickcast"],["long_stride","efficiency","quickcast"]]
var arena: Node
var checks := 0
var failures := 0
var completed := false
var labels: Array[String] = []
var sections := {}
var samples: Array = []
var support_uids := {}
var active_uid := ""
var plain_owned: Dictionary
var stride_owned: Dictionary

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		labels.append(label)
		push_error(label)
	return ok
func near(actual: float, expected: float, label: String, tolerance: float = 0.00001) -> bool:
	return check(is_finite(actual) and absf(actual-expected) <= tolerance, "%s: %.9f expected %.9f" % [label,actual,expected])
func accepted(value: Dictionary, label: String) -> bool:
	return check(bool(value.get("ok",false)),label+": "+JSON.stringify(value))
func section(test: Callable) -> bool:
	completed=false
	var before := checks
	test.call()
	check(completed,"Section finishes normally: "+test.get_method())
	sections[test.get_method()]=checks-before
	print("LONG_STRIDE_SECTION ",test.get_method()," checks=",checks-before," failures=",failures)
	return completed and failures==0
func permutations(values: Array) -> Array:
	if values.size()<2:return [values.duplicate()]
	var result: Array=[]
	for index: int in values.size():
		var tail := values.duplicate();tail.remove_at(index)
		for row: Array in permutations(tail):result.append([values[index]]+row)
	return result
func compile(ids: Array) -> Dictionary:
	return Compiler.compile_group("dash",Combat.snapshot({"damage":100.0},[]),ids)
func price(ids: Array) -> float:
	return 12.0*(1.2 if ids.has("long_stride") else 1.0)*(0.8 if ids.has("efficiency") else 1.0)*(1.4 if ids.has("quickcast") else 1.0)
func cooldown(ids: Array) -> float:
	return 3.0*(1.15 if ids.has("efficiency") else 1.0)*(0.8 if ids.has("quickcast") else 1.0)

func compiler_contract() -> void:
	var base: Dictionary=Combat.snapshot({"damage":100.0},[])
	var original := var_to_bytes(base)
	check(Rules.POLICY==POLICY and Rules.profile_error(POLICY).is_empty(),"Exact reviewed distance/protection/resource policy")
	var definition: Dictionary=Rules.get_definition("long_stride")
	definition.operations[0].value=999.0;definition.skills.clear()
	check(Rules.get_definition("long_stride").skills==["dash"] and Rules.get_definition("long_stride").operations==[{"op":"mana_multiplier","value":1.2}],"Definition and nested arrays are detached")
	for ids: Array in COMBINATIONS:
		var expected: Dictionary=compile(ids)
		if not accepted(expected,"Reviewed combination compiles "+str(ids)):return
		check(expected.long_stride_profile==POLICY and expected.packets.is_empty() and expected.initial_count==0,"Dash-only policy introduces no hit packets or carriers")
		near(expected.mana,price(ids),"Exact combination mana")
		near(expected.cooldown,cooldown(ids),"Only existing resource supports alter cooldown")
		var canonical := ids.duplicate();canonical.sort()
		for ordered: Array in permutations(ids):
			var before := var_to_bytes(ordered)
			var current: Dictionary=Compiler.compile_group("dash",base,ordered)
			check(var_to_bytes(current)==var_to_bytes(expected),"Every support permutation has exact canonical output bytes "+str(ordered))
			check(current.support_ids==canonical and before==var_to_bytes(ordered),"Canonical ordering never mutates supplied selection")
		check(not Compiler.compile_group("dash",expected.snapshot,ids).ok,"Compiled snapshots cannot apply factors a second time")
		expected.long_stride_profile.requested_distance=999.0
		expected.support_ids.clear();expected.snapshot.effects.append("mutated_copy")
		check(compile(ids).long_stride_profile==POLICY and Rules.POLICY==POLICY,"Compiled policies and nested output remain detached across requests")
	check(var_to_bytes(base)==original,"Compiling all combinations leaves input snapshot bytes unchanged")
	for id: String in Registry.Data.SKILLS:
		check(Compiler.compile_group(id,base,["long_stride"]).ok==(id=="dash"),"Longstride compatibility limited to dash: "+id)
	for invalid: Array in [["long_stride","long_stride"],["long_stride","unknown"],["long_stride",1]]:
		check(not Compiler.compile_group("dash",base,invalid).ok,"Malformed or duplicate support selection rejects")
	check(not Compiler.compile_skill("dash",base,["long_stride"],0).ok,"Support occupies a real slot")
	completed=true

func old_compiler_oracle() -> void:
	# Independent pinned d2d188a compiler + registry; other imported mechanics are
	# unchanged by v098. Compare representative complete typed outputs, not labels.
	var selections: Array=[["dash",[]],["dash",["efficiency"]],["dash",["quickcast"]],["dash",["quickcast","efficiency"]],
		["ward",[]],["ward",["efficiency","quickcast"]],["bolt",[]],["bolt",["shock","quickcast"]],
		["tornado",[]],["nova",[]],["cleave",["encircling_cleave"]],["meteor",["inward_pull"]]]
	seed(980031);var expected_rng: Array=[randi(),randi(),randi()];seed(980031)
	for stats: Dictionary in [{"damage":100.0},{"damage":143.0,"global_increased":0.2,"mana_cost_efficiency_increased":0.25,"crit_base_chance":0.4,"crit_base_multiplier":1.8}]:
		var snapshot: Dictionary=Combat.snapshot(stats,[])
		for row: Array in selections:
			var current: Dictionary=Compiler.compile_group(row[0],snapshot,row[1])
			var old: Dictionary=Legacy.compile_group(row[0],snapshot,row[1])
			check(old.ok and current.ok,"Pinned old cast succeeds "+str(row))
			check(var_to_bytes(current)==var_to_bytes(old),"Unselected complete cast equals d2d188a typed bytes "+str(row))
			check(not current.has("long_stride_profile") and not current.snapshot.has("long_stride_profile"),"Unselected cast has no optional Longstride field")
	check([randi(),randi(),randi()]==expected_rng,"Pure old/new compilation leaves global RNG unchanged")
	completed=true

func pause() -> void:
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	for unused: int in range(4):arena.hud.close_panel()
func clean() -> void:
	pause();arena.group_cooldowns.reset()
	for id: String in arena.Data.SKILLS:arena.cooldowns[id]=0.0
	arena.enemies.clear();arena.projectiles.clear();arena.particles.clear();arena.rings.clear();arena.floating_text.clear()
	arena.visual_cues.reset();arena.damage_trace.clear();arena.incoming_damage_trace.clear();arena.attack_admission_trace.clear();arena.combat_trace.clear();arena.event_counts.clear()
	arena.burn_runtime.reset();arena.shock_runtime.reset();arena.freeze_runtime.reset();arena.chill_runtime.reset();arena.leech_runtime.clear();arena.trap_runtime.reset()
	arena.projectile_runtime=arena.Projectiles.new();arena.critical_runtime.reset(980098);arena.rng.seed=980098
	arena.health=1000.0;arena.shield=0.0;arena.mana=1000.0;arena.alive=true;arena.invulnerable=0.0;arena.damage_delay=0.0
	arena.elapsed=0.0;arena._burn_immunity_until=0.0;arena._burn_incoming_time=-1.0;arena._burn_step_active=false
	arena.total_damage=0.0;arena.total_shots=0;arena._camp_movement.clear();arena.player_facing=Vector2.RIGHT
	for action: String in ["move_left","move_right","move_up","move_down"]:Input.action_release(action)
func frozen_state() -> PackedByteArray:
	return var_to_bytes([arena.player_pos,arena.player_facing,arena.mana,arena.health,arena.shield,arena.invulnerable,arena.damage_delay,arena.cooldowns,arena.group_cooldowns.snapshot(),arena.rng.state,arena.critical_runtime.checkpoint(),arena.projectile_runtime.next_cast_id,arena.projectile_runtime.next_projectile_id,arena.damage_trace,arena.attack_admission_trace,arena.projectiles,arena.total_shots,arena.total_damage,arena._camp_movement,arena.get_node("WorldCamera").position,arena.state.snapshot(),arena.state.successful_saves,FileAccess.get_file_as_bytes(arena.build_save_path)])
func cast_direct(ids: Array) -> bool:return arena._execute_compiled(compile(ids))
func no_attack() -> void:
	check(arena.damage_trace.is_empty() and arena.attack_admission_trace.is_empty() and arena.projectiles.is_empty() and arena.total_damage==0.0 and arena.total_shots==0,"Movement emits no new damage packets, attack admissions or projectiles")
	check(arena.leech_runtime.is_empty() and arena.burn_runtime.is_empty() and arena.shock_runtime.is_empty(),"Movement creates no attack-only resource or ailment procs")
func link_supports(ids: Array) -> bool:
	for id: String in support_uids:
		var uid: String=support_uids[id]
		var moved: Dictionary=arena.state.move_item(uid,arena.state.first_bag_position(uid),arena.state.revision(),arena.build_save_path)
		if moved.get("error_code","")=="no_change":
			if not check(arena.state.location(uid).kind=="bag","No-change return already owns support in bag"):return false
		elif not accepted(moved,"Move actual support into bag "+id):return false
	for index: int in ids.size():
		if not accepted(arena.state.move_item(support_uids[ids[index]],{"kind":"skill_support","group_id":GROUP,"index":index},arena.state.revision(),arena.build_save_path),"Link actual owned support "+ids[index]):return false
	return true
func actual_owned_setup() -> void:
	check(arena.world_context().normal_town,"Legal saved fixture loads into formal safe town")
	check(arena.state.Rules.reason(arena.state.snapshot()).is_empty(),"Loaded migrated owned equipment remains canonical and lawful")
	active_uid=arena.state.award_gem("skill:dash")
	if not check(not active_uid.is_empty(),"Lawfully award dash gem"):return
	if not accepted(arena.state.move_item(active_uid,{"kind":"skill_main","group_id":GROUP},arena.state.revision(),arena.build_save_path),"Place owned dash in vacant group8"):return
	plain_owned=arena.state.get_group_cast(GROUP)
	for id: String in ["long_stride","efficiency","quickcast"]:
		support_uids[id]=arena.state.award_gem("support:"+id)
		if not check(not str(support_uids[id]).is_empty(),"Lawfully award support "+id):return
	if not link_supports(["long_stride"]):return
	stride_owned=arena.state.get_group_cast(GROUP)
	check(stride_owned.long_stride_profile==POLICY,"Actual model cache exposes authoritative support profile")
	var changed:=stride_owned.duplicate(true);changed.long_stride_profile.requested_distance=1.0
	check(arena.state.get_group_cast(GROUP)==stride_owned,"Owned model cast cache returns detached result")
	clean();var before:=frozen_state()
	check(not arena.cast_group(GROUP) and frozen_state()==before,"Formal town blocks owned dash before cost, IDs, RNG or motion")
	if not accepted(arena.craft_normal_map("broken_ruins",1,[],[],arena.map_draft().revision),"Prepare legal actual exploration map"):return
	if not accepted(arena.start_map(arena.map_draft().revision),"Actual Main starts exploration map"):return
	pause()
	check(arena.world_geometry().encounter_mode=="exploration" and arena.ARENA.size==Vector2(3600,2400),"Actual exploration geometry and camera are live")
	completed=true

func actual_open_movement() -> void:
	# Controlled open-world geometry, retaining the same legal model instance.
	arena._world_mode="normal";arena.ARENA=View.WORLD_ARENA;arena._geometry.configure("normal",arena.ARENA)
	for ids: Array in [[]]+COMBINATIONS:
		clean();arena.player_pos=arena.ARENA.position+Vector2(300,300)
		var start: Vector2=arena.player_pos;var before_mana: float=arena.mana
		var model_before:=var_to_bytes(arena.state.snapshot());var saves: int=arena.state.successful_saves
		var disk_before:=FileAccess.get_file_as_bytes(arena.build_save_path)
		if not check(cast_direct(ids),"Actual open-world cast accepts "+str(ids)):return
		near(arena.player_pos.x-start.x,280.0 if ids.has("long_stride") else 175.0,"Actual open-world displacement")
		near(arena.player_pos.y,start.y,"Horizontal cast preserves y")
		near(before_mana-arena.mana,price(ids),"Actual mana charged once")
		near(arena.cooldowns.dash,cooldown(ids),"Actual existing cooldown charged once")
		near(arena.invulnerable,0.0 if ids.has("long_stride") else 0.6,"Only supported dash omits its own immunity grant")
		check(var_to_bytes(arena.state.snapshot())==model_before and arena.state.successful_saves==saves and FileAccess.get_file_as_bytes(arena.build_save_path)==disk_before,"Cast does not change saved model, file bytes or save count")
		no_attack()
		samples.append({"case":"open_world","supports":ids,"start":start,"end":arena.player_pos,"mana":before_mana-arena.mana,"cooldown":arena.cooldowns.dash,"protection":arena.invulnerable})
		var frozen:=frozen_state();check(not cast_direct(ids) and frozen_state()==frozen,"Immediate cooldown rejection leaves motion, resources and RNG exact")
	# Existing stronger/shorter protection is retained exactly, never replaced by0.
	for amount: float in [0.0,0.43,0.8]:
		for ids: Array in [[],["long_stride"]]:
			clean();arena.player_pos=arena.ARENA.get_center();arena.invulnerable=amount
			check(cast_direct(ids),"Protection-retention cast accepts")
			check(arena.invulnerable==(amount if not ids.is_empty() else maxf(amount,0.6)),"Existing protection retains exact old maximum semantics")
	for ids: Array in [[],["long_stride"]]:
		clean();arena.player_pos=arena.ARENA.get_center();check(cast_direct(ids),"Immediate incoming-hit fixture dash accepts")
		var health: float=arena.health
		var hit: bool=arena.hit_player_components({"physical":10.0},0,["hit"])
		check(hit==not ids.is_empty(),"Immediate real incoming hit is blocked only by old dash grant")
		check((arena.health<health)==not ids.is_empty(),"Longstride leaves zero-protection player exposed to actual hit settlement")
	completed=true

func malformed_policy_and_gates() -> void:
	clean();arena.player_pos=arena.ARENA.get_center()
	var good:=compile(["long_stride"])
	var bad_casts: Array=[]
	for invalid: Variant in [null,[],{},true,1,"policy"]:
		var bad:=good.duplicate(true);bad.long_stride_profile=invalid;bad_casts.append(bad)
	var absent:=good.duplicate(true);absent.erase("long_stride_profile");bad_casts.append(absent)
	for field: String in POLICY:
		var missing:=good.duplicate(true);missing.long_stride_profile.erase(field);bad_casts.append(missing)
		for invalid: Variant in [null,true,false,"280",NAN,INF,-INF,-1.0,999.0]:
			if typeof(invalid)==typeof(POLICY[field]) and invalid==POLICY[field]:continue
			var bad:=good.duplicate(true);bad.long_stride_profile[field]=invalid;bad_casts.append(bad)
	var integer_distance:=good.duplicate(true);integer_distance.long_stride_profile.requested_distance=280;bad_casts.append(integer_distance)
	var extra:=good.duplicate(true);extra.long_stride_profile.extra=true;bad_casts.append(extra)
	var unselected:=good.duplicate(true);unselected.support_ids=[];bad_casts.append(unselected)
	var wrong_skill:=good.duplicate(true);wrong_skill.skill_id="ward";bad_casts.append(wrong_skill)
	seed(980077);var expected_global: Array=[randi(),randi(),randi()];seed(980077)
	for bad: Dictionary in bad_casts:
		var before:=frozen_state()
		check(not arena._execute_compiled(bad) and frozen_state()==before,"Malformed or unauthorized policy rejects before payment, RNG, cast ID and movement")
	check([randi(),randi(),randi()]==expected_global,"Rejected malformed policies preserve global RNG too")
	for gate: String in ["mana","cooldown","hud","dead","not_ready","town","map_complete"]:
		clean();arena._world_mode="normal";arena.player_pos=arena.ARENA.get_center()
		match gate:
			"mana":arena.mana=14.399
			"cooldown":arena.cooldowns.dash=0.001
			"hud":arena.hud.open_panel("pause")
			"dead":arena.alive=false
			"not_ready":arena._ready_complete=false
			"town":arena._world_mode="town"
			"map_complete":arena._world_mode="map_complete"
		var before:=frozen_state()
		check(not arena._execute_compiled(good) and frozen_state()==before,"Actual "+gate+" gate rejects before resources, IDs, RNG and movement")
		arena._ready_complete=true
	arena._world_mode="normal";clean()
	completed=true

func actual_geometry_and_group() -> void:
	arena._world_mode="map";arena.ARENA=View.exploration_arena();arena._geometry.configure_exploration("broken_ruins",arena.ARENA)
	View.configure_camera(arena,arena.ARENA,true,arena.ARENA.get_center())
	var wall: Rect2=arena.world_geometry().walls[0]
	for ids: Array in [[],["long_stride"]]:
		for diagonal: bool in [false,true]:
			clean();arena.player_pos=Vector2(wall.position.x-60.0,wall.get_center().y)
			var start: Vector2=arena.player_pos
			Input.action_press("move_right")
			if diagonal:Input.action_press("move_down")
			if not check(cast_direct(ids),"Actual wall-constrained dash accepts"):return
			Input.action_release("move_right");Input.action_release("move_down")
			near(arena.player_pos.x,wall.position.x-arena.PLAYER_RADIUS-arena.Geometry.SKIN,"Swept body stops at expanded wall footprint",0.001)
			near(arena.player_pos.y,start.y+(280.0 if not ids.is_empty() else 175.0)/sqrt(2.0) if diagonal else start.y,"Slide preserves tangential requested movement",0.001)
			check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Sweep/slide final body remains legal")
			check(not arena._camp_movement.is_empty() and arena._camp_movement[0][0]==start and Vector2(arena._camp_movement.back()[1]).distance_to(arena.player_pos)<0.001,"Exploration records actual traversed path endpoint")
			for segment: Array in arena._camp_movement:check(arena._geometry.visible(segment[0],segment[1],arena.PLAYER_RADIUS),"Every recorded sweep/slide segment stays outside wall")
			check(arena.get_node("WorldCamera").position==View.follow_position(arena.player_pos,arena.ARENA),"Same-frame camera follows actual clipped destination")
			for cue: Dictionary in arena.visual_cues.cues:
				if cue.kind=="dash":check(cue.destination==arena.player_pos,"Dash cue uses actual clipped destination")
			samples.append({"case":"wall_slide" if diagonal else "wall_sweep","supports":ids,"start":start,"end":arena.player_pos,"path":arena._camp_movement.duplicate(true),"camera":arena.get_node("WorldCamera").position})
		clean();arena.player_pos=arena.ARENA.end-Vector2(arena.PLAYER_RADIUS+40.0,arena.PLAYER_RADIUS+40.0)
		Input.action_press("move_right");Input.action_press("move_down")
		check(cast_direct(ids),"Actual diagonal world-edge cast accepts")
		Input.action_release("move_right");Input.action_release("move_down")
		check(arena.player_pos==arena.ARENA.end-Vector2.ONE*arena.PLAYER_RADIUS,"World bounds clip to exact body-radius corner")
		check(arena._camp_movement.back()[1]==arena.player_pos and arena.get_node("WorldCamera").position==View.follow_position(arena.player_pos,arena.ARENA),"Boundary path and camera report actual corner")
	# Owned group's stable cooldown path uses the same compiler/resource consumers.
	for ids: Array in COMBINATIONS:
		if not link_supports(ids):return
		clean();arena.player_pos=arena.ARENA.position+Vector2(600,1800)
		var current: Dictionary=arena.state.get_group_cast(GROUP)
		if not accepted(current,"Actual owned support combination compiles"):return
		var start: Vector2=arena.player_pos;var before_mana: float=arena.mana
		if not check(arena.cast_group(GROUP),"Actual group cast accepts "+str(ids)):return
		near(arena.player_pos.distance_to(start),280.0,"Actual owned group requests and reaches280 in clear ground",0.001)
		near(before_mana-arena.mana,current.mana,"Owned group charges compiled mana once")
		near(arena.group_cooldown_remaining(GROUP),current.cooldown,"Owned group records exact stable-identity cooldown")
		var before:=frozen_state();check(not arena.cast_group(GROUP) and frozen_state()==before,"Owned group recast rejection preserves complete state")
		no_attack()
	if not link_supports([]):return
	check(arena.state.get_group_cast(GROUP)==plain_owned,"Removing supports restores exact pre-selection owned cast")
	check(stride_owned.long_stride_profile==POLICY,"Original detached Longstride cast survives unlink unchanged")
	completed=true

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v098-runtime-") or not OS.get_user_data_dir().begins_with(isolated+"/"):quit(78);return
	create_timer(45.0).timeout.connect(func()->void:push_error("LONG_STRIDE_RUNTIME watchdog");quit(124))
	var only:=OS.get_environment("LONG_STRIDE_GROUP")
	for test: Callable in [compiler_contract,old_compiler_oracle]:
		if only.is_empty() or only=="compiler":
			if not section(test):await finish();return
	if only=="compiler":await finish();return
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	if not check(file!=null,"Isolated profile destination writable"):await finish();return
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/v094-integration/owned-fixture.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	for test: Callable in [actual_owned_setup,actual_open_movement,malformed_policy_and_gates,actual_geometry_and_group]:
		if not section(test):break
	await finish()
func finish() -> void:
	var report: Dictionary={"checks":checks,"failures":failures,"sections":sections,"failures_detail":labels,"samples":samples,"scope":"Controlled actual Main using one legal saved model; pinned d2d188a compiler and support registry for24 representative old casts. No natural combat, DPS, FPS or Windows claim."}
	var output:=OS.get_environment("LONG_STRIDE_REPORT")
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("LONG_STRIDE_RUNTIME ",checks," checks, ",failures," failures")
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
