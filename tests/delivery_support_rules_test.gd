extends SceneTree
## Pure-provider contract; registry, actual recipe application and save migration are separate integration tests.
const Rules = preload("res://scripts/combat/delivery_support_rules.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const Data = preload("res://scripts/game_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const IDS: Array[String] = ["swift_projectiles", "heavy_projectiles", "lingering_chill", "chain_extension", "chain_reach"]
const NAMES: Array[String] = ["疾速投射辅助", "缓速强击辅助", "寒意延长辅助", "连锁延展辅助", "远链辅助"]
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(193051)
	var expected_rng: Array = [randi(), randi(), randi()]
	seed(193051)
	var catalogs: PackedByteArray = var_to_bytes([Rules.SUPPORTS, Data.SKILLS, Combat.TORNADO, Program.PRIMARY_TAGS])
	_case(_test_metadata, "metadata and corrupt definitions")
	_case(_test_numeric_matrix, "literal single and pair balance")
	_case(_test_selection, "eligible skills and atomic rejection")
	_case(_test_damage_scope, "real primary packets and excluded damage scopes")
	_case(_test_detachment, "detached definitions, programs and canonical ordering")
	_expect(var_to_bytes([Rules.SUPPORTS, Data.SKILLS, Combat.TORNADO, Program.PRIMARY_TAGS]) == catalogs, "All shared catalogs remain byte-identical")
	_expect([randi(), randi(), randi()] == expected_rng, "Validation and compilation consume no global RNG")
	print("Delivery support rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _case(test: Callable, label: String) -> void:
	completed = false
	test.call()
	_expect(completed, "Case completes without a script exception: " + label)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) < 0.000001, "%s (%.9f / %.9f)" % [label, actual, expected])


func _bad_definition(value: Variant) -> void:
	var before: PackedByteArray = var_to_bytes(value)
	_expect(not Rules.definition_error(value).is_empty(), "Malformed definition fails closed")
	_expect(var_to_bytes(value) == before, "Definition validation does not repair caller input")


func _test_metadata() -> void:
	_expect(Rules.SUPPORTS.keys() == IDS, "Five fixed support IDs")
	_expect(Rules.get_definition("unknown") == {}, "Unknown metadata has no definition")
	for index: int in range(IDS.size()):
		var definition: Dictionary = Rules.get_definition(IDS[index])
		_expect(definition.size() == 6 and definition.has_all(["name", "description", "skills", "requires", "operations", "family"]), "Exact six-field metadata")
		_expect(definition.name == NAMES[index] and Rules.definition_error(definition).is_empty(), "Authored name and executable definition validate")
		var json_definition: Variant = JSON.parse_string(JSON.stringify(definition))
		_expect(Rules.definition_error(json_definition).is_empty(), "JSON numeric round trip remains valid")
		for key: String in definition:
			var missing: Dictionary = definition.duplicate(true)
			missing.erase(key)
			_bad_definition(missing)
		var extra: Dictionary = definition.duplicate(true)
		extra.extra = true
		_bad_definition(extra)
		for key: String in ["name", "description", "skills", "requires", "operations", "family"]:
			for invalid: Variant in [null, true, 1, {}, ""]:
				var broken: Dictionary = definition.duplicate(true)
				broken[key] = invalid
				_bad_definition(broken)
		for key: String in ["skills", "requires"]:
			for invalid: Variant in [[], [1], [null], [""], ["unknown"], PackedStringArray(["frost"])]:
				var broken: Dictionary = definition.duplicate(true)
				broken[key] = invalid
				_bad_definition(broken)
			var duplicated: Dictionary = definition.duplicate(true)
			duplicated[key].append(duplicated[key][0])
			_bad_definition(duplicated)
		for i: int in range(definition.operations.size()):
			for invalid: Variant in [null, true, "1", {}, [], NAN, INF, -INF, -99.0, 0.0, 100.0]:
				var broken: Dictionary = definition.duplicate(true)
				broken.operations[i].value = invalid
				_bad_definition(broken)
			for invalid: Variant in [null, true, 1, "unknown"]:
				var broken: Dictionary = definition.duplicate(true)
				broken.operations[i].op = invalid
				_bad_definition(broken)
			for invalid: Variant in [null, [], 1, {}, {"op": "mana_multiplier"}, {"value": 1.1}, {"op": "mana_multiplier", "value": 1.1, "extra": 1}]:
				var broken: Dictionary = definition.duplicate(true)
				broken.operations[i] = invalid
				_bad_definition(broken)
			var missing: Dictionary = definition.duplicate(true)
			missing.operations.remove_at(i)
			_bad_definition(missing)
		var duplicate: Dictionary = definition.duplicate(true)
		duplicate.operations[1] = duplicate.operations[0].duplicate(true)
		_bad_definition(duplicate)
		var wrong_family: Dictionary = definition.duplicate(true)
		wrong_family.family = "control" if definition.family != "control" else "chain"
		_bad_definition(wrong_family)
	for invalid: Variant in [null, 1, true, "", [], {}]:
		_bad_definition(invalid)
	for change: Array in [["swift_projectiles", 0, 1.0], ["heavy_projectiles", 0, 1.0], ["heavy_projectiles", 1, -0.2],
		["lingering_chill", 0, 1.0], ["lingering_chill", 1, 0.1], ["chain_extension", 0, 2.5],
		["chain_extension", 1, 0.2], ["chain_reach", 0, 1.0], ["chain_reach", 1, 0.1]]:
		var broken: Dictionary = Rules.get_definition(change[0])
		broken.operations[change[1]].value = change[2]
		_bad_definition(broken)
	var extra_damage: Dictionary = Rules.get_definition("swift_projectiles")
	extra_damage.operations.append({"op": "primary_hit_more", "value": 0.2})
	_bad_definition(extra_damage)
	var double_factor: Dictionary = Rules.get_definition("chain_extension")
	double_factor.operations[1] = {"op": "chain_followup_range_multiplier", "value": 1.3}
	_bad_definition(double_factor)
	completed = true


func _check_program(skill: String, ids: Array, factors: Dictionary, mana: float, damage: float) -> void:
	var result: Dictionary = Rules.compile_program(skill, ids)
	_expect(result.error.is_empty(), "Eligible selection compiles: %s %s" % [skill, ids])
	_expect(result.keys() == Program.empty().keys(), "Stable five-field program envelope")
	_expect(result.recipe_factors.keys() == factors.keys(), "Only relevant recipe factors are emitted")
	for key: String in factors:
		_near(result.recipe_factors[key], factors[key], "Exact combined factor: " + key)
	_near(result.mana_multiplier, mana, "Mana products")
	_near(result.cooldown_multiplier, 1.0, "No cooldown change")
	var packet: Dictionary = Damage.packet({"cold": 100.0}, Program.PRIMARY_TAGS[skill], skill)
	_near(Damage.resolve(packet, result.modifiers).total, 100.0 * damage, "Primary MORE factors multiply")
	var reversed: Array = ids.duplicate()
	reversed.reverse()
	_expect(var_to_bytes(result) == var_to_bytes(Rules.compile_program(skill, reversed)), "Program byte order is canonical")


func _test_numeric_matrix() -> void:
	for skill: String in ["bolt", "frost"]:
		_check_program(skill, [], {}, 1.0, 1.0)
		_check_program(skill, ["swift_projectiles"], {"projectile_speed_multiplier": 1.35}, 1.10, 1.0)
		_check_program(skill, ["heavy_projectiles"], {"projectile_speed_multiplier": 0.75}, 1.15, 1.20)
		_check_program(skill, ["swift_projectiles", "heavy_projectiles"], {"projectile_speed_multiplier": 1.0125}, 1.265, 1.20)
		_near(float(Data.SKILLS[skill].projectile_recipe.speed) * 1.35, 1053.0 if skill == "bolt" else 702.0, "Authored fast speed")
		_near(float(Data.SKILLS[skill].projectile_recipe.speed) * 0.75, 585.0 if skill == "bolt" else 390.0, "Authored heavy speed")
		_near(float(Data.SKILLS[skill].projectile_recipe.speed) * 1.0125, 789.75 if skill == "bolt" else 526.5, "Opposed speed pair stays multiplicative")
	_check_program("frost", ["lingering_chill"], {"slow_duration_multiplier": 1.5}, 1.10, 0.90)
	_check_program("frost", ["swift_projectiles", "lingering_chill"], {"slow_duration_multiplier": 1.5, "projectile_speed_multiplier": 1.35}, 1.21, 0.90)
	_check_program("frost", ["heavy_projectiles", "lingering_chill"], {"projectile_speed_multiplier": 0.75, "slow_duration_multiplier": 1.5}, 1.265, 1.08)
	_near(float(Data.SKILLS.frost.projectile_recipe.slow) * 1.5, 4.5, "Existing three-second slow becomes 4.5 seconds")
	_check_program("chain", [], {}, 1.0, 1.0)
	_check_program("chain", ["chain_extension"], {"chain_extra_targets": 2}, 1.30, 0.80)
	_check_program("chain", ["chain_reach"], {"chain_followup_range_multiplier": 1.30}, 1.15, 0.90)
	_check_program("chain", ["chain_reach", "chain_extension"], {"chain_extra_targets": 2, "chain_followup_range_multiplier": 1.30}, 1.495, 0.72)
	var extended: Dictionary = Rules.compile_program("chain", ["chain_extension"])
	_expect(extended.recipe_factors.chain_extra_targets is int, "Additional total-target budget stays integral")
	_expect(int(Data.SKILLS.chain.hit_recipe.bounce_count) + int(extended.recipe_factors.chain_extra_targets) == 7, "Five total targets extend to seven total, not seven hops")
	_near(220.0 * Rules.compile_program("chain", ["chain_reach"]).recipe_factors.chain_followup_range_multiplier, 286.0, "Follow-up range is 286")
	_expect(not extended.recipe_factors.has("chain_initial_range_multiplier"), "No first-target range factor can change 600 range")
	completed = true


func _rejected(skill: Variant, ids: Variant) -> void:
	var before: PackedByteArray = var_to_bytes([skill, ids])
	var result: Dictionary = Rules.compile_program(skill, ids)
	_expect(result.keys() == Program.empty().keys(), "Rejected selection keeps full envelope")
	_expect(result.error is String and not result.error.is_empty(), "Rejected selection has an error")
	result.error = ""
	_expect(result == Program.empty(), "Failure exposes no partial modifiers, costs or factors")
	_expect(before == var_to_bytes([skill, ids]), "Rejection preserves caller input")


func _test_selection() -> void:
	for skill: String in Data.SKILLS:
		_expect(Rules.compile_program(skill, []) == Program.empty(), "Empty owner subset is an empty program for any real skill")
		for id: String in IDS:
			if Rules.SUPPORTS[id].skills.has(skill):
				_expect(Rules.compile_program(skill, [id]).error.is_empty(), "Authored skill is admitted")
			else:
				_rejected(skill, [id])
		for first: String in IDS:
			for second: String in IDS:
				if first == second or not Rules.SUPPORTS[first].skills.has(skill) or not Rules.SUPPORTS[second].skills.has(skill):
					_rejected(skill, [first, second])
				else:
					_expect(Rules.compile_program(skill, [first, second]).error.is_empty(), "Every eligible distinct pair is allowed")
	for skill: Variant in [null, 1, true, [], {}, "", "unknown", "basic"]:
		_rejected(skill, [])
		_rejected(skill, ["swift_projectiles"])
	for ids: Variant in [null, "swift_projectiles", 1, true, {}, PackedStringArray(["swift_projectiles"]),
		[null], [true], [1], [["swift_projectiles"]], [""], ["unknown"], ["volley"],
		["swift_projectiles", "unknown"], ["unknown", "swift_projectiles"],
		["swift_projectiles", "swift_projectiles"], ["swift_projectiles", "heavy_projectiles", "lingering_chill"]]:
		_rejected("frost", ids)
	completed = true


func _test_damage_scope() -> void:
	var snapshot: Dictionary = Combat.snapshot({"damage": 100.0, "spell_added_cold": 8.0, "spell_added_lightning": 12.0}, ["explode_on_flight_end"])
	var components: Dictionary = {"physical": 10.0, "fire": 20.0, "cold": 30.0, "lightning": 40.0, "chaos": 50.0}
	var defenses: Dictionary = {"physical": 0.1, "fire": 0.5, "cold": 0.25, "lightning": 0.75, "chaos": -0.2}
	for row: Array in [["bolt", ["heavy_projectiles"], 1.2], ["frost", ["lingering_chill"], 0.9],
		["frost", ["heavy_projectiles", "lingering_chill"], 1.08], ["chain", ["chain_extension"], 0.8],
		["chain", ["chain_reach"], 0.9], ["chain", ["chain_extension", "chain_reach"], 0.72]]:
		var skill: String = row[0]
		var program: Dictionary = Rules.compile_program(skill, row[1])
		var role: String = "bounce" if skill == "chain" else "projectile"
		var count: int = int(Data.SKILLS.chain.hit_recipe.bounce_count) if skill == "chain" else 1
		for index: int in range(count):
			var packet: Dictionary = Combat.event_packet(snapshot, skill, role, index)
			var original: PackedByteArray = var_to_bytes(packet)
			_expect(not packet.is_empty(), "Real authored primary packet exists")
			_near(Damage.resolve(packet, program.modifiers, defenses).total, Damage.resolve(packet, [], defenses).total * float(row[2]), "Real primary coefficient and falloff receive MORE exactly once")
			_expect(var_to_bytes(packet) == original, "Applying MORE does not rewrite packet coefficients")
		var primary: Dictionary = Damage.packet(components, Program.PRIMARY_TAGS[skill], skill)
		var before: Dictionary = Damage.resolve(primary, [], defenses)
		var after: Dictionary = Damage.resolve(primary, program.modifiers, defenses)
		for type: String in components:
			_near(after.components[type], before.components[type] * float(row[2]), "All primary damage types include the same MORE factor")
		var excluded: Array[Dictionary] = [
			Damage.packet(components, ["hit", "projectile", "attack"], "basic"),
			Damage.packet(components, Program.PRIMARY_TAGS[skill], "bolt" if skill != "bolt" else "frost"),
			Damage.packet(components, ["hit", "area", "secondary", "explosion"], skill),
		]
		for tag: String in Program.PRIMARY_TAGS[skill]:
			var tags: Array = Program.PRIMARY_TAGS[skill].duplicate()
			tags.erase(tag)
			excluded.append(Damage.packet(components, tags, skill))
		if skill != "chain":
			excluded.append(Combat.secondary_packet(snapshot, skill))
		for packet: Dictionary in excluded:
			_near(Damage.resolve(packet, program.modifiers, defenses).total, Damage.resolve(packet, [], defenses).total, "Basic, other skill, missing primary tags and independent explosion remain unchanged")
	completed = true


func _test_detachment() -> void:
	for id: String in IDS:
		var definition: Dictionary = Rules.get_definition(id)
		var original: PackedByteArray = var_to_bytes(definition)
		definition.skills.clear()
		definition.requires.append("corrupt")
		definition.operations[0].value = 999.0
		definition.description = "changed"
		_expect(var_to_bytes(Rules.get_definition(id)) == original, "Metadata is deeply detached")
	for row: Array in [["bolt", ["swift_projectiles", "heavy_projectiles"]], ["frost", ["heavy_projectiles", "lingering_chill"]], ["chain", ["chain_reach", "chain_extension"]]]:
		var ids: Array = row[1].duplicate()
		var input_bytes: PackedByteArray = var_to_bytes(ids)
		var result: Dictionary = Rules.compile_program(row[0], ids)
		var original: PackedByteArray = var_to_bytes(result)
		_expect(var_to_bytes(ids) == input_bytes, "Canonical sorting never changes caller link order")
		result.recipe_factors.corrupt = 99
		result.modifiers[0].all_tags.clear()
		result.modifiers[0].skills.clear()
		result.modifiers[0].damage_types.append("cold")
		result.modifiers[0].value = 99
		result.mana_multiplier = 99
		ids.clear()
		_expect(var_to_bytes(Rules.compile_program(row[0], row[1])) == original, "Results are detached from caller IDs, metadata, other runs and primary-tag constants")
	var empty: Dictionary = Rules.compile_program("frost", [])
	empty.modifiers.append({"bad": true})
	empty.recipe_factors.bad = 1
	_expect(Rules.compile_program("frost", []) == Program.empty(), "Empty programs are independently owned")
	completed = true
