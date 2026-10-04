extends SceneTree
const Store=preload("res://scripts/save/canonical_build_store.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
func digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func _initialize()->void:
	var xdg:=OS.get_environment("XDG_DATA_HOME")
	if Rules.VERSION!=25 or ProjectSettings.get_setting("application/config/version")!="0.40.0" or not xdg.begins_with("/tmp/godot-m1-"):quit(78);return
	var directory:String=OS.get_cmdline_user_args()[0];var commit:String=OS.get_cmdline_user_args()[1];var files:Dictionary={}
	for name:String in ["v25-default.json","v25-leech.json"]:
		var candidate:=Store.new().snapshot()
		if name.contains("leech"):
			candidate.revision=53;candidate.crafting.revision=21;candidate.progress.level=119;candidate.progress.xp=17
			candidate.talents.class_id=4;candidate.talents.allocated=["50986","39725","63649","49806","6580","19711","20010","36704"];candidate.talents.normal_points=116
			var old_uid:String=candidate.items.keys()[0];var new_uid:="item_000900"
			candidate.items[new_uid]=candidate.items[old_uid];candidate.items[new_uid].uid=new_uid;candidate.items.erase(old_uid)
			candidate.locations[new_uid]=candidate.locations[old_uid];candidate.locations.erase(old_uid);candidate.next_item_serial=901
		assert(Rules.reason(candidate).is_empty(),Rules.reason(candidate))
		var bytes:PackedByteArray=(" \r\n"+JSON.stringify(candidate,"\t",true,true).replace("\n","\r\n")+"\r\n").to_utf8_buffer()
		var file:=FileAccess.open(directory.path_join(name),FileAccess.WRITE);file.store_buffer(bytes);file.close()
		files[name]={"bytes":bytes.size(),"sha256":digest(bytes)}
	var definitions:Array=Gems.definitions().keys();definitions.sort()
	FileAccess.open(directory.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"source_commit":commit,"schema":25,"application_version":"0.40.0","files":files,"gem_definitions":definitions,"capture":"External export script run against untouched v040 source before schema26 changes; no fixture made by decrementing new code.","no_user_save_reads_or_writes":true},"\t",true,true))
	print("Literal25 fixtures: ",files,"; frozen gems: ",definitions);quit()
