extends SceneTree
## Focused pure leech contracts; no scene, runtime pool, or imported asset needed.
const Rules = preload("res://scripts/combat/leech_rules.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const EXPECTED_STATS: Array[String] = [
	"attack_life_leech", "attack_mana_leech", "physical_attack_life_leech", "physical_attack_mana_leech",
	"life_leech_rate_increased", "mana_leech_rate_increased", "life_leech_max_rate_increased", "mana_leech_max_rate_increased",
]
const EXPECTED_FIELDS: Array[String] = ["attack_fraction", "physical_attack_fraction", "instance_amount_cap", "instance_rate", "total_rate_cap"]
const INVALID_NUMBERS: Array = [null, true, false, "0.1", [], {}, NAN, INF, -INF, -0.0001]
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(400504)
	var expected_random: Array = [randi(), randi(), randi()]
	seed(400504)
	_case(_test_current_profile, "current profile formulas and bounds")
	_case(_test_from_stats, "legacy omission and malformed preservation")
	_case(_test_snapshot, "strict raw snapshot and compile validation")
	_case(_test_profile_schema, "exact compiled profile schema")
	_case(_test_hit_math, "actual typed damage, shield, overkill, and armour")
	_case(_test_tag_scopes, "attack hit admission and excluded event types")
	_case(_test_settlement_validation, "resolved settlement validation")
	_case(_test_overflow, "overflow rejected before caps")
	_case(_test_no_mutation, "detached values and stable ordering")
	_expect([randi(), randi(), randi()] == expected_random, "All operations preserve the global random stream")
	print("Leech rules: %d checks, %d failures" % [checks, failures])
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
	_expect(is_finite(value) and absf(value - expected) <= maxf(1.0, absf(expected)) * 1.0e-12, "%s (actual %.12f, expected %.12f)" % [label, value, expected])


func _stats() -> Dictionary:
	return {"max_health": 1000.0, "max_mana": 400.0,
		"attack_life_leech": 0.05, "attack_mana_leech": 0.04,
		"physical_attack_life_leech": 0.10, "physical_attack_mana_leech": 0.06,
		"life_leech_rate_increased": 0.5, "mana_leech_rate_increased": 1.0,
		"life_leech_max_rate_increased": 0.25, "mana_leech_max_rate_increased": 0.75}


func _leech(stats: Dictionary = {}) -> Dictionary:
	return Rules.compile({"leech_modifiers": Rules.from_stats(_stats() if stats.is_empty() else stats)}, ["attack", "hit"]).leech


func _packet() -> Dictionary:
	return {"tags": ["hit", "attack", "projectile"], "base": {"physical": 600.0, "fire": 400.0}, "role": "parent", "skill_id": "tornado"}


func _settlement() -> Dictionary:
	return {"ok": true, "reason": "", "components": {"physical": 60.0, "fire": 40.0},
		"damage_total": 100.0, "shield_spent": 20.0, "health_lost": 30.0, "overkill": 50.0}


func _test_current_profile() -> void:
	_expect(Rules.STAT_KEYS == EXPECTED_STATS, "Eight stable supported leech stat names")
	var current: Dictionary = Rules.profile(_stats())
	_expect(current.ok and current.reason == "" and current.size() == 4, "Current profile uses exact success wrapper")
	var leech: Dictionary = {"health": current.health, "mana": current.mana}
	_expect(Rules.profile_error(leech).is_empty(), "Current resource payload is a valid compiled profile")
	_near(current.health.attack_fraction, 0.05, "Life amount uses attack fraction")
	_near(current.health.physical_attack_fraction, 0.10, "Life physical amount fraction")
	_near(current.health.instance_amount_cap, 100.0, "Life instance amount cap is ten percent of maximum")
	_near(current.health.instance_rate, 30.0, "Life instance rate is two percent times one plus rate increase")
	_near(current.health.total_rate_cap, 250.0, "Life total rate cap is twenty percent times one plus cap increase")
	_near(current.mana.attack_fraction, 0.04, "Mana amount uses attack fraction")
	_near(current.mana.physical_attack_fraction, 0.06, "Mana physical amount fraction")
	_near(current.mana.instance_amount_cap, 40.0, "Mana has its own maximum and instance cap")
	_near(current.mana.instance_rate, 16.0, "Mana has its own increased instance rate")
	_near(current.mana.total_rate_cap, 140.0, "Mana has its own total rate cap increase")
	var zero: Dictionary = Rules.profile({"max_health": 100, "max_mana": 50, "damage": 999})
	_expect(zero.ok and zero.health.attack_fraction == 0.0 and zero.mana.physical_attack_fraction == 0.0, "No amount stat supplies no base leech")
	_expect(zero.health.instance_rate == 2.0 and zero.mana.instance_rate == 1.0, "Integer maxima produce unrounded scalar rates")
	var altered: Dictionary = _stats()
	altered.life_leech_rate_increased = 3.0
	altered.life_leech_max_rate_increased = 5.0
	var other: Dictionary = Rules.profile(altered)
	_expect(other.health.instance_amount_cap == current.health.instance_amount_cap, "Rate and rate-cap increases cannot change instance amount cap")
	_expect(other.mana == current.mana, "Life rate stats cannot affect mana")
	for key: String in EXPECTED_STATS + ["max_health", "max_mana"]:
		for invalid: Variant in INVALID_NUMBERS:
			var bad: Dictionary = _stats()
			bad[key] = invalid
			var rejected: Dictionary = Rules.profile(bad)
			_expect(not rejected.ok and not rejected.reason.is_empty() and rejected.health.is_empty() and rejected.mana.is_empty(), "Invalid current value fails atomically: " + key)
	for key: String in ["max_health", "max_mana"]:
		for zero_value: Variant in [0, 0.0, -0.0]:
			var bad: Dictionary = _stats()
			bad[key] = zero_value
			_expect(not Rules.profile(bad).ok, "Maximum must be positive: " + key)
		var missing: Dictionary = _stats()
		missing.erase(key)
		_expect(not Rules.profile(missing).ok, "Current profile requires maximum: " + key)
	for key: String in EXPECTED_STATS:
		var unbounded: Dictionary = _stats()
		unbounded[key] = 1000000000.0
		_expect(Rules.profile(unbounded).ok, "No artificial gameplay clamp for finite stat: " + key)
	completed = true


func _test_from_stats() -> void:
	for stats: Dictionary in [{}, {"damage": 100}, {"life_leech": 0.5}, {"max_health": 1000, "max_mana": 400}, {"life_leech_rate_increased": 4}, {"mana_leech_max_rate_increased": 4}]:
		_expect(Rules.from_stats(stats).is_empty(), "No positive amount means no optional snapshot field")
	var zeros: Dictionary = {"max_health": 1000, "max_mana": 400}
	for key: String in EXPECTED_STATS:
		zeros[key] = -0.0
	_expect(Rules.from_stats(zeros).is_empty(), "All numeric zeros preserve snapshot absence")
	zeros.life_leech_rate_increased = 99.0
	zeros.mana_leech_max_rate_increased = 99.0
	_expect(Rules.from_stats(zeros).is_empty(), "Valid rate-only changes preserve snapshot absence")
	for key: String in EXPECTED_STATS + ["max_health", "max_mana"]:
		for invalid: Variant in INVALID_NUMBERS:
			var bad: Dictionary = {key: invalid}
			var raw: Dictionary = Rules.from_stats(bad)
			_expect(raw.has(key) and typeof(raw[key]) == typeof(invalid), "Malformed source keeps field and type: " + key)
			_expect(not Rules.error({"leech_modifiers": raw}).is_empty(), "Malformed amount/rate/cap/max cannot disappear: " + key)
	for key: String in Rules.AMOUNT_KEYS:
		var stats: Dictionary = {"max_health": 1000, "max_mana": 400, key: 0.02, "damage": 999, "crit_base_chance": 0.05}
		var raw: Dictionary = Rules.from_stats(stats)
		_expect(raw.size() == 10 and raw[key] == 0.02, "Active snapshot carries both maxima and all eight canonical stats")
		_expect(not raw.has("damage") and not raw.has("crit_base_chance"), "Leech does not capture unrelated or old critical fields")
		_expect(Rules.error({"leech_modifiers": raw}).is_empty(), "Each amount field independently opts in")
	var missing_max: Dictionary = Rules.from_stats({"attack_life_leech": 0.01})
	_expect(missing_max.has_all(["max_health", "max_mana"]) and not Rules.error({"leech_modifiers": missing_max}).is_empty(), "Active amount cannot silently invent missing maxima")
	var nested: Dictionary = {"attack_life_leech": {"bad": [1]}, "mana_leech_rate_increased": [{"bad": 2}]}
	var detached: Dictionary = Rules.from_stats(nested)
	detached.attack_life_leech.bad[0] = 999
	detached.mana_leech_rate_increased[0].bad = 999
	_expect(nested.attack_life_leech.bad[0] == 1 and nested.mana_leech_rate_increased[0].bad == 2, "Malformed nested values are copied deeply")
	completed = true


func _test_snapshot() -> void:
	_expect(Rules.error({}).is_empty(), "Absent optional snapshot field is valid")
	_expect(Rules.compile({}, ["attack", "hit"]) == {"ok": true, "error": "", "leech": {}}, "Legacy compilation emits no leech")
	for invalid: Variant in [null, true, false, 0, 1.0, [], "", {}]:
		_expect(not Rules.error({"leech_modifiers": invalid}).is_empty(), "Present raw field must be a nonempty dictionary")
	for missing: String in ["max_health", "max_mana"]:
		var raw: Dictionary = _stats()
		raw.erase(missing)
		_expect(not Rules.error({"leech_modifiers": raw}).is_empty(), "Raw modifiers require maxima")
	for key: Variant in ["unknown", "life_leech", "base_amount", "total_rate_cap", false, 2, &"attack_life_leech"]:
		var raw: Dictionary = {"max_health": 1000, "max_mana": 400}
		raw[key] = 0.1
		_expect(not Rules.error({"leech_modifiers": raw}).is_empty(), "Unknown, legacy, and non-String raw keys reject")
	for key: String in EXPECTED_STATS + ["max_health", "max_mana"]:
		for invalid: Variant in INVALID_NUMBERS:
			var raw: Dictionary = _stats()
			raw[key] = invalid
			for tags: Array in [["attack", "hit"], ["spell", "hit"], ["utility"], []]:
				var compiled: Dictionary = Rules.compile({"leech_modifiers": raw}, tags)
				_expect(not compiled.ok and not compiled.error.is_empty() and compiled.leech.is_empty(), "Malformed raw validates before any scope exclusion: " + key)
	var empty_amount: Dictionary = {"max_health": 1000, "max_mana": 400, "life_leech_rate_increased": 10}
	_expect(Rules.error({"leech_modifiers": empty_amount}).is_empty(), "Explicit valid rate-only raw modifiers validate")
	_expect(Rules.compile({"leech_modifiers": empty_amount}, ["attack", "hit"]).leech.is_empty(), "Explicit rate-only raw modifiers emit no compiled profile")
	var compiled: Dictionary = Rules.compile({"leech_modifiers": _stats(), "unrelated_snapshot_data": true}, ["attack", "hit"])
	_expect(compiled.ok and compiled.leech.size() == 2 and Rules.profile_error(compiled.leech).is_empty(), "Compiled leech contains exactly health and mana")
	_expect(not compiled.leech.has("ok") and not compiled.leech.has("reason"), "Current-profile wrapper is stripped when compiling")
	for resource: String in ["health", "mana"]:
		_expect(compiled.leech[resource].size() == 5, "Each compiled resource contains only the five resolved fields")
	completed = true


func _test_profile_schema() -> void:
	var leech: Dictionary = _leech()
	_expect(Rules.profile_error(leech).is_empty(), "Exact compiled profile validates")
	_expect(not Rules.profile_error(Rules.profile(_stats())).is_empty(), "Current-profile wrapper is not accepted as a compiled profile")
	for resource: String in ["health", "mana"]:
		var missing: Dictionary = leech.duplicate(true)
		missing.erase(resource)
		_expect(not Rules.profile_error(missing).is_empty(), "Both resource profiles are required")
		for invalid: Variant in [null, true, 1, [], "", {}]:
			var malformed: Dictionary = leech.duplicate(true)
			malformed[resource] = invalid
			_expect(not Rules.profile_error(malformed).is_empty(), "Resource profile must be a dictionary of exact shape")
		for key: String in EXPECTED_FIELDS:
			var malformed: Dictionary = leech.duplicate(true)
			malformed[resource].erase(key)
			_expect(not Rules.profile_error(malformed).is_empty(), "Required resolved field: " + key)
			for invalid: Variant in INVALID_NUMBERS:
				malformed = leech.duplicate(true)
				malformed[resource][key] = invalid
				_expect(not Rules.profile_error(malformed).is_empty(), "Resolved field rejects invalid number: " + key)
		for extra: Variant in ["unknown", "ok", 1, &"attack_fraction"]:
			var malformed: Dictionary = leech.duplicate(true)
			if extra is StringName:
				malformed[resource].erase("attack_fraction")
			malformed[resource][extra] = 0.05
			_expect(not Rules.profile_error(malformed).is_empty(), "Unknown and non-String resolved fields reject")
		for key: String in ["instance_amount_cap", "instance_rate", "total_rate_cap"]:
			for zero: Variant in [0, 0.0, -0.0]:
				var malformed: Dictionary = leech.duplicate(true)
				malformed[resource][key] = zero
				_expect(not Rules.profile_error(malformed).is_empty(), "Zero rate/capacity rejects: " + key)
				_assert_plan_failure(Rules.plan_hit(malformed, _packet(), _settlement()), "Zero rate/capacity cannot create a plan")
	var extra_top: Dictionary = leech.duplicate(true)
	extra_top.extra = 1
	_expect(not Rules.profile_error(extra_top).is_empty(), "Unknown top profile key rejects")
	var named: Dictionary = {&"health": leech.health, "mana": leech.mana}
	_expect(not Rules.profile_error(named).is_empty(), "Top resource names require String keys")
	completed = true


func _test_hit_math() -> void:
	var leech: Dictionary = _leech()
	var plan: Dictionary = Rules.plan_hit(leech, _packet(), _settlement())
	_expect(plan.ok and plan.reason.is_empty() and plan.size() == 4, "Successful plan has exact wrapper")
	_expect(plan.health.size() == 2 and plan.mana.size() == 2, "Plan resources contain exactly amount and rate")
	_near(plan.health.amount, 5.5, "50 actual, 30 physical: life equals 50*.05 + 30*.10")
	_near(plan.mana.amount, 3.8, "50 actual, 30 physical: mana equals 50*.04 + 30*.06")
	_near(plan.health.rate, 30.0, "Life instance uses frozen hit profile rate")
	_near(plan.mana.rate, 16.0, "Mana instance uses frozen hit profile rate")
	var only_shield: Dictionary = _settlement()
	only_shield.shield_spent = 100.0
	only_shield.health_lost = 0.0
	only_shield.overkill = 0.0
	var shield_plan: Dictionary = Rules.plan_hit(leech, _packet(), only_shield)
	_near(shield_plan.health.amount, 11.0, "Shield-only actual damage grants life leech")
	_near(shield_plan.mana.amount, 7.6, "Shield-only actual damage grants mana leech")
	var only_health: Dictionary = only_shield.duplicate(true)
	only_health.shield_spent = 0.0
	only_health.health_lost = 100.0
	_expect(Rules.plan_hit(leech, _packet(), only_health) == shield_plan, "Same actual damage in life or shield produces the same instance")
	var overkill: Dictionary = _settlement()
	overkill.shield_spent = 1.0
	overkill.health_lost = 1.0
	overkill.overkill = 98.0
	var small: Dictionary = Rules.plan_hit(leech, _packet(), overkill)
	_near(small.health.amount, 0.22, "Overkill never grants leech")
	_near(small.mana.amount, 0.152, "Physical actual share scales down with overkill")
	var elemental: Dictionary = _settlement()
	elemental.components = {"fire": 100.0}
	_near(Rules.plan_hit(leech, _packet(), elemental).health.amount, 2.5, "Pure elemental attack uses generic attack leech only")
	var physical: Dictionary = _settlement()
	physical.components = {"physical": 100.0}
	_near(Rules.plan_hit(leech, _packet(), physical).health.amount, 7.5, "Physical attack adds both amount fractions")
	var resolved: Dictionary = Defense.apply_armour(Damage.resolve({"base": {"physical": 100.0, "fire": 50.0}, "tags": ["attack", "hit"]}, []), 500.0)
	var settled: Dictionary = Defense.settle_resolved(resolved, 20.0, 60.0)
	_expect(settled.ok and settled.components == {"physical": 50.0, "fire": 50.0}, "Known armour example resolves physical mitigation first")
	var armored_plan: Dictionary = Rules.plan_hit(leech, _packet(), settled)
	_expect(armored_plan.ok, "Existing Defense settlement with extra fields is accepted")
	_near(armored_plan.health.amount, 8.0, "Armour-resolved physical share is 40 actual, with no second mitigation")
	_near(armored_plan.mana.amount, 5.6, "Armour-resolved mana leech agrees independently")
	var capped_stats: Dictionary = _stats()
	for key: String in Rules.AMOUNT_KEYS:
		capped_stats[key] = 10.0
	var capped: Dictionary = Rules.plan_hit(_leech(capped_stats), _packet(), only_health)
	_near(capped.health.amount, 100.0, "Life instance cap uses ten percent of maximum")
	_near(capped.mana.amount, 40.0, "Mana instance cap uses its own maximum")
	var display_cap: Dictionary = leech.duplicate(true)
	display_cap.health.total_rate_cap = 0.0001
	display_cap.mana.total_rate_cap = 999999.0
	_expect(Rules.plan_hit(display_cap, _packet(), _settlement()) == plan, "Frozen total-rate cap is display-only and does not change hit planning")
	var zero: Dictionary = {"components": {}, "damage_total": 0, "shield_spent": 0, "health_lost": 0, "overkill": 0}
	var zero_plan: Dictionary = Rules.plan_hit(leech, _packet(), zero)
	_expect(zero_plan.ok and zero_plan.health.amount == 0.0 and zero_plan.mana.amount == 0.0, "Zero damage plans zero without division by zero")
	completed = true


func _test_tag_scopes() -> void:
	for tags: Array in [[], ["utility"], ["spell", "hit"], ["hit", "area", "secondary", "explosion"], ["attack"], ["hit"], ["damage_over_time"]]:
		var compiled: Dictionary = Rules.compile({"leech_modifiers": _stats()}, tags)
		_expect(compiled.ok and compiled.leech.is_empty(), "Non-attack or non-hit compilation emits no profile")
		var packet: Dictionary = _packet()
		packet.tags = tags
		var plan: Dictionary = Rules.plan_hit(_leech(), packet, _settlement())
		_expect(plan.ok and plan.health.amount == 0.0 and plan.mana.amount == 0.0, "Spell, secondary, utility and non-hit events grant zero leech")
	for tags: Array in [["hit", "attack"], ["hit", "attack", "melee", "area"], ["hit", "attack", "projectile"], ["attack", "hit", "attack", "hit"]]:
		var packet: Dictionary = _packet()
		packet.tags = tags
		_expect(Rules.plan_hit(_leech(), packet, _settlement()) == Rules.plan_hit(_leech(), _packet(), _settlement()), "Melee/projectile/duplicate tag shape preserves attack leech")
	for invalid: Variant in [null, false, {}, "attack", [1], [&"attack", "hit"]]:
		var packet: Dictionary = _packet()
		packet.tags = invalid
		_assert_plan_failure(Rules.plan_hit(_leech(), packet, _settlement()), "Invalid packet tags reject")
	_expect(not Rules.compile({"leech_modifiers": _stats()}, ["attack", "hit", false]).ok, "Malformed primary tag rejects")
	completed = true


func _test_settlement_validation() -> void:
	for field: String in ["damage_total", "shield_spent", "health_lost", "overkill", "components"]:
		var missing: Dictionary = _settlement()
		missing.erase(field)
		_assert_plan_failure(Rules.plan_hit(_leech(), _packet(), missing), "Missing settlement field: " + field)
	for field: String in ["damage_total", "shield_spent", "health_lost", "overkill"]:
		for invalid: Variant in INVALID_NUMBERS:
			var bad: Dictionary = _settlement()
			bad[field] = invalid
			_assert_plan_failure(Rules.plan_hit(_leech(), _packet(), bad), "Malformed settlement value: " + field)
	for invalid: Variant in [null, false, 1, [], "", {"unknown": 100}, {false: 100}, {&"physical": 60, "fire": 40}]:
		var bad: Dictionary = _settlement()
		bad.components = invalid
		_assert_plan_failure(Rules.plan_hit(_leech(), _packet(), bad), "Malformed component schema")
	for invalid: Variant in INVALID_NUMBERS:
		var bad: Dictionary = _settlement()
		bad.components.physical = invalid
		_assert_plan_failure(Rules.plan_hit(_leech(), _packet(), bad), "Malformed resolved component amount")
	for change: Dictionary in [{"damage_total": 101}, {"shield_spent": 80, "health_lost": 30, "overkill": 0}, {"overkill": 49}, {"ok": false}, {"ok": 1}, {"ok": "true"}, {"components": {}}]:
		var bad: Dictionary = _settlement()
		bad.merge(change, true)
		_assert_plan_failure(Rules.plan_hit(_leech(), _packet(), bad), "Inconsistent or failed settlement rejects")
	var tiny: Dictionary = {"components": {"physical": 1.0e-15}, "damage_total": 0.0, "shield_spent": 0.0, "health_lost": 0.0, "overkill": 0.0}
	_assert_plan_failure(Rules.plan_hit(_leech(), _packet(), tiny), "Tiny nonzero mismatch cannot become zero through an absolute epsilon")
	var components: Dictionary = {"physical": 0.1, "fire": 0.2}
	var rounded: Dictionary = {"components": components, "damage_total": 0.3, "shield_spent": 0.1, "health_lost": 0.2, "overkill": 0.0}
	_expect(Rules.plan_hit(_leech(), _packet(), rounded).ok, "Only floating roundoff is tolerated in component/accounting sums")
	var invalid_profile: Dictionary = _leech()
	invalid_profile.health.extra = 1
	_assert_plan_failure(Rules.plan_hit(invalid_profile, _packet(), _settlement()), "Plan validates exact profile before using it")
	completed = true


func _test_overflow() -> void:
	for maximum: String in ["max_health", "max_mana"]:
		var underflow: Dictionary = _stats()
		underflow[maximum] = 5.0e-324
		_expect(not Rules.profile(underflow).ok, "Positive maximum whose capacity/rate underflows to zero rejects")
	for pair: Array in [["max_health", "life_leech_rate_increased"], ["max_health", "life_leech_max_rate_increased"], ["max_mana", "mana_leech_rate_increased"], ["max_mana", "mana_leech_max_rate_increased"]]:
		var stats: Dictionary = _stats()
		stats[pair[0]] = 1.0e308
		stats[pair[1]] = 1.0e308
		_expect(not Rules.profile(stats).ok, "Overflowing derived rate rejects: " + str(pair))
		_expect(not Rules.compile({"leech_modifiers": stats}, ["attack", "hit"]).ok, "Overflowing derived rate cannot enter a compiled profile")
		for key: String in Rules.AMOUNT_KEYS:
			stats[key] = 0.0
		_expect(not Rules.from_stats(stats).is_empty(), "Rate-only overflow is preserved for rejection")
	var huge_fraction: Dictionary = _leech()
	huge_fraction.health.attack_fraction = 1.0e308
	_expect(Rules.profile_error(huge_fraction).is_empty(), "Finite huge fraction has no artificial clamp")
	_assert_plan_failure(Rules.plan_hit(huge_fraction, _packet(), _settlement()), "A finite instance cap must not hide multiplication overflow")
	var sum_overflow: Dictionary = _leech()
	sum_overflow.health.attack_fraction = 1.0e308
	sum_overflow.health.physical_attack_fraction = 1.0e308
	var one: Dictionary = {"components": {"physical": 1}, "damage_total": 1, "shield_spent": 0, "health_lost": 1, "overkill": 0}
	_assert_plan_failure(Rules.plan_hit(sum_overflow, _packet(), one), "Finite individual amount terms cannot hide sum overflow")
	var component_overflow: Dictionary = {"components": {"physical": 1.0e308, "fire": 1.0e308}, "damage_total": 1.0e308, "shield_spent": 0, "health_lost": 1, "overkill": 1.0e308}
	_assert_plan_failure(Rules.plan_hit(_leech(), _packet(), component_overflow), "Resolved component sum overflow rejects")
	var settlement_overflow: Dictionary = {"components": {"physical": 1.0e308}, "damage_total": 1.0e308, "shield_spent": 1.0e308, "health_lost": 1.0e308, "overkill": 0}
	_assert_plan_failure(Rules.plan_hit(_leech(), _packet(), settlement_overflow), "Actual damage sum overflow rejects")
	settlement_overflow.health_lost = 0
	settlement_overflow.overkill = 1.0e308
	_assert_plan_failure(Rules.plan_hit(_leech(), _packet(), settlement_overflow), "Actual damage plus overkill overflow rejects")
	completed = true


func _assert_plan_failure(result: Dictionary, label: String) -> void:
	_expect(result.size() == 4 and not result.ok and not result.reason.is_empty(), label)
	_expect(result.health == {"amount": 0.0, "rate": 0.0} and result.mana == {"amount": 0.0, "rate": 0.0}, "Invalid plans have atomic zero outputs")


func _test_no_mutation() -> void:
	var stats: Dictionary = _stats()
	var stats_before: PackedByteArray = var_to_bytes(stats)
	var snapshot: Dictionary = {"leech_modifiers": Rules.from_stats(stats), "existing": {"value": [1, 2]}}
	var snapshot_before: PackedByteArray = var_to_bytes(snapshot)
	var current: Dictionary = Rules.profile(stats)
	var tags: Array = ["hit", "attack", "projectile"]
	var tags_before: PackedByteArray = var_to_bytes(tags)
	var leech: Dictionary = Rules.compile(snapshot, tags).leech
	var leech_before: PackedByteArray = var_to_bytes(leech)
	var packet: Dictionary = _packet()
	var packet_before: PackedByteArray = var_to_bytes(packet)
	var settlement: Dictionary = _settlement()
	var settlement_before: PackedByteArray = var_to_bytes(settlement)
	var result: Dictionary = Rules.plan_hit(leech, packet, settlement)
	var expected: Dictionary = result.duplicate(true)
	Rules.error(snapshot)
	Rules.profile_error(leech)
	result.health.amount = 999
	result.mana.rate = 999
	current.health.instance_rate = 999
	_expect(var_to_bytes(stats) == stats_before, "Profile/from_stats/compile/plan preserve original stats")
	_expect(var_to_bytes(snapshot) == snapshot_before, "Compile and validation preserve original snapshot")
	_expect(var_to_bytes(tags) == tags_before, "Compile preserves caller tag order")
	_expect(var_to_bytes(leech) == leech_before, "Plan result and current profile do not alias compiled profile")
	_expect(var_to_bytes(packet) == packet_before and var_to_bytes(settlement) == settlement_before, "Plan preserves packet and settlement exactly")
	var raw_keys: Array = snapshot.leech_modifiers.keys()
	raw_keys.reverse()
	var reversed: Dictionary = {}
	for key: String in raw_keys:
		reversed[key] = snapshot.leech_modifiers[key]
	tags.reverse()
	_expect(Rules.compile({"leech_modifiers": reversed}, tags).leech == leech, "Stat and tag ordering do not change compile output")
	settlement.components = {"fire": 40.0, "physical": 60.0}
	_expect(Rules.plan_hit(leech, packet, settlement) == expected, "Component order does not change plan output")
	var second: Dictionary = Rules.compile(snapshot, tags).leech
	second.health.instance_rate = 999
	_expect(var_to_bytes(leech) == leech_before, "Independent compile outputs do not alias")
	stats.attack_life_leech = 0.99
	_expect(var_to_bytes(snapshot) == snapshot_before, "Later stats changes cannot edit snapshot")
	snapshot.leech_modifiers.life_leech_rate_increased = 99
	_expect(var_to_bytes(leech) == leech_before, "Later snapshot changes cannot edit frozen instance profile")
	var malformed: Dictionary = _settlement()
	malformed.health_lost = NAN
	var malformed_before: PackedByteArray = var_to_bytes(malformed)
	Rules.plan_hit(leech, packet, malformed)
	_expect(var_to_bytes(malformed) == malformed_before, "Failure validation preserves malformed input exactly")
	completed = true
