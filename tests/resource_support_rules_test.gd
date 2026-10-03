extends SceneTree
## Provider-only contract: no registry/compiler integration or save operations.
const Rules = preload("res://scripts/combat/resource_support_rules.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const Data = preload("res://scripts/game_data.gd")
const SKILLS: Array[String] = ["tornado", "bolt", "frost", "nova", "dash", "ward", "meteor", "chain"]
const ENVELOPE: Array[String] = ["error", "modifiers", "mana_multiplier", "cooldown_multiplier", "recipe_factors"]
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var skill_snapshot: Dictionary = Data.SKILLS.duplicate(true)
	seed(193081)
	randi()
	var expected_rng: Array = [randi(), randi(), randi()]
	seed(193081)
	randi()
	_case(_test_metadata, "authored metadata and detached definitions")
	_case(_test_programs, "all eight skills and link combinations")
	_case(_test_rejections, "atomic selection rejection")
	_case(_test_metadata_rejections, "metadata structure, finite numbers and effect bounds")
	_case(_test_detachment, "independent results and input ownership")
	_expect([randi(), randi(), randi()] == expected_rng, "All successful and rejected calls preserve the global RNG stream")
	_expect(Data.SKILLS == skill_snapshot, "Resource rules leave all skill costs, recipes and capabilities untouched")
	print("Resource support rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	completed = false
	test.call()
	_expect(completed, "Case completes without a script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.00001, "%s (actual %.8f, expected %.8f)" % [label, value, expected])


func _envelope(result: Dictionary, label: String) -> void:
	_expect(result.size() == ENVELOPE.size() and result.has_all(ENVELOPE), "Exact shared five-field envelope: " + label)
	_expect(result.error is String and result.modifiers is Array and result.recipe_factors is Dictionary, "Typed envelope: " + label)
	_expect(result.modifiers.is_empty() and result.recipe_factors.is_empty(), "No hit, shield, invulnerability, dash or projectile effect: " + label)
	_expect(Program.number(result.mana_multiplier) and Program.number(result.cooldown_multiplier), "Finite numeric multipliers: " + label)


func _failure(skill_id: Variant, ids: Variant, label: String) -> void:
	var result: Dictionary = Rules.compile_program(skill_id, ids)
	_envelope(result, label)
	_expect(not result.error.is_empty(), "Reject " + label)
	var neutral: Dictionary = Program.empty()
	neutral.error = result.error
	_expect(result == neutral, "Failure has no partial resource effects: " + label)


func _test_metadata() -> void:
	_expect(Rules.SUPPORTS.keys() == ["efficiency", "quickcast"], "Two stable resource support IDs")
	_expect(Rules.SKILL_IDS == SKILLS, "Eligibility is the fixed eight-skill allowlist")
	var names: Array[String] = ["节能辅助", "疾咏辅助"]
	var costs: Array[float] = [0.80, 1.40]
	var cooldowns: Array[float] = [1.15, 0.80]
	for index: int in range(2):
		var id: String = ["efficiency", "quickcast"][index]
		var definition: Dictionary = Rules.get_definition(id)
		_expect(Rules.definition_error(definition).is_empty(), "Authored metadata validates: " + id)
		_expect(definition.size() == 6 and definition.has_all(["name", "description", "skills", "requires", "operations", "family"]), "Exactly six public metadata fields: " + id)
		_expect(definition.name == names[index] and not definition.description.is_empty(), "Name and description: " + id)
		_expect(definition.skills == SKILLS and definition.requires == [] and definition.family == "resource", "Explicit skill scope and resource family: " + id)
		_expect(definition.operations == [{"op": "mana_multiplier", "value": costs[index]}, {"op": "cooldown_multiplier", "value": cooldowns[index]}], "Exact authored balance: " + id)
		definition.operations[0].value = 9.0
		definition.skills.clear()
		definition.requires.append("projectile_hit")
		_expect(Rules.get_definition(id).operations[0].value == costs[index], "Definition operations are deeply detached: " + id)
		_expect(Rules.get_definition(id).skills == SKILLS and Rules.get_definition(id).requires.is_empty(), "Definition lists are deeply detached: " + id)
	for invalid: Variant in ["unknown", "", "basic", null, true, false, 1, 1.0, NAN, INF, [], {}, &"efficiency"]:
		_expect(Rules.get_definition(invalid).is_empty(), "Invalid metadata lookup is empty: " + str(invalid))
	completed = true


func _test_programs() -> void:
	for skill_id: String in SKILLS:
		for fixture: Array in [[[], 1.0, 1.0], [["efficiency"], 0.80, 1.15], [["quickcast"], 1.40, 0.80],
			[["efficiency", "quickcast"], 1.12, 0.92], [["quickcast", "efficiency"], 1.12, 0.92]]:
			var ids: Array = fixture[0]
			var before: Array = ids.duplicate(true)
			var label: String = "%s %s" % [skill_id, ids]
			var result: Dictionary = Rules.compile_program(skill_id, ids)
			_envelope(result, label)
			_expect(result.error.is_empty(), "Valid resource selection compiles: " + label)
			_near(result.mana_multiplier, fixture[1], "Mana factor: " + label)
			_near(result.cooldown_multiplier, fixture[2], "Cooldown factor: " + label)
			_near(float(Data.SKILLS[skill_id].mana) * result.mana_multiplier, float(Data.SKILLS[skill_id].mana) * float(fixture[1]), "Applied base mana: " + label)
			_near(float(Data.SKILLS[skill_id].cooldown) * result.cooldown_multiplier, float(Data.SKILLS[skill_id].cooldown) * float(fixture[2]), "Applied base cooldown: " + label)
			_expect(ids == before, "Compiling preserves caller list order: " + label)
		_expect(Rules.compile_program(skill_id, []) == Program.empty(), "Empty selection returns a neutral program: " + skill_id)
		_expect(Rules.compile_program(skill_id, ["quickcast", "efficiency"]) == Rules.compile_program(skill_id, ["efficiency", "quickcast"]), "Canonical order has exactly equal output: " + skill_id)
	completed = true


func _test_rejections() -> void:
	for skill_id: Variant in ["basic", "unknown", "future_skill", "", null, true, false, 1, 1.0, NAN, INF, [], {}, &"bolt"]:
		for ids: Array in [[], ["efficiency"], ["quickcast"], ["efficiency", "quickcast"]]:
			_failure(skill_id, ids, "unknown or non-string skill " + str(skill_id))
	for skill_id: String in SKILLS:
		for ids: Variant in [null, "efficiency", {}, 1, true, false, NAN, INF, PackedStringArray(["efficiency"]),
			["unknown"], ["efficiency", "unknown"], ["unknown", "quickcast"], ["quickcast", "efficiency", "unknown"],
			["efficiency", "efficiency"], ["quickcast", "quickcast"], ["efficiency", "quickcast", "efficiency"],
			[""], [true], [false], [1], [1.0], [NAN], [INF], [null], [[]], [{}], [&"efficiency"],
			["efficiency", true], ["quickcast", null], ["efficiency", ["quickcast"]]]:
			_failure(skill_id, ids, "%s malformed selection %s" % [skill_id, ids])
	completed = true


func _test_metadata_rejections() -> void:
	for invalid: Variant in [null, [], "efficiency", {}, 1, 1.0, true, false, NAN, INF]:
		_expect(not Rules.definition_error(invalid).is_empty(), "Reject non-definition metadata")
	for id: String in ["efficiency", "quickcast"]:
		for key: String in ["name", "description", "skills", "requires", "operations", "family"]:
			var missing: Dictionary = Rules.get_definition(id)
			missing.erase(key)
			_expect(not Rules.definition_error(missing).is_empty(), "Reject missing field: " + key)
		for change: Array in [["name", ""], ["name", 2], ["name", &"节能辅助"], ["description", ""], ["description", true],
			["family", ""], ["family", "damage"], ["family", true], ["family", &"resource"], ["extra", true],
			["skills", null], ["skills", []], ["skills", ["bolt"]], ["skills", SKILLS + ["future_skill"]],
			["skills", PackedStringArray(SKILLS)], ["requires", null], ["requires", {}], ["requires", ["projectile_hit"]],
			["requires", PackedStringArray()], ["operations", null], ["operations", {}], ["operations", []]]:
			var invalid: Dictionary = Rules.get_definition(id)
			invalid[change[0]] = change[1]
			_expect(not Rules.definition_error(invalid).is_empty(), "Reject metadata field corruption: " + str(change))
		for bad_skill: Variant in ["future_skill", "bolt", true, null, 1, &"tornado"]:
			var invalid: Dictionary = Rules.get_definition(id)
			var malformed_skills: Array = []
			malformed_skills.append_array(SKILLS)
			malformed_skills[0] = bad_skill
			invalid.skills = malformed_skills
			_expect(not Rules.definition_error(invalid).is_empty(), "Reject replaced, duplicate or non-string skill")
		for index: int in range(2):
			for operation: Variant in [null, {}, [], true, {"op": "mana_multiplier"}, {"value": 1.2},
				{"op": "mana_multiplier", "value": 1.2, "extra": true}, {"op": true, "value": 1.2},
				{"op": &"mana_multiplier", "value": 1.2}, {"op": "hit_more", "value": 1.2},
				{"op": "ward_multiplier", "value": 1.2}, {"op": "invulnerability_multiplier", "value": 1.2},
				{"op": "dash_distance_multiplier", "value": 1.2}, {"op": "projectile_speed_multiplier", "value": 1.2}]:
				var invalid: Dictionary = Rules.get_definition(id)
				invalid.operations[index] = operation
				_expect(not Rules.definition_error(invalid).is_empty(), "Reject unknown or malformed resource operation")
			for amount: Variant in [null, "0.8", true, false, [], {}, NAN, INF, -INF, -10.0, 0.0, 10.0001]:
				var invalid: Dictionary = Rules.get_definition(id)
				invalid.operations[index].value = amount
				_expect(not Rules.definition_error(invalid).is_empty(), "Reject invalid resource multiplier: " + str(amount))
			var duplicate: Dictionary = Rules.get_definition(id)
			duplicate.operations[index] = duplicate.operations[1 - index].duplicate(true)
			_expect(not Rules.definition_error(duplicate).is_empty(), "Reject duplicate resource operation")
		for pair: Array in [[0.8, 0.8], [1.2, 1.2], [1.0, 1.2], [0.8, 1.0], [1.0, 1.0]]:
			var invalid: Dictionary = Rules.get_definition(id)
			invalid.operations[0].value = pair[0]
			invalid.operations[1].value = pair[1]
			_expect(not Rules.definition_error(invalid).is_empty(), "Reject free gains, pure penalties or a missing tradeoff")
		var reversed: Dictionary = Rules.get_definition(id)
		reversed.operations.reverse()
		_expect(Rules.definition_error(reversed).is_empty(), "Operation declaration order does not change validity")
		var bounded: Dictionary = Rules.get_definition(id)
		bounded.operations[0].value = 10.0
		bounded.operations[1].value = 0.01
		_expect(Rules.definition_error(bounded).is_empty(), "Positive finite opposing factors accept the inclusive maximum")
	completed = true


func _test_detachment() -> void:
	var ids: Array = ["quickcast", "efficiency"]
	var first: Dictionary = Rules.compile_program("dash", ids)
	var second: Dictionary = Rules.compile_program("dash", ids)
	ids.clear()
	first.modifiers.append({"id": "foreign", "value": 99.0})
	first.recipe_factors["dash_distance_multiplier"] = 10.0
	first.mana_multiplier = 900.0
	first.cooldown_multiplier = 900.0
	_envelope(second, "separate successful result")
	_near(second.mana_multiplier, 1.12, "Prior output survives caller and sibling mutation")
	_near(second.cooldown_multiplier, 0.92, "Prior cooldown survives caller and sibling mutation")
	_expect(second == Rules.compile_program("dash", ["efficiency", "quickcast"]), "Fresh output is unaffected by prior mutation")
	var empty: Dictionary = Rules.compile_program("ward", [])
	empty.modifiers.append("foreign")
	empty.recipe_factors["ward_multiplier"] = 99.0
	_expect(Rules.compile_program("ward", []) == Program.empty(), "Neutral output containers are detached")
	var failed: Dictionary = Rules.compile_program("ward", ["efficiency", "unknown"])
	failed.modifiers.append("foreign")
	failed.recipe_factors["invulnerability_multiplier"] = 99.0
	_failure("ward", ["efficiency", "unknown"], "fresh failed result after prior mutation")
	_expect(Rules.definition_error(Rules.get_definition("efficiency")).is_empty() and Rules.definition_error(Rules.get_definition("quickcast")).is_empty(), "Result mutations never corrupt the authoritative definitions")
	completed = true
