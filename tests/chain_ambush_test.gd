extends "res://tests/chain_shock_build_test.gd"
const Traps = preload("res://scripts/combat/player_trap_runtime.gd")
var old_comparisons := 0
var trap_samples: Array = []

func compile_contract() -> void:
	var old=load("/tmp/godot-chain-ambush-baseline/skill_compiler.gd")
	for stats: Dictionary in [{"damage":26.0},{"damage":26.0,"spell_added_lightning":5.0}]:
		var source: Dictionary=Compiler.Recipes.snapshot(stats,[])
		for skill: String in Compiler.Data.SKILLS:
			var choices: Array=[[]]
			for support: String in old.Supports.supports_for_skill(skill):choices.append([support])
			for links: Array in choices:
				check(var_to_bytes(old.compile_group(skill,source,links))==var_to_bytes(Compiler.compile_group(skill,source,links)),"Whole old compile bytes "+skill+str(links))
				old_comparisons+=1
		for other: Array in [[],["shock"],["chain_reach"],["chain_extension","chain_reach","shock","efficiency"]]:
			var selected: Array=other+["ambush"]
			var before: Dictionary=Compiler.compile_group("chain",source,other)
			var after: Dictionary=Compiler.compile_group("chain",source,selected)
			check(after.ok and not old.compile_group("chain",source,selected).ok,"Real new chain delivery compatibility")
			if not after.ok:continue
			selected.reverse();check(var_to_bytes(after)==var_to_bytes(Compiler.compile_group("chain",source,selected)),"Five-slot ordering remains canonical")
			check(before.recipe==after.recipe and before.packets==after.packets and before.cooldown==after.cooldown,"Original targeting and typed bounce packets unchanged")
			near(after.mana,before.mana*1.25,"Original ambush cost")
			for index: int in range(before.packets.bounces.size()):
				near(HitDamage.resolve(after.packets.bounces[index],after.snapshot.modifiers).total,HitDamage.resolve(before.packets.bounces[index],before.snapshot.modifiers).total*0.85,"Ambush damage applies once per bounce")
			var runtime:=Traps.new()
			check(runtime.can_place(0.0,Vector2.ZERO,after).ok,"Existing carrier accepts bounded chain payload")
			for field: String in ["range","count","tag","role"]:
				var bad: Dictionary=after.duplicate(true)
				if field=="range":bad.recipe.followup_range+=1
				elif field=="count":bad.packets.bounces.pop_back()
				elif field=="tag":bad.packets.bounces[0].tags.append("trap")
				else:bad.packets.bounces[0].role="direct"
				check(not runtime.can_place(0.0,Vector2.ZERO,bad).ok and runtime.is_empty() and runtime._next_id==1,"Malformed chain payload rejects without carrier mutation: "+field)

func carrier_regression() -> void:
	var old_runtime=load("/tmp/godot-chain-ambush-baseline/player_trap_runtime.gd")
	var current:=Traps.new();var previous=old_runtime.new()
	var source: Dictionary=Compiler.Recipes.snapshot({"damage":26.0},[])
	var oracle:=CritRuntime.new()
	for skill: String in ["nova","meteor"]:
		var cast: Dictionary=Compiler.compile_group(skill,source,["ambush"])
		var frozen: Dictionary=oracle.freeze(cast.snapshot).snapshot
		check(current.place(0.0,Vector2(10,20),cast,frozen,1).ok and previous.place(0.0,Vector2(10,20),cast,frozen,1).ok,"Old area carrier accepts original payload")
		check(var_to_bytes(current._entries)==var_to_bytes(previous._entries),"Entire old area trap storage remains byte-identical")
	var chain: Dictionary=Compiler.compile_group("chain",source,["ambush"])
	check(current.place(0.0,Vector2.ZERO,chain,oracle.freeze(chain.snapshot).snapshot,2).ok and current.active_count()==3,"New chain shares old two-area carrier quota")
	check(not current.can_place(0.0,Vector2.ZERO,chain).ok,"Mixed-kind fourth sigil rejected")

func completion_cleanup() -> bool:
	if not link(["ambush"]):return false
	setup_trap();check(arena.cast_group(group_id),"Untriggered chain remains during actual map objective settlement")
	for unused: int in range(8):
		arena._begin_progress_transaction()
		for target: Dictionary in arena.enemies.duplicate():
			if target.health>0.0:kill(target)
		arena._end_progress_transaction();arena._flush_monster_spawns()
		if arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty():break
	arena._check_map_complete()
	check(arena.world_context().mode=="map_complete" and arena.trap_runtime.is_empty(),"Actual full map completion cancels the untriggered chain carrier")
	return failures==0

func setup_trap() -> void:
	prepare_chain();arena.trap_runtime.reset();arena.trap_trace.clear()
	arena._stats.max_mana=500.0;arena._stats.mana_regen=0.0
	arena.elapsed=0.0;arena.attack_timer=999.0

func trap_case(links: Array, spacing: float, expected_count: int) -> bool:
	if not link(links):return false
	setup_trap()
	for index: int in range(8):prep_actor(arena.enemies[index],arena.player_pos+Vector2(60+spacing*index,0),5.0);arena.enemies[index].speed=0.0
	var compiled: Dictionary=arena.state.get_group_cast(group_id)
	var origin: Vector2=arena.player_pos
	var mana_before: float=arena.mana
	check(arena.cast_group(group_id),"Actual owned chain sigil placement")
	near(mana_before-arena.mana,compiled.mana,"Placement pays once")
	check(arena.damage_trace.is_empty() and arena.projectiles.is_empty() and arena.trap_runtime.active_count()==1,"Placement has no damage or projectiles")
	var frozen: Dictionary=arena.trap_runtime._entries[0].duplicate(true)
	var critical_before: Dictionary=arena.critical_runtime.checkpoint()
	arena.tick(0.349)
	check(arena.damage_trace.is_empty() and arena.trap_runtime.active_count()==1,"Actual tick before arming has no hit")
	if not link([]):return false
	check(arena.trap_runtime._entries[0]==frozen,"Unlink preserves entire pending chain and status snapshot")
	arena.player_pos+=Vector2(1200,600)
	var mana_at_trigger: float=arena.mana
	arena.tick(0.0011)
	check(arena.damage_trace.size()==expected_count and arena.trap_runtime.is_empty(),"Original target cap and frozen reach execute from sigil")
	near(arena.mana,mana_at_trigger,"Trigger never charges a second time")
	check(arena.critical_runtime.checkpoint()==critical_before,"Trigger never rolls another critical")
	var seen: Dictionary={};var totals: Array=[]
	for index: int in range(arena.damage_trace.size()):
		var hit: Dictionary=arena.damage_trace[index]
		check(hit.target_id==arena.enemies[index].id and not seen.has(hit.target_id),"Trigger first, then nearest unhit live target")
		seen[hit.target_id]=true
		check(hit.phase=="trap" and hit.cast_id==frozen.cast_id and hit.tags==["hit","spell","chain"],"Real trap provenance, original chain damage identity")
		var expected: Dictionary=HitDamage.resolve(frozen.bounces[index],frozen.snapshot.modifiers,{},float(frozen.snapshot.get("critical_roll",{}).get("multiplier",1.0)))
		near(hit.total,expected.total,"Frozen per-bounce damage resolves once")
		check(arena.shock_runtime.status_at("monster",hit.target_id,arena.elapsed).active==links.has("shock"),"Existing shock attaches only when frozen selection includes it")
		check(not hit.has("shock"),"First hit never amplifies its own newly applied shock")
		totals.append(hit.total)
	trap_samples.append({"links":links,"spacing":spacing,"hits":arena.damage_trace.size(),"placement":origin,"player_at_trigger":arena.player_pos,"mana":compiled.mana,"damage":totals,"critical":frozen.snapshot.get("critical_roll",{})})
	return failures==0

func capacity_and_expiry() -> bool:
	if not link(["ambush"]):return false
	setup_trap()
	for unused: int in range(3):
		arena.group_cooldowns.reset()
		check(arena.cast_group(group_id),"Three controlled placements share original carrier budget")
	arena.group_cooldowns.reset()
	var before:=var_to_bytes([spell_state(),arena.trap_runtime._entries,arena.trap_runtime._next_id,arena.trap_trace])
	check(not arena.cast_group(group_id) and before==var_to_bytes([spell_state(),arena.trap_runtime._entries,arena.trap_runtime._next_id,arena.trap_trace]),"Fourth placement refusal is atomic")
	arena.tick(12.0)
	check(arena.trap_runtime.is_empty() and arena.damage_trace.is_empty(),"Expired untriggered chain never fires")
	return failures==0

func chain_wall() -> bool:
	if not link(["ambush","chain_reach","shock"]):return false
	setup_trap()
	var corner: Vector2=arena.world_geometry().walls[0].position
	arena.player_pos=corner+Vector2(-16,40)
	prep_actor(arena.enemies[0],corner+Vector2(40,-16),10.0);arena.enemies[0].speed=0.0
	check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS) and arena._geometry.is_clear(arena.enemies[0].pos,10.0),"Corner bodies are outside wall")
	check(Vector2(arena.enemies[0].pos).distance_to(arena.player_pos)<80.0 and not arena._terrain_visible(arena.player_pos,arena.enemies[0].pos),"Blocked body is inside original body-extended trigger circle")
	check(arena.cast_group(group_id),"Place actual chain sigil beside wall")
	arena.tick(0.4)
	check(arena.trap_runtime.active_count()==1 and arena.damage_trace.is_empty(),"Wall prevents sigil trigger")
	prep_actor(arena.enemies[1],arena.player_pos+Vector2(0,50),10.0);arena.enemies[1].speed=0.0;arena.enemies[1].spawn=0.5
	arena._update_traps();check(arena.trap_runtime.active_count()==1,"Birth protection cannot trigger sigil")
	arena.enemies[1].spawn=0.0;arena._update_traps()
	check(arena.damage_trace.size()==1 and arena.damage_trace[0].target_id==arena.enemies[1].id,"Visible trigger is first hit; wall blocks subsequent chain")
	check(arena.enemies[0].health==10000.0 and not arena.shock_runtime.status_at("monster",arena.enemies[0].id,arena.elapsed).active,"Wall-hidden enemy gets neither damage nor shock")
	return failures==0

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-chain-ambush-") or not OS.get_user_data_dir().begins_with(isolated+"/") or FileAccess.file_exists("user://build_save.json"):quit(78);return
	compile_contract();carrier_regression()
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/chain-shock-build/owned.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	for group: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(group.id).skill_id=="chain":group_id=group.id
	active_uid=arena.state.skill_group(group_id).main_uid
	support_uid=purchase("support:ambush",4)
	if support_uid.is_empty():await finish();return
	for uid: String in arena.state.snapshot().items:
		var item: Dictionary=arena.state.item(uid)
		if item.kind=="support_gem":owned[item.definition_id.trim_prefix("support:")]=uid
	if not link(["ambush","shock","chain_reach"]):await finish();return
	owned_cast=arena.state.get_group_cast(group_id)
	var restored:=Model.new()
	check(restored.load_build(arena.build_save_path) and restored.snapshot()==arena.state.snapshot() and restored.get_group_cast(group_id)==owned_cast,"Paid sigil UID, original main and linked cast survive strict reload")
	check(arena.state.snapshot().version==61,"Schema61 unchanged")
	saved_fixture=FileAccess.get_file_as_string(arena.build_save_path)
	if not enter("old_garden"):await finish();return
	if not trap_case(["ambush"],200.0,5):await finish();return
	if not trap_case(["ambush","shock","chain_reach"],250.0,5):await finish();return
	if not trap_case(["ambush","shock","chain_reach","chain_extension","efficiency"],250.0,7):await finish();return
	if not capacity_and_expiry():await finish();return
	if not return_to_town("Retain paid trap skill") or not enter("broken_ruins"):await finish();return
	if not chain_wall():await finish();return
	if not completion_cleanup():await finish();return
	await finish()

func finish() -> void:
	var output:=OS.get_environment("AMBUSH_REPORT")
	var result: Dictionary={"checks":checks,"failures":failures,"labels":labels,"old_cast_comparisons":old_comparisons,"samples":trap_samples,"group_id":group_id,"main_uid":active_uid,"support_uid":support_uid,"owned_cast":owned_cast}
	if failures==0:
		FileAccess.open(output.get_base_dir().path_join("owned.json"),FileAccess.WRITE).store_string(saved_fixture)
		result["owned_sha256"]=FileAccess.get_sha256(output.get_base_dir().path_join("owned.json"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print("CHAIN_AMBUSH checks=%d failures=%d old_casts=%d"%[checks,failures,old_comparisons])
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
