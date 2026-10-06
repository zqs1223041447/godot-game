extends SceneTree
## One frozen released implementation is loaded once, then reused across this
## bounded profile/seed batch. Only an allowed final template substitution may
## differ; every other serialized roster/checkpoint byte must remain identical.
const State = preload("res://scripts/world/map_camp_state.gd")
const Rules = preload("res://scripts/world/mist_skitter_roster_rules.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const Admission = preload("res://scripts/world/map_camp_admission.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const ORACLE_PATH = "res://docs/qa/v071-mist-skitter/roster/map_camp_state_4166822.gd.txt"
const ORACLE_SHA256 = "6abe4a2320425bbcffb421d0b993573242a4fb877434f51d37b99ef2ffc5e11d"
const BOUNDS := Rect2(Vector2(42, 104), Vector2(1840, 712))
const SEEDS: Array[int] = [0, 1, 2, 3, 5, 8, 13, 17, 31, 43, 71, 127, 65535, -1, -71, -1701]
var Reference: GDScript
var checks := 0
var failures := 0
var profile_count := 0
var cases := 0
var roots := 0
var replacements := 0
var no_candidate_camps := 0
var later_candidate_camps := 0
var exact_legacy_cases := 0
var planned_roots := 0
var preserved_templates: Dictionary = {}
var examples: Array[Dictionary] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _initialize() -> void:
	check(FileAccess.get_sha256(ORACLE_PATH) == ORACLE_SHA256, "Oracle is exact 4166822 MapCampState source bytes")
	Reference = GDScript.new()
	Reference.source_code = FileAccess.get_file_as_string(ORACLE_PATH).replace("class_name MapCampState\n", "")
	if Reference.reload() != OK:
		quit(1)
		return
	seed(710071)
	var expected_global := randi()
	seed(710071)
	var caller_rng := RandomNumberGenerator.new()
	caller_rng.seed = 434371
	var caller_state := caller_rng.state
	_test_rules()
	_test_profiles()
	_test_formations()
	_test_rejections()
	check(randi() == expected_global, "Helpers and complete batch consume no global RNG")
	check(caller_rng.state == caller_state, "Independent caller RNG state is untouched")
	check(profile_count == 74 and cases == 1184 and roots == 38400 and planned_roots == 288, "Every bounded profile/seed comparison and real formation case completes")
	check(replacements > 0 and no_candidate_camps > 0 and later_candidate_camps > 0, "Batch contains substitutions, absent candidates and skipped earlier non-normal skitters")
	for template_id: String in ["skitter", "splitter", "brood_host", "ember_guard", "frost_guard", "storm_skitter"]:
		check(preserved_templates.has(template_id), "Natural batch preserves nonselected " + template_id)
	var report := {"checks": checks, "failures": failures, "profiles": profile_count,
		"cases": cases, "roots": roots, "replacements": replacements,
		"exact_legacy_cases": exact_legacy_cases, "no_candidate_camps": no_candidate_camps,
		"planned_roots": planned_roots,
		"later_candidate_camps": later_candidate_camps, "examples": examples,
		"baseline_commit": "4166822ff7a487bb498c7086b20e2823e4e71edb", "baseline_sha256": ORACLE_SHA256,
		"scope": "Final camp-root rosters and lifecycle state only; actual actor/reward execution is covered separately."}
	var report_path := OS.get_environment("MIST_ROSTER_REPORT")
	if not report_path.is_empty():
		FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true) + "\n")
	print("MIST_SKITTER_ROSTER_COMPLETE ", JSON.stringify(report))
	quit(1 if failures else 0)


func _test_rules() -> void:
	var entries: Array[Dictionary] = [
		{"template_id": "skitter", "rarity": "magic"},
		{"template_id": "storm_skitter", "rarity": "normal"},
		{"template_id": "skitter", "rarity": "rare"},
		{"template_id": "skitter", "rarity": "normal", "mechanisms": []},
		{"template_id": "skitter", "rarity": "normal", "mechanisms": []}]
	for tier: int in [2, 3]:
		var profile: Dictionary = Maps.compile_normal("sunwell_terrace", tier, [], []).profile
		var profile_before := var_to_bytes(profile)
		var entries_before := var_to_bytes(entries)
		check(Rules.eligible_profile(profile) and Rules.replacement_index(profile, entries) == 3, "Only the first final normal skitter is selected")
		check(var_to_bytes(entries) == entries_before and var_to_bytes(profile) == profile_before, "Pure selection leaves both inputs byte-identical")
		for rarity: String in ["", "magic", "rare", "boss", "reserved"]:
			var denied: Array[Dictionary] = [{"template_id": "skitter", "rarity": rarity}]
			check(Rules.replacement_index(profile, denied) == -1, "Non-normal rarity cannot become mist")
		for template_id: String in ["crawler", "brute", "splitter", "brood_host", "ember_guard", "frost_guard", "storm_skitter", "rift_warden", "mist_skitter"]:
			var denied: Array[Dictionary] = [{"template_id": template_id, "rarity": "normal"}]
			check(Rules.replacement_index(profile, denied) == -1, "Other templates cannot become mist")
		check(Rules.replacement_index(profile, []) == -1, "Empty camp has no fallback candidate")
		for key: String in ["normal_map", "journey_tier", "wave"]:
			var changed := profile.duplicate(true)
			changed.erase(key)
			check(not Rules.eligible_profile(changed), "Missing eligibility field fails closed")
		for bad_tier: Variant in [true, 2.0, 3.0, "2", 0, 1, 4]:
			var changed := profile.duplicate(true)
			changed.journey_tier = bad_tier
			check(not Rules.eligible_profile(changed), "Only exact integer tiers II/III qualify")
		for bad_wave: Variant in [true, float(profile.wave), str(profile.wave), 3, 5, 9, 11]:
			var changed := profile.duplicate(true)
			changed.wave = bad_wave
			check(not Rules.eligible_profile(changed), "Only the tier's exact integer wave qualifies")
		var wrong_pair := profile.duplicate(true)
		wrong_pair.wave = 10 if tier == 2 else 6
		check(not Rules.eligible_profile(wrong_pair), "Valid waves cannot be swapped between tiers")
		for bad_flag: Variant in [false, 0, 1, "true"]:
			var changed := profile.duplicate(true)
			changed.normal_map = bad_flag
			check(not Rules.eligible_profile(changed), "Normal-map provenance requires true bool")
	for map_id: String in ["old_garden", "broken_ruins", "sunwell_terrace"]:
		var fixed: Dictionary = Maps.compile(map_id, [], []).profile
		check(not Rules.eligible_profile(fixed) and Rules.replacement_index(fixed, entries) == -1, "Every fixed test profile stays unchanged, including Sunwell wave six")
		for tier: int in [1, 2, 3]:
			var profile: Dictionary = Maps.compile_normal(map_id, tier, [], []).profile
			var expected := map_id == "sunwell_terrace" and tier in [2, 3]
			check(Rules.eligible_profile(profile) == expected, "Actual compiler provenance precisely gates normal Sunwell II/III")


func _test_profiles() -> void:
	for map_id: String in ["old_garden", "broken_ruins", "sunwell_terrace"]:
		var layout := Layout.layout(map_id, BOUNDS)
		check(layout.ok, "Batch uses real map geometry and positions")
		for tier: int in [0, 1, 2, 3]:
			for normal: Array in [[], ["enemy_max_health_120", "enemy_shield_from_health_20"]]:
				for special: Array in [[], ["elemental_aegis"], ["frost_patrol"], ["storm_patrol"]]:
					var compiled := Maps.compile(map_id, normal, special) if tier == 0 else Maps.compile_normal(map_id, tier, normal, special)
					if not compiled.ok:
						continue
					profile_count += 1
					for seed_value: int in SEEDS:
						_compare(compiled.profile, layout.landmarks, seed_value, map_id == "sunwell_terrace" and tier in [2, 3])


func _compare(profile: Dictionary, landmarks: Dictionary, seed_value: int, eligible: bool) -> void:
	var old: RefCounted = Reference.new()
	var current := State.new()
	var input_before := var_to_bytes([profile, landmarks])
	check(old.begin(profile, landmarks, seed_value).ok and current.begin(profile, landmarks, seed_value).ok, "Both published and current generators accept the same actual profile/seed/landmarks")
	check(var_to_bytes([profile, landmarks]) == input_before, "Generation does not mutate shared profile/landmark inputs")
	var expected: Dictionary = old.checkpoint()
	var case_replacements := 0
	var selected_admissions: Array[int] = []
	for camp: Dictionary in expected.camps:
		var first := -1
		var earlier_non_normal := false
		if eligible:
			for index: int in range(camp.entries.size()):
				var entry: Dictionary = camp.entries[index]
				if entry.template_id == "skitter" and entry.rarity == "normal":
					first = index
					break
				if entry.template_id == "skitter":
					earlier_non_normal = true
		if first >= 0:
			camp.entries[first].template_id = "mist_skitter"
			selected_admissions.append(camp.entries[first].admission_index)
			case_replacements += 1
			if earlier_non_normal:
				later_candidate_camps += 1
		elif eligible:
			no_candidate_camps += 1
		var actual_entries := current.entries(camp.id)
		var old_entries: Array[Dictionary] = old.entries(camp.id)
		var mist_count := 0
		for index: int in range(actual_entries.size()):
			var actual: Dictionary = actual_entries[index]
			var original: Dictionary = old_entries[index]
			if actual.template_id == "mist_skitter":
				mist_count += 1
				check(eligible and index == first and original.template_id == "skitter" and original.rarity == "normal", "Only the first final normal root skitter changes")
			else:
				check(var_to_bytes(actual) == var_to_bytes(original), "Every other root keeps exact template, rarity, mechanisms, position and admission index")
				preserved_templates[original.template_id] = true
			roots += 1
		check(mist_count == (1 if first >= 0 else 0) and actual_entries.size() == camp.entries.size(), "At most one replacement per camp, zero if absent, with unchanged root count")
	check(case_replacements <= 3 and (profile.ordinary_target == 36 or case_replacements == 0), "At most three of thirty-six roots change")
	check(var_to_bytes(current.checkpoint()) == var_to_bytes(expected), "Entire checkpoint is byte-identical to the released oracle plus only explicit permitted template replacements")
	if not eligible or case_replacements == 0:
		check(var_to_bytes(current.checkpoint()) == var_to_bytes(old.checkpoint()), "Ineligible and candidate-free maps are exact released checkpoint bytes")
		exact_legacy_cases += 1
	if profile.special_ids.has("storm_patrol"):
		check(case_replacements == 0, "Final storm-patrol precedence leaves no normal skitter candidate")
	check(var_to_bytes(current.states({})) == var_to_bytes(old.states({})), "Camp activation/root ownership state is unchanged")
	if seed_value == 43:
		var reordered := landmarks.duplicate(true)
		reordered.camps.reverse()
		var repeat := State.new()
		check(repeat.begin(profile, reordered, seed_value).ok, "Reordered landmark fixture remains valid")
		for camp_id: String in State.CAMP_IDS:
			check(var_to_bytes(repeat.entries(camp_id)) == var_to_bytes(current.entries(camp_id)), "Same seed and canonical camp order produce the identical new roster")
	if eligible and profile.normal_ids.is_empty() and profile.special_ids.is_empty() and seed_value in [0, 43, -71]:
		examples.append({"tier": profile.journey_tier, "seed": seed_value, "mist_admission_indices": selected_admissions})
	replacements += case_replacements
	cases += 1


func _test_formations() -> void:
	var landmarks: Dictionary = Layout.layout("sunwell_terrace", BOUNDS).landmarks
	for tier: int in [2, 3]:
		for special: Array in [[], ["elemental_aegis"], ["frost_patrol"], ["storm_patrol"]]:
			var profile: Dictionary = Maps.compile_normal("sunwell_terrace", tier, ["enemy_max_health_120", "enemy_shield_from_health_20"], special).profile
			var state := State.new()
			var geometry := Geometry.new()
			check(state.begin(profile, landmarks, 43).ok and geometry.configure(profile.id, BOUNDS), "Eligible formation uses original map geometry")
			var geometry_before := var_to_bytes(geometry.snapshot())
			check(geometry.snapshot().walls.size() == 4, "All four original solid spring basins remain")
			var runtime := Runtime.new()
			for camp_id: String in State.CAMP_IDS:
				var entries := state.entries(camp_id)
				var group := Admission.plan(runtime, profile, entries, geometry, landmarks.entry, 100)
				check(group.ok and group.enemies.size() == 12, "All twelve actual bodies fit each original camp without moving slots")
				if not group.ok:
					continue
				var ids: Array[int] = []
				for index: int in range(group.enemies.size()):
					var enemy: Dictionary = group.enemies[index]
					check(enemy.pos == entries[index].position and geometry.is_clear(enemy.pos, enemy.radius), "Actual root radius is clear at its original frozen position")
					check(enemy.generation == 0 and enemy.root_id == enemy.id and enemy.reward_eligible, "Admission retains original root and reward eligibility")
					ids.append(enemy.id)
					planned_roots += 1
				Encounter._restore(runtime, group.runtime_checkpoint)
				check(state.activate(camp_id, ids), "Whole real camp keeps unique root membership")
			check(runtime.roots.size() == 36 and runtime.next_id == 36, "Exactly thirty-six canonical root identities are admitted")
			check(var_to_bytes(geometry.snapshot()) == geometry_before, "Full camp planning never changes terrain")


func _test_rejections() -> void:
	var profile: Dictionary = Maps.compile_normal("sunwell_terrace", 2, [], []).profile
	var landmarks: Dictionary = Layout.layout(profile.id, BOUNDS).landmarks
	var state := State.new()
	check(state.begin(profile, landmarks, 71).ok, "Rejection fixture begins with an eligible map")
	var before := var_to_bytes(state.checkpoint())
	for bad_seed: Variant in [null, false, 71.0, "71", {}, []]:
		check(not state.begin(profile, landmarks, bad_seed).ok and var_to_bytes(state.checkpoint()) == before, "Rejected seed does not publish a partial selection or mutate existing roster")
	for key: String in ["normal_map", "journey_tier", "wave"]:
		var changed := profile.duplicate(true)
		changed.erase(key)
		check(not state.begin(changed, landmarks, 71).ok and var_to_bytes(state.checkpoint()) == before, "Noncanonical eligibility metadata rejects atomically at the existing compiler boundary")
