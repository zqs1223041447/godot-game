extends SceneTree
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Legacy = preload("res://scripts/build_state.gd")
class FailingStore extends Store:
	var fail_writes := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path, bytes)
var checks := 0
var failures := 0
var notifications := 0
func _initialize() -> void:
	var root_dir := OS.get_environment("XDG_DATA_HOME")
	if not root_dir.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(root_dir + "/"):
		quit(78)
		return
	var path := "user://canonical-%d.json" % Time.get_ticks_usec()
	var state := Store.new()
	check(Rules.reason(state.snapshot()).is_empty(), "fresh canonical valid")
	check(Rules.decode(JSON.parse_string(JSON.stringify(state.snapshot()))) == state.snapshot(), "explicit JSON decoder exact")
	state.changed.connect(func(): notifications += 1)
	check(state.save_build(path) == OK, "fresh save")
	var start := state.snapshot()
	var result := state.move_item("swift_blade", {"kind":"equipment","slot_id":"weapon"}, state.revision(), path)
	check(result.ok and notifications == 1, "one committed notification")
	check(state.location("swift_blade") == {"kind":"equipment","slot_id":"weapon"}, "actual location committed")
	check(state.location("ember_wand").kind == "bag", "displaced equipment returned")
	check(Rules.decode(JSON.parse_string(FileAccess.get_file_as_string(path))) == state.snapshot(), "memory equals exact disk candidate")
	var current := state.snapshot()
	var bytes := FileAccess.get_file_as_bytes(path)
	check(not state.move_item("ember_wand", {"kind":"equipment","slot_id":"weapon"}, 0, path).ok, "stale revision denied")
	check(state.snapshot() == current and bytes == FileAccess.get_file_as_bytes(path) and notifications == 1, "stale atomic no save")
	var invalid := state.move_item("azure_charm", {"kind":"equipment","slot_id":"ring_1"}, state.revision(), path)
	check(not invalid.ok and state.snapshot() == current and bytes == FileAccess.get_file_as_bytes(path), "type mismatch atomic")
	var loaded := Store.new()
	check(loaded.load_build(path) and loaded.snapshot() == state.snapshot(), "canonical reload")
	var failing := FailingStore.new()
	check(failing.load_build(path), "fault seam loads")
	failing.fail_writes = true
	var before := failing.snapshot()
	check(not failing.move_item("ember_wand", {"kind":"equipment","slot_id":"weapon"}, failing.revision(), path).ok, "write failure surfaced")
	check(failing.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "write failure preserves items sequence and disk")
	failing.fail_writes = false
	check(failing.move_item("ember_wand", {"kind":"equipment","slot_id":"weapon"}, failing.revision(), path).ok, "same request can retry")
	var externally_changed := failing.snapshot()
	externally_changed.version = 99
	write_bytes(path, JSON.stringify(externally_changed).to_utf8_buffer())
	var external_bytes := FileAccess.get_file_as_bytes(path)
	before = failing.snapshot()
	check(failing.save_build(path) == ERR_FILE_ALREADY_IN_USE and failing.snapshot() == before, "external future rewrite protected before save")
	check(not failing.load_build(path), "future load rejected")
	check(failing.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == external_bytes, "future source remains protected")
	# Migration consumes a byte-exact BOM source only after backup and write succeed.
	var old := Legacy.new()
	var old_path := path + ".old"
	var old_bytes := PackedByteArray([239,187,191]) + JSON.stringify(old._snapshot(), "  ").to_utf8_buffer()
	write_bytes(old_path, old_bytes)
	var migrating := Store.new()
	check(migrating.load_build(old_path), "real legacy migration saved")
	check(FileAccess.get_file_as_bytes(old_path + ".v13-backup.json") == old_bytes, "original BOM whitespace bytes backed up")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(old_path)).version) == Rules.VERSION and Rules.VERSION == 17
		and migrating.successful_saves == 1, "migration committed once to current v16 schema")
	var conflict_path := path + ".conflict"
	write_bytes(conflict_path, old_bytes)
	write_bytes(conflict_path + ".v13-backup.json", "other backup".to_utf8_buffer())
	var conflict := Store.new()
	before = conflict.snapshot()
	check(not conflict.load_build(conflict_path), "backup conflict rejected")
	check(conflict.snapshot() == before and FileAccess.get_file_as_bytes(conflict_path) == old_bytes, "backup failure no memory or source mutation")
	var fault_path := path + ".fault"
	write_bytes(fault_path, old_bytes)
	var fault := FailingStore.new()
	fault.fail_writes = true
	before = fault.snapshot()
	check(not fault.load_build(fault_path), "migration atomic-write fault rejected")
	check(fault.snapshot() == before and FileAccess.get_file_as_bytes(fault_path) == old_bytes, "migration failure atomic")
	check(FileAccess.get_file_as_bytes(fault_path + ".v13-backup.json") == old_bytes, "successful backup retained after failed replacement")
	# Copies cannot mutate live state.
	var projected := state.snapshot()
	projected.items.clear()
	check(not state.snapshot().items.is_empty(), "snapshot detached")
	var malformed := start.duplicate(true)
	malformed.locations.swift_blade = malformed.locations.ember_wand.duplicate()
	check(not Rules.reason(malformed).is_empty(), "duplicate equipment target rejected")
	malformed = start.duplicate(true)
	malformed.next_item_serial = 1
	check(not Rules.reason(malformed).is_empty(), "consumed item sequence cannot go backward")
	for bad: Variant in [true, 1.5, "1", null]:
		malformed = start.duplicate(true)
		malformed.revision = bad
		check(Rules.decode(malformed).is_empty(), "invalid JSON integer rejected")
	for field: String in ["items", "locations", "progress", "crafting", "talents", "migration_ledger"]:
		malformed = start.duplicate(true)
		malformed[field] = []
		check(not Rules.reason(malformed).is_empty(), "invalid dictionary safely rejected")
	print("Canonical build store: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
