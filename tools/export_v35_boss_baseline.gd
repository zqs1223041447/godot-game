extends SceneTree
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Telegraphs=preload("res://scripts/combat/telegraphed_area_runtime.gd")
func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	if ProjectSettings.get_setting("application/config/version")!="0.35.0" or args.size()!=1:quit(78);return
	var records:Array=[];var id:=1
	for wave:int in [4,5,8]:
		for template:String in ["rift_warden","ember_guard","frost_guard","storm_skitter"]:
			var enemy:=Monsters.make_enemy(id,template,wave,Vector2(100,120),"level_boss" if template=="rift_warden" else "ordinary")
			assert(not enemy.is_empty());records.append(enemy.duplicate(true));records.append(Monsters.telegraph_policy(enemy))
			if template!="rift_warden":
				enemy.spawn=0.0;var policy:=Monsters.telegraph_policy(enemy);var runtime:=Telegraphs.new()
				records.append(runtime.start(enemy,Vector2(200,120),policy.profile));records.append(runtime.state_for(id))
				for delta:float in [0.3,0.4,0.25,1.5]:records.append(runtime.advance(delta,[enemy]));records.append(runtime.state_for(id))
			id+=1
	var directory:String=args[0];DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("normal-boss-telegraphs-v35.bin");var file:=FileAccess.open(path,FileAccess.WRITE);file.store_var(records,false);file.close()
	var bytes:=FileAccess.get_file_as_bytes(path);var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes)
	FileAccess.open(directory.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"source_commit":"04fe0dc5ed7f18e54f9f0c32b2f7b8a7f1321c9e","records":records.size(),"bytes":bytes.size(),"sha256":h.finish().hex_encode(),"scope":"Three waves of normal rift_warden and all existing guarded telegraph trajectories; no user saves"},"\t",true,true))
	print("Frozen v35 boss/guard baseline: %d typed records"%records.size());quit()
