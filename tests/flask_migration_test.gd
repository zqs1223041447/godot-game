extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Flasks=preload("res://scripts/items/flask_catalog.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
const Legacy=preload("res://scripts/build_state.gd")
class FaultModel extends Model:
	var fail_write:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_write else super._write_bytes(path,bytes)
class RewriteBackup extends Legacy:
	func _backup_legacy_save(path:String)->Error:
		var result:=super._backup_legacy_save(path)
		if result==OK:FileAccess.open(path,FileAccess.WRITE).store_string("external replacement")
		return result
var checks:=0
var failures:=0
func _initialize()->void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated+"/"):quit(78);return
	var ordinary:Dictionary={}
	for name:String in ["released-v17-two-offense.json","released-v17-maximum-registry.json"]:
		var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/v026_flasks/"+name)
		var decoded:=Rules.decode_v17(JSON.parse_string(bytes.get_string_from_utf8()))
		check(not decoded.is_empty() and Rules.reason_v17(decoded).is_empty(),"Literal released17 file passes frozen full validator")
		if ordinary.is_empty():ordinary=decoded
		var path:="user://"+name;write(path,bytes);var model:=FaultModel.new()
		check(model.load_build(path),"Store migrates validated17 with two real bottles")
		check(FileAccess.get_file_as_bytes(path+".v17-backup.json")==bytes,"Original leading/trailing whitespace and bytes preserved")
		var migrated:=model.snapshot();check(migrated.version==18 and migrated.items.size()==decoded.items.size()+2,"Exactlytwo and correct current schema")
		for uid:String in decoded.items:check(migrated.items[uid]==decoded.items[uid] and migrated.locations[uid]==decoded.locations[uid],"All prior UID/payload/location preserved "+uid)
		for field:String in ["revision","next_item_serial","progress","talents","skill_groups","bindings","crafting","migration_ledger"]:check(migrated[field]==decoded[field],"No unrelated migration changes: "+field)
		check(model.owned_flasks().size()==2 and model.flask_slots()[0].resource=="health" and model.flask_slots()[1].resource=="mana","Starters occupy new slots without old bag demand")
		check(model.crafting_change_already_saved(),"Exact persisted-revision receipt established")
		check(not model.migration_message.contains("退还") and not model.migration_message.contains("扩容"),"Migration reports actual change only")
		var migrated_bytes:=FileAccess.get_file_as_bytes(path);check(model.load_build(path) and FileAccess.get_file_as_bytes(path)==migrated_bytes,"Reload current18 neither rewrites bytes nor grants again")
		if decoded.items.size()==Rules.V17_MAX_ITEMS:
			check(migrated.items.size()==Rules.MAX_ITEMS and Rules.MAX_ITEMS==1027,"Onlytwo registry allowance keeps every full old item")
			check(migrated.next_item_serial==Rules.MAX_SERIAL,"Exhausted normal allocator does not prevent once-only migration")
			check(model.flask_slots()[0].uid not in decoded.items and model.flask_slots()[1].uid not in decoded.items,"Existing migration-like UIDs cannot be overwritten")
	var source:=JSON.stringify(ordinary,"\t",true,true).to_utf8_buffer()
	var model:=FaultModel.new();var before:=model.snapshot()
	var invalids:Array=[]
	var injected:=ordinary.duplicate(true);injected.items["new_flask"]=Flasks.create_instance("new_flask","flask:life");injected.locations.new_flask={"kind":"flask_slot","slot_id":"flask_1"};invalids.append(injected)
	var bad_slot:=ordinary.duplicate(true);var uid:String=bad_slot.items.keys()[0];bad_slot.locations[uid]={"kind":"flask_slot","slot_id":"flask_1"};invalids.append(bad_slot)
	var oversized:=Rules.decode_v17(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v026_flasks/released-v17-maximum-registry.json")))
	oversized.items.too_many=Gems.create_instance("too_many","skill:bolt");oversized.locations.too_many={"kind":"recovery","index":1025};invalids.append(oversized)
	for index:int in invalids.size():
		var path:="user://invalid%d.json"%index;var bytes:=JSON.stringify(invalids[index]).to_utf8_buffer();write(path,bytes)
		check(not model.load_build(path) and model.snapshot()==before and FileAccess.get_file_as_bytes(path)==bytes,"Invalid17 cannot be accepted by broader18 rules")
		check(not FileAccess.file_exists(path+".v17-backup.json"),"Reject before laundering through backup")
	var conflict:="user://conflict.json";write(conflict,source);write(conflict+".v17-backup.json","different original".to_utf8_buffer())
	check(not model.load_build(conflict) and model.snapshot()==before and FileAccess.get_file_as_bytes(conflict)==source,"Conflicting backup refuses without mutation")
	var denied:="user://denied.json";write(denied,source);model.fail_write=true
	check(not model.load_build(denied) and model.snapshot()==before and FileAccess.get_file_as_bytes(denied)==source,"Migration write failure rolls back both starters and memory")
	check(FileAccess.get_file_as_bytes(denied+".v17-backup.json")==source,"Completed original backup survives primary failure")
	model.fail_write=false;check(model.load_build(denied) and model.owned_flasks().size()==2,"Retry creates only same deterministic twoUIDs")
	var moved_before:=model.snapshot();var disk_before:=FileAccess.get_file_as_bytes(denied);var bottle:String=model.flask_slots()[0].uid
	model.fail_write=true;var move:Dictionary=model.move_item(bottle,{"kind":"flask_slot","slot_id":"flask_5"},model.revision(),denied)
	check(not move.ok and model.snapshot()==moved_before and FileAccess.get_file_as_bytes(denied)==disk_before,"Failed flask move cannot publish partial locations or revision")
	var race_path:="user://race.json";write(race_path,source);var race:=FaultModel.new();race._io=RewriteBackup.new();var race_before:=race.snapshot()
	check(not race.load_build(race_path) and race.snapshot()==race_before and FileAccess.get_file_as_string(race_path)=="external replacement","External rewrite between backup and primary commit is retained")
	var future_path:="user://future.json";var future:='{"version":19}'.to_utf8_buffer();write(future_path,future)
	check(not race.load_build(future_path) and race.save_build(future_path)!=OK and FileAccess.get_file_as_bytes(future_path)==future,"Future schema remains write-protected")
	for fixture:String in ["res://tests/fixtures/v022_currency/v14-original-bytes.json","res://tests/fixtures/v022_currency/v15-wallet-27.json","res://tests/fixtures/performance/crowded-inventory-v16.json"]:
		var bytes:=FileAccess.get_file_as_bytes(fixture);var version:int=int(JSON.parse_string(bytes.get_string_from_utf8()).version);var path:="user://old%d.json"%version;write(path,bytes)
		var old:=Model.new();check(old.load_build(path) and old.snapshot().version==18 and old.owned_flasks().size()==2,"Older canonical goes through all frozen version gates")
		check(FileAccess.get_file_as_bytes(path+".v%d-backup.json"%version)==bytes,"Oldest actual source bytes backed up once")
	print("Flask migration: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func write(path:String,bytes:PackedByteArray)->void:FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
