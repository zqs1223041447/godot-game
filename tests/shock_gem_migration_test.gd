extends SceneTree
## Literal released-v51 schema30 migration, strict vocabulary and persistence faults.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/shock_gem_migration.gd")
const ThirdMap = preload("res://scripts/save/third_map_migration.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const FIXTURES := "res://docs/qa/v052-shock-integration/fixtures/"


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
	result.version = 31
	return result


func rejected_preserving(path: String, bytes: PackedByteArray, version: int) -> void:
	write(path, bytes)
	var store := Store.new()
	var initial := store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes, "Invalid input preserves bytes and memory: " + path)
	check(store.save_attempts == 0 and store.successful_saves == 0 and signals[0] == 0, "Invalid input reaches no primary write or signal")
	check(not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Invalid vocabulary never creates backup")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected old input stays protected")


func test_literal(name: String, manifest: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + name)
	check(bytes.size() == int(manifest.files[name].bytes) and digest(bytes) == manifest.files[name].sha256 and bytes.get_string_from_utf8().begins_with(" \r\n"), "Released-v51 literal bytes and raw SHA256: " + name)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var source := Rules.decode_v30(raw)
	check(not source.is_empty() and Rules.reason_v30(source).is_empty() and Rules.decode(raw).is_empty(), "Complete frozen30 decoder and current31 separation")
	if source.is_empty(): return
	var expected := expected_current(source)
	var before := var_to_bytes(source)
	seed(520031)
	var next_rng := randi()
	seed(520031)
	var migrated := Migration.migrate_v30(source)
	check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Migration changes only version; source/RNG immutable")
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Exact preservation of " + field + ": " + name)
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys(), "Item and location insertion order retained")
	check(Migration.migrate_v30(migrated).is_empty(), "Migration rejects repeated/current envelope")
	migrated.journey.best_tiers.sunwell_terrace = 3
	check(var_to_bytes(source) == before, "Candidate journey detached from original")
	var path := "user://literal-" + name
	write(path, bytes)
	var store := Store.new()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and store.save_attempts == 1 and signals[0] == 1, "One durable migration and notification")
	check(FileAccess.get_file_as_bytes(path + ".v30-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Raw original CRLF backup and atomic commit")
	var disk := FileAccess.get_file_as_bytes(path)
	check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated current load does not rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v30-backup.json") == bytes, "Independent strict31 reopen preserves content and backup")


func test_vocabulary(source: Dictionary) -> void:
	var injection := source.duplicate(true)
	var uid := "item_%06d" % int(injection.next_item_serial)
	injection.next_item_serial += 1
	injection.items[uid] = Gems.create_instance(uid, "support:shock")
	var recovery_count := 0
	for location: Dictionary in injection.locations.values():
		if location.kind == "recovery": recovery_count += 1
	injection.locations[uid] = {"kind": "recovery", "index": recovery_count}
	var current := expected_current(injection)
	check(Rules.reason(current).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(current))) == current, "Injected gem fixture otherwise valid under exact current31")
	check(Rules.decode_v30(injection).is_empty() and not Rules.reason_v30(injection).is_empty() and Migration.migrate_v30(injection).is_empty(), "Old30 cannot launder Shock through current catalog")
	rejected_preserving("user://old30-injected-shock.json", JSON.stringify(injection).to_utf8_buffer(), 30)
	for mutation: String in ["future", "duplicate_binding", "fractional_revision", "bool_revision", "extra_field", "missing_journey", "invalid_journey", "duplicate_uid"]:
		var bad := source.duplicate(true)
		match mutation:
			"future": bad.version = 32
			"duplicate_binding": bad.bindings.append(bad.bindings[0].duplicate())
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"extra_field": bad.shock_runtime = {}
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"duplicate_uid": bad.items[bad.items.keys()[0]].uid = "wrong_uid"
		check(not Rules.reason_v30(bad).is_empty() and Migration.migrate_v30(bad).is_empty(), "Strict old30 full validation rejects " + mutation)
		rejected_preserving("user://invalid30-" + mutation + ".json", JSON.stringify(bad).to_utf8_buffer(), int(bad.version))


func test_failures(source: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + "v30-default.json")
	var expected := expected_current(source)
	var conflict_path := "user://backup-collision.json"
	write(conflict_path, bytes)
	var other := "retained backup".to_utf8_buffer()
	write(conflict_path + ".v30-backup.json", other)
	var conflict := Store.new()
	var initial := conflict.snapshot()
	check(not conflict.load_build(conflict_path) and conflict.snapshot() == initial and conflict.save_attempts == 0 and FileAccess.get_file_as_bytes(conflict_path) == bytes and FileAccess.get_file_as_bytes(conflict_path + ".v30-backup.json") == other, "Conflicting backup never overwritten")
	check(conflict.save_build(conflict_path) != OK, "Backup conflict protects later save")
	var backup_path := "user://backup-fail.json"
	write(backup_path, bytes)
	var backup := Store.new()
	backup._io = BackupFailIO.new()
	initial = backup.snapshot()
	check(not backup.load_build(backup_path) and backup.snapshot() == initial and FileAccess.get_file_as_bytes(backup_path) == bytes and backup.save_attempts == 0, "Backup failure prevents commit")
	var external_path := "user://external.json"
	write(external_path, bytes)
	var external := Store.new()
	external._io = ExternalIO.new()
	initial = external.snapshot()
	check(not external.load_build(external_path) and external.snapshot() == initial and FileAccess.get_file_as_string(external_path) == "external writer" and external.save_attempts == 0 and FileAccess.get_file_as_bytes(external_path + ".v30-backup.json") == bytes, "Concurrent source change during backup stays untouched")
	var path := "user://real-atomic-fail.json"
	write(path, bytes)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Isolated real atomic-temp collision created")
	var store := Store.new()
	initial = store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes and signals[0] == 0 and store.successful_saves == 0 and store.save_attempts == 1, "Real write failure preserves primary file and memory")
	check(FileAccess.get_file_as_bytes(path + ".v30-backup.json") == bytes, "Failed commit retains original raw backup")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove isolated failure injection")
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and signals[0] == 1, "Same-backup retry succeeds exactly once")
	var disk := FileAccess.get_file_as_bytes(path)
	write(path, "external after migration".to_utf8_buffer())
	check(store.save_build(path) == ERR_FILE_ALREADY_IN_USE and store.snapshot() == expected and store._disk_bytes == disk and FileAccess.get_file_as_string(path) == "external after migration", "Current receipt protects later external edits")
	var current_path := "user://retained-current.json"
	var current_bytes := JSON.stringify(expected).to_utf8_buffer()
	write(current_path, current_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(current_path), "Accept current31 receipt before failed old load")
	var failed_path := "user://failed-replacement.json"
	write(failed_path, bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == expected and retained._path == current_path and retained._disk_bytes == current_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Primary write failure retains previously accepted receipt")
	var message_path := "user://message.json"
	write(message_path, bytes)
	var game := Game.new()
	check(game.load_build(message_path) and game.migrated_from_legacy and game.migration_message.contains("感电辅助") and not game.migration_message.contains("两瓶药剂"), "Old30 receives accurate non-grant migration message")


func test_prior_chain() -> void:
	var old29 := Rules.decode_v29(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v048-migration/fixtures/v29-active.json")))
	var old30 := ThirdMap.migrate_v29(old29)
	check(old30.version == 30 and Rules.reason_v30(old30).is_empty() and old30.journey.best_tiers.sunwell_terrace == 0, "Previous third-map migration retains frozen30 result")
	check(Migration.migrate_v30(old30) == expected_current(old30), "Frozen29→30→31 chain changes only specified fields")
	for filename: String in ["res://tests/fixtures/v041_journey/v25-default.json", "res://docs/qa/v047-migration/fixtures/v28-active.json", "res://docs/qa/v048-migration/fixtures/v29-active.json"]:
		var bytes := FileAccess.get_file_as_bytes(filename)
		var raw: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
		var version := int(raw.version)
		var path := "user://prior%d.json" % version
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot().version == 31 and Rules.reason(store.snapshot()).is_empty(), "Focused prior%d chain still reaches valid31" % version)
		check(store.save_attempts == 1 and store.successful_saves == 1 and FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % version) == bytes, "Prior chain commits once with original-version bytes")
		check(store.snapshot().items.values().filter(func(item: Dictionary): return item.definition_id == "support:shock").is_empty(), "Prior migration grants no Shock")
	var fresh := Store.new().snapshot()
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v30-vocabulary-oracle.json"))
	check(fresh.version == 31 and fresh.journey == Journey.empty() and Store.Currency.total_quantity(fresh.items).quantity == 0, "Built-in full history chain yields current31 without currency")
	check(Journey.GEM_DEFINITIONS == oracle.gem_definitions and Journey.GEM_DEFINITIONS.size() == 26 and not Journey.GEM_DEFINITIONS.has("support:shock"), "Frozen milestone gem vocabulary unchanged")
	for index: int in oracle.milestones.size():
		check(Journey.gem_definition(index + 1) == oracle.milestones[index], "Released reward ordinal %d remains identical" % (index + 1))
	for id: String in oracle.minimum_save_versions:
		check(Gems.minimum_save_version(id) == int(oracle.minimum_save_versions[id]), "Existing gem save minimum remains unchanged: " + id)


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-v052-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	check(Rules.VERSION == 31 and Rules.V30_VERSION == 30 and Rules.SourceTree.CURRENT_SAVE_VERSION == 25 and Rules.SourceTree._execution_policy(31) == 25, "Schema31 keeps source passive vocabulary frozen25")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "manifest.json"))
	for name: String in ["v30-default.json", "v30-ember-bag.json", "v30-active.json", "v30-pending.json"]:
		test_literal(name, manifest)
	var source := Rules.decode_v30(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v30-default.json")))
	test_vocabulary(source)
	test_failures(source)
	test_prior_chain()
	print("Shock gem migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
