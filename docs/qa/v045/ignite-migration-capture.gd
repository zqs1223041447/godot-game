extends SceneTree
## Run externally with --main-pack <frozen-v44/game.pck> --script <this-file> -- <fixture-dir>.
## This script must never load the new source tree to manufacture historical saves.
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")


func require(ok: bool, label: String) -> bool:
	if not ok:
		push_error(label)
		quit(1)
	return ok


func capture(directory: String, name: String, value: Dictionary) -> bool:
	if not require(value.version == 27 and Rules.reason(value).is_empty(), "Frozen v27 snapshot is valid"): return false
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	if not require(file != null, "Fixture output can be opened"): return false
	file.store_string(" \r\n" + JSON.stringify(value, "  ", true, true).replace("\n", "\r\n") + "\r\n\t")
	file.close()
	return true


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not require(xdg.begins_with("/tmp/godot-m1-v045-ignite-fixture") and OS.get_user_data_dir().begins_with(xdg + "/"), "Isolated fixture user directory required"): return
	if not require(Rules.VERSION == 27 and str(ProjectSettings.get_setting("application/config/version")) == "0.44.0", "Must run the exact released v44 pack"): return
	var arguments := OS.get_cmdline_user_args()
	if not require(arguments.size() == 1, "Provide one fixture output directory"): return
	var directory: String = arguments[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var oracle := {"gem_definitions": Journey.GEM_DEFINITIONS, "milestones": [], "minimum_save_versions": {}}
	for ordinal: int in range(1, 129):
		oracle.milestones.append(Journey.gem_definition(ordinal))
	for definition_id: String in Gems.definitions():
		oracle.minimum_save_versions[definition_id] = Gems.minimum_save_version(definition_id)
	var oracle_file := FileAccess.open(directory.path_join("v27-vocabulary-oracle.json"), FileAccess.WRITE)
	if not require(oracle_file != null, "Frozen vocabulary oracle output opens"): return
	oracle_file.store_string(JSON.stringify(oracle, "  ", true, true) + "\n")
	oracle_file.close()
	var game := Game.new()
	if not capture(directory, "v27-default.json", game.snapshot()): return
	var path := "user://build_save.json"
	if not require(game.save_build(path) == OK, "Open isolated normal profile"): return
	var rng := RandomNumberGenerator.new()
	rng.seed = 450044
	var gear_uid: String = game.award_equipment(rng, 30, "rare")
	if not require(not gear_uid.is_empty(), "Released loot API creates real equipment"): return
	if not require(game.bind_group(game.snapshot().skill_groups[0].id, KEY_F1, game.revision(), path).ok, "Released binding API changes binding"): return
	# Normal API transitions earn currency and claimed gem/flask ordinals. No direct
	# snapshot editing or current-code version decrement is used for these fixtures.
	var craft_cost: Dictionary = Game.Craft.operation_quote(game.item(gear_uid).payload, "recalibrate")
	if not require(craft_cost.ok, "Released craft economics are available"): return
	var cycles: int = ceili(float(craft_cost.cost.calibration_shard + 8) / 4.0)
	for cycle: int in range(cycles):
		var started: Dictionary = game.normal_start_map(Maps.compile_normal("old_garden", 1, [], []).profile, game.revision(), path)
		if not require(started.ok, "Start released tier1"): return
		if cycle == 0:
			for root_kill: int in range(60): game.add_normal_root_xp(1)
		if not require(game.normal_complete_map(started.run_id, game.revision(), path).ok, "Complete released tier1"): return
		if not require(game.normal_claim_rewards(game.revision(), path).ok, "Claim released rewards"): return
	var quote: Dictionary = game.crafting_quote("recalibrate", gear_uid, path)
	if not require(quote.ok, "Released craft quote is available"): return
	if not require(game.execute_crafting(quote.handle, game.item(gear_uid).payload).ok, "Released crafting changes legitimate revision"): return
	var active: Dictionary = game.normal_start_map(Maps.compile_normal("old_garden", 2, ["enemy_armour_80", "enemy_move_speed_110"], ["frost_patrol"]).profile, game.revision(), path)
	if not require(active.ok, "Start paid tier2 with canonical modifiers"): return
	# Keep one further unclaimed gem milestone, exercising pending ordinal metadata.
	for root_kill: int in range(30): game.add_normal_root_xp(1)
	if not capture(directory, "v27-active.json", game.snapshot()): return
	if not require(game.normal_complete_map(active.run_id, game.revision(), path).ok, "Complete released tier2 into pending reward"): return
	if not capture(directory, "v27-pending.json", game.snapshot()): return
	print("Frozen v44 pack exported three literal schema27 CRLF fixtures")
	quit()
