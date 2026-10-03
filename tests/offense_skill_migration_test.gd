extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
const Icons=preload("res://scripts/visuals/skill_emblem.gd")
const Legacy=preload("res://scripts/build_state.gd")
var retained_icons:Dictionary=Icons.ICONS
class FaultModel extends Model:
	var fail_write:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:
		return ERR_CANT_CREATE if fail_write else super._write_bytes(path,bytes)
class RewriteBackup extends Legacy:
	func _backup_legacy_save(path:String)->Error:
		var result:=super._backup_legacy_save(path)
		if result==OK:FileAccess.open(path,FileAccess.WRITE).store_string("external change")
		return result
var checks:=0
var failures:=0
func _initialize()->void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated+"/"):quit(78);return
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/performance/crowded-inventory-v16.json")
	var decoded:=Rules.decode_v16(JSON.parse_string(bytes.get_string_from_utf8()))
	check(not decoded.is_empty() and Rules.reason_v16(decoded).is_empty(),"Literal released v16 file passes its frozen vocabulary and complete validator")
	var path:="user://original16.json";write(path,bytes)
	var model:=FaultModel.new();check(model.load_build(path),"Real store upgrades v16")
	check(FileAccess.get_file_as_bytes(path+".v16-backup.json")==bytes,"Original bytes backed up exactly")
	var expected:=decoded.duplicate(true);expected.version=17
	check(model.snapshot()==expected,"Only version changes; UID/locations/rows/bindings/talents/progress/crafting/ledger identical")
	check(model.crafting_change_already_saved(),"Migration establishes exact persisted revision receipt")
	check(not model.migration_message.contains("退还") and not model.migration_message.contains("扩容"),"Version17 migration does not falsely claim another point refund or bag expansion")
	var migrated_bytes:=FileAccess.get_file_as_bytes(path)
	check(model.load_build(path) and FileAccess.get_file_as_bytes(path)==migrated_bytes,"Repeated current-schema load is byte stable")
	for id:String in ["cleave","shade_bolt"]:
		var invalid:=decoded.duplicate(true)
		var uid:=""
		for key:String in invalid.items:
			if invalid.items[key].kind=="skill_gem":uid=key;break
		invalid.items[uid]=Gems.create_instance(uid,"skill:"+id)
		check(not Rules.reason_v16(invalid).is_empty() and Rules.decode_v16(JSON.parse_string(JSON.stringify(invalid))).is_empty(),"v16 cannot contain a future gem definition")
		var bad_path:="user://injected-"+id+".json";var raw:=JSON.stringify(invalid).to_utf8_buffer();write(bad_path,raw)
		var prior:=model.snapshot()
		check(not model.load_build(bad_path) and model.snapshot()==prior and FileAccess.get_file_as_bytes(bad_path)==raw,"Injected future gem rejected before memory/source mutation")
		check(not FileAccess.file_exists(bad_path+".v16-backup.json"),"Invalid source is not laundered through migration backup")
	var conflict:="user://conflict.json";write(conflict,bytes);write(conflict+".v16-backup.json","different original".to_utf8_buffer())
	var prior:=model.snapshot()
	check(not model.load_build(conflict) and model.snapshot()==prior and FileAccess.get_file_as_bytes(conflict)==bytes,"Conflicting raw-byte backup prevents migration")
	var denied:="user://denied.json";write(denied,bytes);model.fail_write=true
	check(not model.load_build(denied) and model.snapshot()==prior and FileAccess.get_file_as_bytes(denied)==bytes,"Primary write failure rolls back all memory and leaves source intact")
	check(FileAccess.get_file_as_bytes(denied+".v16-backup.json")==bytes,"Successful raw backup survives a later failed primary write")
	model.fail_write=false
	check(model.load_build(denied) and model.snapshot()==expected,"Retry reuses identical backup and migration candidate")
	var modified:="user://modified.json";write(modified,bytes)
	var race:=FaultModel.new();race._io=RewriteBackup.new();var race_before:=race.snapshot()
	check(not race.load_build(modified) and race.snapshot()==race_before,"External change after backup is detected before primary replacement")
	check(FileAccess.get_file_as_string(modified)=="external change","External new bytes remain untouched")
	var future:="user://future.json";var future_bytes:='{"version":18}'.to_utf8_buffer();write(future,future_bytes)
	check(not model.load_build(future) and model.save_build(future)!=OK and FileAccess.get_file_as_bytes(future)==future_bytes,"Unknown future schema remains write-protected")
	for name:String in ["v14-original-bytes.json","v15-wallet-27.json"]:
		var old_bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/v022_currency/"+name)
		var old_path:="user://"+name;write(old_path,old_bytes)
		var old_version:int=int(JSON.parse_string(old_bytes.get_string_from_utf8()).version)
		var older:=FaultModel.new()
		check(older.load_build(old_path) and older.snapshot().version==17,"Older canonical source reaches current schema through all strict intermediate gates")
		check(FileAccess.get_file_as_bytes(old_path+".v%d-backup.json"%old_version)==old_bytes,"Old source backup still preserves exact original version bytes")
	print("Offense skill migration: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func write(path:String,bytes:PackedByteArray)->void:FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
