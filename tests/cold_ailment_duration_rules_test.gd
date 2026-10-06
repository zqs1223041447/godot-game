extends SceneTree
## Focused pure-policy proof; no scene, compiler, save, or AI scheduler loads.
const Cold = preload("res://scripts/combat/cold_ailment_duration_rules.gd")
const Frost = preload("res://scripts/combat/frost_lock_rules.gd")
const Runtime = preload("res://scripts/combat/freeze_runtime.gd")
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(820082)
	var random_before: Array = [randi(), randi(), randi()]
	seed(820082)
	_case(_snapshots_and_duration, "bounded snapshots, detached failures, and one duration multiplier")
	_case(_policies, "zero shape and exact derived policy")
	_case(_legacy_rejection_order, "legacy rejection order")
	_case(_rarity_boundaries, "four rarities and unchanged immunity")
	_case(_no_refresh_and_copies, "two groups cannot refresh, and snapshots are detached")
	_case(_partial_thaw_and_capacity, "partial thaw, atomic failures, and 100-state bound")
	_expect([randi(), randi(), randi()] == random_before, "Pure rules and runtime preserve global RNG")
	print("Cold ailment duration rules/runtime: %d checks, %d failures" % [checks, failures])
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


func _adjacent(value: float, direction: int) -> float:
	var bits := PackedByteArray()
	bits.resize(8)
	bits.encode_double(0, value)
	bits.encode_u64(0, bits.decode_u64(0) + direction)
	return bits.decode_double(0)


func _runtime_bytes(runtime: RefCounted) -> PackedByteArray:
	var entries: Array = []
	for id: int in range(1, 102):
		entries.append(runtime.state_for(id))
	return var_to_bytes([entries, runtime.active_count(), runtime.is_empty()])


func _snapshots_and_duration() -> void:
	_expect(Cold.STAT == "cold_ailment_duration_increased" and Cold.MAX_INCREASED == 0.20, "Only the current 20% cold duration budget is exposed")
	_expect(Cold.from_stats({}).is_empty() and Cold.snapshot_error({}).is_empty(), "Absent stat preserves the absent snapshot")
	for zero: Variant in [0, 0.0, -0.0]:
		_expect(Cold.from_stats({Cold.STAT: zero}).is_empty(), "Explicit zero does not add a snapshot key")
		var unchanged: Dictionary = Cold.duration(3.0, zero)
		_expect(unchanged.ok and var_to_bytes(unchanged.duration) == var_to_bytes(3.0), "Zero duration path preserves the base bits")
	var source: Dictionary = {Cold.STAT: 0.20, "unrelated": {"values": [7]}}
	var before: PackedByteArray = var_to_bytes(source)
	var snapshot: Dictionary = Cold.from_stats(source)
	_expect(snapshot == {Cold.STAT: 0.20} and typeof(snapshot[Cold.STAT]) == TYPE_FLOAT, "Only the normalized cold field enters the snapshot")
	snapshot[Cold.STAT] = 0.10
	_expect(var_to_bytes(source) == before, "Valid snapshot is detached from source")
	for increased: float in [0.10, _adjacent(0.20, -1), 0.20]:
		_expect(Cold.snapshot_error({Cold.STAT: increased}).is_empty(), "Finite nonnegative values fit the current budget")
		var scaled: Dictionary = Cold.duration(3.0, increased)
		_expect(scaled.ok and scaled.duration == 3.0 * (1.0 + increased), "Duration applies the increase exactly once")
	var lingering: Dictionary = Cold.duration(3.0 * 1.5, 0.20)
	_expect(lingering.ok, "Duration accepts the caller's already-formed support base")
	_near(lingering.duration, 5.4, "Cold duration follows existing lingering multiplier")
	_expect(Cold.duration(0.0, 0.20).duration == 0.0, "Zero base stays zero")
	for bad: Variant in [null, true, false, "0.2", &"0.2", [], {}, NAN, INF, -INF, -0.01, _adjacent(0.20, 1), 1]:
		_expect(not Cold.snapshot_error({Cold.STAT: bad}).is_empty(), "Malformed or over-budget increase is rejected")
		var preserved: Dictionary = Cold.from_stats({Cold.STAT: bad})
		_expect(preserved.has(Cold.STAT) and not Cold.snapshot_error(preserved).is_empty(), "Malformed source cannot silently become a zero snapshot")
		var result: Dictionary = Cold.duration(3.0, bad)
		_expect(not result.ok and not result.reason.is_empty() and not result.has("duration"), "Rejected increase exposes no partial duration")
		_expect(Frost.derived_policy(bad).is_empty(), "Malformed increase exposes no partial frost policy")
	var nested: Dictionary = {Cold.STAT: {"values": [0.20]}}
	var detached: Dictionary = Cold.from_stats(nested)
	detached[Cold.STAT].values.append(9)
	_expect(nested[Cold.STAT].values == [0.20], "Malformed nested source is deep-copied for compiler rejection")
	for bad_base: Variant in [null, true, "3", [], {}, NAN, INF, -INF, -1.0]:
		var result: Dictionary = Cold.duration(bad_base, 0.20)
		_expect(not result.ok and not result.has("duration"), "Invalid base has no partial result")
	var overflow: Dictionary = Cold.duration(1.7976931348623157e308, 0.20)
	_expect(not overflow.ok and not overflow.has("duration"), "Finite base overflow fails without clamping")
	completed = true


func _policies() -> void:
	var frozen_bytes: PackedByteArray = var_to_bytes(Frost.PLAYER_POLICY)
	var zero: Dictionary = Frost.derived_policy(0.0)
	_expect(var_to_bytes(zero) == frozen_bytes and not zero.has(Cold.STAT), "Zero policy retains the exact original key shape and values")
	_expect(Frost.policy_error(zero).is_empty(), "Legacy zero policy remains valid")
	zero.duration_by_rarity.normal = 99.0
	_expect(var_to_bytes(Frost.PLAYER_POLICY) == frozen_bytes, "Zero policy is a deep copy")
	var derived: Dictionary = Frost.derived_policy(0.20)
	_expect(derived.size() == 5 and derived[Cold.STAT] == 0.20 and Frost.policy_error(derived).is_empty(), "Derived policy records the validated increase")
	var expected: Dictionary = {"normal": 0.72, "magic": 0.72, "rare": 0.42, "boss": 0.24}
	for rarity: String in Frost.RARITY_KEYS:
		_near(derived.duration_by_rarity[rarity], expected[rarity], "Derived duration for " + rarity)
		var bad: Dictionary = derived.duplicate(true)
		bad.duration_by_rarity[rarity] = _adjacent(float(bad.duration_by_rarity[rarity]), 1)
		_expect(not Frost.policy_error(bad).is_empty(), "Even an adjacent duration cannot retune " + rarity)
		bad.duration_by_rarity[rarity] = float(derived.duration_by_rarity[rarity]) * 1.20
		_expect(not Frost.policy_error(bad).is_empty(), "Repeated duration multiplication is rejected for " + rarity)
	for field: String in ["immunity_seconds", "hit_multiplier", "mana_multiplier"]:
		_expect(derived[field] == Frost.PLAYER_POLICY[field], "Cold duration does not change " + field)
		var changed: Dictionary = derived.duplicate(true)
		changed[field] = float(changed[field]) * 1.20
		_expect(not Frost.policy_error(changed).is_empty(), "Derived policy cannot retune " + field)
	var missing: Dictionary = derived.duplicate(true)
	missing.erase(Cold.STAT)
	_expect(not Frost.policy_error(missing).is_empty(), "Longer durations cannot pose as legacy policy")
	var unchanged: Dictionary = Frost.PLAYER_POLICY.duplicate(true)
	unchanged[Cold.STAT] = 0.20
	_expect(not Frost.policy_error(unchanged).is_empty(), "Increase cannot accompany unchanged durations")
	for invalid_increase: Variant in [0, true, NAN, -0.1, _adjacent(0.20, 1)]:
		var bad: Dictionary = derived.duplicate(true)
		bad[Cold.STAT] = invalid_increase
		_expect(not Frost.policy_error(bad).is_empty(), "Derived marker must have a valid nonzero budget")
	var extra: Dictionary = derived.duplicate(true)
	extra.enabled = true
	_expect(not Frost.policy_error(extra).is_empty(), "Compiled enabled marker is still not a policy field")
	var copied: Dictionary = Frost.derived_policy(0.20)
	derived.duration_by_rarity.normal = 99.0
	_expect(var_to_bytes(Frost.PLAYER_POLICY) == frozen_bytes and copied.duration_by_rarity.normal == 0.72, "Derived policies share neither bases nor nested output dictionaries")
	completed = true


func _legacy_rejection_order() -> void:
	var bad: Dictionary = Frost.PLAYER_POLICY.duplicate(true)
	bad.enabled = true
	bad.duration_by_rarity.normal = -1.0
	_expect(Frost.policy_error(bad) == "Frost-lock policy must have the exact frozen player shape", "Legacy outer shape rejects before duration")
	bad.erase("enabled")
	bad.erase("mana_multiplier")
	bad.unknown = 1.0
	_expect(Frost.policy_error(bad) == "Unknown or non-String frost-lock policy field", "Legacy outer key rejects before duration")
	bad = Frost.PLAYER_POLICY.duplicate(true)
	bad.duration_by_rarity.erase("normal")
	bad.immunity_seconds = -1.0
	_expect(Frost.policy_error(bad) == "Frost-lock durations must have the exact frozen rarity shape", "Legacy rarity shape rejects before scalar")
	bad = Frost.PLAYER_POLICY.duplicate(true)
	bad.duration_by_rarity.normal = -1.0
	bad.immunity_seconds = -1.0
	_expect(Frost.policy_error(bad) == "Frost-lock durations must be finite positive numbers", "Legacy duration type and sign reject first")
	bad.duration_by_rarity.normal = 0.61
	_expect(Frost.policy_error(bad) == "Frost-lock durations must match the frozen player policy", "Legacy duration mismatch rejects before scalar")
	bad.duration_by_rarity.normal = 0.60
	bad.hit_multiplier = 2.0
	_expect(Frost.policy_error(bad) == "Frost-lock policy values must be finite positive numbers", "Legacy scalar validation order is preserved")
	bad.immunity_seconds = 2.0
	bad.hit_multiplier = -1.0
	_expect(Frost.policy_error(bad) == "Frost-lock policy must match the frozen player policy", "Legacy earlier scalar mismatch rejects before later invalid value")
	completed = true


func _rarity_boundaries() -> void:
	var policy: Dictionary = Frost.derived_policy(0.20)
	var packet: Dictionary = {"skill_id": "frost", "role": "projectile", "tags": ["spell", "projectile", "hit"]}
	_expect(Frost.eligible(packet, policy, 1.0, true), "Settled positive frost hit accepts derived policy")
	_expect(not Frost.eligible(packet, policy, 0.0, true) and not Frost.eligible(packet, policy, 1.0, false), "Zero loss and dead targets still cannot freeze")
	packet.skill_id = "nova"
	_expect(not Frost.eligible(packet, policy, 1.0, true), "Generic nova slow does not acquire frost-lock eligibility")
	for rarity: String in Frost.RARITY_KEYS:
		var runtime := Runtime.new()
		_expect(runtime.apply(1, rarity, 0.0, policy).applied, "Derived freeze applies for " + rarity)
		var state: Dictionary = runtime.state_for(1)
		_expect(state.frozen_until == policy.duration_by_rarity[rarity], "Runtime uses the derived rarity duration once")
		_near(float(state.immune_until) - float(state.frozen_until), 1.5, "Every rarity still has 1.50 seconds of immunity")
		_expect(runtime.is_frozen(1, _adjacent(state.frozen_until, -1)) and not runtime.is_frozen(1, state.frozen_until), "Exact thaw remains a half-open boundary")
		var at_thaw: Dictionary = runtime.apply(1, rarity, state.frozen_until, policy)
		_expect(at_thaw.ok and not at_thaw.applied and at_thaw.reason == "immune", "Thaw immediately starts original immunity")
		var last_immune: Dictionary = runtime.apply(1, rarity, _adjacent(state.immune_until, -1), policy)
		_expect(last_immune.ok and not last_immune.applied, "Final representable immune instant cannot freeze")
		_expect(runtime.apply(1, rarity, state.immune_until, policy).applied, "Exact immunity expiry permits new freeze")
	completed = true


func _no_refresh_and_copies() -> void:
	var runtime := Runtime.new()
	var policy: Dictionary = Frost.derived_policy(0.20)
	var provenance: Dictionary = {"skill_id": "frost", "cast_id": 1, "projectile_id": 7, "phase": "outbound"}
	_expect(runtime.apply(1, "boss", 0.0, policy, provenance).applied, "First group starts boss freeze")
	var before: PackedByteArray = _runtime_bytes(runtime)
	var state: Dictionary = runtime.state_for(1)
	for at: float in [0.0, 0.1, state.frozen_until, _adjacent(state.immune_until, -1)]:
		var second: Dictionary = runtime.apply(1, "normal", at, policy, {"cast_id": 2, "projectile_id": 8})
		_expect(second.ok and not second.applied and _runtime_bytes(runtime) == before, "Second group cannot refresh, lengthen, or rewrite original interval")
	policy.duration_by_rarity.boss = 99.0
	provenance.cast_id = 99
	state.provenance.cast_id = 100
	state.frozen_until = 100.0
	var prefix: Dictionary = runtime.frame_prefixes(0.0, 1.0)
	prefix.by_id[1] = 100.0
	_expect(_runtime_bytes(runtime) == before, "Policy, provenance, state, and prefix snapshots are detached")
	var invalid: Dictionary = runtime.apply(2, "boss", 10.0, policy)
	_expect(not invalid.ok and not invalid.applied and _runtime_bytes(runtime) == before, "Bad policy leaves no partial state")
	_expect(runtime.apply(2, "boss", 2.0, Frost.derived_policy(0.20)).applied, "Rejected future policy does not advance the settlement floor")
	completed = true


func _partial_thaw_and_capacity() -> void:
	var runtime := Runtime.new()
	var policy: Dictionary = Frost.derived_policy(0.20)
	runtime.apply(1, "normal", 0.0, policy)
	runtime.apply(2, "boss", 0.0, policy)
	var prefix: Dictionary = runtime.frame_prefixes(0.20, 0.10)
	_expect(prefix.ok, "Frame spanning boss thaw is accepted")
	_near(prefix.by_id[1], 0.10, "Normal target remains frozen for the whole partial frame")
	_near(prefix.by_id[2], 0.04, "Boss target freezes only the leading 0.04 seconds")
	_near(0.10 - float(prefix.by_id[2]), 0.06, "Only remaining 0.06 seconds advances enemy clocks")
	var large: Dictionary = runtime.frame_prefixes(0.20, 10.0)
	_near(10.0 - float(large.by_id[1]), 9.48, "Large delta retains extended normal frozen prefix")
	_expect(runtime.prune(0.72).removed == 0 and runtime.active_count() == 2, "Thaw keeps immunity states in storage")
	runtime.reset()
	for id: int in range(1, 101):
		_expect(runtime.apply(id, "normal", 0.0, policy).applied, "Each unique ID fits the unchanged 100-target limit")
	var before: PackedByteArray = _runtime_bytes(runtime)
	var overflow: Dictionary = runtime.apply(101, "normal", 10.0, policy)
	_expect(not overflow.ok and not overflow.applied and _runtime_bytes(runtime) == before, "The 101st ID fails atomically even after unpruned expiry")
	_expect(runtime.active_count() == 100 and runtime.frame_prefixes(0.0, 1.0).by_id.size() == 100, "Extended duration adds no per-group state or extra target slot")
	var repeat: Dictionary = runtime.apply(100, "boss", 0.0, policy, {"cast_id": 2})
	_expect(repeat.ok and not repeat.applied and _runtime_bytes(runtime) == before, "Repeat group stays harmless at capacity and failed future apply leaves clock intact")
	_expect(runtime.prune(2.22).removed == 100 and runtime.is_empty(), "Original immunity after extended freeze releases all states")
	completed = true
