extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const ROUTE := ["57264","37569","36542","4397","31875","60398","34098"]
var rows: Array[Dictionary] = []
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	rows.append({"ok":ok,"label":label})
	if not ok: failures+=1;push_error(label)
func sha(bytes: PackedByteArray) -> String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func near(a: float,b: float) -> bool:return absf(a-b)<=maxf(1e-8,absf(b)*1e-10)
func run() -> void:
	var output:=OS.get_environment("V058_PACK_QA");var pack:=OS.get_environment("V058_MAIN_PACK");var fixture:=OS.get_environment("V058_OLD_SAVE")
	if output.is_empty() or pack.is_empty() or fixture.is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v058-"):quit(78);return
	create_timer(30.0).timeout.connect(func():push_error("Packed mana-guard probe did not finish");quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_bytes(fixture);var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE);file.store_buffer(original);file.close()
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.hud.close_panel()
	var model:RefCounted=arena.state;var old:Dictionary=JSON.parse_string(original.get_string_from_utf8());var expected:=old.duplicate(true);expected.version=35
	check(str(ProjectSettings.get_setting("application/config/version"))=="0.58.0" and model.snapshot().version==35,"Actual version and migrated schema35")
	check(FileAccess.get_file_as_bytes(arena.build_save_path+".v34-backup.json")==original,"Published34 input is backed up as exact original bytes")
	check(Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())),expected),"Migration changes only version, with no items or points granted")
	check(model.migration_message.contains("魔力") and not model.migration_message.contains("两瓶药剂"),"Correct schema34 migration explanation")
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))=="godot-game-preview-v021" and model.bag_layout()=={"pages":2,"columns":12,"rows":10},"Existing userdata directory and240slots")
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	check(sha(font.data)==OS.get_environment("V058_PACK_FONT_SHA256") and font.has_char("担".unicode_at(0)),"Same previously expanded font is used by new resource wording")
	check(Localization.ready() and Localization.node_name("34098")=="心灵升华" and not Localization.display_line("40% of Damage is taken from Mana before Life").contains(Localization.NOT_IMPLEMENTED),"Packed Chinese name and newly implemented line agree")
	check(SourceTree.node_effect("34098",0,34).status=="unsupported" and SourceTree.node_effect("34098",0,35).status=="full","Old vocabulary rejects the newly enabled source node")
	check(SourceTree.node_effect("42144").status=="partial" and SourceTree.node_effect("922").status=="partial","Other mixed source definitions stay partial")
	check(not model.get_mana_guard_profile().enabled,"No allocation gives no free mana protection")
	check(model.add_xp(48) and model.save_build(arena.build_save_path)==OK and model.talent_points==7 and model.select_class(3,model.revision(),arena.build_save_path).ok,"Existing level/class transactions prepare lawful seven-point fixture")
	var allocated:=true
	for id:String in ROUTE:allocated=bool(model.allocate_passive(id,0,model.revision(),arena.build_save_path).ok) and allocated
	check(allocated and model.talent_points==0 and near(model.get_mana_guard_profile().fraction,0.4),"Actual seven source allocations enable40percent profile")
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Actual normal-practice entry uses the allocated build")
	arena.enemies.clear();arena.projectiles.clear();arena.health=float(arena.get_stats().max_health);arena.shield=0.0;arena.mana=100.0;arena.invulnerable=0.0
	var life:float=arena.health;var rng_state:int=arena.rng.state;var saves:int=model.successful_saves
	check(arena.hit_player_components({"chaos":100.0}) and near(arena.mana,60.0) and near(arena.health,life-60.0),"Actual unmitigated hit spends40mana and60life")
	var hit:Dictionary=arena.incoming_damage_trace.back();arena.feedback_runtime.flush_target("player",0);var feedback:Array=arena.damage_feedback()
	check(near(hit.mana_spent,40.0) and near(hit.health_lost,60.0) and not feedback.is_empty() and near(feedback.back().amount,60.0),"Mana spending remains separate from life loss and displayed loss")
	arena.invulnerable=0.0;arena.shield=25.0;arena.mana=100.0;arena.health=life
	check(arena.hit_player_components({"chaos":100.0}) and near(arena.shield,0.0) and near(arena.mana,70.0) and near(arena.health,life-45.0),"Real shield absorption precedes the mana share")
	arena.invulnerable=0.0;arena.shield=0.0;arena.mana=10.0;arena.health=life
	check(arena.hit_player_components({"chaos":100.0}) and arena.mana==0.0 and near(arena.health,life-90.0),"Actual insufficient mana routes the shortfall to life")
	var state_before:=var_to_bytes([arena.mana,arena.health,arena.shield,arena.group_cooldowns.snapshot(),arena.cooldowns,arena.projectiles,arena.critical_runtime.checkpoint()])
	check(not arena.cast_skill(0) and var_to_bytes([arena.mana,arena.health,arena.shield,arena.group_cooldowns.snapshot(),arena.cooldowns,arena.projectiles,arena.critical_runtime.checkpoint()])==state_before,"Zero mana skill rejection spends no resources/cooldown/RNG")
	arena.burn_runtime.reset();arena.shock_runtime.reset();arena.invulnerable=0.0;arena._burn_immunity_until=0.0;arena._burn_step_active=false;arena.elapsed=0.0;arena._stats.fire_resistance=0.0;arena.shield=0.0;arena.mana=100.0;arena.health=life
	var burning:Dictionary=arena.burn_runtime.apply("player",0,999,100.0,1.0,0.0,{"skill_id":"packed_burn"});arena._advance_player_burn(1.0)
	check(burning.ok and near(arena.mana,60.0) and near(arena.health,life-60.0),"Actual burn uses the same mana-before-life settlement")
	check(arena.rng.state==rng_state and model.successful_saves==saves,"Incoming defense causes no extra reward RNG or persistence writes")
	check(model.refund_passive("34098",model.revision(),arena.build_save_path).ok and not model.get_mana_guard_profile().enabled,"Actual refund disables future mana protection")
	var plain:=Defense.incoming_source_hit({"chaos":100.0},model.get_stats(),0.0,life,"player")
	check(not plain.has("mana_spent") and near(plain.health_lost,100.0),"Disabled profile keeps original settlement shape")
	check(model.allocate_passive("34098",0,model.revision(),arena.build_save_path).ok,"Existing point can be reallocated without duplication")
	var loaded:=Model.new();check(loaded.load_build(arena.build_save_path) and Same._same_data(loaded.snapshot(),model.snapshot()) and near(loaded.get_mana_guard_profile().fraction,0.4),"Schema35 source selection reloads without saving active mana state")
	check(not model.snapshot().has("mana_spent") and not model.snapshot().has("mana"),"Transient resource spending is absent from persistent build")
	var report:Dictionary={"ok":failures==0 and rows.size()==25,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V058_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(pack)),"font_sha256":sha(font.data),"schema":35,"source_node":"34098","fraction":model.get_mana_guard_profile().fraction,"actual_hit":hit,"scope":"Linux same-PCK focused new resource guard, not Windows hardware FPS or physical-input acceptance"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("Packed v58 mana-guard probe: %d checks, %d failures"%[rows.size(),failures]);arena.queue_free();await process_frame;quit(0 if report.ok else 1)
