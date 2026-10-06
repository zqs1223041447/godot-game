extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
func _initialize() -> void:
	var path: String = "res://docs/qa/v070-gameplay/fixtures/selected-above"
	var model := Model.new()
	var raw: Dictionary = Model.Rules.decode(JSON.parse_string(FileAccess.get_file_as_string(path + ".json")))
	model._accept_memory(raw)
	var stats: Dictionary = JSON.parse_string(JSON.stringify(model.get_stats()))
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + "-expected.json"))
	for key: String in stats:
		if stats[key] != expected.stats.get(key): print(key, " actual=", JSON.stringify(stats[key]), " expected=", JSON.stringify(expected.stats.get(key)))
	print("types=", typeof(stats), "/", typeof(expected.stats), " equality=", stats == expected.stats)
	quit(0)
