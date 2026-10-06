extends SceneTree
## Pure frost-lock policy, storage, and enemy-clock prefix contract. Integration
## owns damage attribution, actor liveness, and advancing the actual AI clocks.
const Rules = preload("res://scripts/combat/frost_lock_rules.gd")
const Runtime = preload("res://scripts/combat/freeze_runtime.gd")
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(730073)
	var expected_random: Array = [randi(), randi(), randi()]
	seed(730073)
	_case(_test_policy_and_eligibility, "exact policy and settled cold hit eligibility")
	_case(_test_boundaries, "rarity duration, exact thaw and immunity boundaries")
	_case(_test_no_refresh, "same-time and repeated hits cannot refresh or change provenance")
	_case(_test_prefixes, "positive frame prefixes and atomic unsupported interior starts")
	_case(_test_enemy_clock, "large-delta thaw preserves only the unfrozen enemy clock")
	_case(_test_copies_and_cleanup, "detached values, remove, prune, and immediate reset")
	_case(_test_capacity, "100-state capacity and explicit release")
	_case(_test_invalid_inputs, "invalid inputs and time reversal are atomic")
	_expect([randi(), randi(), randi()] == expected_random, "Rules and every runtime operation preserve global RNG")
	print("Frost-lock rules/runtime: %d checks, %d failures" % [checks, failures])
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


func _packet() -> Dictionary:
	return {"skill_id": "frost", "role": "projectile", "tags": ["spell", "projectile", "hit"]}


func _snapshot(runtime: RefCounted) -> PackedByteArray:
	var entries: Array = []
	for id: int in range(1, 103): entries.append(runtime.state_for(id))
	return var_to_bytes([entries, runtime.active_count(), runtime.is_empty()])


func _reject(runtime: RefCounted, result: Dictionary, before: PackedByteArray, label: String) -> void:
	_expect(not result.ok and not result.applied and not result.reason.is_empty(), label)
	_expect(_snapshot(runtime) == before, "Rejected application is atomic: " + label)


func _test_policy_and_eligibility() -> void:
	_expect(Rules.PLAYER_POLICY == {"duration_by_rarity": {"normal": 0.60, "magic": 0.60, "rare": 0.35, "boss": 0.20},
		"immunity_seconds": 1.50, "hit_multiplier": 0.75, "mana_multiplier": 1.20}, "Exact frozen prototype budget")
	var policy: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
	var packet: Dictionary = _packet()
	var before: PackedByteArray = var_to_bytes([policy, packet])
	for amount: Variant in [1, 0.5, 1.0e-300, 1.0e308]:
		_expect(Rules.eligible(packet, policy, amount, true), "Any finite positive actual cold loss qualifies")
	_expect(var_to_bytes([policy, packet]) == before, "Eligibility never mutates caller-owned inputs")
	for invalid: Variant in [null, true, false, "1", &"1", [], {}, NAN, INF, -INF, -1, 0, -0.0]:
		_expect(not Rules.eligible(packet, policy, invalid, true), "Zero, malformed, negative, and nonfinite actual cold loss do not freeze")
	for invalid: Variant in [null, 0, 1, "true", [], {}, false]:
		_expect(not Rules.eligible(packet, policy, 1.0, invalid), "Liveness must be strict true")
	for patch: Dictionary in [{"skill_id": "bolt"}, {"skill_id": &"frost"}, {"role": "secondary"},
		{"role": "child"}, {"role": &"projectile"}, {"tags": ["hit", "dot"]}, {"tags": ["projectile"]},
		{"tags": ["hit", 1]}, {"tags": [ &"hit" ]}, {"tags": "hit"}]:
		var ineligible: Dictionary = packet.duplicate(true)
		ineligible.merge(patch, true)
		_expect(not Rules.eligible(ineligible, policy, 1, true), "Only the frost projectile hit packet qualifies")
	for invalid: Variant in [null, true, [], "frost", {}]:
		_expect(not Rules.eligible(invalid, policy, 1, true), "Malformed packet cannot freeze")
	for invalid: Variant in [null, true, 1, "frost", [], {}, {"duration_by_rarity": {}}]:
		_expect(not Rules.policy_error(invalid).is_empty(), "Incomplete or wrongly typed policy fails closed")
	var enabled: Dictionary = policy.duplicate(true)
	enabled.enabled = true
	_expect(not Rules.policy_error(enabled).is_empty(), "Compiled enabled marker is forbidden in exact snapshot policy")
	for field: String in ["immunity_seconds", "hit_multiplier", "mana_multiplier"]:
		for invalid: Variant in [null, true, "1", [], {}, NAN, INF, -INF, -1, 0, 2.0]:
			var bad: Dictionary = policy.duplicate(true)
			bad[field] = invalid
			_expect(not Rules.policy_error(bad).is_empty(), "Scalar policy rejects invalid or changed value: " + field)
	for rarity: String in Rules.RARITY_KEYS:
		for invalid: Variant in [null, true, "0.6", [], {}, NAN, INF, -INF, -1, 0, 0.61]:
			var bad: Dictionary = policy.duplicate(true)
			bad.duration_by_rarity[rarity] = invalid
			_expect(not Rules.policy_error(bad).is_empty(), "Rarity duration rejects invalid or changed value: " + rarity)
	var missing: Dictionary = policy.duplicate(true)
	missing.duration_by_rarity.erase("normal")
	_expect(not Rules.policy_error(missing).is_empty(), "Missing rarity rejected")
	var extra: Dictionary = policy.duplicate(true)
	extra.duration_by_rarity.unique = 0.6
	_expect(not Rules.policy_error(extra).is_empty(), "Unknown rarity rejected")
	for key: Variant in [1, &"normal"]:
		var bad: Dictionary = policy.duplicate(true)
		bad.duration_by_rarity.erase("normal")
		bad.duration_by_rarity[key] = 0.6
		_expect(not Rules.policy_error(bad).is_empty(), "Non-String nested policy key rejected")
	for key: Variant in [1, &"hit_multiplier"]:
		var bad: Dictionary = policy.duplicate(true)
		bad.erase("hit_multiplier")
		bad[key] = 0.75
		_expect(not Rules.policy_error(bad).is_empty(), "Non-String outer policy key rejected")
	completed = true


func _test_boundaries() -> void:
	for rarity: String in Rules.RARITY_KEYS:
		var runtime := Runtime.new()
		var result: Dictionary = runtime.apply(1, rarity, 10.0, Rules.PLAYER_POLICY)
		_expect(result.ok and result.applied and result.reason == "new", "First application succeeds for " + rarity)
		var state: Dictionary = runtime.state_for(1)
		_near(float(state.frozen_until) - 10.0, Rules.PLAYER_POLICY.duration_by_rarity[rarity], "Correct duration for " + rarity)
		_near(float(state.immune_until) - float(state.frozen_until), 1.5, "Immunity starts at thaw for " + rarity)
		_expect(not runtime.is_frozen(1, _adjacent_float(10.0, -1)) and runtime.is_frozen(1, 10.0), "Freeze includes its start only")
		_expect(runtime.is_frozen(1, _adjacent_float(state.frozen_until, -1)), "Last representable instant before thaw is frozen")
		_expect(not runtime.is_frozen(1, state.frozen_until) and runtime.remaining_seconds(1, state.frozen_until) == 0.0, "Exact thaw has no freeze remaining")
		var thaw_hit: Dictionary = runtime.apply(1, rarity, state.frozen_until, Rules.PLAYER_POLICY)
		_expect(thaw_hit.ok and not thaw_hit.applied and thaw_hit.reason == "immune", "Exact thaw begins immunity")
		var immune_hit: Dictionary = runtime.apply(1, rarity, _adjacent_float(state.immune_until, -1), Rules.PLAYER_POLICY)
		_expect(immune_hit.ok and not immune_hit.applied and immune_hit.reason == "immune", "Last instant before immunity expiry rejects freeze")
		var next: Dictionary = runtime.apply(1, rarity, state.immune_until, Rules.PLAYER_POLICY)
		_expect(next.ok and next.applied and runtime.state_for(1).frozen_from == state.immune_until, "Exact immunity expiry permits new freeze")
	completed = true


func _test_no_refresh() -> void:
	var runtime := Runtime.new()
	runtime.apply(1, "boss", 0.0, Rules.PLAYER_POLICY, {"skill_id": "frost", "cast_id": 3, "projectile_id": 4, "phase": "outbound"})
	var before: PackedByteArray = _snapshot(runtime)
	for at: float in [0.0, 0.1, _adjacent_float(0.2, -1), 0.2, 1.0, _adjacent_float(1.7, -1)]:
		var result: Dictionary = runtime.apply(1, "normal", at, Rules.PLAYER_POLICY, {"cast_id": 99})
		_expect(result.ok and not result.applied, "Hits while frozen or immune do not apply")
		_expect(_snapshot(runtime) == before, "Hits cannot extend the boss duration or rewrite provenance")
	_expect(runtime.active_count() == 1, "Repeated hits retain only one state per target")
	_expect(runtime.apply(1, "normal", 1.7, Rules.PLAYER_POLICY, {"cast_id": 99}).applied, "Post-immunity hit can replace state once")
	_expect(runtime.state_for(1).provenance.cast_id == 99 and runtime.active_count() == 1, "New interval owns new provenance without stacking")
	completed = true


func _test_prefixes() -> void:
	var runtime := Runtime.new()
	_expect(runtime.frame_prefixes(0, 0) == {"ok": true, "reason": "", "by_id": {}}, "Zero-width absent path produces no status")
	_expect(runtime.frame_prefixes(0, 1).by_id.is_empty() and runtime.is_empty(), "Absent path remains empty")
	runtime.apply(1, "normal", 0.0, Rules.PLAYER_POLICY)
	runtime.apply(2, "boss", 0.0, Rules.PLAYER_POLICY)
	var before: PackedByteArray = _snapshot(runtime)
	_expect(runtime.frame_prefixes(0.0, 0.1).by_id == {1: 0.1, 2: 0.1}, "Short frame is fully frozen")
	_expect(runtime.frame_prefixes(0.0, 1.0).by_id == {1: 0.6, 2: 0.2}, "Cross-thaw frame returns separate rarity prefixes")
	var partial: Dictionary = runtime.frame_prefixes(0.15, 0.1)
	_near(partial.by_id[1], 0.1, "Normal enemy stays frozen through partial frame")
	_near(partial.by_id[2], 0.05, "Boss thaws halfway through frame")
	_expect(runtime.frame_prefixes(0.6, 0.1).by_id.is_empty(), "Exact thaw emits no zero entries")
	_expect(_snapshot(runtime) == before, "Frame-prefix queries never mutate retained state")
	runtime.apply(3, "rare", 5.0, Rules.PLAYER_POLICY)
	_expect(not runtime.frame_prefixes(0.0, 6.0).ok and runtime.frame_prefixes(0.0, 6.0).by_id.is_empty(), "Interior start rejects whole result despite earlier valid prefixes")
	_expect(runtime.frame_prefixes(0.0, 5.0).by_id == {1: 0.6, 2: 0.2}, "Freeze beginning exactly at frame end contributes zero")
	_expect(runtime.frame_prefixes(1.0, 1.0).by_id.is_empty(), "Freeze wholly in future contributes zero")
	_expect(runtime.frame_prefixes(5.0, 0.0).by_id.is_empty(), "Zero-width frame emits no zero entries even at freeze start")
	_expect(runtime.frame_prefixes(5.0, 0.1).by_id == {3: 0.1}, "Freeze beginning exactly at frame start is supported")
	completed = true


func _test_enemy_clock() -> void:
	var runtime := Runtime.new()
	runtime.apply(1, "normal", 0.0, Rules.PLAYER_POLICY)
	var clocks: Dictionary = {"motion": 0.0, "cooldown": 0.0, "windup": 0.0}
	var frozen: Dictionary = runtime.frame_prefixes(0.0, 0.3)
	var enemy_delta: float = 0.3 - float(frozen.by_id.get(1, 0.0))
	for key: String in clocks: clocks[key] += enemy_delta
	_expect(clocks == {"motion": 0.0, "cooldown": 0.0, "windup": 0.0}, "Frozen prefix pauses every caller-owned enemy clock")
	var large: Dictionary = runtime.frame_prefixes(0.3, 10.0)
	enemy_delta = 10.0 - float(large.by_id.get(1, 0.0))
	for key: String in clocks: clocks[key] += enemy_delta
	for key: String in clocks: _near(clocks[key], 9.7, "Large-delta enemy clock advances only after thaw: " + key)
	_expect(runtime.active_count() == 1 and not runtime.is_frozen(1, 10.3), "Querying after expiry does not erase historical prefix")
	var cleaned: Dictionary = runtime.prune(10.3)
	_expect(cleaned.ok and cleaned.removed == 1 and runtime.is_empty(), "Prune after enemy phase removes completed immunity")
	_expect(runtime.frame_prefixes(10.3, 1.0).by_id.is_empty(), "Next frame has the full unfrozen enemy delta")
	completed = true


func _test_copies_and_cleanup() -> void:
	var runtime := Runtime.new()
	var policy: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
	var provenance: Dictionary = {"skill_id": "frost", "cast_id": 7, "projectile_id": 8, "phase": "return"}
	runtime.apply(1, "rare", 0.0, policy, provenance)
	var before: PackedByteArray = _snapshot(runtime)
	policy.duration_by_rarity.rare = 100.0
	provenance.phase = "changed"
	var view: Dictionary = runtime.state_for(1)
	view.provenance.cast_id = 100
	view.frozen_until = 100.0
	var prefixes: Dictionary = runtime.frame_prefixes(0.0, 1.0)
	prefixes.by_id[1] = 100.0
	_expect(_snapshot(runtime) == before, "Policies, provenance, state getters, and prefix maps are detached")
	_expect(runtime.prune(0.35).removed == 0 and runtime.active_count() == 1, "Prune cannot discard an immune target at thaw")
	var immunity_end: float = runtime.state_for(1).immune_until
	_expect(runtime.prune(_adjacent_float(immunity_end, -1)).removed == 0, "Prune keeps final immune instant")
	_expect(runtime.prune(immunity_end).removed == 1 and runtime.is_empty(), "Prune releases capacity at exact immunity expiry")
	_expect(runtime.remove(1) == {"ok": true, "reason": "", "removed": false}, "Removing absent target is valid")
	runtime.apply(1, "normal", 2.0, Rules.PLAYER_POLICY)
	_expect(runtime.remove(1).removed and runtime.is_empty(), "Death removal immediately removes freeze and immunity")
	runtime.apply(1, "normal", 2.0, Rules.PLAYER_POLICY)
	runtime.reset()
	_expect(runtime.is_empty() and runtime.active_count() == 0 and runtime.state_for(1).is_empty(), "Scene reset immediately clears all states")
	_expect(runtime.apply(1, "normal", 0.0, Rules.PLAYER_POLICY).applied, "Reset also clears the previous scene's time floor")
	completed = true


func _test_capacity() -> void:
	var runtime := Runtime.new()
	for id: int in range(1, 101):
		_expect(runtime.apply(id, "normal", 0.0, Rules.PLAYER_POLICY).applied, "Distinct positive ID fits the 100-target cap")
	_expect(runtime.active_count() == 100 and runtime.frame_prefixes(0.0, 0.1).by_id.size() == 100, "Storage and one-pass frame query remain bounded by 100")
	var before: PackedByteArray = _snapshot(runtime)
	_reject(runtime, runtime.apply(101, "normal", 10.0, Rules.PLAYER_POLICY), before, "Expired unpruned states still count toward capacity")
	_expect(runtime.remove(1).removed and runtime.apply(101, "normal", 0.0, Rules.PLAYER_POLICY).applied, "Explicit removal releases one slot and failed cap check never advances time")
	_expect(runtime.active_count() == 100 and not runtime.apply(2, "normal", 0.0, Rules.PLAYER_POLICY).applied, "Existing frozen target remains harmless at capacity")
	_expect(runtime.apply(2, "normal", 2.1, Rules.PLAYER_POLICY).applied and runtime.active_count() == 100, "Exact expired immunity may replace one state without a new slot")
	_expect(runtime.prune(2.1).removed == 99 and runtime.active_count() == 1, "Prune frees only intervals whose immunity finished")
	_expect(runtime.apply(102, "boss", 2.1, Rules.PLAYER_POLICY).applied, "Pruned capacity is reusable")
	completed = true


func _test_invalid_inputs() -> void:
	var runtime := Runtime.new()
	runtime.apply(1, "normal", 1.0, Rules.PLAYER_POLICY)
	var before: PackedByteArray = _snapshot(runtime)
	for invalid: Variant in [null, true, false, 0, -1, 1.0, "1", [], {}, NAN, INF]:
		_reject(runtime, runtime.apply(invalid, "normal", 10.0, Rules.PLAYER_POLICY), before, "Invalid target ID")
		_expect(not runtime.is_frozen(invalid, 1.0) and runtime.remaining_seconds(invalid, 1.0) == 0.0 and runtime.state_for(invalid).is_empty(), "Invalid ID is a harmless empty query")
		_expect(not runtime.remove(invalid).ok and _snapshot(runtime) == before, "Invalid remove is atomic")
	for invalid: Variant in [null, true, "0", [], {}, NAN, INF, -INF, -1]:
		_reject(runtime, runtime.apply(1, "normal", invalid, Rules.PLAYER_POLICY), before, "Invalid time")
		_expect(not runtime.is_frozen(1, invalid) and runtime.remaining_seconds(1, invalid) == 0.0, "Invalid query time is inactive")
		_expect(not runtime.prune(invalid).ok and _snapshot(runtime) == before, "Invalid prune time is atomic")
		_expect(not runtime.frame_prefixes(invalid, 1.0).ok and runtime.frame_prefixes(invalid, 1.0).by_id.is_empty(), "Invalid prefix start is rejected")
		_expect(not runtime.frame_prefixes(0.0, invalid).ok and runtime.frame_prefixes(0.0, invalid).by_id.is_empty(), "Invalid prefix width is rejected")
	for invalid: Variant in [null, true, 1, [], {}, "unique", "Normal", &"normal"]:
		_reject(runtime, runtime.apply(1, invalid, 10.0, Rules.PLAYER_POLICY), before, "Invalid rarity")
	for invalid: Variant in [null, true, [], {}, {"duration_by_rarity": {}}]:
		_reject(runtime, runtime.apply(1, "normal", 10.0, invalid), before, "Invalid policy")
	for invalid: Variant in [null, true, [], "frost", {"unknown": 1}, {1: "frost"}, {&"phase": "hit"},
		{"cast_id": -1}, {"cast_id": 1.0}, {"cast_id": true}, {"projectile_id": "1"}, {"projectile_id": NAN},
		{"skill_id": 1}, {"skill_id": "x".repeat(129)}, {"phase": &"hit"}, {"phase": {}},
		{"skill_id": "frost", "cast_id": 1, "projectile_id": 1, "phase": "hit", "extra": 1}]:
		_reject(runtime, runtime.apply(1, "normal", 10.0, Rules.PLAYER_POLICY, invalid), before, "Invalid or unbounded provenance")
	_reject(runtime, runtime.apply(2, "normal", 0.9, Rules.PLAYER_POLICY), before, "Global settlement time cannot reverse on a different ID")
	_reject(runtime, runtime.apply(1, "normal", 1.0e308, Rules.PLAYER_POLICY), before, "Unrepresentable freeze expiry rejected")
	_reject(runtime, runtime.apply(1, "normal", 1.0e16, Rules.PLAYER_POLICY), before, "Rounded-away duration rejected")
	_expect(not runtime.prune(0.9).ok and _snapshot(runtime) == before, "Pruning cannot reverse time")
	_expect(not runtime.frame_prefixes(1.0e308, 1.0e308).ok, "Overflowed frame end rejected")
	_expect(not runtime.frame_prefixes(1.0e16, 0.1).ok, "Rounded-away positive frame width rejected")
	_expect(_snapshot(runtime) == before, "All invalid queries leave storage unchanged")
	_expect(runtime.apply(2, "magic", 1.0, Rules.PLAYER_POLICY, {"cast_id": 0, "projectile_id": 0, "phase": "x".repeat(128)}).applied,
		"Failed future applications leave time unchanged and bounded metadata is allowed")
	runtime.apply(1, "normal", 1.1, Rules.PLAYER_POLICY)
	before = _snapshot(runtime)
	_reject(runtime, runtime.apply(3, "normal", 1.05, Rules.PLAYER_POLICY), before, "Accepted no-refresh hit still establishes latest settlement boundary")
	runtime.prune(1.2)
	before = _snapshot(runtime)
	_reject(runtime, runtime.apply(3, "normal", 1.15, Rules.PLAYER_POLICY), before, "Prune establishes the next mutation boundary")
	completed = true
