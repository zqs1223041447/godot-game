extends SceneTree
## Schema35 source admission and frozen34 migration, with real persistence faults.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/mana_guard_migration.gd")
const Prior = preload("res://scripts/save/forgeblade_migration.gd")
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const FIXTURE := "res://docs/qa/v056/fixtures/v34-default.json"
const SOURCE_LINE := "40% of Damage is taken from Mana before Life"
const STAT := "damage_taken_from_mana_before_life"
var checks := 0
var failures := 0
var route_report: Array = []


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


func expected_current(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.version = 35
	return result


func reachable(class_id: int, version: int) -> Dictionary:
	var start := SourceTree.Data.start_for_class(class_id)
	var paths := {start:[start]}
	var queue: Array[String] = [start]
	var offset := 0
	while offset < queue.size():
		var current: String = queue[offset]
		offset += 1
		for id: String in SourceTree.Data.adjacency(current):
			var node := SourceTree.Data.node(id)
			if paths.has(id) or node.type in ["mastery", "start"] or node.source.get("isProxy", false) or node.source.get("isBlighted", false): continue
			if SourceTree.node_effect(id, 0, version).status != "full": continue
			paths[id] = paths[current] + [id]
			queue.append(id)
	return paths


func allocated(source: Dictionary, class_id: int, path: Array) -> Dictionary:
	var candidate := expected_current(source)
	candidate.progress.level = 25
	candidate.progress.xp = 0
	candidate.talents.class_id = class_id
	candidate.talents.allocated = path.duplicate()
	candidate.talents.masteries = {}
	candidate.talents.normal_points = 30 - path.size()
	return candidate


func rejected_preserving(path: String, bytes: PackedByteArray, version: int) -> void:
	write(path, bytes)
	var store := Store.new()
	var before := store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Rejected envelope preserves bytes and memory: " + path)
	check(store.save_attempts == 0 and store.successful_saves == 0 and signals[0] == 0, "Rejected envelope performs no save or signal")
	check(not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Invalid source receives no migration backup")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected source remains protected from later save")


func test_parser_and_gates() -> void:
	check(Rules.VERSION == 35 and Rules.V34_VERSION == 34 and SourceTree.CURRENT_SAVE_VERSION == 35 and SourceTree.MANA_GUARD_SAVE_VERSION == 35, "Current schema and source vocabulary open only at35")
	check(SourceTree._execution_policy(32) == 32 and SourceTree._execution_policy(33) == 33 and SourceTree._execution_policy(34) == 33, "Old source policies remain frozen")
	check(Equipment.CURRENT_VOCABULARY == 34 and Equipment.CURRENT_LOOT_PROFILE_ID == "canonical_v34", "Schema35 changes no equipment or reward vocabulary")
	for amount: String in ["0", "8", "10", "40", "12.5"]:
		var line := amount + "% of Damage is taken from Mana before Life"
		var result := Patterns.parse_line(line)
		check(result.supported and result.grants.size() == 1 and result.grants[0].stat == STAT and result.grants[0].mode == "flat" and is_equal_approx(result.grants[0].value, float(amount) * 0.01), "Exact mana-before-life line becomes one fractional flat grant: " + amount)
		for version: int in range(14, 35):
			check(not SourceTree.line_effect(line, version).supported, "Frozen source%d rejects future mana-before-life effect" % version)
		for version: int in [35, 34, 35, 33, 35]:
			check(SourceTree.line_effect(line, version).supported == (version == 35), "Interleaved line cache cannot cross schema gate")
	for value: Variant in [null, {}, [], true, NAN, INF, 40, "-40% of Damage is taken from Mana before Life", "+40% of Damage is taken from Mana before Life", "40% of Damage is taken from Mana before Life while on Full Life", "40% of Fire Damage is taken from Mana before Life", "40% of Damage is taken from Mana before Life.", " 40% of Damage is taken from Mana before Life", "40% of Damage is taken from Mana before Life\n", "40% of Damage is taken from Energy Shield before Life", "40% reduced Mana Cost of Skills", "Transfiguration of Mind", "Damage taken Recouped as Mana", "NaN% of Damage is taken from Mana before Life", "9".repeat(400) + "% of Damage is taken from Mana before Life"]:
		var parsed := Patterns.parse_line(value)
		check(not parsed.supported and parsed.grants.is_empty(), "Scoped, unknown, nonfinite and malformed mana guard lines rejected: " + str(value).left(85))
	var newly_full: Array[String] = []
	for id: String in SourceTree.Data.standard_ids():
		var node := SourceTree.Data.node(id)
		var old := SourceTree.node_effect(id, 0, 34)
		var current := SourceTree.node_effect(id, 0, 35)
		check(old == SourceTree.node_effect(id, 0, 33), "Every schema34 standard node retains exact schema33 execution: " + id)
		if old.status == "full": check(old == current, "Previously legal standard node has identical grants: " + id)
		elif current.status == "full": newly_full.append(id)
		for option: Dictionary in node.mastery_effects:
			var effect := int(option.effect)
			check(SourceTree.node_effect(id, effect, 34) == SourceTree.node_effect(id, effect, 33), "Every schema34 mastery retains exact schema33 execution")
			check(SourceTree.node_effect(id, effect, 35) == SourceTree.node_effect(id, effect, 34), "No mastery newly opens or changes grant")
	check(newly_full == ["34098"] and SourceTree.Data.node("34098").stats == [SOURCE_LINE], "Exactly pinned standard node34098 opens with unchanged English source")
	for id: String in ["42144", "922"]:
		var effect := SourceTree.node_effect(id)
		check(not SourceTree.Data.standard_ids().has(id) and effect.status == "partial" and not effect.unsupported.is_empty(), "Mixed nonstandard node remains locked: " + id)
		check(effect.grants.any(func(grant: Dictionary) -> bool: return grant.stat == STAT), "Exact external-subtree mana line is parser-supported only: " + id)
	check(Localization.line_status(SOURCE_LINE).implemented and not Localization.display_line(SOURCE_LINE).ends_with(Localization.NOT_IMPLEMENTED), "Consumer-backed Chinese line updates dynamically without changing translation")
	check(Localization.display_line("Transfiguration of Mind").ends_with(Localization.NOT_IMPLEMENTED), "Other mixed-node mechanisms retain unsupported labels")
	for code_check: Dictionary in Localization.STAT_CONSUMER_GROUPS.mana_before_life.code_checks:
		check(FileAccess.get_file_as_string("res://" + code_check.path).contains(code_check.contains), "Consumer manifest points to real code: " + code_check.path)


func test_paths(source: Dictionary) -> Dictionary:
	var shortest := 123
	var longest := 0
	var example := {}
	for class_id: int in range(7):
		var old := reachable(class_id, 34)
		var current := reachable(class_id, 35)
		check(current.has("34098") and not old.has("34098"), "Complete standard route reaches34098 only in35 from class%d" % class_id)
		if not current.has("34098"): continue
		var path: Array = current["34098"]
		var spent := path.size() - 1
		shortest = mini(shortest, spent)
		longest = maxi(longest, spent)
		check(spent >= 7 and spent <= 25, "Real shortest route has7–25 point cost")
		var candidate := allocated(source, class_id, path)
		check(SourceTree.analyze(candidate).legal and Rules.reason(candidate).is_empty(), "Full actual route, point budget and native envelope validate for class%d" % class_id)
		check(is_equal_approx(Game._stats_for(candidate).get(STAT, -1.0), 0.4), "Whole route grants exactly40% after canonical stats aggregation")
		for version: int in [34, 35, 33, 35]:
			var gated := candidate.duplicate(true)
			gated.version = version
			check(SourceTree.analyze(gated).legal == (version == 35), "Warm allocation analysis cannot admit34098 into prior schema")
		var denied := candidate.duplicate(true)
		denied.version = 34
		var allow_all := func(_candidate: Dictionary) -> String: return ""
		check(not Rules.reason_v34(denied, allow_all).is_empty() and Rules.decode_v34(denied).is_empty() and Migration.migrate_v34(denied, allow_all).is_empty(), "Caller callback cannot admit injected34098 in frozen34")
		rejected_preserving("user://injected34-class%d.json" % class_id, JSON.stringify(denied).to_utf8_buffer(), 34)
		for id: String in ["42144", "922"]:
			var partial := candidate.duplicate(true)
			partial.talents.allocated.append(id)
			partial.talents.normal_points -= 1
			check(not Rules.reason(partial, allow_all).is_empty(), "Current callback cannot allow mixed nonstandard node injection")
		route_report.append({"class_id":class_id, "class_name":SourceTree.Data.class_definition(class_id).name, "spent":spent, "path":path, "old_reachable":old.size() - 1, "current_reachable":current.size() - 1})
		if class_id == 0: example = candidate
	check(shortest == 7 and longest == 25, "Seven class route point costs span exactly7–25")
	return example


func test_raw_migration(source: Dictionary, bytes: PackedByteArray) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v056/fixtures/manifest.json"))
	check(bytes.size() == int(manifest.bytes) and digest(bytes) == manifest.sha256, "Previously captured published-schema34 fixture bytes and SHA256 are unchanged")
	check(not source.is_empty() and Rules.reason_v34(source).is_empty() and Rules.decode(JSON.parse_string(bytes.get_string_from_utf8())).is_empty(), "Frozen34 source decodes strictly and differs from current35")
	var expected := expected_current(source)
	var before := var_to_bytes(source)
	seed(580034)
	var next_rng := randi()
	seed(580034)
	var migrated := Migration.migrate_v34(source)
	check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Migration only changes version, preserving source and global RNG")
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Exact preserved field: " + field)
	check(Game._stats_for(migrated) == Game._stats_for(source), "Existing source stats are unchanged by migration")
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys(), "UID and location insertion order remain exact")
	check(Migration.migrate_v34(migrated).is_empty(), "Already migrated envelope cannot migrate twice")
	migrated.items.clear()
	check(var_to_bytes(source) == before, "Migration deep copy is detached from source")
	var path := "user://literal34.json"
	write(path, bytes)
	var store := Store.new()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and store.successful_saves == 1 and signals[0] == 1, "Raw34 migration commits once and emits once")
	check(FileAccess.get_file_as_bytes(path + ".v34-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Backup preserves exact original serialized bytes")
	var disk := FileAccess.get_file_as_bytes(path)
	check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated current35 load does not rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0, "Independent strict35 reopen preserves entire envelope")
	var game := Game.new()
	var message_path := "user://message34.json"
	write(message_path, bytes)
	check(game.load_build(message_path) and game.migrated_from_legacy and game.migration_message.contains("魔力") and not game.migration_message.contains("两瓶药剂"), "Migration message describes mana-before-life without claiming grants")


func test_bad_envelopes(source: Dictionary) -> void:
	for mutation: String in ["future", "duplicate_binding", "fractional_revision", "bool_revision", "extra_field", "missing_journey", "invalid_journey", "wrong_uid", "unknown_node", "wrong_allocated_type", "unknown_stat", "nan_revision", "nan_mastery"]:
		var bad := source.duplicate(true)
		match mutation:
			"future": bad.version = 36
			"duplicate_binding": bad.bindings.append(bad.bindings[0].duplicate())
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"extra_field": bad.mana_runtime = {}
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"wrong_uid": bad.items[bad.items.keys()[0]].uid = "wrong_uid"
			"unknown_node": bad.talents.allocated.append("unknown_mana_node"); bad.talents.normal_points -= 1
			"wrong_allocated_type": bad.talents.allocated = {"34098":true}
			"unknown_stat": bad.talents.damage_taken_from_mana_before_life = 0.4
			"nan_revision": bad.revision = NAN
			"nan_mastery": bad.talents.masteries["123"] = NAN
		check(not Rules.reason_v34(bad).is_empty() and Rules.decode_v34(bad).is_empty() and Migration.migrate_v34(bad).is_empty(), "Complete frozen34 source rejects: " + mutation)
		var on_disk := bad.duplicate(true)
		if mutation == "nan_revision": on_disk.revision = null
		if mutation == "nan_mastery": on_disk.talents.masteries["123"] = null
		rejected_preserving("user://invalid34-" + mutation + ".json", JSON.stringify(on_disk).to_utf8_buffer(), int(bad.version))
	for value: Variant in [null, [], true, NAN, INF, 34, "34"]:
		check(not Rules.reason_v34(value).is_empty() and Rules.decode_v34(value).is_empty() and Migration.migrate_v34(value).is_empty(), "Wrong envelope type rejected")


func test_faults(source: Dictionary, bytes: PackedByteArray) -> void:
	var expected := expected_current(source)
	var path := "user://backup-conflict.json"
	write(path, bytes)
	write(path + ".v34-backup.json", "retained backup".to_utf8_buffer())
	var store := Store.new()
	var initial := store.snapshot()
	check(not store.load_build(path) and store.snapshot() == initial and store.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == bytes and FileAccess.get_file_as_string(path + ".v34-backup.json") == "retained backup", "Conflicting backup and source remain untouched")
	check(store.save_build(path) != OK, "Conflicting backup protects later save")
	path = "user://backup-fail.json"
	write(path, bytes)
	store = Store.new()
	store._io = BackupFailIO.new()
	initial = store.snapshot()
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes and store.save_attempts == 0, "Backup failure prevents commit")
	path = "user://external-during-backup.json"
	write(path, bytes)
	store = Store.new()
	store._io = ExternalIO.new()
	initial = store.snapshot()
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_string(path) == "external writer" and store.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v34-backup.json") == bytes, "Concurrent external edit remains untouched and original backup is preserved")
	path = "user://real-atomic-fail.json"
	write(path, bytes)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create real atomic temp-file collision")
	store = Store.new()
	initial = store.snapshot()
	var signals := [0]
	store.changed.connect(func(): signals[0] += 1)
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes and signals[0] == 0 and store.successful_saves == 0 and store.save_attempts == 1, "Atomic-write failure preserves source, memory, revision and signals")
	check(FileAccess.get_file_as_bytes(path + ".v34-backup.json") == bytes, "Failed commit retains exact source backup")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove failure injection")
	check(store.load_build(path) and store.snapshot() == expected and store.successful_saves == 1 and signals[0] == 1, "Same-backup retry succeeds exactly once")
	var disk := FileAccess.get_file_as_bytes(path)
	write(path, "external after commit".to_utf8_buffer())
	check(store.save_build(path) == ERR_FILE_ALREADY_IN_USE and store.snapshot() == expected and store._disk_bytes == disk and FileAccess.get_file_as_string(path) == "external after commit", "Current receipt protects later external writes")


func test_allocation_transaction(candidate: Dictionary) -> void:
	if candidate.is_empty(): return
	var before_target := candidate.duplicate(true)
	before_target.talents.allocated.pop_back()
	before_target.talents.normal_points += 1
	var game := Game.new()
	game._accept_memory(before_target)
	var path := "user://allocation35.json"
	check(game.save_build(path) == OK and Rules.reason(before_target).is_empty(), "Full legal approach to34098 has a real disk receipt")
	var bytes := FileAccess.get_file_as_bytes(path)
	var signals := [0]
	game.changed.connect(func(): signals[0] += 1)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create allocation write failure")
	check(not game.allocate_passive("34098", 0, game.revision(), path).ok and game.snapshot() == before_target and FileAccess.get_file_as_bytes(path) == bytes and game._disk_bytes == bytes and signals[0] == 0 and is_zero_approx(game.get_stats().get(STAT, -1.0)), "Failed actual allocation grants no stat or point spend and preserves disk receipt")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove allocation failure")
	check(game.allocate_passive("34098", 0, game.revision(), path).ok and game.revision() == before_target.revision + 1 and game.snapshot().talents.normal_points == before_target.talents.normal_points - 1 and signals[0] == 1 and is_equal_approx(game.get_stats().get(STAT, -1.0), 0.4), "Allocation retry spends once and exposes exact40% only after commit")
	var accepted := game.snapshot()
	bytes = FileAccess.get_file_as_bytes(path)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create refund write failure")
	check(not game.refund_passive("34098", game.revision(), path).ok and game.snapshot() == accepted and FileAccess.get_file_as_bytes(path) == bytes and signals[0] == 1, "Failed refund preserves granted stat, points, revision and bytes")
	check(DirAccess.remove_absolute(path + ".tmp") == OK and game.refund_passive("34098", game.revision(), path).ok and signals[0] == 2 and is_zero_approx(game.get_stats().get(STAT, -1.0)), "Refund retry returns exactly one point and removes grant")
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == game.snapshot() and reopened.save_attempts == 0, "Current allocation/refund round trip loads without rewriting")


func test_prior_chain(source: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v055-migration/fixtures/v33-active-allocated.json")
	var old33 := Rules.decode_v33(JSON.parse_string(bytes.get_string_from_utf8()))
	var old34 := Prior.migrate_v33(old33)
	var expected34 := old33.duplicate(true)
	expected34.version = 34
	check(old34 == expected34 and Rules.reason_v34(old34).is_empty(), "Prior Forgeblade migration remains frozen at34 after VERSION35")
	check(Migration.migrate_v34(old34) == expected_current(old33), "Focused33→34→35 chain changes only version")
	var path := "user://prior33.json"
	write(path, bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot() == expected_current(old33), "Actual old33 allocated fixture reaches current35")
	check(store.save_attempts == 1 and store.successful_saves == 1 and FileAccess.get_file_as_bytes(path + ".v33-backup.json") == bytes and not FileAccess.file_exists(path + ".v34-backup.json"), "Prior chain commits once and backs up original33 bytes only")
	var fresh := Store.new().snapshot()
	check(fresh.version == 35 and Rules.reason(fresh).is_empty() and fresh == expected_current(source), "Built-in complete migration chain reaches valid35 with exact published34 default contents")
	check(Store.Currency.total_quantity(fresh.items).quantity == 0 and not fresh.talents.allocated.has("34098") and is_zero_approx(Game._stats_for(fresh).get(STAT, -1.0)), "Default construct grants no mana guard node, currency, item or point")


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-v058-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	var bytes := FileAccess.get_file_as_bytes(FIXTURE)
	var source := Rules.decode_v34(JSON.parse_string(bytes.get_string_from_utf8()))
	var scope := OS.get_environment("V058_MANA_GUARD_SCOPE")
	if scope == "raw_migration":
		# Recheck only the production migration-message correction and its real load.
		test_raw_migration(source, bytes)
	else:
		test_parser_and_gates()
		test_raw_migration(source, bytes)
		var candidate := test_paths(source)
		test_bad_envelopes(source)
		test_faults(source, bytes)
		test_allocation_transaction(candidate)
		test_prior_chain(source)
	var report := {"scope":"raw_migration" if scope == "raw_migration" else "full_focused", "old_schema":34, "new_schema":35, "source_sha256":SourceTree.Data.SOURCE_SHA256, "new_full_standard_nodes":["34098"], "parser_only_nonstandard_nodes":["42144", "922"], "classes":route_report, "source_fixture":FIXTURE, "source_bytes":bytes.size(), "source_sha256_file":digest(bytes), "checks":checks, "failures":failures}
	var report_path := OS.get_environment("V058_MANA_GUARD_REPORT")
	if not report_path.is_empty(): FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("Mana guard schema35 migration and source admission: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
