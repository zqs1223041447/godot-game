extends SceneTree
## Focused schema36 source admission, real allocation and frozen35 persistence.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/elemental_resistance_cap_migration.gd")
const Prior = preload("res://scripts/save/mana_guard_migration.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const ROOT := "res://docs/qa/v059-source/"
const STATS := ["maximum_fire_resistance_add", "maximum_cold_resistance_add", "maximum_lightning_resistance_add"]
const MAX_IDS := ["15522", "24133", "25989", "34917", "42009", "45341", "48929", "50029", "5065", "53118", "60031", "6043"]
var checks := 0
var failures := 0
var witness: Dictionary
var evidence := {}


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
	var value := source.duplicate(true)
	value.version = 36
	return value


func route_candidate(source: Dictionary, count: int = 74) -> Dictionary:
	var value := current(source)
	value.progress = {"level":69, "xp":0}
	value.talents.class_id = 1
	value.talents.allocated = witness.allocated.slice(0, count)
	value.talents.masteries = {}
	value.talents.normal_points = 74 - count
	return value


func test_parser() -> void:
	check(Rules.VERSION == 36 and Rules.V35_VERSION == 35 and Source.CURRENT_SAVE_VERSION == 36, "Current envelope and source policy are36")
	check(Source._execution_policy(0) == 19 and Source._execution_policy(34) == 33 and Source._execution_policy(35) == 35, "Earlier policies remain frozen")
	for amount: String in ["0", "1", "2", "1.5"]:
		for index: int in range(4):
			var line: String = "+" + amount + "% to maximum " + ["Fire Resistance", "Cold Resistance", "Lightning Resistance", "unused"][index] if index < 3 else "+" + amount + "% to all maximum Elemental Resistances"
			var parsed := Patterns.parse_line(line)
			check(parsed.supported and parsed.grants.size() == (3 if index == 3 else 1), "Exactly one or three cap grants: " + line)
			for grant: Dictionary in parsed.grants:
				check(STATS.has(grant.stat) and grant.mode == "flat" and is_equal_approx(grant.value, float(amount) * 0.01), "Percentage points become fractional flat modifiers")
			if index < 3: check(parsed.grants[0].stat == STATS[index], "Single-element grant stays scoped")
			for version: int in [0, 19, 25, 32, 33, 34, 35, 36, 35, 36]:
				check(Source.line_effect(line, version).supported == (version >= 36), "Cache cannot cross cap vocabulary gate")
			check(not Patterns.parse_line(line, true, true, true, true, true, true, true, true, true, false).supported, "Explicit frozen35 parser rejects cap lines")
			for bad: String in [line + " while on Full Life", line + ".", " " + line, line + " ", line + "\n", line + "\r", "Minions have " + line, line.replace("+", "-"), line.replace("+", "")]:
				check(not Patterns.parse_line(bad).supported, "Whole-line cap grammar rejects condition, scope, negative, suffix and whitespace")
	for bad: Variant in [null, [], {}, true, 1, NAN, INF, "+1% to maximum Chaos Resistance", "+1% to all maximum Resistances", "+1% to maximum Elemental Resistances", "+NaN% to maximum Fire Resistance", "+" + "9".repeat(400) + "% to all maximum Elemental Resistances"]:
		check(not Patterns.parse_line(bad).supported, "Unknown, malformed and nonfinite cap forms remain rejected")
	var opened: Array[String] = []
	var mastery_checks := 0
	for id: String in Source.Data.standard_ids():
		var old := Source.node_effect(id, 0, 35)
		var fresh := Source.node_effect(id, 0, 36)
		if old.status == "full": check(old == fresh, "Existing full standard node grants are unchanged: " + id)
		elif fresh.status == "full": opened.append(id)
		for option: Dictionary in Source.Data.node(id).mastery_effects:
			check(Source.node_effect(id, int(option.effect), 35) == Source.node_effect(id, int(option.effect), 36), "Existing mastery coverage and grants stay unchanged")
			mastery_checks += 1
	opened.sort()
	check(opened == MAX_IDS, "Exactly the twelve contracted standard nodes newly open")
	for id: String in MAX_IDS:
		for line: String in Source.lines_for(id):
			check(Localization.line_status(line).implemented and not Localization.display_line(line).ends_with(Localization.NOT_IMPLEMENTED), "Every supported source line has consumer-backed dynamic Chinese status: " + id)
	for id: String in ["11820", "20832", "40743"]:
		var effect := Source.node_effect(id)
		check(effect.status == "partial" and not effect.unsupported.is_empty(), "Mixed node retains whole-node lock: " + id)
		for line: String in effect.unsupported:
			check(Localization.display_line(line).ends_with(Localization.NOT_IMPLEMENTED), "Unsupported mixed line retains Chinese marker")
		for line: String in effect.supported:
			check(Localization.line_status(line).implemented, "Mixed node may show individually supported lines")
	for id: String in ["38683", "42313", "44203", "48803", "54766"]:
		var node := Source.Data.node(id)
		check(Source.node_effect(id).status == "full" and not Source.Data.standard_ids().has(id) and node.group_id.is_empty() and not node.has_position, "Text coverage grants no standard-graph membership: " + id)
	for row: Dictionary in Localization.STAT_CONSUMER_GROUPS.elemental_resistance_caps.code_checks:
		check(FileAccess.get_file_as_string("res://" + row.path).contains(row.contains), "Consumer manifest references current executable path")
	evidence.newly_full = opened
	evidence.mastery_options_compared = mastery_checks


func test_rejected_source(source: Dictionary) -> void:
	var injected := route_candidate(source)
	check(Rules.reason(injected).is_empty(), "Full witness independently legal under schema36")
	injected.version = 35
	var permissive := func(_value: Dictionary) -> String: return ""
	check(not Rules.reason_v35(injected, permissive).is_empty() and Rules.decode_v35(injected).is_empty() and Migration.migrate_v35(injected, permissive).is_empty(), "Native frozen35 validation rejects newly injected nodes even with permissive callback")
	reject_bytes("old35-injected-caps", JSON.stringify(injected).to_utf8_buffer())
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "invalid_journey", "bad_uid", "unknown_node", "duplicate_node", "wrong_nodes_type", "unknown_stat", "over_budget", "bad_source", "nan_revision", "nan_mastery"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.maximum_fire_resistance_add = 0.1
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"bad_uid": bad.items[bad.items.keys()[0]].uid = "other"
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"duplicate_node": bad.talents.allocated.append(bad.talents.allocated[0]); bad.talents.normal_points -= 1
			"wrong_nodes_type": bad.talents.allocated = {"58833":true}
			"unknown_stat": bad.talents.maximum_fire_resistance_add = 0.1
			"over_budget": bad.talents.normal_points += 1
			"bad_source": bad.talents.source_version = "3.29.2"
			"nan_revision": bad.revision = NAN
			"nan_mastery": bad.talents.masteries["123"] = NAN
		check(not Rules.reason_v35(bad, permissive).is_empty() and Rules.decode_v35(bad).is_empty() and Migration.migrate_v35(bad, permissive).is_empty(), "Complete frozen35 rejection: " + mutation)
		if mutation == "nan_revision": bad.revision = null
		if mutation == "nan_mastery": bad.talents.masteries["123"] = null
		reject_bytes("invalid35-" + mutation, JSON.stringify(bad).to_utf8_buffer())
	for value: Variant in [null, [], true, 35, "35", NAN, INF]:
		check(not Rules.reason_v35(value).is_empty() and Rules.decode_v35(value).is_empty() and Migration.migrate_v35(value).is_empty(), "Wrong envelope types fail before migration")
	reject_bytes("broken-json", "{ invalid old bytes\r\n".to_utf8_buffer())


func reject_bytes(name: String, bytes: PackedByteArray) -> void:
	var path := "user://" + name + ".json"
	write(path, bytes)
	var store := Store.new()
	var initial := store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	check(not store.load_build(path) and store.snapshot() == initial and FileAccess.get_file_as_bytes(path) == bytes, "Invalid old file keeps bytes and memory: " + name)
	check(store.save_attempts == 0 and store.successful_saves == 0 and events[0] == 0 and not FileAccess.file_exists(path + ".v35-backup.json"), "Invalid source causes no backup, save or signal")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Invalid original remains protected from later overwrite")


func test_migration(source: Dictionary, bytes: PackedByteArray) -> void:
	var expected := current(source)
	var before := var_to_bytes(source)
	var rng: Variant = rand_from_seed(35731)
	var migrated := Migration.migrate_v35(source)
	check(migrated == expected and var_to_bytes(source) == before and rand_from_seed(35731) == rng, "Migration changes only version and leaves input and deterministic RNG untouched")
	migrated.journey.best_tiers.sunwell_terrace = 3
	check(var_to_bytes(source) == before, "Migration deeply detaches nested journey")
	var path := "user://released35.json"
	write(path, bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "Actual released35 saves and publishes exactly one migration")
	check(FileAccess.get_file_as_bytes(path + ".v35-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Original serialized bytes are backed up before atomic commit")
	check(game.migrated_from_legacy and game.migration_message.contains("三元素最大抗性") and game.migration_message.contains("不额外赠物或赠点"), "Migration explains unlocked caps without promising free stats or items")
	var disk := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Second load performs no migration or rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v35-backup.json") == bytes, "Independent current36 reopen keeps original backup and all content")
	var previous := Rules.decode_v34(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v056/fixtures/v34-default.json")))
	var frozen35 := Prior.migrate_v34(previous)
	check(not frozen35.is_empty() and frozen35.version == 35 and Rules.reason_v35(frozen35).is_empty(), "Earlier ManaGuard migration retains frozen35 target")
	check(Migration.migrate_v35(frozen35) == current(frozen35), "Prior34→35→36 chain changes no original content")
	var prior_path := "user://released34.json"
	var prior_bytes := FileAccess.get_file_as_bytes("res://docs/qa/v056/fixtures/v34-default.json")
	write(prior_path, prior_bytes)
	var chain := Store.new()
	check(chain.load_build(prior_path) and chain.snapshot().version == 36 and chain.save_attempts == 1 and FileAccess.get_file_as_bytes(prior_path + ".v34-backup.json") == prior_bytes, "Focused genuine34 load commits once and backs up original version bytes")
	evidence.old_fixture_sha256 = digest(bytes)
	evidence.old_fixture_bytes = bytes.size()


func test_failures(bytes: PackedByteArray) -> void:
	for failure: String in ["collision", "backup", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path, bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "collision": write(path + ".v35-backup.json", "retained backup".to_utf8_buffer())
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic": check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject real temporary-file write collision")
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration publishes nothing: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Failure preserves original or independent writer bytes")
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup succeeds before first commit attempt")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v35-backup.json") == "retained backup", "Conflicting backup retained verbatim")
		if failure in ["external", "atomic"]: check(FileAccess.get_file_as_bytes(path + ".v35-backup.json") == bytes, "Backup retains exact original bytes on failed commit")
		if failure == "atomic":
			check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.successful_saves == 1 and events[0] == 1, "Retry with existing identical backup commits once")
		else: check(store.save_build(path) != OK, "Failed load also protects later saves")


func test_transactions(source: Dictionary) -> void:
	var initial := route_candidate(source, 1)
	var game := Game.new()
	game._accept_memory(initial)
	var path := "user://actual-route.json"
	check(Rules.reason(initial).is_empty() and game.save_build(path) == OK, "Start persisted level69 Marauder with exact73 point budget")
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	var opened := 0
	for index: int in range(1, witness.allocated.size()):
		var id: String = witness.allocated[index]
		var before := game.snapshot()
		var previous := game.get_stats()
		if id == "48929": failed_transaction(game, path, id, false, events)
		check(game.allocate_passive(id, 0, game.revision(), path).ok, "Actual ordered allocation commits: " + id)
		check(game.snapshot().talents.normal_points == 73-index and game.revision() == before.revision+1 and events[0] == index, "Allocation spends one point, advances one revision and emits one event")
		if MAX_IDS.has(id):
			opened += 1
			var stats := game.get_stats()
			var expected: Dictionary = previous.duplicate(true)
			for grant: Dictionary in Source.node_effect(id).grants:
				if STATS.has(grant.stat): expected[grant.stat] += grant.value
			for stat: String in STATS: check(is_equal_approx(stats[stat], expected[stat]), "Canonical model consumes each exact cap grant once: " + id)
	var full := game.snapshot()
	var stats := game.get_stats()
	check(opened == 12 and full.talents.normal_points == 0 and full.talents.allocated.size() == 74, "All twelve caps reachable in same73 point normal allocation")
	var profile := Defense.resistance_profile(stats)
	for element: String in ["fire", "cold", "lightning"]:
		check(is_equal_approx(stats["maximum_"+element+"_resistance_add"], 0.08) and is_equal_approx(stats[element+"_resistance"], witness.expected_raw[element]), "Source route supplies independent raw and maximum resistance: " + element)
		check(profile.ok and is_equal_approx(profile.maximum_resistances[element], 0.83) and is_equal_approx(profile.effective_resistances[element], 0.83), "Authoritative profile actually consumes source cap: " + element)
		var hit := Defense.incoming_source_hit({element:100.0}, stats, 0.0, 1000.0)
		check(hit.ok and is_equal_approx(hit.remaining_health, 983.0), "Real elemental hit loses17 life at attained83percent: " + element)
	var burn := Defense.incoming_burn(100.0, stats.fire_resistance, 0.0, 1000.0, "player", 0.0, 0.0, stats.maximum_fire_resistance_add)
	check(burn.ok and is_equal_approx(burn.remaining_health, 983.0), "Real burn consumes same attained cap")
	var raw_only := stats.duplicate(true)
	for stat: String in STATS: raw_only.erase(stat)
	var zero := raw_only.duplicate(true)
	for stat: String in STATS: zero[stat] = 0.0
	check(Defense.source_profile(raw_only) == Defense.source_profile(zero) and is_equal_approx(Defense.source_profile(raw_only).effective_resistances.fire, 0.75), "Missing and zero cap fields preserve original source defense contract")
	var reloaded := Game.new()
	check(reloaded.load_build(path) and reloaded.snapshot() == full and reloaded.get_stats() == stats and reloaded.save_attempts == 0, "Whole source build reloads without a second migration")
	for id: String in ["11820", "20832", "40743", "38683", "42313", "44203", "48803", "54766"]:
		var relaxed := full.duplicate(true)
		relaxed.progress.level = 119
		relaxed.talents.normal_points = 50
		game._accept_memory(relaxed)
		check(not game.available_passives().has(id) and not game.allocate_passive(id, 0, game.revision(), path).ok and game.snapshot() == relaxed, "Whole-node and graph admission remain locked despite parsed cap: " + id)
	game._accept_memory(full)
	var reverse: Array = witness.allocated.duplicate()
	reverse.reverse()
	for index: int in range(reverse.size()-1):
		var id: String = reverse[index]
		if id == "42009": failed_transaction(game, path, id, true, events)
		check(game.refund_passive(id, game.revision(), path).ok, "Actual reverse-order refund commits: " + id)
	check(game.snapshot().talents.allocated == initial.talents.allocated and game.snapshot().talents.normal_points == 73 and events[0] == 146, "Every spent point is returned exactly once")
	for stat: String in STATS: check(is_zero_approx(game.get_stats()[stat]), "Refund removes all source cap modifiers")
	evidence.actual_allocation_count = 73
	evidence.actual_refund_count = 73
	evidence.raw_resistances = profile.raw_resistances
	evidence.maximum_resistances = profile.maximum_resistances
	evidence.effective_resistances = profile.effective_resistances


func failed_transaction(game: RefCounted, path: String, id: String, refund: bool, events: Array) -> void:
	var before: Dictionary = game.snapshot()
	var stats: Dictionary = game.get_stats()
	var bytes := FileAccess.get_file_as_bytes(path)
	var count: int = events[0]
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject actual passive save failure")
	var result: Dictionary = game.refund_passive(id, game.revision(), path) if refund else game.allocate_passive(id, 0, game.revision(), path)
	check(not result.ok and game.snapshot() == before and game.get_stats() == stats and events[0] == count and FileAccess.get_file_as_bytes(path) == bytes and game._disk_bytes == bytes, "Failed passive transaction preserves points, grants, revision, events and disk receipt")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove isolated temporary-file fault before retry")


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v059-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	witness = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "allocation-witness.json"))
	var bytes := FileAccess.get_file_as_bytes(ROOT + "fixtures/v35-released.json")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "fixtures/manifest.json"))
	check(digest(bytes) == manifest.sha256 and bytes.size() == int(manifest.bytes), "Released35 fixture matches original committed bytes")
	var source := Rules.decode_v35(JSON.parse_string(bytes.get_string_from_utf8()))
	check(not source.is_empty() and Rules.reason_v35(source).is_empty(), "Actual released35 fixture fully validates before migration")
	if source.is_empty():
		quit(1)
		return
	test_parser()
	test_rejected_source(source)
	test_migration(source, bytes)
	test_failures(bytes)
	test_transactions(source)
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V059_SOURCE_REPORT")
	if not output.is_empty(): write(output, (JSON.stringify(evidence, "\t", true, true)+"\n").to_utf8_buffer())
	print("Source resistance cap migration: %d checks, %d failures;73 actual allocations/73 refunds" % [checks, failures])
	quit(1 if failures else 0)
