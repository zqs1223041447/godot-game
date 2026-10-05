extends SceneTree
## A short new-build probe against the exact PCK embedded in the Windows EXE.
const Same=preload("res://scripts/items/crafting_transaction_planner.gd")
const Model=preload("res://scripts/canonical_game_state.gd")
const Preview=preload("res://scripts/combat/damage_preview.gd")
const Rules=preload("res://scripts/combat/shock_rules.gd")
var rows:Array[Dictionary]=[]
var failures:=0
var arena:Node
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	rows.append({"ok":ok,"label":label})
	if not ok:failures+=1;push_error(label)
func sha(data:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(data);return h.finish().hex_encode()
func run()->void:
	var output:String=OS.get_environment("V052_PACK_QA");var pack:String=OS.get_environment("V052_MAIN_PACK");var expected_font:String=OS.get_environment("V052_PACK_FONT_SHA256");var fixture:String=OS.get_environment("V052_OLD_SAVE")
	if output.is_empty() or pack.is_empty() or expected_font.length()!=64 or fixture.is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v052-"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(30.0).timeout.connect(func():push_error("Packed shock probe did not finish");quit(1))
	var original:PackedByteArray=FileAccess.get_file_as_bytes(fixture);var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE);file.store_buffer(original);file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.hud.close_panel()
	var model:RefCounted=arena.state
	check(str(ProjectSettings.get_setting("application/config/version"))=="0.52.0","Packed version is v0.52.0")
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))=="godot-game-preview-v021" and model.bag_layout()=={"pages":2,"columns":12,"rows":10},"Existing user directory and 240 slots remain")
	check(model.snapshot().version==31 and FileAccess.get_file_as_bytes("user://build_save.json.v30-backup.json")==original,"Actual old30 load migrates with original raw-byte backup")
	var old:Dictionary=JSON.parse_string(original.get_string_from_utf8());old.version=31.0
	check(Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())),old),"Migration changes only schema version")
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	check(sha(font.data)==expected_font,"Packed font is the verified frozen subset")
	var glyphs:=true
	for i:int in "感电追溯命中持续伤害刷新".length():glyphs=glyphs and font.has_char("感电追溯命中持续伤害刷新".unicode_at(i))
	check(glyphs,"Shock text has raw-font glyph coverage without system fallback")
	var texture:=load("res://assets/ui/grimoire/shock.png") as Texture2D
	check(texture!=null and texture.get_width()==512,"New original transparent icon imports in the PCK")
	var offer:Dictionary={}
	for row:Dictionary in arena.normal_gem_offers():
		if row.definition_id=="support:shock":offer=row
	check(not offer.is_empty() and offer.cost==4,"Formal merchant dynamically offers Shock at four shards")
	var candidate:Dictionary=model.snapshot();var funded:Dictionary=model._set_bag_currency_balance(candidate,4);candidate.revision+=1
	check(funded.ok and model._commit(candidate,arena.NORMAL_BUILD_PATH).ok,"Isolated fixture uses real physical shard transaction")
	var quote:Dictionary=arena.normal_gem_trade_quote("buy","support:shock",model.revision())
	check(quote.ok and quote.cost=={"calibration_shard":4},"Authoritative purchase quote")
	var purchased:Dictionary=arena.execute_normal_gem_trade(quote.get("handle",""),"support:shock")
	check(purchased.ok and model.crafting_balance()==0,"Actual purchase deducts four and creates UID")
	check(not arena.execute_normal_gem_trade(quote.get("handle",""),"support:shock").ok,"Purchase receipt cannot be replayed")
	var group_id:=""
	for group:Dictionary in model.snapshot().skill_groups:
		if model.skill_group(group.id).skill_id=="nova":group_id=group.id
	check(not group_id.is_empty() and model.move_item(purchased.get("uid",""),{"kind":"skill_support","group_id":group_id,"index":0},model.revision(),arena.NORMAL_BUILD_PATH).ok,"Bought same UID equips into actual nova group")
	var cast:Dictionary=model.get_group_cast(group_id)
	check(cast.ok and cast.shock_profile.enabled and cast.shock_profile.roles==["direct"] and cast.snapshot.shock_policy==Rules.PLAYER_POLICY,"Actual compiler freezes the player policy")
	check(Preview.shock_lines(cast).size()==2,"Packed skill preview reads final shock profile")
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Actual arena practice entry starts combat")
	arena.hud.close_panel();arena.enemies.clear();arena.monster_runtime.reset();arena.player_pos=arena.ARENA.get_center();arena.mana=1000.0;arena.auto_fire=false
	var enemy:Dictionary=arena._spawn_monster("brute",arena.player_pos+Vector2(45,0),"ordinary","",[],false);enemy.spawn=0.0;enemy.health=10000.0;enemy.shield=0.0;enemy.armour=0.0;enemy.resistances={};enemy.speed=0.0;enemy.attack_timer=1000.0
	var mana:float=arena.mana
	check(arena.cast_group(group_id) and absf(mana-arena.mana-float(cast.mana))<0.000001,"Actual equipped cast pays compiled mana once")
	var first:Dictionary=arena.damage_trace.back().duplicate(true);var statuses:Array=arena.shock_statuses()
	check(not first.has("shock") and statuses.size()==1 and statuses[0].remaining_seconds==2.0,"Applying hit is ordinary; survivor then receives two-second shock")
	var repeated:Dictionary=cast.snapshot.duplicate(true)
	if first.has("critical"):repeated.critical_roll=first.critical.duplicate(true)
	arena._apply_damage_packet(enemy,cast.packets.direct,repeated,Color.WHITE)
	var second:Dictionary=arena.damage_trace.back()
	check(second.has("shock") and absf(float(second.total)-float(first.total)*1.15)<0.000001,"Subsequent same-instant hit uses exact 15 percent increase")
	var saved:Dictionary=model.snapshot();var bytes:PackedByteArray=FileAccess.get_file_as_bytes(arena.build_save_path);var count:int=model.successful_saves;var rng:int=arena.rng.state
	arena.elapsed=2.0;arena.shock_runtime.prune(arena.elapsed)
	check(arena.shock_statuses().is_empty() and model.successful_saves==count and Same._same_data(saved,model.snapshot()) and bytes==FileAccess.get_file_as_bytes(arena.build_save_path) and arena.rng.state==rng,"Expiry is transient and changes no save, UID, inventory or RNG")
	var loaded:=Model.new();check(loaded.load_build(arena.build_save_path) and Same._same_data(loaded.snapshot(),saved) and loaded.get_group_cast(group_id)==cast,"Equipped schema31 reload preserves exact compiled consumer")
	var report:Dictionary={"ok":failures==0 and rows.size()==21,"checks":rows.size(),"failures":failures,"results":rows,"pck_sha256":sha(FileAccess.get_file_as_bytes(pack)),"font_sha256":sha(font.data),"source_commit":OS.get_environment("V052_SOURCE"),"schema":model.snapshot().version,"first_total":first.total,"second_total":second.total,"remaining_shards":model.crafting_balance(),"runtime":"same-PCK Linux headless; not Windows hardware acceptance"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("Packed v52 shock probe: %d checks, %d failures"%[rows.size(),failures]);arena.queue_free();await process_frame;quit(0 if report.ok else 1)
