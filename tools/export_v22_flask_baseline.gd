extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Runtime=preload("res://scripts/combat/flask_runtime.gd")
func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	if Model.Rules.VERSION!=22 or ProjectSettings.get_setting("application/config/version")!="0.34.0" or args.size()!=1:quit(78);return
	var directory:String=args[0];DirAccess.make_dir_recursive_absolute(directory);var files:Dictionary={}
	for name:String in ["v22-default.json","v22-cost.json"]:
		var candidate:=Model.new().snapshot()
		if name.contains("cost"):
			candidate.progress.level=119;candidate.progress.xp=0;candidate.talents.allocated=["58833","2151","37690","48423","6204","63976","33479","10490","45680","25237"];candidate.talents.normal_points=114
		assert(Model.Rules.reason(candidate).is_empty())
		var bytes:PackedByteArray=(" \r\n"+JSON.stringify(candidate,"\t",true,true).replace("\n","\r\n")+"\r\n").to_utf8_buffer();var file:=FileAccess.open(directory.path_join(name),FileAccess.WRITE);file.store_buffer(bytes);file.close();files[name]={"bytes":bytes.size(),"sha256":digest(bytes)}
	var runtime:=Runtime.new();var records:Array=[];var owned:Dictionary={"qa_life":"flask:life","qa_mana":"flask:mana"}
	records.append(runtime.reset(owned));records.append(runtime.snapshot());records.append(runtime.use("qa_life",100.0,100.0));records.append(runtime.snapshot())
	records.append(runtime.use("qa_life",10.0,100.0));records.append(runtime.snapshot());records.append(runtime.use("qa_life",10.0,100.0));records.append(runtime.snapshot())
	records.append(runtime.advance(0.7,{"health":10.0,"mana":10.0},{"health":100.0,"mana":140.0}));records.append(runtime.snapshot())
	records.append(runtime.use("qa_mana",15.0,140.0));records.append(runtime.snapshot())
	runtime.charge_rewarded_kill(["qa_life","qa_life","qa_mana"]);records.append(runtime.snapshot())
	records.append(runtime.advance(1.8,{"health":18.0,"mana":15.0},{"health":100.0,"mana":140.0}));records.append(runtime.snapshot())
	records.append(runtime.sync_owned({"qa_life":"flask:life"}));records.append(runtime.snapshot());records.append(runtime.advance(2.0,{"health":39.0,"mana":45.0},{"health":100.0,"mana":140.0}));records.append(runtime.snapshot())
	for i:int in range(35):runtime.charge_rewarded_kill(["qa_life"])
	records.append(runtime.snapshot());runtime.clear_effects();records.append(runtime.snapshot());records.append(runtime.reset(owned));records.append(runtime.snapshot())
	var file:=FileAccess.open(directory.path_join("zero-flask-v34.bin"),FileAccess.WRITE);file.store_var(records,false);file.close();var bytes:=FileAccess.get_file_as_bytes(directory.path_join("zero-flask-v34.bin"));files["zero-flask-v34.bin"]={"bytes":bytes.size(),"sha256":digest(bytes)}
	FileAccess.open(directory.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"source_commit":"572dd6c176b8e3ada045700b62fde4a0dfd53349","schema":22,"files":files,"runtime_records":records.size(),"no_user_save_reads_or_writes":true},"\t",true,true));print("Frozen v34 flask baseline: 2 literal22 files, %d typed runtime records"%records.size());quit()
func digest(bytes:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()
