extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	for name:String in ["released-v17-two-offense.json","released-v17-maximum-registry.json"]:
		var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/v026_flasks/"+name)
		var raw:Dictionary=JSON.parse_string(bytes.get_string_from_utf8())
		var original:Dictionary=Model.Rules.decode_v17(raw);check(Model.Rules.reason_v17(original).is_empty(),"Literal17 passes unchanged frozen source rules")
		var path:="user://chain-"+name;var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		var state:=Model.new();check(state.load_build(path),"17→18→19 chain actually loads")
		var after:=state.snapshot();check(after.version==19 and after.items.size()==original.items.size()+2,"Exactly two once-only bottles and current schema")
		check(after.next_item_serial==original.next_item_serial and after.progress==original.progress and after.talents==original.talents and after.crafting==original.crafting,"Allocator/progress/points/material revision unchanged")
		var retained:Dictionary=after.items.duplicate(true)
		for uid:String in original.items:
			check(after.items[uid]==original.items[uid] and after.locations[uid]==original.locations[uid],"Every old UID/payload/location preserved")
			retained.erase(uid)
		check(retained.size()==2 and retained.values().all(func(item:Dictionary)->bool:return item.kind=="flask"),"Only legitimate starter bottles added")
		check(FileAccess.get_file_as_bytes(path+".v17-backup.json")==bytes,"Original raw17 backup retained across two migration stages")
		check(state.load_build(path) and state.snapshot()==after,"Current reread adds nothing")
	print("Town migration chain: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(why)
