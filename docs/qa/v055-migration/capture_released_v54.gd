extends SceneTree
## Run against the already imported, published v0.54 source; never rewrite version.
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


func require(ok: bool, label: String) -> bool:
	if not ok:
		push_error(label)
		quit(1)
	return ok


func capture(directory: String, name: String, game: RefCounted, path: String) -> bool:
	if not require(game.snapshot().version == 33 and Rules.reason(game.snapshot()).is_empty(), "Published schema33 validates"): return false
	if not require(game.save_build(path) == OK, "Published serializer persists actual save"): return false
	var bytes := FileAccess.get_file_as_bytes(path)
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	if not require(file != null, "Fixture output opens"): return false
	file.store_buffer(bytes)
	file.close()
	return true


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not require(xdg.begins_with("/tmp/godot-m1-v055-fixture") and OS.get_user_data_dir().begins_with(xdg + "/"), "Isolated fixture directory required"): return
	if not require(Rules.VERSION == 33 and str(ProjectSettings.get_setting("application/config/version")) == "0.54.0", "Published v54 source required"): return
	var args := OS.get_cmdline_user_args()
	if not require(args.size() == 1, "Provide new fixture directory"): return
	var directory: String = args[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var game := Game.new()
	if not capture(directory, "v33-default.json", game, "user://default-capture.json"): return
	var path := "user://town_test_build_save.json"
	game = Game.new()
	if not require(game.save_build(path) == OK, "Actual test town save created"): return
	if not require(game.select_class(4, game.revision(), path).ok, "Published API selects Duelist"): return
	if not require(game.add_xp(2000), "Published progress API grants enough allocation budget"): return
	for id: String in ["39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544", "11364", "43684", "59766"]:
		if not require(game.allocate_passive(id, 0, game.revision(), path).ok, "Published native allocation: " + id): return
	if not require(game.town_claim_offer("currency:calibration_shard", game.revision(), path).ok, "Published town grants real currency stack"): return
	var rng := RandomNumberGenerator.new()
	rng.seed = 550033
	if not require(not game.award_equipment(rng, 16, "rare", "local_weapon").is_empty(), "Published loot API produces existing equipment"): return
	if not require(game.bind_group("group_000001", KEY_Q, game.revision(), path).ok == false, "Published reserved binding rejects"): return
	if not require(game.bind_group("group_000001", KEY_F1, game.revision(), path).ok, "Published API changes real group binding"): return
	if not capture(directory, "v33-active-allocated.json", game, path): return
	print("Published v54 exported native schema33 default and actual faster-burn allocations, equipment, currency and bindings")
	quit()
