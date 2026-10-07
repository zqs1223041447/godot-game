extends SceneTree
## One focused gate for exact admission, all six-choice compositions and v093 bytes.
const Rules = preload("res://scripts/combat/encircling_cleave_support_rules.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Data = preload("res://scripts/game_data.gd")
const OldCompiler = preload("res://docs/qa/v094-encircling-cleave/compiler/frozen/skill_compiler.gd")
const OldSupports = preload("res://docs/qa/v094-encircling-cleave/compiler/frozen/support_registry.gd")
const OTHERS: Array[String] = ["breadth", "concentrate", "efficiency", "physical_focus", "quickcast"]
const EXPECTED_POLICY: Dictionary = {"enabled": true, "arc_degrees": 360.0, "base_arc_degrees": 180.0,
	"hit_multiplier": 0.75, "mana_multiplier": 1.25}
var checks: int = 0
var failures: int = 0
var compositions: int = 0
var permutations: int = 0
var old_cases: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(940052)
	var expected_rng: Array = [randi(), randi(), randi()]
	seed(940052)
	_case(_admission, "exact skills, registry, five slots and version gate")
	_case(_composition, "every legal ring composition and every selection order")
	_case(_boundaries, "compiled ownership, detached output and component scope")
	_case(_legacy_bytes, "frozen v093 compiler and all old legal groups")
	check([randi(), randi(), randi()] == expected_rng, "Compiler and providers preserve global RNG")
	var report: Dictionary = {"checks": checks, "failures": failures, "compositions": compositions,
		"permutations": permutations, "old_byte_cases": old_cases, "old_support_count": OldSupports.SUPPORTS.size(),
		"reference_commit": "c5690b933e7ed56210241e8124d45eefc5ee2596"}
	var destination: String = OS.get_environment("V094_COMPILER_REPORT")
	if not destination.is_empty():
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			check(false, "Compiler report destination is writable")
		else:
			file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
			file.close()
	print("Encircling cleave compiler: %d checks, %d failures; %d compositions; %d permutations; %d old byte cases" % [checks, failures, compositions, permutations, old_cases])
	quit(1 if failures else 0)


func _case(callback: Callable, label: String) -> void:
	completed = false
	callback.call()
	check(completed, "Case completed without script errors: " + label)


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
	return ok


func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) <= 1.0e-10 * maxf(1.0, absf(expected)), label)


func snapshot(config: int = 1) -> Dictionary:
	var stats: Dictionary = {"damage": 100.0}
	if config > 0:
		stats.merge({"attack_added_physical": 7.0, "attack_added_fire": 13.0,
			"spell_added_cold": 11.0, "spell_added_lightning": 17.0,
			"global_increased": 0.2, "area_increased": 0.1, "spell_increased": 0.3,
			"area_size_increased": 0.25, "melee_area_size_increased": 0.44,
			"mana_cost_efficiency_increased": 0.25, "mana_cost_increased": 0.1,
			"crit_base_chance": 0.5, "crit_base_multiplier": 2.0})
	if config == 2:
		stats.merge({"physical_to_fire_conversion": 0.4, "physical_to_cold_conversion": 0.4,
			"physical_to_lightning_conversion": 0.4, "resolute_technique": 1.0})
	return Combat.snapshot(stats, ["return_on_range", "explode_on_flight_end"])


func _admission() -> void:
	check(Data.SKILLS.size() == 10 and OldSupports.SUPPORTS.size() == 22 and Supports.SUPPORTS.size() == 23, "Exact current ten skills and one addition to twenty-two supports")
	check(Rules.SAVE_VERSION == 52 and Rules.SKILLS == ["cleave"] and Rules.POLICY == EXPECTED_POLICY, "Authoritative schema52 and fixed support policy")
	var definition: Dictionary = Supports.get_definition("encircling_cleave")
	check(definition.name == "环斩辅助" and definition.family == "encircling_cleave", "Exact support identity and display name")
	check(Supports.definition_error(definition).is_empty() and Supports.is_program_support("encircling_cleave"), "Provider metadata and program are registered")
	check(definition.operations == [{"op": "primary_hit_more", "value": -0.25}, {"op": "mana_multiplier", "value": 1.25}], "Only one primary-hit and one mana operation")
	definition.skills.clear()
	definition.operations[0].value = 0.0
	check(not Rules.definition_error(definition).is_empty() and Rules.SKILLS == ["cleave"], "Definition is detached from authority")
	check(Supports.get_definition("encircling_cleave").operations[0].value == -0.25, "Detached operation mutation cannot alter authority")
	for skill: String in Data.SKILLS:
		var allowed: bool = skill == "cleave"
		check(Supports.compatibility_reason(skill, ["encircling_cleave"]).is_empty() == allowed, "Exact registry eligibility: " + skill)
		check(Supports.supports_for_skill(skill).has("encircling_cleave") == allowed, "Exact selector eligibility: " + skill)
		check(Compiler.compile_group(skill, snapshot(), ["encircling_cleave"]).ok == allowed, "Exact compiler eligibility: " + skill)
		check(Rules.compile_program(skill, []) == Program.empty(), "Unselected provider stays neutral: " + skill)
		var old: Dictionary = Compiler.compile_group(skill, snapshot(), [])
		check(old.ok and not old.has("encircling_cleave_profile") and not old.snapshot.has("encircling_cleave_profile"), "Unselected cast gains no optional fields: " + skill)
	for invalid: Variant in [null, true, "encircling_cleave", ["encircling_cleave", "encircling_cleave"], ["encircling_cleave", 1], ["unknown"]]:
		check(not Rules.compile_program("cleave", invalid).error.is_empty(), "Malformed provider selection fails closed")
		check(not Supports.compatibility_reason("cleave", invalid).is_empty(), "Malformed registry selection fails closed")
	check(not Rules.compile_program("basic", ["encircling_cleave"]).error.is_empty(), "Basic attack cannot use this support")
	check(not Rules.compile_program("cleave", ["encircling_cleave"], 3).error.is_empty(), "Unknown slot count rejected")
	check(not Supports.saved_links_reason("cleave", ["encircling_cleave"], 51).is_empty(), "Schema51 rejects new saved support")
	check(Supports.saved_links_reason("cleave", ["encircling_cleave"], 52).is_empty(), "Schema52 accepts new saved support")
	check(not Compiler.compile_skill("cleave", snapshot(), ["encircling_cleave", "breadth", "physical_focus"]).ok, "Legacy two-slot call retains its capacity")
	var six: Array = OTHERS.duplicate()
	six.append("encircling_cleave")
	check(not Compiler.compile_group("cleave", snapshot(), six).ok, "Six compatible choices cannot fit in five slots")
	var available: Array = Supports.supports_for_skill("cleave")
	available.erase("encircling_cleave")
	available.sort()
	check(available == OTHERS, "Only the existing five cleave alternatives accompany ring support")
	var program: Dictionary = Rules.compile_program("cleave", ["encircling_cleave"])
	var expected: Dictionary = Program.empty()
	expected.modifiers.append(Program.primary_modifier("encircling_cleave", "cleave", -0.25))
	expected.mana_multiplier = 1.25
	check(program == expected, "Program uses one canonical primary modifier and leaves cooldown and recipe factors neutral")
	var cast: Dictionary = Compiler.compile_group("cleave", snapshot(0), ["encircling_cleave"])
	if check(cast.ok, "Base ring cast compiles"):
		check(cast.recipe.radius == 95.0 and cast.recipe.half_angle == PI, "Native95 radius and360-degree arc")
		check(cast.mana == 15.0 and cast.cooldown == 1.4, "Base twelve mana becomes15 and cooldown remains1.4")
		near(Damage.resolve(cast.packets.direct, cast.snapshot.modifiers).total, 210.0, "280-percent native damage becomes210-percent after one MORE")
	completed = true


func _composition() -> void:
	for mask: int in range(1 << OTHERS.size()):
		var links: Array = ["encircling_cleave"]
		for bit: int in OTHERS.size():
			if mask & (1 << bit): links.append(OTHERS[bit])
		if links.size() > Supports.GROUP_MAX_SUPPORTS: continue
		compositions += 1
		for config: int in 3:
			_check_set(links, config)
	check(compositions == 31 and permutations == 911, "All31 legal new-support subsets and all911 ordering permutations covered")
	completed = true


func _check_set(links: Array, config: int) -> void:
	var raw: Dictionary = snapshot(config)
	var before: PackedByteArray = var_to_bytes([raw, links])
	var cast: Dictionary = Compiler.compile_group("cleave", raw, links)
	if not check(cast.ok, "Legal composition: " + str(links)): return
	check(var_to_bytes([raw, links]) == before, "Compilation preserves all input bytes")
	var others: Array = links.duplicate()
	others.erase("encircling_cleave")
	var base: Dictionary = Compiler.compile_group("cleave", raw, others)
	if not check(base.ok, "Existing comparison group compiles"): return
	check(var_to_bytes(cast.packets) == var_to_bytes(base.packets) and cast.packets.keys() == ["direct"], "Only existing direct packet is compiled with original base and conversion")
	var comparable: Dictionary = cast.recipe.duplicate(true)
	comparable.half_angle = base.recipe.half_angle
	check(var_to_bytes(comparable) == var_to_bytes(base.recipe) and base.recipe.half_angle == PI / 2.0 and cast.recipe.half_angle == PI, "Angle is the only geometry change")
	near(cast.recipe.radius, 95.0 * sqrt((1.44 if links.has("breadth") else 1.0) * (0.64 if links.has("concentrate") else 1.0) * (1.69 if config > 0 else 1.0)), "Area support and source area remain final radius authority")
	near(cast.mana, base.mana * 1.25, "Mana factor occurs exactly once")
	near(cast.cooldown, base.cooldown, "Support adds no cooldown factor")
	var profile: Dictionary = EXPECTED_POLICY.duplicate(true)
	profile.radius = float(cast.recipe.radius)
	check(cast.encircling_cleave_profile == profile and not cast.snapshot.has("encircling_cleave_profile"), "Exact preview profile captures final radius without new runtime policy")
	var resolved: Dictionary = Damage.resolve(cast.packets.direct, cast.snapshot.modifiers)
	var old_resolved: Dictionary = Damage.resolve(base.packets.direct, base.snapshot.modifiers)
	check(resolved.has_all(["components", "total"]) and old_resolved.has_all(["components", "total"]) and not resolved.has("error") and not old_resolved.has("error"), "Both direct packets settle")
	for type: String in old_resolved.components:
		near(float(resolved.components.get(type, 0.0)), float(old_resolved.components[type]) * 0.75, "Native, added and converted component gets one0.75 factor: " + type)
	var without_modifier: Dictionary = cast.snapshot.duplicate(true)
	var count: int = 0
	for index: int in range(without_modifier.modifiers.size() - 1, -1, -1):
		if without_modifier.modifiers[index].get("id") == "support:encircling_cleave":
			count += 1
			check(without_modifier.modifiers[index] == Program.primary_modifier("encircling_cleave", "cleave", -0.25), "Original modifier identity and exact primary scope")
			without_modifier.modifiers.remove_at(index)
	check(count == 1 and var_to_bytes(without_modifier) == var_to_bytes(base.snapshot), "One support modifier is the only frozen snapshot change")
	if config > 0:
		near(cast.cost_factors.support_mana, base.cost_factors.support_mana * 1.25, "Resource trace captures support factor once")
		near(cast.cost_factors.final_mana, cast.mana, "Resource final cost matches actual mana")
	if config == 0:
		var orders: Array = []
		_permute(links, [], orders)
		var expected_bytes: PackedByteArray = var_to_bytes(cast)
		for order: Array in orders:
			permutations += 1
			check(var_to_bytes(Compiler.compile_group("cleave", raw, order)) == expected_bytes, "Every selection permutation preserves complete cast bytes")


func _permute(remaining: Array, prefix: Array, output: Array) -> void:
	if remaining.is_empty():
		output.append(prefix)
		return
	for index: int in remaining.size():
		var rest: Array = remaining.duplicate()
		var next: Array = prefix.duplicate()
		next.append(rest.pop_at(index))
		_permute(rest, next, output)


func _boundaries() -> void:
	var raw: Dictionary = snapshot(2)
	var cast: Dictionary = Compiler.compile_group("cleave", raw, ["encircling_cleave", "physical_focus"])
	if not check(cast.ok, "Boundary fixture compiles"): return
	var original: PackedByteArray = var_to_bytes(cast)
	var base: Dictionary = Compiler.compile_group("cleave", raw, ["physical_focus"])
	var basic: Dictionary = Compiler.compile_basic(raw)
	var secondary: Dictionary = Combat.secondary_packet(raw, "bolt")
	check(Damage.resolve(basic.packets.projectile, cast.snapshot.modifiers) == Damage.resolve(basic.packets.projectile, base.snapshot.modifiers), "Basic attack is outside support scope")
	check(Damage.resolve(secondary, cast.snapshot.modifiers) == Damage.resolve(secondary, base.snapshot.modifiers), "Independent explosion is outside support scope")
	check(not Compiler.compile_group("cleave", cast.snapshot, ["encircling_cleave"]).ok, "Compiled snapshot cannot receive support twice")
	check(not Compiler.compile_basic(cast.snapshot).ok, "Compiled cleave snapshot cannot become basic attack")
	for invalid: Variant in [null, false, {}, EXPECTED_POLICY.duplicate(true)]:
		var injected: Dictionary = snapshot()
		injected.encircling_cleave_profile = invalid
		var before: PackedByteArray = var_to_bytes(injected)
		for links: Array in [[], ["encircling_cleave"]]:
			var rejected: Dictionary = Compiler.compile_group("cleave", injected, links)
			check(not rejected.ok and rejected.error.contains("已编译"), "Injected compiled profile cannot bypass compiler ownership")
		check(not Compiler.compile_basic(injected).ok and var_to_bytes(injected) == before, "Invalid injection preserves inputs and fails basic compilation")
	var radius: float = cast.recipe.radius
	cast.encircling_cleave_profile.radius = 1.0
	cast.encircling_cleave_profile.hit_multiplier = 1.0
	check(cast.recipe.radius == radius and Rules.POLICY == EXPECTED_POLICY, "Preview mutation cannot change geometry or shared policy")
	cast.recipe.radius = 2.0
	cast.recipe.half_angle = 0.5
	cast.snapshot.modifiers.back().all_tags.clear()
	cast.packets.direct.tags.clear()
	cast.support_ids.clear()
	check(var_to_bytes(Compiler.compile_group("cleave", raw, ["encircling_cleave", "physical_focus"])) == original, "Recipe, modifiers, packets and selection outputs are detached from future casts")
	var program: Dictionary = Rules.compile_program("cleave", ["encircling_cleave"])
	program.modifiers[0].all_tags.clear()
	program.modifiers[0].skills.clear()
	check(Rules.compile_program("cleave", ["encircling_cleave"]).modifiers[0] == Program.primary_modifier("encircling_cleave", "cleave", -0.25), "Provider nested output is detached from canonical primary scope")
	completed = true


func _legacy_bytes() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v094-encircling-cleave/compiler/frozen_manifest.json"))
	check(manifest.base_commit == "c5690b933e7ed56210241e8124d45eefc5ee2596", "Oracle is the exact v093 base")
	for row: Dictionary in manifest.files:
		check(FileAccess.get_sha256("res://" + row.fixture) == row.fixture_sha256, "Frozen compiler/registry fixture digest: " + row.source)
	for support: String in OldSupports.SUPPORTS:
		check(var_to_bytes(Supports.get_definition(support)) == var_to_bytes(OldSupports.get_definition(support)), "Every old support definition retains exact bytes: " + support)
	for config: int in 3:
		var raw: Dictionary = snapshot(config)
		check(var_to_bytes(Compiler.compile_basic(raw)) == var_to_bytes(OldCompiler.compile_basic(raw)), "Basic cast keeps exact v093 bytes")
	for skill: String in Data.SKILLS:
		var allowed: Array = OldSupports.supports_for_skill(skill)
		allowed.sort()
		for mask: int in range(1 << allowed.size()):
			var links: Array = []
			for bit: int in allowed.size():
				if mask & (1 << bit): links.append(allowed[bit])
			if links.size() > 5: continue
			var previous_reason: String = OldSupports.compatibility_reason(skill, links, 5)
			check(Supports.compatibility_reason(skill, links, 5) == previous_reason, "Every old group admission retains exact reason")
			if not previous_reason.is_empty(): continue
			check(var_to_bytes(Supports.compile_programs(skill, links, 5)) == var_to_bytes(OldSupports.compile_programs(skill, links, 5)), "Old group program retains exact bytes")
			for config: int in 3:
				old_cases += 1
				var raw: Dictionary = snapshot(config)
				var before: PackedByteArray = var_to_bytes(raw)
				var old: Dictionary = OldCompiler.compile_group(skill, raw, links)
				var current: Dictionary = Compiler.compile_group(skill, raw, links)
				check(old.ok and current.ok and var_to_bytes(current) == var_to_bytes(old), "Every old zero-to-five group retains all compiled bytes: %s/%s/%d" % [skill, links, config])
				check(not current.has("encircling_cleave_profile") and var_to_bytes(raw) == before, "Old selection adds no profile and preserves snapshot bytes")
				if config == 0:
					var reverse: Array = links.duplicate()
					reverse.reverse()
					check(var_to_bytes(Compiler.compile_group(skill, raw, reverse)) == var_to_bytes(old), "Old group reversed order retains exact v093 bytes")
	completed = true
