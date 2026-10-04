extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("V039_PACK_QA");var expected_font:=OS.get_environment("V039_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64:quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var arena:Node2D=load("res://scenes/main.tscn").instantiate();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var model:RefCounted=arena.state;var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.39.0" and directory=="godot-game-preview-v021" and model.snapshot().version==24 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font
	for index:int in "暴击几率伤害千家玩".length():ok=ok and font.has_char("暴击几率伤害千家玩".unicode_at(index))
	var cast:Dictionary=model.get_skill_cast("nova");ok=ok and cast.ok and cast.critical.primary=={"chance":0.05,"multiplier":1.5}
	var runtime=load("res://scripts/combat/critical_strike_runtime.gd").new();var seed_value:=-1
	for value:int in range(10000):
		runtime.reset(value)
		if runtime.freeze(cast.snapshot).snapshot.critical_roll.critical:seed_value=value;break
	arena.critical_runtime.reset(seed_value);arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.mana=10000.0
	var target:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(50,0),"ordinary","",[],false);target.spawn=0.0;target.health=100000.0;target.max_health=target.health;target.shield=0.0;target.armour=0.0;target.resistances={}
	var shared_rng:int=arena.rng.state;var saved:=var_to_bytes(model.snapshot())
	runtime.freeze(cast.snapshot);var isolated_rng:bool=arena.rng.state==shared_rng
	ok=ok and arena._execute_compiled(cast) and arena.damage_trace.size()==1 and arena.damage_trace[0].critical.critical and arena.critical_runtime.draws==1
	var normal:Dictionary=arena.Damage.resolve(cast.packets.direct,cast.snapshot.modifiers)
	ok=ok and is_equal_approx(arena.damage_trace[0].total,float(normal.total)*1.5) and isolated_rng and var_to_bytes(model.snapshot())==saved
	var preview=load("res://scripts/combat/damage_preview.gd");var lines:PackedStringArray=preview.critical_lines(cast);ok=ok and lines.size()==1 and lines[0].contains("5.0%") and lines[0].contains("150.0%")
	var coverage=load("res://scripts/passives/source_tree_runtime.gd");ok=ok and coverage.node_effect("35894",0,24).status=="full" and coverage.node_effect("35894",0,23).status!="full"
	var report:Dictionary={"ok":ok,"game_version":version,"schema":model.snapshot().version,"save_directory":directory,"actual_user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"engine":Engine.get_version_info().string,"profile":cast.critical,"critical_hit":arena.damage_trace,"preview":lines,"independent_draws":arena.critical_runtime.draws,"standalone_critical_roll_preserves_shared_rng":isolated_rng,"model_unchanged":var_to_bytes(model.snapshot())==saved,"source_v24_gate":coverage.node_effect("35894",0,24).status,"source_v23_gate":coverage.node_effect("35894",0,23).status,"scope":"Same-package critical consumer, preview, source gate, font and save-directory smoke; broader scoped evidence reused"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	FileAccess.open(output.path_join("GODOT_LICENSE.txt"),FileAccess.WRITE).store_string(Engine.get_license_text());FileAccess.open(output.path_join("GODOT_COPYRIGHT.txt"),FileAccess.WRITE).store_string(JSON.stringify(Engine.get_copyright_info(),"\t",true,true))
	var licenses:Dictionary=Engine.get_license_info();var names:=licenses.keys();names.sort();var text:="Godot 4.6.3 third-party license texts\n\n"
	for name:String in names:text+=name+"\n"+str(licenses[name])+"\n\n"
	FileAccess.open(output.path_join("GODOT_THIRD_PARTY_LICENSES.txt"),FileAccess.WRITE).store_string(text)
	arena.queue_free();await process_frame;print(JSON.stringify(report));quit(0 if ok else 1)
