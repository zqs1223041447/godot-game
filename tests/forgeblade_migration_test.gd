extends SceneTree
## Genuine published schema33 bytes, frozen vocabulary and bounded persistence faults.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/forgeblade_migration.gd")
const FasterBurn = preload("res://scripts/save/faster_burn_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const FIXTURES := "res://docs/qa/v055-migration/fixtures/"


class FaultStore extends Store:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)


class BackupFailIO extends Store.Legacy:
	func _backup_legacy_save(_path: String) -> Error:
		return ERR_CANT_CREATE


class ExternalIO extends Store.Legacy:
	func _backup_legacy_save(path: String) -> Error:
		var result := super._backup_legacy_save(path)
		if result == OK:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string("external writer")
			file.close()
		return result


var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func expected_current(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.version = 34
	return result


func rejected_preserving(path: String, bytes: PackedByteArray, version: int) -> void:
	write(path, bytes)
	var store := Store.new()
	var before := store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Rejected input preserves original bytes and memory: " + path)
	check(store.save_attempts == 0 and store.successful_saves == 0 and signals[0] == 0, "Rejected input performs no save or signal")
	check(not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Invalid source receives no migration backup")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected source remains protected from later save")


func test_literal(name: String, manifest: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + name)
	check(bytes.size() == int(manifest.files[name].bytes) and digest(bytes) == manifest.files[name].sha256, "Actual published-v54 serializer bytes and SHA256: " + name)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var source := Rules.decode_v33(raw)
	check(not source.is_empty() and Rules.reason_v33(source).is_empty() and Rules.decode(raw).is_empty(), "Complete frozen33 decoder is distinct from current34")
	if source.is_empty(): return
	var expected := expected_current(source)
	var before := var_to_bytes(source)
	seed(550033)
	var next_rng := randi()
	seed(550033)
	var migrated := Migration.migrate_v33(source)
	check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Migration changes only version; source and RNG stay unchanged")
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Exact field preservation: " + field + " / " + name)
	check(Game._stats_for(migrated) == Game._stats_for(source), "Complete allocated source stats remain exact")
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys(), "UID and location insertion order retained")
	check(Migration.migrate_v33(migrated).is_empty(), "Already migrated envelope cannot be migrated twice")
	migrated.items.clear()
	check(var_to_bytes(source) == before, "Migrated nested tables are detached from source")
	if name.contains("active"):
		check(source.talents.allocated.has("11364") and source.talents.allocated.has("43684") and source.talents.allocated.has("59766") and Game._stats_for(source).damaging_ailments_faster > 0.0, "Released fixture includes actual v54 faster-burn allocations")
		check(Store.Currency.total_quantity(source.items).quantity == 100 and source.revision > 0 and source.bindings[0].keycode != KEY_1, "Released fixture includes real currency, revision and changed group binding")
	var path := "user://literal-" + name
	write(path, bytes)
	var store := Store.new()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and store.successful_saves == 1 and signals[0] == 1, "Exactly one durable migration and notification")
	check(FileAccess.get_file_as_bytes(path + ".v33-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Backup matches raw published save bytes exactly")
	var disk := FileAccess.get_file_as_bytes(path)
	check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated current load performs no rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v33-backup.json") == bytes, "Independent strict34 reopen preserves content and raw backup")


func with_forgeblade(source: Dictionary) -> Dictionary:
	var candidate := source.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 550034
	var uid := "gear_%06d" % int(candidate.next_item_serial)
	var gear := Equipment.generate_for_pool(rng, uid, 16, "rare", "forgeblade_v34")
	check(not gear.is_empty(), "New profile creates a legal forgeblade fixture")
	candidate.items[uid] = Store.Items.wrap_equipment(gear)
	var recovery_index := 0
	for location: Dictionary in candidate.locations.values():
		if location.kind == "recovery": recovery_index += 1
	candidate.locations[uid] = {"kind":"recovery", "index":recovery_index}
	candidate.next_item_serial += 1
	return candidate


func test_frozen_vocabulary(source: Dictionary) -> void:
	var injected := with_forgeblade(source)
	var current := expected_current(injected)
	check(Rules.reason(current).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(current))) == current, "Forgeblade is independently valid in current34")
	# Populate current positive metadata cache before checking the older envelope.
	Store.Items.metadata_for_items(current.items)
	check(Rules.decode_v33(injected).is_empty() and not Rules.reason_v33(injected).is_empty() and Migration.migrate_v33(injected).is_empty(), "Frozen33 rejects forgeblade despite current positive cache")
	rejected_preserving("user://old33-injected-forgeblade.json", JSON.stringify(injected).to_utf8_buffer(), 33)
	var native_bad := source.duplicate(true)
	native_bad.talents.allocated.append("unknown_forgeblade_node")
	native_bad.talents.normal_points -= 1
	var allow_all := func(_candidate: Dictionary) -> String: return ""
	check(not Rules.reason_v33(native_bad, allow_all).is_empty() and Migration.migrate_v33(native_bad, allow_all).is_empty(), "Optional caller validator cannot bypass native frozen talent legality")
	for mutation: String in ["future", "duplicate_binding", "fractional_revision", "bool_revision", "extra_field", "missing_journey", "invalid_journey", "duplicate_uid", "unknown_node", "wrong_allocated_type", "unknown_stat", "nan_revision", "nan_mastery"]:
		var bad := source.duplicate(true)
		match mutation:
			"future": bad.version = 35
			"duplicate_binding": bad.bindings.append(bad.bindings[0].duplicate())
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"extra_field": bad.forgeblade_runtime = {}
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"duplicate_uid": bad.items[bad.items.keys()[0]].uid = "wrong_uid"
			"unknown_node": bad.talents.allocated.append("unknown_forgeblade_node"); bad.talents.normal_points -= 1
			"wrong_allocated_type": bad.talents.allocated = {"11364":true}
			"unknown_stat": bad.talents.forgeblade_damage = 10
			"nan_revision": bad.revision = NAN
			"nan_mastery": bad.talents.masteries["123"] = NAN
		check(not Rules.reason_v33(bad).is_empty() and Rules.decode_v33(bad).is_empty() and Migration.migrate_v33(bad).is_empty(), "Complete frozen33 source validation: " + mutation)
		var on_disk := bad.duplicate(true)
		if mutation == "nan_revision": on_disk.revision = null
		if mutation == "nan_mastery": on_disk.talents.masteries["123"] = null
		rejected_preserving("user://invalid33-" + mutation + ".json", JSON.stringify(on_disk).to_utf8_buffer(), int(bad.version))
	for value: Variant in [null, [], true, NAN, INF, 33, "33"]:
		check(not Rules.reason_v33(value).is_empty() and Rules.decode_v33(value).is_empty() and Migration.migrate_v33(value).is_empty(), "Wrong envelope type rejected")


func test_failures(source: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + "v33-default.json")
	var expected := expected_current(source)
	var conflict_path := "user://backup-collision.json"
	write(conflict_path, bytes)
	var other := "retained backup".to_utf8_buffer()
	write(conflict_path + ".v33-backup.json", other)
	var conflict := Store.new()
	var before := conflict.snapshot()
	check(not conflict.load_build(conflict_path) and conflict.snapshot() == before and conflict.save_attempts == 0 and FileAccess.get_file_as_bytes(conflict_path) == bytes and FileAccess.get_file_as_bytes(conflict_path + ".v33-backup.json") == other, "Conflicting backup and source never overwritten")
	check(conflict.save_build(conflict_path) != OK, "Backup conflict protects later save")
	var backup_path := "user://backup-fail.json"
	write(backup_path, bytes)
	var backup := Store.new()
	backup._io = BackupFailIO.new()
	before = backup.snapshot()
	check(not backup.load_build(backup_path) and backup.snapshot() == before and FileAccess.get_file_as_bytes(backup_path) == bytes and backup.save_attempts == 0, "Backup failure prevents primary commit")
	var external_path := "user://external.json"
	write(external_path, bytes)
	var external := Store.new()
	external._io = ExternalIO.new()
	before = external.snapshot()
	check(not external.load_build(external_path) and external.snapshot() == before and FileAccess.get_file_as_string(external_path) == "external writer" and external.save_attempts == 0 and FileAccess.get_file_as_bytes(external_path + ".v33-backup.json") == bytes, "Concurrent source edit during backup remains untouched")
	var path := "user://real-atomic-fail.json"
	write(path, bytes)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Real atomic-temp collision created in isolated user directory")
	var store := Store.new()
	before = store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes and signals[0] == 0 and store.successful_saves == 0 and store.save_attempts == 1, "Real atomic-write failure preserves file, memory and notification count")
	check(FileAccess.get_file_as_bytes(path + ".v33-backup.json") == bytes, "Failed commit retains exact original backup")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove isolated failure injection")
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and signals[0] == 1, "Same-backup retry commits exactly once")
	var current_path := "user://retained-current.json"
	var current_bytes := JSON.stringify(expected).to_utf8_buffer()
	write(current_path, current_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(current_path), "Accept current34 receipt before a failed old load")
	var failed_path := "user://failed-replacement.json"
	write(failed_path, bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == expected and retained._path == current_path and retained._disk_bytes == current_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Failed old load retains previously accepted memory and disk receipt")
	var message_path := "user://message.json"
	write(message_path, bytes)
	var game := Game.new()
	check(game.load_build(message_path) and game.migrated_from_legacy and game.migration_message.contains("短刃") and not game.migration_message.contains("两瓶药剂"), "Schema33 migration message accurately describes equipment vocabulary without legacy grants")


func test_current_roundtrip(source: Dictionary) -> void:
	var candidate := expected_current(with_forgeblade(source))
	var store := Store.new()
	store._accept_memory(candidate)
	var path := "user://current34-forgeblade.json"
	check(store.save_build(path) == OK and Rules.reason(candidate).is_empty(), "Current34 with forgeblade saves")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == candidate and reopened.save_attempts == 0, "Current34 forgeblade round-trip preserves all fields without migration")
	var uid := "gear_%06d" % (int(candidate.next_item_serial) - 1)
	var destination := reopened.first_bag_position(uid)
	check(not destination.is_empty(), "Current fixture has an actual bag destination")
	var bytes := FileAccess.get_file_as_bytes(path)
	var signals := [0]
	reopened.changed.connect(func(): signals[0] += 1)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create current transaction atomic-write collision")
	check(not reopened.move_item(uid, destination, reopened.revision(), path).ok and reopened.snapshot() == candidate and FileAccess.get_file_as_bytes(path) == bytes and reopened._disk_bytes == bytes and signals[0] == 0, "Failed current item movement preserves UID, layout, currency, revision and receipt")
	check(DirAccess.remove_absolute(path + ".tmp") == OK and reopened.move_item(uid, destination, reopened.revision(), path).ok and reopened.revision() == candidate.revision + 1 and signals[0] == 1, "Recoverable current transaction retries exactly once")
	var accepted := reopened.snapshot()
	bytes = FileAccess.get_file_as_bytes(path)
	write(path, "external after commit".to_utf8_buffer())
	check(reopened.save_build(path) == ERR_FILE_ALREADY_IN_USE and reopened.snapshot() == accepted and reopened._disk_bytes == bytes and FileAccess.get_file_as_string(path) == "external after commit", "Current receipt protects external disk edits")


func test_prior_chain(source: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v054-source/fixtures/v32-default.json")
	var old32 := Rules.decode_v32(JSON.parse_string(bytes.get_string_from_utf8()))
	var old33 := FasterBurn.migrate_v32(old32)
	var expected33 := old32.duplicate(true)
	expected33.version = 33
	check(old33 == expected33 and Rules.reason_v33(old33).is_empty(), "Prior faster-burn migration remains frozen at33 after current VERSION becomes34")
	check(Migration.migrate_v33(old33) == expected_current(old32), "32 to33 to34 only changes version")
	var path := "user://prior32.json"
	write(path, bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot() == expected_current(old32), "Genuine historical32 source traverses complete remaining chain")
	check(store.save_attempts == 1 and store.successful_saves == 1 and FileAccess.get_file_as_bytes(path + ".v32-backup.json") == bytes and not FileAccess.file_exists(path + ".v33-backup.json"), "Prior32 chain commits once and backs up original32 bytes only")
	var fresh := Store.new().snapshot()
	check(fresh == expected_current(source) and Rules.reason(fresh).is_empty(), "Built-in full history reaches34 with exactly the published33 default content")
	check(Store.Currency.total_quantity(fresh.items).quantity == 0, "Fresh chain has no currency or forgeblade grant")
	var injected32 := with_forgeblade(old32)
	check(Rules.decode_v32(injected32).is_empty() and FasterBurn.migrate_v32(injected32).is_empty(), "Earlier frozen32 boundary also rejects new equipment")


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-v055-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	check(Rules.VERSION == 34 and Rules.V33_VERSION == 33 and Equipment.CURRENT_VOCABULARY == 34 and Rules.SourceTree.CURRENT_SAVE_VERSION == 33 and Rules.SourceTree._execution_policy(34) == 33, "Schema34 changes equipment vocabulary and retains source execution policy33")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "manifest.json"))
	for name: String in ["v33-default.json", "v33-active-allocated.json"]: test_literal(name, manifest)
	var source := Rules.decode_v33(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v33-default.json")))
	test_frozen_vocabulary(source)
	test_failures(source)
	test_current_roundtrip(source)
	test_prior_chain(source)
	print("Forgeblade schema migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
