extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Migration=preload("res://scripts/save/source_recharge_migration.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
class FaultModel extends Model:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
class ExternalIO extends Model.Legacy:
	func _backup_legacy_save(path:String)->Error:
		var result:=super._backup_legacy_save(path)
		if result==OK:
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("external writer");file.close()
		return result
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	for name:String in ["v20-default.json","v20-spatial.json"]:
		var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/v033_recharge/"+name)
		var source:=Rules.decode_v20(JSON.parse_string(bytes.get_string_from_utf8()))
		check(not source.is_empty() and Rules.reason_v20(source).is_empty(),"Released literal20 passes frozen source contract")
		var expected:=source.duplicate(true);expected.version=21
		check(Migration.migrate_v20(source)==expected,"Pure migration changes version only, including all UID/progress/points/revision")
		var expected_current:=expected.duplicate(true);expected_current.version=Rules.VERSION
		var path:="user://spatial-"+name;write(path,bytes)
		var model:=Model.new();var signals:=[0];model.changed.connect(func():signals[0]+=1)
		check(model.load_build(path) and model.snapshot()==expected_current,"Actual store migrates exact complete candidate")
		check(model.successful_saves==1 and signals[0]==1,"One write and one notification")
		check(FileAccess.get_file_as_bytes(path+".v20-backup.json")==bytes,"Backup preserves original whitespace and CRLF bytes")
		check(model.migrated_from_legacy and model.migration_message.contains("护盾充能") and not model.migration_message.contains("放入两瓶"),"Current migration notice does not claim repeated grants")
		var disk:=FileAccess.get_file_as_bytes(path)
		check(model.load_build(path) and model.snapshot()==expected_current and not model.migrated_from_legacy and model.successful_saves==1 and FileAccess.get_file_as_bytes(path)==disk,"Current reread does not write or migrate again")
		var conflict_path:="user://conflict-"+name;write(conflict_path,bytes);write(conflict_path+".v20-backup.json",PackedByteArray([1,2,3]))
		var conflict:=Model.new();var initial:=conflict.snapshot()
		check(not conflict.load_build(conflict_path) and conflict.snapshot()==initial and FileAccess.get_file_as_bytes(conflict_path)==bytes,"Conflicting backup keeps disk and memory unchanged")
		var fault_path:="user://fault-"+name;write(fault_path,bytes)
		var fault:=FaultModel.new();initial=fault.snapshot();fault.fail_save=true
		check(not fault.load_build(fault_path) and fault.snapshot()==initial and FileAccess.get_file_as_bytes(fault_path)==bytes,"Atomic write failure retains source and memory")
		check(FileAccess.get_file_as_bytes(fault_path+".v20-backup.json")==bytes,"Failed primary write retains exact source backup")
		fault.fail_save=false
		check(fault.load_build(fault_path) and fault.snapshot()==expected_current,"Same source safely retries after write failure")
		var external_path:="user://external-"+name;write(external_path,bytes)
		var external:=Model.new();external._io=ExternalIO.new();initial=external.snapshot()
		check(not external.load_build(external_path) and external.snapshot()==initial and FileAccess.get_file_as_string(external_path)=="external writer","External modification after backup is never overwritten")
		check(FileAccess.get_file_as_bytes(external_path+".v20-backup.json")==bytes,"External-modification case retains original backup")
		for mutation:String in ["future","duplicate","unknown","spatial_injection"]:
			var bad:=source.duplicate(true)
			if mutation=="future":bad.version=Rules.VERSION+1
			elif mutation=="duplicate":bad.bindings.append(bad.bindings[0].duplicate())
			elif mutation=="unknown":bad.items[bad.items.keys()[0]].kind="unknown"
			else:
				bad.progress.level=119;bad.progress.xp=0;bad.talents.allocated=["58833","2151","37690","48423","6204","63976","33479","10490","22473","3452"];bad.talents.normal_points=114
			var bad_path:="user://%s-%s"%[mutation,name];var bad_bytes:=JSON.stringify(bad).to_utf8_buffer();write(bad_path,bad_bytes)
			var rejected:=Model.new();initial=rejected.snapshot()
			check(not rejected.load_build(bad_path) and rejected.snapshot()==initial and FileAccess.get_file_as_bytes(bad_path)==bad_bytes and not FileAccess.file_exists(bad_path+".v20-backup.json"),"Malformed/future/new-node injection rejected before backup: "+mutation)
			check(rejected.save_build(bad_path)!=OK and FileAccess.get_file_as_bytes(bad_path)==bad_bytes,"Rejected source remains protected against later save: "+mutation)
	# Both cache directions must preserve the version-specific supported-node gate.
	var candidate:=Model.new().snapshot();candidate.progress.level=119;candidate.talents.allocated=["58833","2151","37690","48423","6204","63976","33479","10490","22473","3452"];candidate.talents.normal_points=114
	check(Rules.reason(candidate).is_empty() and SourceTree.analyze(candidate).legal,"New source recharge node is genuinely legal in21")
	var old:=candidate.duplicate(true);old.version=20
	check(not Rules.reason_v20(old).is_empty() and not SourceTree.analyze(old).legal,"Warm21 analysis cannot authorize20 node injection")
	check(SourceTree.node_effect("3452",0,20).status!="full" and SourceTree.node_effect("3452",0,21).status=="full","Node cache distinguishes source vocabulary")
	check(not SourceTree.line_effect("10% increased Energy Shield Recharge Rate",20).supported and SourceTree.line_effect("10% increased Energy Shield Recharge Rate",21).supported,"Line cache distinguishes source vocabulary")
	check(Rules.reason(candidate).is_empty(),"Warm20 rejection cannot poison legal21 analysis")
	# One representative older source exercises18→19→20 and its original backup.
	var older_bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/v028_town/v18-c-bound.json")
	var older:=Rules.decode_v18(JSON.parse_string(older_bytes.get_string_from_utf8()));var expected_current:=older.duplicate(true);expected_current.version=Rules.VERSION
	expected_current.bindings=expected_current.bindings.filter(func(binding:Dictionary)->bool:return binding.keycode!=KEY_C)
	write("user://older18.json",older_bytes);var model:=Model.new()
	check(model.load_build("user://older18.json") and model.snapshot()==expected_current,"Older18 chain keeps all items and only removes reserved C binding")
	check(FileAccess.get_file_as_bytes("user://older18.json.v18-backup.json")==older_bytes and model.migration_message.contains("未绑定"),"Older source keeps actual18 byte backup and C notice")
	print("Source recharge migration: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
