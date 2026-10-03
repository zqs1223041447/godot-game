extends SceneTree
## Independent integration acceptance. Uses only isolated fixture files and the
## public model transactions; it never opens UI or touches a player's directory.
const State = preload("res://scripts/canonical_game_state.gd")
var checks := 0
var failures := 0

class FaultState extends "res://scripts/canonical_game_state.gd":
	var deny_write := false
	func _write_bytes(path: String,bytes: PackedByteArray)->Error:
		return ERR_CANT_CREATE if deny_write else super._write_bytes(path,bytes)

func _initialize()->void: call_deferred("run")

func run()->void:
	var data_root := OS.get_environment("XDG_DATA_HOME")
	if not data_root.begins_with("/tmp/godot-v022-currency-review-") or State.Rules.VERSION != 16:
		quit(78); return
	for amount: int in [0,27,1000000000]: _migration(amount)
	_literal_v14()
	_rejection_and_failure()
	_quote_and_quantity()
	_no_uid_reuse()
	print("Independent currency acceptance: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func fixture(amount: int)->PackedByteArray:
	return FileAccess.get_file_as_bytes("res://tests/fixtures/v022_currency/v15-wallet-%d.json"%amount)

func put(path: String,bytes: PackedByteArray)->void:
	var f := FileAccess.open(path,FileAccess.WRITE); f.store_buffer(bytes); f.close()

func total(value: Dictionary,only_bag: bool = false)->int:
	var result := 0
	for uid: String in value.items:
		if value.items[uid].kind == "currency" and (not only_bag or value.locations[uid].kind == "bag"):
			result += int(value.items[uid].payload.quantity)
	return result

func _migration(amount: int)->void:
	var path := "user://wallet_%d.json"%amount
	var original := fixture(amount)
	put(path,original)
	# Compare semantic typed snapshots using the frozen old decoder; raw JSON
	# numbers are floats, whereas the save adapter restores declared integers.
	var old: Dictionary = State.Rules.decode_v15(JSON.parse_string(original.get_string_from_utf8()))
	var model = State.new()
	check(model.load_build(path),"Valid v15 amount %d migrates"%amount)
	var migrated: Dictionary = model.snapshot()
	check(migrated.version == 16 and not migrated.crafting.has("materials"),"v16 has one persistent item authority, no wallet")
	check(FileAccess.get_file_as_bytes(path+".v15-backup.json")==original,"Migration preserves exact v15 bytes and spacing")
	check(total(migrated)==amount and model.crafting_balance()==amount,"Every old shard appears in an owned bag stack")
	for key: String in ["progress","talents","skill_groups","bindings","migration_ledger"]:
		check(migrated[key]==old[key],"Migration does not change "+key)
	check(migrated.crafting.revision==old.crafting.revision,"Migration keeps craft seed revision")
	for uid: String in old.items:
		check(migrated.items.has(uid) and migrated.items[uid]==old.items[uid] and migrated.locations[uid]==old.locations[uid],"Existing UID/payload/location preserved: "+uid)
	var before := model.snapshot()
	check(model.load_build(path) and model.snapshot()==before,"Reload does not mint another stack or refund points")

func _rejection_and_failure()->void:
	var path := "user://failed_migration.json"
	var original := fixture(27);put(path,original)
	var fault := FaultState.new();fault.deny_write=true
	var before := fault.snapshot()
	check(not fault.load_build(path) and fault.snapshot()==before and FileAccess.get_file_as_bytes(path)==original,"Migration write failure keeps original bytes and memory")
	check(FileAccess.get_file_as_bytes(path+".v15-backup.json")==original,"Failed replacement still retains completed raw backup")
	fault.deny_write=false
	check(fault.load_build(path) and total(fault.snapshot())==27,"Same original and existing byte backup can be retried after write recovery")
	var future := "user://future.json";var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/v022_currency/future-v17.json");put(future,bytes)
	var model = State.new();before=model.snapshot()
	check(not model.load_build(future) and model.save_build(future)!=OK and model.snapshot()==before and FileAccess.get_file_as_bytes(future)==bytes,"Future save protection survives currency migration")
	var conflict := "user://conflict.json";put(conflict,original);put(conflict+".v15-backup.json","different backup".to_utf8_buffer())
	check(not model.load_build(conflict) and FileAccess.get_file_as_bytes(conflict)==original,"Backup conflict cannot overwrite a valid old source")
	var injected: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	injected.items["review_currency"]={"uid":"review_currency","kind":"currency","definition_id":"currency:calibration_shard","payload":{"quantity":4}}
	injected.locations["review_currency"]={"kind":"recovery","index":0}
	var injected_path := "user://currency_in_v15.json"
	var injected_bytes := JSON.stringify(injected,"\t",true,true).to_utf8_buffer();put(injected_path,injected_bytes)
	check(not model.load_build(injected_path) and FileAccess.get_file_as_bytes(injected_path)==injected_bytes,"New currency kind cannot be injected under a v15 version tag")
	# Prove the envelope/location is otherwise acceptable to the new schema.
	injected.version=16;injected.crafting.erase("materials")
	check(State.Rules.reason(State.Rules.decode(injected)).is_empty(),"Same currency envelope is a valid v16 positive control")

func _literal_v14()->void:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/v022_currency/v14-original-bytes.json")
	var old: Dictionary = State.Rules.decode_v14(JSON.parse_string(bytes.get_string_from_utf8()))
	var path := "user://literal_v14.json";put(path,bytes)
	var model = State.new()
	check(model.load_build(path) and model.snapshot().version==16,"Published v14 fixture reaches v16 through one load")
	check(FileAccess.get_file_as_bytes(path+".v14-backup.json")==bytes,"v14 original bytes, not an intermediate v15 rewrite, are backed up")
	var value: Dictionary = model.snapshot()
	for key: String in ["items","talents","progress","bindings","skill_groups","migration_ledger"]:
		check(value[key]==old[key],"Zero-wallet v14 preserves "+key+" while only bag coordinates migrate")

func _quote_and_quantity()->void:
	var path := "user://craft.json";put(path,fixture(27))
	var model := FaultState.new()
	check(model.load_build(path),"Craft fixture migrated through the real store")
	var rng := RandomNumberGenerator.new();rng.seed=220003
	var uid: String = model.award_equipment(rng,30,"rare")
	check(not uid.is_empty() and model.save_build(path)==OK,"Real catalog equipment is saved before quoting")
	var quote: Dictionary = model.crafting_quote("salvage",uid,path)
	check(bool(quote.get("ok",false)),"Salvage quote reads the item-backed balance")
	if not quote.get("ok",false):return
	var before := model.snapshot();var disk := FileAccess.get_file_as_bytes(path)
	var incoming: int = int(quote.materials.get("calibration_shard",0))
	var calls := [0];model.changed.connect(func():calls[0]+=1)
	model.deny_write=true
	var failed: Dictionary = model.execute_crafting(quote.handle,quote.source_instance)
	check(not failed.ok and model.snapshot()==before and FileAccess.get_file_as_bytes(path)==disk and calls[0]==0,"Failed crafting write changes no quantity, item, revision, bytes or signal")
	model.deny_write=false
	var result: Dictionary = model.execute_crafting(quote.handle,quote.source_instance)
	check(result.ok and total(model.snapshot())==27+incoming and not model.snapshot().items.has(uid) and calls[0]==1,"Same quote retry commits exact shard gain and one changed")
	var accepted := model.snapshot()
	check(not model.execute_crafting(quote.handle,quote.source_instance).ok and model.snapshot()==accepted,"Repeated confirmation cannot duplicate shards")
	check(FileAccess.get_file_as_bytes(path)==JSON.stringify(accepted,"\t",true,true).to_utf8_buffer(),"Persisted full snapshot exactly matches committed item counts")

func check(ok: bool,label: String)->void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func _no_uid_reuse()->void:
	var model = State.new()
	var path := "user://currency-identities.json"
	var rng := RandomNumberGenerator.new();rng.seed=220009
	var a: String = model.award_equipment(rng,30,"rare")
	var b: String = model.award_equipment(rng,30,"rare")
	check(not a.is_empty() and not b.is_empty() and model.save_build(path)==OK,"Two actual random items prepare currency identity lifecycle")
	var quote: Dictionary = model.crafting_quote("salvage",a,path)
	check(quote.get("ok",false) and model.execute_crafting(quote.handle,quote.source_instance).ok,"First salvage creates a real stack")
	var old_uid := ""
	for uid: String in model.snapshot().items:
		if model.item(uid).kind == "currency": old_uid=uid
	check(not old_uid.is_empty() and model.discard_item(old_uid,model.revision(),path).ok,"Discard transaction consumes the first stack identity")
	quote=model.crafting_quote("salvage",b,path)
	check(quote.get("ok",false) and model.execute_crafting(quote.handle,quote.source_instance).ok,"A later salvage creates new owned currency")
	var new_uid := ""
	for uid: String in model.snapshot().items:
		if model.item(uid).kind == "currency": new_uid=uid
	check(not new_uid.is_empty() and new_uid!=old_uid,"A consumed currency instance UID is never recycled for a later item")
