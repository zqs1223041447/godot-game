extends SceneTree
## Instrument the frozen oracle, never the shipping runtime. Times include probes.
const Model = preload("res://scripts/canonical_game_state.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Monsters = preload("res://scripts/monsters/monster_runtime.gd")
func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v038-projectile"):
		quit(78)
		return
	var source := FileAccess.get_file_as_string("res://docs/qa/v038-projectiles/projectile_runtime_f074c26.gd.txt").replace("class_name ProjectileRuntime\n", "")
	source = source.replace("var _index_active: bool = false", "var _index_active: bool = false\nvar profile: Dictionary = {\"contacts\":0,\"events\":0,\"index\":0,\"query\":0,\"sort_contacts\":0}")
	source = source.replace("\t\t_target_index.rebuild(targets)", "\t\tvar index_start := Time.get_ticks_usec()\n\t\t_target_index.rebuild(targets)\n\t\tprofile.index += Time.get_ticks_usec()-index_start")
	source = source.replace("\t_sequence += 1", "\tvar profile_start := Time.get_ticks_usec()\n\t_sequence += 1").replace("\tevents.append(event)", "\tevents.append(event)\n\tprofile.events += Time.get_ticks_usec()-profile_start")
	source = source.replace("\tvar result: Array[Dictionary] = []", "\tvar profile_start := Time.get_ticks_usec()\n\tvar result: Array[Dictionary] = []")
	source = source.replace("\tif _in_advance:\n\t\tlast_contact_queries", "\tprofile.query += Time.get_ticks_usec()-profile_start\n\tif _in_advance:\n\t\tlast_contact_queries")
	source = source.replace("\tresult.sort_custom(", "\tvar sort_start := Time.get_ticks_usec()\n\tresult.sort_custom(")
	source = source.replace("\treturn result", "\tprofile.sort_contacts += Time.get_ticks_usec()-sort_start\n\tprofile.contacts += Time.get_ticks_usec()-profile_start\n\treturn result")
	var instrumented := GDScript.new()
	instrumented.source_code = source
	if instrumented.reload() != OK:
		quit(1)
		return
	var model := Model.new()
	var cast: Dictionary = Compiler.compile_group("bolt", model.get_combat_snapshot(), ["pierce"])
	var samples: Array = []
	for layout: String in ["spread", "dense"]:
		var factory := Monsters.new()
		var targets: Array[Dictionary] = []
		for i: int in range(100):
			var pos := Vector2(80+(i%10)*100,80+int(i/10)*50) if layout=="spread" else Vector2(540+(i%10)*14,260+int(i/10)*14)
			var enemy: Dictionary = factory.create_root("crawler",1,pos,"ordinary","normal",[],false)
			enemy.spawn = 0.0
			targets.append(enemy)
		for amount: int in [30,180]:
			var records: Array = []
			for repetition: int in range(20):
				var runtime = instrumented.new()
				var shots: Array[Dictionary] = []
				for j: int in range(amount):
					var origin := Vector2(60+(j%10)*100,70+int(j%100/10)*50) if layout=="spread" else Vector2(530+(j%10)*13,250+int(j%100/10)*13)
					shots.append(runtime.make_projectile(origin,Vector2.RIGHT,cast.recipe,cast.packets.projectile,cast.snapshot,runtime.new_cast(),Color.WHITE))
				var started := Time.get_ticks_usec()
				var events: Array[Dictionary] = runtime.advance(shots,1.0/60.0,targets,Vector2(500,300),180)
				records.append({"advance_us":Time.get_ticks_usec()-started,"profile":runtime.profile,"events":events.size(),"candidate_visits":runtime.last_candidate_visits})
			samples.append({"layout":layout,"shots":amount,"targets":100,"records":records})
	FileAccess.open("res://docs/qa/v038-projectiles/profile-reproduction.json",FileAccess.WRITE).store_string(JSON.stringify({"samples":samples},"\t",true,true))
	print("Projectile contact profiling complete (instrumented oracle, not performance claim)")
	quit()
