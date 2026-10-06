extends SceneTree
## Short pure v061 contract test. The complete old compiler dependency closure
## is independently frozen from b389993, never routed through the new rules.
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Critical = preload("res://scripts/combat/critical_strike_rules.gd")
const Runtime = preload("res://scripts/combat/critical_strike_runtime.gd")
const Attack = preload("res://scripts/combat/attack_hit_rules.gd")
const Resolute = preload("res://scripts/combat/resolute_technique_rules.gd")
const OldCombat = preload("res://docs/qa/v061-rules/frozen/scripts/combat/combat_data.gd")
const OldCompiler = preload("res://docs/qa/v061-rules/frozen/scripts/combat/skill_compiler.gd")
const OldCritical = preload("res://docs/qa/v061-rules/frozen/scripts/combat/critical_strike_rules.gd")
const OldRuntime = preload("res://docs/qa/v061-rules/frozen/scripts/combat/critical_strike_runtime.gd")
const OldAttack = preload("res://docs/qa/v061-rules/frozen/scripts/combat/attack_hit_rules.gd")
const SKILLS = ["tornado", "bolt", "frost", "shade_bolt", "nova", "meteor", "chain", "cleave", "dash", "ward"]
const TAGS = [["hit", "attack", "projectile"], ["hit", "attack", "melee", "area"], ["hit", "spell", "projectile"], ["hit", "spell", "area"], ["hit", "spell", "chain"], []]
var checks := 0
var failures := 0
var sections: Dictionary = {}
var completed := false


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func same(actual: Variant, expected: Variant, label: String) -> void:
	check(var_to_bytes(actual) == var_to_bytes(expected), label)


func section(test: Callable) -> void:
	var before := checks
	completed = false
	test.call()
	check(completed, "Section finished without a script exception: " + test.get_method())
	sections[test.get_method()] = checks - before


func _initialize() -> void:
	for test: Callable in [flags, critical_validation, compile_coverage, attack_admission, private_rng, isolation]:
		section(test)
	var report_path: String = OS.get_environment("RESOLUTE_RULES_REPORT")
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		check(file != null, "Result report opened")
		if file != null:
			file.store_string(JSON.stringify({"checks": checks, "failures": failures, "sections": sections,
				"base_commit": "b389993ed7f7a90f4043c668704583d44b22f343",
				"scope": "Pure policy/compiler/attack/actual private critical RNG; no main, model, save, UI or Windows claims"}, "\t", true, true))
	print("Resolute technique pure rules: %d checks, %d failures; %s" % [checks, failures, JSON.stringify(sections)])
	quit(1 if failures else 0)


func stats() -> Dictionary:
	return {"damage": 24.0, "crit_base_chance": 0.05, "crit_base_multiplier": 1.5,
		"crit_chance_increased": 0.2, "attack_crit_chance_increased": 0.4,
		"spell_crit_chance_increased": 0.3, "melee_crit_chance_increased": 0.6,
		"projectile_attack_crit_chance_increased": 0.8, "crit_multiplier_add": 0.1,
		"spell_crit_multiplier_add": 0.2, "melee_crit_multiplier_add": 0.4,
		"projectile_attack_crit_multiplier_add": 0.6, "attack_added_physical": 3.0,
		"spell_added_lightning": 2.0, "physical_increased": 0.15}


func blade() -> Dictionary:
	return {"stage": "weapon_local", "item_id": "gear_000001", "base_id": "forgeblade",
		"base": {"physical": 4.0}, "flat": {"physical": 0.0}, "increased": {"physical": 0.0}, "sources": []}


func flags() -> void:
	var old: Dictionary = OldCombat.snapshot(stats(), [])
	same(Combat.snapshot(stats(), []), old, "Absent flag preserves complete snapshot bytes")
	for value: Variant in [0, 0.0, -0.0, 1, 1.0]:
		var input := stats(); input.resolute_technique = value
		var snap := Combat.snapshot(input, [])
		check(Resolute.snapshot_error(input).is_empty(), "Only finite numeric zero/one are valid")
		if float(value) == 0.0:
			same(snap, old, "Explicit numeric zero omits flag and preserves complete snapshot bytes")
			check(not Resolute.active(snap) and Resolute.compiled_profile(snap).is_empty(), "Zero has no policy")
		else:
			check(snap.resolute_technique is float and snap.resolute_technique == 1.0, "Enabled snapshot canonicalizes numeric one")
			check(Resolute.active(snap) and Resolute.compiled_profile(snap) == {"id": "resolute_technique", "hits_cannot_be_evaded": true, "cannot_deal_critical_strikes": true}, "One indivisible policy exposes both effects")
	for value: Variant in [true, false, "1", "0", null, [], {}, NAN, INF, -INF, -1, 2, 0.5, 1.00000001]:
		var input := stats(); input.resolute_technique = value
		var snap := Combat.snapshot(input, [])
		check(snap.has("resolute_technique") and not Resolute.snapshot_error(snap).is_empty(), "Malformed flag survives snapshot creation for explicit rejection")
		check(not Compiler.compile_basic(snap).ok and not Compiler.compile_group("nova", snap, []).ok, "Both compiler entries reject malformed flag")
	var invalid_nested: Dictionary = {"resolute_technique": {"bad": [1]}}
	var detached := Combat.snapshot(invalid_nested, [])
	invalid_nested.resolute_technique.bad[0] = 2
	check(detached.resolute_technique.bad[0] == 1, "Even rejected mutable flag data is detached from caller")
	completed = true


func critical_validation() -> void:
	var raw := Combat.snapshot(stats(), [])
	var malformed: Array = []
	for key: String in ["base_chance", "base_multiplier", "crit_chance_increased", "crit_multiplier_add"]:
		for value: Variant in [true, "0", NAN, INF, -1.0]:
			var item := raw.duplicate(true); item.critical_modifiers[key] = value; malformed.append(item)
	for value: Variant in [{}, [], {"base_chance": 0.1}, {"base_chance": 0.1, "base_multiplier": 1.5, "unknown": 0.0}]:
		var item := raw.duplicate(true); item.critical_modifiers = value; malformed.append(item)
	var derived := raw.duplicate(true)
	derived.critical_modifiers.base_multiplier = 1000.0
	derived.critical_modifiers.crit_multiplier_add = 1000000.0
	malformed.append(derived)
	for item: Dictionary in malformed:
		var expected: Dictionary = OldCritical.compile(item, ["hit", "attack", "projectile"], true)
		check(not expected.ok, "Frozen old critical input/derived validation rejects fixture")
		item.resolute_technique = 1.0
		same(Critical.compile(item, ["hit", "attack", "projectile"], true), expected, "Critical ban cannot conceal original input or derived error")
		check(not Compiler.compile_basic(item).ok, "Compiler propagates old critical failure despite keystone")
	var broken := raw.duplicate(true); broken.base_damage = -1.0
	var old_error: Dictionary = OldCompiler.compile_basic(broken)
	broken.resolute_technique = "invalid"
	same(Compiler.compile_basic(broken), old_error, "Old snapshot validation takes precedence over invalid new flag")
	for tags: Array in TAGS:
		var expected: Dictionary = OldCritical.compile(raw, tags, true)
		same(Critical.compile(raw, tags, true), expected, "Absent flag preserves complete critical rule result")
		var zero := raw.duplicate(true); zero.resolute_technique = 0.0
		same(Critical.compile(zero, tags, true), expected, "Zero flag preserves complete critical rule result")
		var enabled := raw.duplicate(true); enabled.resolute_technique = 1.0
		var actual := Critical.compile(enabled, tags, true)
		check(actual.ok, "Valid critical profiles with keystone compile")
		for role: String in actual.critical:
			check(actual.critical[role].chance == 0.0 and actual.critical[role].multiplier == expected.critical[role].multiplier, "All hit scopes retain validated latent multiplier but lose critical chance")
			for sample: float in [0.0, 0.5, 0.999999999]:
				check(Critical.roll(actual.critical[role], sample) == {"ok": true, "error": "", "critical": false, "multiplier": 1.0, "chance": 0.0}, "Actual roll never critical, even at sample zero")
	var no_modifiers := Combat.snapshot({"damage": 20.0, "resolute_technique": 1.0}, [])
	check(Critical.compile(no_modifiers, ["hit", "attack"], true).critical == {"primary": {"chance": 0.0, "multiplier": 1.5}, "secondary": {"chance": 0.0, "multiplier": 1.5}}, "Keystone without critical sources still has explicit zero profiles")
	completed = true


func cast(raw: Dictionary, skill: String, supports: Array, old: bool) -> Dictionary:
	if skill == "basic":return OldCompiler.compile_basic(raw) if old else Compiler.compile_basic(raw)
	return OldCompiler.compile_group(skill, raw, supports) if old else Compiler.compile_group(skill, raw, supports)


func compile_coverage() -> void:
	for source: Dictionary in [{"damage": 18.0}, stats()]:
		var old_raw: Dictionary = OldCombat.snapshot(source, ["return_on_range", "explode_on_flight_end"])
		var current_raw := Combat.snapshot(source, ["return_on_range", "explode_on_flight_end"])
		var skill_rows: Array = SKILLS.duplicate(); skill_rows.append_array(["basic", "basic_melee"])
		for row: String in skill_rows:
			var old_input := old_raw.duplicate(true); var input := current_raw.duplicate(true)
			var skill: String = "basic" if row == "basic_melee" else row
			if row == "basic_melee":old_input.weapon_profile = blade(); input.weapon_profile = blade()
			var support_ids: Array = ["ignite"] if skill == "meteor" else ["shock"] if skill == "bolt" else []
			var expected := cast(old_input, skill, support_ids, true)
			check(expected.ok, "Independent frozen compiler accepts " + row)
			same(cast(input, skill, support_ids, false), expected, "Complete no-keystone cast bytes match frozen old compiler: " + row)
			var zero := input.duplicate(true); zero.resolute_technique = 0.0
			same(cast(zero, skill, support_ids, false), expected, "Raw explicit-zero snapshot produces original complete cast bytes: " + row)
			input.resolute_technique = 1.0
			var before := var_to_bytes(input)
			var enabled := cast(input, skill, support_ids, false)
			check(enabled.ok and enabled.hit_policy == Resolute.POLICY and enabled.snapshot.resolute_technique == 1.0, "Frozen cast owns flag and exposes indivisible presentation policy: " + row)
			check(var_to_bytes(input) == before, "Compilation does not mutate input: " + row)
			same(enabled.packets, expected.packets, "Keystone preserves all base packets: " + row)
			same(enabled.recipe, expected.recipe, "Keystone preserves reach/delivery recipe: " + row)
			if skill != "basic":check(enabled.mana == expected.mana and enabled.cooldown == expected.cooldown, "Keystone preserves payment and cooldown: " + row)
			if skill in ["dash", "ward"]:
				check(not enabled.has("critical") and not enabled.snapshot.has("critical"), "Utility remains without a hit critical profile")
			else:
				check(enabled.critical == enabled.snapshot.critical, "Preview and actual frozen critical profiles agree: " + row)
				for role: String in enabled.critical:
					check(enabled.critical[role].chance == 0.0, "Every primary/independent secondary chance is zero: " + row + "/" + role)
				check(enabled.critical.has("secondary") == enabled.packets.has("secondary"), "Secondary critical profile follows actual secondary packet: " + row)
			check(not cast(enabled.snapshot, skill, support_ids, false).ok, "Frozen cast refuses double compilation: " + row)
	completed = true


func attack_admission() -> void:
	for accuracy: float in [0.0, 100.0, 1000000.0]:
		for evasion: float in [0.0, 320.0, 1000000000000.0]:
			for entropy: float in [0.0, 50.0, 99.999999]:
				var expected: Dictionary = OldAttack.resolve(accuracy, evasion, entropy)
				same(Attack.resolve(accuracy, evasion, entropy), expected, "Default attack return bytes match independent frozen rules")
				same(Attack.resolve(accuracy, evasion, entropy, false), expected, "Explicit false attack return bytes match independent frozen rules")
				var hit := Attack.resolve(accuracy, evasion, entropy, true)
				same(hit, {"ok": true, "hit": true, "chance": 1.0, "entropy": entropy}, "Cannot evade always hits and preserves exact entropy including zero")
				same(Attack.resolve(accuracy, evasion, hit.entropy), expected, "Next ordinary hit sees untouched defender entropy")
	for row: Array in [[-1.0, 0.0, 50.0], [0.0, -1.0, 50.0], [NAN, 0.0, 50.0], [0.0, INF, 50.0], [0.0, 0.0, NAN], [0.0, 0.0, INF], [0.0, 0.0, -0.01], [0.0, 0.0, 100.0]]:
		var expected: Dictionary = OldAttack.resolve(row[0], row[1], row[2])
		check(not expected.ok, "Invalid legacy attack fixture is rejected")
		same(Attack.resolve(row[0], row[1], row[2], true), expected, "Cannot evade still rejects invalid accuracy/evasion/entropy with original return")
	completed = true


func private_rng() -> void:
	var old_runtime := OldRuntime.new(); var runtime := Runtime.new()
	old_runtime.reset(31961); runtime.reset(31961)
	var raw := Combat.snapshot(stats(), [])
	var old_cast: Dictionary = OldCompiler.compile_basic(OldCombat.snapshot(stats(), []))
	var current := Compiler.compile_basic(raw)
	for index: int in range(16):
		var role: String = "primary" if index % 2 == 0 else "secondary"
		same(runtime.freeze(current.snapshot, role), old_runtime.freeze(old_cast.snapshot, role), "Absent keystone actual frozen rolls equal independent old runtime")
		same(runtime.checkpoint(), old_runtime.checkpoint(), "Absent keystone preserves actual private RNG state/draws/events")
	check(runtime.draws == 16 and runtime.events == 16, "Ordinary critical profiles still take one private sample per event")
	var zero_raw := raw.duplicate(true); zero_raw.resolute_technique = 0.0
	var zero := Compiler.compile_basic(zero_raw)
	same(runtime.freeze(zero.snapshot), old_runtime.freeze(old_cast.snapshot), "Zero keystone continues exact old private stream")
	same(runtime.checkpoint(), old_runtime.checkpoint(), "Zero keystone preserves actual private checkpoint")
	var on_raw := raw.duplicate(true); on_raw.resolute_technique = 1.0
	var enabled := Compiler.compile_basic(on_raw)
	var before := runtime.checkpoint()
	for role: String in ["primary", "secondary"]:
		var inherited: Dictionary = enabled.snapshot.duplicate(true)
		inherited.critical_roll = {"critical": true, "multiplier": 9.0, "chance": 1.0}
		var input_bytes := var_to_bytes(inherited)
		var frozen: Dictionary = runtime.freeze(inherited, role)
		check(frozen.ok and not frozen.snapshot.has("critical_roll"), "Zero chance clears inherited positive critical roll: " + role)
		same(runtime.checkpoint(), before, "Enabled profile consumes zero private samples and zero critical events: " + role)
		check(var_to_bytes(inherited) == input_bytes, "Clearing inherited roll leaves caller immutable")
		check(not runtime.freeze(enabled.snapshot, role).snapshot.has("critical_roll"), "Fresh enabled freeze has no critical roll")
		same(runtime.checkpoint(), before, "Fresh enabled profile also consumes zero private samples")
	same(runtime.freeze(current.snapshot), old_runtime.freeze(old_cast.snapshot), "Later ordinary cast resumes original private stream after zero-draw casts")
	same(runtime.checkpoint(), old_runtime.checkpoint(), "Future private checkpoint remains equal after enabled freeze bypass")
	var guaranteed := stats(); guaranteed.crit_base_chance = 1.0
	var all := Compiler.compile_basic(Combat.snapshot(guaranteed, []))
	var draws_before: int = runtime.draws
	check(runtime.freeze(all.snapshot).snapshot.critical_roll.critical and runtime.draws == draws_before, "Old guaranteed critical behavior still emits critical without a random sample")
	completed = true


func isolation() -> void:
	var live := stats()
	var old_raw := Combat.snapshot(live, [])
	var old_cast := Compiler.compile_group("tornado", old_raw, [])
	var old_bytes := var_to_bytes(old_cast)
	live.resolute_technique = 1.0
	var enabled_raw := Combat.snapshot(live, [])
	var enabled := Compiler.compile_group("tornado", enabled_raw, [])
	var enabled_bytes := var_to_bytes(enabled)
	live.resolute_technique = 0.0; live.crit_base_chance = 1.0
	check(var_to_bytes(old_cast) == old_bytes and not Resolute.active(old_cast.snapshot), "Allocating later cannot change preexisting flight snapshot")
	check(var_to_bytes(enabled) == enabled_bytes and Resolute.active(enabled.snapshot), "Refund or gear-source change cannot change enabled flight snapshot")
	var child: Dictionary = enabled.snapshot.duplicate(true)
	child.modifiers.append({"id": "child_test"})
	check(Resolute.active(child) and child.critical.primary.chance == 0.0 and enabled.snapshot.modifiers.size() + 1 == child.modifiers.size(), "Detached descendant carries same flag/zero profile")
	var policy := Resolute.compiled_profile(enabled.snapshot); policy.hits_cannot_be_evaded = false
	check(Resolute.compiled_profile(enabled.snapshot).hits_cannot_be_evaded and Resolute.POLICY.hits_cannot_be_evaded, "Policy getter returns independent dictionary")
	enabled.hit_policy.cannot_deal_critical_strikes = false
	enabled.critical.primary.chance = 1.0
	check(enabled.snapshot.critical.primary.chance == 0.0 and Resolute.active(enabled.snapshot), "Presentation result mutation cannot alter authoritative frozen critical or flag")
	enabled_raw.resolute_technique = 0.0; enabled_raw.critical_modifiers.base_chance = 1.0
	check(enabled.snapshot.resolute_technique == 1.0 and enabled.snapshot.critical_modifiers.base_chance == 0.05, "Caller input mutation after compile cannot alter cast")
	completed = true
