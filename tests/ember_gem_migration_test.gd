extends SceneTree
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/ember_gem_migration.gd")
const IgniteMigration = preload("res://scripts/save/ignite_gem_migration.gd")
const EquipmentMigration = preload("res://scripts/save/equipment_affix_migration.gd")
const Prior = preload("res://scripts/save/normal_journey_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const Trade = preload("res://scripts/items/gem_trade_rules.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const FIXTURES := "res://docs/qa/v047-migration/fixtures/"
const NEW_ID := "support:ember_proliferation"


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
	check(bytes.size() == int(manifest.files[name].bytes) and digest(bytes) == manifest.files[name].sha256 and bytes.get_string_from_utf8().begins_with(" \r\n"), "Literal frozen v46 fixture digest/CRLF: " + name)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var source := Rules.decode_v28(raw)
	check(not source.is_empty() and Rules.reason_v28(source).is_empty() and Rules.decode(raw).is_empty(), "Strict frozen28 envelope: " + name)
	if source.is_empty(): return
	var before := var_to_bytes(source)
	var expected := source.duplicate(true)
	expected.version = 29
	seed(470029)
	var next_rng := randi()
	seed(470029)
	var migrated := Migration.migrate_v28(source)
	check(randi() == next_rng, "Envelope migration consumes no RNG draw: " + name)
	check(migrated == expected and var_to_bytes(source) == before, "Pure migration changes only version: " + name)
	for field: String in Rules.FIELDS:
		if field != "version": check(expected[field] == source[field], "Version-only preserved field " + field + ": " + name)
	check(Migration.migrate_v28(expected).is_empty(), "Current snapshot cannot migrate twice: " + name)
	if name != "v28-default.json":
		check(source.items.has("gear_000004") and source.items.item_000009.definition_id == "support:ignite" and source.crafting.revision == 1 and source.next_item_serial == 10, "Released equipment, old ignite UID and craft/serial metadata survive: " + name)
		check(source.bindings.has({"group_id": "group_000001", "keycode": KEY_F1}), "Released binding change is preserved: " + name)
	if name == "v28-ignite-bag.json":
		check(source.locations.item_000009.kind == "bag" and source.items.item_000005.payload.quantity == 10, "Old paid ignite in bag remains unchanged")
	if name in ["v28-active.json", "v28-pending.json"]:
		check(source.progress == {"level": 4, "xp": 6} and source.talents.normal_points == 8 and source.journey.normal_root_kills == 90 and source.journey.claimed_gems == 2 and source.journey.claimed_flasks == 1, "Released XP, budgets and owed ordinals survive: " + name)
		check(source.locations.item_000009 == {"kind": "skill_support", "group_id": "group_000007", "index": 0} and source.items.item_000005.payload.quantity == 6, "Old linked ignite and paid currency stay exact: " + name)
	if name == "v28-active.json":
		check(source.revision == 123 and source.journey.active_run.run_id == 10 and source.journey.active_run.fee_paid == 4 and source.journey.active_run.tier == 2 and source.journey.pending_map_reward.is_empty(), "Paid active tier2 remains active")
	if name == "v28-pending.json":
		check(source.revision == 124 and source.journey.active_run.is_empty() and source.journey.pending_map_reward == {"run_id": 10, "map_id": "old_garden", "tier": 2, "shards": 12}, "Pending tier2 reward remains owed")
	var path := "user://ember-" + name
	write(path, bytes)
	var store := Store.new()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(store.load_build(path) and store.snapshot() == expected, "Store changes only28 to29: " + name)
	check(store.save_attempts == 1 and store.successful_saves == 1 and signals[0] == 1, "Migration writes/notifies once: " + name)
	check(FileAccess.get_file_as_bytes(path + ".v28-backup.json") == bytes, "Backup equals original literal bytes: " + name)
	var disk := FileAccess.get_file_as_bytes(path)
	check(store._disk_revision == source.revision and store._disk_bytes == disk and store._disk_expected_exists and store._path == path, "Migration installs exact disk receipt: " + name)
	check(not FileAccess.file_exists(path + ".tmp"), "Atomic primary commit leaves no temporary file: " + name)
	check(Rules.decode(JSON.parse_string(disk.get_string_from_utf8())) == expected, "Persisted candidate matches every field: " + name)
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Current reread does not rewrite: " + name)
	var fresh := Store.new()
	check(fresh.load_build(path) and fresh.snapshot() == expected and fresh.successful_saves == 0 and FileAccess.get_file_as_bytes(path + ".v28-backup.json") == bytes, "Independent reopen migrates zero times: " + name)
	var conflict_path := "user://collision-" + name
	write(conflict_path, bytes)
	var other := PackedByteArray([1, 2, 3])
	write(conflict_path + ".v28-backup.json", other)
	var conflict := Store.new()
	var initial := conflict.snapshot()
	check(not conflict.load_build(conflict_path) and conflict.snapshot() == initial and FileAccess.get_file_as_bytes(conflict_path) == bytes and FileAccess.get_file_as_bytes(conflict_path + ".v28-backup.json") == other and conflict.save_attempts == 0, "Existing different backup is never overwritten: " + name)
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
	check(FileAccess.get_file_as_bytes(fault_path + ".v28-backup.json") == bytes, "Failed commit retains exact original backup: " + name)
	fault.fail_save = false
	check(fault.load_build(fault_path) and fault.snapshot() == expected and fault.successful_saves == 1 and fault_signals[0] == 1, "Retry with matching backup succeeds once: " + name)
	var external_path := "user://external-" + name
	write(external_path, bytes)
	var external := Store.new()
	external._io = ExternalIO.new()
	initial = external.snapshot()
	check(not external.load_build(external_path) and external.snapshot() == initial and FileAccess.get_file_as_string(external_path) == "external writer" and external.save_attempts == 0, "External primary rewrite is preserved: " + name)
	check(FileAccess.get_file_as_bytes(external_path + ".v28-backup.json") == bytes, "External writer retains old backup: " + name)


func with_ember(source: Dictionary, linked: bool) -> Dictionary:
	var candidate := source.duplicate(true)
	candidate.items["item_000900"] = Gems.create_instance("item_000900", NEW_ID)
	candidate.locations["item_000900"] = {"kind": "skill_support", "group_id": "group_000007", "index": 0} if linked else {"kind": "bag", "page": 1, "x": 11, "y": 9}
	candidate.next_item_serial = 901
	return candidate


func test_vocabulary(source: Dictionary) -> void:
	check(Gems.minimum_save_version(NEW_ID) == 29 and Equipment.CURRENT_VOCABULARY == 27, "Ember alone opens gem schema29; equipment vocabulary stays27")
	check(not Supports.saved_links_reason("meteor", ["ember_proliferation"], 28).is_empty() and Supports.saved_links_reason("meteor", ["ember_proliferation"], 29).is_empty(), "Linked support version gate rejects28 and accepts29")
	for linked: bool in [false, true]:
		var old := with_ember(source, linked)
		var current := old.duplicate(true)
		current.version = 29
		check(not old.items.item_000900.is_empty() and Rules.reason(current).is_empty(), "Schema29 accepts valid ember in " + ("link" if linked else "bag"))
		check(Items.metadata_for_items(current.items).size() == current.items.size(), "Warm current metadata cache before frozen-schema rejection")
		check(Rules.decode_v28(JSON.parse_string(JSON.stringify(old))).is_empty() and not Rules.reason_v28(old).is_empty() and Migration.migrate_v28(old).is_empty(), "Frozen28 rejects known new support before migration")
		check(not Rules.reason_v28(old, func(_value: Dictionary) -> String: return "").is_empty(), "Custom talent validator cannot bypass gem vocabulary")
		for existing_backup: bool in [false, true]:
			rejected_preserving("user://injected28-%s-%s.json" % [str(linked), str(existing_backup)], JSON.stringify(old).to_utf8_buffer(), 28, existing_backup)
		check(Rules.decode(JSON.parse_string(JSON.stringify(current))) == current, "Current JSON accepts integer-normalized gem payload")
		var path := "user://current29-%s.json" % str(linked)
		var bytes := JSON.stringify(current, "\t", true, true).to_utf8_buffer()
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == current and store.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(path + ".v29-backup.json"), "Current29 opens without migration or rewrite")
		var older := old.duplicate(true)
		older.version = 27
		check(Rules.decode_v27(older).is_empty() and not Rules.reason_v27(older).is_empty() and IgniteMigration.migrate_v27(older).is_empty(), "Frozen27 cannot launder ember through historical ignite step")
		older.version = 26
		check(Rules.decode_v26(older).is_empty() and not Rules.reason_v26(older).is_empty() and EquipmentMigration.migrate_v26(older).is_empty(), "Frozen26 cannot launder ember into27")
		older.version = 25
		older.erase("journey")
		check(Rules.decode_v25(older).is_empty() and not Rules.reason_v25(older).is_empty() and Prior.migrate_v25(older).is_empty(), "Frozen25 cannot launder ember through the chain")
	for malformed: Variant in [true, 0.5, "1", null]:
		var old_bad := source.duplicate(true)
		old_bad.items.migration_gem_000001.payload.level = malformed
		check(Rules.decode_v28(JSON.parse_string(JSON.stringify(old_bad))).is_empty() and not Rules.reason_v28(old_bad).is_empty() and Migration.migrate_v28(old_bad).is_empty(), "Old28 existing gem payload is still strict: " + str(malformed))
		rejected_preserving("user://old28-bad-level-" + str(malformed) + ".json", JSON.stringify(old_bad).to_utf8_buffer(), 28)
	var valid := with_ember(source, false)
	valid.version = 29
	for field: String in ["level", "quality"]:
		for malformed: Variant in [true, false, 0.5, "1", null, 2]:
			var bad := valid.duplicate(true)
			bad.items.item_000900.payload[field] = malformed
			check(Rules.decode(JSON.parse_string(JSON.stringify(bad))).is_empty() and not Rules.reason(bad).is_empty(), "Reject malformed ember payload " + field + ": " + str(malformed))
			if malformed is bool or malformed is float:
				rejected_preserving("user://bad29-%s-%s.json" % [field, str(malformed)], JSON.stringify(bad).to_utf8_buffer(), 29)
		var direct_float := valid.duplicate(true)
		direct_float.items.item_000900.payload[field] = 1.0 if field == "level" else 0.0
		check(not Rules.reason(direct_float).is_empty() and not Gems.validate_instance(direct_float.items.item_000900), "Direct gem payload must retain real integers: " + field)
	for malformed: Variant in [true, 29, null, "ember", "support:unknown_ember", "support:Ember", "余烬扩散", "support:ember_proliferation ", &"support:ember_proliferation"]:
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
	extra.items.item_000900.payload["ember_chance"] = 1
	check(Rules.decode(extra).is_empty() and not Rules.reason(extra).is_empty(), "Derived ember data cannot be persisted inside payload")


func test_frozen_rewards(manifest: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + "v28-vocabulary-oracle.json")
	check(digest(bytes) == manifest.files["v28-vocabulary-oracle.json"].sha256, "Frozen v46 reward/catalog oracle digest")
	var oracle: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	check(Journey.GEM_DEFINITIONS == oracle.gem_definitions and Journey.GEM_DEFINITIONS.size() == 26 and not Journey.GEM_DEFINITIONS.has(NEW_ID), "Exact26 schema26 normal reward definitions remain frozen")
	for index: int in range(oracle.milestones.size()):
		check(Journey.gem_definition(index + 1) == oracle.milestones[index], "Old owed milestone identity preserved at ordinal %d" % (index + 1))
	for definition_id: String in oracle.minimum_save_versions:
		check(Gems.minimum_save_version(definition_id) == int(oracle.minimum_save_versions[definition_id]), "Old gem minimum schema unchanged: " + definition_id)
	check(digest(FileAccess.get_file_as_bytes("res://scripts/world/normal_journey_state.gd")) == manifest.normal_journey_source_signature.sha256, "NormalJourneyState source remains byte-identical to v46")
	var fresh := Store.new().snapshot()
	check(fresh.version == 29 and fresh.journey == Journey.empty(), "Fresh chain ends at29 with untouched empty journey")
	for item: Dictionary in fresh.items.values():
		check(item.definition_id != NEW_ID, "Schema migration never gifts ember")
	check(Trade.quote("buy", NEW_ID).ok and Trade.quote("buy", NEW_ID).cost == {"calibration_shard": 4}, "Dynamic gem trade offers ember at unchanged support cost")
	var offer_ids: Array[String] = []
	for offer: Dictionary in Trade.offers(): offer_ids.append(offer.definition_id)
	check(offer_ids.has(NEW_ID) and offer_ids.size() == 28 and Trade.ACTIVE_COST == 8 and Trade.SUPPORT_COST == 4 and Trade.RECYCLE_CREDIT == 1, "Catalog expands to28 offers without economy changes")


func test_prior_chain() -> void:
	for version: int in [25, 26, 27]:
		var filename := "res://tests/fixtures/v041_journey/v25-default.json" if version == 25 else "res://tests/fixtures/v042_affixes/v26-active.json" if version == 26 else "res://docs/qa/v045/ignite-migration-fixtures/v27-active.json"
		var bytes := FileAccess.get_file_as_bytes(filename)
		var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		var source := Rules.decode_v25(raw) if version == 25 else Rules.decode_v26(raw) if version == 26 else Rules.decode_v27(raw)
		check(not source.is_empty(), "Literal prior fixture decodes at%d" % version)
		var v26 := Prior.migrate_v25(source) if version == 25 else source.duplicate(true)
		var v27 := EquipmentMigration.migrate_v26(v26) if version < 27 else source.duplicate(true)
		check(not v27.is_empty() and v27.version == 27 and Rules.reason_v27(v27).is_empty(), "Historical equipment step remains pinned to27")
		var v28 := IgniteMigration.migrate_v27(v27)
		check(not v28.is_empty() and v28.version == 28 and Rules.reason_v28(v28).is_empty() and not Rules.reason(v28).is_empty(), "Historical ignite step remains pinned to28, not current29")
		var expected := v27.duplicate(true)
		expected.version = 29
		check(Migration.migrate_v28(v28) == expected, "Prior chain adds no gifts, refunds or field changes")
		var path := "user://chain%d.json" % version
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and store.save_attempts == 1, "Prior%d reaches29 in one write" % version)
		check(FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % version) == bytes and not FileAccess.file_exists(path + ".v28-backup.json"), "Chain backs up only real original%d bytes" % version)
	# Earlier literal envelopes exercise every dispatched canonical branch and
	# each existing one-time migration, with only one final current-schema write.
	var old_paths := [
		"res://tests/fixtures/v022_currency/v14-original-bytes.json",
		"res://tests/fixtures/v022_currency/v15-wallet-27.json",
		"res://tests/fixtures/performance/crowded-inventory-v16.json",
		"res://tests/fixtures/v026_flasks/released-v17-two-offense.json",
		"res://tests/fixtures/v028_town/v18-c-bound.json",
		"res://tests/fixtures/v032_spatial/v19-default.json",
		"res://tests/fixtures/v033_recharge/v20-default.json",
		"res://tests/fixtures/v034_cost/v21-default.json",
		"res://tests/fixtures/v035_flasks/v22-default.json",
		"res://tests/fixtures/v039_critical/v23-default.json",
		"res://tests/fixtures/v040_leech/v24-default.json",
	]
	for filename: String in old_paths:
		var bytes := FileAccess.get_file_as_bytes(filename)
		var raw: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
		var version := int(raw.version)
		var path := "user://historical%d.json" % version
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot().version == 29 and Rules.reason(store.snapshot()).is_empty() and store.successful_saves == 1, "Historical literal%d still reaches29" % version)
		check(FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % version) == bytes, "Historical%d backup retains literal bytes" % version)
		for item: Dictionary in store.snapshot().items.values():
			check(item.definition_id not in [NEW_ID, "support:ignite"], "Historical%d grants no newer support" % version)
	var legacy := Store.Legacy.new()
	var raw := legacy._snapshot()
	var legacy_bytes := JSON.stringify(raw, "  ", true, true).to_utf8_buffer()
	var legacy_path := "user://legacy-default.json"
	write(legacy_path, legacy_bytes)
	var legacy_store := Store.new()
	check(legacy_store.load_build(legacy_path) and legacy_store.snapshot().version == 29 and Rules.reason(legacy_store.snapshot()).is_empty(), "Original legacy default still traverses full migration chain")
	check(FileAccess.get_file_as_bytes(legacy_path + ".v%d-backup.json" % int(raw.version)) == legacy_bytes, "Legacy default raw backup is exact")


func test_real_atomic_failure(source: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + "v28-default.json")
	var path := "user://atomic-temporary-collision.json"
	write(path, bytes)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create isolated primary-temp directory collision")
	var store := Store.new()
	var initial := store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes and signals[0] == 0 and store.successful_saves == 0 and store.save_attempts == 1, "Real atomic temp-open failure preserves primary and memory")
	check(FileAccess.get_file_as_bytes(path + ".v28-backup.json") == bytes, "Real commit failure still preserves original raw backup")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove only isolated temporary collision")
	var expected := source.duplicate(true)
	expected.version = 29
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and signals[0] == 1, "Retry real atomic failure with same backup succeeds once")
	var disk := FileAccess.get_file_as_bytes(path)
	write(path, "external writer after migration".to_utf8_buffer())
	check(store.save_build(path) == ERR_FILE_ALREADY_IN_USE and store.snapshot() == expected and store._disk_bytes == disk and FileAccess.get_file_as_string(path) == "external writer after migration", "Migrated receipt still protects external changes")
	var retained_path := "user://retained-receipt29.json"
	var retained_bytes := JSON.stringify(expected, "\t", true, true).to_utf8_buffer()
	write(retained_path, retained_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(retained_path), "Load current29 before testing failure receipt retention")
	var retained_snapshot := retained.snapshot()
	var failed_path := "user://failed-with-existing-receipt28.json"
	var failed_bytes := FileAccess.get_file_as_bytes(FIXTURES + "v28-active.json")
	write(failed_path, failed_bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == retained_snapshot and retained._path == retained_path and retained._disk_bytes == retained_bytes and retained._disk_revision == retained_snapshot.revision and retained._disk_expected_exists, "Failed migration retains the previously accepted current receipt")
	check(FileAccess.get_file_as_bytes(failed_path) == failed_bytes and FileAccess.get_file_as_bytes(retained_path) == retained_bytes, "Failed replacement changes neither original nor previously loaded file")
	var message_path := "user://migration-message.json"
	write(message_path, bytes)
	var game := Game.new()
	check(game.load_build(message_path) and game.migrated_from_legacy and game.migration_message.contains("余烬扩散") and not game.migration_message.contains("两瓶药剂"), "Old28 gets accurate non-grant migration message")


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "manifest.json"))
	check(Rules.VERSION == 29 and Rules.V28_VERSION == 28 and Rules.SourceTree.CURRENT_SAVE_VERSION == 25 and Rules.SourceTree._execution_policy(29) == 25, "Schema29 does not expand source passive vocabulary")
	for name: String in ["v28-default.json", "v28-ignite-bag.json", "v28-active.json", "v28-pending.json"]:
		test_literal(name, manifest)
	var source := Rules.decode_v28(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v28-default.json")))
	test_vocabulary(source)
	for mutation: String in ["future", "duplicate_binding", "fractional_revision", "bool_revision", "extra_field", "missing_journey", "invalid_journey"]:
		var bad := source.duplicate(true)
		match mutation:
			"future": bad.version = 30
			"duplicate_binding": bad.bindings.append(bad.bindings[0].duplicate())
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"extra_field": bad.live_ember_instances = []
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.normal_root_kills = 0.5
		rejected_preserving("user://invalid28-" + mutation + ".json", JSON.stringify(bad).to_utf8_buffer(), int(bad.version))
	test_frozen_rewards(manifest)
	test_prior_chain()
	test_real_atomic_failure(source)
	print("Ember gem migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
