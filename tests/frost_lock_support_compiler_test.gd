extends SceneTree
## Focused support admission, frozen policy, cost and pre-v073 byte equivalence.
const Rules = preload("res://scripts/combat/frost_lock_support_rules.gd")
const Freeze = preload("res://scripts/combat/frost_lock_rules.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Data = preload("res://scripts/game_data.gd")
const OldCompiler = preload("res://docs/qa/v073-compiler/frozen/skill_compiler.gd")
const OldSupports = preload("res://docs/qa/v073-compiler/frozen/support_registry.gd")
var checks := 0
var failures := 0
var old_cases := 0
var compositions := 0
var completed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(734647)
	var expected := [randi(), randi(), randi()]
	seed(734647)
	_case(_admission, "admission")
	_case(_composition, "composition")
	_case(_boundary, "frozen snapshot boundary")
	_case(_old_bytes, "all old legal zero/single/pair groups")
	check([randi(), randi(), randi()] == expected, "Compiler and provider never consume global RNG")
	var report := {"checks":checks, "failures":failures, "old_byte_cases":old_cases, "frost_lock_compositions":compositions,
		"reference_commit":"70b75bc255c3f54c8365f959c046934e61759f6e"}
	var output := OS.get_environment("V073_COMPILER_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		file.close()
	print("Frost Lock support/compiler: %d checks, %d failures; %d old byte cases; %d compositions" % [checks, failures, old_cases, compositions])
	quit(1 if failures else 0)


func _case(callback: Callable, label: String) -> void:
	completed = false
	callback.call()
	check(completed, "Case completed without script errors: " + label)


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) <= 1.0e-10 * maxf(1.0, absf(expected)), label)


func snapshot(config: int = 1) -> Dictionary:
	var stats := {"damage":100.0}
	if config > 0:
		stats.merge({"spell_added_cold":13.0, "spell_added_lightning":11.0, "attack_added_physical":7.0,
			"global_increased":0.2, "area_increased":0.1, "spell_increased":0.3,
			"area_size_increased":0.25, "mana_cost_efficiency_increased":0.25, "mana_cost_increased":0.1,
			"crit_base_chance":0.5, "crit_base_multiplier":2.0, "fire_dot_multiplier":0.2, "burn_faster":0.25})
	if config == 2: stats.resolute_technique = 1.0
	return Combat.snapshot(stats, ["return_on_range", "explode_on_flight_end"])


func _admission() -> void:
	check(Rules.SAVE_VERSION == 47 and Rules.SKILLS == ["frost"], "Only native frost opens in schema47")
	var definition := Supports.get_definition("frost_lock")
	check(definition.name == "霜锁辅助" and definition.family == "frost_lock", "Exact identity, family and display name")
	check(Supports.definition_error(definition).is_empty() and Supports.is_program_support("frost_lock"), "Exact provider registered")
	definition.skills.clear()
	definition.operations[0].value = 0.0
	check(not Rules.definition_error(definition).is_empty() and Rules.SKILLS == ["frost"], "Provider metadata is detached")
	for skill: String in Data.SKILLS:
		check(Supports.compatibility_reason(skill, ["frost_lock"]).is_empty() == (skill == "frost"), "Exact admission: " + skill)
		check(Compiler.compile_group(skill, snapshot(), ["frost_lock"]).ok == (skill == "frost"), "Exact compiler admission: " + skill)
		check(Rules.compile_program(skill, []) == Program.empty(), "Unselected provider stays neutral: " + skill)
	for links: Array in [["frost_lock", "lingering_chill"], ["lingering_chill", "frost_lock"]]:
		var reason := Supports.compatibility_reason("frost", links)
		check(reason.contains("霜锁辅助") and reason.contains("寒意延长辅助") and reason.contains("不能同时"), "Explicit mutual exclusion in both orders")
		check(not Compiler.compile_group("frost", snapshot(), links).ok, "Incompatible pair cannot compile")
	for links: Variant in [null, true, "frost_lock", ["frost_lock", "frost_lock"], ["frost_lock", 1], ["unknown"]]:
		check(not Rules.compile_program("frost", links).error.is_empty(), "Malformed provider selection rejects")
		check(not Supports.compatibility_reason("frost", links).is_empty(), "Malformed registry selection rejects")
	check(not Supports.saved_links_reason("frost", ["frost_lock"], 46).is_empty() and Supports.saved_links_reason("frost", ["frost_lock"], 47).is_empty(), "Saved link gate opens only47")
	check(not Compiler.compile_skill("frost", snapshot(), ["frost_lock", "cold_focus", "efficiency"]).ok, "Legacy two-slot limit preserved")
	check(not Compiler.compile_group("frost", snapshot(), ["frost_lock", "cold_focus", "efficiency", "quickcast", "pierce", "focus"]).ok, "Sixth group support rejected")
	check(not Rules.compile_program("frost", ["frost_lock"], 3).error.is_empty(), "Unknown slot capacity rejected")
	var cast := Compiler.compile_group("frost", snapshot(0), ["frost_lock"])
	if check(cast.ok, "Single Frost Lock compiles"):
		near(cast.mana, 19.2, "Fixed base mana sixteen times1.20")
		check(cast.cooldown == 4.0 and cast.initial_count == 5 and cast.recipe.pierce == 2 and cast.recipe.slow == 3.0, "Native four-second cooldown, five pellets, two pierce and three-second slow preserved")
	completed = true


func _composition() -> void:
	_check_set(["frost_lock"])
	for other: String in Supports.SUPPORTS:
		if other == "frost_lock" or not Supports.compatibility_reason("frost", ["frost_lock", other], 5).is_empty(): continue
		_check_set(["frost_lock", other])
	_check_set(["frost_lock", "cold_focus", "efficiency", "pierce", "focus"])
	_check_set(["frost_lock", "quickcast", "swift_projectiles", "volley", "heavy_projectiles"])
	completed = true


func _check_set(links: Array) -> void:
	compositions += 1
	var raw := snapshot()
	var before := var_to_bytes([raw, links])
	var cast := Compiler.compile_group("frost", raw, links)
	if not check(cast.ok, "Legal Frost Lock composition: " + str(links)): return
	var reversed := links.duplicate()
	reversed.reverse()
	check(var_to_bytes(cast) == var_to_bytes(Compiler.compile_group("frost", raw, reversed)), "Canonical selection order")
	check(var_to_bytes([raw, links]) == before, "Compile preserves input bytes")
	var others := links.duplicate()
	others.erase("frost_lock")
	var base := Compiler.compile_group("frost", raw, others)
	check(base.ok and cast.recipe == base.recipe and cast.initial_count == base.initial_count and cast.packets == base.packets, "Carrier geometry and packet bases unchanged")
	near(cast.mana, base.mana * 1.20, "Mana factor applies exactly once")
	near(cast.cooldown, base.cooldown, "No Frost Lock cooldown modifier")
	var primary: Dictionary = Damage.resolve(cast.packets.projectile, cast.snapshot.modifiers)
	var old_primary: Dictionary = Damage.resolve(base.packets.projectile, base.snapshot.modifiers)
	for type: String in old_primary.components:
		near(float(primary.components.get(type, 0.0)), float(old_primary.components[type]) * 0.75, "Every primary component gets0.75: " + type)
	check(Damage.resolve(cast.packets.secondary, cast.snapshot.modifiers) == Damage.resolve(base.packets.secondary, base.snapshot.modifiers), "Independent secondary explosion unchanged")
	near(cast.cost_factors.support_mana, base.cost_factors.support_mana * 1.20, "Support cost trace includes factor")
	near(cast.cost_factors.final_mana, base.cost_factors.final_mana * 1.20, "Final cost trace includes factor")
	var profile: Dictionary = Freeze.PLAYER_POLICY.duplicate(true)
	profile.enabled = true
	check(cast.freeze_profile == profile and cast.snapshot.freeze_policy == Freeze.PLAYER_POLICY, "Exact detached preview and runtime freeze contracts")
	check(Freeze.policy_error(cast.snapshot.freeze_policy).is_empty(), "Frozen runtime policy accepted")
	cast.freeze_profile.duration_by_rarity.normal = 9.0
	check(cast.snapshot.freeze_policy == Freeze.PLAYER_POLICY, "Nested preview mutation cannot change frozen policy")
	cast.snapshot.freeze_policy.duration_by_rarity.boss = 9.0
	var fresh := Compiler.compile_group("frost", raw, links)
	check(fresh.freeze_profile == profile and fresh.snapshot.freeze_policy == Freeze.PLAYER_POLICY, "Outputs cannot mutate future compilation")


func _boundary() -> void:
	for key: String in ["freeze_policy", "freeze_profile"]:
		for value: Variant in [null, false, {}, Freeze.PLAYER_POLICY.duplicate(true)]:
			var raw := snapshot()
			raw[key] = value
			# Even a broken cost input must lose to compiler-owned policy rejection.
			raw.mana_cost_increased = NAN
			var before := var_to_bytes(raw)
			for links: Array in [[], ["frost_lock"]]:
				var cast := Compiler.compile_group("frost", raw, links)
				check(not cast.ok and cast.error.contains("已编译"), "Reserved policy rejected before cost compilation")
			check(not Compiler.compile_basic(raw).ok and var_to_bytes(raw) == before, "Basic also rejects injected policy and leaves input untouched")
	var cast := Compiler.compile_group("frost", snapshot(), ["frost_lock"])
	check(not Compiler.compile_group("frost", cast.snapshot, ["frost_lock"]).ok, "Compiled snapshot cannot be compiled again")
	completed = true


func _old_bytes() -> void:
	check(Supports.SUPPORTS.size() == OldSupports.SUPPORTS.size() + 1, "One support added to actual previous catalog")
	for skill: String in Data.SKILLS:
		var allowed: Array = OldSupports.supports_for_skill(skill)
		allowed.sort()
		var selections: Array = [[]]
		for first: int in allowed.size():
			selections.append([allowed[first]])
			for second: int in range(first + 1, allowed.size()):
				var pair: Array = [allowed[first], allowed[second]]
				if OldSupports.compatibility_reason(skill, pair).is_empty(): selections.append(pair)
		var group: Array = []
		for support: String in allowed:
			if group.size() == 5: break
			var candidate := group.duplicate()
			candidate.append(support)
			if OldSupports.compatibility_reason(skill, candidate, 5).is_empty(): group = candidate
		if group.size() > 2: selections.append(group)
		for config: int in 3:
			var raw := snapshot(config)
			check(var_to_bytes(Compiler.compile_basic(raw)) == var_to_bytes(OldCompiler.compile_basic(raw)), "Basic bytes identical to actual baseline")
			for links: Array in selections:
				old_cases += 1
				var old := OldCompiler.compile_group(skill, raw, links)
				var current := Compiler.compile_group(skill, raw, links)
				check(old.ok and current.ok and var_to_bytes(current) == var_to_bytes(old), "Old compile bytes preserved: %s/%s/%d" % [skill, links, config])
				check(var_to_bytes(Supports.compile_programs(skill, links, 5)) == var_to_bytes(OldSupports.compile_programs(skill, links, 5)), "Old support program bytes preserved")
				check(not current.has("freeze_profile") and not current.snapshot.has("freeze_policy"), "No freeze fields added without selected support")
	completed = true
