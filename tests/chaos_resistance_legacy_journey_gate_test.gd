extends SceneTree
## Narrow closeout proof: source50 cannot borrow current51 encounter vocabulary.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Migration = preload("res://scripts/save/chaos_resistance_affix_migration.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_buffer(bytes); file.close()

func active_fixture(source: Dictionary, special_id: String) -> Dictionary:
	var fixture := source.duplicate(true)
	fixture.journey.best_tiers.ginkgo_arcade = 1
	var compiled := Journey.Maps.compile_normal("ginkgo_arcade", 2, [], [special_id])
	if not check(compiled.ok, "Controlled active fixture compiles: " + special_id): return {}
	var started := Journey.start(fixture.journey, compiled.profile)
	if not check(started.ok, "Controlled tierII active fixture starts: " + special_id): return {}
	fixture.journey = started.journey
	return fixture

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v093-journey-gate-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78); return
	var source := Rules.decode_v50(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v091-root-ui/main-after-reforge.json")))
	if not check(not source.is_empty(), "Actual released schema50 source remains valid"):
		quit(1); return
	for special_id: String in ["frost_patrol", "storm_patrol"]:
		var fixture := active_fixture(source, special_id)
		var before := var_to_bytes(fixture); var expected := fixture.duplicate(true); expected.version = 51
		check(Rules.reason_v50(fixture).is_empty() and Rules.decode_v50(fixture) == fixture, "Existing active50 vocabulary remains accepted: " + special_id)
		check(Migration.migrate_v50(fixture) == expected and var_to_bytes(fixture) == before, "Existing active journey migrates version only: " + special_id)
		var bytes := JSON.stringify(fixture, "\t").to_utf8_buffer(); var path := "user://old-" + special_id + ".json"; write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v50-backup.json") == bytes, "Existing active50 loads with exact source backup: " + special_id)
	var injected := active_fixture(source, "chaos_patrol")
	check(Journey.reason(injected.journey).is_empty(), "Current generic journey validator alone accepts new option")
	var calls := [0]; var permissive := func(_value: Dictionary) -> String: calls[0] += 1; return ""
	check(Rules.reason_v50(injected, permissive) == "此存档版本不能包含新增地图特殊词缀" and calls[0] == 0, "Frozen50 rejects new encounter before callback")
	check(Rules.decode_v50(injected).is_empty() and Migration.migrate_v50(injected, permissive).is_empty() and calls[0] == 0, "Decode and migration cannot borrow new encounter")
	var path := "user://forged50.json"; var bytes := JSON.stringify(injected).to_utf8_buffer(); write(path, bytes)
	var rejected := Store.new(); var original := rejected.snapshot(); var changed := [0]; rejected.changed.connect(func(): changed[0] += 1)
	check(not rejected.load_build(path) and rejected.snapshot() == original and FileAccess.get_file_as_bytes(path) == bytes, "Forged50 preserves source bytes and live memory")
	check(rejected.save_attempts == 0 and rejected.successful_saves == 0 and changed[0] == 0 and not FileAccess.file_exists(path + ".v50-backup.json") and not FileAccess.file_exists(path + ".tmp"), "Forged50 never reaches backup, write or notification")
	check(rejected.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected destination remains protected")
	var current := injected.duplicate(true); current.version = 51
	check(Rules.reason(current).is_empty() and Rules.decode(current) == current, "Current51 explicitly accepts active chaos patrol")
	path = "user://current51.json"; bytes = JSON.stringify(current).to_utf8_buffer(); write(path, bytes)
	var accepted := Store.new()
	check(accepted.load_build(path) and accepted.snapshot() == current and accepted.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == bytes, "Current51 new encounter reopens without rewrite")
	check(Rules.SourceTree.CURRENT_SAVE_VERSION == 49 and Rules.SourceTree._execution_policy(51) == 49 and Rules.equipment_vocabulary_for_save_version(50) == 46, "Source49 and frozen equipment46 remain unchanged")
	var report := OS.get_environment("V093_JOURNEY_GATE_REPORT")
	if not report.is_empty(): write(report, (JSON.stringify({"checks":checks, "failures":failures}, "\t") + "\n").to_utf8_buffer())
	print("Chaos legacy journey gate: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
