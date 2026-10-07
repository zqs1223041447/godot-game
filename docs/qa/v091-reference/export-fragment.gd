extends SceneTree
## Read accepted isolated Main output; export one detached game-data fragment.
## Does not instantiate Main, spend currency, write saves, roll drops or export the full catalog.
const Model = preload("res://scripts/canonical_game_state.gd")
const Reference = preload("res://tools/jewel_crafting_reference.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const FIXTURE := "res://docs/qa/v091-root-ui/main-after-reforge.json"
const UI_LOG := "res://docs/qa/v091-root-ui/ui.log"
const OUTPUT := "res://docs/qa/v091-reference/jewel-crafting-fragment.json"
func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v091-reference-") or not OS.get_user_data_dir().begins_with(isolated + "/"): quit(78); return
	var log := FileAccess.get_file_as_string(UI_LOG)
	assert(log.contains("Jewel crafting UI: 15 checks, 0 failures") and not log.contains("ERROR:"))
	assert(FileAccess.get_file_as_string("res://docs/qa/v091-root-ui/exit-code.txt").strip_edges() == "0")
	var fixture_hash := FileAccess.get_sha256(FIXTURE)
	var build := Model.Rules.decode(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))
	assert(not build.is_empty() and Model.Rules.reason(build).is_empty() and build.version == 50)
	var model := Model.new()
	model._accept_memory(build.duplicate(true))
	assert(model.crafting_balance() == 56 and build.crafting.revision == 1)
	var after: Dictionary = model.item("jewel_000004").payload
	assert(Jewels.validate_instance(after, false) and after.base == "emberheart" and after.rarity == "magic")
	var before: Dictionary = Jewels.starter_jewels()["jewel_000001"]
	before.id = after.id
	var seed_text := JSON.stringify({"rules": Model.JewelCraft.RULES_VERSION + ":reforge", "revision": 0, "item": before}, "", true, true)
	var expected := Model.JewelCraft.operation_plan(before, "reforge", seed_text.sha256_text().substr(0, 15).hex_to_int())
	assert(expected.ok and after == expected.instance)
	var fragment := Reference.build_snapshot()
	fragment["actual_main_example"] = {"source": before, "result": after,
		"name": Jewels.display_name(after), "description": Jewels.get_description(after),
		"balance_before": 64, "balance_after": model.crafting_balance(), "cost": 8,
		"fixture": FIXTURE.trim_prefix("res://"), "fixture_sha256": fixture_hash,
		"ui_log": UI_LOG.trim_prefix("res://"), "ui_log_sha256": FileAccess.get_sha256(UI_LOG),
		"scope": "Isolated test game data from the accepted actual Main UI run; never a user's normal save",
		"whole_build_valid": true, "exact_main_result_verified": true}
	assert(model.save_attempts == 0 and model.snapshot() == build and FileAccess.get_sha256(FIXTURE) == fixture_hash)
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"jewel_crafting": fragment}, "\t", true, true) + "\n")
	file.close()
	print("Jewel crafting fragment: existing rules and one validated actual Main test save; no Main rerun or full export")
	quit(0)
