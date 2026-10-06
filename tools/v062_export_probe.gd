extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Items=preload("res://scripts/items/unified_item_catalog.gd")
const Same=preload("res://scripts/items/crafting_transaction_planner.gd")
const Source=preload("res://scripts/passives/source_tree_runtime.gd")
const Hit=preload("res://scripts/combat/attack_hit_rules.gd")
const SIX=["ironhide","mistweave","rootwell","emberward","rimeward","stormward"]
var arena:Node
var output:=""
var rows:Array[Dictionary]=[]
var failures:=0
var completed:=false
var evidence:Dictionary={}
func _initialize()->void:call_deferred("run")
func sha(b:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(b);return h.finish().hex_encode()
func near(a:float,b:float)->bool:return is_finite(a) and absf(a-b)<=maxf(1e-8,absf(b)*1e-9)
func save_report()->void:
	if output.is_empty():return
	var result:Dictionary={"ok":completed and failures==0,"completed":completed,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V062_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(OS.get_environment("V062_MAIN_PACK"))),"schema":39,"source_policy":38,"evidence":evidence,"scope":"Linux same-PCK focused acquisition/equipment/attack/craft check; no Windows hardware or physical UI claims"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
func check(ok:bool,label:String)->bool:
	rows.append({"ok":ok,"label":label})
	if not ok:failures+=1;push_error(label);save_report();quit(1)
	return ok
func accept(result:Dictionary,label:String)->bool:return check(result.get("ok",false),label+": "+str(result.get("reason","")))
func prepare_recovery(model:RefCounted,path:String)->bool:
	# Shared verified preparation order: recover owned items, then acquire, then equip.
	for uid:String in model.pending_items():
		var destination:Dictionary=model.first_bag_position(uid)
		if destination.is_empty():return check(false,"Original recovery UID has no lawful bag space")
		var moved:Dictionary=model.move_item(uid,destination,model.revision(),path)
		if not moved.get("ok",false):return check(false,"Recovery-to-bag transaction failed: "+str(moved.get("reason","")))
	return check(model.pending_items().is_empty(),"Original recovery items move through real transactions before acquisition")
func full_vest(uid:String)->Dictionary:
	var affixes:Array=[]
	for id:String in SIX:affixes.append({"id":id,"tier":3,"value":int(Gear.affix_definition(id).tiers[2].max)})
	return {"id":uid,"base_id":"emberhide_vest","rarity":"rare","item_level":16,"affixes":affixes}
func reset_resources()->void:
	arena.alive=true;arena.health=1000.0;arena.shield=0.0;arena.mana=float(arena._stats.max_mana);arena.invulnerable=0.0
	arena.incoming_damage_trace.clear();arena.attack_admission_trace.clear();arena._player_evasion_entropy=0.0
	arena._burn_immunity_until=0.0;arena._burn_incoming_time=-1.0;arena.burn_runtime.reset();arena.shock_runtime.reset();arena.elapsed=0.0
func run()->void:
	output=OS.get_environment("V062_PACK_QA")
	var fixture:=OS.get_environment("V062_OLD_SAVE")
	if output.is_empty() or fixture.is_empty() or OS.get_environment("V062_MAIN_PACK").is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v062-"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(30.0).timeout.connect(func():check(false,"Packed rating probe stalled"))
	var original:=FileAccess.get_file_as_bytes(fixture);var f:=FileAccess.open("user://build_save.json",FileAccess.WRITE);f.store_buffer(original);f.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.hud.close_panel()
	var model:RefCounted=arena.state
	if not check(str(ProjectSettings.get_setting("application/config/version"))=="0.62.0" and model.snapshot().version==39,"Actual version0.62 and schema39"):return
	if not check(FileAccess.get_file_as_bytes(arena.build_save_path+".v38-backup.json")==original,"Exact original38 bytes backed up"):return
	var expected:Dictionary=JSON.parse_string(original.get_string_from_utf8());expected.version=39
	if not check(Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())),JSON.parse_string(JSON.stringify(expected))),"Migration changes only schema through equal JSON boundaries"):return
	if not check(model.get_stats().resolute_technique==1.0 and Source.CURRENT_SAVE_VERSION==38,"Old allocated keystone and entire source execution policy remain38"):return
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	if not check(sha(font.data)==OS.get_environment("V062_PACK_FONT_SHA256") and font.has_char("雾".unicode_at(0)) and font.has_char("革".unicode_at(0)),"Actual packaged font covers both new family names"):return
	if not check(Gear.CURRENT_VOCABULARY==39 and Gear.CURRENT_DEFENSE_POOL_ID=="defense_v39" and Gear.CANONICAL_LOOT_PROFILE_ID=="canonical_v39","Current equipment and supply IDs are39"):return
	if not prepare_recovery(model,arena.build_save_path):return
	var uid:="gear_%06d"%int(model.snapshot().next_item_serial);var vest:=full_vest(uid)
	if not check(Gear.validate_instance(vest) and not Gear.validate_instance_for_version(vest,37) and not Gear.validate_instance_for_version(vest,38),"New legal six-affix vest rejects historical vocabularies"):return
	if not check(model._admit_reward_item(Items.wrap_equipment(vest)) and model.save_build(arena.build_save_path)==OK,"Owned selected UID enters bag and persists"):return
	if not check(Gear.affix_display(vest.affixes[0]).line=="护甲 +120" and Gear.affix_display(vest.affixes[1]).line=="闪避值 +450","Shared formatter uses flat point units"):return
	var before_stats:Dictionary=model.get_stats()
	if not accept(model.move_item(uid,{"kind":"equipment","slot_id":"body_armour"},model.revision(),arena.build_save_path),"Actual body-slot equip"):return
	var stats:Dictionary=model.get_stats()
	if not check(near(stats.armour-before_stats.armour,120.0*(1.0+stats.armour_increased)) and near(stats.evasion-before_stats.evasion,450.0*(1.0+stats.evasion_increased+floorf(stats.dexterity/5.0)*0.01)),"Equipped flat ratings receive existing global increases exactly once"):return
	if not accept(arena.leave_normal_town(arena.world_context().revision),"Actual practice entry"):return
	arena.enemies.clear();arena.projectiles.clear();reset_resources()
	if not check(arena.hit_player_components({"physical":40.0},0,["hit","spell"]) and near(arena.incoming_damage_trace.back().damage_total,40.0*(1.0-minf(0.9,stats.armour/(stats.armour+200.0)))),"Actual nonattack physical hit uses armour but no evasion"):return
	reset_resources()
	if not check(arena.hit_player_components({"cold":40.0},0,["hit","spell"]) and near(arena.incoming_damage_trace.back().damage_total,30.0) and arena.attack_admission_trace.is_empty(),"Nonattack elemental hit retains only original25percent resistance"):return
	reset_resources();var hits:=0;var entropy_expected:=Hit.chance(100.0,stats.evasion)
	for index:int in range(100):
		arena.health=1000.0;arena.invulnerable=0.0
		if arena.hit_player_components({"lightning":40.0},0,["hit","attack"]):hits+=1
	if not check(hits==int(round(entropy_expected*100.0)) and hits<100 and near(arena._player_evasion_entropy,0.0),"One hundred actual elemental attacks follow real evasion entropy"):return
	reset_resources()
	if not accept(arena.burn_runtime.apply("player",0,71,20.0,3.0,0.0),"Attach existing burn"):return
	arena.elapsed=1.0;arena._advance_player_burn(1.0)
	if not check(not arena.burn_trace.is_empty() and near(arena.burn_trace.back().settlement.damage_total,12.0) and arena.attack_admission_trace.is_empty(),"Burn keeps existing40percent fire resistance without armour/evasion"):return
	if not accept(model.move_item(uid,model.first_bag_position(uid),model.revision(),arena.build_save_path),"Return selected gear to bag before craft"):return
	if not check(model._admit_reward_item(Items.calibration_shard("item_%06d"%int(model.snapshot().next_item_serial),200)) and model.save_build(arena.build_save_path)==OK,"Admit real shard material stack"):return
	var before:=var_to_bytes(model.snapshot());var disk:=FileAccess.get_file_as_bytes(arena.build_save_path)
	var quote:Dictionary=model.crafting_quote("recalibrate",uid,arena.build_save_path)
	if not accept(quote,"Actual selected UID quote"):return
	model.cancel_crafting_quote(quote.handle)
	if not check(before==var_to_bytes(model.snapshot()) and disk==FileAccess.get_file_as_bytes(arena.build_save_path) and quote.cost=={"calibration_shard":42},"Cancel preserves build/disk and current six-affix cost42"):return
	quote=model.crafting_quote("recalibrate",uid,arena.build_save_path)
	if not accept(quote,"Fresh real quote after cancel"):return
	if not accept(model.execute_crafting(quote.handle,quote.source_instance),"Actual craft commits atomically"):return
	var identities:Array=[]
	for a:Dictionary in model.item(uid).payload.affixes:identities.append([a.id,a.tier])
	if not check(model.crafting_balance()==158 and identities==SIX.map(func(id:String)->Array:return [id,3]),"Calibration pays42 and preserves new families and tiers"):return
	before=var_to_bytes(model.snapshot());disk=FileAccess.get_file_as_bytes(arena.build_save_path)
	if not check(not model.execute_crafting(quote.handle,quote.source_instance).ok and before==var_to_bytes(model.snapshot()) and disk==FileAccess.get_file_as_bytes(arena.build_save_path),"Consumed handle cannot charge twice"):return
	var loaded:=Model.new()
	if not check(loaded.load_build(arena.build_save_path) and Same._same_data(loaded.snapshot(),model.snapshot()),"Actual new affix and material state reloads exactly"):return
	evidence={"font_sha256":sha(font.data),"item":vest,"equipped_stats":stats,"actual_attack_hits":hits,"actual_attack_chance":entropy_expected,"calibrated":model.item(uid).payload}
	completed=true;save_report();print("Packed v62 rating probe: %d checks, %d failures"%[rows.size(),failures]);arena.queue_free();await process_frame;quit(0)
