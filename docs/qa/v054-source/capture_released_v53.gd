extends SceneTree
## Run with --path <released-v53-source> --script <this-file> -- <fixture-dir>.
## The only runtime dependencies are released source scripts, with isolated user data.
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")


func require(ok: bool, label: String) -> bool:
	if not ok:
		push_error(label)
		quit(1)
	return ok


func capture(directory: String, name: String, value: Dictionary) -> bool:
	if not require(value.version == 32 and Rules.reason(value).is_empty(), "Released32 snapshot validates"): return false
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	if not require(file != null, "Fixture output opens"): return false
	file.store_string(" \r\n" + JSON.stringify(value, "  ", true, true).replace("\n", "\r\n") + "\r\n\t")
	file.close()
	return true


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not require(xdg.begins_with("/tmp/godot-m1-v054-fixture") and OS.get_user_data_dir().begins_with(xdg + "/"), "Isolated fixture directory required"): return
	if not require(Rules.VERSION == 32 and str(ProjectSettings.get_setting("application/config/version")) == "0.53.0", "Exact published v53 source required"): return
	var arguments := OS.get_cmdline_user_args()
	if not require(arguments.size() == 1, "Provide fixture directory"): return
	var directory: String = arguments[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var game := Game.new()
	if not capture(directory, "v32-default.json", game.snapshot()): return
	# Open the literal previous fixture with the genuine published v53 loader.
	var path := "user://build_save.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/v053-source/fixtures/v31-active-allocated.json"))
	file.close()
	if not require(game.load_build(path), "Released32 opens historical active journey"): return
	for id: String in ["54396", "2550"]:
		if not require(game.allocate_passive(id, 0, game.revision(), path).ok, "Released Fire DoT node allocates: " + id): return
	if not capture(directory, "v32-active-allocated.json", game.snapshot()): return
	var oracle := {"version":32,"source_policy":32,"full_nodes":{},"full_masteries":{}}
	for id: String in SourceTree.Data.standard_ids():
		var node := SourceTree.Data.node(id)
		if node.type == "mastery":
			for effect: Dictionary in node.mastery_effects:
				var execution := SourceTree.node_effect(id, int(effect.effect), 32)
				if execution.status == "full": oracle.full_masteries[id + ":" + str(int(effect.effect))] = execution.grants
		else:
			var execution := SourceTree.node_effect(id, 0, 32)
			if execution.status == "full": oracle.full_nodes[id] = execution.grants
	file = FileAccess.open(directory.path_join("v32-vocabulary-oracle.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(oracle, "  ", true, true) + "\n")
	file.close()
	print("Released v53 source exported two literal schema32 fixtures and full source vocabulary oracle")
	quit()
