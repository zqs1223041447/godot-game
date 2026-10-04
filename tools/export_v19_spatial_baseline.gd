extends SceneTree
## Execute against the immutable v0.31 project, before enabling source spatial
## formats. Output is test-owned literal bytes and typed compiler fingerprints.
func _initialize()->void:
	var output:=OS.get_environment("V19_SPATIAL_BASELINE_DIR")
	var Model=load("res://scripts/canonical_game_state.gd")
	if output.is_empty() or ProjectSettings.get_setting("application/config/version")!="0.31.0" or Model.Rules.VERSION!=19:
		push_error("Requires the frozen v31/schema19 project and explicit output");quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var model=Model.new();var initial:Dictionary=model.snapshot()
	var allocated:Dictionary=initial.duplicate(true)
	for unused:int in range(2):
		var choices:Array=Model.SourceTree.available(allocated)
		if choices.is_empty():push_error("No valid v19 path fixture");quit(1);return
		allocated.talents.allocated.append(choices[0]);allocated.talents.normal_points-=1;allocated.revision+=1
	if not Model.Rules.reason(initial).is_empty() or not Model.Rules.reason(allocated).is_empty():quit(1);return
	var files:Dictionary={}
	for id:String in ["default","allocated"]:
		var value:Dictionary=initial if id=="default" else allocated
		var bytes:PackedByteArray=(" \r\n"+JSON.stringify(value,"  ",true,true).replace("\n","\r\n")+"\r\n").to_utf8_buffer()
		FileAccess.open(output.path_join("v19-"+id+".json"),FileAccess.WRITE).store_buffer(bytes)
		files["v19-"+id+".json"]={"bytes":bytes.size(),"sha256":_hash(bytes)}
	var Compiler=load("res://scripts/combat/skill_compiler.gd");var Supports=load("res://scripts/combat/support_registry.gd");var Data=load("res://scripts/game_data.gd");var Combat=load("res://scripts/combat/combat_data.gd")
	var choices:Array=[[]];var support_ids:Array=Supports.SUPPORTS.keys();support_ids.sort()
	for id:String in support_ids:choices.append([id])
	for first:int in range(support_ids.size()):
		for second:int in range(first+1,support_ids.size()):choices.append([support_ids[first],support_ids[second]])
	var records:Array=[]
	var snapshots:Array=[]
	for effects:Array in [[],["return_on_range","explode_on_flight_end"]]:
		var snapshot:Dictionary=model.get_combat_snapshot();snapshot.effects=effects
		var rows:Array=[]
		for skill:String in Data.SKILLS:
			for ids:Array in choices:
				var compiled:Dictionary=Compiler.compile_group(skill,snapshot,ids)
				if compiled.ok:rows.append({"skill":skill,"supports":ids.duplicate(),"hash":_hash(var_to_bytes(compiled))})
		var basic:Dictionary=snapshot.duplicate(true)
		basic.compiled_skill_id="basic";basic.compiled_packets={"projectile":Combat.event_packet(snapshot,"basic","projectile").duplicate(true),"secondary":Combat.secondary_packet(snapshot,"basic").duplicate(true)}
		records.append({"snapshot":snapshot,"casts":rows,"basic_snapshot_hash":_hash(var_to_bytes(basic)),"basic_speed":640.0})
	var path:=output.path_join("zero-spatial-v31.bin")
	FileAccess.open(path,FileAccess.WRITE).store_var(records,false)
	var bytes:=FileAccess.get_file_as_bytes(path);files["zero-spatial-v31.bin"]={"bytes":bytes.size(),"sha256":_hash(bytes)}
	var report:Dictionary={"source_commit":"75f48cc91d2f82c3b5c9a8f9e0ae756b11c82f37","source_version":"0.31.0","schema":19,"files":files,"zero_spatial_casts":records[0].casts.size()+records[1].casts.size(),"basic_snapshots":2,"uid_count":initial.items.size(),"allocated_fixture":allocated.talents.allocated,"no_user_save_reads_or_writes":true}
	FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));quit()
func _hash(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
