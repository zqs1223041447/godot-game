extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Migration=preload("res://scripts/save/reserved_hotkey_migration.gd")
class FaultModel extends Model:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
var checks:=0
var failures:=0
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	for source_file:String in ["v18-no-c.json","v18-c-bound.json"]:
		var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/v028_town/"+source_file)
		var raw:Variant=JSON.parse_string(bytes.get_string_from_utf8())
		var source:=Rules.decode_v18(raw)
		check(not source.is_empty() and Rules.reason_v18(source).is_empty(),"Frozen18 validates released source including C")
		var expected:=source.duplicate(true);expected.version=19
		expected.bindings=expected.bindings.filter(func(b:Dictionary)->bool:return b.keycode!=KEY_C)
		check(Migration.migrate_v18(source)==expected,"Pure migration changes only version and C binding")
		check(Rules.reason(source)!="" and not Rules.BINDABLE_KEYS.has(KEY_C),"Current contract reserves C")
		var path:="user://hotkey-"+source_file
		write(path,bytes)
		var state:=Model.new();var changes:=[0];state.changed.connect(func():changes[0]+=1)
		check(state.load_build(path) and state.snapshot()==expected,"Actual store commits exact migrated build")
		check(FileAccess.get_file_as_bytes(path+".v18-backup.json")==bytes,"Original whitespace/CRLF bytes backed up")
		check(changes[0]==1 and state.successful_saves==1,"One persisted migration and one notification")
		check(state.migration_message.contains("未绑定")==source_file.contains("c-bound"),"Only affected groups receive unbound notice")
		var disk:=FileAccess.get_file_as_bytes(path)
		check(state.load_build(path) and not state.migrated_from_legacy and state.snapshot()==expected and FileAccess.get_file_as_bytes(path)==disk,"Current reread does not repeat migration or notice")
		check(not state.bind_group("group_000001",KEY_C,state.revision(),path).ok,"New C skill binding rejected")
		var conflict_path:="user://conflict-"+source_file;write(conflict_path,bytes);write(conflict_path+".v18-backup.json",PackedByteArray([1,2,3]))
		var conflict:=Model.new();var initial:=conflict.snapshot()
		check(not conflict.load_build(conflict_path) and conflict.snapshot()==initial and FileAccess.get_file_as_bytes(conflict_path)==bytes,"Conflicting backup never overwrites original or memory")
		var fault_path:="user://fault-"+source_file;write(fault_path,bytes)
		var fault:=FaultModel.new();initial=fault.snapshot();fault.fail_save=true
		check(not fault.load_build(fault_path) and fault.snapshot()==initial and FileAccess.get_file_as_bytes(fault_path)==bytes,"Primary write failure preserves bytes and memory")
		check(FileAccess.get_file_as_bytes(fault_path+".v18-backup.json")==bytes,"Failed primary still retains safe source backup")
		fault.fail_save=false
		check(fault.load_build(fault_path) and fault.snapshot()==expected,"Safe retry after write failure succeeds once")
		for mutation:String in ["duplicate","unknown","future"]:
			var bad:Dictionary=raw.duplicate(true)
			if mutation=="duplicate":bad.bindings.append(bad.bindings[0].duplicate())
			elif mutation=="unknown":bad.items[bad.items.keys()[0]].kind="unknown"
			else:bad.version=20
			var bad_bytes:=JSON.stringify(bad).to_utf8_buffer();var bad_path:="user://%s-%s"%[mutation,source_file];write(bad_path,bad_bytes)
			var rejected:=Model.new();initial=rejected.snapshot()
			check(not rejected.load_build(bad_path) and rejected.snapshot()==initial and FileAccess.get_file_as_bytes(bad_path)==bad_bytes and not FileAccess.file_exists(bad_path+".v18-backup.json"),"Invalid/future input rejected before cleanup/backup/write: "+mutation)
	print("Reserved hotkey migration: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(why)
