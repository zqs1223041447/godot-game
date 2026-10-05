extends SceneTree
## Pure shock contract only. Gameplay settlement, damage channels, and actor
## liveness belong to integration tests; no scene, save, or actor is loaded here.
const Rules = preload("res://scripts/combat/shock_rules.gd")
const Runtime = preload("res://scripts/combat/shock_runtime.gd")
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(520052)
	var expected_random: Array = [randi(), randi(), randi()]
	seed(520052)
	_case(_test_rules, "frozen policies and positive settled lightning")
	_case(_test_projectile_batch_preflight, "original projectile ordering and complete-batch historical preflight")
	_case(_test_time_boundaries, "original event time and half-open lifetime")
	_case(_test_same_time_order, "same-time read settle attach sequence")
	_case(_test_refresh_and_old_application, "exact refresh and old application atomicity")
	_case(_test_continuous_refresh, "continuous shock, future first application, and expired gaps")
	_case(_test_expiry_crossing_window, "ULP expiry-crossing ties and retained prior interval")
	_case(_test_history_floor, "bounded history eviction, explicit read floor, and sequential large deltas")
	_case(_test_cleanup, "target removal, source lifetime, and explicit cleanup")
	_case(_test_copies, "detached caller inputs and getter results")
	_case(_test_capacity_and_order, "101-target bound and deterministic identity order")
	_case(_test_invalid_inputs, "strict type validation and error atomicity")
	_expect([randi(), randi(), randi()] == expected_random, "Rules and all runtime operations preserve global RNG")
	print("Shock rules/runtime: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	completed = false
	test.call()
	_expect(completed, "Case completes without script exceptions: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) <= 1.0e-12, label)


func _adjacent_float(value: float, direction: int) -> float:
	var bits := PackedByteArray()
	bits.resize(8)
	bits.encode_double(0, value)
	bits.encode_u64(0, bits.decode_u64(0) + direction)
	return bits.decode_double(0)


func _snapshot(runtime: RefCounted) -> PackedByteArray:
	return var_to_bytes([runtime.statuses(0), runtime.statuses(10), runtime.statuses(10.5),
		runtime.statuses(11), runtime.statuses(11.5), runtime.statuses(12), runtime.is_empty(), runtime.read_floor()])


func _reject_application(runtime: RefCounted, result: Dictionary, before: PackedByteArray, label: String) -> void:
	_expect(not result.ok and not result.applied and not result.refreshed and not result.reason.is_empty(), label)
	_expect(_snapshot(runtime) == before, "Rejected application leaves every state unchanged: " + label)


func _test_rules() -> void:
	_expect(Rules.PLAYER_POLICY == {"duration": 2.0, "hit_damage_taken_increased": 0.15,
		"hit_multiplier": 0.80, "mana_multiplier": 1.20}, "Player prototype policy is exactly frozen")
	_expect(Rules.ENEMY_POLICY == {"duration": 1.0, "hit_damage_taken_increased": 0.15}, "Enemy prototype policy is exactly frozen")
	var input_policy: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
	var before: PackedByteArray = var_to_bytes(input_policy)
	for amount: Variant in [1, 1.0e-300, 80.0, 1.0e308]:
		var result: Dictionary = Rules.from_lightning_hit(amount, input_policy)
		_expect(result.ok and result.duration == 2.0 and result.hit_damage_taken_increased == 0.15,
			"Any positive actual lightning hit uses the same strength without damage scaling")
	_expect(var_to_bytes(input_policy) == before, "Rules never mutate the caller's policy")
	var enemy: Dictionary = Rules.from_lightning_hit(1, Rules.ENEMY_POLICY)
	_expect(enemy.ok and enemy.duration == 1.0 and enemy.hit_damage_taken_increased == 0.15, "Enemy prototype lasts one second")
	for invalid: Variant in [null, true, false, "1", &"1", [], {}, NAN, INF, -INF, -1, 0, -0.0]:
		var result: Dictionary = Rules.from_lightning_hit(invalid, Rules.PLAYER_POLICY)
		_expect(not result.ok and result.duration == 0.0 and result.hit_damage_taken_increased == 0.0,
			"Malformed, nonpositive, or nonfinite lightning creates no profile")
	for invalid: Variant in [null, true, 1, "player", [], {}, {"duration": 2.0}, {"hit_damage_taken_increased": 0.15}]:
		_expect(not Rules.from_lightning_hit(1, invalid).ok, "Incomplete or wrongly typed policies are rejected")
	for field: String in Rules.POLICY_KEYS:
		for invalid: Variant in [null, true, false, "1", &"1", [], {}, NAN, INF, -INF, -1, 0]:
			var bad: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
			bad[field] = invalid
			_expect(not Rules.from_lightning_hit(1, bad).ok, "Policy field rejects invalid values: " + field)
		var unfrozen: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
		unfrozen[field] = float(unfrozen[field]) + 0.01
		_expect(not Rules.from_lightning_hit(1, unfrozen).ok, "Policy cannot introduce new strengths or tuning: " + field)
	for key: Variant in ["unknown", 3, false, &"duration"]:
		var bad: Dictionary = {"hit_damage_taken_increased": 0.15}
		bad[key] = 1.0
		if typeof(key) != TYPE_STRING_NAME: bad["duration"] = 1.0
		_expect(not Rules.from_lightning_hit(1, bad).ok, "Unknown and non-String policy keys are rejected")
	var int_duration: Dictionary = Rules.ENEMY_POLICY.duplicate(true)
	int_duration.duration = 1
	_expect(Rules.from_lightning_hit(1, int_duration).ok, "Numerically exact integer duration remains valid")
	var detached: Dictionary = Rules.from_lightning_hit(1, input_policy)
	detached.duration = 100
	_expect(Rules.from_lightning_hit(1, input_policy).duration == 2.0, "Rule outputs are independently owned")
	completed = true


func _test_time_boundaries() -> void:
	var runtime := Runtime.new()
	_expect(runtime.status_at("monster", 1, 0).ok and not runtime.status_at("monster", 1, 0).active, "Missing status is a valid inactive read")
	var result: Dictionary = runtime.apply("monster", 1, 0, 10.0, Rules.PLAYER_POLICY)
	_expect(result.ok and result.applied and not result.refreshed and result.reason == "new", "First positive-hit application creates a new status")
	var before: PackedByteArray = _snapshot(runtime)
	for at: float in [0.0, 9.0, 10.0 - 1.0e-12]:
		var query: Dictionary = runtime.status_at("monster", 1, at)
		_expect(query.ok and not query.active and query.hit_damage_taken_increased == 0.0 and query.status.is_empty(), "Queries before application never observe future shock")
	for at: float in [10.0, 11.0, 12.0 - 1.0e-12]:
		var query: Dictionary = runtime.status_at("monster", 1, at)
		_expect(query.ok and query.active and query.hit_damage_taken_increased == 0.15, "Application endpoint and pre-expiry timestamps are active")
		_near(query.status.remaining_seconds, 12.0 - at, "Remaining time derives from the absolute expiry")
	for at: float in [12.0, 12.0 + 1.0e-12, 1.0e300]:
		var query: Dictionary = runtime.status_at("monster", 1, at)
		_expect(query.ok and not query.active and query.hit_damage_taken_increased == 0.0 and query.status.is_empty(), "Expiry equality and later timestamps are inactive")
	_expect(_snapshot(runtime) == before, "Arbitrary query order never advances or discards state")
	_expect(not runtime.status_at("player", 0, 10.0).active, "Monster status never propagates to the player")
	_expect(runtime.statuses(9.0).is_empty() and runtime.statuses(12.0).is_empty(), "Presentation list excludes future and expired shock")
	_expect(runtime.apply("player", 0, 12, 0.0, Rules.ENEMY_POLICY).ok, "Player and monster use independent timestamps")
	_expect(runtime.status_at("player", 0, 0.0).active and not runtime.status_at("player", 0, 1.0).active, "Enemy shock is active for precisely its one-second half-open interval")
	runtime.reset()
	_expect(runtime.apply("monster", 1, 0, 1.0e16, Rules.PLAYER_POLICY).ok, "Large timestamp accepts a representable two-second expiry")
	_expect(runtime.status_at("monster", 1, 1.0e16).active and not runtime.status_at("monster", 1, 1.0e16 + 2.0).active, "Large timestamp keeps exact endpoints")
	completed = true


func _test_projectile_batch_preflight() -> void:
	var step: float = 1.0 / 60.0
	var legal: Array = [{"time": 0.008498710574771513, "payload": {"skill_id": "bolt"}},
		{"time": 0.008495442978210952}, {"time": 0.008485886630782776}]
	var bytes: PackedByteArray = var_to_bytes(legal)
	for start: float in [0.0, 1000000.0]:
		_expect(Rules.projectile_batch_error(legal, start, start + step, start).is_empty(), "Established non-transitive adjacent raw-offset tie chain remains legal at any uptime")
	_expect(var_to_bytes(legal) == bytes, "Whole-batch preflight preserves raw times, order, and nested payloads")
	for start: float in [1.0, 1000000.0, 1000000000.0]:
		var end: float = start + step
		var endpoint: Array = [{"time": step}]
		var endpoint_bytes: PackedByteArray = var_to_bytes(endpoint)
		_expect(Rules.projectile_batch_error(endpoint, start, end, start, step).is_empty(), "Original delta admits a raw endpoint even when accumulated subtraction rounds the window shorter")
		_expect(var_to_bytes(endpoint) == endpoint_bytes, "Endpoint preflight preserves the actual simulation offset")
	_expect((1.0 + step) - 1.0 < step, "Endpoint fixture exercises the reachable shorter reconstructed window")
	_expect(not Rules.projectile_batch_error([{"time": step}], 1.0, 1.0 + step, 1.0).is_empty(), "Four-argument compatibility retains its exact reconstructed-window bound")
	_expect(not Rules.projectile_batch_error([{"time": step + 0.001}], 1.0, 1.0 + step, 1.0, step).is_empty(), "Original delta does not introduce tolerance above the actual simulation width")
	_expect(not Rules.projectile_batch_error([{"time": step}], 1.0, 1.0 + step, 1.0 + step + 0.001, step).is_empty(), "Original-delta endpoint still validates absolute clamped time against history floor")
	for invalid_delta: Variant in [true, false, "0", [], {}, NAN, INF, -INF, -1.0]:
		_expect(not Rules.projectile_batch_error(legal, 1.0, 1.0 + step, 1.0, invalid_delta).is_empty(), "Optional original delta rejects malformed, negative, and nonfinite values")
	_expect(var_to_bytes(legal) == bytes, "Malformed original delta never changes the event batch")
	_expect(Rules.projectile_batch_error([], 0, 0, 0).is_empty(), "Empty zero-width batch is valid")
	_expect(Rules.projectile_batch_error([{"time": 0}], 5, 5, 5).is_empty(), "Exact-time event accepts zero width and exact history floor")
	_expect(Rules.projectile_batch_error([{"time": 0.0}, {"time": 1.0}, {"time": 1000000.0}], 0.0, 1000000.0, 0.0).is_empty(), "Strictly ordered large-delta batches do not need a one-second total-width cap")
	_expect(Rules.projectile_batch_error([{"time": 200000.0}, {"time": 199999.00000000003}], 0.0, 200000.0, 0.0).is_empty(), "A legal approximate tie with reversal strictly below one second fits retained history")
	for later: float in [199999.0, 199998.5]:
		var events: Array = [{"time": 200000.0}, {"time": later}]
		_expect(Rules.EmberClock.offsets(events).ok, "Boundary fixture is legal under the unchanged raw-offset comparator")
		_expect(not Rules.projectile_batch_error(events, 0.0, 200000.0, 0.0).is_empty(), "Exactly-one-second or larger reversal is rejected before any hit")
	var long_chain: Array = [{"time": 200000.0}, {"time": 199999.4}, {"time": 199998.8}]
	_expect(Rules.EmberClock.offsets(long_chain).ok and not Rules.projectile_batch_error(long_chain, 0.0, 200000.0, 0.0).is_empty(), "Cumulative tie reversal is checked against normalized offset, not only adjacent differences")
	_expect(not Rules.projectile_batch_error([{"time": 0.01}, {"time": 0.009}], 1000000.0, 1000000.0 + step, 1000000.0).is_empty(), "Large elapsed time cannot legalize a real reverse raw-offset jump")
	for bad: Variant in [null, {}, true, [null], [{}], [{"time": true}], [{"time": "0"}],
		[{"time": NAN}], [{"time": INF}], [{"time": -0.001}]]:
		_expect(not Rules.projectile_batch_error(bad, 0.0, step, 0.0).is_empty(), "Malformed event batch is explicitly rejected")
	for invalid: Variant in [null, true, false, "0", [], {}, NAN, INF, -INF, -1]:
		_expect(not Rules.projectile_batch_error([], invalid, 1.0, 0.0).is_empty(), "Batch start validates exact numeric time")
		_expect(not Rules.projectile_batch_error([], 0.0, invalid, 0.0).is_empty(), "Batch end validates exact numeric time")
		_expect(not Rules.projectile_batch_error([], 0.0, 1.0, invalid).is_empty(), "Batch read floor validates exact numeric time")
	_expect(not Rules.projectile_batch_error([], 2.0, 1.0, 0.0).is_empty(), "Batch window cannot run backward")
	var runtime := Runtime.new()
	runtime.apply("monster", 1, 0, 0.0, Rules.PLAYER_POLICY)
	var state_bytes: PackedByteArray = var_to_bytes([runtime.read_floor(), runtime.statuses(0.0)])
	for invalid_late: Array in [[{"time": 0.001}, {"time": 0.2}],
		[{"time": 0.001}, {"time": NAN}]]:
		var original: PackedByteArray = var_to_bytes(invalid_late)
		var reason: String = Rules.projectile_batch_error(invalid_late, 0.0, step, runtime.read_floor())
		var dispatched: int = 0
		if reason.is_empty():
			for event: Dictionary in invalid_late:
				dispatched += 1
				runtime.apply("monster", 1, 7, event.time, Rules.PLAYER_POLICY)
		_expect(not reason.is_empty() and dispatched == 0, "Valid first event followed by invalid late event rejects the complete batch before dispatch")
		_expect(var_to_bytes(invalid_late) == original and var_to_bytes([runtime.read_floor(), runtime.statuses(0.0)]) == state_bytes, "Rejected complete batch changes neither input nor runtime")
	var historical: Array = [legal[0].duplicate(true), legal[1].duplicate(true)]
	var historical_bytes: PackedByteArray = var_to_bytes(historical)
	runtime.prune(0.008497)
	var floor_bytes: PackedByteArray = var_to_bytes([runtime.read_floor(), runtime.statuses(runtime.read_floor())])
	_expect(not Rules.projectile_batch_error(historical, 0.0, step, runtime.read_floor()).is_empty(), "Legal adjacent tie with a later-dispatched event below history floor fails whole-batch validation")
	_expect(var_to_bytes(historical) == historical_bytes and var_to_bytes([runtime.read_floor(), runtime.statuses(runtime.read_floor())]) == floor_bytes, "Historical preflight rejection leaves input, floor, and shock unchanged")
	_expect(Rules.projectile_batch_error([{"time": 0.008497}], 0.0, step, runtime.read_floor()).is_empty(), "Preflight accepts an event exactly at the retained floor")
	completed = true


func _test_same_time_order() -> void:
	var runtime := Runtime.new()
	# Caller snapshots the modifier before settlement, then attaches afterward.
	var triggering_read: Dictionary = runtime.status_at("monster", 1, 2.0)
	runtime.apply("monster", 1, 0, 2.0, Rules.PLAYER_POLICY, {"cast_id": 1})
	_expect(not triggering_read.active and triggering_read.hit_damage_taken_increased == 0.0, "Triggering read cannot gain the shock attached after its settlement")
	var later_same_time_read: Dictionary = runtime.status_at("monster", 1, 2.0)
	_expect(later_same_time_read.active and later_same_time_read.hit_damage_taken_increased == 0.15, "A later ordered hit at the same timestamp sees existing shock")
	var refreshed: Dictionary = runtime.apply("monster", 1, 17, 2.0, Rules.PLAYER_POLICY, {"cast_id": 2})
	_expect(refreshed.ok and refreshed.applied and refreshed.refreshed, "Exact-time application refreshes the existing fixed-strength status")
	var state: Dictionary = runtime.status_at("monster", 1, 2.0).status
	_expect(state.source_id == 17 and state.provenance.cast_id == 2 and state.expires_at == 4.0, "Same-time caller order chooses the final source and provenance")
	_expect(runtime.statuses(2.0).size() == 1 and state.hit_damage_taken_increased == 0.15, "Repeated same-time applications never stack")
	_expect(later_same_time_read.status.source_id == 0 and later_same_time_read.status.provenance.cast_id == 1, "Earlier read remains detached after another same-time application")
	completed = true


func _test_refresh_and_old_application() -> void:
	var runtime := Runtime.new()
	runtime.apply("monster", 7, 0, 10.0, Rules.PLAYER_POLICY, {"skill_id": "bolt", "cast_id": 1})
	var refresh: Dictionary = runtime.apply("monster", 7, 33, 11.0, Rules.PLAYER_POLICY, {"skill_id": "chain", "cast_id": 2})
	_expect(refresh.ok and refresh.refreshed and refresh.applied and refresh.reason == "refreshed", "Later active hit refreshes shock")
	var state: Dictionary = runtime.status_at("monster", 7, 11.0).status
	_expect(state.applied_at == 10.0 and state.refreshed_at == 11.0 and state.expires_at == 13.0 and state.remaining_seconds == 2.0, "Refresh preserves continuous interval start and uses its own deadline")
	_expect(state.source_id == 33 and state.provenance.skill_id == "chain", "Refresh takes the latest source and provenance")
	var before: PackedByteArray = var_to_bytes(runtime.statuses(11.0))
	for older: float in [0.0, 10.0, 11.0 - 1.0e-12]:
		var result: Dictionary = runtime.apply("monster", 7, 99, older, Rules.PLAYER_POLICY, {"skill_id": "nova", "cast_id": 3})
		_expect(result.ok and not result.applied and not result.refreshed and result.reason == "older_application", "Valid older application is an explicit no-op")
		_expect(var_to_bytes(runtime.statuses(11.0)) == before, "Older application preserves newer time, expiry, source, and provenance")
		_expect(runtime.status_at("monster", 7, older).active == (older >= 10.0), "Older read sees only the continuous preexisting shock interval")
	var expired: Dictionary = runtime.apply("monster", 7, 5, 13.0, Rules.PLAYER_POLICY)
	_expect(expired.ok and expired.applied and not expired.refreshed and expired.reason == "new", "Application at exact expiry starts a new lifetime")
	_expect(runtime.status_at("monster", 7, 13.0).status.expires_at == 15.0 and runtime.status_at("monster", 7, 13.0).status.applied_at == 13.0, "New lifetime resets its interval start and absolute deadline")
	runtime.reset()
	runtime.apply("monster", 7, 1, 1000000.0, Rules.PLAYER_POLICY)
	var original: Dictionary = runtime.status_at("monster", 7, 1000000.0).status
	var near_tie: Dictionary = runtime.apply("monster", 7, 2, 1000000.0 - 1.0e-7, Rules.PLAYER_POLICY)
	_expect(near_tie.reason == "older_application" and not near_tie.applied, "Large accumulated time never creates a fuzzy refresh allowance")
	_expect(runtime.status_at("monster", 7, 1000000.0).status == original, "Large-time near tie leaves newer state unchanged")
	_expect(not runtime.status_at("monster", 7, 1000000.0 - 1.0e-7).active, "Near-tie read uses original hit time rather than normalized later clock")
	completed = true


func _test_continuous_refresh() -> void:
	var continuous := Runtime.new()
	continuous.apply("monster", 1, 0, 0.0, Rules.PLAYER_POLICY, {"cast_id": 1})
	continuous.apply("monster", 1, 7, 1.000002, Rules.PLAYER_POLICY, {"cast_id": 2})
	var newer: Dictionary = continuous.status_at("monster", 1, 1.000002).status
	_expect(newer.applied_at == 0.0 and newer.refreshed_at == 1.000002, "Active refresh preserves the beginning of one continuous interval")
	_near(newer.expires_at, 3.000002, "Continuous refresh extends expiry by the frozen two-second duration")
	_expect(not continuous.status_at("monster", 1, newer.expires_at).active, "Continuous refresh preserves exact expiry equality using its authoritative deadline")
	var earlier: Dictionary = continuous.status_at("monster", 1, 1.000001)
	_expect(earlier.active and earlier.hit_damage_taken_increased == 0.15, "A slightly earlier original hit retains benefit from preexisting continuous shock")
	var ignored: Dictionary = continuous.apply("monster", 1, 9, 1.000001, Rules.PLAYER_POLICY, {"cast_id": 3})
	_expect(ignored.ok and not ignored.applied and ignored.reason == "older_application", "Earlier near-tie cannot overwrite a newer refresh")
	_expect(continuous.status_at("monster", 1, 1.000002).status == newer, "Earlier near-tie preserves newest expiry, source, provenance, and refresh time")
	var fresh := Runtime.new()
	fresh.apply("monster", 1, 7, 1.000002, Rules.PLAYER_POLICY)
	_expect(not fresh.status_at("monster", 1, 1.000001).active, "Without a preexisting interval, future first application gives no earlier-hit benefit")
	_expect(fresh.status_at("monster", 1, 1.000002).status.applied_at == 1.000002, "First application starts at its original timestamp")
	var after_gap: Dictionary = continuous.apply("monster", 1, 10, 4.0, Rules.PLAYER_POLICY, {"cast_id": 4})
	_expect(after_gap.ok and after_gap.applied and not after_gap.refreshed, "Application after an expired gap starts a separate lifetime")
	var restarted: Dictionary = continuous.status_at("monster", 1, 4.0).status
	_expect(restarted.applied_at == 4.0 and restarted.refreshed_at == 4.0 and restarted.expires_at == 6.0, "Post-gap application resets continuous start and latest refresh time")
	_expect(not continuous.status_at("monster", 1, 3.5).active and not continuous.status_at("monster", 1, 4.0 - 1.0e-12).active, "New post-gap status cannot fill the gap or leak backward")
	_expect(continuous.apply("monster", 1, 11, 3.5, Rules.PLAYER_POLICY).reason == "older_application", "Older gap event cannot overwrite the later new lifetime")
	_expect(continuous.status_at("monster", 1, 4.0).status == restarted, "Ignored gap event leaves new lifetime unchanged")
	completed = true


func _test_cleanup() -> void:
	var runtime := Runtime.new()
	runtime.apply("player", 0, 12, 10.0, Rules.ENEMY_POLICY)
	runtime.apply("monster", 12, 0, 10.0, Rules.PLAYER_POLICY)
	_expect(runtime.remove("monster", 12).removed, "Death cleanup removes the target's incoming shock")
	_expect(runtime.status_at("player", 0, 10.5).active and runtime.status_at("player", 0, 10.5).status.source_id == 12, "Source death retains its outgoing shock attribution")
	_expect(runtime.remove("monster", 12).ok and not runtime.remove("monster", 12).removed, "Removing an absent target is a valid no-op")
	_expect(runtime.prune(10.5).removed == 0, "Frame cleanup preserves unexpired state")
	_expect(runtime.statuses(11.0).is_empty() and not runtime.is_empty(), "Read-only expiry excludes status while retaining storage until cleanup")
	_expect(runtime.prune(11.0).removed == 1 and runtime.is_empty(), "Expiry equality reclaims the status")
	_expect(runtime.prune(100.0).removed == 0, "Repeated prune cannot remove a state twice")
	runtime.reset()
	runtime.apply("monster", 1, 0, 50.0, Rules.PLAYER_POLICY)
	_expect(runtime.prune(10.0).removed == 0 and runtime.status_at("monster", 1, 50.0).active, "Cleanup before application never deletes future state")
	runtime.reset()
	_expect(runtime.is_empty() and runtime.statuses(50.0).is_empty(), "Reset clears every state and identity cache")
	_expect(runtime.apply("monster", 1, 0, 0.0, Rules.PLAYER_POLICY).ok, "Reset permits a fresh run at zero")
	_expect(runtime.prune(1.0e300).removed == 1 and runtime.is_empty(), "Huge frame jump reclaims expired state without damage integration")
	completed = true


func _test_expiry_crossing_window() -> void:
	var runtime := Runtime.new()
	var before_expiry: float = _adjacent_float(2.0, -1)
	var after_expiry: float = _adjacent_float(2.0, 1)
	_expect(before_expiry < 2.0 and after_expiry > 2.0, "Expiry-crossing fixtures are strict adjacent floating-point timestamps")
	runtime.apply("monster", 1, 0, 0.0, Rules.PLAYER_POLICY, {"cast_id": 1, "phase": "old"})
	var old_query: Dictionary = runtime.status_at("monster", 1, before_expiry)
	var added: Dictionary = runtime.apply("monster", 1, 7, after_expiry, Rules.PLAYER_POLICY, {"cast_id": 2, "phase": "new"})
	_expect(added.ok and added.applied and not added.refreshed, "Hit just after expiry creates a new interval")
	var late_old_query: Dictionary = runtime.status_at("monster", 1, before_expiry)
	_expect(late_old_query.ok and late_old_query.active and late_old_query.status == old_query.status, "Later-processed hit just before expiry retains the complete old interval")
	_expect(late_old_query.status.source_id == 0 and late_old_query.status.provenance.cast_id == 1, "Retained interval preserves old source and provenance")
	var boundary: Dictionary = runtime.status_at("monster", 1, 2.0)
	_expect(boundary.ok and not boundary.active, "Exact expired deadline is inactive in the representable gap")
	var newest: Dictionary = runtime.status_at("monster", 1, after_expiry)
	_expect(newest.active and newest.status.source_id == 7 and newest.status.provenance.cast_id == 2, "Post-expiry hit sees the current interval at its inclusive start")
	_expect(runtime.statuses(before_expiry).size() == 1 and runtime.statuses(before_expiry)[0] == old_query.status, "Presentation query returns at most one matching interval per target")
	late_old_query.status.provenance.cast_id = 999
	var historical_list: Array[Dictionary] = runtime.statuses(before_expiry)
	historical_list[0].expires_at = 999.0
	historical_list[0].provenance.phase = "changed"
	_expect(runtime.status_at("monster", 1, before_expiry).status == old_query.status, "Historical query and list entries do not expose cached state")
	var ignored: Dictionary = runtime.apply("monster", 1, 99, before_expiry, Rules.PLAYER_POLICY, {"cast_id": 3})
	_expect(ignored.ok and not ignored.applied and ignored.reason == "older_application", "Older expiry-crossing application cannot overwrite the new interval")
	_expect(runtime.status_at("monster", 1, after_expiry).status == newest.status and runtime.status_at("monster", 1, before_expiry).status == old_query.status, "Ignored application preserves both current and retained intervals")
	var pruned: Dictionary = runtime.prune(after_expiry)
	_expect(pruned.ok and pruned.removed == 0 and runtime.read_floor() == after_expiry, "Frame cleanup discards expired history and advances the floor without removing the live target")
	_expect(not runtime.status_at("monster", 1, before_expiry).ok, "Read before the completed frame is explicitly rejected after history discard")
	_expect(runtime.status_at("monster", 1, after_expiry).active, "Exact frame floor remains readable")
	runtime.reset()
	runtime.apply("monster", 1, 0, 0.0, Rules.PLAYER_POLICY)
	runtime.apply("monster", 1, 7, after_expiry, Rules.PLAYER_POLICY)
	_expect(runtime.remove("monster", 1).removed, "Target cleanup removes current and previous interval together")
	_expect(not runtime.status_at("monster", 1, before_expiry).active and not runtime.status_at("monster", 1, after_expiry).active, "Removed target leaves no incoming historical shock")
	_expect(runtime.is_empty() and runtime.read_floor() == 0.0, "Target removal does not invent a global completed-frame floor")
	completed = true


func _test_history_floor() -> void:
	var runtime := Runtime.new()
	var first_new: float = _adjacent_float(2.0, 1)
	_expect(runtime.read_floor() == 0.0, "Fresh runtime accepts time zero")
	runtime.apply("monster", 1, 0, 0.0, Rules.PLAYER_POLICY, {"cast_id": 1})
	runtime.apply("monster", 1, 7, first_new, Rules.PLAYER_POLICY, {"cast_id": 2})
	var preserved: PackedByteArray = var_to_bytes([runtime.read_floor(), runtime.statuses(1.0), runtime.statuses(first_new)])
	var invalid: Dictionary = runtime.apply("monster", 1, 9, 5.0, Rules.PLAYER_POLICY, {"cast_id": true})
	_expect(not invalid.ok and not invalid.applied, "Invalid second replacement is rejected")
	_expect(var_to_bytes([runtime.read_floor(), runtime.statuses(1.0), runtime.statuses(first_new)]) == preserved, "Rejected replacement cannot evict history or advance the global floor")
	var second_new: Dictionary = runtime.apply("monster", 1, 9, 5.0, Rules.PLAYER_POLICY, {"cast_id": 3})
	_expect(second_new.ok and second_new.applied and not second_new.refreshed, "A second expired replacement is valid for sequential large-time usage")
	_expect(runtime.read_floor() == 2.0, "Evicting the oldest interval advances the floor to its exclusive expiry")
	var before: PackedByteArray = var_to_bytes([runtime.read_floor(), runtime.statuses(first_new), runtime.statuses(5.0)])
	for at: float in [0.0, 1.0, _adjacent_float(2.0, -1)]:
		var query: Dictionary = runtime.status_at("monster", 1, at)
		_expect(not query.ok and not query.active and query.status.is_empty() and query.hit_damage_taken_increased == 0.0, "Discarded historical read fails explicitly rather than silently appearing inactive")
		var applied: Dictionary = runtime.apply("monster", 1, 99, at, Rules.PLAYER_POLICY)
		_expect(not applied.ok and not applied.applied and not applied.refreshed, "Application before retained window is rejected")
		_expect(not runtime.apply("monster", 2, 0, at, Rules.PLAYER_POLICY).ok, "History floor also validates absent targets before mutation")
		_expect(not runtime.prune(at).ok and runtime.statuses(at).is_empty(), "Backward cleanup fails and presentation exposes no discarded history")
		_expect(var_to_bytes([runtime.read_floor(), runtime.statuses(first_new), runtime.statuses(5.0)]) == before, "Out-of-window errors are atomic for current state, previous state, and floor")
	_expect(runtime.status_at("monster", 1, 2.0).ok and not runtime.status_at("monster", 1, 2.0).active, "Exact floor is a legal read even within the old representable gap")
	var exact: Dictionary = runtime.apply("monster", 1, 99, 2.0, Rules.PLAYER_POLICY)
	_expect(exact.ok and not exact.applied and exact.reason == "older_application", "Exact floor is a legal older-application no-op")
	_expect(runtime.status_at("monster", 1, first_new).status.provenance.cast_id == 2, "Only the latest prior interval is retained")
	_expect(runtime.prune(5.0).ok and runtime.read_floor() == 5.0, "Frame completion advances beyond the retained prior interval")
	_expect(not runtime.status_at("monster", 1, first_new).ok and runtime.status_at("monster", 1, 5.0).active, "Pruned history is explicitly closed while current interval remains live")
	var stable_floor: float = runtime.read_floor()
	runtime.remove("monster", 1)
	_expect(runtime.is_empty() and runtime.read_floor() == stable_floor, "Removing all targets retains the global discarded-history boundary")
	runtime.reset()
	_expect(runtime.is_empty() and runtime.read_floor() == 0.0 and runtime.status_at("monster", 1, 0.0).ok, "Reset alone clears targets, prior intervals, and history floor")
	runtime.apply("monster", 1, 0, 0.0, Rules.PLAYER_POLICY)
	runtime.prune(2.0)
	var large: float = 1000000000000.0
	_expect(runtime.apply("monster", 1, 0, large, Rules.PLAYER_POLICY).ok, "A large forward jump remains a valid sequential application")
	_expect(runtime.status_at("monster", 1, large).active and runtime.prune(large + 2.0).removed == 1, "Large sequential interval retains exact expiry and cleanup")
	_expect(runtime.read_floor() == large + 2.0, "Large frame end advances the floor without tolerance growth")
	_expect(runtime.apply("monster", 1, 0, large + 2.0, Rules.PLAYER_POLICY).ok, "Application at exact large-time floor remains legal")
	_expect(not runtime.status_at("monster", 1, large + 1.0).ok, "Large-time floor never permits an older read by fuzzy tolerance")
	completed = true


func _test_copies() -> void:
	var runtime := Runtime.new()
	var policy: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
	var provenance: Dictionary = {"skill_id": "bolt", "cast_id": 8, "projectile_id": 9, "phase": "outbound"}
	runtime.apply("monster", 7, 0, 10.0, policy, provenance)
	policy.duration = 50.0
	policy.hit_damage_taken_increased = 10.0
	provenance.skill_id = "changed"
	provenance.cast_id = 100
	var expected: Dictionary = runtime.status_at("monster", 7, 10.0).status
	_expect(expected.expires_at == 12.0 and expected.hit_damage_taken_increased == 0.15 and expected.provenance.skill_id == "bolt" and expected.provenance.cast_id == 8, "Stored scalar policy and provenance are detached from application inputs")
	var query: Dictionary = runtime.status_at("monster", 7, 10.0)
	query.status.source_id = 99
	query.status.expires_at = 99.0
	query.status.provenance.phase = "changed"
	query.hit_damage_taken_increased = 9.0
	_expect(runtime.status_at("monster", 7, 10.0).status == expected, "Query envelope and nested provenance never expose internal dictionaries")
	var list: Array[Dictionary] = runtime.statuses(10.0)
	list[0].applied_at = 0.0
	list[0].provenance.projectile_id = 999
	list.clear()
	_expect(runtime.status_at("monster", 7, 10.0).status == expected and runtime.statuses(10.0).size() == 1, "List and nested status entries are detached")
	var missing: Dictionary = runtime.status_at("monster", 8, 10.0)
	missing.status.target_id = 8
	_expect(runtime.status_at("monster", 8, 10.0).status.is_empty(), "Empty query results are independent dictionaries")
	completed = true


func _test_capacity_and_order() -> void:
	var runtime := Runtime.new()
	_expect(Runtime.MAX_TARGETS == 101, "Runtime capacity remains 101")
	runtime.apply("player", 0, 50, 10.0, Rules.ENEMY_POLICY)
	for id: int in range(100, 0, -1):
		_expect(runtime.apply("monster", id, 0, 10.0, Rules.PLAYER_POLICY).ok, "Every target within the bounded capacity is accepted")
	var statuses: Array[Dictionary] = runtime.statuses(10.0)
	_expect(statuses.size() == 101 and statuses[100].target_kind == "player", "Deterministic order places monsters before the player")
	for i: int in range(100):
		_expect(statuses[i].target_kind == "monster" and statuses[i].target_id == i + 1, "Monster ordering is numeric rather than lexical")
	var before: PackedByteArray = _snapshot(runtime)
	_reject_application(runtime, runtime.apply("monster", 101, 0, 10.0, Rules.PLAYER_POLICY), before, "New identity beyond capacity is rejected")
	_expect(runtime.apply("monster", 1, 9, 10.0, Rules.PLAYER_POLICY).refreshed, "Existing target refresh remains legal at capacity")
	_expect(runtime.apply("monster", 1, 8, 9.0, Rules.PLAYER_POLICY).reason == "older_application", "Older existing-target no-op remains legal at capacity")
	_expect(runtime.statuses(12.0).is_empty(), "All expired entries are omitted before pruning")
	var full: Dictionary = runtime.apply("monster", 101, 0, 12.0, Rules.PLAYER_POLICY)
	_expect(not full.ok, "Apply does not hide a per-hit full-scan cleanup")
	_expect(runtime.prune(12.0).removed == 101 and runtime.is_empty(), "Once-per-frame prune reclaims the complete bounded store")
	_expect(runtime.apply("monster", 101, 0, 12.0, Rules.PLAYER_POLICY).ok, "Reclaimed capacity accepts a fresh identity")
	for id: int in range(102, 150):
		runtime.prune(float(id))
		_expect(runtime.apply("monster", id, 0, float(id), Rules.PLAYER_POLICY).ok, "Expired identities do not accumulate hidden historical clocks")
	completed = true


func _test_invalid_inputs() -> void:
	var runtime := Runtime.new()
	runtime.apply("monster", 7, 0, 10.0, Rules.PLAYER_POLICY, {"cast_id": 1})
	runtime.apply("player", 0, 7, 10.0, Rules.ENEMY_POLICY, {"phase": "telegraph"})
	var before: PackedByteArray = _snapshot(runtime)
	for kind: Variant in [null, true, 0, [], {}, &"monster", "Monster", "", "enemy"]:
		_reject_application(runtime, runtime.apply(kind, 7, 0, 10.0, Rules.PLAYER_POLICY), before, "Invalid target kind")
		_expect(not runtime.status_at(kind, 7, 10.0).ok and not runtime.remove(kind, 7).ok, "Read and removal validate target kind")
	for id: Variant in [null, true, false, 7.0, "7", &"7", [], {}, -1, 0]:
		_reject_application(runtime, runtime.apply("monster", id, 0, 10.0, Rules.PLAYER_POLICY), before, "Monster ID must be a positive exact integer")
		_expect(not runtime.status_at("monster", id, 10.0).ok and not runtime.remove("monster", id).ok, "Read and removal reject malformed monster IDs")
	for id: Variant in [null, true, false, 0.0, "0", [], {}, -1, 1]:
		_reject_application(runtime, runtime.apply("player", id, 7, 10.0, Rules.ENEMY_POLICY), before, "Player ID must be exact integer zero")
		_expect(not runtime.status_at("player", id, 10.0).ok and not runtime.remove("player", id).ok, "Read and removal reject malformed player IDs")
	for source: Variant in [null, true, false, -1, 0.0, "0", &"0", [], {}]:
		_reject_application(runtime, runtime.apply("monster", 7, source, 10.0, Rules.PLAYER_POLICY), before, "Source ID must be a nonnegative exact integer")
	for time: Variant in [null, true, false, "10", &"10", [], {}, NAN, INF, -INF, -1.0]:
		_reject_application(runtime, runtime.apply("monster", 7, 0, time, Rules.PLAYER_POLICY), before, "Invalid application timestamp")
		var query: Dictionary = runtime.status_at("monster", 7, time)
		_expect(not query.ok and not query.active and query.hit_damage_taken_increased == 0.0 and query.status.is_empty(), "Invalid read returns inert failure")
		_expect(runtime.statuses(time).is_empty(), "Invalid presentation timestamp returns no borrowed data")
		var pruned: Dictionary = runtime.prune(time)
		_expect(not pruned.ok and pruned.removed == 0 and _snapshot(runtime) == before, "Invalid cleanup is atomic")
	for time: float in [1.0e20, 1.0e100, 1.0e308]:
		_reject_application(runtime, runtime.apply("monster", 7, 0, time, Rules.PLAYER_POLICY), before, "Unrepresentable positive expiry is rejected")
	for policy: Variant in [null, true, 1, "player", [], {}, {"duration": 2.0},
		{"duration": 2.0, "hit_damage_taken_increased": 0.15},
		{"duration": 1.0, "hit_damage_taken_increased": 0.30},
		{"duration": 1.0, "hit_damage_taken_increased": 0.15, "unknown": 1.0}]:
		_reject_application(runtime, runtime.apply("monster", 7, 0, 10.0, policy), before, "Runtime requires a frozen complete policy")
	for field: String in Rules.POLICY_KEYS:
		for value: Variant in [true, false, 0, NAN, INF, -INF, "1", null]:
			var bad: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
			bad[field] = value
			_reject_application(runtime, runtime.apply("monster", 7, 0, 10.0, bad), before, "Runtime rejects invalid policy field: " + field)
	for provenance: Variant in [null, true, 1, "bolt", [], {"unknown": 1}, {"propagate": true},
		{"skill_id": []}, {"phase": {}}, {"cast_id": true}, {"projectile_id": -1},
		{"skill_id": "a".repeat(129)}, {"phase": "a".repeat(129)}]:
		_reject_application(runtime, runtime.apply("monster", 7, 0, 10.0, Rules.PLAYER_POLICY, provenance), before, "Malformed or oversized provenance")
	for key: Variant in [3, false, &"skill_id"]:
		var bad: Dictionary = {}
		bad[key] = "bolt"
		_reject_application(runtime, runtime.apply("monster", 7, 0, 10.0, Rules.PLAYER_POLICY, bad), before, "Provenance keys must be known exact Strings")
	for key: String in ["cast_id", "projectile_id"]:
		for value: Variant in [null, true, false, -1, 0.0, "0", &"0", [], {}, NAN, INF]:
			var bad: Dictionary = {}
			bad[key] = value
			_reject_application(runtime, runtime.apply("monster", 7, 0, 10.0, Rules.PLAYER_POLICY, bad), before, "Provenance IDs reject coercion: " + key)
	for key: String in ["skill_id", "phase"]:
		for value: Variant in [null, true, 0, &"bolt", [], {}]:
			var bad: Dictionary = {}
			bad[key] = value
			_reject_application(runtime, runtime.apply("monster", 7, 0, 10.0, Rules.PLAYER_POLICY, bad), before, "Provenance text rejects coercion: " + key)
	_reject_application(runtime, runtime.apply("monster", 7, true, 9.0, Rules.PLAYER_POLICY), before, "Older applications are fully validated before no-op handling")
	_expect(_snapshot(runtime) == before, "All invalid reads, removals, pruning, and applications preserve state")
	var valid: Dictionary = runtime.apply("monster", 7, 0, 10, Rules.PLAYER_POLICY,
		{"skill_id": "a".repeat(128), "phase": "", "cast_id": 0, "projectile_id": 0})
	_expect(valid.ok and valid.refreshed, "Boundary-length text, empty text, zero provenance IDs, and integer time remain valid")
	completed = true
