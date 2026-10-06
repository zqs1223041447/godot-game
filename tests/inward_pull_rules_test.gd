extends SceneTree
## Pure policy/vector boundaries; no actors, scene, timers, or persistent save.
const Rules = preload("res://scripts/combat/inward_pull_support_rules.gd")
var checks: int = 0
var failures: int = 0
var completed: bool = false


class Hostile extends RefCounted:
	var calls: int = 0
	func _to_string() -> String:
		calls += 1
		return "toward_origin"
	func _get(_property: StringName) -> Variant:
		calls += 1
		return 190.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(670043)
	var expected: Array = [randi(), randi(), randi()]
	seed(670043)
	_case(_policy, "exact enabled policy and malformed values")
	_case(_vectors, "finite direction, center, translation and no mutation")
	_case(_objects, "objects never execute while validating inputs")
	_expect([randi(), randi(), randi()] == expected, "Pure policy/vector operations preserve global RNG")
	print("Inward pull rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _case(callback: Callable, label: String) -> void:
	completed = false
	callback.call()
	_expect(completed, "Case completed without script errors: " + label)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _profile() -> Dictionary:
	var result: Dictionary = {"enabled": true}
	result.merge(Rules.POLICY.duplicate(true))
	return result


func _reject(value: Variant, label: String) -> void:
	_expect(not Rules.policy_error(value).is_empty() and not Rules.profile_error(value).is_empty(), label)
	_expect(Rules.impulse(Vector2.ZERO, Vector2.RIGHT, value) == Vector2.ZERO, "Invalid policy cannot produce an impulse: " + label)


func _policy() -> void:
	_expect(Rules.POLICY == {"impulse_speed": 190.0, "mana_multiplier": 1.20, "direction": "toward_origin"}, "Exact approved three-field authority")
	var profile := _profile()
	var original := var_to_bytes(profile)
	_expect(Rules.policy_error(profile).is_empty() and Rules.profile_error(profile).is_empty(), "One four-field profile accepted by both boundaries")
	_expect(var_to_bytes(profile) == original, "Validation does not modify policy")
	for value: Variant in [null, true, 190.0, "toward_origin", [], Rules.POLICY, {}, Vector2.ZERO]:
		_reject(value, "Wrong policy shape rejects")
	for key: String in profile:
		var missing := _profile()
		missing.erase(key)
		_reject(missing, "Missing required field: " + key)
		var nested := _profile()
		nested[key] = {"value": profile[key]}
		_reject(nested, "Nested field rejects: " + key)
	var extra := _profile()
	extra.timer = 0.35
	_reject(extra, "New timing or arbitrary extra fields reject")
	for value: Variant in [false, 1, "true", null]:
		var altered := _profile()
		altered.enabled = value
		_reject(altered, "Enabled must be boolean true")
	for value: Variant in ["away_from_origin", "", &"toward_origin", 1, null]:
		var altered := _profile()
		altered.direction = value
		_reject(altered, "Direction must be the exact string")
	for key: String in ["impulse_speed", "mana_multiplier"]:
		for value: Variant in [null, true, "190", 0.0, -1.0, INF, -INF, NAN, 190.001, 1.20001]:
			var altered := _profile()
			altered[key] = value
			_reject(altered, "Numeric policy field must equal finite fixed value: " + key)
	var non_string := _profile()
	non_string.erase("direction")
	non_string[17] = "toward_origin"
	_reject(non_string, "Non-string keys reject")
	completed = true


func _vectors() -> void:
	var policy := _profile()
	var original := var_to_bytes(policy)
	var origin := Vector2(317.0, -109.0)
	for offset: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(3.0, 4.0), Vector2(-43.0, 29.0), Vector2(0.0001, -0.0002)]:
		var target: Vector2 = origin + offset
		var legacy: Vector2 = (target - origin).normalized() * 190.0
		var actual: Vector2 = Rules.impulse(origin, target, policy)
		_expect(actual == -legacy, "Exactly reverses old normalized impulse")
		_expect(absf(actual.length() - 190.0) < 0.0001 and actual.dot(origin - target) > 0.0, "Fixed speed points toward the actual blast origin")
	_expect(Rules.impulse(origin, origin, policy) == Vector2.ZERO, "Enemy at exact center stays zero")
	_expect(Rules.impulse(Vector2(10, 20), Vector2(13, 24), policy) == Rules.impulse(Vector2(110, -80), Vector2(113, -76), policy), "Translation does not change impulse")
	for value: Variant in [null, true, 1.0, [], {}, "Vector2(0, 0)", Vector2i.ZERO, Vector2(INF, 0), Vector2(0, NAN)]:
		_expect(Rules.impulse(value, Vector2.RIGHT, policy) == Vector2.ZERO, "Malformed origin rejects")
		_expect(Rules.impulse(Vector2.ZERO, value, policy) == Vector2.ZERO, "Malformed target rejects")
	_expect(Rules.impulse(Vector2(3.0e38, 0), Vector2(-3.0e38, 0), policy) == Vector2.ZERO, "Overflowing finite coordinate subtraction rejects")
	_expect(var_to_bytes(policy) == original, "Every accepted and rejected vector call preserves policy bytes")
	completed = true


func _objects() -> void:
	var object := Hostile.new()
	_reject(object, "Object-shaped policy rejects")
	for key: String in _profile():
		var policy := _profile()
		policy[key] = object
		_reject(policy, "Object-shaped policy field rejects: " + key)
	var object_key := _profile()
	object_key.erase("direction")
	object_key[object] = "toward_origin"
	_reject(object_key, "Object-shaped key rejects")
	_expect(Rules.impulse(object, Vector2.RIGHT, _profile()) == Vector2.ZERO, "Object-shaped origin rejects")
	_expect(Rules.impulse(Vector2.ZERO, object, _profile()) == Vector2.ZERO, "Object-shaped target rejects")
	_expect(Rules.get_definition(object).is_empty() and not Rules.definition_error(object).is_empty(), "Object-shaped metadata inputs reject")
	_expect(not Rules.compile_program(object, ["inward_pull"]).error.is_empty(), "Object skill rejects")
	_expect(not Rules.compile_program("nova", [object]).error.is_empty(), "Object support rejects")
	_expect(object.calls == 0, "No stringification or property getter on untrusted objects")
	completed = true
