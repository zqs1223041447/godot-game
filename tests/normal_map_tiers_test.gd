extends SceneTree
const Maps = preload("res://scripts/world/map_compiler.gd")
const Catalog = preload("res://scripts/world/normal_map_catalog.gd")
const Encounters = preload("res://scripts/encounters/encounter_catalog.gd")
const LEGACY_FIXTURE = "res://docs/qa/v041/map-tiers-v040-profiles.bin"
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func selections() -> Array:
	var choices: Array = [[]]
	var ids: Array[String] = Encounters.get_ids()
	for id: String in ids:
		choices.append([id])
	for first: int in range(ids.size()):
		for second: int in range(first + 1, ids.size()):
			choices.append([ids[first], ids[second]])
	return choices


func _initialize() -> void:
	seed(41041)
	var expected_next := randi()
	seed(41041)
	_test_catalog()
	_test_all_choices()
	_test_rejections()
	_test_canonical_validation()
	_test_independence()
	_test_legacy_bytes()
	check(randi() == expected_next, "All valid and rejected compilation/catalog operations preserve global RNG")
	print("Normal map tiers: %d checks, %d failures; 374 legal normal choices; 176 legacy results byte-identical" % [checks, failures])
	quit(1 if failures else 0)


func _test_catalog() -> void:
	var waves := {"old_garden": [1, 4, 8], "broken_ruins": [2, 5, 9]}
	for map_id: String in waves:
		for tier: int in range(1, 4):
			var definition := Catalog.definition(map_id, tier)
			check(definition.map_id == map_id and definition.tier == tier, "Catalog preserves map ID and integer tier")
			check(definition.wave == waves[map_id][tier - 1], "Catalog uses approved actual wave")
			check(definition.ordinary_target == (24 if map_id == "old_garden" else 36), "Catalog retains ordinary target")
			check(definition.cost == (tier - 1) * 4 and definition.base_reward == tier * 4, "Tier fee and base completion reward")
			check(definition.cost is int and definition.base_reward is int and definition.wave is int, "Catalog quantities are genuine integers")
			check(definition.label.contains(Maps.Catalog.MAPS[map_id].name), "Tier label retains map name")
		for best: int in range(4):
			var rows := Catalog.tiers(map_id, best)
			check(rows.size() == 3, "Every map exposes exactly three tier rows")
			for index: int in range(rows.size()):
				var row: Dictionary = rows[index]
				check(row.has_all(["map_id", "tier", "label", "wave", "ordinary_target", "cost", "base_reward", "unlocked", "reason"]), "UI row carries the complete catalog contract")
				check(row.unlocked is bool and row.reason is String, "UI lock metadata has canonical types")
				check(row.unlocked == (index <= best), "Only own best completed tier unlocks the next tier")
				check(row.reason.is_empty() == row.unlocked, "Locked tiers explain their prerequisite")
	check(Catalog.tiers("old_garden", 0)[0].unlocked and Catalog.tiers("broken_ruins", 0)[0].unlocked, "Both map tier I choices start unlocked")
	check(Catalog.tiers("old_garden", 2)[2].unlocked and not Catalog.tiers("broken_ruins", 0)[1].unlocked, "Map progress is independent")
	check(Catalog.tiers("missing", 3).is_empty(), "Unknown map has no UI tier rows")


func _test_all_choices() -> void:
	var choices := selections()
	check(choices.size() == 22, "Exactly 22 legal ordinary modifier selections")
	var legal := 0
	var per_pair: Dictionary = {}
	for map_id: String in ["old_garden", "broken_ruins"]:
		for tier: int in range(1, 4):
			var definition := Catalog.definition(map_id, tier)
			var pair_count := 0
			for normal: Array in choices:
				for special: Array in [[], ["elemental_aegis"], ["frost_patrol"], ["storm_patrol"]]:
					var expected: bool = special.is_empty() or definition.wave >= Maps.Catalog.SPECIAL[special[0]].minimum_wave
					var compiled := Maps.compile_normal(map_id, tier, normal, special)
					check(compiled.ok == expected, "Special gate uses the actual tier wave")
					if not expected:
						check(compiled.code == "invalid_map" and not compiled.has("profile"), "Rejected gate exposes no profile")
						continue
					legal += 1
					pair_count += 1
					var profile: Dictionary = compiled.profile
					check(compiled.code.is_empty() and compiled.reason.is_empty(), "Normal success retains compiler result shape")
					check(profile.normal_map is bool and profile.normal_map and profile.journey_tier == tier, "Normal profile has explicit canonical mode/tier")
					check(profile.id == map_id and profile.wave == definition.wave and profile.name == definition.label, "Profile identity is stable and tier wave/label is canonical")
					check(profile.fee == definition.cost and profile.base_completion_reward == definition.base_reward, "Compiled fee and base reward match catalog")
					check(profile.completion_reward == tier * 4 + normal.size() + 2 * special.size(), "Completion reward adds one per normal and two per special")
					check(profile.completion_reward >= tier * 4 and profile.completion_reward <= tier * 4 + 4, "Modifier completion reward bonus stays inside zero to four")
					for field: String in Maps.Catalog.MAPS[map_id]:
						if field not in ["name", "wave"]:
							check(profile[field] == Maps.Catalog.MAPS[map_id][field], "Retained map field: " + field)
					check(Maps.profile_reason(profile).is_empty(), "Every legal normal profile passes canonical validation")
					var reversed := normal.duplicate()
					var before := normal.duplicate()
					reversed.reverse()
					check(Maps.compile_normal(map_id, tier, reversed, special).profile == profile and normal == before, "Ordinary selection order is canonical and input remains intact")
					var expected_frost: String = "frost_guard" if special == ["frost_patrol"] else ""
					var expected_storm: String = "storm_skitter" if special == ["storm_patrol"] else ""
					check(Maps.special_template(profile, {"template": "brute"}) == expected_frost, "Validated normal frost special retains template substitution")
					check(Maps.special_template(profile, {"template": "skitter"}) == expected_storm, "Validated normal storm special retains template substitution")
					check(Maps.special_template(profile, {"template": "ember_guard"}).is_empty(), "Special templates leave original ember slots unchanged")
			per_pair["%s:%d" % [map_id, tier]] = pair_count
	check(legal == 374, "Exactly 374 legal normal map/tier/modifier combinations")
	check(per_pair == {"old_garden:1": 22, "old_garden:2": 66, "old_garden:3": 88, "broken_ruins:1": 22, "broken_ruins:2": 88, "broken_ruins:3": 88}, "Per-tier legal selection counts match actual special gates")


func _test_rejections() -> void:
	for map_id: Variant in [null, true, 1, 1.0, &"old_garden", [], {}, "", "unknown"]:
		check(Catalog.definition(map_id, 1).is_empty(), "Catalog rejects unknown or non-String map ID")
		check(not Maps.compile_normal(map_id, 1, [], []).ok, "Compiler rejects unknown or non-String map ID")
	for tier: Variant in [null, true, false, 0, -1, 4, 100, 1.0, 2.0, 3.0, NAN, INF, "1", [], {}]:
		check(Catalog.definition("old_garden", tier).is_empty(), "Catalog rejects tier outside genuine integer one to three")
		check(not Maps.compile_normal("old_garden", tier, [], []).ok, "Compiler rejects tier outside genuine integer one to three")
	for normal: Variant in [null, true, 1, "enemy_armour_80", PackedStringArray(["enemy_armour_80"]), {}, [null], [true], [1], [&"enemy_armour_80"], ["unknown"], ["enemy_armour_80", "enemy_armour_80"], ["enemy_armour_80", "enemy_damage_115", "enemy_attack_speed_110"]]:
		check(not Maps.compile_normal("old_garden", 3, normal, []).ok, "Malformed, unknown, duplicate or excess ordinary choice is rejected")
	for special: Variant in [null, true, 1, "frost_patrol", PackedStringArray(["frost_patrol"]), {}, [null], [true], [1], [&"frost_patrol"], ["unknown"], ["frost_patrol", "frost_patrol"], ["frost_patrol", "storm_patrol"]]:
		check(not Maps.compile_normal("old_garden", 3, [], special).ok, "Malformed, unknown, duplicate or excess special choice is rejected")


func _test_canonical_validation() -> void:
	var canonical: Dictionary = Maps.compile_normal("old_garden", 2, ["enemy_armour_80"], ["frost_patrol"]).profile
	for field: String in canonical:
		var missing := canonical.duplicate(true)
		missing.erase(field)
		check(not Maps.profile_reason(missing).is_empty(), "Missing canonical field cannot be laundered: " + field)
	var mutations := {"normal_map": [false, 0, 1, "true", null], "journey_tier": [1, 3, 2.0, true, "2"],
		"fee": [0, 4.0, 999], "base_completion_reward": [0, 8.0, 999], "completion_reward": [0, 11.0, 999],
		"wave": [1, 4.0, 8], "ordinary_target": [36, 24.0], "id": ["broken_ruins", &"old_garden"],
		"name": ["Fake"], "summary": ["Fake"], "boss_id": ["crawler"], "boss_attack_id": ["ruins_mark"],
		"normal_ids": [[], ["enemy_armour_80", "enemy_armour_80"]], "special_ids": [[], ["storm_patrol"]]}
	for field: String in mutations:
		for value: Variant in mutations[field]:
			var changed := canonical.duplicate(true)
			changed[field] = value
			check(not Maps.profile_reason(changed).is_empty(), "Tampered normal field rejected: " + field)
			check(Maps.special_template(changed, {"template": "brute"}).is_empty(), "Tampered normal profile cannot apply template")
	var extra := canonical.duplicate(true)
	extra.unrecognized = true
	check(not Maps.profile_reason(extra).is_empty(), "Extra top-level field cannot be laundered")
	var nested := canonical.duplicate(true)
	nested.encounter_profile.multipliers.max_health = 1
	check(not Maps.profile_reason(nested).is_empty(), "Nested type substitution cannot be laundered")
	nested = canonical.duplicate(true)
	nested.encounter_profile.extra = true
	check(not Maps.profile_reason(nested).is_empty(), "Extra nested field cannot be laundered")
	var legacy: Dictionary = Maps.compile("old_garden", [], []).profile
	legacy.normal_map = false
	check(not Maps.profile_reason(legacy).is_empty(), "False normal marker cannot launder a test profile")
	legacy.normal_map = true
	check(not Maps.profile_reason(legacy).is_empty(), "True normal marker alone cannot launder a test profile")
	var reordered: Dictionary = {}
	var keys := canonical.keys()
	keys.reverse()
	for key: String in keys:
		reordered[key] = canonical[key]
	check(Maps.profile_reason(reordered).is_empty(), "Dictionary insertion order is not profile identity")


func _test_independence() -> void:
	var definition := Catalog.definition("old_garden", 2)
	definition.wave = 100
	definition.cost = 999
	check(Catalog.definition("old_garden", 2).wave == 4 and Catalog.definition("old_garden", 2).cost == 4, "Definition values are detached from canonical catalog")
	var rows := Catalog.tiers("old_garden", 0)
	rows[1].unlocked = true
	rows[1].cost = 999
	rows.clear()
	check(not Catalog.tiers("old_garden", 0)[1].unlocked and Catalog.tiers("old_garden", 0)[1].cost == 4, "UI tier rows and array are detached")
	var normal: Array = ["enemy_armour_80"]
	var special: Array = ["frost_patrol"]
	var compiled := Maps.compile_normal("old_garden", 2, normal, special)
	normal.clear()
	special.clear()
	check(compiled.profile.normal_ids == ["enemy_armour_80"] and compiled.profile.special_ids == ["frost_patrol"], "Compiled profile owns detached selections")
	var altered: Dictionary = compiled.profile.duplicate(true)
	altered.encounter_profile.definitions[0].name = "Changed"
	altered.normal_ids.clear()
	altered.special_ids.clear()
	check(Maps.profile_reason(compiled.profile).is_empty(), "Deep copied profile mutation leaves original canonical profile intact")
	compiled.profile.wave = 99
	compiled.profile.special_ids.clear()
	var fresh := Maps.compile_normal("old_garden", 2, ["enemy_armour_80"], ["frost_patrol"])
	check(fresh.profile.wave == 4 and fresh.profile.special_ids == ["frost_patrol"], "Compiled profile mutation cannot poison later compilation")
	check(Maps.Catalog.MAPS.old_garden.wave == 4 and Maps.Catalog.MAPS.broken_ruins.wave == 5, "Normal catalog/compilation never mutates fixed test-mode map catalog")


func _test_legacy_bytes() -> void:
	var frozen := FileAccess.get_file_as_bytes(LEGACY_FIXTURE)
	check(not frozen.is_empty(), "Untouched v40 binary profile capture exists")
	if frozen.is_empty():
		return
	var records: Variant = bytes_to_var(frozen)
	check(records is Array and records.size() == 176, "Fixture contains every legacy map/ordinary/special choice")
	if not records is Array:
		return
	var current: Array = []
	var legal := 0
	for record: Dictionary in records:
		var actual := Maps.compile(record.map_id, record.normal, record.special)
		check(var_to_bytes(actual) == var_to_bytes(record.result), "Legacy result remains byte-identical to untouched v40")
		if actual.ok:
			legal += 1
			check(Maps.profile_reason(actual.profile).is_empty(), "Legacy profile still validates")
			check(actual.profile.wave == (4 if record.map_id == "old_garden" else 5), "Legacy fixed map wave is unchanged")
			check(not actual.profile.has("normal_map") and not actual.profile.has("fee") and not actual.profile.has("completion_reward"), "Legacy profiles gain no progression metadata")
		current.append({"map_id": record.map_id, "normal": record.normal, "special": record.special, "result": actual})
	check(legal == 154, "Legacy legal selection count remains 154")
	check(var_to_bytes(current) == frozen, "Entire 176-result legacy capture is byte-for-byte unchanged")
