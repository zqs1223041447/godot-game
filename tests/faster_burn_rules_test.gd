extends SceneTree
## v0.54 pure arithmetic and unchanged-runtime consumer contracts.
const Rules = preload("res://scripts/combat/burn_rules.gd")
const Runtime = preload("res://scripts/combat/burn_runtime.gd")
const OldRules = preload("res://docs/qa/v054-rules/v053_burn_rules.gd")
const BASE_SHA: String = "e3a5f7559ecbcb2cb56a9c192d75899fdcf43b3a"
var checks: int = 0
var failures: int = 0
var completed: bool = false
var sections: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(540054)
	var expected_random: Array = [randi(), randi(), randi()]
	seed(540054)
	_case(_test_frozen_zero, "frozen_v053_zero_bytes")
	_case(_test_source_and_snapshot, "source_and_snapshot_validation")
	_case(_test_faster_arithmetic, "faster_arithmetic")
	_case(_test_invalid_and_extreme, "invalid_and_extreme_arithmetic")
	_case(_test_runtime_consumer, "runtime_consumer")
	_case(_test_input_isolation, "input_isolation")
	_expect([randi(), randi(), randi()] == expected_random, "Pure derivation and runtime consumption preserve global RNG")
	print("Faster burn rules: %d checks, %d failures; frozen v053 %s; sections %s" % [checks, failures, BASE_SHA, JSON.stringify(sections)])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	var start: int = checks
	completed = false
	test.call()
	_expect(completed, "Case completes without a script exception: " + label)
	sections[label] = checks - start


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _same(actual: Variant, expected: Variant, label: String) -> void:
	_expect(var_to_bytes(actual) == var_to_bytes(expected), label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(is_finite(actual) and absf(actual - expected) <= maxf(1.0e-9, 1.0e-12 * absf(expected)),
		"%s (actual %s, expected %s)" % [label, actual, expected])


func _amount(result: Dictionary) -> float:
	var total: float = 0.0
	for segment: Dictionary in result.segments: total += float(segment.raw_amount)
	return total


func _test_frozen_zero() -> void:
	_same(Rules.PLAYER_POLICY, OldRules.PLAYER_POLICY, "Player policy keeps complete published bytes")
	_same(Rules.ENEMY_POLICY, OldRules.ENEMY_POLICY, "Enemy policy keeps complete published bytes")
	_same(Rules.POLICY_KEYS, OldRules.POLICY_KEYS, "Fixed policy shape remains unchanged")
	var fires: Array = [1, 0.000001, 0.1, 17.3, 213.225, 1.0e-300, 1.0e90, 1.0e308,
		null, true, false, "1", &"1", [], {}, NAN, INF, -INF, -1, 0, -0.0]
	var multipliers: Array = [0, 0.0, -0.0, 0.1, 0.04 + 0.06, 1.0e308,
		null, true, false, "0.1", [], {}, NAN, INF, -INF, -0.1]
	var policies: Array = [Rules.PLAYER_POLICY, Rules.ENEMY_POLICY,
		{"duration": 60, "rate_fraction": 1}, {"duration": 0.25, "rate_fraction": 0.123456789},
		{"duration": 1.0e-300, "rate_fraction": 1.0e-300},
		{"duration": 60.01, "rate_fraction": 1}, {"duration": 3, "rate_fraction": true},
		{"duration": 3, "rate_fraction": 1, "unexpected": 2},
		{"duration": 3, "rate_fraction": 1, &"hit_multiplier": 0.75},
		{}, {"duration": 3}, null, true, "player", []]
	for policy: Variant in policies:
		for fire: Variant in fires:
			for multiplier: Variant in multipliers:
				var expected: Dictionary = OldRules.from_fire_hit(fire, policy, multiplier)
				_same(Rules.from_fire_hit(fire, policy, multiplier), expected, "Omitted F preserves complete old result and error priority")
				for zero: Variant in [0, 0.0, -0.0]:
					_same(Rules.from_fire_hit(fire, policy, multiplier, zero), expected, "Numeric-zero F preserves complete old result bytes")
	for fire: float in [0.0, -0.0, 0.1, 17.3, 1.0e-300, 1.0e90, 1.0e308]:
		for rate: float in [0.0, -0.0, 0.3, 1.0 / 3.0, 1.0e-300, 2.0]:
			for multiplier: float in [0.0, -0.0, 0.1, 0.04 + 0.06, 1.0e308]:
				_same(Rules.raw_fire_dps(fire, rate, multiplier, 0.0), OldRules.raw_fire_dps(fire, rate, multiplier), "Zero-F shared DPS authority keeps old arithmetic bytes")
	for duration: float in [0.0, -0.0, 0.1, 3.0, 60.0, 1.0e-300]:
		_same(Rules.burn_duration(duration), duration, "Absent F duration helper is a byte-preserving identity")
		_same(Rules.burn_duration(duration, -0.0), duration, "Signed zero F skips division")
	completed = true


func _test_source_and_snapshot() -> void:
	var values: Array = [0, 0.0, -0.0, 0.1, 2, 1.0e308, true, false, null, "0.1", &"0.1", [], {}, NAN, INF, -INF, -0.1]
	for multiplier: Variant in values:
		var old_source: Dictionary = {"fire_dot_multiplier_add": multiplier}
		var expected: Dictionary = OldRules.multiplier_from_stats(old_source)
		_same(Rules.multiplier_from_stats(old_source), expected, "Absent F preserves old source projection bytes")
		for zero: Variant in [0, 0.0, -0.0]:
			var source: Dictionary = old_source.duplicate(true)
			source.damaging_ailments_faster = zero
			_same(Rules.multiplier_from_stats(source), expected, "Numeric-zero F is omitted from snapshots")
		_same(Rules.snapshot_multiplier_error(expected), OldRules.snapshot_multiplier_error(expected), "Old snapshot validation and reason remain exact")
	_same(Rules.multiplier_from_stats({}), {}, "Absent stat families produce no optional keys")
	for faster: Variant in [0.25, 1, 1.0e-300, 1.0e308]:
		var snapshot: Dictionary = Rules.multiplier_from_stats({"damaging_ailments_faster": faster})
		_same(snapshot, {"burn_faster": faster}, "Positive faster stat keeps its numeric type and exact value")
		_expect(Rules.snapshot_multiplier_error(snapshot).is_empty(), "Positive finite faster snapshot passes")
	var invalids: Array = [true, false, null, "0.25", &"0.25", [], {}, {"nested": []}, NAN, INF, -INF, -0.1]
	for invalid: Variant in invalids:
		var source: Dictionary = {"damaging_ailments_faster": invalid}
		var before: PackedByteArray = var_to_bytes(source)
		var snapshot: Dictionary = Rules.multiplier_from_stats(source)
		_expect(snapshot.has("burn_faster") and typeof(snapshot.burn_faster) == typeof(invalid), "Invalid source is preserved for downstream rejection")
		_same(snapshot.burn_faster, invalid, "Invalid source is never silently sanitized")
		_expect(not Rules.snapshot_multiplier_error(snapshot).is_empty(), "Invalid faster source rejects as a snapshot")
		_expect(var_to_bytes(source) == before, "Projection never mutates invalid input")
	for invalid: Variant in invalids + [0, 0.0, -0.0]:
		_expect(not Rules.snapshot_multiplier_error({"burn_faster": invalid}).is_empty(), "Explicit snapshot F requires strictly positive finite numeric input")
		_same(Rules.snapshot_multiplier_error({"fire_dot_multiplier": false, "burn_faster": invalid}),
			OldRules.snapshot_multiplier_error({"fire_dot_multiplier": false}), "Existing Fire DoT snapshot error has priority")
	var combined: Dictionary = Rules.multiplier_from_stats({"fire_dot_multiplier_add": 0.04 + 0.06,
		"damaging_ailments_faster": 0.10 + 0.15, "unrelated": 400})
	_same(combined, {"fire_dot_multiplier": 0.04 + 0.06, "burn_faster": 0.10 + 0.15}, "Two independent families project once in stable field order")
	_expect(Rules.snapshot_multiplier_error(combined).is_empty(), "Combined positive source families pass")
	completed = true


func _test_faster_arithmetic() -> void:
	var quarter: Dictionary = Rules.from_fire_hit(100.0, Rules.PLAYER_POLICY, 0.0, 0.25)
	_expect(quarter.ok, "Quarter-faster profile is valid")
	_same(quarter.raw_dps, 37.5, "Quarter-faster produces exactly 1.25 times thirty DPS")
	_same(quarter.duration, 2.4, "Quarter-faster compresses three seconds to 2.4")
	_near(quarter.raw_dps * quarter.duration, 90.0, "Quarter-faster preserves theoretical lifetime damage")
	for policy: Dictionary in [Rules.PLAYER_POLICY, Rules.ENEMY_POLICY, {"duration": 0.25, "rate_fraction": 0.17}]:
		for fire: float in [0.000001, 0.1, 17.3, 100.0, 213.225, 1.0e90]:
			for multiplier: float in [0.0, 0.04 + 0.06, 0.7, 2.0]:
				var original: Dictionary = OldRules.from_fire_hit(fire, policy, multiplier)
				for faster: float in [0.01, 0.10 + 0.15, 0.5, 1.0, 1.0e6]:
					var result: Dictionary = Rules.from_fire_hit(fire, policy, multiplier, faster)
					_expect(original.ok and result.ok, "Ordinary combined profile is valid")
					_same(result.raw_dps, original.raw_dps * (1.0 + faster), "Faster applies once after the existing Fire DoT factor")
					_same(result.duration, float(policy.duration) / (1.0 + faster), "Duration uses the same summed faster family")
					_same(result.raw_dps, Rules.raw_fire_dps(fire, policy.rate_fraction, multiplier, faster), "Runtime uses shared DPS authority")
					_same(result.duration, Rules.burn_duration(policy.duration, faster), "Runtime uses shared duration authority")
					_near(result.raw_dps * result.duration, original.raw_dps * original.duration, "Faster preserves old theoretical total within declared floating tolerance")
	var summed_faster: float = 0.10 + 0.15
	var additive: Dictionary = Rules.from_fire_hit(100.0, Rules.PLAYER_POLICY, 0.10, summed_faster)
	_near(additive.raw_dps, 41.25, "Additive faster contributions combine to twenty-five percent")
	_expect(absf(additive.raw_dps - 30.0 * 1.10 * 1.10 * 1.15) > 0.1, "Faster contributions are not independent multiplicative factors")
	_near(additive.raw_dps * additive.duration, 99.0, "Fire DoT increases total while faster only compresses its delivery")
	_same(Rules.from_fire_hit(50.0, Rules.ENEMY_POLICY), OldRules.from_fire_hit(50.0, OldRules.ENEMY_POLICY), "Enemy default stays exactly unchanged")
	completed = true


func _test_invalid_and_extreme() -> void:
	for invalid: Variant in [null, true, false, "0.25", &"0.25", [], {}, NAN, INF, -INF, -1, -0.001]:
		var rejected: Dictionary = Rules.from_fire_hit(100, Rules.PLAYER_POLICY, 0.10, invalid)
		_expect(not rejected.ok and not rejected.reason.is_empty() and rejected.raw_dps == 0.0 and rejected.duration == 0.0, "Invalid faster input cannot create an inert or partial burn")
		_same(Rules.from_fire_hit(false, {}, false, invalid), OldRules.from_fire_hit(false, {}, false), "Bad policy keeps first error priority")
		_same(Rules.from_fire_hit(false, Rules.PLAYER_POLICY, false, invalid), OldRules.from_fire_hit(false, Rules.PLAYER_POLICY, false), "Bad fire keeps error priority ahead of multipliers")
		_same(Rules.from_fire_hit(100, Rules.PLAYER_POLICY, false, invalid), OldRules.from_fire_hit(100, Rules.PLAYER_POLICY, false), "Bad Fire DoT multiplier keeps priority ahead of faster")
	var extremes: Array = [
		[1.0e308, {"duration": 3.0, "rate_fraction": 1.0}, 0.0, 1.0],
		[1.0e308, {"duration": 3.0, "rate_fraction": 1.0}, 1.0, 1.0e100],
		[1.0e308, {"duration": 60.0, "rate_fraction": 1.0}, 0.0, 0.25],
		[1.0e-300, {"duration": 3.0, "rate_fraction": 1.0e-100}, 0.0, 1.0e300],
		[1.0e-100, {"duration": 1.0e-300, "rate_fraction": 1.0}, 0.0, 1.0e100],
		[1.0e-300, {"duration": 1.0e-300, "rate_fraction": 1.0}, 0.0, 0.25],
		[1.0e-308, Rules.PLAYER_POLICY, 0.0, 1.0e308],
	]
	for args: Array in extremes:
		var result: Dictionary = Rules.from_fire_hit(args[0], args[1], args[2], args[3])
		_expect(not result.ok and result.raw_dps == 0.0 and result.duration == 0.0 and not result.reason.is_empty(), "Overflow or underflow rejects without exposing partial arithmetic")
	# Keep this accepted-extreme fixture above the engine's subnormal range.
	# The original 1e-308 input was rejected as nonpositive on the target build.
	var compressed: Dictionary = Rules.from_fire_hit(1.0e-300, Rules.PLAYER_POLICY, 0.0, 1.0e300)
	_expect(compressed.ok and Rules.positive_number(compressed.raw_dps) and Rules.positive_number(compressed.duration), "Huge finite faster factor remains legal when every result is representable")
	_expect(Rules.positive_number(compressed.raw_dps * compressed.duration), "Tiny accepted lifetime remains positive and finite")
	var minimum: float = pow(2.0, -1074.0)
	var subnormal: Dictionary = Rules.from_fire_hit(1.0, {"duration": minimum, "rate_fraction": 1.0}, 0.0, 3.0)
	_expect(not subnormal.ok and subnormal.duration == 0.0, "Subnormal duration division that reaches zero cannot be accepted")
	for faster: Variant in [0, 0.0, -0.0, 1, 2.0, 1.0e-300]:
		_expect(Rules.from_fire_hit(100, Rules.PLAYER_POLICY, 0, faster).ok, "Finite nonnegative runtime F accepts numeric zero and integers")
	completed = true


func _test_runtime_consumer() -> void:
	var plain: Dictionary = OldRules.from_fire_hit(100.0, OldRules.PLAYER_POLICY, 0.10)
	var faster: Dictionary = Rules.from_fire_hit(100.0, Rules.PLAYER_POLICY, 0.10, 0.25)
	var large := Runtime.new()
	var split := Runtime.new()
	for runtime in [large, split]:
		var applied: Dictionary = runtime.apply("monster", 1, 0, faster.raw_dps, faster.duration, 0.0, {"skill_id": "meteor"})
		_expect(applied.ok and applied.applied and applied.segments.is_empty(), "Derived profile is consumed without instant damage")
		_same(runtime.status_for("monster", 1).remaining, 2.4, "Runtime stores already-compressed duration")
	var settled: Dictionary = large.advance_all(2.4)
	_expect(settled.ok and large.is_empty(), "Faster burn expires at 2.4 seconds")
	_near(_amount(settled), plain.raw_dps * plain.duration, "Unchanged runtime consumes the complete original damage budget")
	var total: float = 0.0
	for step: int in range(1, 25):
		var piece: Dictionary = split.advance_target("monster", 1, float(step) / 10.0)
		_expect(piece.ok, "Every ordinary compressed-time partition is valid")
		total += _amount(piece)
	_near(total, _amount(settled), "Split and large advances preserve the same compressed total")
	_expect(split.is_empty(), "Split advancement reclaims compressed expiry")
	_expect(large.advance_all(3.0).segments.is_empty(), "Original three-second deadline cannot pay faster burn twice")
	var runtime := Runtime.new()
	var quarter: Dictionary = Rules.from_fire_hit(100.0, Rules.PLAYER_POLICY, 0.0, 0.25)
	runtime.apply("monster", 1, 1, quarter.raw_dps, quarter.duration, 0.0)
	var weak: Dictionary = runtime.apply("monster", 1, 2, 30.0, 3.0, 1.0)
	_expect(weak.ok and not weak.applied and weak.reason == "weaker", "Replacement compares final DPS rather than preserved total")
	_near(_amount(weak), 37.5, "Weaker arrival settles old faster interval first")
	_expect(runtime.status_for("monster", 1).source_id == 1, "Weaker application keeps old faster source")
	var twice: Dictionary = Rules.from_fire_hit(100.0, Rules.PLAYER_POLICY, 0.0, 1.0)
	var stronger: Dictionary = runtime.apply("monster", 1, 3, twice.raw_dps, twice.duration, 1.5)
	_expect(stronger.ok and stronger.applied and stronger.reason == "stronger", "Higher faster DPS replaces and takes ownership")
	_near(_amount(stronger), 18.75, "Replacement pays only the old half-second interval")
	_same(runtime.status_for("monster", 1).remaining, 1.5, "Stronger replacement adopts its own compressed duration")
	var equal_profile: Dictionary = Rules.from_fire_hit(160.0, Rules.PLAYER_POLICY, 0.0, 0.25)
	var equal: Dictionary = runtime.apply("monster", 1, 4, equal_profile.raw_dps, equal_profile.duration, 2.0)
	_expect(equal.ok and equal.applied and equal.reason == "equal", "Exactly equal final DPS refreshes even with a different duration")
	_expect(equal.segments[0].source_id == 3, "Equal refresh settles prior ownership")
	_same(runtime.status_for("monster", 1).remaining, 2.4, "Equal refresh adopts incoming compressed duration")
	_near(_amount(runtime.advance_all(10.0)), 144.0, "Refreshed profile pays its own lifetime budget")
	_expect(runtime.is_empty(), "Final runtime state is reclaimed")
	var old_runtime := Runtime.new()
	var zero_runtime := Runtime.new()
	var zero: Dictionary = Rules.from_fire_hit(100.0, Rules.PLAYER_POLICY, 0.10, -0.0)
	_same(zero_runtime.apply("monster", 1, 0, zero.raw_dps, zero.duration, 0.0),
		old_runtime.apply("monster", 1, 0, plain.raw_dps, plain.duration, 0.0), "Zero-F runtime application result bytes remain exact")
	for at: float in [0.0, 0.1, 1.0, 2.4, 3.0, 10.0]:
		_same(zero_runtime.advance_all(at), old_runtime.advance_all(at), "Zero-F settled segment bytes remain exact")
		_same(zero_runtime.statuses(), old_runtime.statuses(), "Zero-F runtime state bytes remain exact")
	completed = true


func _test_input_isolation() -> void:
	var policy: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
	var policy_bytes: PackedByteArray = var_to_bytes(policy)
	var source: Dictionary = {"fire_dot_multiplier_add": 0.10, "damaging_ailments_faster": 0.25, "nested_unrelated": {"items": [1, 2]}}
	var source_bytes: PackedByteArray = var_to_bytes(source)
	var projected: Dictionary = Rules.multiplier_from_stats(source)
	var profile: Dictionary = Rules.from_fire_hit(100.0, policy, projected.fire_dot_multiplier, projected.burn_faster)
	_expect(var_to_bytes(policy) == policy_bytes and var_to_bytes(source) == source_bytes, "Successful projection and derivation preserve all inputs")
	var profile_bytes: PackedByteArray = var_to_bytes(profile)
	var projected_bytes: PackedByteArray = var_to_bytes(projected)
	source.damaging_ailments_faster = 9.0
	source.fire_dot_multiplier_add = 3.0
	policy.duration = 60.0
	_expect(var_to_bytes(projected) == projected_bytes and var_to_bytes(profile) == profile_bytes, "Later source and policy changes do not change frozen scalar outputs")
	profile.raw_dps = 9999.0
	projected.burn_faster = 9999.0
	_same(Rules.PLAYER_POLICY, OldRules.PLAYER_POLICY, "Caller output mutation cannot alter fixed player policy")
	_same(Rules.ENEMY_POLICY, OldRules.ENEMY_POLICY, "Caller output mutation cannot alter fixed enemy policy")
	_same(Rules.from_fire_hit(100.0, Rules.PLAYER_POLICY, 0.10, 0.25).raw_dps, 41.25, "Later calls retain their independent result")
	completed = true
