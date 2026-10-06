extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const ROUTE := ["47175","31628","9511","23881","26523","6446","10221","50422","50570","29353","63282","31961"]
const POLICY := {"id":"resolute_technique","hits_cannot_be_evaded":true,"cannot_deal_critical_strikes":true}
var arena: Node
var rows: Array[Dictionary]=[]
var failures:=0
var completed:=false
var output:=""
var evidence:Dictionary={}
func _initialize()->void:call_deferred("run")
func sha(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func check(ok:bool,label:String)->bool:
	rows.append({"ok":ok,"label":label})
	if not ok:
		failures+=1;push_error(label);save_report();quit(1)
	return ok
func save_report()->void:
	if output.is_empty():return
	var report:Dictionary={"ok":completed and failures==0,"completed":completed,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V061_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(OS.get_environment("V061_MAIN_PACK"))),"schema":38,"evidence":evidence,"scope":"Linux same-PCK focused keystone/transaction/snapshot checks, not Windows hardware FPS or physical-input acceptance"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
func clean()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.attack_admission_trace.clear();arena.event_counts.clear()
	arena.projectile_runtime=arena.Projectiles.new();arena.monster_runtime=arena.MonsterLifecycle.new()
	arena.burn_runtime.reset();arena.shock_runtime.reset();arena.leech_runtime.clear();arena.group_cooldowns.reset()
	arena._world_mode="normal";arena._geometry.configure("normal",arena.ARENA);arena.alive=true;arena.auto_fire=false;arena.elapsed=0.0;arena._burn_step_active=false
	arena._stats=arena.state.get_stats();arena.mana=float(arena._stats.max_mana);arena.health=float(arena._stats.max_health);arena.player_facing=Vector2.RIGHT
	arena.player_pos=arena.ARENA.get_center();arena.hud._process(0.0);arena.hud.close_panel()
	for id:String in arena.Data.SKILLS:arena.cooldowns[id]=0.0
func target(pos:Vector2)->Dictionary:
	var enemy:Dictionary=arena._spawn_monster("crawler",pos,"ordinary","",[],false)
	if not enemy.has("id"):return {}
	enemy.spawn=0.0;enemy.health=10000.0;enemy.max_health=10000.0;enemy.shield=0.0;enemy.max_shield=0.0
	enemy.armour=0.0;enemy.resistances={};enemy.evasion=1000000000.0;enemy.evasion_entropy=13.25;enemy.radius=1.0;enemy.speed=0.0;enemy.attack_timer=1000.0
	return enemy
func run()->void:
	output=OS.get_environment("V061_PACK_QA")
	var fixture:=OS.get_environment("V061_OLD_SAVE")
	if output.is_empty() or fixture.is_empty() or OS.get_environment("V061_MAIN_PACK").is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v061-"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(30.0).timeout.connect(func():check(false,"Packed keystone probe unexpectedly stalled"))
	var original:=FileAccess.get_file_as_bytes(fixture);var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE);file.store_buffer(original);file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.hud.close_panel()
	var model:RefCounted=arena.state;var expected:Dictionary=JSON.parse_string(original.get_string_from_utf8());expected.version=38
	if not check(str(ProjectSettings.get_setting("application/config/version"))=="0.61.0" and model.snapshot().version==38,"Actual version and schema38"):return
	if not check(FileAccess.get_file_as_bytes(arena.build_save_path+".v37-backup.json")==original,"Frozen v60 serializer37 bytes backed up exactly"):return
	if not check(Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())),JSON.parse_string(JSON.stringify(expected))),"Migration changes only version using equal JSON boundaries"):return
	if not check(model.migration_message.contains("坚决技艺") and str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))=="godot-game-preview-v021","Correct migration explanation and original user directory"):return
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	if not check(sha(font.data)==OS.get_environment("V061_PACK_FONT_SHA256") and font.has_char("括".unicode_at(0)),"Actual new font contains the one added glyph"):return
	if not check(SourceTree.node_effect("31961",0,37).status=="unsupported" and SourceTree.node_effect("31961",0,38).status=="full" and SourceTree.node_effect("63620").status=="unsupported","Only exact keystone block opens at38; conditional source stays closed"):return
	if not check(Localization.ready() and not Localization.display_line("Your hits can't be Evaded\nNever deal Critical Strikes").contains(Localization.NOT_IMPLEMENTED),"Packed Chinese line reads actual source support"):return
	if not check(arena.enter_town_test(arena.world_context().revision).ok,"Actual isolated test-town entry"):return
	if not check(arena.start_map(arena.map_draft().revision).ok,"Actual test-map entry"):return
	model=arena.state
	var gem_uid:String=model.award_gem("skill:cleave")
	if not check(not gem_uid.is_empty() and model.move_item(gem_uid,{"kind":"skill_main","group_id":"group_000009"},model.revision(),arena.build_save_path).ok,"Actual owned cleave gem uses existing skill group"):return
	var candidate:Dictionary=model.snapshot();candidate.progress={"level":7,"xp":0};candidate.talents.class_id=1;candidate.talents.allocated=[ROUTE[0]];candidate.talents.normal_points=11;candidate.revision+=1
	if not check(model.Rules.reason(candidate).is_empty() and model._commit(candidate,arena.build_save_path).ok,"Lawful seven-level eleven-point fixture"):return
	var old_cast:Dictionary={}
	for id:String in ROUTE.slice(1):
		if id=="31961":old_cast=model.get_skill_cast("cleave")
		if not model.available_passives().has(id) or not model.allocate_passive(id,0,model.revision(),arena.build_save_path).ok:
			check(false,"Connected source allocation failed: "+id);return
	if not check(model.talent_points==0 and model.get_stats().resolute_technique==1.0 and old_cast.get("ok",false) and not old_cast.has("hit_policy"),"Eleven real transactions enable the indivisible policy"):return
	var cast:Dictionary=model.get_skill_cast("cleave")
	if not check(cast.get("ok",false) and cast.get("hit_policy",{})==POLICY and cast.critical.primary.chance==0.0,"Real compiled melee policy and zero critical chance"):return
	var old_bytes:=var_to_bytes(old_cast);clean();var enemy:=target(arena.player_pos+Vector2(40,0))
	if not check(not enemy.is_empty() and arena._execute_compiled(cast),"Actual high-evasion cleave starts"):return
	if not check(arena.damage_trace.size()==1 and arena.attack_admission_trace.size()==1 and arena.attack_admission_trace[0].chance==1.0 and enemy.evasion_entropy==13.25,"Actual hit records certainty without advancing evasion entropy"):return
	if not check(not arena.damage_trace[0].get("critical",{}).get("critical",false) and arena.critical_runtime.draws==0,"Enabled melee neither critically hits nor consumes a private draw"):return
	if not check(var_to_bytes(old_cast)==old_bytes and not old_cast.snapshot.has("resolute_technique"),"Previously compiled inactive snapshot is unchanged"):return
	var charm:=""
	for uid:String in model.snapshot().items:
		if model.item(uid).definition_id=="equipment:detonation_charm":charm=uid;break
	if not check(not charm.is_empty() and model.move_item(charm,{"kind":"equipment","slot_id":"amulet"},model.revision(),arena.build_save_path).ok,"Actual owned explosion charm equips through model"):return
	cast=model.get_skill_cast("tornado")
	if not check(cast.get("ok",false) and cast.get("hit_policy",{})==POLICY and cast.critical.has("secondary") and cast.critical.primary.chance==0.0 and cast.critical.secondary.chance==0.0,"Actual equipped tornado zeros both primary and independent secondary"):return
	clean()
	if not check(arena._execute_compiled(cast) and not arena.projectiles.is_empty(),"Actual enabled tornado creates real frozen shots"):return
	var original_snapshots:Array=[]
	for shot:Dictionary in arena.projectiles:original_snapshots.append(var_to_bytes(shot.snapshot))
	if not check(model.refund_passive("31961",model.revision(),arena.build_save_path).ok,"Actual refund affects future casts"):return
	var untouched:=true
	for shot:Dictionary in arena.projectiles:untouched=untouched and original_snapshots.has(var_to_bytes(shot.snapshot))
	if not check(untouched and not model.get_basic_cast().has("hit_policy") and model.get_basic_cast().critical.primary.chance>0.0,"Old shots retain policy while new casts regain ordinary critical chance"):return
	clean();var origin:Vector2=arena.player_pos+Vector2(200,0)
	var one:=target(origin+Vector2(0,25));var two:=target(origin+Vector2(0,-25))
	if not check(not one.is_empty() and not two.is_empty(),"Two real eligible secondary targets are prepared"):return
	var frozen:Dictionary=arena.critical_runtime.freeze(cast.snapshot)
	if not check(frozen.get("ok",false),"Old enabled compiled snapshot remains valid after refund"):return
	var checkpoint:Dictionary=arena.critical_runtime.checkpoint()
	var carrier:Dictionary=arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,{"speed":10.0,"range":500.0,"lifetime":0.01,"pierce":-1,"radius":1.0},cast.packets.parent,frozen.snapshot,arena.projectile_runtime.new_cast(),Color.WHITE)
	arena.projectiles.append(carrier);arena._update_projectiles(0.02)
	if not check(int(arena.event_counts.get("explosion",0))==1 and arena.damage_trace.size()==2,"Natural expiry of controlled carrier invokes real two-target secondary"):return
	var no_crit:=true
	for hit:Dictionary in arena.damage_trace:no_crit=no_crit and hit.tags.has("secondary") and not hit.get("critical",{}).get("critical",false)
	if not check(no_crit and arena.critical_runtime.checkpoint()==checkpoint and arena.attack_admission_trace.is_empty(),"Frozen independent explosion remains noncritical and invents no attack admission"):return
	if not check(model.allocate_passive("31961",0,model.revision(),arena.build_save_path).ok,"Refunded real point can reallocate without duplication"):return
	var loaded:=Model.new()
	if not check(loaded.load_build(arena.build_save_path) and Same._same_data(loaded.snapshot(),model.snapshot()) and loaded.get_stats().resolute_technique==1.0,"Reallocated source and original inventory persist through reload"):return
	evidence={"font_sha256":sha(font.data),"allocated_points":11,"secondary_hits":arena.damage_trace.duplicate(true),"controlled_carrier":true,"charm_retained":true}
	completed=true;save_report();print("Packed v61 keystone probe: %d checks, %d failures"%[rows.size(),failures]);arena.queue_free();await process_frame;quit(0)
