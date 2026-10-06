extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v066-messages"):
		quit(78); return
	var cases := [[41, "res://docs/qa/v066-migration/fixtures/v41-ir-frozen-v065.json", "符印伏击辅助"],
		[40, "res://docs/qa/v065-migration/fixtures/v40-frozen-v064.json", "狂信者的誓约"],
		[39, "res://docs/qa/v064-migration/fixtures/v39-frozen-v063.json", "铁反射"]]
	var failures := 0
	for row: Array in cases:
		var path := "user://message%d.json" % row[0]
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(row[1])); file.close()
		var model := Model.new()
		var ok: bool = model.load_build(path) and model.migration_message.contains(row[2]) and model.migration_message.contains("不额外赠物或赠点")
		if not ok: failures += 1; push_error("Migration message failed: " + str(row[0]))
	print("Ambush migration messages: 3 checks, %d failures" % failures)
	quit(1 if failures else 0)
