extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v067-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	var path := "user://message42.json"
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v067-migration/fixtures/v42-ir-frozen-v066.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var model := Model.new()
	if not check(model.load_build(path), "Native42 migration succeeds before displaying a message"):
		quit(1)
		return
	check(model.migrated_from_legacy and model.migration_message.contains("牵引辅助") and model.migration_message.contains("原字节备份") and model.migration_message.contains("不额外赠物或赠点"), "Successful42 migration explains the new support, backup and no gifts")
	check(model.load_build(path) and not model.migrated_from_legacy and model.migration_message.is_empty(), "Reopening current43 does not repeat an old migration message")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ broken42")
	file.close()
	check(not model.load_build(path) and not model.migrated_from_legacy and model.migration_message.is_empty(), "Failed load never claims a completed migration")
	print("Inward Pull migration messages: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
