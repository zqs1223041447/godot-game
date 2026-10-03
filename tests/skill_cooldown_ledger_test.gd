extends SceneTree
## Pure runtime-ledger contract. No game state, compiler, payment or save integration.
const Ledger = preload("res://scripts/combat/skill_cooldown_ledger.gd")
const ItemLocations = preload("res://scripts/items/item_location_rules.gd")

var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(810032)
	var expected_rng: Array[int] = [randi(), randi(), randi(), randi()]
	seed(810032)
	_case(_test_locks_and_boundary, "stable group/gem locks, repeat admission and exact expiry")
	_case(_test_identity_independence_and_max, "same-name UID independence and maximum debt")
	_case(_test_snapshot_and_reset, "detached snapshot and reset")
	_case(_test_invalid_ids, "ItemLocationRules stable ID protocol")
	_case(_test_invalid_numbers, "strict finite non-negative numeric inputs and atomic rejection")
	_case(_test_zero_and_large_delta, "zero duration, zero delta and large finite delta")
	_expect([randi(), randi(), randi(), randi()] == expected_rng, "All valid and invalid operations preserve the global RNG stream")
	print("Skill cooldown ledger: %d checks, %d failures" % [checks, failures])
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


func _near(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) <= 0.000001, "%s (actual %.8f, expected %.8f)" % [label, actual, expected])


func _test_locks_and_boundary() -> void:
	var ledger = Ledger.new()
	_expect(ledger.begin("row_stable_7", "skill_gem_0001", 8.0), "First real cast can record group and gem debt")
	_near(ledger.remaining("row_stable_7", "skill_gem_0001"), 8.0, "Initial debt")
	_expect(not ledger.begin("row_stable_7", "skill_gem_0001", 99.0), "Repeated begin cannot overwrite active debt")
	_expect(not ledger.begin("row_stable_7", "skill_gem_0002", 4.0), "Changing the main gem cannot bypass its stable group debt")
	_expect(not ledger.begin("row_moved_elsewhere", "skill_gem_0001", 4.0), "Moving the main gem to another group cannot bypass its UID debt")
	_near(ledger.remaining("row_stable_7", "skill_gem_0002"), 8.0, "A replacement gem still sees the group's debt")
	_near(ledger.remaining("row_moved_elsewhere", "skill_gem_0001"), 8.0, "A moved gem still sees its own UID debt")
	_near(ledger.remaining("row_unrelated", "skill_gem_0099"), 0.0, "Unrelated stable identities remain ready")
	_expect(ledger.advance(3), "Valid delta advances the ledger")
	_near(ledger.remaining("row_stable_7", "skill_gem_0001"), 5.0, "Debt decreases by delta")
	_expect(ledger.advance(5), "Advancing exactly to the debt boundary is valid")
	_near(ledger.remaining("row_stable_7", "skill_gem_0001"), 0.0, "Exact expiry boundary is ready")
	_expect(ledger.begin("row_stable_7", "skill_gem_0001", 1), "Cast can begin again at exact expiry")
	completed = true


func _test_identity_independence_and_max() -> void:
	var ledger = Ledger.new()
	# These UIDs represent two instances of the same skill definition.
	_expect(ledger.begin("row_bolt_a", "skill_gem_bolt_0001", 5), "First same-name skill instance begins independently")
	_expect(ledger.begin("row_bolt_b", "skill_gem_bolt_0002", 9), "Second same-name skill instance in another group is independent")
	_near(ledger.remaining("row_bolt_a", "skill_gem_bolt_0001"), 5.0, "First instance keeps its own cooldown")
	_near(ledger.remaining("row_bolt_b", "skill_gem_bolt_0002"), 9.0, "Second instance keeps its own cooldown")
	_near(ledger.remaining("row_bolt_a", "skill_gem_bolt_0002"), 9.0, "Query takes the maximum of group and gem debts")
	_expect(ledger.advance(9), "All independent casts expire after their exact maximum")
	_near(ledger.remaining("row_bolt_a", "skill_gem_bolt_0001"), 0.0, "Both same-name instances are ready after their own debts expire")

	# Build group-only and gem-only debt with separate successful casts, then query their max.
	_expect(ledger.begin("row_alpha", "skill_gem_shared", 8), "Prepare first identity pair")
	_expect(ledger.advance(8), "Expire first identity pair")
	_expect(ledger.begin("row_alpha", "skill_gem_other", 10), "Assign longer debt to group alpha")
	_expect(ledger.begin("row_beta", "skill_gem_shared", 3), "Assign shorter debt to shared gem UID")
	_near(ledger.remaining("row_alpha", "skill_gem_shared"), 10.0, "Group debt wins when it is greater than gem debt")
	_expect(ledger.advance(3), "Advance shorter UID debt to exact expiry")
	_near(ledger.remaining("row_alpha", "skill_gem_shared"), 7.0, "Remaining query keeps the greater group debt")
	completed = true


func _test_snapshot_and_reset() -> void:
	var ledger = Ledger.new()
	_expect(ledger.begin("row_snapshot", "skill_gem_snapshot", 6), "Snapshot fixture starts with debt")
	var before: Dictionary = ledger.snapshot()
	_expect(before.size() == 2 and before.has_all(["group_debts", "main_uid_debts"]), "Snapshot has the exact two debt maps")
	_expect(before.group_debts == {"row_snapshot": 6.0} and before.main_uid_debts == {"skill_gem_snapshot": 6.0}, "Snapshot exposes current debts by stable identity")
	before.group_debts.row_snapshot = -1.0
	before.main_uid_debts.clear()
	before.group_debts["injected"] = [1, 2, 3]
	_expect(ledger.snapshot() == {"group_debts": {"row_snapshot": 6.0}, "main_uid_debts": {"skill_gem_snapshot": 6.0}}, "Mutating returned nested maps cannot change ledger state")
	ledger.reset()
	_expect(ledger.snapshot() == {"group_debts": {}, "main_uid_debts": {}}, "Reset clears both runtime maps")
	_near(ledger.remaining("row_snapshot", "skill_gem_snapshot"), 0.0, "Reset makes prior identities ready")
	completed = true


func _test_invalid_ids() -> void:
	var ledger = Ledger.new()
	_expect(ledger.begin("row_kept", "skill_gem_kept", 4), "Invalid-input fixture has existing state")
	var before: Dictionary = ledger.snapshot()
	var invalid_ids: Array = [null, "", " padded ", "line\nbreak", "tab\tvalue", "delete" + String.chr(127),
		"x".repeat(129), true, false, 1, 1.0, NAN, INF, -INF, [], {}, &"row_kept"]
	for invalid: Variant in invalid_ids:
		_expect(not ItemLocations._stable_id(invalid), "Reference protocol rejects fixture: " + str(invalid))
		_expect(not ledger.begin(invalid, "skill_gem_new", 3), "Invalid group ID rejects without coercion: " + str(invalid))
		_expect(not ledger.begin("row_new", invalid, 3), "Invalid main UID rejects without coercion: " + str(invalid))
		_expect(ledger.snapshot() == before, "Invalid IDs leave both debt maps unchanged: " + str(invalid))
	_expect(ledger.remaining(" padded ", "skill_gem_kept") == 0.0, "Invalid remaining query returns zero without creating aliases")
	_expect(ledger.snapshot() == before, "Invalid remaining query leaves state unchanged")
	var maximum_id: String = "x".repeat(128)
	_expect(ItemLocations._stable_id(maximum_id) and ledger.begin(maximum_id, "skill_gem_maximum_id", 2), "Protocol maximum-length ID is accepted")
	_expect(ledger.remaining(maximum_id, "skill_gem_maximum_id") == 2.0, "Accepted maximum-length ID addresses its exact debt")
	completed = true


func _test_invalid_numbers() -> void:
	var ledger = Ledger.new()
	_expect(ledger.begin("row_numeric", "skill_gem_numeric", 7), "Numeric fixture begins")
	var before: Dictionary = ledger.snapshot()
	var invalid_numbers: Array = [null, true, false, "2", [], {}, NAN, INF, -INF, -1, -0.5]
	for invalid: Variant in invalid_numbers:
		_expect(not ledger.begin("row_free_" + str(checks), "skill_gem_free_" + str(checks), invalid), "Invalid duration rejects: " + str(invalid))
		_expect(ledger.snapshot() == before, "Invalid duration leaves ledger unchanged: " + str(invalid))
		_expect(not ledger.advance(invalid), "Invalid delta rejects: " + str(invalid))
		_expect(ledger.snapshot() == before, "Invalid delta leaves ledger unchanged: " + str(invalid))
	_expect(ledger.remaining("row_numeric", "skill_gem_numeric") == 7.0, "Rejected numeric calls preserve the existing cooldown")
	completed = true


func _test_zero_and_large_delta() -> void:
	var ledger = Ledger.new()
	_expect(ledger.begin("row_zero", "skill_gem_zero", 0), "Zero duration is a successful immediate cast")
	_expect(ledger.snapshot() == {"group_debts": {}, "main_uid_debts": {}}, "Zero duration leaves no active debt")
	_expect(ledger.begin("row_zero", "skill_gem_zero", 0.0), "Zero-duration cast can be repeated immediately")
	_expect(ledger.advance(0), "Zero delta is a valid no-op")
	_expect(ledger.snapshot() == {"group_debts": {}, "main_uid_debts": {}}, "Zero delta does not create or remove debt")
	_expect(ledger.begin("row_long", "skill_gem_long", 120), "Large-delta fixture begins")
	_expect(ledger.advance(1.0e300), "A very large finite delta is accepted")
	_expect(ledger.snapshot() == {"group_debts": {}, "main_uid_debts": {}}, "Large delta drains every active debt")
	_expect(ledger.begin("row_after_large", "skill_gem_after_large", 1), "Ledger remains usable after a large delta")
	completed = true
