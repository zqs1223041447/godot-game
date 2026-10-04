extends SceneTree
## Pure policy/runtime contracts. Gameplay owns defenses, actor life, and clocks.
const Rules = preload("res://scripts/combat/burn_rules.gd")
const Runtime = preload("res://scripts/combat/burn_runtime.gd")
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(450045)
	var expected_random: Array = [randi(), randi(), randi()]
	seed(450045)
	_case(_test_policy, "original policy and single resolved base")
	_case(_test_independent_actors, "target clocks and source lifetime")
	_case(_test_replacement, "stronger equal weaker and old attribution")
	_case(_test_time_boundaries, "expiry zero and large advances")
	_case(_test_partition_equivalence, "large versus split time")
	_case(_test_invalid_inputs, "strict shapes and atomic rejection")
	_case(_test_atomic_advance_all, "all-target planning before commit")
	_case(_test_capacity_order_and_copy, "bounded deterministic detached storage")
	_expect([randi(), randi(), randi()] == expected_random, "Every rule and runtime operation preserves global RNG")
	print("Burn rules/runtime: %d checks, %d failures" % [checks, failures])
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
	_expect(absf(value - expected) <= maxf(1.0e-10, absf(expected) * 1.0e-12),
		"%s (actual %.12f, expected %.12f)" % [label, value, expected])


func _amount(result: Dictionary) -> float:
	var total: float = 0.0
	for segment: Dictionary in result.segments: total += float(segment.raw_amount)
	return total


func _test_policy() -> void:
	_expect(Rules.PLAYER_POLICY == {"duration": 3.0, "rate_fraction": 0.30,
		"hit_multiplier": 0.75, "mana_multiplier": 1.20}, "Player prototype policy is explicit")
	_expect(Rules.ENEMY_POLICY == {"duration": 3.0, "rate_fraction": 1.0 / 3.0,
		"upfront_fire_multiplier": 0.50}, "Enemy prototype policy is explicit")
	var player: Dictionary = Rules.from_fire_hit(100.0, Rules.PLAYER_POLICY)
	_expect(player.ok and player.duration == 3.0, "Positive resolved fire creates three-second player profile")
	_near(player.raw_dps, 30.0, "Helper uses resolved fire once without repeating .75 hit multiplier")
	var enemy: Dictionary = Rules.from_fire_hit(50.0, Rules.ENEMY_POLICY)
	_near(enemy.raw_dps * enemy.duration, 50.0, "Enemy already-halved fire is not halved again")
	var policy: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
	var policy_bytes: PackedByteArray = var_to_bytes(policy)
	player = Rules.from_fire_hit(80, policy)
	_expect(player.ok and var_to_bytes(policy) == policy_bytes, "Rules accept numeric integers without mutating the policy")
	player.raw_dps = 1234.0
	_expect(Rules.from_fire_hit(80, policy).raw_dps == 24.0, "Rule output is independent of later caller edits")
	for invalid: Variant in [null, true, false, "1", &"1", [], {}, NAN, INF, -INF, -1, 0, -0.0]:
		var result: Dictionary = Rules.from_fire_hit(invalid, Rules.PLAYER_POLICY)
		_expect(not result.ok and result.raw_dps == 0.0 and result.duration == 0.0, "Invalid or zero fire creates no burn")
	for invalid: Variant in [null, true, 1, "player", [], {}, {"duration": 3}, {"rate_fraction": 0.3}]:
		_expect(not Rules.from_fire_hit(100, invalid).ok, "Policy requires an exact dictionary with both required fields")
	for key: String in Rules.POLICY_KEYS:
		for invalid: Variant in [null, true, false, "1", &"1", [], {}, NAN, INF, -INF, 0, -0.5]:
			var bad: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
			bad[key] = invalid
			_expect(not Rules.from_fire_hit(100, bad).ok, "Policy rejects invalid typed amount: " + key)
	for key: Variant in ["unknown", 3, false, &"duration"]:
		var bad: Dictionary = {"rate_fraction": 0.3}
		bad[key] = 3.0
		if typeof(key) != TYPE_STRING_NAME: bad.duration = 3.0
		_expect(not Rules.from_fire_hit(100, bad).ok, "Unknown or StringName policy keys are rejected")
	_expect(not Rules.from_fire_hit(100, {"duration": 60.01, "rate_fraction": 0.3}).ok, "Duration above sixty is rejected")
	_expect(Rules.from_fire_hit(1, {"duration": 60, "rate_fraction": 1}).ok, "Sixty-second inclusive bound accepts integers")
	_expect(not Rules.from_fire_hit(1.0e308, {"duration": 3.0, "rate_fraction": 2.0}).ok, "Rate multiplication overflow is rejected")
	_expect(not Rules.from_fire_hit(1.0e308, {"duration": 60.0, "rate_fraction": 1.0}).ok, "Lifetime budget overflow is rejected")
	_expect(not Rules.from_fire_hit(1.0e-300, {"duration": 3.0, "rate_fraction": 1.0e-300}).ok, "Positive multiplication underflow cannot create an inert status")
	completed = true


func _test_independent_actors() -> void:
	var runtime := Runtime.new()
	var player: Dictionary = runtime.apply("player", 0, 11, 20, 3, 10)
	var monster: Dictionary = runtime.apply("monster", 11, 0, 30, 3, 10)
	_expect(player.ok and monster.ok and player.segments.is_empty() and monster.segments.is_empty(), "Applications cause no instant damage")
	_near(_amount(runtime.advance_target("monster", 11, 11)), 30.0, "Monster clock advances independently")
	var states: Array[Dictionary] = runtime.statuses()
	_expect(states[1].target_kind == "player" and states[1].last_time == 10.0 and states[1].remaining == 3.0, "Advancing a monster leaves player clock and remaining lifetime untouched")
	_near(_amount(runtime.advance_target("player", 0, 10.5)), 10.0, "Player may independently advance to an earlier timestamp")
	var ended: Dictionary = runtime.advance_all(100)
	_expect(ended.ok and ended.segments.size() == 2 and runtime.is_empty(), "Final settlement reclaims both expired targets")
	_near(ended.segments[0].raw_amount, 60.0, "Monster exact remaining interval settles")
	_near(ended.segments[1].raw_amount, 50.0, "Player exact remaining interval settles")
	runtime.apply("player", 0, 11, 20, 3, 0)
	runtime.apply("monster", 11, 0, 30, 3, 0)
	_expect(runtime.remove("monster", 11).removed, "Target death removes its own incoming burn")
	var survived: Dictionary = runtime.advance_target("player", 0, 3)
	_expect(survived.segments[0].source_id == 11, "A dead source keeps its outgoing burn attribution")
	_near(_amount(survived), 60.0, "Source death does not cancel outgoing burn")
	completed = true


func _test_replacement() -> void:
	var runtime := Runtime.new()
	var original: Dictionary = {"skill_id": "firebolt", "cast_id": 1, "projectile_id": 2, "phase": "outbound"}
	runtime.apply("monster", 1, 0, 10, 3, 0, original)
	var weak: Dictionary = runtime.apply("monster", 1, 7, 9, 3, 1, {"skill_id": "weak"})
	_expect(weak.ok and not weak.applied and weak.reason == "weaker", "Weaker burn is ignored after settlement")
	_near(_amount(weak), 10.0, "Ignored weaker application still settles old interval")
	_expect(runtime.statuses()[0].remaining == 2.0 and runtime.statuses()[0].provenance == original, "Weaker burn neither refreshes nor changes attribution")
	var stronger: Dictionary = runtime.apply("monster", 1, 8, 20, 3, 1.5, {"skill_id": "strong"})
	_expect(stronger.applied and stronger.reason == "stronger", "Strictly stronger raw DPS replaces the status")
	_near(_amount(stronger), 5.0, "Old DPS settles to replacement timestamp")
	_expect(stronger.segments[0].source_id == 0 and stronger.segments[0].provenance == original, "Replacement segment retains old source and provenance")
	_expect(runtime.statuses()[0].remaining == 3.0 and runtime.statuses()[0].source_id == 8, "Stronger application resets duration with new source")
	var equal: Dictionary = runtime.apply("monster", 1, 9, 20.0, 3, 2, {"skill_id": "equal"})
	_expect(equal.applied and equal.reason == "equal", "Exact numeric DPS equality refreshes the burn")
	_near(_amount(equal), 10.0, "Equal refresh settles the previous source first")
	_expect(equal.segments[0].source_id == 8, "Equal refresh settles original attribution")
	var final: Dictionary = runtime.advance_all(5)
	_near(_amount(final), 60.0, "Equal refresh receives the complete new duration")
	_expect(final.segments[0].source_id == 9 and final.segments[0].provenance.skill_id == "equal", "Refreshed interval uses the latest equal source")
	_near(_amount(weak) + _amount(stronger) + _amount(equal) + _amount(final), 85.0, "Replacement timeline has no skipped or double-paid interval")
	runtime.apply("monster", 1, 0, 10.0, 3, 0)
	_expect(runtime.apply("monster", 1, 0, 10.0 - 1.0e-12, 3, 0).reason == "weaker", "Near equality does not refresh weaker DPS")
	_expect(runtime.apply("monster", 1, 0, 10.0 + 1.0e-12, 3, 0).reason == "stronger", "Near equality does not conceal stronger DPS")
	completed = true


func _test_time_boundaries() -> void:
	var runtime := Runtime.new()
	runtime.apply("monster", 1, 0, 10, 3, 5)
	var snapshot: PackedByteArray = var_to_bytes(runtime.statuses())
	_expect(runtime.advance_target("monster", 1, 5).segments.is_empty(), "Zero elapsed time emits no segment")
	_expect(runtime.advance_all(5).segments.is_empty() and var_to_bytes(runtime.statuses()) == snapshot, "Zero all-target advance is an exact no-op")
	var expiry: Dictionary = runtime.apply("monster", 1, 9, 1, 1, 8)
	_expect(expiry.reason == "new" and expiry.applied, "At expiry even a weaker new burn is admitted")
	_near(_amount(expiry), 30.0, "Applying at expiry settles the exact old lifetime")
	_expect(expiry.segments[0].from_time == 5.0 and expiry.segments[0].to_time == 8.0, "Segment reports only the active interval")
	_near(_amount(runtime.advance_all(1000000)), 1.0, "Huge advance stops precisely at new expiry")
	_expect(runtime.advance_all(0).ok and runtime.advance_target("monster", 1, 0).ok, "Expired-target clocks are discarded by the documented bounded-clock policy")
	runtime.apply("monster", 1, 0, 10, 0.25, 4)
	var huge: Dictionary = runtime.advance_all(1.0e300)
	_near(_amount(huge), 2.5, "Very large absolute time never multiplies DPS by inactive time")
	_expect(huge.segments[0].from_time == 4.0 and huge.segments[0].to_time == 4.25, "Large-time segment endpoint is the active expiry")
	_expect(runtime.is_empty() and runtime.advance_all(1.0e300).segments.is_empty(), "Expired burn is reclaimed and cannot pay twice")
	runtime.apply("monster", 1, 0, 10, 3, 7)
	runtime.reset()
	_expect(runtime.is_empty() and runtime.statuses() == Runtime.new().statuses(), "Reset clears all statuses and clocks")
	_expect(runtime.apply("monster", 1, 0, 10, 3, 0).ok, "Reset permits a new run from zero")
	completed = true


func _test_partition_equivalence() -> void:
	var large := Runtime.new()
	var split := Runtime.new()
	for runtime in [large, split]:
		runtime.apply("monster", 2, 0, 17.25, 3, 0, {"phase": "outbound"})
		runtime.apply("player", 0, 2, 6.75, 2.75, 0, {"phase": "telegraph"})
	var expected: float = _amount(large.advance_all(100.0))
	var actual: float = 0.0
	for step: int in range(1, 81):
		var result: Dictionary = split.advance_all(float(step) / 20.0)
		_expect(result.ok, "Every split-time advance is valid")
		actual += _amount(result)
		for segment: Dictionary in result.segments:
			_expect(segment.to_time <= 3.0 and segment.to_time > segment.from_time, "Split segments never extend beyond the active expiry")
		if step == 60: _expect(split.is_empty(), "Split advancement reclaims the status at exact expiry without drift")
	_near(actual, expected, "Split and large time integrate equivalent total raw amount")
	_expect(large.is_empty() and split.is_empty(), "Both time partitions expire and reclaim the same statuses")
	# Event timestamps are fixed while extra advances partition their intervals.
	large.reset()
	split.reset()
	large.apply("monster", 1, 0, 10, 3, 0)
	split.apply("monster", 1, 0, 10, 3, 0)
	expected = _amount(large.apply("monster", 1, 0, 20, 3, 1.25))
	actual = _amount(split.advance_target("monster", 1, 0.5))
	actual += _amount(split.apply("monster", 1, 0, 20, 3, 1.25))
	expected += _amount(large.apply("monster", 1, 0, 15, 3, 2.5))
	actual += _amount(split.advance_target("monster", 1, 2.0))
	actual += _amount(split.apply("monster", 1, 0, 15, 3, 2.5))
	expected += _amount(large.advance_all(8))
	actual += _amount(split.advance_all(3))
	actual += _amount(split.advance_all(8))
	_near(actual, expected, "Replacement and ignored application remain invariant under extra time partitions")
	completed = true


func _test_invalid_inputs() -> void:
	var runtime := Runtime.new()
	runtime.apply("monster", 1, 0, 10, 3, 1, {"skill_id": "original"})
	var baseline: PackedByteArray = var_to_bytes(runtime.statuses())
	var base: Array = ["monster", 1, 0, 20, 3, 2, {}]
	var bad_fields: Array = [
		[null, true, 1, "", "enemy", &"monster", [], {}],
		[null, true, false, "1", 1.0, -1, 0, [], {}, NAN, INF],
		[null, true, false, "0", 0.0, -1, [], {}, NAN, INF],
		[null, true, false, "20", &"20", 0, -1, [], {}, NAN, INF, -INF],
		[null, true, false, "3", 0, -1, 60.01, [], {}, NAN, INF, -INF],
		[null, true, false, "2", -1, [], {}, NAN, INF, -INF, 0.5],
		[null, true, 1, "", [], {"unknown": 1}, {1: 1}, {&"skill_id": "x"},
			{"skill_id": &"x"}, {"phase": 1}, {"skill_id": "x".repeat(129)}, {"phase": "x".repeat(129)},
			{"cast_id": 1.0}, {"cast_id": -1}, {"projectile_id": true}, {"projectile_id": []},
			{"skill_id": {"nested": []}}, {"phase": "x", "cast_id": 1, "projectile_id": 1, "skill_id": "x", "extra": 0}],
	]
	for index: int in range(bad_fields.size()):
		for invalid: Variant in bad_fields[index]:
			var args: Array = base.duplicate(true)
			args[index] = invalid
			var result: Dictionary = runtime.callv("apply", args)
			_expect(not result.ok and not result.applied and result.segments.is_empty() and not result.reason.is_empty(), "Malformed application rejects before any settlement, field %d" % index)
			_expect(var_to_bytes(runtime.statuses()) == baseline, "Malformed application keeps exact state, field %d" % index)
	for args: Array in [["player", 1, 0, 20, 3, 2], ["player", -1, 0, 20, 3, 2],
			["monster", 1, 0, 1.0e308, 60.0, 2], ["monster", 1, 0, 1.0e-300, 1.0e-300, 2],
			["monster", 1, 0, 20, 3, 1.0e300]]:
		_expect(not runtime.callv("apply", args).ok and var_to_bytes(runtime.statuses()) == baseline, "Invalid actor or nonrepresentable arithmetic is atomic")
	for invalid: Variant in [null, true, false, "2", [], {}, -1, NAN, INF, -INF, 0.5]:
		_expect(not runtime.advance_target("monster", 1, invalid).ok, "Target advance rejects invalid or reversed time")
		_expect(not runtime.advance_all(invalid).ok, "All-target advance rejects invalid or reversed time")
		_expect(var_to_bytes(runtime.statuses()) == baseline, "Invalid advances preserve every status")
	for actor: Array in [[&"monster", 1], ["monster", 1.0], ["monster", 0], ["player", 1], ["other", 1], ["monster", true]]:
		_expect(not runtime.advance_target(actor[0], actor[1], 2).ok and not runtime.remove(actor[0], actor[1]).ok, "Advance/remove reject malformed actor identity")
		_expect(var_to_bytes(runtime.statuses()) == baseline, "Malformed actor operation cannot settle or remove anything")
	_expect(runtime.remove("monster", 99).ok and not runtime.remove("monster", 99).removed, "Removing absent valid actor is an idempotent no-op")
	_expect(runtime.advance_target("monster", 99, 0).ok and var_to_bytes(runtime.statuses()) == baseline, "Absent target stores no hidden clock")
	completed = true


func _test_atomic_advance_all() -> void:
	var runtime := Runtime.new()
	runtime.apply("monster", 1, 0, 10, 3, 0)
	runtime.apply("monster", 2, 0, 20, 3, 2)
	var before: PackedByteArray = var_to_bytes(runtime.statuses())
	var result: Dictionary = runtime.advance_all(1)
	_expect(not result.ok and result.segments.is_empty(), "One reversed active clock rejects the whole all-target operation")
	_expect(var_to_bytes(runtime.statuses()) == before, "Earlier valid target is not partially committed")
	result = runtime.advance_all(3)
	_near(_amount(result), 50.0, "A later valid operation includes all previously uncommitted damage")
	_expect(result.segments[0].target_id == 1 and result.segments[1].target_id == 2, "All-target segments retain stable actor order")
	runtime.reset()
	runtime.apply("monster", 1, 0, 10.0, 1.0, 0)
	runtime.apply("monster", 2, 0, 1.0e-300, 1.0, 0)
	before = var_to_bytes(runtime.statuses())
	result = runtime.advance_all(1.0e-300)
	_expect(not result.ok and result.segments.is_empty() and var_to_bytes(runtime.statuses()) == before, "One segment underflow rejects all advancement atomically")
	result = runtime.apply("monster", 2, 0, 20, 3, 1.0e-300)
	_expect(not result.ok and not result.applied and var_to_bytes(runtime.statuses()) == before, "Replacement cannot discard an unrepresentable old interval")
	_expect(runtime.advance_all(1).ok and runtime.is_empty(), "A representable later interval can settle after rejected underflow")
	completed = true


func _test_capacity_order_and_copy() -> void:
	var runtime := Runtime.new()
	var provenance: Dictionary = {"skill_id": "firebolt", "cast_id": 0, "projectile_id": 9, "phase": ""}
	runtime.apply("player", 0, 1, 10, 3, 0, provenance)
	provenance.skill_id = "caller mutation"
	_expect(runtime.statuses()[0].provenance.skill_id == "firebolt", "Input provenance is detached on admission")
	var detached: Array[Dictionary] = runtime.statuses()
	detached[0].raw_dps = 9000
	detached[0].provenance.phase = "mutation"
	detached.clear()
	_expect(runtime.statuses()[0].raw_dps == 10.0 and runtime.statuses()[0].provenance.phase == "", "Nested status outputs are detached")
	var paid: Dictionary = runtime.advance_target("player", 0, 0.5)
	paid.segments[0].provenance.skill_id = "segment mutation"
	_expect(runtime.statuses()[0].provenance.skill_id == "firebolt", "Nested segment output cannot mutate the active status")
	for id: int in range(100, 0, -1):
		_expect(runtime.apply("monster", id, 0, 10, 3, 0).ok, "Within-bound actor is admitted")
	var ordered: Array[Dictionary] = runtime.statuses()
	_expect(ordered.size() == Runtime.MAX_TARGETS and ordered.back().target_kind == "player", "Capacity includes player and deterministic lexical kind order")
	for index: int in range(100):
		_expect(ordered[index].target_kind == "monster" and ordered[index].target_id == index + 1, "Monster IDs sort numerically, independent of insertion")
	var before: PackedByteArray = var_to_bytes(ordered)
	var rejected: Dictionary = runtime.apply("monster", 101, 0, 10, 3, 0)
	_expect(not rejected.ok and var_to_bytes(runtime.statuses()) == before, "Target 102 is atomically rejected at full capacity")
	_expect(runtime.apply("monster", 1, 0, 20, 3, 0).ok, "Existing target can replace at capacity")
	_expect(runtime.remove("monster", 100).removed and runtime.apply("monster", 101, 0, 10, 3, 0).ok, "Removal reclaims a bounded slot")
	var final: Dictionary = runtime.advance_all(100)
	_expect(final.ok and final.segments.size() == 101 and runtime.is_empty(), "Every active target settles once and all capacity is reclaimed")
	_expect(final.segments.back().target_kind == "player", "Segment identity order matches status identity order")
	_expect(runtime.apply("monster", 1000000, 0, 10, 3, 0).ok, "Expired IDs leave no unbounded clock history")
	runtime.reset()
	_expect(runtime.is_empty(), "Reset clears the last status")
	completed = true
