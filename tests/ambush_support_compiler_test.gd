extends SceneTree
## Exact support admission/composition; no gameplay scene or persistent save.
const Rules = preload("res://scripts/combat/ambush_support_rules.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Data = preload("res://scripts/game_data.gd")
var checks: int = 0
var failures: int = 0
var compositions: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(660042)
	var expected: Array = [randi(), randi()]
	seed(660042)
	_admission()
	_composition()
	_expect([randi(), randi()] == expected, "Pure provider and compiler preserve global RNG")
	print("Ambush support/compiler: %d checks, %d failures; %d support compositions" % [checks, failures, compositions])
	quit(1 if failures else 0)


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
		"crit_base_chance": 0.5, "crit_base_multiplier": 2.0, "fire_dot_multiplier": 0.2}, [])


func _admission() -> void:
	_expect(Rules.POLICY == {"arming_seconds": 0.35, "trigger_radius": 70.0, "lifetime_seconds": 12.0,
		"maximum_traps": 3, "hit_multiplier": 0.85, "mana_multiplier": 1.25}, "Exact approved six-field policy")
	_expect(Rules.SAVE_VERSION == 42 and Rules.SKILLS == ["nova", "meteor"], "Explicit save version and admitted skills")
	var definition: Dictionary = Supports.get_definition("ambush")
	_expect(definition.name == "符印伏击辅助" and definition.family == "ambush", "Canonical support identity and full display name")
	_expect(Supports.definition_error(definition).is_empty() and Supports.is_program_support("ambush"), "Registry owns metadata and program admission")
	definition.operations[0].value = 0.0
	_expect(not Rules.definition_error(definition).is_empty() and Supports.get_definition("ambush").operations[0].value == -0.15, "Detached metadata cannot mutate authority")
	for skill: String in Data.SKILLS:
		var allowed: bool = skill in Rules.SKILLS
		_expect(Supports.compatibility_reason(skill, ["ambush"]).is_empty() == allowed, "Exact registry admission: " + skill)
		_expect(Supports.supports_for_skill(skill).has("ambush") == allowed, "Exact selector admission: " + skill)
		_expect(Compiler.compile_group(skill, _snapshot(), ["ambush"]).ok == allowed, "Exact compiler admission: " + skill)
		_expect(Rules.compile_program(skill, []) == Program.empty(), "Unselected provider is neutral for old skills: " + skill)
		var base: Dictionary = Compiler.compile_group(skill, _snapshot(), [])
		_expect(base.ok and not base.has("trap_profile") and not base.snapshot.has("trap_profile"), "Old empty selection has no trap output: " + skill)
	for skill: String in Rules.SKILLS:
		_expect(not Supports.saved_links_reason(skill, ["ambush"], 41).is_empty(), "Old41 rejects new links")
		_expect(Supports.saved_links_reason(skill, ["ambush"], 42).is_empty(), "Current42 accepts new links")
		var program: Dictionary = Rules.compile_program(skill, ["ambush"])
		_expect(program == {"error": "", "modifiers": [Program.primary_modifier("ambush", skill, -0.15)],
			"mana_multiplier": 1.25, "cooldown_multiplier": 1.0, "recipe_factors": {}}, "Only primary factor and mana change")
	for links: Variant in [null, true, "ambush", ["ambush", "ambush"], ["ambush", 1], ["ambush", "unknown"]]:
		_expect(not Rules.compile_program("nova", links).error.is_empty(), "Malformed provider selection rejects")
		_expect(not Supports.compatibility_reason("nova", links).is_empty(), "Malformed registry selection rejects")
	_expect(not Rules.compile_program("nova", ["ambush"], 3).error.is_empty(), "Unknown slot capacity rejects")
	_expect(not Compiler.compile_skill("nova", _snapshot(), ["ambush", "breadth", "shock"]).ok, "Legacy two-slot contract remains")
	_expect(not Compiler.compile_group("nova", _snapshot(), ["ambush", "breadth", "shock", "efficiency", "quickcast", "concentrate"]).ok, "Sixth group support rejects")


func _composition() -> void:
	for skill: String in Rules.SKILLS:
		_check_set(skill, ["ambush"])
		for other: String in Supports.SUPPORTS:
			if other == "ambush" or not Supports.compatibility_reason(skill, ["ambush", other], 5).is_empty(): continue
			_check_set(skill, ["ambush", other])
	_check_set("nova", ["ambush", "breadth", "shock", "efficiency", "quickcast"])
	_check_set("meteor", ["ambush", "concentrate", "ignite", "efficiency", "quickcast"])
	_check_set("meteor", ["ambush", "breadth", "ember_proliferation", "fire_focus", "quickcast"])


func _check_set(skill: String, links: Array) -> void:
	compositions += 1
	var raw: Dictionary = _snapshot()
	var original: PackedByteArray = var_to_bytes(raw)
	var before_links: PackedByteArray = var_to_bytes(links)
	var cast: Dictionary = Compiler.compile_group(skill, raw, links)
	_expect(cast.ok, "Compatible composition compiles: " + str(links))
	if not cast.ok: return
	var reversed: Array = links.duplicate()
	reversed.reverse()
	_expect(var_to_bytes(cast) == var_to_bytes(Compiler.compile_group(skill, raw, reversed)), "Canonical ordering independent of selection order")
	_expect(var_to_bytes(raw) == original and var_to_bytes(links) == before_links, "Compiler never changes inputs")
	var others: Array = links.duplicate()
	others.erase("ambush")
	var base: Dictionary = Compiler.compile_group(skill, raw, others)
	_expect(base.ok and cast.packets == base.packets and cast.recipe == base.recipe and cast.initial_count == base.initial_count, "Delivery conversion leaves old packets and final blast geometry intact")
	_near(cast.mana, base.mana * 1.25, "Final mana factor applied once")
	_near(cast.cooldown, base.cooldown, "Other cooldown factors stay unchanged")
	_expect(cast.trap_profile.size() == 7 and Rules.profile_error(cast.trap_profile).is_empty(), "Exact detached preview profile")
	_expect(not cast.snapshot.has("trap_profile") and cast.packets.direct.tags == ["hit", "spell", "area"], "Trap carrier never adds damage tags or snapshot executor")
	var expected: Dictionary = Damage.resolve(base.packets.direct, base.snapshot.modifiers)
	var actual: Dictionary = Damage.resolve(cast.packets.direct, cast.snapshot.modifiers)
	for type: String in expected.components:
		_near(actual.components[type], expected.components[type] * 0.85, "Primary component penalized once: " + type)
	_expect(cast.get("critical", {}) == base.get("critical", {}) and cast.get("leech", {}) == base.get("leech", {}), "Critical and spell leech admission retain existing rules")
	if base.has("burn_profile"):
		_near(cast.burn_profile.roles.direct.dps, base.burn_profile.roles.direct.dps * 0.85, "Burn derives from penalized primary fire exactly once")
	if base.has("shock_profile"):
		_expect(cast.shock_profile == base.shock_profile, "Shock policy remains independent of delivery")
	cast.trap_profile.maximum_traps = 99
	_expect(Compiler.compile_group(skill, raw, links).trap_profile.maximum_traps == 3, "Mutated preview cannot change future compilation")
