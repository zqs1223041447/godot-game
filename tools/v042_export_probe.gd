extends SceneTree
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Items=preload("res://scripts/items/unified_item_catalog.gd")
const Card=preload("res://scripts/ui/unified_item_presentation.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("V042_PACK_QA");var expected_font:=OS.get_environment("V042_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64 or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	var model:RefCounted=arena.state;var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.42.0" and directory=="godot-game-preview-v021" and model.snapshot().version==27 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font and arena.world_context().normal_town
	for index:int in "血汲灵汲锐察重创个百分点".length():ok=ok and font.has_char("血汲灵汲锐察重创个百分点".unicode_at(index))
	ok=ok and arena.save_build()
	var uid:String="gear_%06d"%int(model.snapshot().next_item_serial);var affixes:Array=[]
	for id:String in Gear.BuildAffixes.AFFIX_IDS:affixes.append({"id":id,"tier":3,"value":Gear.affix_definition(id).tiers[2].max})
	var item:Dictionary={"id":uid,"base_id":"wayglass_token","rarity":"rare","item_level":16,"affixes":affixes}
	ok=ok and model._admit_reward_item(Items.wrap_equipment(item))
	ok=ok and model.move_item(uid,{"kind":"equipment","slot_id":"amulet"},model.revision(),arena.NORMAL_BUILD_PATH).ok
	var view:Dictionary=Card.view(model,uid);var profile:Dictionary=model.get_leech_profile();var cast:Dictionary=model.get_skill_cast("tornado")
	ok=ok and "\n".join(view.affix_lines).contains("0.60%") and "\n".join(view.affix_lines).contains("+15个百分点")
	ok=ok and is_equal_approx(cast.critical.primary.chance,0.07) and is_equal_approx(cast.critical.primary.multiplier,1.65) and is_equal_approx(profile.health.attack_fraction,0.006) and is_equal_approx(profile.mana.attack_fraction,0.0035)
	ok=ok and arena.leave_normal_town(arena.world_context().revision).ok
	arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.leech_runtime.clear();arena.health=10.0;arena.mana=30.0;arena.player_facing=Vector2.RIGHT
	var target:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(60,0),"ordinary","",[],false)
	target.spawn=0.0;target.health=100000.0;target.max_health=target.health;target.shield=0.0;target.armour=0.0;target.evasion=0.0;target.resistances={}
	ok=ok and arena._execute_compiled(cast);arena._update_projectiles(0.18)
	var applied:=0.0;var life_budget:=0.0;var mana_budget:=0.0
	for hit:Dictionary in arena.damage_trace:
		applied+=float(hit.health_lost)+float(hit.shield_spent);life_budget+=float(hit.get("leech",{}).get("health",0.0));mana_budget+=float(hit.get("leech",{}).get("mana",0.0))
	ok=ok and applied>0.0 and is_equal_approx(life_budget,applied*0.006) and is_equal_approx(mana_budget,applied*0.0035)
	var before_health:float=arena.health;var before_mana:float=arena.mana;arena._advance_leech(0.5)
	ok=ok and arena.health>before_health and arena.mana>before_mana
	var result:Dictionary={"ok":ok,"version":version,"schema":model.snapshot().version,"save_directory":directory,"user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"font_characters":font.get_supported_chars().length(),"equipment":item,"affix_lines":view.affix_lines,"critical":cast.critical,"leech":profile,"actual_damage":applied,"life_budget":life_budget,"mana_budget":mana_budget,"recovered_life":arena.health-before_health,"recovered_mana":arena.mana-before_mana}
	var file:=FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("Packed v42 equipment build probe: ","PASS" if ok else "FAIL");arena.queue_free();await process_frame;quit(0 if ok else 1)
