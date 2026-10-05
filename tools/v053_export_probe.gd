extends SceneTree
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Model=preload("res://scripts/canonical_game_state.gd")
const Same=preload("res://scripts/items/crafting_transaction_planner.gd")
const Preview=preload("res://scripts/combat/damage_preview.gd")
const PREFIX:Array[String]=["47175","31628","9511","23881","26523","6446","10221"]
var rows:Array[Dictionary]=[]
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	rows.append({"ok":ok,"label":label})
	if not ok:failures+=1;push_error(label)
func sha(b:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(b);return h.finish().hex_encode()
func near(a:float,b:float)->bool:return absf(a-b)<=0.000001*maxf(1.0,absf(b))
func run()->void:
	var output:String=OS.get_environment("V053_PACK_QA");var pack:String=OS.get_environment("V053_MAIN_PACK");var fixture:String=OS.get_environment("V053_OLD_SAVE")
	if output.is_empty() or pack.is_empty() or fixture.is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v053-"):quit(78);return
	create_timer(30.0).timeout.connect(func():push_error("Packed Fire DoT probe did not finish");quit(1));DirAccess.make_dir_recursive_absolute(output)
	var original:PackedByteArray=FileAccess.get_file_as_bytes(fixture);var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE);file.store_buffer(original);file.close()
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.hud.close_panel()
	var model:RefCounted=arena.state
	check(str(ProjectSettings.get_setting("application/config/version"))=="0.53.0","Actual packed version")
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))=="godot-game-preview-v021" and model.bag_layout()=={"pages":2,"columns":12,"rows":10},"Old directory and240slots")
	check(model.snapshot().version==32 and FileAccess.get_file_as_bytes("user://build_save.json.v31-backup.json")==original,"Real31 migration preserves original bytes")
	var old:Dictionary=JSON.parse_string(original.get_string_from_utf8());old.version=32.0
	check(Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())),old),"Migration changes only version")
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	check(sha(font.data)==OS.get_environment("V053_PACK_FONT_SHA256"),"Raw packed font unchanged")
	var glyphs:=true
	for c:int in "火焰持续伤害加成已计入上方数值".length():glyphs=glyphs and font.has_char("火焰持续伤害加成已计入上方数值".unicode_at(c))
	check(glyphs,"New preview text has raw-font glyphs")
	var candidate:Dictionary=model.snapshot();candidate.progress={"level":3,"xp":0};candidate.talents.class_id=1;candidate.talents.allocated=PREFIX.duplicate();candidate.talents.normal_points=1;candidate.revision+=1
	var funds:Dictionary=model._set_bag_currency_balance(candidate,4)
	check(funds.ok and Rules.reason(candidate).is_empty() and model._commit(candidate,arena.build_save_path).ok,"Lawful isolated Marauder prefix and paid-gem material fixture")
	var quote:Dictionary=arena.normal_gem_trade_quote("buy","support:ignite",model.revision());var purchased:Dictionary=arena.execute_normal_gem_trade(quote.get("handle",""),"support:ignite")
	check(quote.ok and purchased.ok and model.crafting_balance()==0,"Existing merchant sells actual Ignite UID for four shards")
	var group_id:=""
	for group:Dictionary in model.snapshot().skill_groups:
		if model.skill_group(group.id).skill_id=="meteor":group_id=group.id
	check(not group_id.is_empty() and model.move_item(purchased.get("uid",""),{"kind":"skill_support","group_id":group_id,"index":0},model.revision(),arena.build_save_path).ok,"Actual support equips to real Meteor group")
	var base:Dictionary=model.get_group_cast(group_id)
	check(base.ok and not base.snapshot.has("fire_dot_multiplier") and not base.burn_profile.has("fire_dot_multiplier"),"Zero-source packed cast has no extra field")
	var saves:int=model.successful_saves;var rng:int=arena.rng.state
	check(model.available_passives().has("54396") and model.allocate_passive("54396",0,model.revision(),arena.build_save_path).ok,"Real guarded allocation activates existing node54396")
	check(model.talent_points==0 and model.successful_saves==saves+1 and arena.rng.state==rng,"Allocation spends one point/saves once without combat RNG")
	var cast:Dictionary=model.get_group_cast(group_id)
	check(model.get_stats().fire_dot_multiplier_add==0.04 and cast.snapshot.fire_dot_multiplier==0.04 and cast.burn_profile.fire_dot_multiplier==0.04,"Stat/cast/profile agree on additive four percent")
	check(var_to_bytes(cast.packets)==var_to_bytes(base.packets) and cast.mana==base.mana and cast.burn_profile.duration==3.0 and near(cast.burn_profile.roles.direct.dps,base.burn_profile.roles.direct.dps*1.04),"Only burn DPS changes, direct packets/mana/duration stay")
	check("\n".join(Preview.burn_lines(cast)).contains("+4%"),"Packed preview explains already-included bonus")
	var loaded:=Model.new();check(loaded.load_build(arena.build_save_path) and Same._same_data(loaded.snapshot(),model.snapshot()) and loaded.get_group_cast(group_id)==cast,"New allocation and consumer survive actual reload")
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Actual normal combat entry")
	arena.hud.close_panel();arena.enemies.clear();arena.monster_runtime.reset();arena.player_pos=arena.ARENA.get_center();arena.mana=1000.0;arena.auto_fire=false
	var enemy:Dictionary=arena._spawn_monster("brute",arena.player_pos+Vector2(60,0),"ordinary","",[],false);enemy.spawn=0.0;enemy.health=10000.0;enemy.max_health=10000.0;enemy.shield=0.0;enemy.armour=0.0;enemy.resistances.fire=0.25;enemy.speed=0.0;enemy.attack_timer=1000.0
	check(arena.cast_group(group_id),"Real enhanced Meteor cast")
	var burn:Dictionary=arena.burn_runtime.status_for("monster",int(enemy.id));var hit:Dictionary=arena.damage_trace.back()
	check(not burn.is_empty() and near(burn.raw_dps,float(hit.before_defense_components.fire)*0.3*1.04) and burn.remaining==3.0,"Actual positive hit attaches once-enhanced frozen burn")
	check(model.refund_passive("54396",model.revision(),arena.build_save_path).ok and model.talent_points==1 and not model.get_group_cast(group_id).snapshot.has("fire_dot_multiplier"),"Real refund affects next cast, without changing active burn")
	var health:float=enemy.health;var bytes:PackedByteArray=FileAccess.get_file_as_bytes(arena.build_save_path);saves=model.successful_saves;rng=arena.rng.state
	arena.elapsed+=0.5;arena._advance_monster_burns(arena.elapsed)
	check(near(health-float(enemy.health),float(burn.raw_dps)*0.5*0.75) and arena.burn_runtime.status_for("monster",int(enemy.id)).raw_dps==burn.raw_dps,"Half-second real health loss uses original cast after refund")
	check(model.successful_saves==saves and bytes==FileAccess.get_file_as_bytes(arena.build_save_path) and arena.rng.state==rng,"Nonlethal tick introduces no writes or RNG")
	var report:Dictionary={"ok":failures==0 and rows.size()==22,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V053_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(pack)),"font_sha256":sha(font.data),"raw_dps":burn.get("raw_dps",0.0),"actual_half_second_health_loss":health-float(enemy.health),"schema":32,"scope":"Linux same-PCK new-content acceptance; no Windows hardware FPS claim"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("Packed v53 Fire DoT probe: %d checks, %d failures"%[rows.size(),failures]);arena.queue_free();await process_frame;quit(0 if report.ok else 1)
