extends SceneTree
## Exact support admission and composition without actors or persistent state.
const Rules = preload("res://scripts/combat/inward_pull_support_rules.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Data = preload("res://scripts/game_data.gd")
var checks: int = 0
var failures: int = 0
var compositions: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(670067)
	var expected: Array = [randi(), randi(), randi()]
	seed(670067)
	_case(_admission, "registry, slots, version and neutral path")
	_case(_composition, "all legal pairs and representative five-support groups")
	_case(_snapshot_boundary, "compiler-owned profile and single compilation")
	_expect([randi(), randi(), randi()] == expected, "Provider and compiler preserve global RNG")
	print("Inward pull support/compiler: %d checks, %d failures; %d support compositions" % [checks, failures, compositions])
	quit(1 if failures else 0)


func _case(callback: Callable, label: String) -> void:
	completed = false
	callback.call()
	_expect(completed, "Case completed without script errors: " + label)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) <= 1.0e-10 * maxf(1.0, absf(expected)), label)


func _snapshot() -> Dictionary:
	return Combat.snapshot({"damage": 100.0, "spell_added_cold": 13.0, "spell_added_lightning": 11.0,
		"global_increased": 0.2, "area_increased": 0.1, "spell_increased": 0.3,
		"area_size_increased": 0.25, "mana_cost_efficiency_increased": 0.25,
		"crit_base_chance": 0.5, "crit_base_multiplier": 2.0, "fire_dot_multiplier": 0.2, "burn_faster": 0.25}, [])


func _profile() -> Dictionary:
	var result: Dictionary = {"enabled": true}
	result.merge(Rules.POLICY.duplicate(true))
	return result


func _admission() -> void:
	_expect(Rules.SAVE_VERSION == 43 and Rules.SKILLS == ["nova", "meteor"], "Explicit schema43 and exactly two admitted skills")
	var definition: Dictionary = Supports.get_definition("inward_pull")
	_expect(definition.name == "牵引辅助" and definition.family == "inward_pull", "Canonical support identity and display name")
	_expect(Supports.definition_error(definition).is_empty() and Supports.is_program_support("inward_pull"), "Registry owns exact provider metadata and program")
	_expect(definition.operations == [{"op": "mana_multiplier", "value": 1.20}], "One mana operation and no damage/cooldown operation")
	definition.operations[0].value = 1.0
	definition.skills.clear()
	_expect(not Rules.definition_error(definition).is_empty() and Supports.get_definition("inward_pull").operations[0].value == 1.20 and Rules.SKILLS.size() == 2, "Detached metadata never changes provider authority")
	for skill: String in Data.SKILLS:
		var allowed: bool = skill in Rules.SKILLS
		_expect(Supports.compatibility_reason(skill, ["inward_pull"]).is_empty() == allowed, "Exact registry admission: " + skill)
		_expect(Supports.supports_for_skill(skill).has("inward_pull") == allowed, "Exact selector admission: " + skill)
		_expect(Compiler.compile_group(skill, _snapshot(), ["inward_pull"]).ok == allowed, "Exact compiler admission: " + skill)
		_expect(Rules.compile_program(skill, []) == Program.empty(), "Unselected provider neutral for old skills: " + skill)
		var base: Dictionary = Compiler.compile_group(skill, _snapshot(), [])
		_expect(base.ok and not base.has("area_impulse_profile") and not base.snapshot.has("area_impulse_policy"), "No new profile in old empty selection: " + skill)
	for skill: String in Rules.SKILLS:
		_expect(not Supports.saved_links_reason(skill, ["inward_pull"], 42).is_empty(), "Schema42 rejects new link")
		_expect(Supports.saved_links_reason(skill, ["inward_pull"], 43).is_empty(), "Schema43 accepts new link")
		_expect(Supports.saved_links_reason(skill, ["ambush"], 42).is_empty(), "Old Ambush gate stays schema42")
		var expected: Dictionary = Program.empty()
		expected.mana_multiplier = 1.20
		_expect(Rules.compile_program(skill, ["inward_pull"]) == expected, "Only mana changes in support program")
	for links: Variant in [null, true, "inward_pull", ["inward_pull", "inward_pull"], ["inward_pull", 1], ["inward_pull", "unknown"]]:
		_expect(not Rules.compile_program("nova", links).error.is_empty(), "Malformed provider selection rejects")
		_expect(not Supports.compatibility_reason("nova", links).is_empty(), "Malformed registry selection rejects")
	_expect(not Rules.compile_program("nova", ["inward_pull"], 3).error.is_empty(), "Unknown slot capacity rejects")
	_expect(not Compiler.compile_skill("nova", _snapshot(), ["inward_pull", "breadth", "shock"]).ok, "Legacy two-slot capacity remains")
	_expect(not Compiler.compile_group("nova", _snapshot(), ["inward_pull", "ambush", "breadth", "shock", "efficiency", "quickcast"]).ok, "One occupied slot means sixth support rejects")
	completed = true


func _composition() -> void:
	for skill: String in Rules.SKILLS:
		_check_set(skill, ["inward_pull"])
		for other: String in Supports.SUPPORTS:
			if other == "inward_pull" or not Supports.compatibility_reason(skill, ["inward_pull", other], 5).is_empty(): continue
			_check_set(skill, ["inward_pull", other])
	_check_set("nova", ["inward_pull", "ambush", "breadth", "shock", "efficiency"])
	_check_set("nova", ["inward_pull", "concentrate", "shock", "efficiency", "quickcast"])
	_check_set("meteor", ["inward_pull", "ambush", "concentrate", "ignite", "quickcast"])
	_check_set("meteor", ["inward_pull", "breadth", "ember_proliferation", "fire_focus", "quickcast"])
	completed = true


func _check_set(skill: String, links: Array) -> void:
	compositions += 1
	var raw: Dictionary = _snapshot()
	var before: PackedByteArray = var_to_bytes([raw, links])
	var cast: Dictionary = Compiler.compile_group(skill, raw, links)
	_expect(cast.ok, "Compatible composition compiles: " + str(links))
	if not cast.ok: return
	var reversed: Array = links.duplicate()
	reversed.reverse()
	_expect(var_to_bytes(cast) == var_to_bytes(Compiler.compile_group(skill, raw, reversed)), "Canonical order independent of selection order")
	_expect(var_to_bytes([raw, links]) == before, "Compiler preserves all input bytes")
	var others: Array = links.duplicate()
	others.erase("inward_pull")
	var base: Dictionary = Compiler.compile_group(skill, raw, others)
	_expect(base.ok and cast.packets == base.packets and cast.recipe == base.recipe and cast.initial_count == base.initial_count, "All old packets and final geometry stay unchanged")
	_near(cast.mana, base.mana * 1.20, "Final mana factor applied once after other costs")
	_near(cast.cooldown, base.cooldown, "Cooldown unchanged")
	_expect(cast.area_impulse_profile == _profile() and cast.snapshot.area_impulse_policy == _profile(), "Preview and frozen cast contain exact enabled profile")
	_expect(Rules.policy_error(cast.snapshot.area_impulse_policy).is_empty(), "Compiled runtime contract is accepted")
	var comparable: Dictionary = cast.snapshot.duplicate(true)
	comparable.erase("area_impulse_policy")
	_expect(var_to_bytes(comparable) == var_to_bytes(base.snapshot), "Impulse policy is the only snapshot change")
	_expect(Damage.resolve(cast.packets.direct, cast.snapshot.modifiers) == Damage.resolve(base.packets.direct, base.snapshot.modifiers), "Every resolved damage component stays unchanged")
	_near(cast.cost_factors.support_mana, base.cost_factors.support_mana * 1.20, "Cost trace includes support mana once")
	_near(cast.cost_factors.final_mana, base.cost_factors.final_mana * 1.20, "Cost trace final mana matches increased cost")
	for key: String in ["increased_cost", "increased_efficiency", "numerator", "denominator"]:
		_expect(cast.cost_factors[key] == base.cost_factors[key], "Source cost formula factor unchanged: " + key)
	for key: String in ["critical", "leech", "burn_profile", "shock_profile", "trap_profile", "hit_policy"]:
		_expect(cast.get(key) == base.get(key), "Existing independent compile product unchanged: " + key)
	cast.area_impulse_profile.impulse_speed = 1.0
	_expect(cast.snapshot.area_impulse_policy == _profile(), "Preview mutation cannot alter frozen runtime profile")
	cast.snapshot.area_impulse_policy.direction = "away_from_origin"
	var fresh: Dictionary = Compiler.compile_group(skill, raw, links)
	_expect(fresh.area_impulse_profile == _profile() and fresh.snapshot.area_impulse_policy == _profile(), "Detached output cannot mutate future compilation")


func _snapshot_boundary() -> void:
	for skill: String in Rules.SKILLS:
		var cast: Dictionary = Compiler.compile_group(skill, _snapshot(), ["inward_pull"])
		_expect(not Compiler.compile_group(skill, cast.snapshot, ["inward_pull"]).ok, "Compiled cast cannot be compiled twice")
		var injected: Dictionary = _snapshot()
		injected.area_impulse_policy = _profile()
		var before := var_to_bytes(injected)
		_expect(not Compiler.compile_group(skill, injected, []).ok, "Unselected injected policy cannot bypass compiler ownership")
		_expect(var_to_bytes(injected) == before, "Rejected injected policy preserves input bytes")
	completed = true
