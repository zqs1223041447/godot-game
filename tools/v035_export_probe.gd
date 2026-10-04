extends SceneTree
func _initialize()->void:
	var output:=OS.get_environment("V035_PACK_QA");var expected_font:=OS.get_environment("V035_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64:quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var model=load("res://scripts/canonical_game_state.gd").new()
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(font.data);var font_hash:=hash.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.35.0" and directory=="godot-game-preview-v021" and model.snapshot().version==23 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font
	var tree=load("res://scripts/passives/source_tree_runtime.gd")
	ok=ok and tree.node_effect("18402",0,23).status=="full" and tree.node_effect("18402",0,22).status!="full"
	var rules=load("res://scripts/combat/flask_modifier_rules.gd");var runtime=load("res://scripts/combat/flask_runtime.gd").new()
	var profile:Dictionary=rules.profile("flask:life",{"flask_life_recovery_increased":0.5},100.0)
	ok=ok and profile.ok and is_equal_approx(profile.recovery_total,52.5)
	runtime.reset({"packed_life":"flask:life"})
	var used:Dictionary=runtime.use("packed_life",0.0,100.0,{"flask_life_recovery_increased":0.5})
	var gain:Dictionary=runtime.advance(3.0,{"health":0.0,"mana":0.0},{"health":200.0,"mana":100.0})
	runtime.charge_rewarded_kill(["packed_life"],{"flask_charges_gained_increased":0.15})
	var snapshot:Dictionary=runtime.snapshot()
	ok=ok and used.ok and is_equal_approx(gain.health,52.5) and snapshot.charges_by_uid.packed_life==21 and snapshot.charge_remainders_micro.packed_life==150000
	for character:String in "药剂当前回复充能小数累计有效原生怪".split(""):ok=ok and font.has_char(character.unicode_at(0))
	var report:Dictionary={"ok":ok,"game_version":version,"schema":model.snapshot().version,"save_directory":directory,"actual_user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"engine":Engine.get_version_info().string,"flask_profile":profile,"actual_recovery":gain.health,"flask_snapshot":snapshot,"normal_save":"user://build_save.json","test_save":"user://town_test_build_save.json","scope":"Current flask consumer and packaging smoke only; unchanged older mechanics use prior matching-input evidence"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	FileAccess.open(output.path_join("GODOT_LICENSE.txt"),FileAccess.WRITE).store_string(Engine.get_license_text())
	FileAccess.open(output.path_join("GODOT_COPYRIGHT.txt"),FileAccess.WRITE).store_string(JSON.stringify(Engine.get_copyright_info(),"\t",true,true))
	var licenses:Dictionary=Engine.get_license_info();var names:=licenses.keys();names.sort();var text:="Godot 4.6.3 third-party license texts\n\n"
	for name:String in names:text+=name+"\n"+str(licenses[name])+"\n\n"
	FileAccess.open(output.path_join("GODOT_THIRD_PARTY_LICENSES.txt"),FileAccess.WRITE).store_string(text)
	print(JSON.stringify(report));quit(0 if ok else 1)
