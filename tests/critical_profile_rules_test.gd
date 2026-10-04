extends SceneTree
## Pure critical profile contracts; no gameplay, packets, or scene dependencies.
const Rules = preload("res://scripts/combat/critical_strike_rules.gd")
const EXPECTED_STATS: Array[String] = [
	"crit_chance_increased", "attack_crit_chance_increased", "spell_crit_chance_increased",
	"melee_crit_chance_increased", "projectile_attack_crit_chance_increased",
	"crit_multiplier_add", "spell_crit_multiplier_add", "melee_crit_multiplier_add",
	"projectile_attack_crit_multiplier_add",
]
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(390507)
	var expected_random: Array = [randi(), randi(), randi()]
	seed(390507)
	_case(_test_from_stats, "legacy absence and detached stats")
	_case(_test_snapshot_validation, "snapshot schema and numeric bounds")
	_case(_test_scopes, "additive primary scopes and secondary isolation")
	_case(_test_compile_boundaries, "compile bounds and atomic failures")
	_case(_test_profile_validation, "exact resolved profile schema")
	_case(_test_roll, "pure strict roll boundaries")
	_case(_test_detachment_and_order, "detached outputs and canonical order")
	_expect([randi(), randi(), randi()] == expected_random, "Every public operation preserves global RNG state")
	print("Critical profile rules: %d checks, %d failures" % [checks, failures])
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
	_expect(absf(value - expected) < 0.000000001, "%s (actual %.12f, expected %.12f)" % [label, value, expected])


func _snapshot() -> Dictionary:
	return {"critical_modifiers": {"base_chance": 0.05, "base_multiplier": 1.5}}


func _test_from_stats() -> void:
	_expect(Rules.STAT_KEYS == EXPECTED_STATS, "Exactly nine stable modifier stat keys")
	for stats: Dictionary in [{}, {"damage": 100.0}, {"unknown_crit_chance": 0.5}]:
		_expect(Rules.from_stats(stats).is_empty(), "Legacy and unrelated stats do not opt into critical profiles")
	var zeroes: Dictionary = {}
	for key: String in EXPECTED_STATS:
		zeroes[key] = 0
	_expect(Rules.from_stats(zeroes).is_empty(), "All integer-zero modifier fields preserve legacy absence")
	for key: String in EXPECTED_STATS:
		zeroes[key] = -0.0
	_expect(Rules.from_stats(zeroes).is_empty(), "All float-zero modifier fields preserve legacy absence")
	_expect(Rules.from_stats({"crit_base_chance": 0.0}) == {"base_chance": 0.0, "base_multiplier": 1.5}, "Explicit zero chance opts in")
	_expect(Rules.from_stats({"crit_base_multiplier": 1.0}) == {"base_chance": 0.0, "base_multiplier": 1.0}, "Explicit multiplier opts in with zero chance")
	_expect(Rules.from_stats({"crit_base_chance": 0.05, "crit_base_multiplier": 1.5}) == _snapshot().critical_modifiers, "Canonical baseline retains five-percent chance")
	for key: String in EXPECTED_STATS:
		var stats: Dictionary = zeroes.duplicate(true)
		stats[key] = 0.25
		var output: Dictionary = Rules.from_stats(stats)
		_expect(output.size() == 3 and output[key] == 0.25, "Only the nonzero known modifier is retained: " + key)
		_expect(output.base_chance == 0.0 and output.base_multiplier == 1.5, "Modifier-only stats use zero/1.5 defaults: " + key)
		_expect(Rules.error({"critical_modifiers": output}).is_empty(), "Modifier-only profile validates: " + key)
	for key: String in EXPECTED_STATS + ["crit_base_chance", "crit_base_multiplier"]:
		for invalid: Variant in [null, true, false, "0", [], {}, NAN, INF, -INF, -0.1]:
			var stats: Dictionary = {key: invalid}
			var output: Dictionary = Rules.from_stats(stats)
			var output_key: String = "base_chance" if key == "crit_base_chance" else ("base_multiplier" if key == "crit_base_multiplier" else key)
			_expect(output.has(output_key) and typeof(output[output_key]) == typeof(invalid), "Malformed source retains its field and type: " + key)
			_expect(not Rules.error({"critical_modifiers": output}).is_empty(), "Malformed source is rejected rather than washed out: " + key)
	var nested: Dictionary = {"crit_base_chance": {"bad": [0.25]}, "crit_multiplier_add": [1.0, {"bad": 2}]}
	var detached: Dictionary = Rules.from_stats(nested)
	detached.base_chance.bad[0] = 99
	detached.crit_multiplier_add[1].bad = 99
	_expect(nested.crit_base_chance.bad[0] == 0.25 and nested.crit_multiplier_add[1].bad == 2, "Even malformed nested values are deeply detached")
	completed = true


func _test_snapshot_validation() -> void:
	_expect(Rules.error({}).is_empty(), "Absent optional critical modifiers are valid")
	_expect(Rules.error({"legacy": {"damage": 100}}).is_empty(), "Other snapshot data remains outside this schema")
	for invalid: Variant in [null, true, false, 0, 1.5, "", [], {}]:
		_expect(not Rules.error({"critical_modifiers": invalid}).is_empty(), "Present modifiers require a nonempty dictionary")
	for missing: String in ["base_chance", "base_multiplier"]:
		var snapshot: Dictionary = _snapshot()
		snapshot.critical_modifiers.erase(missing)
		_expect(not Rules.error(snapshot).is_empty(), "Required field cannot be missing: " + missing)
	for key: Variant in ["unknown", "attack_crit_multiplier_add", 3, false, &"extra", &"crit_chance_increased"]:
		var snapshot: Dictionary = _snapshot()
		snapshot.critical_modifiers[key] = 0.0
		_expect(not Rules.error(snapshot).is_empty(), "Unknown and non-String keys are rejected")
	for key: String in EXPECTED_STATS + ["base_chance", "base_multiplier"]:
		for invalid: Variant in [null, true, false, "0.05", {}, [], NAN, INF, -INF]:
			var snapshot: Dictionary = _snapshot()
			snapshot.critical_modifiers[key] = invalid
			_expect(not Rules.error(snapshot).is_empty(), "Invalid numeric type or nonfinite value is rejected: " + key)
	for chance: Variant in [0, 0.0, 0.05, 1, 1.0]:
		var snapshot: Dictionary = _snapshot()
		snapshot.critical_modifiers.base_chance = chance
		_expect(Rules.error(snapshot).is_empty(), "Base chance accepts inclusive zero/one and integer numbers")
	for chance: float in [-0.000001, 1.000001]:
		var snapshot: Dictionary = _snapshot()
		snapshot.critical_modifiers.base_chance = chance
		_expect(not Rules.error(snapshot).is_empty(), "Base chance rejects outside bounds")
	for multiplier: Variant in [1, 1.0, 1.5, 1000, 1000.0]:
		var snapshot: Dictionary = _snapshot()
		snapshot.critical_modifiers.base_multiplier = multiplier
		_expect(Rules.error(snapshot).is_empty(), "Base multiplier accepts inclusive one/thousand")
	for multiplier: float in [0.999999, 1000.000001]:
		var snapshot: Dictionary = _snapshot()
		snapshot.critical_modifiers.base_multiplier = multiplier
		_expect(not Rules.error(snapshot).is_empty(), "Base multiplier rejects outside bounds")
	for key: String in EXPECTED_STATS:
		for valid: Variant in [0, 0.0, 0.25, 1000000, 1000000.0]:
			var snapshot: Dictionary = _snapshot()
			snapshot.critical_modifiers[key] = valid
			_expect(Rules.error(snapshot).is_empty(), "Modifier accepts inclusive finite bounds: " + key)
		for invalid: float in [-0.000001, 1000000.000001, 1.0e300]:
			var snapshot: Dictionary = _snapshot()
			snapshot.critical_modifiers[key] = invalid
			_expect(not Rules.error(snapshot).is_empty(), "Modifier rejects negative or excessive values: " + key)
	var named_base: Dictionary = {&"base_chance": 0.05, "base_multiplier": 1.5}
	_expect(not Rules.error({"critical_modifiers": named_base}).is_empty(), "Base StringName keys cannot coerce into String keys")
	completed = true


func _test_scopes() -> void:
	var snapshot: Dictionary = _snapshot()
	snapshot.critical_modifiers.merge({"crit_chance_increased": 0.2, "spell_crit_chance_increased": 0.3,
		"crit_multiplier_add": 0.1, "spell_crit_multiplier_add": 0.2})
	var spell: Dictionary = Rules.compile(snapshot, ["hit", "spell"], true)
	_expect(spell.ok and spell.error.is_empty(), "Real global/spell example compiles")
	_near(spell.critical.primary.chance, 0.075, "Five percent times one plus 0.2 plus 0.3 equals 7.5 percent")
	_near(spell.critical.primary.multiplier, 1.8, "1.5 plus 0.1 plus 0.2 equals 1.8")
	_near(spell.critical.secondary.chance, 0.06, "Secondary uses global chance only")
	_near(spell.critical.secondary.multiplier, 1.6, "Secondary uses global multiplier only")
	_expect(not is_equal_approx(spell.critical.primary.chance, 0.05 * 1.2 * 1.3), "Chance increases are additive, not multiplicative")
	_expect(not is_equal_approx(spell.critical.primary.multiplier, 1.5 * 1.1 * 1.2), "Multiplier additions are percentage points")
	var scoped: Dictionary = _snapshot()
	scoped.critical_modifiers.merge({"crit_chance_increased": 0.1, "attack_crit_chance_increased": 0.2,
		"spell_crit_chance_increased": 0.4, "melee_crit_chance_increased": 0.8,
		"projectile_attack_crit_chance_increased": 1.6, "crit_multiplier_add": 0.1,
		"spell_crit_multiplier_add": 0.2, "melee_crit_multiplier_add": 0.4,
		"projectile_attack_crit_multiplier_add": 0.8})
	var cases: Array = [
		[["hit"], 0.055, 1.6],
		[["hit", "attack"], 0.065, 1.6],
		[["hit", "spell"], 0.075, 1.8],
		[["hit", "melee"], 0.095, 2.0],
		[["hit", "projectile"], 0.055, 1.6],
		[["hit", "projectile", "spell"], 0.075, 1.8],
		[["hit", "projectile", "attack"], 0.145, 2.4],
		[["hit", "melee", "attack"], 0.105, 2.0],
		[["hit", "melee", "spell"], 0.115, 2.2],
		[["hit", "projectile", "attack", "spell", "melee"], 0.205, 3.0],
	]
	for item: Array in cases:
		var result: Dictionary = Rules.compile(scoped, item[0], true)
		_expect(result.ok, "Scope combination compiles: " + str(item[0]))
		_near(result.critical.primary.chance, item[1], "Exact scoped chance: " + str(item[0]))
		_near(result.critical.primary.multiplier, item[2], "Exact scoped multiplier: " + str(item[0]))
		_near(result.critical.secondary.chance, 0.055, "Secondary chance ignores every primary scope")
		_near(result.critical.secondary.multiplier, 1.6, "Secondary multiplier ignores every primary scope")
		_expect(result.critical.size() == 2 and result.critical.primary.size() == 2 and result.critical.secondary.size() == 2, "Compiled profiles contain only resolved chance and multiplier")
	var no_secondary: Dictionary = Rules.compile(scoped, ["hit", "spell"], false)
	_expect(no_secondary.critical.keys() == ["primary"], "Secondary is only emitted when requested")
	for tags: Array in [[], ["utility"], ["spell"], ["attack", "melee", "projectile"]]:
		_expect(Rules.compile(scoped, tags, true) == {"ok": true, "error": "", "critical": {}}, "No-hit utility never gets critical profiles")
	completed = true


func _test_compile_boundaries() -> void:
	_expect(Rules.compile({}, ["hit", "attack"], true) == {"ok": true, "error": "", "critical": {}}, "Missing critical modifiers preserve legacy compilation")
	var zero: Dictionary = {"critical_modifiers": {"base_chance": 0, "base_multiplier": 1}}
	zero.critical_modifiers["crit_chance_increased"] = 1000000
	var compiled: Dictionary = Rules.compile(zero, ["hit"], true)
	_expect(compiled.ok and compiled.critical.primary == {"chance": 0.0, "multiplier": 1.0}, "Zero chance remains zero with maximum increases")
	_expect(compiled.critical.secondary == compiled.critical.primary, "Zero chance secondary remains zero")
	var capped: Dictionary = _snapshot()
	for key: String in EXPECTED_STATS:
		if key.ends_with("chance_increased"):
			capped.critical_modifiers[key] = 1000000
	var maximum: Dictionary = Rules.compile(capped, ["hit", "attack", "spell", "melee", "projectile"], true)
	_expect(maximum.ok and maximum.critical.primary.chance == 1.0 and maximum.critical.secondary.chance == 1.0, "Every chance increase can reach its bound and final chance clamps to one")
	var multiplier_limit: Dictionary = {"critical_modifiers": {"base_chance": 1.0, "base_multiplier": 1000.0, "crit_multiplier_add": 999000.0}}
	compiled = Rules.compile(multiplier_limit, ["hit"], true)
	_expect(compiled.ok and compiled.critical.primary.multiplier == 1000000.0, "Final multiplier accepts exact maximum")
	multiplier_limit.critical_modifiers.crit_multiplier_add += 0.000001
	_expect(Rules.error(multiplier_limit).is_empty(), "Individually valid modifiers may exceed resolved profile bound")
	_assert_compile_failure(multiplier_limit, ["hit"], "Final multiplier overflow fails atomically")
	var scoped_overflow: Dictionary = _snapshot()
	scoped_overflow.critical_modifiers["spell_crit_multiplier_add"] = 1000000.0
	_assert_compile_failure(scoped_overflow, ["hit", "spell"], "Applicable scope cannot exceed final multiplier bound")
	_expect(Rules.compile(scoped_overflow, ["hit", "attack"], true).ok, "Unused scope does not affect final profile bounds")
	_expect(Rules.compile(scoped_overflow, ["utility"], true).critical.is_empty(), "Valid source fields without hits do not produce profiles")
	for value: Variant in [{}, null, {"base_chance": 0.05}, {"base_chance": NAN, "base_multiplier": 1.5},
		{"base_chance": 1, "base_multiplier": 1, "crit_chance_increased": 1.0e308},
		{"base_chance": 1, "base_multiplier": 1, "crit_multiplier_add": INF},
		{"base_chance": 0.05, "base_multiplier": 1.5, "unknown": 0}]:
		_assert_compile_failure({"critical_modifiers": value}, ["hit"], "Malformed source compile fails atomically")
		_assert_compile_failure({"critical_modifiers": value}, ["utility"], "Utility cannot hide invalid critical source data")
	completed = true


func _assert_compile_failure(snapshot: Dictionary, tags: Array, label: String) -> void:
	for secondary: bool in [false, true]:
		var result: Dictionary = Rules.compile(snapshot, tags, secondary)
		_expect(result.size() == 3 and result.has_all(["ok", "error", "critical"]), "Compilation has an exact result shape")
		_expect(not result.ok and not result.error.is_empty() and result.critical.is_empty(), label)


func _test_profile_validation() -> void:
	for invalid: Variant in [null, true, false, 0, "", [], {}, {"chance": 0.05}, {"multiplier": 1.5},
		{"chance": 0.05, "multiplier": 1.5, "extra": 0}, {&"chance": 0.05, "multiplier": 1.5},
		{"chance": 0.05, &"multiplier": 1.5}, {0: 0.05, "multiplier": 1.5}]:
		_expect(not Rules.profile_error(invalid).is_empty(), "Profile requires exactly two named String fields")
	for key: String in ["chance", "multiplier"]:
		for invalid: Variant in [null, true, false, "1", {}, [], NAN, INF, -INF]:
			var profile: Dictionary = {"chance": 0.05, "multiplier": 1.5}
			profile[key] = invalid
			_expect(not Rules.profile_error(profile).is_empty(), "Profile values cannot coerce invalid types: " + key)
	for chance: Variant in [0, 0.0, 0.05, 1, 1.0]:
		for multiplier: Variant in [1, 1.0, 1.5, 1000000, 1000000.0]:
			_expect(Rules.profile_error({"chance": chance, "multiplier": multiplier}).is_empty(), "Profile accepts finite integer/float inclusive bounds")
	for profile: Dictionary in [{"chance": -0.000001, "multiplier": 1.5}, {"chance": 1.000001, "multiplier": 1.5},
		{"chance": 0.05, "multiplier": 0.999999}, {"chance": 0.05, "multiplier": 1000000.000001}]:
		_expect(not Rules.profile_error(profile).is_empty(), "Profile rejects values immediately outside bounds")
	completed = true


func _test_roll() -> void:
	var profile: Dictionary = {"chance": 0.25, "multiplier": 1.8}
	for sample: float in [0.0, 0.249999999, 0.25, 0.250000001, 0.999999999]:
		var result: Dictionary = Rules.roll(profile, sample)
		_expect(result.size() == 5 and result.has_all(["ok", "error", "critical", "multiplier", "chance"]), "Roll returns the exact result shape")
		_expect(result.ok and result.error.is_empty() and result.chance == 0.25, "Roll preserves valid profile chance")
		_expect(result.critical == (sample < 0.25), "Only samples strictly below chance are critical")
		_expect(result.multiplier == (1.8 if sample < 0.25 else 1.0), "Ordinary hits use multiplier one")
	for chance: float in [0.0, 1.0]:
		for sample: float in [0.0, 0.5, 0.999999999]:
			var result: Dictionary = Rules.roll({"chance": chance, "multiplier": 1000000}, sample)
			_expect(result.ok and result.critical == (chance == 1.0), "Zero never crits and one always crits for valid samples")
	for sample: float in [-0.000001, 1.0, 1.000001, NAN, INF, -INF]:
		_assert_roll_failure(Rules.roll(profile, sample), "Sample rejects nonfinite or out-of-range values")
		_assert_roll_failure(Rules.roll({"chance": 0.0, "multiplier": 1.5}, sample), "Zero chance still validates its sample")
		_assert_roll_failure(Rules.roll({"chance": 1.0, "multiplier": 1.5}, sample), "Certain chance still validates its sample")
	for invalid: Dictionary in [{}, {"chance": 0.5, "multiplier": false}, {"chance": NAN, "multiplier": 1.5},
		{"chance": 0.5, "multiplier": 1.5, "extra": true}, {"chance": 0.5, "multiplier": 1000001}]:
		_assert_roll_failure(Rules.roll(invalid, 0.0), "Invalid profiles fail without an accidental critical result")
	var neutral: Dictionary = Rules.roll({"chance": 1, "multiplier": 1}, 0.0)
	_expect(neutral.ok and neutral.critical and neutral.multiplier == 1.0, "A critical event may have neutral multiplier one")
	completed = true


func _assert_roll_failure(result: Dictionary, label: String) -> void:
	_expect(result.size() == 5 and not result.ok and not result.error.is_empty(), label)
	_expect(not result.critical and result.multiplier == 1.0 and result.chance == 0.0, "Invalid rolls expose a safe neutral result")


func _test_detachment_and_order() -> void:
	var stats: Dictionary = {"crit_base_chance": 0.05, "crit_base_multiplier": 1.5,
		"crit_chance_increased": 0.2, "attack_crit_chance_increased": 0.1,
		"spell_crit_chance_increased": 0.3, "melee_crit_chance_increased": 0.4,
		"projectile_attack_crit_chance_increased": 0.5, "crit_multiplier_add": 0.1,
		"spell_crit_multiplier_add": 0.2, "melee_crit_multiplier_add": 0.3,
		"projectile_attack_crit_multiplier_add": 0.4}
	var stats_before: PackedByteArray = var_to_bytes(stats)
	var snapshot: Dictionary = {"critical_modifiers": Rules.from_stats(stats), "packet": {"damage": 12.0}}
	var snapshot_before: PackedByteArray = var_to_bytes(snapshot)
	var tags: Array = ["hit", "attack", "spell", "melee", "projectile"]
	var tags_before: PackedByteArray = var_to_bytes(tags)
	var original: Dictionary = Rules.compile(snapshot, tags, true)
	var original_before: PackedByteArray = var_to_bytes(original)
	var keys: Array = snapshot.critical_modifiers.keys()
	keys.reverse()
	var reversed: Dictionary = {}
	for key: String in keys:
		reversed[key] = snapshot.critical_modifiers[key]
	var reversed_tags: Array = tags.duplicate()
	reversed_tags.reverse()
	_expect(Rules.compile({"critical_modifiers": reversed}, reversed_tags, true) == original, "Key and tag order do not change resolved numbers")
	_expect(Rules.compile(snapshot, tags + tags, true) == original, "Repeated tags never apply a modifier twice")
	_expect(Rules.compile(snapshot, tags + ["unknown", "damage_over_time"], true) == original, "Unrelated tags do not add critical scope")
	Rules.error(snapshot)
	Rules.profile_error(original.critical.primary)
	var rolled: Dictionary = Rules.roll(original.critical.primary, 0.0)
	rolled.multiplier = 999
	rolled.chance = 0.99
	_expect(var_to_bytes(original) == original_before, "Roll and validation never mutate the profile")
	var modified: Dictionary = Rules.compile(snapshot, tags, true)
	modified.critical.primary.chance = 0.99
	modified.critical.secondary.multiplier = 99
	_expect(var_to_bytes(original) == original_before, "Separate compilations do not alias their profiles")
	_expect(modified.critical.secondary.chance == original.critical.secondary.chance, "Primary and secondary profile dictionaries do not alias")
	_expect(var_to_bytes(stats) == stats_before, "from_stats does not mutate source stats")
	_expect(var_to_bytes(snapshot) == snapshot_before, "Compilation, validation and returned writes preserve snapshot and packet")
	_expect(var_to_bytes(tags) == tags_before, "Compilation preserves caller tag order")
	stats.crit_base_chance = 0.9
	stats.spell_crit_multiplier_add = 100
	_expect(var_to_bytes(snapshot) == snapshot_before, "Later stats edits cannot change the detached modifier snapshot")
	snapshot.critical_modifiers.base_chance = 0.9
	_expect(var_to_bytes(original) == original_before, "Later snapshot edits cannot change frozen compiled profiles")
	completed = true
