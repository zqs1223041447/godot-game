extends SceneTree
## One current monster/telegraph snapshot. No Main instance, save, player build,
## damage settlement, map regeneration, RNG, PNGs or full-catalog export.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Telegraph = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Chill = preload("res://scripts/combat/chill_rules.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const OUTPUT := "res://docs/qa/v087-reference/frost-chill-fragment.json"


func clean(value: Variant) -> Variant:
	if value is Vector2: return [value.x, value.y]
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[str(key)] = clean(value[key])
		return result
	if value is Array:
		var result := []
		for item: Variant in value: result.append(clean(item))
		return result
	return value


func evidence(path: String) -> Dictionary:
	assert((path.begins_with("docs/qa/v087-gameplay/") or path.begins_with("docs/qa/v087-integration/")) and FileAccess.file_exists("res://" + path), "Missing accepted v087 Main evidence: " + path)
	return {"path": path, "sha256": FileAccess.get_sha256("res://" + path)}


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-v087-reference-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	assert(not FileAccess.file_exists(OUTPUT), "Never overwrite previous export evidence")
	var main_evidence := evidence(OS.get_environment("CHILL_REFERENCE_MAIN_REPORT"))
	var main_run_evidence := evidence(OS.get_environment("CHILL_REFERENCE_MAIN_RUN"))
	var main_inputs_evidence := evidence(OS.get_environment("CHILL_REFERENCE_MAIN_INPUTS"))
	var accepted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + main_evidence.path))
	var run: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + main_run_evidence.path))
	assert(int(accepted.get("checks", 0)) > 0 and int(accepted.get("failures", -1)) == 0, "Actual Main report must pass before export")
	assert(int(run.get("exit_code", -1)) == 0 and run.get("error_logged", true) == false and run.get("timed_out", true) == false, "Actual Main runner must exit cleanly")
	var inputs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + main_inputs_evidence.path))
	for path: String in inputs:
		assert(FileAccess.get_sha256("res://" + path) == inputs[path], "Main evidence source changed: " + path)
	assert(Model.Rules.VERSION == 50 and Source.CURRENT_SAVE_VERSION == 49 and Equipment.CURRENT_VOCABULARY == 46)
	assert(ProjectSettings.get_setting("application/config/version") == "0.87.0")
	var enemy: Dictionary = Monsters.make_enemy(1, "frost_guard", 4, Vector2(100, 0))
	assert(not enemy.is_empty())
	# Pure runtime preparation: leave birth protection only for this detached
	# catalog actor so the scheduler may return its authored attack snapshot.
	enemy.spawn = 0.0
	var policy: Dictionary = Monsters.telegraph_policy(enemy)
	assert(policy.chill_policy == Chill.ENEMY_POLICY)
	var runtime := Telegraph.new()
	var started: Dictionary = runtime.start(enemy, Vector2.ZERO, policy.profile)
	assert(started.ok)
	var events: Array[Dictionary] = runtime.advance(float(policy.profile.windup_seconds), [enemy], true)
	assert(events.size() == 1 and events[0].chill_policy == Chill.ENEMY_POLICY)
	assert(events[0].packet.base == started.attack.packet.base)
	var result := {"game_version": ProjectSettings.get_setting("application/config/version"),
		"frost_guard_chill": {"policy": Chill.ENEMY_POLICY.duplicate(true),
			"base_profile": Monsters.TelegraphProfiles.ELEMENTAL.frost_guard.duplicate(true),
			"telegraph_policy": policy, "source": enemy, "start": started.attack,
			"event": events[0], "recovery": runtime.state_for(int(enemy.id)),
			"save_version": Model.Rules.VERSION, "source_policy": Source.CURRENT_SAVE_VERSION,
			"equipment_vocabulary": Equipment.CURRENT_VOCABULARY,
			"actual_main_report": main_evidence, "actual_main_run": main_run_evidence,
			"actual_main_inputs": main_inputs_evidence, "actual_main_checks": int(accepted.checks),
			"scope": "Detached MonsterCatalog and Telegraph runtime snapshot only. The existing damage examples and four-map data remain exact historical bytes. Actual Main evidence is read only; no Main, player build, damage settlement or map regeneration runs here.",
			"sources": {"catalog": "scripts/monsters/monster_catalog.gd", "profiles": "scripts/monsters/telegraph_profiles.gd",
				"telegraph": "scripts/combat/telegraphed_area_runtime.gd", "rules": "scripts/combat/chill_rules.gd",
				"runtime": "scripts/combat/player_chill_runtime.gd", "main": "scripts/main.gd"}}}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(clean(result), "\t", true, true) + "\n")
	file.close()
	print("Frost chill fragment: one current monster/telegraph snapshot; accepted Main read only; no player, combat, save, maps, PNG or full export")
	quit(0)
