extends SceneTree
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/equipment_affix_migration.gd")
const Prior = preload("res://scripts/save/normal_journey_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const FIXTURES := "res://tests/fixtures/v042_affixes/"
const NEW_AFFIXES := ["attack_life_leech", "attack_mana_leech", "global_critical_chance", "global_critical_multiplier"]


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


func with_affix(source: Dictionary, affix_id: String, base_id: String = "wayglass_token") -> Dictionary:
	var candidate := source.duplicate(true)
	var family: Dictionary = Equipment.affix_definition(affix_id)
	var payload := {"id": "gear_000900", "base_id": base_id, "rarity": "magic", "item_level": 30,
		"affixes": [{"id": affix_id, "tier": 1, "value": int(family.tiers[0].min)}]}
	candidate.items[payload.id] = Items.wrap_equipment(payload)
	candidate.locations[payload.id] = {"kind": "recovery", "index": 0}
	candidate.next_item_serial = 901
	return candidate


func test_literal(name: String, manifest: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + name)
	check(bytes.size() == int(manifest.files[name].bytes) and digest(bytes) == manifest.files[name].sha256 and bytes.get_string_from_utf8().begins_with(" \r\n"), "Literal frozen v41 fixture digest/CRLF: " + name)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var source := Rules.decode_v26(raw)
	check(not source.is_empty() and Rules.reason_v26(source).is_empty() and Rules.decode(raw).is_empty(), "Strict frozen26 envelope: " + name)
	if source.is_empty(): return
	var before := var_to_bytes(source)
	var expected := source.duplicate(true)
	expected.version = 27
	check(Migration.migrate_v26(source) == expected and var_to_bytes(source) == before, "Pure migration changes only version: " + name)
	check(Migration.migrate_v26(expected).is_empty(), "Current snapshot cannot migrate twice: " + name)
	if name != "v26-default.json":
		check(source.items.has("gear_000004") and source.items.has("item_000005") and source.items.item_000005.payload.quantity == 6 and source.crafting.revision == 1 and source.next_item_serial == 9, "Released UID/currency/craft metadata is nontrivial: " + name)
		check(source.progress == {"level": 4, "xp": 6} and source.talents.normal_points == 8 and source.journey.normal_root_kills == 90 and source.journey.claimed_gems == 2 and source.journey.claimed_flasks == 1, "Released XP/budget/claim ordinals are preserved: " + name)
		check(source.bindings.has({"group_id": "group_000001", "keycode": KEY_F1}), "Real released binding change is preserved: " + name)
	if name == "v26-active.json":
		check(source.revision == 115 and source.journey.active_run.run_id == 8 and source.journey.active_run.fee_paid == 4 and source.journey.active_run.tier == 2 and source.journey.pending_map_reward.is_empty(), "Paid active tier2 remains active")
	if name == "v26-pending.json":
		check(source.revision == 116 and source.journey.active_run.is_empty() and source.journey.pending_map_reward == {"run_id": 8, "map_id": "old_garden", "tier": 2, "shards": 12}, "Pending tier2 reward remains owed")
	var path := "user://affix-" + name
	write(path, bytes)
	var store := Store.new()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(store.load_build(path) and store.snapshot() == expected, "Store changes only26 to27: " + name)
	check(store.save_attempts == 1 and store.successful_saves == 1 and signals[0] == 1, "Migration writes/notifies once: " + name)
	check(FileAccess.get_file_as_bytes(path + ".v26-backup.json") == bytes, "Backup equals original literal bytes: " + name)
	var disk := FileAccess.get_file_as_bytes(path)
	check(Rules.decode(JSON.parse_string(disk.get_string_from_utf8())) == expected, "Persisted candidate matches every field: " + name)
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Current reread does not rewrite: " + name)
	var fresh := Store.new()
	check(fresh.load_build(path) and fresh.snapshot() == expected and fresh.successful_saves == 0 and FileAccess.get_file_as_bytes(path + ".v26-backup.json") == bytes, "Independent reopen migrates zero times: " + name)
	var conflict_path := "user://collision-" + name
	write(conflict_path, bytes)
	var other := PackedByteArray([1, 2, 3])
	write(conflict_path + ".v26-backup.json", other)
	var conflict := Store.new()
	var initial := conflict.snapshot()
	check(not conflict.load_build(conflict_path) and conflict.snapshot() == initial and FileAccess.get_file_as_bytes(conflict_path) == bytes and FileAccess.get_file_as_bytes(conflict_path + ".v26-backup.json") == other and conflict.save_attempts == 0, "Existing different backup is never overwritten: " + name)
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
	check(FileAccess.get_file_as_bytes(fault_path + ".v26-backup.json") == bytes, "Failed commit retains exact original backup: " + name)
	fault.fail_save = false
	check(fault.load_build(fault_path) and fault.snapshot() == expected and fault.successful_saves == 1 and fault_signals[0] == 1, "Retry with matching backup succeeds once: " + name)
	var external_path := "user://external-" + name
	write(external_path, bytes)
	var external := Store.new()
	external._io = ExternalIO.new()
	initial = external.snapshot()
	check(not external.load_build(external_path) and external.snapshot() == initial and FileAccess.get_file_as_string(external_path) == "external writer" and external.save_attempts == 0, "External primary rewrite is preserved: " + name)
	check(FileAccess.get_file_as_bytes(external_path + ".v26-backup.json") == bytes, "External writer retains old backup: " + name)


func test_vocabulary(source: Dictionary, pure_only: bool = false) -> void:
	var current := source.duplicate(true)
	current.version = 27
	for affix_id: String in NEW_AFFIXES:
		for base_id: String in Equipment.BuildAffixes.ALLOWED_BASE_IDS:
			var valid := with_affix(current, affix_id, base_id)
			check(not valid.items.gear_000900.is_empty() and Rules.reason(valid).is_empty(), "Schema27 admits " + affix_id + " on " + base_id)
			if valid.items.gear_000900.is_empty(): continue
			check(Items.metadata_for_items(valid.items).size() == valid.items.size(), "Warm current positive cache for " + affix_id + " on " + base_id)
			var old := valid.duplicate(true)
			old.version = 26
			check(Rules.decode_v26(JSON.parse_string(JSON.stringify(old))).is_empty() and not Rules.reason_v26(old).is_empty() and Migration.migrate_v26(old).is_empty(), "Frozen26 refuses current cached affix " + affix_id + " on " + base_id)
			check(not Rules.reason_v26(old, func(_value: Dictionary) -> String: return "").is_empty(), "Custom talent validator cannot bypass old equipment gate")
			old.version = 25
			old.erase("journey")
			check(Rules.decode_v25(old).is_empty() and not Rules.reason_v25(old).is_empty() and Prior.migrate_v25(old).is_empty(), "Frozen25 also refuses newly injected affix")
		var valid := with_affix(current, affix_id)
		var old := valid.duplicate(true)
		old.version = 26
		var old_bytes := JSON.stringify(old).to_utf8_buffer()
		if not pure_only:
			rejected_preserving("user://injected26-" + affix_id + ".json", old_bytes, 26)
			rejected_preserving("user://injected26-existing-backup-" + affix_id + ".json", old_bytes, 26, true)
		var decoded := Rules.decode(JSON.parse_string(JSON.stringify(valid)))
		check(decoded == valid and decoded.items.gear_000900.payload.affixes[0].value is int and decoded.items.gear_000900.payload.affixes[0].tier is int and decoded.items.gear_000900.payload.size() == 5, "Current affix JSON stays five-field payload with integer ticks: " + affix_id)
		if not pure_only:
			var current_path := "user://current27-" + affix_id + ".json"
			var current_bytes := JSON.stringify(valid, "\t", true, true).to_utf8_buffer()
			write(current_path, current_bytes)
			var store := Store.new()
			check(store.load_build(current_path) and store.snapshot() == valid and store.successful_saves == 0 and FileAccess.get_file_as_bytes(current_path) == current_bytes and not FileAccess.file_exists(current_path + ".v27-backup.json"), "Current new affix reads without migration: " + affix_id)
		for field: String in ["value", "tier"]:
			for malformed: Variant in [true, false, 0.5, "1", null]:
				var bad := valid.duplicate(true)
				bad.items.gear_000900.payload.affixes[0][field] = malformed
				check(Rules.decode(JSON.parse_string(JSON.stringify(bad))).is_empty() and not Rules.reason(bad).is_empty(), "Reject malformed affix " + field + ": " + str(malformed))
				if not pure_only and field == "value" and (malformed is bool or malformed is float):
					rejected_preserving("user://bad27-%s-%s.json" % [affix_id, str(malformed)], JSON.stringify(bad).to_utf8_buffer(), 27)
		var extra := valid.duplicate(true)
		extra.items.gear_000900.payload.stats = {"attack_life_leech": 99}
		check(Rules.decode(extra).is_empty() and not Rules.reason(extra).is_empty(), "Derived stat payload cannot be persisted")


func test_prior_chain() -> void:
	for name: String in ["v25-default.json", "v25-leech.json"]:
		var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/v041_journey/" + name)
		var source := Rules.decode_v25(JSON.parse_string(bytes.get_string_from_utf8()))
		var v26 := source.duplicate(true)
		v26.version = 26
		v26["journey"] = Journey.empty()
		check(Prior.migrate_v25(source) == v26 and Rules.reason_v26(v26).is_empty() and Rules.decode(v26).is_empty(), "Prior migration remains pinned to26: " + name)
		var expected := v26.duplicate(true)
		expected.version = 27
		var path := "user://chain-" + name
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1, "25-through27 chain writes once: " + name)
		check(FileAccess.get_file_as_bytes(path + ".v25-backup.json") == bytes and not FileAccess.file_exists(path + ".v26-backup.json"), "Chained migration backs up only actual original25: " + name)
	var legacy := Store.Legacy.new()._snapshot()
	var bytes := PackedByteArray([239, 187, 191]) + JSON.stringify(legacy, "  ").to_utf8_buffer()
	var path := "user://legacy13.json"
	write(path, bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot().version == 27 and store.snapshot().journey == Journey.empty() and store.successful_saves == 1, "Complete13-through27 chain commits once")
	check(FileAccess.get_file_as_bytes(path + ".v13-backup.json") == bytes, "Full chain retains original13 BOM bytes")


func test_old_rolls() -> void:
	var source := Rules.decode_v26(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v26-active.json")))
	for field: String in ["value", "tier"]:
		for malformed: Variant in [true, false, 0.5, "1", null]:
			var bad := source.duplicate(true)
			bad.items.gear_000004.payload.affixes[0][field] = malformed
			check(Rules.decode_v26(JSON.parse_string(JSON.stringify(bad))).is_empty() and not Rules.reason_v26(bad).is_empty() and Migration.migrate_v26(bad).is_empty(), "Frozen26 also rejects malformed existing affix " + field + ": " + str(malformed))
			if field == "value" and (malformed is bool or malformed is float):
				rejected_preserving("user://bad26-roll-" + str(malformed) + ".json", JSON.stringify(bad).to_utf8_buffer(), 26, true)


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	if OS.get_cmdline_user_args().has("--vocabulary-only"):
		var source := Rules.decode_v26(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v26-default.json")))
		test_vocabulary(source, true)
		print("Equipment affix vocabulary/cache: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "manifest.json"))
	check(Store.new().snapshot().version == 27 and Rules.VERSION == 27 and Store.new().snapshot().journey == Journey.empty(), "Fresh store ends the default migration chain at27")
	check(Rules.SourceTree.CURRENT_SAVE_VERSION == 25 and Rules.SourceTree._execution_policy(27) == 25, "Schema27 leaves source talent vocabulary at25")
	for name: String in ["v26-default.json", "v26-active.json", "v26-pending.json"]:
		test_literal(name, manifest)
	var source := Rules.decode_v26(JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v26-default.json")))
	test_vocabulary(source)
	test_old_rolls()
	for mutation: String in ["future", "duplicate_binding", "fractional_revision", "bool_revision", "extra_field", "missing_journey", "invalid_journey"]:
		var bad := source.duplicate(true)
		match mutation:
			"future": bad.version = 28
			"duplicate_binding": bad.bindings.append(bad.bindings[0].duplicate())
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"extra_field": bad.live_leech_instances = []
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.normal_root_kills = 0.5
		rejected_preserving("user://invalid26-" + mutation + ".json", JSON.stringify(bad).to_utf8_buffer(), int(bad.version))
	test_prior_chain()
	print("Equipment affix migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
