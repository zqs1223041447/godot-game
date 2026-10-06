extends SceneTree
## Strict40→41 migration from independent frozen-v064 serializer bytes.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/zealots_oath_migration.gd")
const Prior = preload("res://scripts/save/iron_reflexes_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const ROOT := "res://docs/qa/v065-migration/"
const ROUTE := ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "44202", "23027", "60472", "26270", "64210", "7444", "63425", "55649", "22285", "53793", "37884", "32482", "31033", "38906"]
var checks := 0
var failures := 0
var evidence := {}


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


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func current(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.version = 41
	return result


func reject_bytes(name: String, bytes: PackedByteArray, version: int = 40) -> void:
	var path := "user://" + name + ".json"
	write(path,bytes)
	var store := Store.new()
	var before := store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Rejected source leaves original bytes and live state unchanged: " + name)
	check(store.save_attempts == 0 and store.successful_saves == 0 and events[0] == 0 and not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Invalid input causes no backup, write or event")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected source cannot be overwritten by a later save")


func strict_checks(source: Dictionary) -> void:
	var injected := current(source)
	injected.progress = {"level":19,"xp":0}
	injected.talents.class_id = 1
	injected.talents.allocated = ROUTE.duplicate()
	injected.talents.masteries = {}
	injected.talents.normal_points = 0
	check(Rules.reason(injected).is_empty(), "Injected63425 route is otherwise completely legal in current41")
	injected.version = 40
	var calls := [0]
	var permissive := func(_value: Dictionary) -> String: calls[0] += 1; return ""
	check(not Rules.reason_v40(injected,permissive).is_empty() and Rules.decode_v40(injected).is_empty() and Migration.migrate_v40(injected,permissive).is_empty() and calls[0] == 0, "Native frozen40 rejects63425 before any permissive callback")
	reject_bytes("injected40-zealots-oath",JSON.stringify(injected).to_utf8_buffer())
	var gear_uid := "gear_%06d" % (int(source.next_item_serial)-2)
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "invalid_journey", "bad_uid", "unknown_node", "duplicate_node", "wrong_nodes_type", "unknown_stat", "over_budget", "bad_source", "nan_revision", "nan_mastery", "fractional_roll", "unknown_affix", "missing_location", "reused_serial", "bad_binding", "bad_ledger"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.zealots_oath = 1.0
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"bad_uid": bad.items[gear_uid].uid = "other"
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"duplicate_node": bad.talents.allocated.append(bad.talents.allocated[0]); bad.talents.normal_points -= 1
			"wrong_nodes_type": bad.talents.allocated = {"47175":true}
			"unknown_stat": bad.talents.zealots_oath = 1.0
			"over_budget": bad.talents.normal_points += 1
			"bad_source": bad.talents.source_version = "3.29.2"
			"nan_revision": bad.revision = NAN
			"nan_mastery": bad.talents.masteries["123"] = NAN
			"fractional_roll": bad.items[gear_uid].payload.affixes[0].value = 9.5
			"unknown_affix": bad.items[gear_uid].payload.affixes[0].id = "unrecognized_affix"
			"missing_location": bad.locations.erase(gear_uid)
			"reused_serial": bad.next_item_serial -= 1
			"bad_binding": bad.bindings[0].keycode = KEY_C
			"bad_ledger": bad.migration_ledger.normal_budget_at_migration += 1
		calls[0] = 0
		check(not Rules.reason_v40(bad,permissive).is_empty() and Rules.decode_v40(bad).is_empty() and Migration.migrate_v40(bad,permissive).is_empty() and calls[0] == 0, "Complete native frozen40 rejects before callback: " + mutation)
		if mutation == "nan_revision": bad.revision = null
		if mutation == "nan_mastery": bad.talents.masteries["123"] = null
		reject_bytes("invalid40-" + mutation,JSON.stringify(bad).to_utf8_buffer())
	for value: Variant in [null,[],true,40,"40",NAN,INF]:
		check(not Rules.reason_v40(value).is_empty() and Rules.decode_v40(value).is_empty() and Migration.migrate_v40(value).is_empty(), "Wrong envelope types fail before migration")
	reject_bytes("broken-json","{ broken40\r\n".to_utf8_buffer())
	var future := current(source)
	future.version = 42
	reject_bytes("future42",JSON.stringify(future).to_utf8_buffer(),42)
	check(Rules.decode(source).is_empty() and not Rules.reason(source).is_empty() and Rules.decode_v40(current(source)).is_empty(), "Current decoder accepts exactly41; frozen decoder accepts exactly40")
	var reject := func(_value: Dictionary) -> String: return "additional restriction"
	check(Migration.migrate_v40(source,reject).is_empty(), "Optional callbacks may add a further restriction")


func literal_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	var expected := current(source)
	var before := var_to_bytes(source)
	seed(614041)
	var next_rng := randi()
	seed(614041)
	var migrated := Migration.migrate_v40(source)
	check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Migration changes only version; source and global RNG stay untouched")
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Every nonversion field retains identity and content: " + field)
	check(Game._stats_for(migrated) == Game._stats_for(source) and not Game._stats_for(migrated).has("zealots_oath") and not Game._stats_for(migrated).has("shield_regeneration_rate"), "Migration grants no effect to the existing legal build")
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys() and Store.Currency.total_quantity(migrated.items) == Store.Currency.total_quantity(source.items), "Items, UID order, locations and currency are preserved")
	check(Migration.migrate_v40(migrated).is_empty(), "Already migrated envelope is not migrated twice")
	migrated.journey.best_tiers.sunwell_terrace = 3
	check(var_to_bytes(source) == before, "Migrated nested journey is deeply detached")
	var path := "user://frozen-v064-native40.json"
	write(path,bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "Native old40 loads with one atomic commit and notification")
	check(FileAccess.get_file_as_bytes(path + ".v40-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Old40 bytes are backed up verbatim before atomic replacement")
	check(game.migrated_from_legacy, "Game reports the completed migration")
	var disk := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated41 load performs no migration or rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v40-backup.json") == bytes, "Independent41 reopen preserves migrated fields and original-byte backup")
	var dual_uid := "gear_%06d" % (int(source.next_item_serial)-2)
	var payload: Dictionary = source.items[dual_uid].payload
	check(payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="rimeward") and payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="stormward") and reopened.item(dual_uid).payload == payload, "Both vocabulary39 elemental suffixes survive41 without reroll or vocabulary regression")
	check(Equipment.validate_instance_for_version(payload,39) and not Equipment.validate_instance_for_version(payload,37) and not Equipment.validate_instance_for_version(payload,40) and not Equipment.validate_instance_for_version(payload,41), "Fixture uses genuine vocabulary39 equipment; equipment40/41 remain undefined")
	evidence.schema40_sha256 = digest(bytes)
	evidence.schema40_bytes = bytes.size()
	evidence.preserved_items = source.items.size()
	check(payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="ironhide") and payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="mistweave"), "Both vocabulary39 rating prefixes survive unchanged")
	check(Store.Currency.total_quantity(source.items).quantity == 73 and float(Game._stats_for(source).get("iron_reflexes",0.0)) == 1.0 and Game._stats_for(source).evasion == 0.0, "Fixture exercises nonzero currency and previously allocated Iron Reflexes")
	evidence.preserved_rating_item = payload
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "fixtures/v40-stats-oracle.json"))
	check(Game._stats_for(expected) == oracle.stats and Game._stats_for(source) == oracle.stats, "Complete migrated and source stats match independent native v64 oracle")
	check(source.locations[dual_uid] == {"kind":"equipment", "slot_id":"body_armour"} and float(oracle.stats.armour) > 0.0, "Frozen fixture exercises equipped vocabulary39 defense prefixes with active Iron Reflexes")
	evidence.frozen40_stats = oracle.stats


func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path,bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "collision": write(path + ".v40-backup.json","retained backup".to_utf8_buffer())
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic": check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject actual temporary-file collision")
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration publishes nothing: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Failed migration preserves original or independent writer bytes")
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup must succeed before first commit attempt")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v40-backup.json") == "retained backup", "Conflicting backup remains verbatim")
		if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path + ".v40-backup.json") == bytes, "Failed commit retains exact raw backup")
		if failure == "atomic":
			check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.snapshot() == current(source) and store.successful_saves == 1 and events[0] == 1, "Identical-backup retry commits once after fault removal")
		else: check(store.save_build(path) != OK, "Failed load protects the same target from a later save")
	var accepted := current(source)
	var accepted_bytes := JSON.stringify(accepted).to_utf8_buffer()
	var accepted_path := "user://accepted41.json"
	write(accepted_path,accepted_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(accepted_path), "Establish current41 live state and disk receipt")
	var failed_path := "user://failed40-replacement.json"
	write(failed_path,bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == accepted and retained._path == accepted_path and retained._disk_bytes == accepted_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Failed old40 commit preserves prior accepted live state and disk receipt")


func chain_checks() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v064-migration/fixtures/v39-frozen-v063.json")
	var old39 := Rules.decode_v39(JSON.parse_string(bytes.get_string_from_utf8()))
	var frozen40 := Prior.migrate_v39(old39)
	var expected40 := old39.duplicate(true)
	expected40.version = 40
	check(not old39.is_empty() and frozen40 == expected40 and Rules.reason_v40(frozen40).is_empty(), "Prior39 to40 still stops at strict40 and changes only version")
	check(Migration.migrate_v40(frozen40) == current(old39), "Frozen39 to40 to41 chain preserves every nonversion field")
	var path := "user://released39-chain.json"
	write(path,bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot() == current(old39) and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v39-backup.json") == bytes and not FileAccess.file_exists(path + ".v40-backup.json"), "Actual39 chain commits once and backs up original39 bytes only")
	var fresh := Store.new().snapshot()
	check(fresh.version == 41 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0 and not Game._stats_for(fresh).has("zealots_oath") and not Game._stats_for(fresh).has("shield_regeneration_rate"), "Fresh full default chain reaches41 without currency or keystone gifts")


func current_checks(source: Dictionary) -> void:
	var candidate := current(source)
	candidate.progress = {"level":19,"xp":0}
	candidate.talents.class_id = 1
	candidate.talents.allocated = ROUTE.duplicate()
	candidate.talents.masteries = {}
	candidate.talents.normal_points = 0
	var store := Store.new()
	store._accept_memory(candidate)
	var path := "user://current41-zealots-oath.json"
	check(Rules.reason(candidate).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(candidate))) == candidate and store.save_build(path) == OK, "Current41 Zealot's Oath allocation serializes under the complete envelope")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == candidate and reopened.save_attempts == 0 and not FileAccess.file_exists(path+".v40-backup.json"), "Current41 reopens without migration, point grant or reroll")
	var stats := Game._stats_for(reopened.snapshot())
	check(float(stats.get("zealots_oath", 0.0)) == 1.0 and stats.life_regen == 0.0 and is_equal_approx(float(stats.get("shield_regeneration_rate", 0.0)), 10.0 + 0.018 * float(stats.max_shield)), "Current41 persisted allocation activates the complete Zealot's Oath consumer")
	evidence.current41_zealots_oath_route = ROUTE
	evidence.current41_shield_regeneration_rate = stats.get("shield_regeneration_rate", 0.0)
	evidence.current41_max_shield = stats.max_shield


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v065-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	check(Rules.VERSION == 41 and Rules.V40_VERSION == 40 and Source.CURRENT_SAVE_VERSION == 41 and Equipment.CURRENT_VOCABULARY == 39, "Source/save41 retains equipment vocabulary39")
	check(Source._execution_policy(39) == 38 and Source._execution_policy(40) == 40 and Source._execution_policy(41) == 41, "Old39 and40 retain exact frozen source policies")
	for version: int in range(1,42):
		check(Rules.equipment_vocabulary_for_save_version(version) == (39 if version >= 39 else 37 if version >= 37 else 34 if version >= 34 else version), "Explicit save-to-equipment mapping retains historical vocabulary")
	var bytes := FileAccess.get_file_as_bytes(ROOT + "fixtures/v40-frozen-v064.json")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "fixtures/manifest.json"))
	check(digest(bytes) == manifest.sha256 and bytes.size() == int(manifest.bytes), "Independent frozen-v064 native serializer fixture matches recorded bytes")
	var source := Rules.decode_v40(JSON.parse_string(bytes.get_string_from_utf8()))
	check(not source.is_empty() and Rules.reason_v40(source).is_empty(), "Full schema40 fixture validates before any migration")
	if source.is_empty():
		quit(1)
		return
	strict_checks(source)
	literal_checks(source,bytes)
	failure_checks(source,bytes)
	chain_checks()
	current_checks(source)
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V065_MIGRATION_REPORT")
	if not output.is_empty(): write(output,(JSON.stringify(evidence,"\t",true,true)+"\n").to_utf8_buffer())
	print("Zealot's Oath source migration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
