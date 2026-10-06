extends "res://tests/physical_fire_conversion_gameplay_test.gd"
## The identical external script executes against verified07922581 and v078.
## Typed snapshots, compiled packets, Damage receipts and runtime results are
## unprojected. Actor source policy metadata and save schema are compared alone.
const Preview=preload("res://scripts/combat/damage_preview.gd")
var metadata: Array=[]

func actor_without_source_versions(value: Array, path: String="") -> Array:
	var result: Array=value.duplicate(true)
	for index: int in result.size():
		var actor: Dictionary=result[index]
		var actor_path: String=path+"/"+str(index)
		if actor.has("mechanism_policy") and actor.mechanism_policy is String and actor.mechanism_policy.contains("source-tree:"):
			metadata.append({"path":actor_path+"/mechanism_policy","value":actor.mechanism_policy})
			actor.mechanism_policy=actor.mechanism_policy.replace(":policy:45",":policy:0").replace(":policy:48",":policy:0")
		for grant_index: int in actor.get("mechanism_source_grants",[]).size():
			var grant: Dictionary=actor.mechanism_source_grants[grant_index]
			for field: String in ["source_policy","source_save_version","policy_version"]:
				if not grant.has(field): continue
				metadata.append({"path":actor_path+"/mechanism_source_grants/"+str(grant_index)+"/"+field,"value":grant[field]})
				if field=="policy_version": grant[field]=grant[field].replace(":policy:45",":policy:0").replace(":policy:48",":policy:0")
				else: grant[field]=0
	return result

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v078-gameplay") or not OS.get_user_data_dir().begins_with(isolated+"/"): quit(78); return
	create_timer(35.0).timeout.connect(watchdog)
	arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire=false
	var output:=OS.get_environment("ELEMENTAL_LEGACY_OUTPUT")
	var samples: Array=[]; var actors: Array=[]; var raw_actor_samples: Array=[]
	legal_source_and_owned_group()
	if not check(completed,"Known legal fire route setup completed"): quit(1); return
	for amount: float in [0.0,0.4]:
		if not set_mastery(amount==0.4): quit(1); return
		for skill: String in ["basic","cleave","tornado","nova","meteor"]:
			clean(); arena.wave=6; var stats:=controlled_stats(true); stats[STAT]=amount
			var snapshot: Dictionary=arena.state.get_combat_snapshot() if skill=="basic" else Combat.snapshot(stats,["return_on_range","explode_on_flight_end"])
			var links: Array=["physical_focus","fire_focus","ignite"] if skill=="tornado" else ["ignite"] if skill=="meteor" else []
			var cast: Dictionary=Compiler.compile_basic(snapshot) if skill=="basic" else Compiler.compile_group(skill,snapshot,links)
			if not accepted(cast,"Frozen old "+skill): quit(1); return
			var enemy:=target(Vector2(40,0)); enemy.armour=40.0; enemy.resistances={"fire":0.25,"cold":0.1,"lightning":0.1}
			var source_actor: Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(700,0),"ordinary","magic",["source_ember_power"],false)
			if not check(not source_actor.is_empty(),"Real source-policy monster"): quit(1); return
			source_actor.spawn=1000.0
			if skill=="basic":
				arena.auto_fire=true; arena._update_auto_attack(); arena.auto_fire=false
				if not check(arena.damage_trace.size()==1,"Actual legal basic auto-attack admission and hit"): quit(1); return
			elif not check(arena._execute_compiled(cast),"Frozen old actual cast "+skill): quit(1); return
			for index: int in range(8): arena._update_projectiles(0.1)
			arena.elapsed=0.8; arena._advance_monster_burns(0.8)
			var damage_receipts: Array=[]
			for entry: Dictionary in Preview.entries(cast): damage_receipts.append(arena.Damage.resolve(entry.packet,cast.snapshot.modifiers,{"physical":0.1,"fire":0.25,"cold":0.1,"lightning":0.1},2.0))
			samples.append({"kind":[amount,skill],"typed_snapshot":snapshot,"compiled":cast,"damage_receipts":damage_receipts,
				"damage":arena.damage_trace.duplicate(true),"burn":arena.burn_runtime.statuses(),"burn_trace":arena.burn_trace.duplicate(true),
				"projectiles":arena.projectiles.duplicate(true),"events":arena.event_counts.duplicate(true),"leech":arena.leech_runtime.snapshot(),
				"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint(),"health":enemy.health,"shield":enemy.shield,
				"resources":[arena.health,arena.mana,arena.shield],"model_snapshot":arena.state.get_combat_snapshot()})
			raw_actor_samples.append(arena.enemies.duplicate(true)); actors.append(actor_without_source_versions(arena.enemies,"sample/"+str(samples.size()-1)))
	if not check(arena.save_build(),"Real source save"): quit(1); return
	FileAccess.open(output+".bin",FileAccess.WRITE).store_buffer(var_to_bytes(samples))
	FileAccess.open(output+".actors.bin",FileAccess.WRITE).store_buffer(var_to_bytes(raw_actor_samples))
	FileAccess.open(output+".actors-without-policy-versions.bin",FileAccess.WRITE).store_buffer(var_to_bytes(actors))
	FileAccess.open(output+".save",FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
	FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples.size(),"source_metadata":metadata},"\t",true,true))
	print("ELEMENTAL_LEGACY ",JSON.stringify({"checks":checks,"failures":failures,"samples":samples.size()}))
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
