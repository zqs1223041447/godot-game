extends SceneTree
func _initialize() -> void:
	var output := OS.get_environment("V027_PACK_QA")
	var expected_font := OS.get_environment("V027_PACK_FONT_SHA256")
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
	var ok: bool = version == "0.27.0" and save_dir == expected_dir and model.snapshot().version == 18 and not model.snapshot().crafting.has("materials") and model.bag_layout() == {"pages":2,"columns":12,"rows":10} and font_hash == expected_font
	var craft=load("res://scripts/items/crafting_rules.gd")
	var gear=load("res://scripts/items/equipment_catalog.gd")
	var reports:Dictionary={}
	var normal:Dictionary={"id":"gear_000001","base_id":"ashwood_bow","rarity":"normal","item_level":30,"affixes":[]}
	var source:Dictionary=normal
	for operation:String in ["enchant","elevate","reforge"]:
		var quote:Dictionary=craft.operation_quote(source,operation)
		var plan:Dictionary=craft.operation_plan(source,operation,27)
		ok=ok and quote.ok and plan.ok and gear.validate_instance(plan.instance)
		reports[operation]={"cost":quote.cost,"rarity":plan.instance.rarity,"affix_count":plan.instance.affixes.size()}
		source=plan.instance
	var single:Dictionary={"id":"gear_000002","base_id":"ashwood_bow","rarity":"magic","item_level":30,"affixes":[{"id":"whetstone_edge","tier":1,"value":1}]}
	var augment:Dictionary=craft.operation_plan(single,"augment",27)
	ok=ok and augment.ok and augment.cost.calibration_shard==6 and augment.instance.affixes.size()==2
	reports.augment={"cost":augment.cost,"affix_count":augment.instance.affixes.size()}
	var entries:Array=model.crafting_operations("")
	ok=ok and entries.size()==6 and model.flask_slots().size()==5 and model.owned_flasks().size()==2
	for entry:Dictionary in entries:ok=ok and not entry.available
	for character:String in ["差","撤","铸","销"]:ok=ok and font.has_char(character.unicode_at(0))
	var report := {"ok":ok,"game_version":version,"save_directory":save_dir,"actual_user_dir":OS.get_user_data_dir(),"schema":model.snapshot().version,"bag_layout":model.bag_layout(),"font_sha256":font_hash,"engine":Engine.get_version_info().string,"crafting":reports,"metadata_operations":entries.size(),"owned_flasks":model.owned_flasks().size(),"slot_count":model.flask_slots().size()}
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
