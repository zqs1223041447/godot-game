extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
var rows: Array[Dictionary] = []
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	rows.append({"ok":ok,"label":label})
	if not ok: failures += 1; push_error(label)
func sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(bytes); return h.finish().hex_encode()
func near(a: float, b: float) -> bool: return absf(a-b) <= maxf(1e-8,absf(b)*1e-10)
func run() -> void:
	var output := OS.get_environment("V059_PACK_QA")
	var pack := OS.get_environment("V059_MAIN_PACK")
	var fixture := OS.get_environment("V059_OLD_SAVE")
	var witness_path := OS.get_environment("V059_ALLOCATION_WITNESS")
	if output.is_empty() or pack.is_empty() or fixture.is_empty() or witness_path.is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v059-"):
		quit(78); return
	create_timer(35.0).timeout.connect(func(): push_error("Packed resistance-cap probe did not finish"); quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	var original := FileAccess.get_file_as_bytes(fixture)
	var file := FileAccess.open("user://build_save.json",FileAccess.WRITE); file.store_buffer(original); file.close()
	var arena: Node = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire=false; arena.hud.close_panel()
	var model: RefCounted = arena.state
	var expected: Dictionary = JSON.parse_string(original.get_string_from_utf8()); expected.version=36
	check(str(ProjectSettings.get_setting("application/config/version"))=="0.59.0" and model.snapshot().version==36,"Actual version and schema36")
	check(FileAccess.get_file_as_bytes(arena.build_save_path+".v35-backup.json")==original,"Old35 backup retains exact original bytes")
	check(Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())),JSON.parse_string(JSON.stringify(expected))),"Migration changes only version across the same JSON boundary")
	check(model.migration_message.contains("83%") and not model.migration_message.contains("两瓶药剂"),"Current migration explains cap budget without extra gifts")
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))=="godot-game-preview-v021" and model.bag_layout()=={"pages":2,"columns":12,"rows":10},"Existing save directory and240slots")
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile; font.allow_system_fallback=false
	check(sha(font.data)==OS.get_environment("V059_PACK_FONT_SHA256") and font.has_char("限".unicode_at(0)),"Verified font bytes cover cap wording")
	check(Localization.ready() and not Localization.display_line("+2% to all maximum Elemental Resistances").contains(Localization.NOT_IMPLEMENTED),"Packed Chinese mapping sees the real maximum-resistance consumer")
	check(SourceTree.node_effect("25989",0,35).status=="unsupported" and SourceTree.node_effect("25989",0,36).status=="full","Old35 cannot inject newly complete source node")
	check(SourceTree.node_effect("11820").status=="partial" and SourceTree.node_effect("20832").status=="partial","Mixed unsupported clauses keep full allocation blocked")
	var default_profile: Dictionary=model.get_resistance_profile()
	check(default_profile.maximum_resistances=={"fire":0.75,"cold":0.75,"lightning":0.75},"Old build gains no free maximum resistance")
	var witness: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(witness_path))
	var candidate: Dictionary=model.snapshot()
	candidate.progress={"level":int(witness.level),"xp":0}; candidate.talents.class_id=int(witness.class_id)
	candidate.talents.allocated=[str(witness.allocated[0])]; candidate.talents.masteries={}; candidate.talents.normal_points=int(witness.spent); candidate.revision+=1
	check(model.Rules.reason(candidate).is_empty() and model._commit(candidate,arena.build_save_path).ok,"Lawful level69 fixture supplies73 earned-point budget")
	var allocated := true
	for id: Variant in witness.allocated.slice(1): allocated=bool(model.allocate_passive(str(id),0,model.revision(),arena.build_save_path).ok) and allocated
	var profile: Dictionary=model.get_resistance_profile()
	check(allocated and model.talent_points==0 and model.snapshot().talents.allocated.size()==74,"Actual73 allocation transactions retain unique source ownership")
	check(near(profile.raw_resistances.fire,0.91) and near(profile.raw_resistances.cold,0.83) and near(profile.raw_resistances.lightning,0.83),"Real source path supplies raw91/83/83")
	check(profile.maximum_resistances=={"fire":0.83,"cold":0.83,"lightning":0.83} and profile.effective_resistances==profile.maximum_resistances,"Three effective resistances reach this game's83 safety cap")
	var readonly := var_to_bytes([model.snapshot(),model.successful_saves,arena.rng.state]); profile.effective_resistances.fire=0.0
	check(near(model.get_resistance_profile().effective_resistances.fire,0.83) and readonly==var_to_bytes([model.snapshot(),model.successful_saves,arena.rng.state]),"Profile is detached and reads cause no model/save/RNG changes")
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Actual practice entry consumes current allocated defense")
	arena.enemies.clear(); arena.projectiles.clear(); arena.shield=0.0; arena._stats.damage_taken_from_mana_before_life=0.0
	var rng_state: int=arena.rng.state; var saves: int=model.successful_saves; var hits: Array=[]
	for element: String in ["fire","cold","lightning"]:
		arena.health=500.0; arena.invulnerable=0.0
		var hit_ok: bool=arena.hit_player_components({element:100.0})
		check(hit_ok and near(arena.health,483.0),"Actual100 "+element+" hit loses17life")
		if hit_ok: hits.append(arena.incoming_damage_trace.back().duplicate(true))
	arena._stats.fire_resistance=0.4; arena.health=500.0; arena.invulnerable=0.0
	check(arena.hit_player_components({"fire":100.0}) and near(arena.health,440.0),"Raw40 remains40 effective even when the cap is83")
	arena._stats.fire_resistance=0.91; arena._stats.damage_taken_from_mana_before_life=0.4
	arena.shield=5.0; arena.mana=100.0; arena.health=500.0; arena.invulnerable=0.0
	check(arena.hit_player_components({"fire":100.0}) and arena.shield==0.0 and near(arena.mana,95.2) and near(arena.health,492.8),"Capped hit then pays shield5, mana4.8 and life7.2")
	arena._stats.damage_taken_from_mana_before_life=0.0; arena.shield=0.0; arena.health=500.0; arena.invulnerable=0.0
	arena._burn_immunity_until=0.0; arena._burn_step_active=false; arena.elapsed=0.0; arena.burn_runtime.reset(); arena.shock_runtime.reset()
	var burning: Dictionary=arena.burn_runtime.apply("player",0,999,100.0,1.0,0.0,{"skill_id":"packed_cap_burn"})
	var statuses: Array=arena.burn_statuses()
	check(burning.ok and statuses.size()==1 and near(statuses[0].effective_dps,17.0),"Burn status effectiveDPS shares current cap")
	arena._advance_player_burn(1.0)
	check(near(arena.health,483.0) and near(arena.burn_trace.back().settlement.damage_total,17.0),"Actual full burn segment settles the same17damage")
	check(arena.rng.state==rng_state and model.successful_saves==saves,"Incoming cap settlement adds no loot randomness or persistence writes")
	var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and Same._same_data(loaded.snapshot(),model.snapshot()) and loaded.get_resistance_profile().effective_resistances==model.get_resistance_profile().effective_resistances,"Allocated source survives real save reload")
	var report: Dictionary={"ok":failures==0 and rows.size()==25,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V059_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(pack)),"font_sha256":sha(font.data),"schema":36,"allocated_points":73,"defense_profile":model.get_resistance_profile(),"actual_hits":hits,"scope":"Linux same-PCK new defense consumer; not Windows hardware FPS or physical input acceptance"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("Packed v59 resistance-cap probe: %d checks, %d failures"%[rows.size(),failures]); arena.queue_free(); await process_frame; quit(0 if report.ok else 1)
