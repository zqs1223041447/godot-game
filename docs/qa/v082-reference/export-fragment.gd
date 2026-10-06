extends SceneTree
## One bounded read-only fragment. Historical catalog bytes never enter Godot.
const Model = preload("res://scripts/canonical_game_state.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Locale = preload("res://scripts/passives/source_tree_localization.gd")
const Reference = preload("res://tools/export_reference.gd")
const Coverage = preload("res://tools/export_source_execution_coverage.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Fixture = preload("res://tests/fixtures/v082/cold_ailment_duration_fixture.gd")
const Freeze = preload("res://scripts/combat/freeze_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const ROOT := "res://docs/qa/v082-reference/"
const FIXTURES := "docs/qa/v082-gameplay/fixtures/"
const LINE := "20% increased Duration of Cold Ailments"
const STAT := "cold_ailment_duration_increased"

func write(path: String, text: String) -> void:
	assert(not FileAccess.file_exists(path), "Do not overwrite prior QA evidence")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()

func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-v082-reference-") or not OS.get_user_data_dir().begins_with(isolated + "/"): quit(78); return
	var accepted_path := OS.get_environment("COLD_REFERENCE_MAIN_REPORT")
	assert(not accepted_path.is_empty(), "Actual Main report required")
	var accepted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(accepted_path))
	assert(int(accepted.get("failures", -1)) == 0 and int(accepted.get("checks", 0)) > 0)
	assert(accepted.sections.has("compiled_and_preview") and int(accepted.sections.compiled_and_preview.failures) == 0)
	assert(Model.Rules.VERSION == 49 and Source.CURRENT_SAVE_VERSION == 49)
	assert(ProjectSettings.get_setting("application/config/version") == "0.82.0")
	var expected_path := "res://" + FIXTURES + "compiled-preview.json"
	var expected_hash := FileAccess.get_sha256(expected_path)
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	var examples := {}
	for scenario: String in ["plain-frost", "lingering-frost", "frost-lock"]:
		for stage: String in ["before", "after"]:
			var label := stage + "-" + scenario
			var path := FIXTURES + label + ".json"
			var fixture_hash := FileAccess.get_sha256("res://" + path)
			var raw := Model.Rules.decode(JSON.parse_string(FileAccess.get_file_as_string("res://" + path)))
			assert(not raw.is_empty() and int(raw.version) == 49 and Model.Rules.reason(raw).is_empty() and Source.reason(raw).is_empty())
			var route := Fixture.WITCH_ROUTE.duplicate()
			if stage == "before": route.erase(Fixture.TARGET)
			assert(raw.talents.allocated == route and int(raw.progress.level) == Fixture.LEVEL)
			assert(int(raw.talents.normal_points) == (1 if stage == "before" else 0))
			var model := Model.new()
			model._accept_memory(raw.duplicate(true))
			var group_id := str(expected[label].group_id)
			var cast := model.get_group_cast(group_id)
			assert(cast.get("ok", false) and cast.skill_id == "frost")
			assert(JSON.parse_string(JSON.stringify(cast, "", true, true)) == expected[label].cast, "Whole cast must equal actual Main: " + label)
			assert(Preview.details(cast) == expected[label].preview)
			assert(JSON.parse_string(JSON.stringify(model.get_stats(), "", true, true)) == expected[label].stats)
			assert(model.save_attempts == 0 and model.snapshot() == raw and model.pending_items().is_empty())
			assert(FileAccess.get_sha256("res://" + path) == fixture_hash)
			examples[label] = {"fixture":path,"fixture_sha256":fixture_hash,"group_id":group_id,
				"support_ids":model.skill_group(group_id).support_ids,"recipe":cast.recipe,
				"snapshot_increased":cast.snapshot.get(STAT,0.0),"freeze_profile":cast.get("freeze_profile",{}),
				"mana":cast.mana,"cooldown":cast.cooldown,"initial_count":cast.initial_count,
				"preview":Preview.details(cast),"summary":Preview.summary(cast),
				"whole_build_valid":true,"whole_cast_matches_main":true,"read_only_rebuilt":true,"save_attempts":model.save_attempts}
	assert(FileAccess.get_sha256(expected_path) == expected_hash)
	var mechanisms := {}
	for id: String in Reference.SourceMonster.IDS: mechanisms[id] = Reference.mechanism_reference(id)
	var raw_node: Dictionary = Source.Data.node(Fixture.TARGET)
	assert(raw_node.stats == [LINE] and Source.node_effect(Fixture.TARGET).status == "full")
	var rule := {"minimum_save_version":Model.Rules.VERSION,"source_policy":Source.CURRENT_SAVE_VERSION,
		"equipment_vocabulary":Equipment.CURRENT_VOCABULARY,"source_line":LINE,"increased":0.20,
		"level":Fixture.LEVEL,"point_budget":Fixture.BUDGET,"route":Fixture.WITCH_ROUTE,
		"fixture_helper":"tests/fixtures/v082/cold_ailment_duration_fixture.gd",
		"fixture_helper_sha256":FileAccess.get_sha256("res://tests/fixtures/v082/cold_ailment_duration_fixture.gd"),
		"actual_main_report":accepted_path.trim_prefix("res://"),"actual_main_report_sha256":FileAccess.get_sha256(accepted_path),
		"compiled_fixture":FIXTURES + "compiled-preview.json","compiled_fixture_sha256":expected_hash,
		"max_targets":Freeze.MAX_TARGETS,"examples":examples}
	var result := {"game_version":ProjectSettings.get_setting("application/config/version"),
		"save_version":Model.Rules.VERSION,"source_policy":Source.CURRENT_SAVE_VERSION,
		"nodes":{Fixture.TARGET:{"execution":Source.node_effect(Fixture.TARGET)}},
		"localized_nodes":{Fixture.TARGET:{"stats":Locale.display_lines(raw_node.stats)}},
		"localized_lines":{LINE:{"text":Locale.display_lines([LINE]),"status":Locale.line_status(LINE)}},
		"mechanisms":mechanisms,"cold_ailment_duration":rule}
	var coverage := Coverage.build_report()
	assert(not coverage.is_empty() and coverage.integrity.ok)
	write(ROOT + "cold-duration-fragment.json", JSON.stringify(result, "\t", true, true) + "\n")
	write(ROOT + "source-tree-coverage.json", Coverage.serialize_report(coverage))
	print("Cold duration fragment: 6 exact Main casts, 1 source node, 5 current source metadata definitions")
	quit(0)
