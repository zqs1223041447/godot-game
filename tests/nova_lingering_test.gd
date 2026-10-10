extends "res://tests/chain_ambush_test.gd"
var nova_samples: Array=[]

func nova_compile_checks() -> void:
	var old=load("/tmp/godot-nova-lingering-baseline/skill_compiler.gd")
	for stats: Dictionary in [{"damage":26.0},{"damage":26.0,"cold_ailment_duration_increased":0.2}]:
		var source: Dictionary=Compiler.Recipes.snapshot(stats,[])
		for skill: String in Compiler.Data.SKILLS:
			var choices: Array=[[]]
			for support: String in old.Supports.supports_for_skill(skill):choices.append([support])
			for links: Array in choices:
				check(var_to_bytes(old.compile_group(skill,source,links))==var_to_bytes(Compiler.compile_group(skill,source,links)),"Whole old cast bytes "+skill+str(links));comparisons+=1
		for other: Array in [[],["ambush"],["breadth","shock","ambush","efficiency"]]:
			var selected: Array=other+["lingering_chill"]
			var before: Dictionary=Compiler.compile_group("nova",source,other)
			var after: Dictionary=Compiler.compile_group("nova",source,selected)
			check(after.ok and not old.compile_group("nova",source,selected).ok,"Formerly unsupported nova duration now compiles")
			if not after.ok:continue
			var recipe: Dictionary=after.recipe.duplicate(true);recipe.erase("slow")
			check(recipe==before.recipe and after.packets==before.packets and after.cooldown==before.cooldown,"New duration preserves old radius, typed packets and cooldown")
			near(after.recipe.slow,0.9,"Generic nova slow ignores cold ailment source attribute")
			near(after.mana,before.mana*1.1,"Original duration support mana multiplier")
			near(HitDamage.resolve(after.packets.direct,after.snapshot.modifiers).total,HitDamage.resolve(before.packets.direct,before.snapshot.modifiers).total*0.9,"Original support hit tradeoff once")
			selected.reverse();check(var_to_bytes(after)==var_to_bytes(Compiler.compile_group("nova",source,selected)),"Five-slot ordering is canonical")
			if after.has("trap_profile"):
				var runtime:=Traps.new();check(runtime.can_place(0.0,Vector2.ZERO,after).ok,"Original sigil accepts frozen extended nova")
				after.recipe.slow=1.0
				check(not runtime.can_place(0.0,Vector2.ZERO,after).ok and runtime.is_empty(),"Forged sigil slow refuses atomically")
		var frost: Dictionary=Compiler.compile_group("frost",source,["lingering_chill"])
		near(frost.recipe.slow,5.4 if stats.has("cold_ailment_duration_increased") else 4.5,"Frost keeps its distinct original source duration consumer")

func old_carrier_bytes() -> void:
	var old_runtime=load("/tmp/godot-nova-lingering-baseline/player_trap_runtime.gd")
	var old=old_runtime.new();var current:=Traps.new();var oracle:=CritRuntime.new()
	var source: Dictionary=Compiler.Recipes.snapshot({"damage":26.0},[])
	for skill: String in ["nova","meteor","chain"]:
		var cast: Dictionary=Compiler.compile_group(skill,source,["ambush"])
		var frozen: Dictionary=oracle.freeze(cast.snapshot).snapshot
		check(old.place(0.0,Vector2.ZERO,cast,frozen,1).ok and current.place(0.0,Vector2.ZERO,cast,frozen,1).ok,"Old and new carriers admit unchanged "+skill)
		check(var_to_bytes(old._entries)==var_to_bytes(current._entries),"Whole old sigil entries remain exact "+skill)

func nova_case(links: Array) -> bool:
	if not link(links):return false
	setup_trap()
	var target: Dictionary=arena.enemies[0]
	prep_actor(target,arena.player_pos+Vector2(50,0),5.0);target.speed=0.0
	var protected: Dictionary=arena.enemies[1]
	prep_actor(protected,arena.player_pos+Vector2(0,50),5.0);protected.spawn=1.0;protected.speed=0.0
	var cast: Dictionary=arena.state.get_group_cast(group_id)
	var trap: bool=links.has("ambush")
	var duration: float=0.9 if links.has("lingering_chill") else 0.6
	var before: float=arena.mana
	check(arena.cast_group(group_id),"Actual owned nova casts "+str(links))
	near(before-arena.mana,cast.mana,"Exact one-time mana payment")
	near(arena.group_cooldown_remaining(group_id),cast.cooldown,"Unchanged original cooldown")
	if trap:
		check(target.slow==0.0 and arena.damage_trace.is_empty(),"Placement does not preapply slow or hit")
		var frozen: Dictionary=arena.trap_runtime._entries[0].duplicate(true)
		if not link([]):return false
		check(arena.trap_runtime._entries[0]==frozen,"Unlink leaves whole carrier unchanged")
		arena.player_pos+=Vector2(500,0)
		arena.elapsed=0.35;arena._update_traps()
		check(arena.trap_runtime.is_empty(),"Armed sigil consumes actual nearby target")
	near(target.slow,duration,"Actual direct or delayed hit applies correct frozen duration")
	check(protected.slow==0.0 and protected.health==10000.0,"Birth-protected body gets neither slow nor damage")
	check(arena.damage_trace.size()==1 and arena.damage_trace[0].tags==["hit","spell","area"],"One original area hit with unchanged damage identity")
	var hit: Dictionary=arena.damage_trace[0]
	near(hit.total,HitDamage.resolve(cast.packets.direct,cast.snapshot.modifiers,{},float(hit.get("critical",{}).get("multiplier",1.0))).total,"Actual damage equals frozen compiler preview")
	near(target.knockback.length(),190.0,"Original knockback magnitude unchanged")
	nova_samples.append({"links":links,"duration":target.slow,"mana":cast.mana,"hit":hit.total,"radius":cast.recipe.radius,"phase":hit.phase})
	return failures==0

func movement_and_refresh() -> bool:
	if not nova_case(["lingering_chill"]):return false
	var target: Dictionary=arena.enemies[0]
	target.knockback=Vector2.ZERO;target.speed=100.0
	var start: Vector2=target.pos
	arena._update_enemies(0.1)
	near(start.distance_to(target.pos),3.6,"Existing actual movement uses original0.36 speed factor")
	near(target.slow,0.8,"Existing world delta consumes extended timer")
	target.speed=0.0;arena._update_enemies(0.7)
	near(target.slow,0.1,"Extended slow survives beyond original0.6 seconds")
	arena._update_enemies(0.11);near(target.slow,0.0,"Extended slow expires through existing timer")
	target.slow=1.2;ready_cast()
	check(arena.cast_group(group_id),"Second real nova uses original refresh path")
	near(target.slow,1.2,"Shorter application uses max, never sums durations")
	ready_cast();arena.mana=float(arena.state.get_group_cast(group_id).mana)-0.01
	var rejected:=spell_state()
	check(not arena.cast_group(group_id) and spell_state()==rejected,"Insufficient mana rejects without cast-state mutation")
	return failures==0

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-nova-lingering-") or not OS.get_user_data_dir().begins_with(isolated+"/") or FileAccess.file_exists("user://build_save.json"):quit(78);return
	nova_compile_checks();old_carrier_bytes()
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/chain-ambush/owned.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	for group: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(group.id).skill_id=="nova":group_id=group.id
	active_uid=arena.state.skill_group(group_id).main_uid
	for uid: String in arena.state.snapshot().items:
		var item: Dictionary=arena.state.item(uid)
		if item.kind=="support_gem":owned[item.definition_id.trim_prefix("support:")]=uid
	support_uid=owned.lingering_chill
	var balance: int=arena.state.crafting_balance();var item_count: int=arena.state.snapshot().items.size()
	if not link(["lingering_chill","ambush"]):await finish();return
	check(arena.state.crafting_balance()==balance and arena.state.snapshot().items.size()==item_count,"Reuse existing gem without duplicate purchase, gift or charge")
	owned_cast=arena.state.get_group_cast(group_id)
	var restored:=Model.new()
	check(restored.load_build(arena.build_save_path) and restored.snapshot()==arena.state.snapshot() and restored.get_group_cast(group_id)==owned_cast,"Existing exact UIDs and new legal links survive strict schema61 reload")
	check(arena.state.snapshot().version==61,"No schema increment")
	saved_fixture=FileAccess.get_file_as_string(arena.build_save_path)
	if not enter("old_garden"):await finish();return
	for links: Array in [[],["lingering_chill"],["ambush","lingering_chill"],["ambush","lingering_chill","breadth","shock","efficiency"]]:
		if not nova_case(links):await finish();return
	if not movement_and_refresh():await finish();return
	await finish()

func finish() -> void:
	var output:=OS.get_environment("NOVA_REPORT")
	var result: Dictionary={"checks":checks,"failures":failures,"labels":labels,"old_cast_comparisons":comparisons,"samples":nova_samples,"group_id":group_id,"main_uid":active_uid,"support_uid":support_uid,"owned_cast":owned_cast}
	if failures==0:
		FileAccess.open(output.get_base_dir().path_join("owned.json"),FileAccess.WRITE).store_string(saved_fixture)
		result["owned_sha256"]=FileAccess.get_sha256(output.get_base_dir().path_join("owned.json"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print("NOVA_LINGERING checks=%d failures=%d old_casts=%d"%[checks,failures,comparisons])
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
