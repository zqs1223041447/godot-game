extends SceneTree
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/ignite_gem_migration.gd")
const EquipmentMigration = preload("res://scripts/save/equipment_affix_migration.gd")
const Prior = preload("res://scripts/save/normal_journey_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const Trade = preload("res://scripts/items/gem_trade_rules.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const FIXTURES := "res://docs/qa/v045/ignite-migration-fixtures/"
const NEW_ID := "support:ignite"


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


func test_literal(name: String, manifest: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + name)
	check(bytes.size() == int(manifest.files[name].bytes) and digest(bytes) == manifest.files[name].sha256 and bytes.get_string_from_utf8().begins_with(" \r\n"), "Literal frozen v44 fixture digest/CRLF: " + name)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var source := Rules.decode_v27(raw)
	check(not source.is_empty() and Rules.reason_v27(source).is_empty() and Rules.decode(raw).is_empty(), "Strict frozen27 envelope: " + name)
	if source.is_empty(): return
	var before := var_to_bytes(source)
	var expected := source.duplicate(true)
	expected.version = 28
	check(Migration.migrate_v27(source) == expected and var_to_bytes(source) == before, "Pure migration changes only version: " + name)
	for field: String in Rules.FIELDS:
		if field != "version": check(expected[field] == source[field], "Version-only preserved field " + field + ": " + name)
	check(Migration.migrate_v27(expected).is_empty(), "Current snapshot cannot migrate twice: " + name)
	if name != "v27-default.json":
		check(source.items.has("gear_000004") and source.items.has("item_000005") and source.items.item_000005.payload.quantity == 6 and source.crafting.revision == 1 and source.next_item_serial == 9, "Released UID/currency/craft metadata is nontrivial: " + name)
		check(source.progress == {"level": 4, "xp": 6} and source.talents.normal_points == 8 and source.journey.normal_root_kills == 90 and source.journey.claimed_gems == 2 and source.journey.claimed_flasks == 1, "Released XP/budget/claim ordinals are preserved: " + name)
		check(source.bindings.has({"group_id": "group_000001", "keycode": KEY_F1}), "Real released binding change is preserved: " + name)
	if name == "v27-active.json":
		check(source.revision == 121 and source.journey.active_run.run_id == 10 and source.journey.active_run.fee_paid == 4 and source.journey.active_run.tier == 2 and source.journey.pending_map_reward.is_empty(), "Paid active tier2 remains active")
	if name == "v27-pending.json":
		check(source.revision == 122 and source.journey.active_run.is_empty() and source.journey.pending_map_reward == {"run_id": 10, "map_id": "old_garden", "tier": 2, "shards": 12}, "Pending tier2 reward remains owed")
	var path := "user://ignite-" + name
	write(path, bytes)
	var store := Store.new()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(store.load_build(path) and store.snapshot() == expected, "Store changes only27 to28: " + name)
	check(store.save_attempts == 1 and store.successful_saves == 1 and signals[0] == 1, "Migration writes/notifies once: " + name)
	check(FileAccess.get_file_as_bytes(path + ".v27-backup.json") == bytes, "Backup equals original literal bytes: " + name)
	var disk := FileAccess.get_file_as_bytes(path)
	check(store._disk_revision == source.revision and store._disk_bytes == disk and store._disk_expected_exists and store._path == path, "Migration installs exact disk receipt: " + name)
	check(not FileAccess.file_exists(path + ".tmp"), "Atomic primary commit leaves no temporary file: " + name)
	check(Rules.decode(JSON.parse_string(disk.get_string_from_utf8())) == expected, "Persisted candidate matches every field: " + name)
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Current reread does not rewrite: " + name)
	var fresh := Store.new()
	check(fresh.load_build(path) and fresh.snapshot() == expected and fresh.successful_saves == 0 and FileAccess.get_file_as_bytes(path + ".v27-backup.json") == bytes, "Independent reopen migrates zero times: " + name)
	var conflict_path := "user://collision-" + name
	write(conflict_path, bytes)
	var other := PackedByteArray([1, 2, 3])
	write(conflict_path + ".v27-backup.json", other)
	var conflict := Store.new()
	var initial := conflict.snapshot()
	check(not conflict.load_build(conflict_path) and conflict.snapshot() == initial and FileAccess.get_file_as_bytes(conflict_path) == bytes and FileAccess.get_file_as_bytes(conflict_path + ".v27-backup.json") == other and conflict.save_attempts == 0, "Existing different backup is never overwritten: " + name)
	check(conflict.save_build(conflict_path) != OK, "Backup collision protects later writes: " + name)
	var backup_path := "user://backup-fail-" + name
	write(backup_path, bytes)
	var backup := Store.new()
	initial = backup.snapshot()
	backup._io = BackupFailIO.new()
	check(not backup.load_build(backup_path) and backup.snapshot() == initial and FileAccess.get_file_as_bytes(backup_path) == bytes and backup.save_attempts == 0, "Backup failure prevents commit: " + name)
	var fault_path := "user://fault-" + name
	write(fault_path, bytes)
	var fault := FaultStore.new()
	initial = fault.snapshot()
	fault.fail_save = true
	var fault_signals := [0]
	fault.changed.connect(func(): fault_signals[0] += 1)
	check(not fault.load_build(fault_path) and fault.snapshot() == initial and FileAccess.get_file_as_bytes(fault_path) == bytes and fault_signals[0] == 0 and fault.successful_saves == 0, "Migration write failure rolls back memory/source: " + name)
	check(FileAccess.get_file_as_bytes(fault_path + ".v27-backup.json") == bytes, "Failed commit retains exact original backup: " + name)
	fault.fail_save = false
	check(fault.load_build(fault_path) and fault.snapshot() == expected and fault.successful_saves == 1 and fault_signals[0] == 1, "Retry with matching backup succeeds once: " + name)
	var external_path := "user://external-" + name
	write(external_path, bytes)
	var external := Store.new()
	external._io = ExternalIO.new()
	initial = external.snapshot()
	check(not external.load_build(external_path) and external.snapshot() == initial and FileAccess.get_file_as_string(external_path) == "external writer" and external.save_attempts == 0, "External primary rewrite is preserved: " + name)
	check(FileAccess.get_file_as_bytes(external_path + ".v27-backup.json") == bytes, "External writer retains old backup: " + name)


func with_ignite(source: Dictionary, linked: bool) -> Dictionary:
	var candidate := source.duplicate(true)
	candidate.items["item_000900"] = Gems.create_instance("item_000900", NEW_ID)
	candidate.locations["item_000900"] = {"kind": "skill_support", "group_id": "group_000007", "index": 0} if linked else {"kind": "bag", "page": 1, "x": 11, "y": 9}
	candidate.next_item_serial = 901
	return candidate


func test_vocabulary(source: Dictionary) -> void:
	check(Gems.minimum_save_version(NEW_ID) == 28 and Equipment.CURRENT_VOCABULARY == 27, "Ignite alone opens gem schema28; equipment vocabulary stays27")
	check(not Supports.saved_links_reason("meteor", ["ignite"], 27).is_empty() and Supports.saved_links_reason("meteor", ["ignite"], 28).is_empty(), "Linked support version gate rejects27 and accepts28")
	for linked: bool in [false, true]:
		var old := with_ignite(source, linked)
		var current := old.duplicate(true)
		current.version = 28
		check(not old.items.item_000900.is_empty() and Rules.reason(current).is_empty(), "Schema28 accepts valid ignite in " + ("link" if linked else "bag"))
		check(Items.metadata_for_items(current.items).size() == current.items.size(), "Warm current metadata cache before frozen-schema rejection")
		check(Rules.decode_v27(JSON.parse_string(JSON.stringify(old))).is_empty() and not Rules.reason_v27(old).is_empty() and Migration.migrate_v27(old).is_empty(), "Frozen27 rejects known new support before migration")
		check(not Rules.reason_v27(old, func(_value: Dictionary) -> String: return "").is_empty(), "Custom talent validator cannot bypass gem vocabulary")
		for existing_backup: bool in [false, true]:
			rejected_preserving("user://injected27-%s-%s.json" % [str(linked), str(existing_backup)], JSON.stringify(old).to_utf8_buffer(), 27, existing_backup)
		check(Rules.decode(JSON.parse_string(JSON.stringify(current))) == current, "Current JSON accepts integer-normalized gem payload")
		var path := "user://current28-%s.json" % str(linked)
		var bytes := JSON.stringify(current, "\t", true, true).to_utf8_buffer()
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == current and store.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(path + ".v28-backup.json"), "Current28 opens without migration or rewrite")
		var older := old.duplicate(true)
		older.version = 26
		check(Rules.decode_v26(older).is_empty() and not Rules.reason_v26(older).is_empty() and EquipmentMigration.migrate_v26(older).is_empty(), "Frozen26 cannot launder ignite into27")
		older.version = 25
		older.erase("journey")
		check(Rules.decode_v25(older).is_empty() and not Rules.reason_v25(older).is_empty() and Prior.migrate_v25(older).is_empty(), "Frozen25 cannot launder ignite through the chain")
	for malformed: Variant in [true, 0.5, "1", null]:
		var old_bad := source.duplicate(true)
		old_bad.items.migration_gem_000001.payload.level = malformed
		check(Rules.decode_v27(JSON.parse_string(JSON.stringify(old_bad))).is_empty() and not Rules.reason_v27(old_bad).is_empty() and Migration.migrate_v27(old_bad).is_empty(), "Old27 existing gem payload is still strict: " + str(malformed))
		rejected_preserving("user://old27-bad-level-" + str(malformed) + ".json", JSON.stringify(old_bad).to_utf8_buffer(), 27)
	var valid := with_ignite(source, false)
	valid.version = 28
	for field: String in ["level", "quality"]:
		for malformed: Variant in [true, false, 0.5, "1", null, 2]:
			var bad := valid.duplicate(true)
			bad.items.item_000900.payload[field] = malformed
			check(Rules.decode(JSON.parse_string(JSON.stringify(bad))).is_empty() and not Rules.reason(bad).is_empty(), "Reject malformed ignite payload " + field + ": " + str(malformed))
			if malformed is bool or malformed is float:
				rejected_preserving("user://bad28-%s-%s.json" % [field, str(malformed)], JSON.stringify(bad).to_utf8_buffer(), 28)
		var direct_float := valid.duplicate(true)
		direct_float.items.item_000900.payload[field] = 1.0 if field == "level" else 0.0
		check(not Rules.reason(direct_float).is_empty() and not Gems.validate_instance(direct_float.items.item_000900), "Direct gem payload must retain real integers: " + field)
	for malformed: Variant in [true, 28, null, "ignite", "support:unknown_ignite", "support:Ignite", "点燃", "support:ignite ", &"support:ignite"]:
		var bad := valid.duplicate(true)
		bad.items.item_000900.definition_id = malformed
		check(not Rules.reason(bad).is_empty() and not Gems.validate_instance(bad.items.item_000900), "Reject malformed or aliased definition identity: " + str(malformed))
		if not malformed is StringName:
			check(Rules.decode(bad).is_empty(), "Decoder rejects malformed identity: " + str(malformed))
	for field: String in ["uid", "kind"]:
		var bad := valid.duplicate(true)
		bad.items.item_000900[field] = StringName(str(bad.items.item_000900[field]))
		check(not Rules.reason(bad).is_empty(), "StringName wrapper field is not a string: " + field)
	var extra := valid.duplicate(true)
	extra.items.item_000900.payload["ignite_chance"] = 1
	check(Rules.decode(extra).is_empty() and not Rules.reason(extra).is_empty(), "Derived ignite data cannot be persisted inside payload")


func test_frozen_rewards(manifest: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + "v27-vocabulary-oracle.json")
	check(digest(bytes) == manifest.files["v27-vocabulary-oracle.json"].sha256, "Frozen v44 reward/catalog oracle digest")
	var oracle: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	check(Journey.GEM_DEFINITIONS == oracle.gem_definitions and Journey.GEM_DEFINITIONS.size() == 26 and not Journey.GEM_DEFINITIONS.has(NEW_ID), "Exact26 schema26 normal reward definitions remain frozen")
	for index: int in range(oracle.milestones.size()):
		check(Journey.gem_definition(index + 1) == oracle.milestones[index], "Old owed milestone identity preserved at ordinal %d" % (index + 1))
	for definition_id: String in oracle.minimum_save_versions:
		check(Gems.minimum_save_version(definition_id) == int(oracle.minimum_save_versions[definition_id]), "Old gem minimum schema unchanged: " + definition_id)
	check(digest(FileAccess.get_file_as_bytes("res://scripts/world/normal_journey_state.gd")) == manifest.normal_journey_source_signature.sha256, "NormalJourneyState source remains byte-identical to v44")
	var fresh := Store.new().snapshot()
	check(fresh.version == 28 and fresh.journey == Journey.empty(), "Fresh chain ends at28 with untouched empty journey")
	for item: Dictionary in fresh.items.values():
		check(item.definition_id != NEW_ID, "Schema migration never gifts ignite")
	check(Trade.quote("buy", NEW_ID).ok and Trade.quote("buy", NEW_ID).cost == {"calibration_shard": 4}, "Dynamic gem trade offers ignite at unchanged support cost")
	var offer_ids: Array[String] = []
	for offer: Dictionary in Trade.offers(): offer_ids.append(offer.definition_id)
	check(offer_ids.has(NEW_ID) and offer_ids.size() == 27 and Trade.ACTIVE_COST == 8 and Trade.SUPPORT_COST == 4 and Trade.RECYCLE_CREDIT == 1, "Catalog expands to27 offers without economy changes")


func test_prior_chain() -> void:
	for version: int in [25, 26]:
		var filename := "res://tests/fixtures/v041_journey/v25-default.json" if version == 25 else "res://tests/fixtures/v042_affixes/v26-active.json"
		var bytes := FileAccess.get_file_as_bytes(filename)
		var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		var source := Rules.decode_v25(raw) if version == 25 else Rules.decode_v26(raw)
		check(not source.is_empty(), "Literal prior fixture decodes at%d" % version)
		var v26 := Prior.migrate_v25(source) if version == 25 else source.duplicate(true)
		check(not v26.is_empty() and v26.version == 26 and Rules.reason_v26(v26).is_empty(), "Previous25 migration stays pinned to26")
		var v27 := EquipmentMigration.migrate_v26(v26)
		check(not v27.is_empty() and v27.version == 27 and Rules.reason_v27(v27).is_empty(), "Previous26 migration stays pinned to27")
		var expected := v26.duplicate(true)
		expected.version = 28
		check(Migration.migrate_v27(v27) == expected, "Prior chain introduces no extra gifts/changes")
		var path := "user://chain%d.json" % version
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and store.save_attempts == 1, "Prior%d reaches28 in one write" % version)
		check(FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % version) == bytes and not FileAccess.file_exists(path + ".v27-backup.json"), "Chained migration backs up only real original%d bytes" % version)


func test_real_atomic_failure(source: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + "v27-default.json")
	var path := "user://atomic-temporary-collision.json"
	write(path, bytes)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create isolated primary-temp directory collision")
	var store := Store.new()
	var initial := store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes and signals[0] == 0 and store.successful_saves == 0 and store.save_attempts == 1, "Real atomic temp-open failure preserves primary and memory")
	check(FileAccess.get_file_as_bytes(path + ".v27-backup.json") == bytes, "Real commit failure still preserves original raw backup")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove only isolated temporary collision")
	var expected := source.duplicate(true)
	expected.version = 28
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and signals[0] == 1, "Retry real atomic failure with same backup succeeds once")
	var disk := FileAccess.get_file_as_bytes(path)
	write(path, "external writer after migration".to_utf8_buffer())
	check(store.save_build(path) == ERR_FILE_ALREADY_IN_USE and store.snapshot() == expected and store._disk_bytes == disk and FileAccess.get_file_as_string(path) == "external writer after migration", "Migrated receipt still protects external changes")
	var retained_path := "user://retained-receipt28.json"
	var retained_bytes := JSON.stringify(expected, "\t", true, true).to_utf8_buffer()
	write(retained_path, retained_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(retained_path), "Load current28 before testing failure receipt retention")
	var retained_snapshot := retained.snapshot()
	var failed_path := "user://failed-with-existing-receipt27.json"
	var failed_bytes := FileAccess.get_file_as_bytes(FIXTURES + "v27-active.json")
	write(failed_path, failed_bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == retained_snapshot and retained._path == retained_path and retained._disk_bytes == retained_bytes and retained._disk_revision == retained_snapshot.revision and retained._disk_expected_exists, "Failed migration retains the previously accepted current receipt")
	check(FileAccess.get_file_as_bytes(failed_path) == failed_bytes and FileAccess.get_file_as_bytes(retained_path) == retained_bytes, "Failed replacement changes neither original nor previously loaded file")
	var message_path := "user://migration-message.json"
	write(message_path, bytes)
	var game := Game.new()
	check(game.load_build(message_path) and game.migrated_from_legacy and game.migration_message.contains("点燃") and not game.migration_message.contains("两瓶药剂"), "Old27 gets accurate non-grant migration message")


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "manifest.json"))
	check(Rules.VERSION == 28 and Rules.V27_VERSION == 27 and Rules.SourceTree.CURRENT_SAVE_VERSION == 25 and Rules.SourceTree._execution_policy(28) == 25, "Schema28 does not expand source passive vocabulary")
	for name: String in ["v27-default.json", "v27-active.json", "v27-pending.json"]:
		test_literal(name, manifest)
	var source := Rules.decode_v27(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v27-default.json")))
	test_vocabulary(source)
	for mutation: String in ["future", "duplicate_binding", "fractional_revision", "bool_revision", "extra_field", "missing_journey", "invalid_journey"]:
		var bad := source.duplicate(true)
		match mutation:
			"future": bad.version = 29
			"duplicate_binding": bad.bindings.append(bad.bindings[0].duplicate())
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"extra_field": bad.live_ignite_instances = []
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.normal_root_kills = 0.5
		rejected_preserving("user://invalid27-" + mutation + ".json", JSON.stringify(bad).to_utf8_buffer(), int(bad.version))
	test_frozen_rewards(manifest)
	test_prior_chain()
	test_real_atomic_failure(source)
	print("Ignite gem migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
