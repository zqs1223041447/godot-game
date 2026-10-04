extends SceneTree
const Store=preload("res://scripts/save/canonical_build_store.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Migration=preload("res://scripts/save/source_leech_migration.gd")
const PriorMigration=preload("res://scripts/save/source_critical_migration.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const LEECH_PATH=["50986","39725","63649","49806","6580","19711","20010","36704"]
class FaultStore extends Store:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
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
func leech_candidate(source:Dictionary)->Dictionary:
	var result:=source.duplicate(true);result.version=25;result.progress.level=119;result.progress.xp=17
	result.talents.class_id=4;result.talents.allocated=LEECH_PATH.duplicate();result.talents.normal_points=116
	return result
func reject_preserving(path:String,bad_bytes:PackedByteArray,version:int)->void:
	write(path,bad_bytes);var store:=Store.new();var initial:=store.snapshot();var signals:=[0];store.changed.connect(func():signals[0]+=1)
	check(not store.load_build(path) and store.snapshot()==initial and FileAccess.get_file_as_bytes(path)==bad_bytes,"Rejected input preserves memory and exact raw source: "+path)
	check(store.save_attempts==0 and store.successful_saves==0 and signals[0]==0 and not FileAccess.file_exists(path+".v%d-backup.json"%version),"Rejection precedes backup, write and notification: "+path)
	check(store.save_build(path)!=OK and FileAccess.get_file_as_bytes(path)==bad_bytes,"Rejected source remains protected against later save: "+path)
func _initialize()->void:
	var xdg:=OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(xdg+"/"):quit(78);return
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v040_leech/manifest.json"))
	check(Store.new().snapshot().version==25 and Rules.VERSION==25,"Fresh store completes the entire chain to25")
	for name:String in ["v24-default.json","v24-critical.json"]:
		var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/v040_leech/"+name)
		check(bytes.size()==int(manifest.files[name].bytes) and digest(bytes)==manifest.files[name].sha256,"Literal fixture matches frozen unmodified d6c8165 source bytes")
		var raw:Variant=JSON.parse_string(bytes.get_string_from_utf8());var source:=Rules.decode_v24(raw)
		check(not source.is_empty() and Rules.reason_v24(source).is_empty() and Rules.decode(raw).is_empty(),"Released literal24 decodes only under frozen24 contract")
		if name=="v24-critical.json":
			check(source.items.has("item_000900") and source.locations.has("item_000900") and source.next_item_serial==901 and source.revision==47 and source.crafting.revision==19,"Literal released fixture contains deliberate changed UID and revision values")
		var transient:=source.duplicate(true);transient.version=25;transient.leech_instances=[]
		reject_preserving("user://current-transient-"+name,JSON.stringify(transient).to_utf8_buffer(),25)
		var before:=var_to_bytes(source);var expected:=source.duplicate(true);expected.version=25
		check(Migration.migrate_v24(source)==expected and var_to_bytes(source)==before,"Pure migration changes only version and leaves caller untouched")
		check(Migration.migrate_v24(expected).is_empty(),"Already-current data cannot enter the old migration")
		var path:="user://leech-"+name;write(path,bytes)
		var store:=Store.new();var signals:=[0];store.changed.connect(func():signals[0]+=1)
		check(store.load_build(path) and store.snapshot()==expected,"Actual store migrates all UID/location/progress/points/binding/revision fields exactly")
		check(store.save_attempts==1 and store.successful_saves==1 and signals[0]==1,"Migration writes and notifies once")
		check(FileAccess.get_file_as_bytes(path+".v24-backup.json")==bytes,"Backup keeps exact original leading whitespace and CRLF")
		var disk:=FileAccess.get_file_as_bytes(path)
		check(Rules.decode(JSON.parse_string(disk.get_string_from_utf8()))==expected,"Committed disk is the exact complete candidate")
		check(store.load_build(path) and store.snapshot()==expected and store.successful_saves==1 and FileAccess.get_file_as_bytes(path)==disk,"Current25 reread never migrates or writes again")
		var conflict_path:="user://conflict-"+name;write(conflict_path,bytes);var other:=PackedByteArray([1,2,3]);write(conflict_path+".v24-backup.json",other)
		var conflict:=Store.new();var initial:=conflict.snapshot()
		check(not conflict.load_build(conflict_path) and conflict.snapshot()==initial and FileAccess.get_file_as_bytes(conflict_path)==bytes and FileAccess.get_file_as_bytes(conflict_path+".v24-backup.json")==other and conflict.save_attempts==0,"Conflicting backup preserves both files and memory")
		check(conflict.save_build(conflict_path)!=OK,"Backup conflict keeps primary save protected")
		var fault_path:="user://fault-"+name;write(fault_path,bytes)
		var fault:=FaultStore.new();initial=fault.snapshot();fault.fail_save=true;var fault_signals:=[0];fault.changed.connect(func():fault_signals[0]+=1)
		check(not fault.load_build(fault_path) and fault.snapshot()==initial and FileAccess.get_file_as_bytes(fault_path)==bytes and fault_signals[0]==0 and fault.successful_saves==0,"Failed migration write exposes no memory or notification")
		check(FileAccess.get_file_as_bytes(fault_path+".v24-backup.json")==bytes,"Failed primary write retains exact original backup")
		fault.fail_save=false
		check(fault.load_build(fault_path) and fault.snapshot()==expected and fault.successful_saves==1 and fault_signals[0]==1,"Matching byte backup permits safe retry of the original source")
		var external_path:="user://external-"+name;write(external_path,bytes)
		var external:=Store.new();external._io=ExternalIO.new();initial=external.snapshot()
		check(not external.load_build(external_path) and external.snapshot()==initial and FileAccess.get_file_as_string(external_path)=="external writer" and external.save_attempts==0,"External rewrite between backup and primary commit is preserved")
		check(FileAccess.get_file_as_bytes(external_path+".v24-backup.json")==bytes,"External rewrite keeps original raw-byte backup")
		for mutation:String in ["future","duplicate_binding","unknown_item","fractional_revision","extra_field","leech_injection"]:
			var bad:=source.duplicate(true)
			if mutation=="future":bad.version=26
			elif mutation=="duplicate_binding":bad.bindings.append(bad.bindings[0].duplicate())
			elif mutation=="unknown_item":bad.items[bad.items.keys()[0]].kind="unknown"
			elif mutation=="fractional_revision":bad.revision=0.5
			elif mutation=="extra_field":bad.leech_instances=1.0
			else:bad=leech_candidate(source);bad.version=24
			reject_preserving("user://%s-%s"%[mutation,name],JSON.stringify(bad).to_utf8_buffer(),int(bad.version))
		var leech:=leech_candidate(source)
		check(Rules.reason(leech).is_empty() and SourceTree.analyze(leech).legal,"Injected24 node is independently proven legal in25")
		var old:=leech.duplicate(true);old.version=24
		check(not Rules.reason_v24(old).is_empty() and Migration.migrate_v24(old).is_empty(),"Strict old vocabulary rejects new allocation before migration")
		check(SourceTree.node_effect("36704",0,24).status!="full" and SourceTree.node_effect("36704",0,25).status=="full" and Rules.reason(leech).is_empty(),"Node and analysis cache retain both policy boundaries")
		var transaction_path:="user://current-"+name;var transaction:=FaultStore.new();transaction._accept_memory(expected);check(transaction.save_build(transaction_path)==OK,"Persist current25 before transactional source edit")
		var original:=transaction.snapshot();disk=FileAccess.get_file_as_bytes(transaction_path);leech.revision=original.revision+1;transaction.fail_save=true
		check(not transaction._commit(leech,transaction_path).ok and transaction.snapshot()==original and FileAccess.get_file_as_bytes(transaction_path)==disk,"Failed new-node save retains complete old build and disk")
		transaction.fail_save=false;check(transaction._commit(leech,transaction_path).ok,"Same new-node candidate commits after recoverable failure")
		var loaded:=Store.new();check(loaded.load_build(transaction_path) and loaded.snapshot()==leech,"Current leech allocation survives exact save/reload")
		write(transaction_path,"external current replacement".to_utf8_buffer());initial=loaded.snapshot()
		check(loaded.save_build(transaction_path)==ERR_FILE_ALREADY_IN_USE and loaded.snapshot()==initial and FileAccess.get_file_as_string(transaction_path)=="external current replacement","Current save also respects external write protection")
	# Actual released intermediate fixtures must reach25 while retaining source-version backups.
	for fixture:String in ["v028_town/v18-c-bound.json","v032_spatial/v19-allocated.json","v033_recharge/v20-spatial.json","v034_cost/v21-allocated.json","v035_flasks/v22-cost.json","v039_critical/v23-default.json","v039_critical/v23-flasks.json"]:
		var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/"+fixture);var raw:Dictionary=JSON.parse_string(bytes.get_string_from_utf8());var version:int=int(raw.version)
		var expected:=raw.duplicate(true);expected.version=25
		if version==18:expected.bindings=expected.bindings.filter(func(binding:Dictionary)->bool:return int(binding.keycode)!=KEY_C)
		expected=Rules.decode(expected);check(Rules.reason(expected).is_empty(),"Intermediate expected candidate remains valid")
		var path:="user://chain%d-"%version+fixture.get_file();write(path,bytes);var store:=Store.new()
		check(store.load_build(path) and store.snapshot()==expected and store.successful_saves==1,"Full loader chain preserves released intermediate"+str(version))
		check(FileAccess.get_file_as_bytes(path+".v%d-backup.json"%version)==bytes,"Chain retains actual original-version byte backup")
		if version==23:
			var source:=Rules.decode_v23(raw);var intermediate:=PriorMigration.migrate_v23(source);var v24:=source.duplicate(true);v24.version=24
			check(intermediate==v24 and Rules.reason_v24(intermediate).is_empty(),"Prior critical migration is pinned to24 rather than jumping directly to25")
	# Each released source format rejects newly executable leech nodes BEFORE any backup/write.
	for fixture:String in ["v022_currency/v14-original-bytes.json","v022_currency/v15-wallet-27.json","performance/crowded-inventory-v16.json","v026_flasks/released-v17-two-offense.json","v028_town/v18-no-c.json","v032_spatial/v19-default.json","v033_recharge/v20-default.json","v034_cost/v21-default.json","v035_flasks/v22-default.json","v039_critical/v23-default.json","v040_leech/v24-default.json"]:
		var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/"+fixture));var version:int=int(raw.version)
		var old:Dictionary=Rules.new().call("decode_v%d"%version,raw)
		check(not old.is_empty() and Rules.new().call("reason_v%d"%version,old).is_empty(),"Actual released old fixture is valid before leech injection at version"+str(version))
		var injected:=leech_candidate(old);injected.version=version
		check(not Rules.new().call("reason_v%d"%version,injected).is_empty(),"Old boundary rejects leech node at version"+str(version))
		reject_preserving("user://leech-injected%d.json"%version,JSON.stringify(injected).to_utf8_buffer(),version)
	# The built-in schema13 source exercises every older link, without user-save access.
	var legacy:=Store.Legacy.new()._snapshot();var legacy_bytes:=PackedByteArray([239,187,191])+JSON.stringify(legacy,"  ").to_utf8_buffer();write("user://legacy13.json",legacy_bytes)
	var legacy_store:=Store.new();check(legacy_store.load_build("user://legacy13.json") and legacy_store.snapshot().version==25 and legacy_store.successful_saves==1,"Complete13-through25 chain ends in one atomic commit")
	check(FileAccess.get_file_as_bytes("user://legacy13.json.v13-backup.json")==legacy_bytes,"Entire chain backs up original13 BOM bytes only")
	print("Source leech migration: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
