extends SceneTree
const Store=preload("res://scripts/save/canonical_build_store.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
func digest(bytes:PackedByteArray)->String:
 var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func _initialize()->void:
 if Rules.VERSION!=24 or ProjectSettings.get_setting("application/config/version")!="0.39.0":quit(78);return
 var directory:String=OS.get_cmdline_user_args()[0];var commit:String=OS.get_cmdline_user_args()[1];var files:Dictionary={}
 for name:String in ["v24-default.json","v24-critical.json"]:
  var candidate:=Store.new().snapshot()
  if name.contains("critical"):
   candidate.revision=47;candidate.crafting.revision=19;candidate.progress.level=119;candidate.progress.xp=23
   candidate.talents.class_id=6;candidate.talents.allocated=["44683","38129","11334","15549","20546","35894"];candidate.talents.normal_points=118
   var old_uid:String=candidate.items.keys()[0];var new_uid:="item_000900"
   candidate.items[new_uid]=candidate.items[old_uid];candidate.items[new_uid].uid=new_uid;candidate.items.erase(old_uid)
   candidate.locations[new_uid]=candidate.locations[old_uid];candidate.locations.erase(old_uid);candidate.next_item_serial=901
  assert(Rules.reason(candidate).is_empty(),Rules.reason(candidate))
  var bytes:PackedByteArray=(" \r\n"+JSON.stringify(candidate,"\t",true,true).replace("\n","\r\n")+"\r\n").to_utf8_buffer()
  var file:=FileAccess.open(directory.path_join(name),FileAccess.WRITE);file.store_buffer(bytes);file.close()
  files[name]={"bytes":bytes.size(),"sha256":digest(bytes)}
 FileAccess.open(directory.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"source_commit":commit,"schema":24,"application_version":"0.39.0","files":files,"capture":"External export script run against untouched v039 source before schema25 changes; no fixture created by decrementing new code.","no_user_save_reads_or_writes":true},"\t",true,true))
 var result:Dictionary={"source_commit":commit,"policies":{}}
 var ids:=SourceTree.Data.standard_ids();ids.sort()
 for version:int in range(19,25):
  var records:Array=[]
  for id:String in ids:
   records.append([id,0,SourceTree.node_effect(id,0,version)])
   for effect:Dictionary in SourceTree.Data.node(id).mastery_effects:records.append([id,int(effect.effect),SourceTree.node_effect(id,int(effect.effect),version)])
  result.policies[str(version)]={"records":records.size(),"sha256":digest(JSON.stringify(records,"",true,true).to_utf8_buffer())}
 FileAccess.open(directory.path_join("old-source-gates.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print("Literal24 fixtures: ",files,"; frozen policy hashes: ",result);quit()
