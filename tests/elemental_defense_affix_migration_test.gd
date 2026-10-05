extends SceneTree
## One focused strict36→37 migration and persistence contract, using released bytes.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/elemental_defense_affix_migration.gd")
const Prior = preload("res://scripts/save/elemental_resistance_cap_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const ROOT := "res://docs/qa/v060-migration/"
const OLD_POOLS := ["legacy", "nine_slot", "runewood", "defense", "local_weapon", "build_legacy_v27", "build_nine_slot_v27", "forgeblade_v34"]
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
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func current(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.version = 37
	return result


func add_gear(candidate: Dictionary, gear: Dictionary) -> void:
	check(Equipment.validate_instance(gear), "Added witness is a valid equipment instance")
	var index := 0
	for location: Dictionary in candidate.locations.values():
		if location.kind == "recovery": index += 1
	candidate.items[gear.id] = Store.Items.wrap_equipment(gear)
	candidate.locations[gear.id] = {"kind":"recovery", "index":index}
	candidate.next_item_serial += 1


func with_elemental_gear(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var gear := {"id":"gear_%06d" % int(result.next_item_serial), "base_id":"emberhide_vest", "rarity":"rare", "item_level":16,
		"affixes":[{"id":"rootwell", "tier":3, "value":32}, {"id":"deepwell", "tier":3, "value":22}, {"id":"lanternveil", "tier":3, "value":22},
			{"id":"emberward", "tier":3, "value":25}, {"id":"rimeward", "tier":3, "value":25}, {"id":"stormward", "tier":3, "value":25}]}
	add_gear(result, gear)
	return result


func reject_bytes(name: String, bytes: PackedByteArray, version: int = 36) -> void:
	var path := "user://" + name + ".json"
	write(path, bytes)
	var store := Store.new()
	var before := store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Invalid source preserves original bytes and live state: " + name)
	check(store.save_attempts == 0 and store.successful_saves == 0 and events[0] == 0 and not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Invalid source causes no backup, save or notification")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Invalid original is protected from a later save")


func test_strict_boundary(source: Dictionary) -> void:
	var injected := with_elemental_gear(source)
	var valid := current(injected)
	check(Rules.reason(valid).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(valid))) == valid, "Dual resistance item is independently legal in schema37")
	Store.Items.metadata_for_items(valid.items)
	var permissive := func(_value: Dictionary) -> String: return ""
	check(not Rules.reason_v36(injected, permissive).is_empty() and Rules.decode_v36(injected).is_empty() and Migration.migrate_v36(injected, permissive).is_empty(), "Positive current metadata and permissive callback cannot inject new affixes into36")
	reject_bytes("injected36-dual-resistance", JSON.stringify(injected).to_utf8_buffer())
	injected.version = 35
	check(not Rules.reason_v35(injected, permissive).is_empty() and Rules.decode_v35(injected).is_empty() and Prior.migrate_v35(injected, permissive).is_empty(), "Schema35 also retains equipment vocabulary34")
	reject_bytes("injected35-dual-resistance", JSON.stringify(injected).to_utf8_buffer(), 35)
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "invalid_journey", "bad_uid", "unknown_node", "duplicate_node", "wrong_nodes_type", "unknown_stat", "over_budget", "bad_source", "nan_revision", "nan_mastery", "fractional_roll", "unknown_affix"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.cold_resistance = 0.25
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"bad_uid": bad.items[bad.items.keys()[0]].uid = "other"
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"duplicate_node": bad.talents.allocated.append(bad.talents.allocated[0]); bad.talents.normal_points -= 1
			"wrong_nodes_type": bad.talents.allocated = {"58833":true}
			"unknown_stat": bad.talents.cold_resistance = 0.25
			"over_budget": bad.talents.normal_points += 1
			"bad_source": bad.talents.source_version = "3.29.2"
			"nan_revision": bad.revision = NAN
			"nan_mastery": bad.talents.masteries["123"] = NAN
			"fractional_roll", "unknown_affix":
				var rng := RandomNumberGenerator.new()
				rng.seed = 6036
				var gear := Equipment.generate_for_pool(rng, "gear_%06d" % int(bad.next_item_serial), 16, "rare", "defense")
				add_gear(bad, gear)
				if mutation == "fractional_roll": bad.items[gear.id].payload.affixes[0].value = 9.5
				else: bad.items[gear.id].payload.affixes[0].id = "unrecognized_affix"
		check(not Rules.reason_v36(bad, permissive).is_empty() and Rules.decode_v36(bad).is_empty() and Migration.migrate_v36(bad, permissive).is_empty(), "Complete frozen36 rejection despite callback: " + mutation)
		if mutation == "nan_revision": bad.revision = null
		if mutation == "nan_mastery": bad.talents.masteries["123"] = null
		reject_bytes("invalid36-" + mutation, JSON.stringify(bad).to_utf8_buffer())
	for value: Variant in [null, [], true, 36, "36", NAN, INF]:
		check(not Rules.reason_v36(value).is_empty() and Rules.decode_v36(value).is_empty() and Migration.migrate_v36(value).is_empty(), "Wrong envelope types fail before migration")
	reject_bytes("broken-json", "{ invalid old bytes\r\n".to_utf8_buffer())
	var future := current(source)
	future.version = 38
	reject_bytes("future38", JSON.stringify(future).to_utf8_buffer(), 38)
	var rejected_callback := func(_value: Dictionary) -> String: return "additional restriction"
	check(Migration.migrate_v36(source, rejected_callback).is_empty(), "Optional validator may still add restrictions")


func test_literal(source: Dictionary, bytes: PackedByteArray) -> void:
	var expected := current(source)
	var before := var_to_bytes(source)
	seed(603637)
	var next_rng := randi()
	seed(603637)
	var migrated := Migration.migrate_v36(source)
	check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Migration changes only version and leaves source/global RNG untouched")
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Exact preservation of released field: " + field)
	check(Game._stats_for(migrated) == Game._stats_for(source), "Existing complete stats remain identical")
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys(), "UID and location insertion order stay unchanged")
	check(Migration.migrate_v36(migrated).is_empty(), "Already migrated envelope cannot be migrated again")
	migrated.journey.best_tiers.sunwell_terrace = 3
	check(var_to_bytes(source) == before, "Migration deeply detaches nested journey")
	var path := "user://released36.json"
	write(path, bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "Actual released36 saves and publishes one migration")
	check(FileAccess.get_file_as_bytes(path + ".v36-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Raw released bytes are backed up before atomic commit")
	check(game.migrated_from_legacy and game.migration_message.contains("冰霜") and game.migration_message.contains("闪电"), "Migration message names newly opened equipment defenses")
	var disk := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated current load does not migrate or rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v36-backup.json") == bytes, "Independent current37 reopen preserves content and original backup")
	evidence.released36_sha256 = digest(bytes)
	evidence.released36_bytes = bytes.size()


func test_old_pools_and_source(source: Dictionary) -> void:
	var candidate := source.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 603436
	for pool: String in OLD_POOLS:
		var gear := Equipment.generate_for_pool(rng, "gear_%06d" % int(candidate.next_item_serial), 16, "rare", pool)
		check(Equipment.validate_instance_for_version(gear, 34) and not Equipment.validate_instance_for_version(gear, 35) and not Equipment.validate_instance_for_version(gear, 36), "Direct equipment vocabulary35/36 keeps historical rejection: " + pool)
		add_gear(candidate, gear)
	check(Rules.reason_v36(candidate).is_empty() and Rules.decode_v36(JSON.parse_string(JSON.stringify(candidate))) == candidate, "All frozen pools validate in schema36 via vocabulary34")
	var old35 := candidate.duplicate(true)
	old35.version = 35
	check(Rules.reason_v35(old35).is_empty() and Rules.decode_v35(JSON.parse_string(JSON.stringify(old35))) == old35 and Prior.migrate_v35(old35) == candidate, "All frozen pools validate in schema35 and prior migration still ends at36")
	var expected := current(candidate)
	var state := rng.state
	check(Migration.migrate_v36(candidate) == expected and rng.state == state, "Every frozen pool payload survives migration without reroll")
	var path := "user://all-old-pools.json"
	var bytes := JSON.stringify(candidate, "\t", true, true).to_utf8_buffer()
	write(path, bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot() == expected and FileAccess.get_file_as_bytes(path + ".v36-backup.json") == bytes, "All old pool payloads, serials, currency, points and journey persist exactly")
	var witness: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v059-source/allocation-witness.json"))
	var capped := source.duplicate(true)
	capped.progress = {"level":69, "xp":0}
	capped.talents.class_id = 1
	capped.talents.allocated = witness.allocated.duplicate()
	capped.talents.masteries = {}
	capped.talents.normal_points = 0
	check(Rules.reason_v36(capped).is_empty() and Migration.migrate_v36(capped) == current(capped), "Full released36 cap route stays legal with every allocation and point unchanged")
	check(Game._stats_for(capped) == Game._stats_for(current(capped)) and Source._execution_policy(37) == 36, "Schema37 retains identical source-policy36 grants and stats")
	evidence.frozen_equipment_pools = OLD_POOLS
	evidence.preserved_source_allocations = capped.talents.allocated.size()


func test_failures(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["collision", "backup", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path, bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "collision": write(path + ".v36-backup.json", "retained backup".to_utf8_buffer())
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic": check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject real temporary-file collision")
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration publishes nothing: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Failure preserves original or independent writer bytes")
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup succeeds before first commit attempt")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v36-backup.json") == "retained backup", "Conflicting backup remains verbatim")
		if failure in ["external", "atomic"]: check(FileAccess.get_file_as_bytes(path + ".v36-backup.json") == bytes, "Failed commit retains exact raw backup")
		if failure == "atomic":
			check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.snapshot() == current(source) and store.successful_saves == 1 and events[0] == 1, "Identical-backup retry commits exactly once")
		else: check(store.save_build(path) != OK, "Failed load protects later saves")
	var accepted := current(source)
	var accepted_bytes := JSON.stringify(accepted).to_utf8_buffer()
	var accepted_path := "user://retained-current37.json"
	write(accepted_path, accepted_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(accepted_path), "Accept current37 disk receipt")
	var failed_path := "user://failed-old-replacement.json"
	write(failed_path, bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == accepted and retained._path == accepted_path and retained._disk_bytes == accepted_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Failed old load preserves previously accepted live snapshot and disk receipt")
	var malformed_path := "user://malformed36-replacement.json"
	var malformed := source.duplicate(true)
	malformed.talents.normal_points += 1
	var malformed_bytes := JSON.stringify(malformed).to_utf8_buffer()
	write(malformed_path, malformed_bytes)
	check(not retained.load_build(malformed_path) and retained.snapshot() == accepted and retained._path == accepted_path and retained._disk_bytes == accepted_bytes and FileAccess.get_file_as_bytes(malformed_path) == malformed_bytes, "Malformed old36 also preserves an existing accepted snapshot and receipt")


func test_current_roundtrip(source: Dictionary) -> void:
	var candidate := current(with_elemental_gear(source))
	var uid := "gear_%06d" % (int(candidate.next_item_serial) - 1)
	var store := Store.new()
	store._accept_memory(candidate)
	var path := "user://current37-dual-resistance.json"
	check(store.save_build(path) == OK and Rules.reason(candidate).is_empty(), "Current37 dual resistance item saves")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == candidate and reopened.save_attempts == 0, "Current37 item reloads without migration or rewrite")
	var destination := reopened.first_bag_position(uid)
	check(not destination.is_empty(), "Dual resistance item has a real bag destination")
	var bytes := FileAccess.get_file_as_bytes(path)
	var events := [0]
	reopened.changed.connect(func(): events[0] += 1)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create actual transaction save fault")
	check(not reopened.move_item(uid, destination, reopened.revision(), path).ok and reopened.snapshot() == candidate and reopened._disk_bytes == bytes and FileAccess.get_file_as_bytes(path) == bytes and events[0] == 0, "Failed new-item movement preserves rolls, revision, currency, location and receipt")
	check(DirAccess.remove_absolute(path + ".tmp") == OK and reopened.move_item(uid, destination, reopened.revision(), path).ok and reopened.revision() == candidate.revision + 1 and events[0] == 1, "New-item transaction retries once after fault removal")
	var committed := reopened.snapshot()
	bytes = FileAccess.get_file_as_bytes(path)
	write(path, "external after commit".to_utf8_buffer())
	check(reopened.save_build(path) == ERR_FILE_ALREADY_IN_USE and reopened.snapshot() == committed and reopened._disk_bytes == bytes and FileAccess.get_file_as_string(path) == "external after commit", "New-item save receipt protects subsequent external edits")
	evidence.current37_payload = candidate.items[uid].payload


func test_prior_chain() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v059-source/fixtures/v35-released.json")
	var old35 := Rules.decode_v35(JSON.parse_string(bytes.get_string_from_utf8()))
	var frozen36 := Prior.migrate_v35(old35)
	var expected36 := old35.duplicate(true)
	expected36.version = 36
	check(not old35.is_empty() and frozen36 == expected36 and Rules.reason_v36(frozen36).is_empty(), "Previous35→36 migration remains frozen and version-only")
	check(Migration.migrate_v36(frozen36) == current(old35), "35→36→37 chain changes only version")
	var path := "user://released35-chain.json"
	write(path, bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot() == current(old35) and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v35-backup.json") == bytes and not FileAccess.file_exists(path + ".v36-backup.json"), "Genuine35 chain commits once and backs up original35 bytes only")
	var old34_bytes := FileAccess.get_file_as_bytes("res://docs/qa/v056/fixtures/v34-default.json")
	var old34 := Rules.decode_v34(JSON.parse_string(old34_bytes.get_string_from_utf8()))
	path = "user://released34-chain.json"
	write(path, old34_bytes)
	var previous := Store.new()
	check(previous.load_build(path) and previous.snapshot() == current(old34) and previous.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v34-backup.json") == old34_bytes, "Genuine34 reaches37 with all original fields and a single original-byte backup")
	var legacy := Store.Legacy.new()._snapshot()
	var legacy_bytes := JSON.stringify(legacy).to_utf8_buffer()
	path = "user://legacy-full-chain.json"
	write(path, legacy_bytes)
	var full := Store.new()
	check(full.load_build(path) and full.snapshot().version == 37 and Rules.reason(full.snapshot()).is_empty() and full.save_attempts == 1, "Legacy fixture traverses full historical chain through frozen36 to37")
	check(FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % int(legacy.version)) == legacy_bytes, "Full-chain backup uses original legacy version and bytes")
	var fresh := Store.new().snapshot()
	check(fresh == current(old34) and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0, "Built-in fixture reaches37 without equipment or currency grants")
	evidence.prior35_sha256 = digest(bytes)
	evidence.prior34_sha256 = digest(old34_bytes)


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v060-migration-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	check(Rules.VERSION == 37 and Rules.V36_VERSION == 36 and Equipment.CURRENT_VOCABULARY == 37 and Source.CURRENT_SAVE_VERSION == 36, "Equipment envelope37 retains source execution policy36")
	for version: int in range(1, 38):
		check(Rules.equipment_vocabulary_for_save_version(version) == (37 if version == 37 else 34 if version >= 34 else version), "Save-to-equipment mapping preserves each earlier vocabulary")
	var bytes := FileAccess.get_file_as_bytes(ROOT + "fixtures/v36-released.json")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "fixtures/manifest.json"))
	check(digest(bytes) == manifest.sha256 and bytes.size() == int(manifest.bytes), "Released36 fixture matches original committed bytes")
	var source := Rules.decode_v36(JSON.parse_string(bytes.get_string_from_utf8()))
	check(not source.is_empty() and Rules.reason_v36(source).is_empty(), "Genuine released36 envelope validates before migration")
	if source.is_empty():
		quit(1)
		return
	test_strict_boundary(source)
	test_literal(source, bytes)
	test_old_pools_and_source(source)
	test_failures(source, bytes)
	test_current_roundtrip(source)
	test_prior_chain()
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V060_MIGRATION_REPORT")
	if not output.is_empty(): write(output, (JSON.stringify(evidence, "\t", true, true) + "\n").to_utf8_buffer())
	print("Elemental defense affix migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
