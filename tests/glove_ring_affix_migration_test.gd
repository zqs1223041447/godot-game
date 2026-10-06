extends SceneTree
## Strict45→46 from released v070 actual-Main bytes and original v071 build routes.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/glove_ring_affix_migration.gd")
const Prior = preload("res://scripts/save/precise_technique_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const FIXTURES := "res://docs/qa/v070-gameplay/fixtures/"
var checks := 0
var failures := 0
var evidence := {}

class FaultStore extends Store:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)

class BackupFailIO extends Store.Legacy:
	func _backup_legacy_save(_path: String) -> Error: return ERR_CANT_CREATE

class ExternalIO extends Store.Legacy:
	func _backup_legacy_save(path: String) -> Error:
		var result := super._backup_legacy_save(path)
		if result == OK:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string("external writer")
			file.close()
		return result

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok

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
	result.version = 46
	return result

func consumers(source: Dictionary) -> Dictionary:
	var game := Game.new()
	game._accept_memory(source)
	var casts := {}
	for group: Dictionary in source.skill_groups:
		casts[group.id] = game.get_group_cast(group.id)
	return {"stats":game.get_stats(), "snapshot":game.get_combat_snapshot(), "basic":game.get_basic_cast(),
		"casts":casts, "equipped":game.equipped_items(), "pending":game.pending_items(),
		"wallet":Store.Currency.total_quantity(source.items)}

func migrate_case(source: Dictionary, bytes: PackedByteArray, label: String) -> void:
	if not check(not source.is_empty() and Rules.reason_v45(source).is_empty(), "Frozen45 legal before migration: " + label): return
	var before := var_to_bytes(source)
	var expected := current(source)
	var old_consumers := consumers(source)
	seed(724546)
	var next_rng := randi()
	seed(724546)
	var result := Migration.migrate_v45(source)
	check(randi() == next_rng and result == expected and var_to_bytes(source) == before, "Only version changes; RNG and source unchanged: " + label)
	for field: String in Rules.FIELDS:
		if field != "version": check(result[field] == source[field], "Nonversion field retained: " + label + "/" + field)
	check(consumers(result) == old_consumers, "Every current model consumer retains stats, casts, flags, gear, wallet and recovery: " + label)
	var path := "user://" + label + ".json"
	write(path, bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	if not check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "One atomic migration and event: " + label): return
	check(FileAccess.get_file_as_bytes(path + ".v45-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Exact original45 bytes backed up: " + label)
	check(game.migrated_from_legacy and game.migration_message.contains("手套") and game.migration_message.contains("戒指") and game.migration_message.contains("不额外赠物或赠点"), "Latest migration message describes affixes and no gifts")
	check(consumers(game.snapshot()) == old_consumers, "Reloaded model retains every consumer output: " + label)
	var disk := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated46 load does not rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v45-backup.json") == bytes, "Independent46 reopen retains source backup")
	evidence[label] = {"source_sha256":digest(bytes), "bytes":bytes.size(), "items":source.items.size(), "pending":old_consumers.pending, "wallet":old_consumers.wallet}

func reject_bytes(label: String, value: Dictionary) -> void:
	var path := "user://reject-" + label + ".json"
	var bytes := JSON.stringify(value).to_utf8_buffer()
	write(path, bytes)
	var store := Store.new()
	var before := store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Illegal input preserves disk and live state: " + label)
	check(store.save_attempts == 0 and store.successful_saves == 0 and events[0] == 0 and not FileAccess.file_exists(path + ".v45-backup.json"), "Illegal input never reaches backup, write or notification")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected target remains protected")

func with_affix(source: Dictionary, family: String) -> Dictionary:
	var candidate := source.duplicate(true)
	var tier: Dictionary = Equipment.affix_definition(family).tiers[0]
	var gear := {"id":"gear_%06d" % int(candidate.next_item_serial),
		"base_id":"nine_slot_threaded_gloves" if family == "glove_accuracy" else "nine_slot_etched_ring",
		"rarity":"magic", "item_level":1, "affixes":[{"id":family,"tier":1,"value":int(tier.min)}]}
	var index := 0
	for location: Dictionary in candidate.locations.values():
		if location.kind == "recovery": index += 1
	candidate.items[gear.id] = Store.Items.wrap_equipment(gear)
	candidate.locations[gear.id] = {"kind":"recovery", "index":index}
	candidate.next_item_serial += 1
	return candidate

func strict_checks(source: Dictionary) -> void:
	var calls := [0]
	var permissive := func(_value: Dictionary) -> String: calls[0] += 1; return ""
	for family: String in ["glove_accuracy", "ring_emberward", "ring_rimeward", "ring_stormward"]:
		var injected := with_affix(source, family)
		if not check(Rules.reason(current(injected)).is_empty(), "New family legal only in current46: " + family): continue
		Store.Items.metadata_for_items(injected.items)
		calls[0] = 0
		check(not Rules.reason_v45(injected, permissive).is_empty() and Rules.decode_v45(injected).is_empty() and Migration.migrate_v45(injected, permissive).is_empty() and calls[0] == 0, "Frozen45 rejects new affix before callbacks even with warm current metadata: " + family)
		reject_bytes(family, injected)
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "unknown_node", "over_budget", "wrong_source", "missing_location", "bad_binding", "bad_ledger"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.extra = true
			"missing_journey": bad.erase("journey")
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"over_budget": bad.talents.normal_points += 1
			"wrong_source": bad.talents.source_version = "3.29.2"
			"missing_location": bad.locations.erase(bad.locations.keys()[0])
			"bad_binding": bad.bindings[0].keycode = KEY_C
			"bad_ledger": bad.migration_ledger.normal_budget_at_migration += 1
		calls[0] = 0
		check(not Rules.reason_v45(bad, permissive).is_empty() and Rules.decode_v45(bad).is_empty() and Migration.migrate_v45(bad, permissive).is_empty() and calls[0] == 0, "Complete frozen45 native legality precedes callbacks: " + mutation)
		reject_bytes(mutation, bad)
	check(Migration.migrate_v45(current(source)).is_empty() and Rules.decode(source).is_empty() and Rules.decode_v45(current(source)).is_empty(), "Strict decoders and migration accept exactly their version")
	var reject := func(_value: Dictionary) -> String: return "extra restriction"
	check(Migration.migrate_v45(source, reject).is_empty(), "Optional callback can add restrictions")

func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path, bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "collision": write(path + ".v45-backup.json", "retained backup".to_utf8_buffer())
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic": check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject real atomic-write failure")
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration never publishes state: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Original or external-writer bytes retained: " + failure)
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup and concurrency checks precede commit")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v45-backup.json") == "retained backup", "Conflicting backup untouched")
		if failure in ["external", "atomic"]: check(FileAccess.get_file_as_bytes(path + ".v45-backup.json") == bytes, "Failed commit retains exact source backup")
		if failure == "atomic":
			check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.snapshot() == current(source) and store.successful_saves == 1 and events[0] == 1, "Fault removal permits one successful retry with identical backup")
		else: check(store.save_build(path) != OK, "Failed target cannot be accidentally overwritten")
	var accepted := current(source)
	var accepted_bytes := JSON.stringify(accepted).to_utf8_buffer()
	var accepted_path := "user://accepted46.json"
	write(accepted_path, accepted_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(accepted_path), "Establish current46 state and receipt")
	var failed_path := "user://failed45-replacement.json"
	write(failed_path, bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == accepted and retained._path == accepted_path and retained._disk_bytes == accepted_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Failed migration retains prior live state and receipt")

func prior_and_pending_checks() -> void:
	for label: String in ["ir", "zo", "conversion"]:
		var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v070-migration/fixtures/v44-" + label + "-native-v069.json")
		var old44 := Rules.decode_v44(JSON.parse_string(bytes.get_string_from_utf8()))
		if not check(not old44.is_empty(), "Released native44 fixture remains valid: " + label): continue
		var frozen45 := Prior.migrate_v44(old44)
		var expected45 := old44.duplicate(true)
		expected45.version = 45
		check(frozen45 == expected45 and Rules.reason_v45(frozen45).is_empty(), "Prior migration remains frozen44→45")
		var path := "user://chain44-" + label + ".json"
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == current(old44) and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v44-backup.json") == bytes and not FileAccess.file_exists(path + ".v45-backup.json"), "Older chain commits once with original44 backup")
		check(consumers(frozen45) == consumers(store.snapshot()), "IR, ZO, conversion and original recovery consumers unchanged: " + label)
		if label == "ir":
			var profile: Dictionary = Journey.Maps.compile_normal("sunwell_terrace", 1, [], []).profile
			var started: Dictionary = Journey.start(frozen45.journey, profile)
			check(started.ok, "Legal journey plan starts")
			frozen45.journey = started.journey
			migrate_case(frozen45, JSON.stringify(frozen45).to_utf8_buffer(), "active-run-recovery")
			var completed: Dictionary = Journey.complete(frozen45.journey, int(started.run_id))
			check(completed.ok, "Legal journey completion retains pending reward")
			frozen45.journey = completed.journey
			migrate_case(frozen45, JSON.stringify(frozen45).to_utf8_buffer(), "pending-reward-recovery")
	var legacy := Store.Legacy.new()._snapshot()
	var bytes := JSON.stringify(legacy).to_utf8_buffer()
	var path := "user://complete-legacy-chain.json"
	write(path, bytes)
	var full := Store.new()
	check(full.load_build(path) and full.snapshot().version == 46 and Rules.reason(full.snapshot()).is_empty() and full.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % int(legacy.version)) == bytes, "Full legacy load chain reaches46 with one original backup")
	var fresh := Store.new().snapshot()
	check(fresh.version == 46 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0, "Fresh default chain reaches46 without currency gift")

func sample_checks(source: Dictionary) -> void:
	var routes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v071-build-comparison/routes.json"))
	for label: String in routes:
		var candidate := source.duplicate(true)
		candidate.progress = {"level":19, "xp":0}
		candidate.talents.allocated = routes[label]
		candidate.talents.normal_points = 23 - (routes[label].size() - 1)
		migrate_case(candidate, JSON.stringify(candidate).to_utf8_buffer(), "v071-" + label)

func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v072-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	check(Rules.VERSION == 46 and Rules.V45_VERSION == 45 and Equipment.CURRENT_VOCABULARY == 46 and Source.CURRENT_SAVE_VERSION == 45 and Source._execution_policy(46) == 45, "Equipment46 retains exact source policy45")
	for version: int in range(1, 47):
		check(Rules.equipment_vocabulary_for_save_version(version) == (46 if version >= 46 else 39 if version >= 39 else 37 if version >= 37 else 34 if version >= 34 else version), "Historical equipment mapping remains explicit: " + str(version))
	var source := {}
	var bytes := PackedByteArray()
	for label: String in ["selected-above", "selected-below", "refunded"]:
		bytes = FileAccess.get_file_as_bytes(FIXTURES + label + ".json")
		source = Rules.decode_v45(JSON.parse_string(bytes.get_string_from_utf8()))
		migrate_case(source, bytes, "native45-" + label)
		if label == "selected-above" and not source.is_empty(): sample_checks(source)
	if not source.is_empty():
		strict_checks(source)
		failure_checks(source, bytes)
	prior_and_pending_checks()
	evidence.checks = checks
	evidence.failures = failures
	var report := OS.get_environment("V072_MIGRATION_REPORT")
	if not report.is_empty(): write(report, (JSON.stringify(evidence, "\t", true, true) + "\n").to_utf8_buffer())
	print("Glove/ring migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
