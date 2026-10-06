extends SceneTree
## Strict39→40 migration from independent frozen-v063 serializer bytes.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/iron_reflexes_migration.gd")
const Prior = preload("res://scripts/save/defense_rating_affix_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const ROOT := "res://docs/qa/v064-migration/"
const ROUTE := ["50986", "39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544", "10661"]
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
	result.version = 40
	return result


func reject_bytes(name: String, bytes: PackedByteArray, version: int = 39) -> void:
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
	injected.progress = {"level":8,"xp":0}
	injected.talents.class_id = 4
	injected.talents.allocated = ROUTE.duplicate()
	injected.talents.masteries = {}
	injected.talents.normal_points = 0
	check(Rules.reason(injected).is_empty(), "Injected10661 route is otherwise completely legal in current40")
	injected.version = 39
	var calls := [0]
	var permissive := func(_value: Dictionary) -> String: calls[0] += 1; return ""
	check(not Rules.reason_v39(injected,permissive).is_empty() and Rules.decode_v39(injected).is_empty() and Migration.migrate_v39(injected,permissive).is_empty() and calls[0] == 0, "Native frozen39 rejects10661 before any permissive callback")
	reject_bytes("injected39-iron-reflexes",JSON.stringify(injected).to_utf8_buffer())
	var gear_uid := "gear_%06d" % (int(source.next_item_serial)-2)
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "invalid_journey", "bad_uid", "unknown_node", "duplicate_node", "wrong_nodes_type", "unknown_stat", "over_budget", "bad_source", "nan_revision", "nan_mastery", "fractional_roll", "unknown_affix", "missing_location", "reused_serial", "bad_binding", "bad_ledger"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.iron_reflexes = 1.0
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"bad_uid": bad.items[gear_uid].uid = "other"
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"duplicate_node": bad.talents.allocated.append(bad.talents.allocated[0]); bad.talents.normal_points -= 1
			"wrong_nodes_type": bad.talents.allocated = {"47175":true}
			"unknown_stat": bad.talents.iron_reflexes = 1.0
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
		check(not Rules.reason_v39(bad,permissive).is_empty() and Rules.decode_v39(bad).is_empty() and Migration.migrate_v39(bad,permissive).is_empty() and calls[0] == 0, "Complete native frozen39 rejects before callback: " + mutation)
		if mutation == "nan_revision": bad.revision = null
		if mutation == "nan_mastery": bad.talents.masteries["123"] = null
		reject_bytes("invalid39-" + mutation,JSON.stringify(bad).to_utf8_buffer())
	for value: Variant in [null,[],true,39,"39",NAN,INF]:
		check(not Rules.reason_v39(value).is_empty() and Rules.decode_v39(value).is_empty() and Migration.migrate_v39(value).is_empty(), "Wrong envelope types fail before migration")
	reject_bytes("broken-json","{ broken39\r\n".to_utf8_buffer())
	var future := current(source)
	future.version = 41
	reject_bytes("future41",JSON.stringify(future).to_utf8_buffer(),41)
	check(Rules.decode(source).is_empty() and not Rules.reason(source).is_empty() and Rules.decode_v39(current(source)).is_empty(), "Current decoder accepts exactly40; frozen decoder accepts exactly39")
	var reject := func(_value: Dictionary) -> String: return "additional restriction"
	check(Migration.migrate_v39(source,reject).is_empty(), "Optional callbacks may add a further restriction")


func literal_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	var expected := current(source)
	var before := var_to_bytes(source)
	seed(613940)
	var next_rng := randi()
	seed(613940)
	var migrated := Migration.migrate_v39(source)
	check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Migration changes only version; source and global RNG stay untouched")
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Every nonversion field retains identity and content: " + field)
	check(Game._stats_for(migrated) == Game._stats_for(source) and float(Game._stats_for(migrated).get("iron_reflexes",0.0)) == 0.0, "Migration grants no effect to the existing legal build")
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys() and Store.Currency.total_quantity(migrated.items) == Store.Currency.total_quantity(source.items), "Items, UID order, locations and currency are preserved")
	check(Migration.migrate_v39(migrated).is_empty(), "Already migrated envelope is not migrated twice")
	migrated.journey.best_tiers.sunwell_terrace = 3
	check(var_to_bytes(source) == before, "Migrated nested journey is deeply detached")
	var path := "user://frozen-v063-native39.json"
	write(path,bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "Native old39 loads with one atomic commit and notification")
	check(FileAccess.get_file_as_bytes(path + ".v39-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Old39 bytes are backed up verbatim before atomic replacement")
	check(game.migrated_from_legacy, "Game reports the completed migration")
	var disk := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated40 load performs no migration or rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v39-backup.json") == bytes, "Independent40 reopen preserves migrated fields and original-byte backup")
	var dual_uid := "gear_%06d" % (int(source.next_item_serial)-2)
	var payload: Dictionary = source.items[dual_uid].payload
	check(payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="rimeward") and payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="stormward") and reopened.item(dual_uid).payload == payload, "Both schema39 elemental suffixes survive40 without reroll or vocabulary regression")
	check(Equipment.validate_instance_for_version(payload,39) and not Equipment.validate_instance_for_version(payload,37) and not Equipment.validate_instance_for_version(payload,40), "Fixture uses genuine vocabulary39 equipment; equipment40 remains undefined")
	evidence.schema39_sha256 = digest(bytes)
	evidence.schema39_bytes = bytes.size()
	evidence.preserved_items = source.items.size()
	check(payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="ironhide") and payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="mistweave"), "Both vocabulary39 rating prefixes survive unchanged")
	check(Store.Currency.total_quantity(source.items).quantity == 73 and Game._stats_for(source).resolute_technique == 1.0, "Fixture exercises nonzero currency and previously allocated Resolute Technique")
	evidence.preserved_rating_item = payload


func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path,bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "collision": write(path + ".v39-backup.json","retained backup".to_utf8_buffer())
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic": check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject actual temporary-file collision")
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration publishes nothing: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Failed migration preserves original or independent writer bytes")
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup must succeed before first commit attempt")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v39-backup.json") == "retained backup", "Conflicting backup remains verbatim")
		if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path + ".v39-backup.json") == bytes, "Failed commit retains exact raw backup")
		if failure == "atomic":
			check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.snapshot() == current(source) and store.successful_saves == 1 and events[0] == 1, "Identical-backup retry commits once after fault removal")
		else: check(store.save_build(path) != OK, "Failed load protects the same target from a later save")
	var accepted := current(source)
	var accepted_bytes := JSON.stringify(accepted).to_utf8_buffer()
	var accepted_path := "user://accepted40.json"
	write(accepted_path,accepted_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(accepted_path), "Establish current40 live state and disk receipt")
	var failed_path := "user://failed39-replacement.json"
	write(failed_path,bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == accepted and retained._path == accepted_path and retained._disk_bytes == accepted_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Failed old39 commit preserves prior accepted live state and disk receipt")


func chain_checks() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v062-migration/fixtures/v38-frozen-v061.json")
	var old38 := Rules.decode_v38(JSON.parse_string(bytes.get_string_from_utf8()))
	var frozen39 := Prior.migrate_v38(old38)
	var expected39 := old38.duplicate(true)
	expected39.version = 39
	check(not old38.is_empty() and frozen39 == expected39 and Rules.reason_v39(frozen39).is_empty(), "Prior38 to39 still stops at strict39 and changes only version")
	check(Migration.migrate_v39(frozen39) == current(old38), "Frozen38 to39 to40 chain preserves every nonversion field")
	var path := "user://released38-chain.json"
	write(path,bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot() == current(old38) and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v38-backup.json") == bytes and not FileAccess.file_exists(path + ".v39-backup.json"), "Actual38 chain commits once and backs up original38 bytes only")
	var fresh := Store.new().snapshot()
	check(fresh.version == 40 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0 and float(Game._stats_for(fresh).get("iron_reflexes",0.0)) == 0.0, "Fresh full default chain reaches40 without currency or keystone gifts")


func current_checks(source: Dictionary) -> void:
	var candidate := current(source)
	candidate.progress = {"level":8,"xp":0}
	candidate.talents.class_id = 4
	candidate.talents.allocated = ROUTE.duplicate()
	candidate.talents.masteries = {}
	candidate.talents.normal_points = 0
	var store := Store.new()
	store._accept_memory(candidate)
	var path := "user://current40-iron-reflexes.json"
	check(Rules.reason(candidate).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(candidate))) == candidate and store.save_build(path) == OK, "Current40 Iron Reflexes allocation serializes under the complete envelope")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == candidate and reopened.save_attempts == 0 and not FileAccess.file_exists(path+".v39-backup.json"), "Current40 reopens without migration, point grant or reroll")
	var stats := Game._stats_for(reopened.snapshot())
	check(stats.iron_reflexes == 1.0 and stats.evasion == 0.0, "Current40 persisted allocation activates the complete Iron Reflexes consumer")
	evidence.current40_iron_reflexes_route = ROUTE
	evidence.current40_armour = stats.armour
	evidence.current40_evasion = stats.evasion


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v064-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	check(Rules.VERSION == 40 and Rules.V39_VERSION == 39 and Source.CURRENT_SAVE_VERSION == 40 and Equipment.CURRENT_VOCABULARY == 39, "Source/save40 retains equipment vocabulary39")
	check(Source._execution_policy(39) == 38 and Source._execution_policy(40) == 40, "Old39 keeps frozen source policy38")
	for version: int in range(1,41):
		check(Rules.equipment_vocabulary_for_save_version(version) == (39 if version >= 39 else 37 if version >= 37 else 34 if version >= 34 else version), "Explicit save-to-equipment mapping retains historical vocabulary")
	var bytes := FileAccess.get_file_as_bytes(ROOT + "fixtures/v39-frozen-v063.json")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "fixtures/manifest.json"))
	check(digest(bytes) == manifest.sha256 and bytes.size() == int(manifest.bytes), "Independent frozen-v063 native serializer fixture matches recorded bytes")
	var source := Rules.decode_v39(JSON.parse_string(bytes.get_string_from_utf8()))
	check(not source.is_empty() and Rules.reason_v39(source).is_empty(), "Full schema39 fixture validates before any migration")
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
	var output := OS.get_environment("V064_MIGRATION_REPORT")
	if not output.is_empty(): write(output,(JSON.stringify(evidence,"\t",true,true)+"\n").to_utf8_buffer())
	print("Iron Reflexes source migration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
