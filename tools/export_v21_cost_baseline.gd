extends SceneTree
## Execute against the immutable v0.33 project, before enabling source mana-cost
## formats. Output is test-owned literal bytes and typed compiler fingerprints.
func _initialize()->void:
	var output:=OS.get_environment("V21_COST_BASELINE_DIR")
	var Model=load("res://scripts/canonical_game_state.gd")
	if output.is_empty() or ProjectSettings.get_setting("application/config/version")!="0.33.0" or Model.Rules.VERSION!=21:
		push_error("Requires the frozen v33/schema21 project and explicit output");quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var model=Model.new();var initial:Dictionary=model.snapshot()
	var allocated:Dictionary=initial.duplicate(true)
	allocated.progress.level=119;allocated.progress.xp=0;allocated.talents.allocated=["58833","2151","37690","48423","6204","63976","33479","10490","22473","3452"];allocated.talents.normal_points=114
	if not Model.Rules.reason(initial).is_empty() or not Model.Rules.reason(allocated).is_empty():quit(1);return
	var files:Dictionary={}
	for id:String in ["default","allocated"]:
		var value:Dictionary=initial if id=="default" else allocated
		var bytes:PackedByteArray=(" \r\n"+JSON.stringify(value,"  ",true,true).replace("\n","\r\n")+"\r\n").to_utf8_buffer()
		FileAccess.open(output.path_join("v21-"+id+".json"),FileAccess.WRITE).store_buffer(bytes)
		files["v21-"+id+".json"]={"bytes":bytes.size(),"sha256":_hash(bytes)}
	var Compiler=load("res://scripts/combat/skill_compiler.gd");var Supports=load("res://scripts/combat/support_registry.gd");var Data=load("res://scripts/game_data.gd");var Combat=load("res://scripts/combat/combat_data.gd")
	var choices:Array=[[]];var support_ids:Array=Supports.SUPPORTS.keys();support_ids.sort()
	for id:String in support_ids:choices.append([id])
	for first:int in range(support_ids.size()):
		for second:int in range(first+1,support_ids.size()):choices.append([support_ids[first],support_ids[second]])
	var records:Array=[]
	var snapshots:Array=[]
	for effects:Array in [[],["return_on_range","explode_on_flight_end"]]:
		var snapshot:Dictionary=model.get_combat_snapshot();snapshot.effects=effects
		if not effects.is_empty():snapshot.spatial_modifiers={"area_size_increased":0.25,"projectile_speed_increased":0.3}
		var rows:Array=[]
		for skill:String in Data.SKILLS:
			for ids:Array in choices:
				var compiled:Dictionary=Compiler.compile_group(skill,snapshot,ids)
				if compiled.ok:rows.append({"skill":skill,"supports":ids.duplicate(),"hash":_hash(var_to_bytes(compiled))})
		var basic:Dictionary=Compiler.compile_basic(snapshot)
		records.append({"snapshot":snapshot,"casts":rows,"basic_cast_hash":_hash(var_to_bytes(basic))})
	var path:=output.path_join("zero-cost-v33.bin")
	FileAccess.open(path,FileAccess.WRITE).store_var(records,false)
	var bytes:=FileAccess.get_file_as_bytes(path);files["zero-cost-v33.bin"]={"bytes":bytes.size(),"sha256":_hash(bytes)}
	var report:Dictionary={"source_commit":"421b5f46713acf1f336b3df8c9c2023504e03c4f","source_version":"0.33.0","schema":21,"files":files,"zero_cost_casts":records[0].casts.size()+records[1].casts.size(),"basic_snapshots":2,"uid_count":initial.items.size(),"allocated_fixture":allocated.talents.allocated,"no_user_save_reads_or_writes":true}
	FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));quit()
func _hash(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
