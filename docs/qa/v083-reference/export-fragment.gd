extends SceneTree
## Bounded new-map fragment only. No old catalog or source coverage enters Godot.
const Maps = preload("res://scripts/world/map_catalog.gd")
const Compiler = preload("res://scripts/world/map_compiler.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const Roster = preload("res://scripts/world/map_camp_state.gd")
const Ginkgo = preload("res://scripts/world/ginkgo_roster_rules.gd")
const Admission = preload("res://scripts/world/map_camp_admission.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Bosses = preload("res://scripts/monsters/map_boss_profiles.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Fixture = preload("res://tests/fixtures/v083/ginkgo_journey_fixture.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const ROOT := "res://docs/qa/v083-reference/"
const MAP_ID := "ginkgo_arcade"
const MAIN_ROOT := "docs/qa/v083-gameplay/results/"

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

func json_value(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func evidence(path: String) -> Dictionary:
	assert(FileAccess.file_exists("res://" + path), "Missing accepted evidence: " + path)
	return {"path": path, "sha256": FileAccess.get_sha256("res://" + path)}

func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-v083-reference-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	var accepted_path := OS.get_environment("GINKGO_REFERENCE_MAIN_REPORT")
	assert(accepted_path == "res://" + MAIN_ROOT + "main-result.json")
	var accepted_text := FileAccess.get_file_as_string(accepted_path)
	var accepted: Dictionary = JSON.parse_string(accepted_text)
	assert(int(accepted.get("checks", 0)) > 0 and int(accepted.get("failures", -1)) == 0)
	assert(accepted.runs.size() == 2 and accepted.attacks.has_all(["1", "2", "freeze"]))
	# JSON parsing converts large 64-bit seeds to floats. Recover each original
	# integer literal directly so the runtime replay uses the exact Main RNG seed.
	var seed_pattern := RegEx.new()
	assert(seed_pattern.compile('"seed":\\s*(-?[0-9]+)') == OK)
	var seed_literals := seed_pattern.search_all(accepted_text)
	assert(seed_literals.size() == accepted.runs.size())
	assert(Model.Rules.VERSION == 50 and Source.CURRENT_SAVE_VERSION == 49 and Equipment.CURRENT_VOCABULARY == 46)
	assert(ProjectSettings.get_setting("application/config/version") == "0.83.0")
	var geometry := Geometry.new()
	assert(geometry.configure(MAP_ID, View.WORLD_ARENA))
	var layout: Dictionary = Layout.layout(MAP_ID, View.WORLD_ARENA)
	assert(layout.ok)
	var landmarks: Dictionary = layout.landmarks
	var shape: Dictionary = geometry.snapshot()
	shape.landmarks = landmarks
	var definition: Dictionary = Maps.MAPS[MAP_ID].duplicate(true)
	definition.id = MAP_ID
	var tiers := []
	var roster_examples := {}
	for tier: int in range(1, 4):
		var model := Model.new()
		# The real journey guard requires this exact logical path. XDG isolation
		# above separates it from any user save; the shared helper resets native49.
		var prepared: Dictionary = Fixture.prepare(model, "user://build_save.json", tier, false)
		assert(prepared.ok, "Shared helper: " + JSON.stringify(prepared))
		assert(Model.Rules.reason(model.snapshot()).is_empty(), "Whole helper model: " + Model.Rules.reason(model.snapshot()))
		assert(int(model.normal_journey().best_tiers[MAP_ID]) == tier - 1)
		var base: Dictionary = Compiler.compile_normal(MAP_ID, tier, [], []).profile
		assert(prepared.profile == base)
		var special_ids := []
		for id: String in Maps.SPECIAL:
			if int(Maps.SPECIAL[id].minimum_wave) <= int(base.wave): special_ids.append(id)
		var chosen := [] if special_ids.is_empty() else [special_ids[0]]
		var maximum: Dictionary = Compiler.compile_normal(MAP_ID, tier, ["enemy_max_health_120", "enemy_move_speed_110"], chosen)
		assert(maximum.ok)
		tiers.append({"base": base, "maximum_bonus_example": maximum.profile,
			"eligible_special_ids": special_ids, "legal_precondition": {"schema": model.snapshot().version,
				"best_completed": model.normal_journey().best_tiers[MAP_ID], "balance": model.crafting_balance(),
				"whole_model_valid": true, "helper_profile_matches": true}})
		var examples := {}
		for camp: Dictionary in landmarks.camps:
			var entries := []
			for ordinal: int in range(1, int(camp.root_count) + 1):
				entries.append(Ginkgo.template_for_roll(int(base.wave), camp.id, ordinal,
					{"template": "crawler", "rarity": "normal", "mechanisms": []}))
			examples[camp.id] = entries
		roster_examples[str(base.wave)] = examples
	var main_examples := []
	for index: int in range(accepted.runs.size()):
		var run: Dictionary = accepted.runs[index]
		var tier := int(run.tier)
		var profile: Dictionary = Compiler.compile_normal(MAP_ID, tier, run.profile.normal_ids, run.profile.special_ids).profile
		assert(json_value(profile) == run.profile, "Compiled profile must match accepted Main")
		var roster := Roster.new()
		var seed_value := int(seed_literals[index].get_string(1))
		assert(roster.begin(profile, landmarks, seed_value, Monsters.CURRENT_ROLL_POLICY).ok)
		assert(json_value(roster.checkpoint()) == run.roster, "Full current roster must match actual Main")
		var actual: Dictionary = accepted.attacks[str(tier)]
		var attack: Dictionary = actual.attack
		assert(attack.center == str(landmarks.boss.center) and attack.visual_pattern == definition.boss_attack_id)
		assert(not attack.has("pulse_count"))
		# JSON numbers have no int type. Restore only identity types required by the
		# authoritative boss policy, leaving all supplied numeric values unchanged.
		var boss: Dictionary = actual.boss.duplicate(true)
		for key: String in ["id", "root_id", "generation"]: boss[key] = int(boss[key])
		var policy: Dictionary = Monsters.telegraph_policy(boss)
		assert(not policy.is_empty() and json_value(policy.profile) == attack.profile)
		var model_path := MAIN_ROOT + "formal-tier%d.json" % tier
		var raw: Dictionary = Model.Rules.decode(JSON.parse_string(FileAccess.get_file_as_string("res://" + model_path)))
		assert(not raw.is_empty() and Model.Rules.reason(raw).is_empty() and int(raw.version) == 50)
		assert(int(raw.journey.best_tiers[MAP_ID]) == tier)
		main_examples.append({"tier": tier, "profile": profile, "roster": roster.checkpoint(),
			"source_attack_speed": boss.attack_speed, "policy": policy, "attack_profile": attack.profile,
			"locked_center": landmarks.boss.center, "packet": attack.packet,
			"roots_rewarded": run.roots, "coexisting_roots": run.coexisting_roots,
			"boss_children": run.boss_children, "pending": run.pending, "claim": run.claim,
			"model": evidence(model_path), "whole_model_valid": true,
			"whole_profile_matches_main": true, "whole_roster_matches_main": true})
	var prototype: Dictionary = Monsters.make_enemy(1, "crawler", int(tiers[0].base.wave), landmarks.entry, "ordinary")
	var freeze: Dictionary = accepted.attacks.freeze.state
	var result := {"game_version": ProjectSettings.get_setting("application/config/version"), "save_version": Model.Rules.VERSION,
		"ginkgo_arcade": {"definition": definition, "save_version": Model.Rules.VERSION,
			"source_policy": Source.CURRENT_SAVE_VERSION, "equipment_vocabulary": Equipment.CURRENT_VOCABULARY,
			"test_profile": Compiler.compile(MAP_ID, [], []).profile,
			"tiers": tiers, "geometry": shape, "patterns": Ginkgo.PATTERNS,
			"roster_examples_by_wave": roster_examples,
			"elemental_gates": {"frost_guard": Monsters.ELEMENTAL_ENCOUNTERS.frost_guard,
				"storm_skitter": Monsters.ELEMENTAL_ENCOUNTERS.storm_skitter},
			"player_clearance": Admission.PLAYER_CLEARANCE, "spawn_seconds": prototype.spawn,
			"boss_definition": Bosses.definition(definition.boss_attack_id),
			"fixture_helper": evidence("tests/fixtures/v083/ginkgo_journey_fixture.gd"),
			"native49_fixture": evidence(Fixture.NATIVE49.trim_prefix("res://")),
			"actual_main_report": evidence(accepted_path.trim_prefix("res://")),
			"actual_main_checks": accepted.checks, "actual_main_examples": main_examples,
			"freeze_source": evidence(MAIN_ROOT + "freeze-source.json"),
			"freeze_cast": evidence(MAIN_ROOT + "freeze-cast.json"),
			"actual_freeze_seconds": float(freeze.frozen_until) - float(freeze.frozen_from),
			"scope": "三档使用共用合法49夹具与真实迁移/解锁/领奖事务；I/II编译及整组编排逐项匹配已通过的Main证据。资料导出不重跑战斗，不构成新的玩法或平衡通过。"}}
	var path := ROOT + "ginkgo-fragment.json"
	assert(not FileAccess.file_exists(path), "Do not overwrite earlier evidence")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(clean(result), "\t", true, true) + "\n")
	file.close()
	print("Ginkgo fragment: 3 legal helper tiers, 2 exact Main profiles/rosters, shared geometry and boss policy; no full catalog or coverage export")
	quit(0)
