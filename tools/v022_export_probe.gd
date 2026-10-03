extends SceneTree
func _initialize() -> void:
	var output := OS.get_environment("V022_PACK_QA")
	var expected_font := OS.get_environment("V022_PACK_FONT_SHA256")
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
	var ok: bool = version == "0.22.0" and save_dir == expected_dir and model.snapshot().version == 16 and not model.snapshot().crafting.has("materials") and model.bag_layout() == {"pages":2,"columns":12,"rows":10} and font_hash == expected_font
	var report := {"ok":ok,"game_version":version,"save_directory":save_dir,"actual_user_dir":OS.get_user_data_dir(),"schema":model.snapshot().version,"bag_layout":model.bag_layout(),"font_sha256":font_hash,"engine":Engine.get_version_info().string}
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
