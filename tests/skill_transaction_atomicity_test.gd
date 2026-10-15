extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
class Fault extends Model:
	var writes := 0
	var fail_at := -1
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		writes += 1
		if writes == fail_at: return ERR_FILE_CANT_WRITE
		return super._write_bytes(path, bytes)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	for mode: String in ["move_fail", "repair_fail", "move", "repair", "bound", "rebound"]:
		var m := Fault.new()
		var path := "user://skill-transaction-" + mode + ".json"
		check(m.save_build(path) == OK, mode + " fixture saved")
		if mode == "rebound":
			check(m.bind_group("group_000003", KEY_1, m.revision(), path).ok, "rebind fixture")
		elif mode != "bound":
			check(m.unbind_group("group_000001", m.revision(), path).ok, mode + " fixture unbound")
		var skill := "bolt" if mode.begins_with("repair") else "frost"
		var uid := ""
		for id: String in m.snapshot().items:
			if m.item(id).definition_id == "skill:" + skill: uid = id; break
		var before := m.snapshot()
		var memory := var_to_bytes(before)
		var disk := FileAccess.get_file_as_bytes(path)
		var writes := m.writes
		var saves := m.successful_saves
		var signals := [0]
		m.changed.connect(func(): signals[0] += 1)
		m.fail_at = writes + (1 if mode.ends_with("fail") else 2)
		var result := m.slot_skill(0, skill)
		if mode.ends_with("fail"):
			check(not result, mode + " rejects")
			check(m.writes == writes + 1, mode + " one persistence attempt")
			check(memory == var_to_bytes(m.snapshot()), mode + " exact memory unchanged")
			check(disk == FileAccess.get_file_as_bytes(path), mode + " exact disk unchanged")
			check(m.successful_saves == saves and signals[0] == 0 and m.revision() == before.revision, mode + " no saves revision signals")
		else:
			var group := "group_000003" if mode == "rebound" else "group_000001"
			check(result, mode + " commits")
			check(m.writes == writes + 1 and m.successful_saves == saves + 1, mode + " exactly one write")
			check(m.revision() == before.revision + 1 and signals[0] == 1, mode + " exactly one revision and signal")
			check(m.location(uid) == {"kind":"skill_main", "group_id":group} and m.group_for_key(KEY_1) == group, mode + " move and binding together")
			check(m.snapshot().items == before.items, mode + " item UIDs and payloads unchanged")
			var repeat_memory := var_to_bytes(m.snapshot())
			var repeat_disk := FileAccess.get_file_as_bytes(path)
			check(not m.slot_skill(0, skill), mode + " repeated legacy bool no-op")
			check(m.writes == writes + 1 and signals[0] == 1 and repeat_memory == var_to_bytes(m.snapshot()) and repeat_disk == FileAccess.get_file_as_bytes(path), mode + " repeated request no writes")
		var loaded := Model.new()
		check(loaded.load_build(path) and loaded.snapshot() == m.snapshot(), mode + " persisted reload matches")
	var m := Fault.new()
	var path := "user://skill-binding-idempotence.json"
	check(m.save_build(path) == OK, "binding fixture saved")
	var memory := var_to_bytes(m.snapshot())
	var disk := FileAccess.get_file_as_bytes(path)
	var writes := m.writes
	var saves := m.successful_saves
	var signals := [0]
	m.changed.connect(func(): signals[0] += 1)
	for binding: Dictionary in m.snapshot().bindings:
		for repeat: int in range(2):
			var result := m.bind_group(binding.group_id, binding.keycode, m.revision(), path)
			check(not result.ok and result.error_code == "no_change", "same binding no_change at every position")
			check(m.writes == writes and m.successful_saves == saves and signals[0] == 0, "same binding no write or signals")
			check(memory == var_to_bytes(m.snapshot()) and disk == FileAccess.get_file_as_bytes(path), "same binding exact memory/disk order")
	check(m.bind_group("group_000001", KEY_F1, m.revision() - 1, path).error_code == "stale_revision", "binding stale guard retained")
	check(m.bind_group("group_000001", KEY_ESCAPE, m.revision(), path).error_code == "invalid_binding", "binding key guard retained")
	check(m.bind_group("group_000001", KEY_F1, m.revision(), path).ok, "ordinary UI binding still commits")
	check(m.group_for_key(KEY_F1) == "group_000001" and m.group_for_key(KEY_1).is_empty(), "ordinary rebind replaces prior key")
	print("skill_transaction_atomicity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
