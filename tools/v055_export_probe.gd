extends SceneTree
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Art = preload("res://scripts/visuals/equipment_painterly_art.gd")
const Town = preload("res://scripts/town/town_catalog.gd")
const EXPECTED_CHECKS := 25
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
	var output := OS.get_environment("V055_PACK_QA")
	var pack := OS.get_environment("V055_MAIN_PACK")
	var fixture := OS.get_environment("V055_OLD_SAVE")
	if output.is_empty() or pack.is_empty() or fixture.is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v055-"):
		quit(78); return
	create_timer(30.0).timeout.connect(func(): push_error("Packed forgeblade probe did not finish"); quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	var original := FileAccess.get_file_as_bytes(fixture)
	var file := FileAccess.open("user://build_save.json",FileAccess.WRITE); file.store_buffer(original); file.close()
	var arena: Node = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire=false; arena.hud.close_panel()
	var model: RefCounted = arena.state
	check(str(ProjectSettings.get_setting("application/config/version"))=="0.55.0", "Actual packed version")
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))=="godot-game-preview-v021" and model.bag_layout()=={"pages":2,"columns":12,"rows":10}, "Existing directory and240slots")
	check(model.snapshot().version==34 and FileAccess.get_file_as_bytes("user://build_save.json.v33-backup.json")==original, "Real33 migration preserves exact original bytes")
	var old: Dictionary=JSON.parse_string(original.get_string_from_utf8()); old.version=34.0
	check(Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())),old), "Migration changes only version without grants")
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile; font.allow_system_fallback=false
	check(sha(font.data)==OS.get_environment("V055_PACK_FONT_SHA256"), "Raw packed font matches frozen source")
	var caption := "锻纹短刃本武器物理裂刃斩"; var glyphs := true
	for i: int in caption.length(): glyphs=glyphs and font.has_char(caption.unicode_at(i))
	check(glyphs, "New short-blade text uses actual bundled glyphs")
	var texture := Art.texture_for_entry({"base_id":"forgeblade","kind":"equipment"})
	check(texture!=null and texture.get_height()==512 and texture.get_width()>0 and texture.get_width()<=512 and Art.source_rect({"base_id":"forgeblade"}).has_area(), "Imported original artwork obeys512limit and alpha bounds")
	var found := false
	for offer: Dictionary in Town.offers("equipment_merchant"):
		if offer.id=="base:forgeblade": found=offer.available and offer.size==Vector2i(1,3)
	check(found, "Dynamic test catalog contains actual1x3blade")
	var rng := RandomNumberGenerator.new(); rng.seed=550055
	var uid: String=model.award_equipment(rng,16,"normal","forgeblade_v34")
	check(not uid.is_empty() and model.item(uid).payload.base_id=="forgeblade" and model.save_build(arena.build_save_path)==OK, "Real reward admission stores owned normal blade UID")
	var candidate: Dictionary=model.snapshot(); var funds: Dictionary=model._set_bag_currency_balance(candidate,100); candidate.revision+=1
	check(funds.ok and Rules.reason(candidate).is_empty() and model._commit(candidate,arena.build_save_path).ok, "Isolated100shard fixture follows real save transaction")
	var source: Dictionary=model.item(uid).payload
	var quote: Dictionary=model.crafting_quote("enchant",uid,arena.build_save_path)
	var made: Dictionary=model.execute_crafting(quote.get("handle",""),source)
	check(quote.ok and made.ok and model.crafting_balance()==92 and model.item(uid).payload.rarity=="magic", "Actual enchant keeps UID and spends8")
	source=model.item(uid).payload; var before: Dictionary=model.snapshot(); var disk:=FileAccess.get_file_as_bytes(arena.build_save_path)
	quote=model.crafting_quote("targeted_reforge_damage",uid,arena.build_save_path); model.cancel_crafting_quote(quote.get("handle",""))
	check(quote.ok and not model.execute_crafting(quote.get("handle",""),source).ok and var_to_bytes(model.snapshot())==var_to_bytes(before) and FileAccess.get_file_as_bytes(arena.build_save_path)==disk, "Cancelled target preserves all money items and raw save")
	quote=model.crafting_quote("targeted_reforge_damage",uid,arena.build_save_path); made=model.execute_crafting(quote.get("handle",""),source)
	var current: Dictionary=model.item(uid).payload
	check(made.ok and model.crafting_balance()==76 and current.affixes.any(func(a: Dictionary)->bool:return a.id in ["whetstone_edge","tempered_edge"]), "Paid16damage reforge guarantees legal local family")
	var gem_quote: Dictionary=arena.normal_gem_trade_quote("buy","skill:cleave",model.revision())
	var purchased: Dictionary=arena.execute_normal_gem_trade(gem_quote.get("handle",""),"skill:cleave")
	check(gem_quote.ok and purchased.ok and model.crafting_balance()==68, "Existing formal merchant sells actual cleave UID for8")
	var group := "group_000009"
	check(model.equip(uid) and model.move_item(purchased.get("uid",""),{"kind":"skill_main","group_id":group},model.revision(),arena.build_save_path).ok, "Actual blade and skill UIDs equip through model")
	var cast: Dictionary=model.get_group_cast(group); var profile: Dictionary=model.item_definition(uid).weapon_profile
	var w: float=(float(profile.base.physical)+float(profile.flat.physical))*(1.0+float(profile.increased.physical))
	check(cast.ok and near(cast.packets.direct.assembly.weapon.contribution.physical,w*2.8) and cast.snapshot.weapon_profile.item_id==uid, "Real compiler includes calculated W once in direct cleave")
	var base_snapshot: Dictionary=model.get_combat_snapshot()
	var raw: Dictionary=base_snapshot.duplicate(true); raw.erase("weapon_profile")
	var basic_a: Dictionary=Compiler.compile_basic(base_snapshot); var basic_b: Dictionary=Compiler.compile_basic(raw)
	var bolt_a: Dictionary=Compiler.compile_group("bolt",base_snapshot,[]); var bolt_b: Dictionary=Compiler.compile_group("bolt",raw,[])
	check(basic_a.ok and basic_b.ok and bolt_a.ok and bolt_b.ok and var_to_bytes(basic_a.packets)==var_to_bytes(basic_b.packets) and var_to_bytes(bolt_a.packets)==var_to_bytes(bolt_b.packets), "Blade local W does not leak to basic projectile or spell")
	check(Preview.details(cast).contains("锻纹短刃") and Preview.assembly_line(cast.packets.direct).contains("武器"), "Packed presentation reads real weapon assembly")
	var reopened:=Model.new()
	check(reopened.load_build(arena.build_save_path) and Same._same_data(reopened.snapshot(),model.snapshot()) and reopened.get_group_cast(group)==cast, "Current weapon rolls UID and cast survive raw save reload")
	check(arena.leave_normal_town(arena.world_context().revision).ok, "Real formal practice entry")
	arena.hud.close_panel(); arena.enemies.clear(); arena.damage_trace.clear(); arena.player_pos=arena.ARENA.get_center(); arena.mana=float(model.get_stats().max_mana)
	var enemy: Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(55,0),"ordinary","",[],false)
	enemy.spawn=0.0; enemy.health=10000.0; enemy.max_health=10000.0; enemy.shield=5.0; enemy.armour=80.0; enemy.evasion=0.0; enemy.evasion_entropy=50.0; enemy.resistances={}; enemy.speed=0.0; enemy.attack_timer=1000.0
	var rear: Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(-55,0),"ordinary","",[],false); rear.spawn=0.0; rear.health=10000.0; rear.radius=1.0
	var mana: float=arena.mana
	check(arena.cast_group(group) and near(mana-arena.mana,cast.mana) and near(arena.group_cooldown_remaining(group),cast.cooldown), "Real melee cast charges compiled mana and shared cooldown")
	var hit: Dictionary=arena.damage_trace.back(); var raw_physical: float=hit.before_defense_components.physical
	var expected: float=raw_physical*(1.0-minf(0.9,80.0/(80.0+5.0*raw_physical)))
	check(hit.skill_id=="cleave" and near(hit.total,expected) and near(hit.shield_spent,5.0) and near(10000.0-float(enemy.health),expected-5.0), "Local weapon hit passes actual critical armour shield then health settlement")
	check(near(rear.health,10000.0) and arena.damage_trace.size()==1, "Original front-sector geometry still excludes rear target")
	var now: float=arena.mana; var count: int=arena.damage_trace.size()
	check(not arena.cast_group(group) and arena.mana==now and arena.damage_trace.size()==count, "Rejected repeat charges no extra mana or damage")
	var frozen:=var_to_bytes(cast.packets); var old_contribution: float=cast.packets.direct.assembly.weapon.contribution.physical
	check(model.unequip("weapon") and not model.get_group_cast(group).packets.direct.assembly.has("weapon") and var_to_bytes(cast.packets)==frozen and old_contribution>0.0 and model.item(uid).payload==current, "Unequip affects only future cast and preserves crafted item")
	var report := {"ok":failures==0 and rows.size()==EXPECTED_CHECKS,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V055_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(pack)),"font_sha256":sha(font.data),"weapon_uid":uid,"local_physical":w,"actual_hit":hit,"remaining_shards":model.crafting_balance(),"schema":34,"scope":"Linux same-PCK new-content acceptance; no Windows hardware FPS claim"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("Packed v55 forgeblade probe: %d checks, %d failures"%[rows.size(),failures]); arena.queue_free(); await process_frame; quit(0 if report.ok else 1)
