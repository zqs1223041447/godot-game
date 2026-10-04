extends SceneTree
const Store=preload("res://scripts/save/canonical_build_store.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Journey=preload("res://scripts/world/normal_journey_state.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Migration=preload("res://scripts/save/normal_journey_migration.gd")
const Prior=preload("res://scripts/save/source_leech_migration.gd")
class FaultStore extends Store:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
class BackupFailIO extends Store.Legacy:
	func _backup_legacy_save(_path:String)->Error:return ERR_CANT_CREATE
class ExternalIO extends Store.Legacy:
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
func digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func reject_preserving(path:String,bad_bytes:PackedByteArray,version:int)->void:
	write(path,bad_bytes);var store:=Store.new();var initial:=store.snapshot();var signals:=[0];store.changed.connect(func():signals[0]+=1)
	check(not store.load_build(path) and store.snapshot()==initial and FileAccess.get_file_as_bytes(path)==bad_bytes,"Rejected input preserves memory and exact source: "+path)
	check(store.save_attempts==0 and store.successful_saves==0 and signals[0]==0 and not FileAccess.file_exists(path+".v%d-backup.json"%version),"Rejected before backup/write/notify: "+path)
	check(store.save_build(path)!=OK and FileAccess.get_file_as_bytes(path)==bad_bytes,"Rejected source stays protected: "+path)
func _initialize()->void:
	var xdg:=OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(xdg+"/"):quit(78);return
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v041_journey/manifest.json"))
	check(Store.new().snapshot().version==26 and Rules.VERSION==26 and Store.new().snapshot().journey==Journey.empty(),"Fresh store finishes chain to26 with empty journey")
	for name:String in ["v25-default.json","v25-leech.json"]:
		var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/v041_journey/"+name)
		check(bytes.size()==int(manifest.files[name].bytes) and digest(bytes)==manifest.files[name].sha256 and bytes.get_string_from_utf8().begins_with(" \r\n"),"Literal fixture matches untouched8e5f4fb and keeps CRLF")
		var raw:Variant=JSON.parse_string(bytes.get_string_from_utf8());var source:=Rules.decode_v25(raw)
		check(not source.is_empty() and Rules.reason_v25(source).is_empty() and Rules.decode(raw).is_empty(),"Released literal25 uses exact frozen envelope")
		if name=="v25-leech.json":
			check(source.items.has("item_000900") and source.locations.has("item_000900") and source.next_item_serial==901 and source.revision==53 and source.crafting.revision==21 and source.talents.allocated.has("36704"),"Real leech allocation and changed UID/revisions captured")
		var before:=var_to_bytes(source);var expected:=source.duplicate(true);expected.version=26;expected["journey"]=Journey.empty()
		check(Migration.migrate_v25(source)==expected and var_to_bytes(source)==before,"Pure migration only adds empty journey and version")
		check(Migration.migrate_v25(expected).is_empty(),"No remigration of26")
		var injected:=source.duplicate(true);injected["journey"]=Journey.empty()
		check(Rules.decode_v25(injected).is_empty() and not Rules.reason_v25(injected).is_empty() and Migration.migrate_v25(injected).is_empty(),"Schema25 injection of journey is rejected")
		var path:="user://journey-"+name;write(path,bytes)
		var store:=Store.new();var signals:=[0];store.changed.connect(func():signals[0]+=1)
		check(store.load_build(path) and store.snapshot()==expected,"Store preserves all UID/location/progress/passive/revision fields")
		check(store.save_attempts==1 and store.successful_saves==1 and signals[0]==1,"Direct migration writes and notifies once")
		check(FileAccess.get_file_as_bytes(path+".v25-backup.json")==bytes,"Backup is exact original bytes")
		var disk:=FileAccess.get_file_as_bytes(path)
		check(Rules.decode(JSON.parse_string(disk.get_string_from_utf8()))==expected,"Disk contains full candidate")
		check(store.load_build(path) and store.snapshot()==expected and store.successful_saves==1 and FileAccess.get_file_as_bytes(path)==disk,"Current reread never rewrites")
		var conflict_path:="user://conflict-"+name;write(conflict_path,bytes);var other:=PackedByteArray([1,2,3]);write(conflict_path+".v25-backup.json",other)
		var conflict:=Store.new();var initial:=conflict.snapshot()
		check(not conflict.load_build(conflict_path) and conflict.snapshot()==initial and FileAccess.get_file_as_bytes(conflict_path)==bytes and FileAccess.get_file_as_bytes(conflict_path+".v25-backup.json")==other and conflict.save_attempts==0,"Backup collision preserves both files and memory")
		check(conflict.save_build(conflict_path)!=OK,"Backup conflict blocks later save")
		var backup_path:="user://backup-fail-"+name;write(backup_path,bytes);var backup:=Store.new();initial=backup.snapshot();backup._io=BackupFailIO.new()
		check(not backup.load_build(backup_path) and backup.snapshot()==initial and FileAccess.get_file_as_bytes(backup_path)==bytes and backup.save_attempts==0,"Failed backup precedes primary write and memory")
		var fault_path:="user://fault-"+name;write(fault_path,bytes);var fault:=FaultStore.new();initial=fault.snapshot();fault.fail_save=true;var fault_signals:=[0];fault.changed.connect(func():fault_signals[0]+=1)
		check(not fault.load_build(fault_path) and fault.snapshot()==initial and FileAccess.get_file_as_bytes(fault_path)==bytes and fault_signals[0]==0 and fault.successful_saves==0,"Failed migration write leaves memory/source untouched")
		check(FileAccess.get_file_as_bytes(fault_path+".v25-backup.json")==bytes,"Failed write retains exact byte backup")
		fault.fail_save=false
		check(fault.load_build(fault_path) and fault.snapshot()==expected and fault.successful_saves==1 and fault_signals[0]==1,"Retry with matching backup succeeds once")
		var external_path:="user://external-"+name;write(external_path,bytes);var external:=Store.new();external._io=ExternalIO.new();initial=external.snapshot()
		check(not external.load_build(external_path) and external.snapshot()==initial and FileAccess.get_file_as_string(external_path)=="external writer" and external.save_attempts==0,"External rewrite after backup preserved")
		check(FileAccess.get_file_as_bytes(external_path+".v25-backup.json")==bytes,"External rewrite retains source backup")
		for mutation:String in ["future","duplicate_binding","unknown_item","fractional_revision","extra_field","journey_injection"]:
			var bad:=source.duplicate(true)
			match mutation:
				"future":bad.version=27
				"duplicate_binding":bad.bindings.append(bad.bindings[0].duplicate())
				"unknown_item":bad.items[bad.items.keys()[0]].kind="unknown"
				"fractional_revision":bad.revision=0.5
				"extra_field":bad.leech_instances=[]
				"journey_injection":bad["journey"]=Journey.empty()
			reject_preserving("user://%s-%s"%[mutation,name],JSON.stringify(bad).to_utf8_buffer(),int(bad.version))
	# Current persistent run/reward survive save/reload and bad candidates never overwrite them.
	var transaction:=FaultStore.new();var current:=transaction.snapshot();current.journey=Journey.start(current.journey,Maps.compile_normal("old_garden",1,[],[]).profile).journey
	transaction._accept_memory(current);var path:="user://current-active.json";check(transaction.save_build(path)==OK,"Active snapshot persists")
	var disk:=FileAccess.get_file_as_bytes(path);var reload:=Store.new();check(reload.load_build(path) and reload.snapshot()==current and reload.successful_saves==0,"Current active run reload is exact")
	var pending:=current.duplicate(true);pending.journey=Journey.complete(current.journey,1).journey;pending.revision+=1;transaction.fail_save=true
	check(not transaction._commit(pending,path).ok and transaction.snapshot()==current and FileAccess.get_file_as_bytes(path)==disk,"Failed full-snapshot reward commit preserves active run")
	transaction.fail_save=false;check(transaction._commit(pending,path).ok and transaction.snapshot()==pending,"Retry persists pending reward exactly once")
	for mutation:String in ["missing","runtime","negative","claims","serial","selection","concurrent","reward","bool","float"]:
		var bad:=current.duplicate(true)
		match mutation:
			"missing":bad.erase("journey")
			"runtime":bad.journey.rng=1
			"negative":bad.journey.normal_root_kills=-1
			"claims":bad.journey.claimed_gems=1
			"serial":bad.journey.active_run.run_id=bad.journey.next_run_id
			"selection":bad.journey.active_run.normal_ids=["enemy_move_speed_110","enemy_armour_80"]
			"concurrent":bad.journey.pending_map_reward=pending.journey.pending_map_reward.duplicate()
			"reward":bad=pending.duplicate(true);bad.journey.pending_map_reward.shards=100
			"bool":bad.journey.normal_root_kills=true
			"float":bad.journey.normal_root_kills=0.5
		reject_preserving("user://current-invalid-"+mutation+".json",JSON.stringify(bad).to_utf8_buffer(),26)
	# Each existing chain is reused once, then the final26 wrapper runs once.
	for fixture:String in ["v028_town/v18-c-bound.json","v032_spatial/v19-allocated.json","v033_recharge/v20-spatial.json","v034_cost/v21-allocated.json","v035_flasks/v22-cost.json","v039_critical/v23-flasks.json","v040_leech/v24-critical.json"]:
		var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/"+fixture);var raw:Dictionary=JSON.parse_string(bytes.get_string_from_utf8());var version:int=int(raw.version)
		var expected:=raw.duplicate(true);expected.version=26;expected["journey"]=Journey.empty()
		if version==18:expected.bindings=expected.bindings.filter(func(binding:Dictionary)->bool:return int(binding.keycode)!=KEY_C)
		expected=Rules.decode(expected);check(Rules.reason(expected).is_empty(),"Intermediate expected candidate valid")
		var chain_path:="user://chain%d-"%version+fixture.get_file();write(chain_path,bytes);var store:=Store.new()
		check(store.load_build(chain_path) and store.snapshot()==expected and store.successful_saves==1,"Released intermediate chain preserves exact fields "+str(version))
		check(FileAccess.get_file_as_bytes(chain_path+".v%d-backup.json"%version)==bytes,"Chain keeps actual original-version byte backup")
		if version==24:
			var source:=Rules.decode_v24(raw);var intermediate:=Prior.migrate_v24(source);var v25:=source.duplicate(true);v25.version=25
			check(intermediate==v25 and Rules.reason_v25(intermediate).is_empty() and Rules.decode(intermediate).is_empty(),"Prior leech migration pinned to25 with frozen envelope")
	var legacy:=Store.Legacy.new()._snapshot();var legacy_bytes:=PackedByteArray([239,187,191])+JSON.stringify(legacy,"  ").to_utf8_buffer();write("user://legacy13.json",legacy_bytes)
	var legacy_store:=Store.new();check(legacy_store.load_build("user://legacy13.json") and legacy_store.snapshot().version==26 and legacy_store.snapshot().journey==Journey.empty() and legacy_store.successful_saves==1,"Complete13-through26 chain commits once")
	check(FileAccess.get_file_as_bytes("user://legacy13.json.v13-backup.json")==legacy_bytes,"Full chain backs up original13 BOM bytes only")
	print("Normal journey migration: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
