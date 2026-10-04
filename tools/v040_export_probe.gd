extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("V040_PACK_QA");var expected_font:=OS.get_environment("V040_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64:quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var arena:Node2D=load("res://scenes/main.tscn").instantiate();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var model:RefCounted=arena.state;var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.40.0" and directory=="godot-game-preview-v021" and model.snapshot().version==25 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font
	for index:int in "偷取实际扣除生命法力速率上限".length():ok=ok and font.has_char("偷取实际扣除生命法力速率上限".unicode_at(index))
	var candidate:Dictionary=model.snapshot();candidate.progress.level=3;candidate.progress.xp=0;candidate.talents.class_id=4
	candidate.talents.allocated=["50986","39725","63649","49806","6580","19711","20010","36704"];candidate.talents.normal_points=0
	ok=ok and model.Rules.reason(candidate).is_empty();model._accept_memory(candidate);arena._on_build_changed()
	arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.leech_runtime.clear();arena.health=10.0;arena.mana=30.0
	var target:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(60,0),"ordinary","",[],false)
	target.spawn=0.0;target.health=100000.0;target.max_health=target.health;target.shield=0.0;target.armour=0.0;target.evasion=0.0;target.resistances={}
	var cast:Dictionary=model.get_skill_cast("tornado");var profile:Dictionary=model.get_leech_profile();var saved:=var_to_bytes(model.snapshot());var saves:int=model.successful_saves
	ok=ok and arena._execute_compiled(cast);arena._update_projectiles(0.18)
	var budget_health:=0.0;var budget_mana:=0.0;var applied:=0.0
	for hit:Dictionary in arena.damage_trace:
		applied+=float(hit.shield_spent)+float(hit.health_lost)
		budget_health+=float(hit.get("leech",{}).get("health",0.0));budget_mana+=float(hit.get("leech",{}).get("mana",0.0))
	var before_health:float=arena.health;var before_mana:float=arena.mana;arena._advance_leech(0.5)
	ok=ok and not arena.damage_trace.is_empty() and budget_health>0.0 and is_equal_approx(budget_health,applied*0.004) and is_equal_approx(budget_mana,applied*0.004)
	ok=ok and before_health==10.0 and is_equal_approx(arena.health-before_health,budget_health) and is_equal_approx(arena.mana-before_mana,budget_mana)
	ok=ok and var_to_bytes(model.snapshot())==saved and model.successful_saves==saves
	var preview=load("res://scripts/combat/damage_preview.gd");var lines:PackedStringArray=preview.leech_lines(cast)
	var sheet=load("res://scripts/ui/canonical_character_panel.gd");var values:Dictionary=sheet.leech_stat_values(profile)
	ok=ok and lines.size()==2 and lines[0].contains("0.40%") and values.health_leech_instance==profile.health.instance_rate
	var tree=load("res://scripts/passives/source_tree_runtime.gd");ok=ok and tree.node_effect("36704",0,24).status!="full" and tree.node_effect("36704",0,25).status=="full"
	var result:Dictionary={"ok":ok,"version":version,"schema":model.snapshot().version,"save_directory":directory,"user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"font_characters":font.get_supported_chars().length(),"applied_damage":applied,"life_budget":budget_health,"mana_budget":budget_mana,"life_recovered":arena.health-before_health,"mana_recovered":arena.mana-before_mana,"hit_count":arena.damage_trace.size(),"profile":profile,"preview":Array(lines),"old_gate_rejects":tree.node_effect("36704",0,24).status!="full","runtime_did_not_save":model.successful_saves==saves}
	var file:=FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("Packed v40 leech probe: ","PASS" if ok else "FAIL");arena.queue_free();await process_frame;quit(0 if ok else 1)
