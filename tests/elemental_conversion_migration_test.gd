extends SceneTree
## Frozen47 validation, exact original-byte backup and atomic48 publication.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/elemental_conversion_migration.gd")
const Prior = preload("res://scripts/save/frost_lock_gem_migration.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Frozen = preload("res://tests/fixtures/v078/source_tree_runtime_v077.gd")
const Fixture = preload("res://tests/fixtures/v078/elemental_conversion_fixture.gd")
const ROOT := "res://docs/qa/v078-source/"
const NATIVE47 := "res://docs/qa/v073-gameplay/fixtures/selected.json"
var checks := 0
var failures := 0
var report := {"native47_source":NATIVE47,"migration":"47→48","changed_fields":["version"]}

class BackupFailIO extends Store.Legacy:
	func _backup_legacy_save(_path: String) -> Error: return ERR_CANT_CREATE

class ExternalIO extends Store.Legacy:
	func _backup_legacy_save(path: String) -> Error:
		var result := super._backup_legacy_save(path)
		if result == OK:
			var file := FileAccess.open(path,FileAccess.WRITE)
			file.store_string("external writer")
			file.close()
		return result

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func current(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.version = 48
	return result

func reject_bytes(name: String, bytes: PackedByteArray) -> void:
	var path := "user://reject48-"+name+".json"
	write(path,bytes)
	var store := Store.new()
	var before := store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Invalid old47 preserves source bytes and live state: "+name)
	check(store.save_attempts == 0 and store.successful_saves == 0 and events[0] == 0 and not FileAccess.file_exists(path+".v47-backup.json"), "Invalid old47 makes no backup, write or event")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected path cannot be overwritten")

func migration_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	var before := var_to_bytes(source)
	check(Migration.migrate_v47(source) == current(source) and var_to_bytes(source) == before, "Pure migration changes only version and never its input")
	check(Rules.equipment_vocabulary_for_save_version(47) == 46 and Rules.equipment_vocabulary_for_save_version(48) == 46, "Equipment vocabulary stays46")
	var old_game := Game.new()
	old_game._accept_memory(source)
	var stats_before := old_game.get_stats()
	var path := "user://native47-to48.json"
	write(path,bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	check(not game._canonical_disk_stamp(path).ok and FileAccess.get_file_as_bytes(path) == bytes, "Native stamp declines old version without migration side effects")
	if not check(game.load_build(path), "Actual model loads genuine saved schema47"): return
	check(game.snapshot() == current(source) and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "One atomic migration publishes exactly once")
	check(FileAccess.get_file_as_bytes(path+".v47-backup.json") == bytes, "Backup preserves exact genuine47 serializer bytes")
	check(game.get_stats() == stats_before, "Already allocated old source retains exact gameplay stats")
	check(game.migrated_from_legacy and game.migration_message.contains("冰霜") and game.migration_message.contains("6%") and game.migration_message.contains("不额外赠物或赠点"), "Migration notice describes source opening without gifts")
	check(game._canonical_disk_stamp(path).ok, "Native48 stamp accepts migrated file")
	var disk := FileAccess.get_file_as_bytes(path)
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == game.snapshot() and reopened.save_attempts == 0 and not reopened.migrated_from_legacy and FileAccess.get_file_as_bytes(path) == disk, "Native48 reload neither remigrates nor writes")
	check(FileAccess.get_file_as_bytes(path+".v47-backup.json") == bytes, "Native reload preserves historical backup")

func strict_checks(source: Dictionary) -> void:
	var calls := [0]
	var permissive := func(_candidate: Dictionary) -> String: calls[0] += 1; return ""
	var game := Game.new()
	if not check(Fixture.prepare(game,"user://injected48-source.json").ok, "Actual legal27-point fixture available for frozen47 rejection"): return
	var injected := game.snapshot()
	check(Rules.reason(injected).is_empty(), "Three choices and both original notables are legal under48")
	injected.version = 47
	check(not Rules.reason_v47(injected,permissive).is_empty() and Rules.decode_v47(injected).is_empty() and Migration.migrate_v47(injected,permissive).is_empty() and calls[0] == 0, "Old47 cannot preallocate new nodes or masteries even with permissive callback")
	reject_bytes("new-source",JSON.stringify(injected).to_utf8_buffer())
	for mutation: String in ["fractional_revision","bool_revision","unknown_field","missing_journey","invalid_journey","bad_uid","unknown_node","duplicate_node","wrong_nodes_type","over_budget","bad_source","nan_mastery","missing_location","reused_serial","bad_binding","bad_ledger","wrong_version"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 1.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.runtime_penetration = {}
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.normal_root_kills = -1
			"bad_uid": bad.items[bad.items.keys()[0]].uid = "other"
			"unknown_node": bad.talents.allocated.append("unknown-source-node")
			"duplicate_node": bad.talents.allocated.append(bad.talents.allocated[0])
			"wrong_nodes_type": bad.talents.allocated = "nodes"
			"over_budget": bad.talents.normal_points += 1
			"bad_source": bad.talents.source_version = "3.30"
			"nan_mastery": bad.talents.masteries["60170"] = NAN
			"missing_location": bad.locations.erase(bad.locations.keys()[0])
			"reused_serial": bad.next_item_serial = 1
			"bad_binding": bad.bindings[0].keycode = KEY_C
			"bad_ledger": bad.migration_ledger.default_class_id = -1
			"wrong_version": bad.version = 48
		calls[0] = 0
		check(not Rules.reason_v47(bad,permissive).is_empty() and Rules.decode_v47(bad).is_empty() and Migration.migrate_v47(bad,permissive).is_empty() and calls[0] == 0, "Complete frozen native legality precedes callbacks: "+mutation)
		if mutation != "nan_mastery" and mutation != "wrong_version": reject_bytes(mutation,JSON.stringify(bad).to_utf8_buffer())
	var restrictive := func(_candidate: Dictionary) -> String: return "extra policy restriction"
	check(Migration.migrate_v47(source,restrictive).is_empty(), "Optional validator may add restrictions")
	check(Rules.decode(source).is_empty() and Rules.decode_v47(current(source)).is_empty() and Migration.migrate_v47(current(source)).is_empty(), "Decode and migration enforce exact envelope versions")
	for version: int in [45,46,47]:
		for id: String in ["8833","56716"]: check(Source.node_effect(id,0,version) == Frozen.node_effect(id,0,version) and Source.node_effect(id,0,version).status == "partial", "Explicit old policy keeps notable partially unsupported")
		check(Source.node_effect("60170",4116,version).status == "unsupported" and Source.node_effect("58816",53046,version).status == "unsupported", "Explicit old policies reject new masteries")

func chain_checks() -> void:
	var fresh := Store.new().snapshot()
	check(fresh.version == 48 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0, "Complete built-in legacy migration chain constructs current48 without currency gifts")
	var source46 := fresh.duplicate(true)
	source46.version = 46
	var source47 := source46.duplicate(true)
	source47.version = 47
	check(Rules.reason_v46(source46).is_empty() and Prior.migrate_v46(source46) == source47 and Rules.reason_v47(source47).is_empty(), "Previous Frost Lock migration remains fixed at47")
	check(Migration.migrate_v47(source47) == fresh, "46→47→48 preserves every non-version field")
	for version: int in [45,46,47]:
		var old := fresh.duplicate(true)
		old.version = version
		var bytes := (JSON.stringify(old,"  ",false,true)+"\n").to_utf8_buffer()
		var path := "user://default-chain%d.json" % version
		write(path,bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == fresh and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path+".v%d-backup.json" % version) == bytes, "Old%d loader chain writes once and preserves exact input backup" % version)
		check(not FileAccess.file_exists(path+".v48-backup.json"), "No generated intermediate48 backup")

func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup","collision","external","atomic"]:
		var path := "user://failure48-"+failure+".json"
		write(path,bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "collision": write(path+".v47-backup.json","retained backup".to_utf8_buffer())
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic": check(DirAccess.make_dir_absolute(path+".tmp") == OK, "Inject actual atomic migration failure")
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration never publishes memory: "+failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Original or external writer bytes are preserved")
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup and concurrency checks precede writing")
		if failure == "collision": check(FileAccess.get_file_as_string(path+".v47-backup.json") == "retained backup", "Conflicting backup is retained")
		if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path+".v47-backup.json") == bytes, "Failed final commit preserves original backup")
		if failure == "atomic": check(DirAccess.remove_absolute(path+".tmp") == OK and store.load_build(path) and store.snapshot() == current(source) and events[0] == 1, "Atomic retry commits once after fault removal")
		else: check(store.save_build(path) != OK, "Failed migration path remains protected")

func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v078-source") or not OS.get_user_data_dir().begins_with(isolation+"/"): quit(78); return
	var bytes := FileAccess.get_file_as_bytes(NATIVE47)
	var source := Rules.decode_v47(JSON.parse_string(bytes.get_string_from_utf8()))
	if not check(not source.is_empty() and Rules.reason_v47(source).is_empty(), "Genuine released native47 fixture is fully valid"): quit(1); return
	migration_checks(source,bytes); strict_checks(source); chain_checks(); failure_checks(source,bytes)
	report.checks = checks; report.failures = failures
	write(ROOT+"migration-report.json",(JSON.stringify(report,"\t",true,true)+"\n").to_utf8_buffer())
	print("Elemental conversion migration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
