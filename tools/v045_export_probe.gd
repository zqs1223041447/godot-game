extends SceneTree
const Same=preload("res://scripts/items/crafting_transaction_planner.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("V045_PACK_QA");var expected_font:=OS.get_environment("V045_PACK_FONT_SHA256");var fixture:=OS.get_environment("V045_OLD_SAVE")
	if output.is_empty() or expected_font.length()!=64 or fixture.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var original:PackedByteArray=FileAccess.get_file_as_bytes(fixture)
	var input:=FileAccess.open("user://build_save.json",FileAccess.WRITE);input.store_buffer(original);input.close()
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.hud.close_panel()
	var model:RefCounted=arena.state;var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.45.0" and directory=="godot-game-preview-v021" and model.snapshot().version==28 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font
	var backup_exact:bool=FileAccess.get_file_as_bytes("user://build_save.json.v27-backup.json")==original;ok=ok and backup_exact
	for index:int in "点燃燃烧持续伤害".length():ok=ok and font.has_char("点燃燃烧持续伤害".unicode_at(index))
	var candidate:Dictionary=model.snapshot();ok=ok and model._set_bag_currency_balance(candidate,4).ok;candidate.revision+=1;ok=ok and model._commit(candidate,arena.NORMAL_BUILD_PATH).ok
	var quote:Dictionary=arena.normal_gem_trade_quote("buy","support:ignite",model.revision());ok=ok and quote.ok
	var bought:Dictionary=arena.execute_normal_gem_trade(quote.get("handle",""),"support:ignite");ok=ok and bought.ok and model.crafting_balance()==0
	var group_id:=""
	for group:Dictionary in model.snapshot().skill_groups:
		if model.skill_group(group.id).skill_id=="meteor":group_id=group.id
	ok=ok and not group_id.is_empty() and model.move_item(bought.get("uid",""),{"kind":"skill_support","group_id":group_id,"index":0},model.revision(),arena.NORMAL_BUILD_PATH).ok
	var compiled:Dictionary=model.get_group_cast(group_id);ok=ok and compiled.ok and compiled.has("burn_profile")
	ok=ok and arena.leave_normal_town(arena.world_context().revision).ok
	arena.enemies.clear();arena.monster_runtime.reset();arena.player_pos=arena.ARENA.get_center();arena.mana=1000.0;arena.auto_fire=false;arena.hud.close_panel()
	var enemy:Dictionary=arena._spawn_monster("brute",arena.player_pos+Vector2(100,0));enemy.spawn=0.0;enemy.health=10000.0;enemy.max_health=10000.0;enemy.shield=0.0;enemy.attack_timer=1000.0;enemy.speed=0.0;enemy.resistances.fire=0.25
	ok=ok and arena.cast_group(group_id)
	var statuses:Array=arena.burn_statuses();ok=ok and statuses.size()==1 and statuses[0].raw_dps>0.0
	var life:float=enemy.health;var rng:int=arena.rng.state;var saves:int=model.successful_saves
	arena.elapsed+=0.5;arena._advance_monster_burns(arena.elapsed)
	var actual:float=life-float(enemy.health);var expected:float=float(statuses[0].raw_dps)*0.5*0.75
	ok=ok and is_equal_approx(actual,expected) and rng==arena.rng.state and saves==model.successful_saves
	var record:Dictionary={"target":statuses[0].target_id,"dps":statuses[0].raw_dps,"half_second_actual":actual,"half_second_expected":expected,"no_tick_rng":rng==arena.rng.state,"no_tick_save":saves==model.successful_saves}
	arena.burn_runtime.reset();arena.projectiles.clear();arena.invulnerable=0.0;arena.spawn_timer=1000.0
	var guard:Dictionary=arena._spawn_monster("ember_guard",arena.player_pos+Vector2(80,0));guard.spawn=0.0;guard.attack_timer=0.0;guard.speed=0.0
	arena._start_enemy_telegraphs();var attack:Dictionary=arena.telegraphs.state_for(guard.id)
	ok=ok and attack.has("burn_policy") and attack.profile.windup_seconds==0.7 and attack.profile.radius==90.0
	arena.tick(0.7);var player_burn:=false
	for status:Dictionary in arena.burn_statuses():
		if status.target_kind=="player":player_burn=true
	ok=ok and player_burn
	var result:Dictionary={"ok":ok,"version":version,"schema":model.snapshot().version,"save_directory":directory,"user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"font_characters":font.get_supported_chars().length(),"old27_backup_exact":backup_exact,"bought":bought,"profile":compiled.burn_profile,"burn_record":record,"ember_player_burn":player_burn,"ember_profile":attack.profile}
	var file:=FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("Packed v45 burning probe: ","PASS" if ok else "FAIL");arena.queue_free();await process_frame;quit(0 if ok else 1)
