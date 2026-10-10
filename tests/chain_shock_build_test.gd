extends "res://tests/cleave_inward_test.gd"
## Existing skill + existing supports: paid ownership, real casts and authored guide.
var bolt_group := ""
var cases: Array = []
var saved_fixture := ""
var owned_cast: Dictionary = {}

func prepare_chain() -> void:
	park();arena.player_pos=arena.ARENA.position+Vector2(400,1600)
	arena.shock_runtime.reset();arena.projectile_runtime.cancel_all(arena.projectiles)
	ready_cast()
	for enemy: Dictionary in arena.enemies: enemy.speed=0.0

func chain_case(links: Array, spacing: float=250.0, first_distance: float=100.0) -> bool:
	if not link(links):return false
	prepare_chain()
	var compiled: Dictionary=arena.state.get_group_cast(group_id)
	for index: int in range(6):
		prep_actor(arena.enemies[index],arena.player_pos+Vector2(first_distance+spacing*index,0),5.0)
		arena.enemies[index].resistances={"lightning":0.25}
		arena.enemies[index].shield=5.0;arena.enemies[index].max_shield=5.0
	var expected_count: int=0 if first_distance>=600.0 else (5 if spacing < (286.0 if links.has("chain_reach") else 220.0) else 1)
	var mana_before: float=arena.mana
	var disk_before:=FileAccess.get_file_as_bytes(arena.build_save_path)
	check(arena.cast_group(group_id),"Actual chain group casts "+str(links))
	near(arena.mana,mana_before-float(compiled.mana),"Exact mana once")
	near(arena.group_cooldown_remaining(group_id),4.5,"Unchanged real cooldown")
	check(arena.damage_trace.size()==expected_count,"Sparse spacing and unchanged five-target cap")
	var seen: Dictionary={}
	var totals: Array=[]
	for index: int in range(arena.damage_trace.size()):
		var hit: Dictionary=arena.damage_trace[index]
		var target: Dictionary=arena.enemies[index]
		check(hit.target_id==target.id and not seen.has(hit.target_id),"Nearest next target, no duplicate target in cast")
		seen[hit.target_id]=true
		check(hit.tags==["hit","spell","chain"] and hit.components.keys()==["lightning"],"Actual bounce keeps lightning spell/chain classification")
		var critical: float=float(hit.get("critical",{}).get("multiplier",1.0))
		var expected: Dictionary=HitDamage.resolve(compiled.packets.bounces[index],compiled.snapshot.modifiers,target.resistances,critical)
		near(hit.total,expected.total,"Original per-bounce damage after actual resistance")
		near(target.shield,maxf(0.0,5.0-expected.total),"Actual shield settled")
		near(target.health,10000.0-maxf(0.0,float(expected.total)-5.0),"Actual health settled")
		check(not hit.has("shock"),"Triggering chain hit never amplifies itself")
		var status: Dictionary=arena.shock_runtime.status_at("monster",target.id,arena.elapsed)
		check(status.active==links.has("shock"),"Only selected support attaches existing shock")
		if status.active:
			near(status.hit_damage_taken_increased,0.15,"Original15% strength")
			near(status.status.remaining_seconds,2.0,"Original2s duration")
		totals.append(hit.total)
	check(not arena.shock_runtime.status_at("monster",arena.enemies[5].id,arena.elapsed).active,"Sixth target receives no status")
	var rejected:=spell_state()
	check(not arena.cast_group(group_id) and spell_state()==rejected,"Cooldown denial remains atomic")
	check(FileAccess.get_file_as_bytes(arena.build_save_path)==disk_before,"Casting never writes owned build")
	cases.append({"links":links,"spacing":spacing,"first_distance":first_distance,"hit_count":arena.damage_trace.size(),"mana":compiled.mana,"cooldown":compiled.cooldown,"damage_after_25_lightning_resistance":totals})
	return failures==0

func followup_case() -> bool:
	if not chain_case(["chain_reach","shock"]):return false
	var target: Dictionary=arena.enemies[0]
	var chain_time: float=arena.elapsed
	var bolt: Dictionary=arena.state.get_group_cast(bolt_group)
	for after_expiry: bool in [false,true]:
		arena.damage_trace.clear()
		check(arena.cast_group(bolt_group),"Existing owned unlinked bolt supplies subsequent real hit")
		for unused: int in range(12):arena.tick(1.0/60.0)
		check(not arena.damage_trace.is_empty(),"Subsequent projectile actually contacts target")
		for hit: Dictionary in arena.damage_trace:
			check(hit.target_id==target.id and hit.skill_id=="bolt","Follow-up sample belongs to actual first target and bolt")
			var expected: Dictionary=HitDamage.resolve(bolt.packets.projectile,bolt.snapshot.modifiers,target.resistances,float(hit.get("critical",{}).get("multiplier",1.0)))
			near(hit.total,float(expected.total)*(1.0 if after_expiry else 1.15),"Actual subsequent hit gains15% only before expiry")
			check(hit.has("shock")==not after_expiry,"Trace reports only active inherited shock")
		if not after_expiry:
			check(arena.elapsed<chain_time+2.0 and arena.group_cooldown_remaining(group_id)>0.0,"Use another skill inside2s while chain remains on4.5s cooldown")
			arena.projectile_runtime.cancel_all(arena.projectiles)
			for unused: int in range(120):arena.tick(1.0/60.0)
	check(arena.elapsed>chain_time+2.0 and not arena.shock_runtime.status_at("monster",target.id,arena.elapsed).active,"Real time expires the original shock")
	return failures==0

func wall_probe() -> bool:
	if not link(["chain_reach","shock"]):return false
	prepare_chain()
	var wall: Rect2=arena.world_geometry().walls[0]
	arena.player_pos=wall.position+Vector2(-50,80)
	prep_actor(arena.enemies[0],arena.player_pos+Vector2(0,50),5.0)
	prep_actor(arena.enemies[1],Vector2(wall.end.x+20,arena.enemies[0].pos.y),5.0)
	check(arena._geometry.is_clear(arena.enemies[0].pos,5.0) and arena._geometry.is_clear(arena.enemies[1].pos,5.0),"Wall fixture has legal target bodies")
	check(Vector2(arena.enemies[0].pos).distance_to(arena.enemies[1].pos)<286.0 and not arena._terrain_visible(arena.enemies[0].pos,arena.enemies[1].pos),"Next target is inside reach but beyond real wall")
	check(arena.cast_group(group_id) and arena.damage_trace.size()==1,"Real wall blocks chain follow-up")
	check(arena.enemies[1].health==10000.0 and not arena.shock_runtime.status_at("monster",arena.enemies[1].id,arena.elapsed).active,"Blocked body takes neither damage nor shock")
	return failures==0

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-chain-shock-") or not OS.get_user_data_dir().begins_with(isolated+"/") or FileAccess.file_exists("user://build_save.json"):quit(78);return
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/v094-integration/owned-fixture.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	check(arena.world_context().normal_town and Rules.reason(arena.state.snapshot()).is_empty(),"Committed owned build loads legally")
	for group: Dictionary in arena.state.snapshot().skill_groups:
		var current: Dictionary=arena.state.skill_group(group.id)
		if current.skill_id=="chain":group_id=group.id
		if current.skill_id=="bolt":bolt_group=group.id
	active_uid=arena.state.skill_group(group_id).main_uid
	check(arena.state.item(active_uid).definition_id=="skill:chain" and not bolt_group.is_empty(),"Reuse existing owned chain and bolt groups")
	var balance: int=arena.state.crafting_balance()
	support_uid=purchase("support:shock",4)
	if support_uid.is_empty():await finish();return
	check(arena.state.crafting_balance()==balance-4 and arena.state.location(support_uid).kind=="bag","Actual paid shock acquisition reaches bag")
	for uid: String in arena.state.snapshot().items:
		var item: Dictionary=arena.state.item(uid)
		if item.kind=="support_gem":owned[item.definition_id.trim_prefix("support:")]=uid
	for uid: String in arena.state.skill_group(bolt_group).support_uids:
		if not uid.is_empty():accepted(arena.state.move_item(uid,arena.state.first_bag_position(uid),arena.state.revision(),arena.build_save_path),"Unlink existing bolt for plain follow-up comparison")
	if not link(["chain_reach","shock"]):await finish();return
	owned_cast=arena.state.get_group_cast(group_id)
	var reloaded:=Model.new()
	check(reloaded.load_build(arena.build_save_path) and reloaded.snapshot()==arena.state.snapshot() and reloaded.get_group_cast(group_id)==owned_cast,"Actual bought and reused UIDs survive strict save/reload")
	check(arena.state.snapshot().version==61,"No schema change")
	saved_fixture=FileAccess.get_file_as_string(arena.build_save_path)
	var source: Dictionary=arena.state.get_combat_snapshot()
	var base: Dictionary=Compiler.compile_group("chain",source,[])
	near(owned_cast.mana,base.mana*1.38,"Existing paired mana multiplication")
	for index: int in range(5):
		var plain: Dictionary=HitDamage.resolve(base.packets.bounces[index],base.snapshot.modifiers)
		var linked: Dictionary=HitDamage.resolve(owned_cast.packets.bounces[index],owned_cast.snapshot.modifiers)
		near(linked.total,float(plain.total)*0.72,"Existing paired per-bounce tradeoff")
	if not enter("old_garden"):await finish();return
	for links: Array in [[],["chain_reach"],["shock"],["chain_reach","shock"]]:
		if not chain_case(links):await finish();return
	for distance: float in [285.99,286.0]:
		if not chain_case(["chain_reach","shock"],distance):await finish();return
	for distance: float in [599.99,600.0]:
		if not chain_case(["chain_reach","shock"],250.0,distance):await finish();return
	if not followup_case():await finish();return
	if not return_to_town("Preserve actual build before wall check") or not enter("broken_ruins"):await finish();return
	if not wall_probe():await finish();return
	await finish()

func finish() -> void:
	var output:=OS.get_environment("CHAIN_REPORT")
	var result: Dictionary={"checks":checks,"failures":failures,"labels":labels,"cases":cases,"group_id":group_id,"bolt_group":bolt_group,"active_uid":active_uid,"support_uid":support_uid,"owned_cast":owned_cast,"source_fixture_sha256":FileAccess.get_sha256("res://docs/qa/v094-integration/owned-fixture.json")}
	if failures==0:
		FileAccess.open(output.get_base_dir().path_join("owned.json"),FileAccess.WRITE).store_string(saved_fixture)
		result["owned_sha256"]=FileAccess.get_sha256(output.get_base_dir().path_join("owned.json"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print("CHAIN_SHOCK_BUILD checks=%d failures=%d"%[checks,failures])
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
