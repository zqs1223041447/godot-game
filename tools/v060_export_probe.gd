extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const SIX := ["rootwell","deepwell","lanternveil","emberward","rimeward","stormward"]
var rows: Array[Dictionary] = []
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	rows.append({"ok":ok,"label":label})
	if not ok: failures+=1;push_error(label)
func sha(bytes: PackedByteArray) -> String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func near(a:float,b:float)->bool:return absf(a-b)<=maxf(1e-8,absf(b)*1e-10)
func full_vest(uid:String)->Dictionary:
	var affixes:Array=[]
	for id:String in SIX:affixes.append({"id":id,"tier":3,"value":int(Gear.affix_definition(id).tiers[2].max)})
	return {"id":uid,"base_id":"emberhide_vest","rarity":"rare","item_level":16,"affixes":affixes}
func run()->void:
	var output:=OS.get_environment("V060_PACK_QA");var pack:=OS.get_environment("V060_MAIN_PACK");var fixture:=OS.get_environment("V060_OLD_SAVE")
	if output.is_empty() or pack.is_empty() or fixture.is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v060-"):quit(78);return
	create_timer(35.0).timeout.connect(func():push_error("Packed defense-affix probe timed out");quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_bytes(fixture);var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE);file.store_buffer(original);file.close()
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.hud.close_panel()
	var model:RefCounted=arena.state;var expected:Dictionary=JSON.parse_string(original.get_string_from_utf8());expected.version=37
	check(str(ProjectSettings.get_setting("application/config/version"))=="0.60.0" and model.snapshot().version==37,"Actual version and schema37")
	check(FileAccess.get_file_as_bytes(arena.build_save_path+".v36-backup.json")==original,"Old36 backed up as exact original bytes")
	check(Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())),JSON.parse_string(JSON.stringify(expected))),"Migration changes only version across equal JSON boundaries")
	check(model.migration_message.contains("灰烬皮甲") and model.migration_message.contains("旧装备保持原值"),"Correct no-reroll migration explanation")
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))=="godot-game-preview-v021" and model.bag_layout()=={"pages":2,"columns":12,"rows":10},"Existing save path and240slots")
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	check(sha(font.data)==OS.get_environment("V060_PACK_FONT_SHA256") and font.has_char("寒".unicode_at(0)),"Original font covers new suffix wording")
	check(Gear.CURRENT_VOCABULARY==37 and Gear.CANONICAL_LOOT_PROFILE_ID=="canonical_v37" and SourceTree.CURRENT_SAVE_VERSION==36,"Equipment vocabulary advances while passive execution stays36")
	var white:Dictionary=Gear.definition({"id":"gear_000601","base_id":"emberhide_vest","rarity":"normal","item_level":30,"affixes":[]})
	check(near(white.stats.fire_resistance,0.15) and not white.stats.has("cold_resistance") and not white.stats.has("lightning_resistance"),"White test supply still grants no cold/lightning suffix")
	var uid:="gear_%06d"%int(model.snapshot().next_item_serial);var vest:=full_vest(uid)
	check(Gear.validate_instance(vest) and vest.affixes.size()==6 and not Gear.validate_instance_for_version(vest,36),"Legal six-affix current item cannot enter old vocabulary")
	check(model._admit_reward_item(Items.wrap_equipment(vest)) and model.save_build(arena.build_save_path)==OK,"Actual full legal UID enters bag and persists")
	check(Gear.affix_display(vest.affixes[4]).line=="冰霜抗性 +25%" and Gear.affix_display(vest.affixes[5]).line=="闪电抗性 +25%","Shared percent formatter preserves exact new labels")
	check(model.move_item(uid,{"kind":"equipment","slot_id":"body_armour"},model.revision(),arena.build_save_path).ok,"Actual single body-slot equipment transaction")
	var profile:Dictionary=model.get_resistance_profile()
	check(near(profile.raw_resistances.fire,0.4) and near(profile.raw_resistances.cold,0.25) and near(profile.raw_resistances.lightning,0.25) and near(profile.maximum_resistances.cold,0.75),"Real equipped ticks divide100 once and do not raise maximum resistance")
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Actual practice scene consumes current equipment")
	arena.enemies.clear();arena.projectiles.clear();arena.burn_runtime.reset();arena.shock_runtime.reset()
	for element:String in ["cold","lightning"]:
		arena.health=1000.0;arena.shield=0.0;arena.invulnerable=0.0
		check(arena.hit_player_components({element:100.0}) and near(arena.health,925.0),"Actual100 "+element+" hit loses75health")
	check(model.get_resistance_profile().maximum_resistances=={"fire":0.75,"cold":0.75,"lightning":0.75},"New raw suffixes grant no maximum cap")
	check(model.move_item(uid,model.first_bag_position(uid),model.revision(),arena.build_save_path).ok and near(arena._stats.cold_resistance,0.0) and near(arena._stats.lightning_resistance,0.0),"Unequip removes only that item's cold/lightning")
	check(model.move_item(uid,{"kind":"equipment","slot_id":"body_armour"},model.revision(),arena.build_save_path).ok and model.item(uid).payload==vest,"Reequip preserves UID and original affix payload")
	var returned:Dictionary=model.move_item(uid,model.first_bag_position(uid),model.revision(),arena.build_save_path)
	check(returned.ok and model._admit_reward_item(Items.calibration_shard("item_%06d"%int(model.snapshot().next_item_serial),200)) and model.save_build(arena.build_save_path)==OK,"Move equipment back to bag and admit the real material stack")
	var before:=var_to_bytes(model.snapshot());var disk:=FileAccess.get_file_as_bytes(arena.build_save_path)
	var quoted:Dictionary=model.crafting_quote("recalibrate",uid,arena.build_save_path)
	if quoted.ok:model.cancel_crafting_quote(quoted.handle)
	check(quoted.ok and quoted.cost=={"calibration_shard":42} and before==var_to_bytes(model.snapshot()) and disk==FileAccess.get_file_as_bytes(arena.build_save_path),"Quote cancellation preserves complete build and disk")
	quoted=model.crafting_quote("recalibrate",uid,arena.build_save_path)
	var executed:Dictionary=model.execute_crafting(quoted.handle,quoted.source_instance) if quoted.ok else {}
	var after:Dictionary=model.item(uid).payload;var identities:Array=[]
	for affix:Dictionary in after.affixes:identities.append([affix.id,affix.tier])
	check(executed.get("ok",false) and model.crafting_balance()==158 and identities==SIX.map(func(id:String)->Array:return [id,3]),"Real calibration costs42 and retains all six family/tier identities")
	before=var_to_bytes(model.snapshot());disk=FileAccess.get_file_as_bytes(arena.build_save_path)
	check(not model.execute_crafting(str(quoted.get("handle","")),quoted.get("source_instance",{})).ok and before==var_to_bytes(model.snapshot()) and disk==FileAccess.get_file_as_bytes(arena.build_save_path),"Consumed quote cannot charge or reroll again")
	arena.wave=9;arena.reward_kills=0;arena.kills=0;arena.enemies.clear();arena.monster_runtime=arena.MonsterLifecycle.new()
	var enemy:Dictionary=arena._spawn_monster("ember_guard",arena.player_pos+Vector2(160,0),"ordinary","",[],true)
	check(enemy.rarity=="rare" and enemy.equipment_pool=="defense" and enemy.reward_eligible,"Original ember guard retains rare-root reward eligibility")
	var drop_uid:="gear_%06d"%int(model.snapshot().next_item_serial);arena.rng.seed=2;enemy.health=0.0;arena._finish_enemy_death(enemy,false)
	var dropped:Dictionary=model.item(drop_uid)
	check(not dropped.is_empty() and dropped.payload.affixes.any(func(a:Dictionary)->bool:return a.id=="rimeward") and dropped.payload.affixes.any(func(a:Dictionary)->bool:return a.id=="stormward") and arena.reward_kills==1,"Actual root death maps logical defense into new dual-resistance drop")
	before=var_to_bytes([model.snapshot(),arena.rng.state,arena.reward_kills]);arena._finish_enemy_death(enemy,false)
	check(before==var_to_bytes([model.snapshot(),arena.rng.state,arena.reward_kills]),"Repeated death cannot duplicate item or consume reward RNG")
	check(arena.save_build(),"Real reward state saves once through existing main path")
	var loaded:=Model.new()
	check(loaded.load_build(arena.build_save_path) and Same._same_data(loaded.snapshot(),model.snapshot()),"New affix items, locations and shards survive reload")
	var legacy_rng:=RandomNumberGenerator.new();legacy_rng.seed=60031
	var legacy:Dictionary=Gear.generate_for_pool(legacy_rng,"gear_000999",16,"rare","defense")
	check(not legacy.affixes.any(func(a:Dictionary)->bool:return a.id in ["rimeward","stormward"]) and not Gear.validate_instance_for_version(legacy,35) and not Gear.validate_instance_for_version(legacy,36),"Historical explicit pool and35/36 equipment rejection remain frozen")
	var report:Dictionary={"ok":failures==0 and rows.size()==29,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V060_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(pack)),"font_sha256":sha(font.data),"schema":37,"source_policy":36,"full_vest":vest,"initial_profile":profile,"calibrated_vest":after,"natural_drop":dropped,"scope":"Linux same-PCK equipment supply and transaction check, not Windows hardware FPS or physical-input acceptance"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("Packed v60 defense-affix probe: %d checks, %d failures"%[rows.size(),failures]);arena.queue_free();await process_frame;quit(0 if report.ok else 1)
