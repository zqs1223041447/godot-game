extends SceneTree
func _initialize() -> void:
	var output := OS.get_environment("V034_PACK_QA")
	var expected_font := OS.get_environment("V034_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64: quit(78); return
	DirAccess.make_dir_recursive_absolute(output)
	var expected_dir := "godot-game-preview-v021"
	var version := str(ProjectSettings.get_setting("application/config/version"))
	var save_dir := str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var model = load("res://scripts/canonical_game_state.gd").new()
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile
	font.allow_system_fallback = false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(font.data)
	var font_hash := hash.finish().hex_encode()
	var ok: bool = version == "0.34.0" and save_dir == expected_dir and model.snapshot().version == 22 and not model.snapshot().crafting.has("materials") and model.bag_layout() == {"pages":2,"columns":12,"rows":10} and font_hash == expected_font
	var town=load("res://scripts/town/town_catalog.gd")
	var maps=load("res://scripts/world/map_compiler.gd")
	var map_catalog=load("res://scripts/world/map_catalog.gd")
	var offers:=0
	for service:String in ["skill_merchant","equipment_merchant","jewel_merchant"]:
		offers+=town.offers(service).size()
	var profiles:Array=[]
	for id:String in map_catalog.MAPS:
		var special:Array=["elemental_aegis"]
		var compiled:Dictionary=maps.compile(id,["enemy_max_health_120","enemy_move_speed_110"],special)
		ok=ok and compiled.ok and maps.profile_reason(compiled.profile).is_empty()
		profiles.append({"id":id,"target":compiled.profile.ordinary_target,"wave":compiled.profile.wave,"special_ids":special})
	ok=ok and town.services().size()==6 and offers==56 and not model.Rules.BINDABLE_KEYS.has(KEY_C)
	var arena=load("res://scripts/main.gd").new()
	arena._world_mode="map"
	var map_profile:Dictionary=maps.compile("broken_ruins",[],[]).profile
	var began:bool=arena._map_run.begin(map_profile)
	arena._refresh_world_geometry()
	var geometry:Dictionary=arena.world_geometry()
	ok=ok and began and geometry.id=="broken_ruins" and geometry.walls.size()==2
	var wall:Rect2=geometry.walls[0]
	var from:=Vector2(wall.position.x-100,wall.get_center().y)
	var to:=Vector2(wall.end.x+100,wall.get_center().y)
	var terrain_blocked:bool=arena._geometry.sweep(from,to,6.0).hit
	ok=ok and terrain_blocked and arena._geometry.move(from,to,15.0).x<wall.position.x-15.0
	var admission=load("res://scripts/world/map_admission.gd")
	var runtime=load("res://scripts/monsters/monster_runtime.gd").new()
	var aegis:Dictionary=maps.compile("broken_ruins",["enemy_armour_80","enemy_shield_from_health_20"],["elemental_aegis"]).profile
	var root:Dictionary=admission.create_root(runtime,aegis,"ember_guard",5,from,"ordinary","",[],true)
	ok=ok and root.ok and is_equal_approx(root.enemy.resistances.fire,0.45) and is_equal_approx(root.enemy.resistances.cold,0.20) and is_equal_approx(root.enemy.resistances.lightning,0.20)
	var effective:Dictionary=root.enemy.resistances.duplicate(true)
	var shield_bonus:float=root.enemy.encounter_source.shield_bonus
	ok=ok and root.enemy.armour==80.0 and is_equal_approx(shield_bonus,float(root.enemy.encounter_source.before.max_health)*0.20)
	var ordinary=load("res://scripts/encounters/encounter_catalog.gd")
	ok=ok and ordinary.get_ids().size()==6
	var offense:Dictionary=maps.compile("old_garden",["enemy_damage_115","enemy_attack_speed_110"],[]).profile
	var attacker:Dictionary=admission.create_root(runtime,offense,"crawler",4,from,"ordinary","",[],true)
	ok=ok and attacker.ok and is_equal_approx(attacker.enemy.damage,float(attacker.enemy.encounter_source.before.damage)*1.15) and is_equal_approx(attacker.enemy.attack_speed,float(attacker.enemy.encounter_source.before.attack_speed)*1.1)
	arena.free()
	var names:PackedStringArray=[]
	for service:Dictionary in town.services():names.append(service.name)
	for character:String in "城镇测试旧庭断垣墙挡残绕道遮阔各电抗凶猛护幕铁肤".split(""):ok=ok and font.has_char(character.unicode_at(0))
	var spatial_compiler=load("res://scripts/combat/skill_compiler.gd")
	var spatial_snapshot=model.get_combat_snapshot();spatial_snapshot.spatial_modifiers={"area_size_increased":0.12,"projectile_speed_increased":0.1}
	var nova:Dictionary=spatial_compiler.compile_skill("nova",spatial_snapshot,[])
	var tornado:Dictionary=spatial_compiler.compile_skill("tornado",spatial_snapshot,[])
	var source_tree=load("res://scripts/passives/source_tree_runtime.gd")
	ok=ok and nova.ok and is_equal_approx(nova.recipe.radius,155.0*sqrt(1.12)) and tornado.ok and is_equal_approx(tornado.recipe.parent.speed,462.0) and is_equal_approx(tornado.recipe.child.speed,286.0)
	ok=ok and source_tree.node_effect("5560",0,20).status=="full" and source_tree.node_effect("5560",0,19).status!="full"
	for character:String in "慢赠面积半径投射速度".split(""):ok=ok and font.has_char(character.unicode_at(0))
	var defense=load("res://scripts/mechanics/defense_rules.gd")
	var recharge:Dictionary=defense.recharge_profile({"shield_regen":10.0,"shield_recharge_rate_increased":0.3,"shield_recharge_start_faster":0.15})
	ok=ok and recharge.ok and recharge.rate==13.0 and is_equal_approx(recharge.delay,4.0/1.15) and source_tree.node_effect("23690",0,21).status=="full" and source_tree.node_effect("23690",0,20).status!="full"
	var stats:Dictionary=model.get_stats();ok=ok and stats.shield_recharge_rate==stats.shield_regen and stats.shield_recharge_delay==4.0
	var cost_snapshot:Dictionary=model.get_combat_snapshot();cost_snapshot.resource_modifiers={"mana_cost_efficiency_increased":0.25,"mana_cost_increased":0.15}
	var cost_cast:Dictionary=spatial_compiler.compile_group("nova",cost_snapshot,["efficiency","quickcast"])
	ok=ok and cost_cast.ok and is_equal_approx(cost_cast.mana,24.0*0.8*1.4*1.15/1.25) and cost_cast.cost_factors.final_mana==cost_cast.mana
	ok=ok and source_tree.node_effect("25237",0,22).status=="full" and source_tree.node_effect("25237",0,21).status!="full" and source_tree.node_effect("53188",12119,22).status=="full" and source_tree.node_effect("53188",12119,21).status!="full"
	var basic:Dictionary=spatial_compiler.compile_basic(cost_snapshot);ok=ok and basic.ok and not basic.has("mana")
	var report := {"ok":ok,"game_version":version,"save_directory":save_dir,"actual_user_dir":OS.get_user_data_dir(),"schema":model.snapshot().version,"bag_layout":model.bag_layout(),"font_sha256":font_hash,"engine":Engine.get_version_info().string,"services":names,"supply_count":offers,"maps":profiles,"C_reserved":not model.Rules.BINDABLE_KEYS.has(KEY_C),"geometry_id":geometry.id,"wall_count":geometry.walls.size(),"terrain_blocked":terrain_blocked,"aegis_effective_resistances":effective,"ordinary_count":ordinary.get_ids().size(),"armour":root.enemy.armour,"shield_bonus":shield_bonus,"attack_speed":attacker.enemy.attack_speed,"attack_damage":attacker.enemy.damage,"spatial_nova_radius":nova.recipe.radius,"spatial_parent_speed":tornado.recipe.parent.speed,"spatial_child_speed":tornado.recipe.child.speed,"recharge_rate":recharge.rate,"recharge_delay":recharge.delay,"zero_recharge_rate":stats.shield_recharge_rate,"source_cost_nova_mana":cost_cast.mana,"source_cost_factors":cost_cast.cost_factors,"basic_free":not basic.has("mana"),"normal_save":"user://build_save.json","test_save":"user://town_test_build_save.json"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	FileAccess.open(output.path_join("GODOT_LICENSE.txt"),FileAccess.WRITE).store_string(Engine.get_license_text())
	FileAccess.open(output.path_join("GODOT_COPYRIGHT.txt"),FileAccess.WRITE).store_string(JSON.stringify(Engine.get_copyright_info(),"\t",true,true))
	var licenses: Dictionary = Engine.get_license_info()
	var license_names := licenses.keys(); license_names.sort()
	var text := "Godot 4.6.3 third-party license texts\n\n"
	for name: String in license_names: text += name + "\n" + str(licenses[name]) + "\n\n"
	FileAccess.open(output.path_join("GODOT_THIRD_PARTY_LICENSES.txt"),FileAccess.WRITE).store_string(text)
	print(JSON.stringify(report))
	quit(0 if ok else 1)
