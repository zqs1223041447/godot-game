extends SceneTree
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/third_map_migration.gd")
const EmberMigration = preload("res://scripts/save/ember_gem_migration.gd")
const IgniteMigration = preload("res://scripts/save/ignite_gem_migration.gd")
const EquipmentMigration = preload("res://scripts/save/equipment_affix_migration.gd")
const Prior = preload("res://scripts/save/normal_journey_migration.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const FIXTURES := "res://docs/qa/v048-migration/fixtures/"
const MAP_ID := "sunwell_terrace"


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


func rejected_preserving(path: String, bytes: PackedByteArray, version: int, existing_backup: bool = false) -> void:
	write(path, bytes)
	var backup_path := path + ".v%d-backup.json" % version
	var sentinel := "previous original byte backup\r\n".to_utf8_buffer()
	if existing_backup: write(backup_path, sentinel)
	var store := Store.new()
	var initial := store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes, "Invalid input preserves source and memory: " + path)
	check(store.save_attempts == 0 and store.successful_saves == 0 and signals[0] == 0, "Invalid input reaches no primary write or signal: " + path)
	check(FileAccess.get_file_as_bytes(backup_path) == sentinel if existing_backup else not FileAccess.file_exists(backup_path), "Invalid input cannot create/overwrite a backup: " + path)
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Invalid source stays protected: " + path)


func expected_current(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.version = 30
	result.journey.best_tiers[MAP_ID] = 0
	return result


func test_literal(name: String, manifest: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + name)
	check(bytes.size() == int(manifest.files[name].bytes) and digest(bytes) == manifest.files[name].sha256 and bytes.get_string_from_utf8().begins_with(" \r\n"), "Released v47 literal bytes and digest: " + name)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var source := Rules.decode_v29(raw)
	check(not source.is_empty() and Rules.reason_v29(source).is_empty() and Rules.decode(raw).is_empty(), "Frozen schema29 complete envelope: " + name)
	if source.is_empty(): return
	var expected := expected_current(source)
	var input_bytes := var_to_bytes(source)
	seed(480030)
	var next_rng := randi()
	seed(480030)
	var migrated := Migration.migrate_v29(source)
	check(randi() == next_rng and migrated == expected and var_to_bytes(source) == input_bytes, "Only version30 and new map zero; immutable source and RNG: " + name)
	for field: String in Rules.FIELDS:
		if field not in ["version", "journey"]: check(migrated[field] == source[field], "Preserve " + field + ": " + name)
	var preserved: Dictionary = migrated.journey.duplicate(true)
	preserved.best_tiers.erase(MAP_ID)
	check(preserved == source.journey and migrated.journey.best_tiers[MAP_ID] == 0, "Exact old tiers, active run, pending reward and claimed ordinals survive: " + name)
	check(Migration.migrate_v29(migrated).is_empty(), "Migration cannot run twice: " + name)
	check(Journey.start(migrated.journey, Maps.compile_normal(MAP_ID, 2, [], []).profile).ok == false, "New tierII cannot inherit old progression: " + name)
	var path := "user://literal-" + name
	write(path, bytes)
	var store := Store.new()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and store.save_attempts == 1 and signals[0] == 1, "One persisted migration and notification: " + name)
	check(FileAccess.get_file_as_bytes(path + ".v29-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Exact raw backup, atomic commit: " + name)
	var disk := FileAccess.get_file_as_bytes(path)
	check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated current load does not rewrite: " + name)
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v29-backup.json") == bytes, "Independent current reopen preserves all bytes: " + name)


func test_validation(source: Dictionary) -> void:
	var old_journey: Dictionary = source.journey.duplicate(true)
	check(Journey.reason_legacy(old_journey).is_empty() and Journey.decode_legacy(old_journey) == old_journey, "Frozen two-map journey accepts released29")
	check(not Journey.reason(old_journey).is_empty() and Journey.decode(old_journey).is_empty(), "Current30 requires explicit third map record")
	var current := expected_current(source)
	check(Rules.reason(current).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(current))) == current, "Current30 decodes a three-map envelope")
	for bad_value: Variant in [true, false, 0.5, "0", null, -1, 4]:
		var bad := current.duplicate(true)
		bad.journey.best_tiers[MAP_ID] = bad_value
		check(not Rules.reason(bad).is_empty() and Rules.decode(bad).is_empty(), "Reject malformed third-map tier: " + str(bad_value))
		if bad_value is bool or bad_value is float: rejected_preserving("user://bad30-" + str(bad_value) + ".json", JSON.stringify(bad).to_utf8_buffer(), 30)
	var direct_float := current.duplicate(true)
	direct_float.journey.best_tiers[MAP_ID] = 0.0
	check(not Rules.reason(direct_float).is_empty() and Rules.decode(direct_float) == current, "JSON whole floats normalize; direct planners require integer tiers")
	for mutation: String in ["new_key", "new_active", "new_pending", "extra_key", "missing_key", "duplicate_binding", "fractional_revision", "invalid_item", "future"]:
		var bad := source.duplicate(true)
		match mutation:
			"new_key": bad.journey.best_tiers[MAP_ID] = 0
			"new_active":
				bad.journey.next_run_id = 2
				bad.journey.active_run = {"run_id": 1, "map_id": MAP_ID, "tier": 1, "normal_ids": [], "special_ids": [], "fee_paid": 0}
			"new_pending":
				bad.journey.next_run_id = 2
				bad.journey.pending_map_reward = {"run_id": 1, "map_id": MAP_ID, "tier": 1, "shards": 4}
			"extra_key": bad.journey.best_tiers.other_map = 0
			"missing_key": bad.journey.best_tiers.erase("old_garden")
			"duplicate_binding": bad.bindings.append(bad.bindings[0].duplicate())
			"fractional_revision": bad.revision = 0.5
			"invalid_item": bad.items[bad.items.keys()[0]].uid = "missing_identity"
			"future": bad.version = 31
		check(not Rules.reason_v29(bad).is_empty() and Migration.migrate_v29(bad).is_empty(), "Original29 full precondition rejects " + mutation)
		if mutation not in ["duplicate_binding", "invalid_item"]: check(Rules.decode_v29(bad).is_empty(), "Frozen29 decoder rejects " + mutation)
		rejected_preserving("user://invalid29-" + mutation + ".json", JSON.stringify(bad).to_utf8_buffer(), int(bad.version), mutation == "new_key")
	for field: String in ["active_run", "pending_map_reward"]:
		var alias := current.duplicate(true)
		alias.journey.next_run_id = 2
		alias.journey.best_tiers[MAP_ID] = 1
		alias.journey[field] = {"run_id": 1, "map_id": "Sunwell_Terrace", "tier": 1, "normal_ids": [], "special_ids": [], "fee_paid": 0} if field == "active_run" else {"run_id": 1, "map_id": "Sunwell_Terrace", "tier": 1, "shards": 4}
		check(not Rules.reason(alias).is_empty() and Rules.decode(alias).is_empty(), "Current map identity rejects aliases in " + field)


func test_failures(source: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + "v29-default.json")
	var expected := expected_current(source)
	var conflict_path := "user://backup-collision.json"
	write(conflict_path, bytes)
	var other := "retained backup".to_utf8_buffer()
	write(conflict_path + ".v29-backup.json", other)
	var conflict := Store.new()
	var initial := conflict.snapshot()
	check(not conflict.load_build(conflict_path) and conflict.snapshot() == initial and conflict.save_attempts == 0 and FileAccess.get_file_as_bytes(conflict_path) == bytes and FileAccess.get_file_as_bytes(conflict_path + ".v29-backup.json") == other, "Conflicting backup never overwritten")
	check(conflict.save_build(conflict_path) != OK, "Backup collision protects later saves")
	var backup_path := "user://backup-fail.json"
	write(backup_path, bytes)
	var backup := Store.new()
	backup._io = BackupFailIO.new()
	initial = backup.snapshot()
	check(not backup.load_build(backup_path) and backup.snapshot() == initial and FileAccess.get_file_as_bytes(backup_path) == bytes and backup.save_attempts == 0, "Backup IO failure cannot commit")
	var external_path := "user://external.json"
	write(external_path, bytes)
	var external := Store.new()
	external._io = ExternalIO.new()
	initial = external.snapshot()
	check(not external.load_build(external_path) and external.snapshot() == initial and FileAccess.get_file_as_string(external_path) == "external writer" and external.save_attempts == 0 and FileAccess.get_file_as_bytes(external_path + ".v29-backup.json") == bytes, "External change during backup remains untouched")
	var path := "user://real-atomic-fail.json"
	write(path, bytes)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Real isolated atomic-temp collision created")
	var store := Store.new()
	initial = store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes and signals[0] == 0 and store.successful_saves == 0 and store.save_attempts == 1, "Real temp-open failure preserves primary and memory")
	check(FileAccess.get_file_as_bytes(path + ".v29-backup.json") == bytes, "Failed commit retains exact original backup")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove isolated temp collision")
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and signals[0] == 1, "Matching-backup retry succeeds exactly once")
	var disk := FileAccess.get_file_as_bytes(path)
	write(path, "external after migration".to_utf8_buffer())
	check(store.save_build(path) == ERR_FILE_ALREADY_IN_USE and store.snapshot() == expected and store._disk_bytes == disk and FileAccess.get_file_as_string(path) == "external after migration", "New receipt protects later external edits")
	var current_path := "user://retained-current.json"
	var current_bytes := JSON.stringify(expected).to_utf8_buffer()
	write(current_path, current_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(current_path), "Accept current30 receipt before a failed old load")
	var failed_path := "user://failed-replacement.json"
	write(failed_path, bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == expected and retained._path == current_path and retained._disk_bytes == current_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Failed primary commit retains previously accepted receipt")
	var message_path := "user://message.json"
	write(message_path, bytes)
	var game := Game.new()
	check(game.load_build(message_path) and game.migrated_from_legacy and game.migration_message.contains("晴泉台地 I") and not game.migration_message.contains("两瓶药剂"), "Old29 migration tells the player the correct unlocked content")


func test_history() -> void:
	var paths := ["res://tests/fixtures/v041_journey/v25-default.json", "res://tests/fixtures/v042_affixes/v26-active.json", "res://docs/qa/v045/ignite-migration-fixtures/v27-active.json", "res://docs/qa/v047-migration/fixtures/v28-active.json"]
	for filename: String in paths:
		var bytes := FileAccess.get_file_as_bytes(filename)
		var raw: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
		var version := int(raw.version)
		var source: Dictionary = Rules.decode_v25(raw) if version == 25 else Rules.decode_v26(raw) if version == 26 else Rules.decode_v27(raw) if version == 27 else Rules.decode_v28(raw)
		check(not source.is_empty(), "Independent literal old%d still decodes" % version)
		var candidate := source.duplicate(true)
		if version < 26:
			candidate = Prior.migrate_v25(candidate)
			check(candidate.version == 26 and candidate.journey == Journey.empty_legacy() and candidate.journey.best_tiers.size() == 2, "Historical25→26 creates only legacy two-map journey")
		if version < 27: candidate = EquipmentMigration.migrate_v26(candidate)
		if version < 28: candidate = IgniteMigration.migrate_v27(candidate)
		var old29 := EmberMigration.migrate_v28(candidate)
		check(old29.version == 29 and Rules.reason_v29(old29).is_empty() and old29.journey.best_tiers.size() == 2, "Historical28→29 stays frozen before third-map migration")
		var expected := expected_current(old29)
		var path := "user://history%d.json" % version
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and store.successful_saves == 1 and FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % version) == bytes, "Old%d full chain commits30 once with original-version backup" % version)
		if version >= 26:
			var injected := source.duplicate(true)
			injected.journey.best_tiers[MAP_ID] = 0
			var decoded: Dictionary = Rules.decode_v26(injected) if version == 26 else Rules.decode_v27(injected) if version == 27 else Rules.decode_v28(injected)
			var rejected: String = Rules.reason_v26(injected) if version == 26 else Rules.reason_v27(injected) if version == 27 else Rules.reason_v28(injected)
			check(decoded.is_empty() and not rejected.is_empty(), "Frozen%d cannot launder new-map key" % version)
			rejected_preserving("user://historical-injection%d.json" % version, JSON.stringify(injected).to_utf8_buffer(), version)
	var fresh := Store.new().snapshot()
	check(fresh.version == 30 and fresh.journey == Journey.empty() and fresh.journey.best_tiers[MAP_ID] == 0, "Default full legacy chain produces valid30 with third tierI available")
	check(Store.Currency.total_quantity(fresh.items).quantity == 0, "Default third-map expansion gifts no currency")
	var old_default := Rules.decode_v29(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v29-default.json")))
	check(fresh.items == old_default.items and fresh.next_item_serial == old_default.next_item_serial and fresh.locations == old_default.locations, "Fresh default retains released29 items, UID serial and locations")
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v29-vocabulary-oracle.json"))
	check(Journey.GEM_DEFINITIONS == oracle.gem_definitions and Journey.GEM_DEFINITIONS.size() == 26, "Frozen26 reward definitions unchanged")
	for index: int in range(oracle.milestones.size()): check(Journey.gem_definition(index + 1) == oracle.milestones[index], "Released reward ordinal %d unchanged" % (index + 1))


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-v048-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	check(Rules.VERSION == 30 and Rules.V29_VERSION == 29, "Explicit29 and current30 envelope versions")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "manifest.json"))
	for name: String in ["v29-default.json", "v29-ember-bag.json", "v29-active.json", "v29-pending.json"]: test_literal(name, manifest)
	var source := Rules.decode_v29(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v29-default.json")))
	test_validation(source)
	test_failures(source)
	test_history()
	print("Third map migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
