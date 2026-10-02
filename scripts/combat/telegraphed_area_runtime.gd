class_name TelegraphedAreaRuntime
extends RefCounted
## Bounded pure-data scheduler. No damage settlement, drawing, signals, or RNG.
## Callers supply a complete frame-start source snapshot, then consume copied events.

const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const MAX_ACTIVE: int = Profiles.MAX_ACTIVE
const TIME_EPSILON: float = 0.000000001

var _states: Dictionary = {}
var _next_attack_id: int = 1


func start(enemy: Variant, target_center: Vector2, overrides: Variant = {}) -> Dictionary:
	if not enemy is Dictionary or not _valid_id(enemy.get("id")) or not _can_attack(enemy):
		return _failure("Source must be alive and outside birth protection")
	var source_id: int = int(enemy.id)
	if _states.has(source_id):
		return _failure("Source already has an attack in progress")
	if _states.size() >= MAX_ACTIVE:
		return _failure("Attack capacity reached")
	if not target_center.is_finite():
		return _failure("Target center must be finite")
	var checked: Dictionary = Profiles.resolve(overrides)
	if not checked.ok:
		return checked
	if not _nonnegative_number(enemy.get("damage")):
		return _failure("Contact damage must be finite and nonnegative")
	var weights: Variant = enemy.get("contact_weights", {"physical": 1.0})
	if not weights is Dictionary or weights.size() > Damage.TYPES.size():
		return _failure("Contact weights must be a bounded object")
	var validated: Dictionary = Defense.validate_components(weights)
	if not validated.ok or not is_equal_approx(float(validated.get("total", 0.0)), 1.0):
		return _failure("Contact weights must be valid damage types summing to one")
	# Use the existing contact-component authority only after validating its inputs.
	var components: Dictionary = Monsters.contact_components(enemy)
	for type: String in components:
		components[type] = float(components[type]) * float(checked.profile.damage_multiplier)
	validated = Defense.validate_components(components)
	if not validated.ok:
		return _failure("Scaled contact damage is invalid or overflowed")
	var attack: Dictionary = {
		"source_id": source_id, "attack_id": _next_attack_id, "phase": "windup", "elapsed": 0.0,
		"center": target_center, "profile": checked.profile,
		"packet": Damage.packet(validated.components, ["attack", "area", "hit"], Profiles.PROFILE_ID),
	}
	_next_attack_id += 1
	_states[source_id] = attack
	return {"ok": true, "reason": "", "attack": attack.duplicate(true)}


func advance(delta: float, live_enemies: Variant) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	# Reject a partial/ambiguous source universe rather than guessing who survived.
	if not live_enemies is Array or live_enemies.size() > MAX_ACTIVE:
		reset()
		return events
	var live: Dictionary = {}
	for enemy: Variant in live_enemies:
		if not enemy is Dictionary or not _valid_id(enemy.get("id")) or live.has(enemy.id):
			reset()
			return events
		live[enemy.id] = _can_attack(enemy)
	var pending: Array[Dictionary] = []
	for source_id: int in _states.keys():
		# Cancellation also runs on zero, negative, or nonfinite delta.
		if not bool(live.get(source_id, false)):
			_states.erase(source_id)
			continue
		if not is_finite(delta) or delta <= 0.0:
			continue
		var attack: Dictionary = _states[source_id]
		var windup: float = float(attack.profile.windup_seconds)
		var duration: float = windup + float(attack.profile.recovery_seconds)
		var previous: float = float(attack.elapsed)
		# Cap arithmetic, not the caller's simulated time; even a huge delta finishes.
		attack.elapsed = minf(duration, previous + minf(delta, duration))
		if attack.phase == "windup" and float(attack.elapsed) + TIME_EPSILON >= windup:
			attack.phase = "recovery"
			pending.append({"at": maxf(0.0, windup - previous), "event": {
				"type": "circle_attack", "shape": "circle", "source_id": source_id,
				"attack_id": attack.attack_id, "center": attack.center, "radius": attack.profile.radius,
				"attack_age": windup, "profile_id": Profiles.PROFILE_ID,
				"schema_version": Profiles.SCHEMA_VERSION, "balance_version": Profiles.BALANCE_VERSION,
				"profile": attack.profile.duplicate(true), "packet": attack.packet.duplicate(true),
			}})
		if float(attack.elapsed) + TIME_EPSILON >= duration:
			_states.erase(source_id)
	# Stable chronological order within this call; equal deadlines use source identity.
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.at) != float(b.at):
			return float(a.at) < float(b.at)
		return int(a.event.source_id) < int(b.event.source_id))
	for item: Dictionary in pending:
		events.append(item.event)
	return events


func cancel(source_id: int) -> bool:
	return _states.erase(source_id)


func reset() -> void:
	_states.clear()
	# Like MonsterRuntime identities, attack identities never restart on reset.


func active_count() -> int:
	return _states.size()


func state_for(source_id: int) -> Dictionary:
	return _states.get(source_id, {}).duplicate(true)


static func _valid_id(value: Variant) -> bool:
	return value is int and int(value) > 0


static func _nonnegative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _can_attack(enemy: Dictionary) -> bool:
	return (_nonnegative_number(enemy.get("health")) and float(enemy.health) > 0.0
		and _nonnegative_number(enemy.get("spawn")) and float(enemy.spawn) == 0.0
		and enemy.get("death_processed", false) is bool and not bool(enemy.get("death_processed", false)))


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
