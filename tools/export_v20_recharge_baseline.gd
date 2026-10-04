extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	if Model.Rules.VERSION!=20 or ProjectSettings.get_setting("application/config/version")!="0.32.0" or args.size()!=1:quit(78);return
	var directory:String=args[0];DirAccess.make_dir_recursive_absolute(directory)
	var files:Dictionary={}
	for name:String in ["v20-default.json","v20-spatial.json"]:
		var candidate:=Model.new().snapshot()
		if name.contains("spatial"):candidate.talents.allocated=["58833","2151","5560"];candidate.talents.normal_points=3
		assert(Model.Rules.reason(candidate).is_empty())
		var bytes:PackedByteArray=(" \r\n"+JSON.stringify(candidate,"\t",true,true).replace("\n","\r\n")+"\r\n").to_utf8_buffer()
		var file:=FileAccess.open(directory.path_join(name),FileAccess.WRITE);file.store_buffer(bytes);file.close();files[name]={"bytes":bytes.size(),"sha256":digest(bytes)}
	var records:Array=[]
	for id:String in Monsters.TEMPLATES:
		for wave:int in [1,5]:
			var context:="map_boss" if Monsters.TEMPLATES[id].rarity=="boss" else "ordinary"
			var enemy:=Monsters.make_enemy(23,id,wave,Vector2(105,217),context)
			assert(not enemy.is_empty());records.append({"template":id,"wave":wave,"context":context,"rarity":"","mechanisms":[],"hash":digest(var_to_bytes(enemy))})
	for id:String in ["crawler","brute"]:
		var enemy:=Monsters.make_enemy(23,id,5,Vector2(105,217),"ordinary","magic",["aegis_recovery"])
		assert(not enemy.is_empty());records.append({"template":id,"wave":5,"context":"ordinary","rarity":"magic","mechanisms":["aegis_recovery"],"hash":digest(var_to_bytes(enemy))})
	var file:=FileAccess.open(directory.path_join("zero-recharge-v32.bin"),FileAccess.WRITE);file.store_var(records,false);file.close()
	var bytes:=FileAccess.get_file_as_bytes(directory.path_join("zero-recharge-v32.bin"));files["zero-recharge-v32.bin"]={"bytes":bytes.size(),"sha256":digest(bytes)}
	FileAccess.open(directory.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"source_commit":"0d2cfd5091643b50e2cc05bc9340c545de77d6a4","schema":20,"source_version":"0.32.0","files":files,"enemy_records":records.size(),"no_user_save_reads_or_writes":true},"\t",true,true))
	print("Frozen v32 recharge baseline: 2 literal20 files, %d exact enemy records"%records.size());quit()
func digest(bytes:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()
