extends SceneTree
func _initialize()->void:
	var Model=load("res://scripts/canonical_game_state.gd")
	if Model.Rules.VERSION!=18 or ProjectSettings.get_setting("application/config/version")!="0.27.0":quit(78);return
	var output:=OS.get_environment("V028_FIXTURE_OUTPUT")
	if output.is_empty():quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var model=Model.new()
	var rng:=RandomNumberGenerator.new();rng.seed=280018
	model.award_equipment(rng,30,"rare","nine_slot")
	var source:Dictionary=model.snapshot()
	var normal_bytes:=("  \r\n"+JSON.stringify(source,"  ",false,true).replace("\n","\r\n")+"\r\n").to_utf8_buffer()
	FileAccess.open(output.path_join("v18-no-c.json"),FileAccess.WRITE).store_buffer(normal_bytes)
	for binding:Dictionary in source.bindings:
		if binding.group_id=="group_000001":binding.keycode=KEY_C
	var c_bytes:=("\r\n  "+JSON.stringify(source,"  ",false,true).replace("\n","\r\n")+"\r\n\r\n").to_utf8_buffer()
	assert(Model.Rules.reason(source).is_empty())
	FileAccess.open(output.path_join("v18-c-bound.json"),FileAccess.WRITE).store_buffer(c_bytes)
	print("Released v0.27 schema18 literal fixtures written");quit()
