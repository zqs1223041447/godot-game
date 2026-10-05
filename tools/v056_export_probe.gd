extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const EXPECTED_CHECKS := 23
var rows: Array[Dictionary] = []
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	rows.append({"ok":ok,"label":label})
	if not ok: failures+=1;push_error(label)
func sha(bytes: PackedByteArray) -> String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func near(a: float,b: float) -> bool: return absf(a-b)<=maxf(1e-8,absf(b)*1e-10)
func run() -> void:
	var output:=OS.get_environment("V056_PACK_QA");var pack:=OS.get_environment("V056_MAIN_PACK");var fixture:=OS.get_environment("V056_OLD_SAVE")
	if output.is_empty() or pack.is_empty() or fixture.is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v056-"):quit(78);return
	create_timer(30.0).timeout.connect(func():push_error("Packed melee-basic probe did not finish");quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_bytes(fixture);var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE);file.store_buffer(original);file.close()
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.hud.close_panel()
	var model:RefCounted=arena.state
	check(str(ProjectSettings.get_setting("application/config/version"))=="0.56.0","Actual packed version")
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))=="godot-game-preview-v021" and model.bag_layout()=={"pages":2,"columns":12,"rows":10},"Existing directory and240slots")
	check(model.snapshot().version==34 and Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())),JSON.parse_string(original.get_string_from_utf8())),"Published schema34 contents load without migration or grants")
	check(FileAccess.get_file_as_bytes(arena.build_save_path)==original and not FileAccess.file_exists("user://build_save.json.v34-backup.json"),"Unchanged schema leaves original save bytes intact")
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	check(sha(font.data)==OS.get_environment("V056_PACK_FONT_SHA256") and font.has_char("挥".unicode_at(0)),"Actual packed font contains added swing glyph")
	var rng:=RandomNumberGenerator.new();rng.seed=560056
	var uid:String=model.award_equipment(rng,16,"normal","forgeblade_v34")
	check(not uid.is_empty() and model.equip(uid) and model.save_build(arena.build_save_path)==OK,"Actual existing catalog sword UID equips and saves")
	var profile:Dictionary=model.get_basic_attack_profile();var cast:Dictionary=model.get_basic_cast()
	check(profile=={"delivery":"melee","radius":60.0,"half_angle":PI/4.0,"max_targets":1} and cast.ok and cast.recipe==profile,"Cached admission and compiled geometry share authority")
	check(cast.packets.size()==1 and cast.packets.has("direct") and cast.packets.direct.tags==["hit","attack","melee"] and near(cast.packets.direct.assembly.weapon.contribution.physical,4.0),"Packed basic/direct uses three tags and one localW")
	profile.radius=999.0
	check(model.get_basic_attack_profile().radius==60.0 and not cast.critical.has("secondary"),"Public profile is detached and melee has no secondary critical role")
	check(Preview.details(cast).contains("近战") and Preview.details(cast).contains("60"),"Actual compiled basic preview explains melee range")
	var reopened:=Model.new()
	check(reopened.load_build(arena.build_save_path) and Same._same_data(reopened.snapshot(),model.snapshot()) and reopened.get_basic_cast()==cast,"Schema34 sword ownership and delivery survive reload")
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Actual formal practice entry")
	arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.attack_timer=0.0;arena.auto_fire=true;arena.hud.close_panel();arena.player_pos=arena.ARENA.get_center()
	var first:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(140,0),"ordinary","",[],false)
	first.spawn=0.0;first.health=10000.0;first.max_health=10000.0;first.radius=1.0;first.armour=0.0;first.evasion=0.0;first.evasion_entropy=50.0;first.shield=0.0;first.resistances={}
	var checkpoint:Dictionary=arena.critical_runtime.checkpoint();arena._update_auto_attack()
	check(arena.attack_timer==0.0 and arena.projectiles.is_empty() and arena.damage_trace.is_empty() and arena.critical_runtime.checkpoint()==checkpoint,"Automatic out-of-range admission does not swing or draw")
	first.pos=arena.player_pos+Vector2(35,0)
	var second:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(45,0),"ordinary","",[],false)
	second.spawn=0.0;second.health=10000.0;second.radius=1.0
	var mana:float=arena.mana;var shots:int=arena.total_shots;var draws:int=arena.critical_runtime.draws;arena._update_auto_attack()
	check(arena.damage_trace.size()==1 and arena.damage_trace[0].target_id==first.id and second.health==10000.0 and arena.projectiles.is_empty(),"Actual auto melee hits nearest single target without a projectile")
	check(arena.mana==mana and arena.total_shots==shots and near(arena.attack_timer,1.0/maxf(0.2,arena.get_stats().attack_speed)) and arena.critical_runtime.draws==draws+1,"Free basic swing keeps attack interval and uses one critical draw")
	var hit:Dictionary=arena.damage_trace[0]
	check(hit.assembly==cast.packets.direct.assembly and near(10000.0-float(first.health),float(hit.total)),"Actual damage consumes frozen local assembly")
	var debt:float=arena.attack_timer;checkpoint=arena.critical_runtime.checkpoint();arena._update_auto_attack()
	check(arena.attack_timer==debt and arena.critical_runtime.checkpoint()==checkpoint and arena.damage_trace.size()==1,"Immediate repeat cannot bypass current attack debt")
	arena.enemies.clear();arena.attack_timer=0.0;draws=arena.critical_runtime.draws;arena._update_basic_melee(model.get_basic_attack_profile(),true)
	check(arena.attack_timer>0.0 and arena.critical_runtime.draws==draws+1 and arena.damage_trace.size()==1 and arena.projectiles.is_empty(),"Manual handler accepts one empty swing without damage")
	debt=arena.attack_timer
	check(model.unequip("weapon") and model.get_basic_attack_profile().delivery=="projectile" and near(arena.attack_timer,debt),"Unequip changes future delivery without resetting timer")
	arena.enemies.append(first);first.pos=arena.player_pos+Vector2(35,0);arena.attack_timer=0.0;arena._update_auto_attack()
	check(arena.projectiles.size()==1 and arena.projectiles[0].payload.role=="projectile","Restored original default emits a real frozen projectile")
	var frozen:=var_to_bytes(arena.projectiles);debt=arena.attack_timer
	check(model.equip(uid) and model.get_basic_attack_profile().delivery=="melee" and arena.attack_timer==debt and var_to_bytes(arena.projectiles)==frozen,"Reequip preserves attack debt and already-flying arrow bytes")
	var seed_shot:Dictionary=arena.projectiles[0]
	while arena.projectiles.size()<arena.MAX_PROJECTILES:
		arena.projectiles.append(arena.projectile_runtime.make_projectile(arena.player_pos+Vector2(0,100),Vector2.RIGHT,{"speed":640.0,"range":650.0,"lifetime":1.7},seed_shot.payload,seed_shot.snapshot,arena.projectile_runtime.new_cast(),Color.WHITE))
	frozen=var_to_bytes(arena.projectiles);var prior:int=arena.damage_trace.size();arena.attack_timer=0.0;arena._update_auto_attack()
	check(arena.damage_trace.size()==prior+1 and arena.projectiles.size()==arena.MAX_PROJECTILES and var_to_bytes(arena.projectiles)==frozen,"Full180valid-carrier capacity cannot block or mutate melee")
	var count:int=arena.damage_trace.size();arena.projectiles.clear();arena._update_projectiles(2.0)
	check(arena.projectiles.is_empty() and arena.damage_trace.size()==count and not arena.event_counts.has("return_started") and not arena.event_counts.has("explosion"),"Direct basic has no delayed return or flight-end explosion")
	var report:Dictionary={"ok":failures==0 and rows.size()==EXPECTED_CHECKS,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V056_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(pack)),"font_sha256":sha(font.data),"schema":34,"weapon_uid":uid,"basic_packet":cast.packets.direct,"actual_hit":hit,"scope":"Linux same-PCK targeted new build; no physical mouse or Windows hardware FPS claim"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("Packed v56 melee-basic probe: %d checks, %d failures"%[rows.size(),failures]);arena.queue_free();await process_frame;quit(0 if report.ok else 1)
