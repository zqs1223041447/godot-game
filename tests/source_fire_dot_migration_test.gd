extends SceneTree
## Literal released-v52 schema31 migration, strict vocabulary and persistence faults.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/fire_dot_migration.gd")
const Prior = preload("res://scripts/save/shock_gem_migration.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")

const FIXTURES := "res://docs/qa/v053-source/fixtures/"


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
	result.version = 32
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
	check(bytes.size() == int(manifest.files[name].bytes) and digest(bytes) == manifest.files[name].sha256 and bytes.get_string_from_utf8().begins_with(" \r\n"), "Released-v52 literal bytes and raw SHA256: " + name)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var source := Rules.decode_v31(raw)
	check(not source.is_empty() and Rules.reason_v31(source).is_empty() and Rules.decode(raw).is_empty(), "Complete frozen31 decoder and current32 separation")
	if source.is_empty(): return
	var expected := expected_current(source)
	var before := var_to_bytes(source)
	seed(520031)
	var next_rng := randi()
	seed(520031)
	var migrated := Migration.migrate_v31(source)
	check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Migration changes only version; source/RNG immutable")
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Exact preservation of " + field + ": " + name)
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys(), "Item and location insertion order retained")
	check(Migration.migrate_v31(migrated).is_empty(), "Migration rejects repeated/current envelope")
	migrated.journey.best_tiers.sunwell_terrace = 3
	check(var_to_bytes(source) == before, "Candidate journey detached from original")
	var path := "user://literal-" + name
	write(path, bytes)
	var store := Store.new()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and store.save_attempts == 1 and signals[0] == 1, "One durable migration and notification")
	check(FileAccess.get_file_as_bytes(path + ".v31-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Raw original CRLF backup and atomic commit")
	var disk := FileAccess.get_file_as_bytes(path)
	check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated current load does not rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v31-backup.json") == bytes, "Independent strict32 reopen preserves content and backup")


func fire_candidate(source: Dictionary) -> Dictionary:
	var candidate := source.duplicate(true)
	candidate.progress = {"level":119,"xp":17}
	candidate.talents.class_id = 1
	candidate.talents.allocated = ["47175","31628","9511","23881","26523","6446","10221","54396","2550"]
	candidate.talents.masteries = {}
	candidate.talents.normal_points = 115
	return candidate


func test_vocabulary(source: Dictionary) -> void:
	var injected := fire_candidate(source)
	var current := expected_current(injected)
	check(Rules.reason(current).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(current))) == current, "Injected route is independently legal under current32")
	check(Rules.decode_v31(injected).is_empty() and not Rules.reason_v31(injected).is_empty() and Migration.migrate_v31(injected).is_empty(), "Old31 rejects Fire DoT node before migration")
	rejected_preserving("user://old31-injected-fire.json",JSON.stringify(injected).to_utf8_buffer(),31)
	for mutation: String in ["future","duplicate_binding","fractional_revision","bool_revision","extra_field","missing_journey","invalid_journey","duplicate_uid","unknown_node","wrong_allocated_type","unknown_stat","nan_revision","nan_mastery"]:
		var bad := source.duplicate(true)
		match mutation:
			"future": bad.version = 33
			"duplicate_binding": bad.bindings.append(bad.bindings[0].duplicate())
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"extra_field": bad.fire_dot_runtime = {}
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"duplicate_uid": bad.items[bad.items.keys()[0]].uid = "wrong_uid"
			"unknown_node": bad.talents.allocated.append("unknown_fire_node"); bad.talents.normal_points -= 1
			"wrong_allocated_type": bad.talents.allocated = {"54396":true}
			"unknown_stat": bad.talents.fire_dot_multiplier_add = 0.1
			"nan_revision": bad.revision = NAN
			"nan_mastery": bad.talents.masteries["123"] = NAN
		check(not Rules.reason_v31(bad).is_empty() and Migration.migrate_v31(bad).is_empty() and Rules.decode_v31(bad).is_empty(), "Strict frozen31 whole-envelope rejection: " + mutation)
		# JSON has no NaN representation; direct dictionary checks above cover it.
		# Model the actual null bytes a serializer would emit without logging a warning.
		var on_disk := bad.duplicate(true)
		if mutation == "nan_revision": on_disk.revision = null
		if mutation == "nan_mastery": on_disk.talents.masteries["123"] = null
		rejected_preserving("user://invalid31-" + mutation + ".json",JSON.stringify(on_disk).to_utf8_buffer(),int(bad.version))
	for value: Variant in [null,[],true,NAN,INF,31,"31"]:
		check(not Rules.reason_v31(value).is_empty() and Rules.decode_v31(value).is_empty() and Migration.migrate_v31(value).is_empty(), "Wrong envelope type rejected")


func test_failures(source: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + "v31-default.json")
	var expected := expected_current(source)
	var conflict_path := "user://backup-collision.json"
	write(conflict_path, bytes)
	var other := "retained backup".to_utf8_buffer()
	write(conflict_path + ".v31-backup.json", other)
	var conflict := Store.new()
	var initial := conflict.snapshot()
	check(not conflict.load_build(conflict_path) and conflict.snapshot() == initial and conflict.save_attempts == 0 and FileAccess.get_file_as_bytes(conflict_path) == bytes and FileAccess.get_file_as_bytes(conflict_path + ".v31-backup.json") == other, "Conflicting backup never overwritten")
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
	check(not external.load_build(external_path) and external.snapshot() == initial and FileAccess.get_file_as_string(external_path) == "external writer" and external.save_attempts == 0 and FileAccess.get_file_as_bytes(external_path + ".v31-backup.json") == bytes, "Concurrent source change during backup stays untouched")
	var path := "user://real-atomic-fail.json"
	write(path, bytes)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Isolated real atomic-temp collision created")
	var store := Store.new()
	initial = store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes and signals[0] == 0 and store.successful_saves == 0 and store.save_attempts == 1, "Real write failure preserves primary file and memory")
	check(FileAccess.get_file_as_bytes(path + ".v31-backup.json") == bytes, "Failed commit retains original raw backup")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove isolated failure injection")
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and signals[0] == 1, "Same-backup retry succeeds exactly once")
	var disk := FileAccess.get_file_as_bytes(path)
	write(path, "external after migration".to_utf8_buffer())
	check(store.save_build(path) == ERR_FILE_ALREADY_IN_USE and store.snapshot() == expected and store._disk_bytes == disk and FileAccess.get_file_as_string(path) == "external after migration", "Current receipt protects later external edits")
	var current_path := "user://retained-current.json"
	var current_bytes := JSON.stringify(expected).to_utf8_buffer()
	write(current_path, current_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(current_path), "Accept current32 receipt before failed old load")
	var failed_path := "user://failed-replacement.json"
	write(failed_path, bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == expected and retained._path == current_path and retained._disk_bytes == current_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Primary write failure retains previously accepted receipt")
	var message_path := "user://message.json"
	write(message_path, bytes)
	var game := Game.new()
	check(game.load_build(message_path) and game.migrated_from_legacy and game.migration_message.contains("火焰持续伤害") and not game.migration_message.contains("两瓶药剂"), "Old31 receives accurate non-grant migration message")


func test_current_transaction(source: Dictionary) -> void:
	var candidate := expected_current(fire_candidate(source))
	candidate.talents.allocated.resize(7)
	candidate.talents.normal_points = 117
	var game := Game.new()
	game._accept_memory(candidate)
	var path := "user://current-allocation.json"
	check(game.save_build(path) == OK and Rules.reason(candidate).is_empty(), "Current32 old path has persisted receipt")
	var before := game.snapshot()
	var bytes := FileAccess.get_file_as_bytes(path)
	var attempts := game.save_attempts
	var saves := game.successful_saves
	var signals := [0]
	game.changed.connect(func(): signals[0] += 1)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create real allocation temp-write collision")
	check(not game.allocate_passive("54396",0,game.revision(),path).ok and game.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes and game._disk_bytes == bytes, "Failed actual allocation preserves entire state and accepted disk receipt")
	check(game.save_attempts == attempts+1 and game.successful_saves == saves and signals[0] == 0 and is_zero_approx(game.get_stats().fire_dot_multiplier_add), "Failed allocation exposes no grant, point spend, save or signal")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove isolated allocation failure")
	check(game.allocate_passive("54396",0,game.revision(),path).ok and game.revision() == before.revision+1 and game.snapshot().talents.normal_points == before.talents.normal_points-1 and signals[0] == 1, "Recoverable allocation retry commits exactly once")
	check(is_equal_approx(game.get_stats().fire_dot_multiplier_add,0.04), "Committed allocation exposes precise fractional grant")
	before = game.snapshot()
	bytes = FileAccess.get_file_as_bytes(path)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create real refund temp-write collision")
	check(not game.refund_passive("54396",game.revision(),path).ok and game.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes and signals[0] == 1, "Failed refund preserves grant, points, revision and bytes")
	check(DirAccess.remove_absolute(path + ".tmp") == OK and game.refund_passive("54396",game.revision(),path).ok and signals[0] == 2 and is_zero_approx(game.get_stats().fire_dot_multiplier_add), "Refund retry removes grant once")


func test_prior_chain() -> void:
	var old30 := Rules.decode_v30(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v052-shock-integration/fixtures/v30-active.json")))
	var old31 := Prior.migrate_v30(old30)
	check(old31.version == 31 and Rules.reason_v31(old31).is_empty(), "Prior Shock migration retains frozen31 result")
	var expected31 := old30.duplicate(true)
	expected31.version = 31
	check(old31 == expected31 and Migration.migrate_v31(old31) == expected_current(old31), "Frozen30→31→32 chain changes only version")
	for filename: String in ["res://tests/fixtures/v041_journey/v25-default.json","res://docs/qa/v048-migration/fixtures/v29-active.json","res://docs/qa/v052-shock-integration/fixtures/v30-active.json"]:
		var bytes := FileAccess.get_file_as_bytes(filename)
		var raw: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
		var version := int(raw.version)
		var path := "user://prior%d.json" % version
		write(path,bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot().version == 32 and Rules.reason(store.snapshot()).is_empty(), "Focused prior%d chain reaches valid32" % version)
		check(store.save_attempts == 1 and store.successful_saves == 1 and FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % version) == bytes, "Prior chain commits once with original-version bytes")
		check(not store.snapshot().talents.allocated.has("54396"), "Migration adds no Fire DoT allocation")
	var fresh := Store.new().snapshot()
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v31-vocabulary-oracle.json"))
	check(fresh.version == 32 and fresh.journey == Journey.empty() and Store.Currency.total_quantity(fresh.items).quantity == 0, "Built-in whole history yields current32 without currency grant")
	check(Journey.GEM_DEFINITIONS == oracle.gem_definitions and Journey.GEM_DEFINITIONS.size() == 26, "Frozen milestone gem vocabulary unchanged")
	for index: int in oracle.milestones.size(): check(Journey.gem_definition(index+1) == oracle.milestones[index], "Released reward ordinal stays unchanged: " + str(index+1))
	# Literal released saves at every source-tree envelope boundary must reject a
	# new node before the loader can write a backup or current candidate.
	for fixture: String in ["tests/fixtures/v022_currency/v14-original-bytes.json","tests/fixtures/v022_currency/v15-wallet-27.json","tests/fixtures/performance/crowded-inventory-v16.json","tests/fixtures/v026_flasks/released-v17-two-offense.json","tests/fixtures/v028_town/v18-no-c.json","tests/fixtures/v032_spatial/v19-default.json","tests/fixtures/v033_recharge/v20-default.json","tests/fixtures/v034_cost/v21-default.json","tests/fixtures/v035_flasks/v22-default.json","tests/fixtures/v039_critical/v23-default.json","tests/fixtures/v040_leech/v24-default.json","tests/fixtures/v041_journey/v25-default.json","tests/fixtures/v042_affixes/v26-default.json","docs/qa/v045/ignite-migration-fixtures/v27-default.json","docs/qa/v047-migration/fixtures/v28-default.json","docs/qa/v048-migration/fixtures/v29-default.json","docs/qa/v052-shock-integration/fixtures/v30-default.json","docs/qa/v053-source/fixtures/v31-default.json"]:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + fixture))
		var version := int(raw.version)
		var old: Dictionary = Rules.new().call("decode_v%d" % version,raw)
		check(not old.is_empty() and Rules.new().call("reason_v%d" % version,old).is_empty(), "Genuine released%d valid before injection" % version)
		var injected := fire_candidate(old)
		check(not Rules.new().call("reason_v%d" % version,injected).is_empty(), "Frozen%d reason rejects new source node" % version)
		rejected_preserving("user://fire-injected%d.json" % version,JSON.stringify(injected).to_utf8_buffer(),version)


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-v053-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	check(Rules.VERSION == 32 and Rules.V31_VERSION == 31 and SourceTree.CURRENT_SAVE_VERSION == 32 and SourceTree._execution_policy(31) == 25, "Schema32 keeps old31 source vocabulary frozen25")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "manifest.json"))
	for name: String in ["v31-default.json","v31-active-allocated.json"]: test_literal(name,manifest)
	var source := Rules.decode_v31(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v31-default.json")))
	test_vocabulary(source)
	test_failures(source)
	test_current_transaction(source)
	test_prior_chain()
	print("Source Fire DoT migration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
