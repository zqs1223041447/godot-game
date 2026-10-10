extends "res://tests/chain_ambush_test.gd"
var outcomes: Array=[]

func crawler() -> Dictionary:
	for enemy: Dictionary in arena.enemies:
		if enemy.health>0.0 and enemy.template_id=="crawler":return enemy
	check(false,"Real living crawler available")
	return {}

func dead_before_trigger() -> bool:
	setup_trap();var target: Dictionary=crawler()
	prep_actor(target,arena.player_pos+Vector2(40,0),5.0)
	check(arena.cast_group(group_id),"Place before candidate dies")
	kill(target)
	check(target.health<=0.0 and arena.enemies.has(target),"Actual settlement leaves settled corpse before filtering")
	arena.elapsed=0.35;arena._update_traps()
	check(arena.trap_runtime.active_count()==1 and arena.damage_trace.is_empty(),"Dead candidate cannot trigger armed chain")
	arena._flush_monster_spawns()
	check(not arena.enemies.has(target),"Original lifecycle physically removes settled corpse")
	arena._update_traps()
	check(arena.trap_runtime.active_count()==1 and arena.damage_trace.is_empty(),"Removed candidate cannot trigger or consume chain")
	var replacement: Dictionary=crawler();prep_actor(replacement,arena.player_pos+Vector2(50,0),5.0)
	arena._update_traps()
	check(arena.damage_trace.size()==1 and arena.damage_trace[0].target_id==replacement.id and arena.trap_runtime.is_empty(),"Later live candidate consumes waiting sigil once")
	outcomes.append({"case":"dead_removed_before_trigger","dead":target.id,"replacement":replacement.id})
	return failures==0

func simultaneous_and_chain_death() -> bool:
	setup_trap();var candidates: Array=[]
	for enemy: Dictionary in arena.enemies:
		if enemy.health>0.0 and enemy.template_id=="crawler":candidates.append(enemy)
	if not check(candidates.size()>=2,"Two real living candidates available"):return false
	var a: Dictionary=candidates[0];var b: Dictionary=candidates[1]
	check(arena.cast_group(group_id),"Place before candidates enter together")
	prep_actor(a,arena.player_pos+Vector2(40,0),5.0);prep_actor(b,arena.player_pos+Vector2(-40,0),5.0)
	arena.enemies.reverse();arena.tick(0.35)
	check(arena.damage_trace.size()==2 and arena.damage_trace[0].target_id==mini(a.id,b.id),"Same-tick equal-distance first trigger uses minimum ID despite reversed storage")
	check(arena.trap_trace.back().target_id==arena.damage_trace[0].target_id,"Chain first hit is exact selected trigger")
	setup_trap();prep_actor(a,arena.player_pos+Vector2(40,0),5.0);prep_actor(b,arena.player_pos+Vector2(210,0),5.0)
	a.health=1.0;b.health=1.0
	for unused: int in range(2):
		arena.group_cooldowns.reset();check(arena.cast_group(group_id),"Place two ordered chain sigils")
	var first: int=arena.trap_runtime._entries[0].id
	var second: int=arena.trap_runtime._entries[1].id
	arena.tick(0.35)
	check(a.health<=0.0 and b.health<=0.0 and arena.damage_trace.size()==2,"First lethal bounce still continues from dead trigger's captured position")
	check(arena.damage_trace[0].target_id==a.id and arena.damage_trace[1].target_id==b.id,"Lethal chain follows original target exclusion and continuation")
	check(arena.trap_runtime.active_count()==1 and arena.trap_runtime._entries[0].id==second,"Later sigil rereads deaths and stays armed")
	var triggers: Array=[]
	for event: Dictionary in arena.trap_trace:
		if event.event=="triggered":triggers.append(event.id)
	check(triggers==[first],"Exactly one chain trigger consumed")
	outcomes.append({"case":"same_tick_and_lethal_chain","first":first,"waiting":second,"targets":[a.id,b.id]})
	return failures==0

func restart_cancellation() -> void:
	check(arena.trap_runtime.active_count()==1,"Pending chain exists immediately before real restart")
	var items: Dictionary=arena.state.snapshot().items.duplicate(true)
	var locations: Dictionary=arena.state.snapshot().locations.duplicate(true)
	arena.restart_run();pause()
	check(arena.trap_runtime.is_empty() and arena.trap_trace.is_empty(),"Actual restart cancels pending chain and old trace")
	var before:=var_to_bytes([arena.damage_trace,arena.mana,arena.critical_runtime.checkpoint()])
	arena.elapsed=1.0;arena._update_traps()
	check(before==var_to_bytes([arena.damage_trace,arena.mana,arena.critical_runtime.checkpoint()]),"Cancelled chain never fires, charges or rolls later")
	check(arena.state.snapshot().items==items and arena.state.snapshot().locations==locations,"Restart retains owned gem identities and links")

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-chain-followup-") or not OS.get_user_data_dir().begins_with(isolated+"/") or FileAccess.file_exists("user://build_save.json"):quit(78);return
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/chain-ambush/owned.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	for group: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(group.id).skill_id=="chain":group_id=group.id
	active_uid=arena.state.skill_group(group_id).main_uid
	for uid: String in arena.state.snapshot().items:
		var item: Dictionary=arena.state.item(uid)
		if item.kind=="support_gem":owned[item.definition_id.trim_prefix("support:")]=uid
	if not link(["ambush"]) or not enter("old_garden"):await finish();return
	if not dead_before_trigger() or not simultaneous_and_chain_death():await finish();return
	restart_cancellation();await finish()

func finish() -> void:
	FileAccess.open(OS.get_environment("FOLLOWUP_REPORT"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"labels":labels,"cases":outcomes},"\t",true,true)+"\n")
	print("CHAIN_FOLLOWUP checks=%d failures=%d"%[checks,failures])
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
