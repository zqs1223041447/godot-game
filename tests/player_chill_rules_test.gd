extends SceneTree
## Pure player chill admission and one-state movement accounting. Main owns
## frost-guard hit provenance, target liveness, and settlement ordering.
const Rules = preload("res://scripts/combat/chill_rules.gd")
const Runtime = preload("res://scripts/combat/player_chill_runtime.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(850085)
	var expected_random: Array = [randi(), randi(), randi()]
	seed(850085)
	_case(_test_policy, "exact two-field enemy budget")
	_case(_test_receipts, "authoritative cold share and real pool loss")
	_case(_test_bad_receipts, "malformed receipts fail closed without mutation")
	_case(_test_lifecycle, "single-state boundaries and cleanup")
	_case(_test_refresh, "refresh from latest hit without stacking")
	_case(_test_movement, "partial-tick expiry and no historical replay")
	_case(_test_atomic_errors, "read-only preflight and atomic errors")
	_case(_test_detached_values, "isolated metadata and no mutable borrowing")
	_expect([randi(), randi(), randi()] == expected_random, "Rules and runtime preserve the global RNG stream")
	print("Player chill rules/runtime: %d checks, %d failures" % [checks, failures])
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
	_expect(absf(value - expected) <= maxf(1.0e-12, absf(expected) * 1.0e-12), label)


func _receipt() -> Dictionary:
	return {"ok": true, "components": {"cold": 60.0, "physical": 40.0},
		"damage_total": 100.0, "shield_spent": 20.0, "health_lost": 30.0}


func _snapshot(runtime: RefCounted, at: float = 1.0) -> PackedByteArray:
	return var_to_bytes([runtime.is_empty(), runtime.status(at),
		runtime.application_error(1, 0.5, Rules.ENEMY_POLICY),
		runtime.application_error(1, 1.5, Rules.ENEMY_POLICY)])


func _test_policy() -> void:
	_expect(Rules.ENEMY_POLICY == {"duration": 1.2, "movement_speed_reduced": 0.25}, "Frozen budget is 25 percent for 1.2 seconds")
	var policy: Dictionary = Rules.ENEMY_POLICY.duplicate(true)
	var before: PackedByteArray = var_to_bytes(policy)
	_expect(Rules.policy_error(policy).is_empty(), "Exact frozen policy passes")
	_expect(var_to_bytes(policy) == before, "Policy validation never changes its input")
	for bad: Variant in [null, true, [], {}, {"duration": 1.2}]:
		_expect(not Rules.policy_error(bad).is_empty(), "Malformed or missing policy fields fail closed")
	for field: String in ["duration", "movement_speed_reduced"]:
		for invalid: Variant in [true, "0.25", NAN, INF, -1.0, 0.0]:
			var bad: Dictionary = policy.duplicate(true)
			bad[field] = invalid
			_expect(not Rules.policy_error(bad).is_empty(), "Policy values are strict finite frozen numbers: " + field)
	_expect(not Rules.policy_error({"duration": 1.0, "movement_speed_reduced": 0.20}).is_empty(), "Superseded 20 percent for one second is rejected")
	_expect(not Rules.policy_error({&"duration": 1.2, "movement_speed_reduced": 0.25}).is_empty(), "StringName policy keys are rejected")
	policy["metadata"] = {"duration": 1.2}
	_expect(not Rules.policy_error(policy).is_empty(), "Extra metadata cannot enter exact policy")
	completed = true


func _test_receipts() -> void:
	var mixed: Dictionary = _receipt()
	var before: PackedByteArray = var_to_bytes(mixed)
	_expect(Rules.actual_cold_loss(mixed) == {"ok": true, "reason": "", "actual_cold": 30.0}, "Mixed hit attributes only the cold share of spent pools")
	_expect(var_to_bytes(mixed) == before, "Cold admission leaves damage totals and receipt untouched")
	var shield: Dictionary = Defense.incoming_source_hit({"cold": 100.0}, {}, 200.0, 100.0)
	_expect(Rules.actual_cold_loss(shield).actual_cold == 100.0 and shield.health_lost == 0.0, "Shield-only cold damage qualifies")
	var life: Dictionary = Defense.incoming_source_hit({"cold": 100.0}, {}, 0.0, 200.0)
	_expect(Rules.actual_cold_loss(life).actual_cold == 100.0, "Life-only cold damage qualifies")
	var mana: Dictionary = Defense.incoming_source_hit({"cold": 100.0}, {}, 0.0, 200.0, "player", 0.0, 200.0, 1.0)
	_expect(Rules.actual_cold_loss(mana).actual_cold == 100.0 and mana.health_lost == 0.0 and mana.mana_spent == 100.0, "Mana absorbs all cold damage and still qualifies")
	var split: Dictionary = Defense.incoming_source_hit({"cold": 60.0, "physical": 40.0}, {}, 10.0, 5.0, "player", 0.0, 10.0, 0.5)
	_expect(Rules.actual_cold_loss(split).actual_cold == 15.0 and split.overkill == 75.0, "Shield plus mana plus life excludes overkill before attribution")
	var resisted: Dictionary = Defense.incoming_source_hit({"cold": 100.0, "physical": 50.0}, {"cold_resistance": 0.5}, 0.0, 20.0)
	_expect(Rules.actual_cold_loss(resisted).actual_cold == 10.0, "Cold share uses post-defense components rather than raw tooltip damage")
	var no_cold: Dictionary = Defense.incoming_source_hit({"physical": 100.0}, {}, 0.0, 200.0)
	_expect(Rules.actual_cold_loss(no_cold) == {"ok": true, "reason": "", "actual_cold": 0.0}, "Valid non-cold damage yields zero")
	var no_loss: Dictionary = Defense.incoming_source_hit({"cold": 100.0}, {}, 0.0, 0.0)
	_expect(Rules.actual_cold_loss(no_loss).actual_cold == 0.0, "All overkill with no spent resources yields zero")
	_expect(Rules.actual_cold_loss(Defense.incoming_source_hit({}, {}, 5.0, 5.0)).actual_cold == 0.0, "Legal zero-damage receipt yields zero")
	var large: Dictionary = {"ok": true, "components": {"cold": 1.0e308}, "damage_total": 1.0e308, "shield_spent": 0.0, "health_lost": 1.0e308}
	_expect(Rules.actual_cold_loss(large).actual_cold == 1.0e308, "Valid large cold loss does not overflow during proportional attribution")
	var tiny: Dictionary = {"ok": true, "components": {"cold": 1.0e-300}, "damage_total": 1.0e-300, "shield_spent": 0.0, "health_lost": 1.0e-300}
	_expect(Rules.actual_cold_loss(tiny).actual_cold > 0.0, "Representable tiny positive cold loss remains positive")
	var rounded: Dictionary = {"ok": true, "components": {"cold": 0.3}, "damage_total": 0.3, "shield_spent": 0.1, "health_lost": 0.2}
	_expect(Rules.actual_cold_loss(rounded).actual_cold == 0.3, "Last-bit pool sum above total is safely clamped for attribution")
	completed = true


func _test_bad_receipts() -> void:
	for malformed: Variant in [null, true, [], {}, {"ok": false}, {"ok": 1}]:
		var result: Dictionary = Rules.actual_cold_loss(malformed)
		_expect(not result.ok and result.actual_cold == 0.0 and not result.reason.is_empty(), "Only strict successful Defense receipts are admitted")
	for patch: Dictionary in [{"components": []}, {"components": {"cold": -1.0}},
		{"components": {"frost": 100.0}}, {"components": {"cold": INF}},
		{"damage_total": 90.0}, {"damage_total": true}, {"shield_spent": null},
		{"health_lost": -1.0}, {"mana_spent": NAN}, {"mana_spent": "5"},
		{"mana_spent": 100.0}, {"components": {"cold": 1.0e308, "fire": 1.0e308}},
		{"shield_spent": 1.0e308, "health_lost": 1.0e308}]:
		var bad: Dictionary = _receipt()
		bad.merge(patch, true)
		var before: PackedByteArray = var_to_bytes(bad)
		var result: Dictionary = Rules.actual_cold_loss(bad)
		_expect(not result.ok and result.actual_cold == 0.0 and var_to_bytes(bad) == before, "Malformed numeric or component receipt fails atomically")
	for field: String in ["components", "damage_total", "shield_spent", "health_lost"]:
		var missing: Dictionary = _receipt()
		missing.erase(field)
		_expect(not Rules.actual_cold_loss(missing).ok, "Mandatory receipt field cannot default to zero: " + field)
	var zero: Dictionary = {"ok": true, "components": {"cold": 1.0e-10}, "damage_total": 0.0, "shield_spent": 0.0, "health_lost": 0.0}
	_expect(not Rules.actual_cold_loss(zero).ok, "Tolerance cannot disguise nonzero damage as a zero total")
	completed = true


func _test_lifecycle() -> void:
	var runtime := Runtime.new()
	_expect(runtime.is_empty() and runtime.status(0.0).is_empty(), "New runtime has no player status")
	_expect(runtime.apply(7, 1.0, Rules.ENEMY_POLICY) == {"ok": true, "reason": "new", "applied": true}, "First valid hit applies one state")
	var state: Dictionary = runtime.status(1.0)
	_expect(state.size() == 6 and state.source_id == 7 and state.applied_at == 1.0, "Status has only the six documented scalar fields")
	_near(state.expires_at, 2.2, "First expiry equals hit time plus 1.2 seconds")
	_near(state.remaining_seconds, 1.2, "Status is active at its start")
	_expect(state.movement_speed_reduced == 0.25 and state.movement_multiplier == 0.75, "One active status supplies the frozen movement reduction")
	_expect(runtime.status(0.9).is_empty() and runtime.status(state.expires_at).is_empty(), "Before start and at exact expiry are inactive")
	_expect(not runtime.is_empty(), "Read-only expiry query does not erase retained state")
	_expect(not runtime.prune(2.0).removed and not runtime.is_empty(), "Prune before expiry retains the state")
	_expect(runtime.prune(2.2).removed and runtime.is_empty(), "Prune removes the one state at exact expiry")
	_expect(not runtime.apply(8, 1.5, Rules.ENEMY_POLICY).ok, "Expired pruned state cannot be resurrected by an older event")
	runtime.reset()
	_expect(runtime.is_empty() and runtime.apply(8, 0.0, Rules.ENEMY_POLICY).applied, "Scene/death reset clears both state and old scene's time floor")
	completed = true


func _test_refresh() -> void:
	var runtime := Runtime.new()
	runtime.apply(1, 0.0, Rules.ENEMY_POLICY)
	_expect(runtime.apply(2, 0.0, Rules.ENEMY_POLICY).reason == "refreshed", "Same-time second source refreshes the single state")
	_near(runtime.status(0.0).expires_at, 1.2, "Same-time repeat cannot extend expiry")
	_expect(runtime.status(0.0).movement_multiplier == 0.75, "Same-time repeat cannot stack reduction")
	_expect(runtime.apply(3, 0.5, Rules.ENEMY_POLICY).applied, "Later active hit refreshes")
	var state: Dictionary = runtime.status(0.5)
	_near(state.expires_at, 1.7, "Refresh uses hit time plus duration, never old expiry plus duration")
	_expect(state.source_id == 3 and state.applied_at == 0.5, "Most recent legal hit owns scalar source metadata")
	_expect(state.movement_multiplier == 0.75 and state.size() == 6, "Repeated source hits still expose exactly one unstacked state")
	var before: PackedByteArray = _snapshot(runtime, 0.5)
	_expect(not runtime.apply(9, 0.4, Rules.ENEMY_POLICY).ok and _snapshot(runtime, 0.5) == before, "Old event cannot replace refreshed metadata or deadline")
	_expect(runtime.apply(4, 1.7, Rules.ENEMY_POLICY).reason == "new", "Exact expiry hit starts a new state")
	_near(runtime.status(1.7).expires_at, 2.9, "Reapplication starts its own duration")
	completed = true


func _test_movement() -> void:
	var runtime := Runtime.new()
	_expect(runtime.movement_factor(0.0, 1.0) == {"ok": true, "reason": "", "factor": 1.0}, "Absent chill preserves movement")
	runtime.apply(1, 1.0, Rules.ENEMY_POLICY)
	var before: PackedByteArray = _snapshot(runtime)
	_near(runtime.movement_factor(1.0, 1.1).factor, 0.75, "Fully chilled tick moves at 75 percent")
	_near(runtime.movement_factor(1.0, 2.2).factor, 0.75, "Tick ending at exact expiry is fully chilled")
	_near(runtime.movement_factor(2.0, 2.4).factor, 0.875, "Tick crossing expiry retains its full-speed suffix")
	_near(runtime.movement_factor(1.0, 3.0).factor, 0.85, "Large delta averages only 1.2 slowed seconds")
	_near(runtime.movement_factor(2.2, 3.0).factor, 1.0, "Tick beginning at exact expiry is full speed")
	_near(runtime.movement_factor(1.0, 1.0).factor, 1.0, "Zero-width active interval has neutral factor")
	_expect(not runtime.movement_factor(0.5, 1.5).ok, "Movement already performed before the hit is never retrospectively slowed")
	_expect(_snapshot(runtime) == before, "Successful and rejected movement queries do not change state or clocks")
	runtime.apply(2, 1.5, Rules.ENEMY_POLICY)
	_expect(not runtime.movement_factor(1.0, 2.0).ok, "Refreshing does not promise unsupported historical interval replay")
	_near(runtime.movement_factor(1.5, 1.6).factor, 0.75, "Current interval after refresh remains fully supported")
	completed = true


func _test_atomic_errors() -> void:
	var runtime := Runtime.new()
	runtime.apply(1, 1.0, Rules.ENEMY_POLICY)
	var before: PackedByteArray = _snapshot(runtime)
	for source: Variant in [null, true, 0, -1, 1.0, "1", [], INF]:
		var reason: String = runtime.application_error(source, 2.0, Rules.ENEMY_POLICY)
		var result: Dictionary = runtime.apply(source, 2.0, Rules.ENEMY_POLICY)
		_expect(not reason.is_empty() and result.reason == reason and not result.applied and not result.ok and _snapshot(runtime) == before, "Bad source is rejected identically by preflight and apply")
	for at: Variant in [null, true, "1", [], NAN, INF, -INF, -1.0]:
		var application: Dictionary = runtime.apply(2, at, Rules.ENEMY_POLICY)
		var prune_result: Dictionary = runtime.prune(at)
		var movement: Dictionary = runtime.movement_factor(at, 2.0)
		var ending: Dictionary = runtime.movement_factor(1.0, at)
		_expect(not application.ok and not prune_result.ok and not movement.ok and not ending.ok and runtime.status(at).is_empty() and _snapshot(runtime) == before, "All operations reject malformed time atomically")
	_expect(not runtime.apply(2, 1.0e308, Rules.ENEMY_POLICY).ok and _snapshot(runtime) == before, "Unrepresentable expiry fails without advancing the clock")
	_expect(not runtime.apply(2, 2.0, {"duration": 1.0, "movement_speed_reduced": 0.25}).ok and _snapshot(runtime) == before, "Changed policy fails without replacing prior state")
	_expect(not runtime.prune(0.5).ok and _snapshot(runtime) == before, "Backward prune is atomic")
	_expect(not runtime.movement_factor(2.0, 1.0).ok and _snapshot(runtime) == before, "Reversed movement interval is atomic")
	_expect(runtime.application_error(2, 100.0, Rules.ENEMY_POLICY).is_empty() and _snapshot(runtime) == before, "Successful future preflight is read-only")
	_expect(runtime.apply(2, 1.5, Rules.ENEMY_POLICY).applied, "Rejected writes and future read-only preflight do not advance write floor")
	completed = true


func _test_detached_values() -> void:
	var runtime := Runtime.new()
	var policy: Dictionary = Rules.ENEMY_POLICY.duplicate(true)
	var applied: Dictionary = runtime.apply(1, 1.0, policy)
	var before: PackedByteArray = _snapshot(runtime)
	policy.duration = 100.0
	policy.movement_speed_reduced = 0.99
	applied.applied = false
	var state: Dictionary = runtime.status(1.0)
	state.source_id = 99
	state.expires_at = 100.0
	state["metadata"] = {"nested": [{"changed": true}]}
	_expect(_snapshot(runtime) == before, "Input policy and returned status/result cannot mutate retained state")
	var factor: Dictionary = runtime.movement_factor(1.0, 1.1)
	factor.factor = 0.0
	_expect(runtime.movement_factor(1.0, 1.1).factor == 0.75, "Movement result is detached")
	var receipt: Dictionary = _receipt()
	receipt["metadata"] = {"nested": [{"source_id": 2}]}
	var receipt_before: PackedByteArray = var_to_bytes(receipt)
	var loss: Dictionary = Rules.actual_cold_loss(receipt)
	loss.actual_cold = 999.0
	loss["metadata"] = {"nested": []}
	_expect(var_to_bytes(receipt) == receipt_before, "Cold result never borrows nested receipt metadata")
	_expect(Rules.actual_cold_loss(receipt).actual_cold == 30.0, "Mutating returned cold metadata does not poison subsequent admission")
	var absent: Dictionary = runtime.status(100.0)
	absent["source_id"] = 5
	_expect(runtime.status(100.0).is_empty(), "Inactive status also returns a fresh dictionary")
	runtime.reset()
	_expect(runtime.is_empty() and runtime.status(1.0).is_empty(), "Reset leaves no borrowed state alive")
	completed = true
