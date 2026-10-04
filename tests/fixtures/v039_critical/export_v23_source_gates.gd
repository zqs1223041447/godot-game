extends SceneTree
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
func _initialize()->void:
	if Rules.VERSION!=23:quit(78);return
	var result:Dictionary={"source_commit":"a4b13688c9bed0911b751854172d073e83935903","policies":{}}
	var ids:=SourceTree.Data.standard_ids();ids.sort()
	for version:int in range(19,24):
		var records:Array=[]
		for id:String in ids:
			records.append([id,0,SourceTree.node_effect(id,0,version)])
			for effect:Dictionary in SourceTree.Data.node(id).mastery_effects:records.append([id,int(effect.effect),SourceTree.node_effect(id,int(effect.effect),version)])
		var bytes:=JSON.stringify(records,"",true,true).to_utf8_buffer();var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
		result.policies[str(version)]={"records":records.size(),"sha256":hash.finish().hex_encode()}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(result);quit()
