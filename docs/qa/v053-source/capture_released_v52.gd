extends SceneTree
## Run with --path <released-v52-source> --script <this-file> -- <fixture-dir>.
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
	if not require(value.version == 31 and Rules.reason(value).is_empty(), "Released31 snapshot validates"): return false
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	if not require(file != null, "Fixture output opens"): return false
	file.store_string(" \r\n" + JSON.stringify(value, "  ", true, true).replace("\n", "\r\n") + "\r\n\t")
	file.close()
	return true


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not require(xdg.begins_with("/tmp/godot-m1-v053-fixture") and OS.get_user_data_dir().begins_with(xdg + "/"), "Isolated fixture directory required"): return
	if not require(Rules.VERSION == 31 and str(ProjectSettings.get_setting("application/config/version")) == "0.52.0", "Exact published v52 source required"): return
	var arguments := OS.get_cmdline_user_args()
	if not require(arguments.size() == 1, "Provide fixture directory"): return
	var directory: String = arguments[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var game := Game.new()
	if not capture(directory, "v31-default.json", game.snapshot()): return
	# Open an actual released30 fixture using the released31 loader; never lower
	# the version of a current snapshot to manufacture a historical save.
	var path := "user://build_save.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/v052-shock-integration/fixtures/v30-active.json"))
	file.close()
	if not require(game.load_build(path), "Released31 opens historical active journey"): return
	game.add_xp(5000)
	if not require(game.select_class(1, game.revision(), path).ok, "Released class selection persists"): return
	for id: String in ["31628", "9511", "23881", "26523", "6446", "10221"]:
		if not require(game.allocate_passive(id, 0, game.revision(), path).ok, "Released old node allocates: " + id): return
	if not require(not game.award_gem("support:shock").is_empty() and game.save_build(path) == OK, "Released Shock item persisted"): return
	if not capture(directory, "v31-active-allocated.json", game.snapshot()): return
	var oracle := {"version":31,"source_policy":25,"full_nodes":{},"full_masteries":{},"gem_definitions":Game.Journey.GEM_DEFINITIONS,"milestones":[]}
	for id: String in SourceTree.Data.standard_ids():
		var node := SourceTree.Data.node(id)
		if node.type == "mastery":
			for effect: Dictionary in node.mastery_effects:
				var execution := SourceTree.node_effect(id, int(effect.effect), 31)
				if execution.status == "full": oracle.full_masteries[id + ":" + str(int(effect.effect))] = execution.grants
		else:
			var execution := SourceTree.node_effect(id, 0, 31)
			if execution.status == "full": oracle.full_nodes[id] = execution.grants
	for ordinal: int in range(1, 129): oracle.milestones.append(Game.Journey.gem_definition(ordinal))
	file = FileAccess.open(directory.path_join("v31-vocabulary-oracle.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(oracle, "  ", true, true) + "\n")
	file.close()
	print("Released v52 source exported two literal schema31 fixtures and full source vocabulary oracle")
	quit()
