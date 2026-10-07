extends SceneTree
## Four-map bounded metadata/Plan export. Never opens a save, runs Main or combat,
## imports a historical catalog, renders PNGs or rebuilds source coverage.
const Maps = preload("res://scripts/world/map_catalog.gd")
const Compiler = preload("res://scripts/world/map_compiler.gd")
const Layout = preload("res://scripts/world/exploration_map_layout.gd")
const Plan = preload("res://scripts/world/exploration_map_plan.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const Bosses = preload("res://scripts/monsters/map_boss_profiles.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Main = preload("res://scripts/main.gd")
const OUTPUT := "res://docs/qa/v086-reference/exploration-fragment.json"
const SEED_VALUE := 861073


func clean(value: Variant) -> Variant:
	if value is Vector2: return [value.x, value.y]
	if value is Rect2: return {"position": clean(value.position), "size": clean(value.size)}
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
	assert(path.begins_with("docs/qa/v086-") and FileAccess.file_exists("res://" + path), "Missing accepted v086 evidence: " + path)
	return {"path": path, "sha256": FileAccess.get_sha256("res://" + path)}


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-v086-reference-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	assert(not FileAccess.file_exists(OUTPUT), "Never overwrite previous export evidence")
	var main_path := OS.get_environment("EXPLORATION_REFERENCE_MAIN_REPORT")
	var acceptance_evidence := evidence(main_path)
	var accepted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + main_path))
	assert(accepted.get("ok", false) and accepted.get("main_core_flow_accepted", false), "Combined Main acceptance must pass before export")
	assert(accepted.unchanged_production_proof.all_unchanged and accepted.full_run.original_result_preserved)
	assert(int(accepted.full_run.unresolved_product_failures) == 0 and int(accepted.focused_input_validation.failures) == 0)
	for source_path: String in accepted.unchanged_production_proof.files:
		assert(FileAccess.get_sha256("res://" + source_path) == accepted.unchanged_production_proof.files[source_path].first_run_sha256)
	var main_evidence := evidence(accepted.full_run.result)
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + accepted.full_run.result))
	assert(int(original.checks) == 245 and int(original.failures) == 1 and original.failed_labels == accepted.full_run.failed_labels)
	var input_evidence := evidence(accepted.focused_input_validation.result)
	var focused: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + accepted.focused_input_validation.result))
	assert(int(focused.checks) == 10 and int(focused.failures) == 0)
	var plan_path := OS.get_environment("EXPLORATION_REFERENCE_PLAN_REPORT")
	var plan_evidence := evidence(plan_path)
	var plan_inputs_evidence := evidence(plan_path.replace("-result.json", "-inputs.json"))
	var plan_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + plan_path))
	assert(int(plan_report.get("exit_code", -1)) == 0 and not bool(plan_report.get("error_logged", true)), "Plan validation must pass before export")
	assert(Model.Rules.VERSION == 50 and Source.CURRENT_SAVE_VERSION == 49 and Equipment.CURRENT_VOCABULARY == 46)
	assert(ProjectSettings.get_setting("application/config/version") == "0.86.0")
	var bounds := View.exploration_arena()
	assert(bounds == Layout.WORLD_BOUNDS and bounds.size == Vector2(3600, 2400))
	var maps := {}
	for map_id: String in Maps.MAPS:
		var tiers := []
		for tier: int in range(1, 4):
			var compiled: Dictionary = Compiler.compile_normal(map_id, tier, [], [])
			assert(compiled.ok)
			var eligible := []
			for special_id: String in Maps.SPECIAL:
				if int(Maps.SPECIAL[special_id].minimum_wave) <= int(compiled.profile.wave): eligible.append(special_id)
			var chosen := [] if eligible.is_empty() else [eligible[0]]
			var maximum: Dictionary = Compiler.compile_normal(map_id, tier, ["enemy_max_health_120", "enemy_move_speed_110"], chosen)
			assert(maximum.ok)
			tiers.append({"profile": compiled.profile, "eligible_special_ids": eligible,
				"maximum_modifier_bonus": maximum.profile.completion_reward - compiled.profile.completion_reward})
		var layout: Dictionary = Layout.layout(map_id, bounds)
		assert(layout.ok)
		var runtime := Runtime.new()
		var planned: Dictionary = Plan.plan(tiers[0].profile, runtime, SEED_VALUE, bounds)
		assert(planned.ok and planned.roots.size() == int(Maps.MAPS[map_id].ordinary_target) + 1)
		assert(planned.spawn_records.size() == planned.roots.size())
		assert(planned.mechanism_config.is_empty() and planned.optional_encounters.is_empty())
		assert(runtime.next_id == 0, "Detached export must not commit staged actors")
		var shape: Dictionary = planned.geometry.snapshot()
		assert(shape.landmarks == layout.landmarks and shape.walls == layout.walls)
		var roots := []
		for enemy: Dictionary in planned.roots:
			assert(not enemy.exploration_awake)
			roots.append({"actor_id": enemy.id, "root_id": enemy.root_id, "template_id": enemy.template_id,
				"position": enemy.pos, "radius": enemy.radius, "rarity": enemy.rarity,
				"generation": enemy.generation, "reward_eligible": enemy.reward_eligible,
				"spawn_key": enemy.map_spawn_key, "awake": enemy.exploration_awake})
		var main_entry := {}
		for observed: Dictionary in original.entries:
			if observed.map_id == map_id: main_entry = observed
		assert(not main_entry.is_empty() and main_entry.ids.size() == roots.size() and main_entry.records.size() == roots.size())
		assert(main_entry.entry == str(layout.landmarks.entry))
		maps[map_id] = {"id": map_id, "name": Maps.MAPS[map_id].name,
			"description": Layout.description(map_id), "ordinary_target": Maps.MAPS[map_id].ordinary_target,
			"tiers": tiers, "test_profile": Compiler.compile(map_id, [], []).profile,
			"actual_main_entry": {"entry": main_entry.entry, "actor_ids": main_entry.ids, "spawn_records": main_entry.records},
			"geometry": shape, "boss_definition": Bosses.definition(Maps.MAPS[map_id].boss_attack_id),
			"plan_example": {"seed": SEED_VALUE, "total": roots.size(), "roots": roots,
				"spawn_records": planned.spawn_records, "mechanism_config": planned.mechanism_config,
				"optional_encounters": planned.optional_encounters,
				"scope": "Detached I-tier empty-modifier Plan example; no Main execution, player build, save, combat or rewards."}}
	assert(maps.size() == 4)
	var result := {"game_version": ProjectSettings.get_setting("application/config/version"),
		"exploration_maps": {"maps": maps, "aggro_radius": Main.EXPLORATION_AGGRO_RADIUS,
			"entry_clearance": Layout.ENTRY_CLEARANCE,
			"save_version": Model.Rules.VERSION, "source_policy": Source.CURRENT_SAVE_VERSION,
			"equipment_vocabulary": Equipment.CURRENT_VOCABULARY,
			"plan_test": plan_evidence, "plan_test_inputs": plan_inputs_evidence, "actual_main_report": main_evidence,
			"main_acceptance": acceptance_evidence, "focused_input_report": input_evidence,
			"actual_main_checks": int(original.checks), "actual_main_original_failures": int(original.failures),
			"focused_input_checks": int(focused.checks),
			"scope": "本片段只读Main组合验收与原始结果，并导出四图实际入场记录、同源布局、原经济与独立Plan。原245项保留1项合成输入夹具失败；其余244项复用，唯一失败由10项窄补验证解决，不合计成255个独立场景。Plan示例不构成自然战斗、完整流程或平衡结论；本批资料校验不包含原生F8视觉、600秒稳定性、安装包或Release验收。",
			"sources": {"layout": "scripts/world/exploration_map_layout.gd", "plan": "scripts/world/exploration_map_plan.gd",
				"geometry": "scripts/world/map_geometry.gd", "world_view": "scripts/visuals/world_view.gd",
				"compiler": "scripts/world/map_compiler.gd", "main": "scripts/main.gd"}}}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(clean(result), "\t", true, true) + "\n")
	file.close()
	print("Exploration fragment: four layouts and detached Plans; accepted Main read only; no combat, save, PNG or full reference export")
	quit(0)
