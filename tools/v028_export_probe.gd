extends SceneTree
func _initialize() -> void:
	var output := OS.get_environment("V028_PACK_QA")
	var expected_font := OS.get_environment("V028_PACK_FONT_SHA256")
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
	var ok: bool = version == "0.28.0" and save_dir == expected_dir and model.snapshot().version == 19 and not model.snapshot().crafting.has("materials") and model.bag_layout() == {"pages":2,"columns":12,"rows":10} and font_hash == expected_font
	var town=load("res://scripts/town/town_catalog.gd")
	var maps=load("res://scripts/world/map_compiler.gd")
	var map_catalog=load("res://scripts/world/map_catalog.gd")
	var offers:=0
	for service:String in ["skill_merchant","equipment_merchant","jewel_merchant"]:
		for entry:Dictionary in town.offers(service):
			var sample:Dictionary=town.make_item(entry,1)
			ok=ok and model.Items.validate_instance(sample)
			offers+=1
	var profiles:Array=[]
	for id:String in map_catalog.MAPS:
		var special:Array=["storm_patrol"] if id=="broken_ruins" else ["frost_patrol"]
		var compiled:Dictionary=maps.compile(id,["enemy_max_health_120","enemy_move_speed_110"],special)
		ok=ok and compiled.ok and maps.profile_reason(compiled.profile).is_empty()
		profiles.append({"id":id,"target":compiled.profile.ordinary_target,"wave":compiled.profile.wave,"special_ids":special})
	ok=ok and town.services().size()==6 and offers==56 and not model.Rules.BINDABLE_KEYS.has(KEY_C)
	var names:PackedStringArray=[]
	for service:Dictionary in town.services():names.append(service.name)
	for character:String in "城镇测试旧庭断垣".split(""):ok=ok and font.has_char(character.unicode_at(0))
	var report := {"ok":ok,"game_version":version,"save_directory":save_dir,"actual_user_dir":OS.get_user_data_dir(),"schema":model.snapshot().version,"bag_layout":model.bag_layout(),"font_sha256":font_hash,"engine":Engine.get_version_info().string,"services":names,"supply_count":offers,"maps":profiles,"C_reserved":not model.Rules.BINDABLE_KEYS.has(KEY_C),"normal_save":"user://build_save.json","test_save":"user://town_test_build_save.json"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	FileAccess.open(output.path_join("GODOT_LICENSE.txt"),FileAccess.WRITE).store_string(Engine.get_license_text())
	FileAccess.open(output.path_join("GODOT_COPYRIGHT.txt"),FileAccess.WRITE).store_string(JSON.stringify(Engine.get_copyright_info(),"\t",true,true))
	var licenses: Dictionary = Engine.get_license_info()
	var names := licenses.keys(); names.sort()
	var text := "Godot 4.6.3 third-party license texts\n\n"
	for name: String in names: text += name + "\n" + str(licenses[name]) + "\n\n"
	FileAccess.open(output.path_join("GODOT_THIRD_PARTY_LICENSES.txt"),FileAccess.WRITE).store_string(text)
	print(JSON.stringify(report))
	quit(0 if ok else 1)
