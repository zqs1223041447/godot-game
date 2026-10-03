class_name SkillCooldownLedger
extends RefCounted
## Runtime-only cooldown debt keyed by stable skill-group and main-gem identities.
## The caller owns admission, payment, persistence policy, death and run resets.

const ItemLocations = preload("res://scripts/items/item_location_rules.gd")

var _group_debts: Dictionary = {}
var _main_uid_debts: Dictionary = {}


## Return the greater of the configured group's and main gem UID's remaining debt.
## Invalid IDs have no addressable debt and return zero; begin() still rejects them.
func remaining(group_id: Variant, main_uid: Variant) -> float:
	if not _stable_id(group_id) or not _stable_id(main_uid):
		return 0.0
	return maxf(float(_group_debts.get(group_id, 0.0)), float(_main_uid_debts.get(main_uid, 0.0)))


## Record identical debt on both identities only when neither is cooling down.
## Zero duration is a successful, immediately expired cast with no stored debt.
func begin(group_id: Variant, main_uid: Variant, duration: Variant) -> bool:
	if not _stable_id(group_id) or not _stable_id(main_uid) or not _nonnegative_finite_number(duration):
		return false
	if remaining(group_id, main_uid) > 0.0:
		return false
	var seconds: float = float(duration)
	if seconds > 0.0:
		_group_debts[group_id] = seconds
		_main_uid_debts[main_uid] = seconds
	return true


## Subtract a finite, non-negative frame delta from every debt. Returns false and
## leaves both maps untouched for invalid input. Exact-boundary debt expires.
func advance(delta: Variant) -> bool:
	if not _nonnegative_finite_number(delta):
		return false
	var seconds: float = float(delta)
	if seconds == 0.0:
		return true
	_decrement(_group_debts, seconds)
	_decrement(_main_uid_debts, seconds)
	return true


## Clear runtime state. The run owner should call this on death and run restart.
func reset() -> void:
	_group_debts.clear()
	_main_uid_debts.clear()


## Return detached maps. The result is diagnostic/runtime state, not save data.
func snapshot() -> Dictionary:
	return {
		"group_debts": _group_debts.duplicate(true),
		"main_uid_debts": _main_uid_debts.duplicate(true),
	}


func _decrement(debts: Dictionary, seconds: float) -> void:
	for stable_id: String in debts.keys():
		var next_debt: float = float(debts[stable_id]) - seconds
		if next_debt <= 0.0:
			debts.erase(stable_id)
		else:
			debts[stable_id] = next_debt


static func _stable_id(value: Variant) -> bool:
	# Keep group/gem identities exactly aligned with the location system's protocol.
	return ItemLocations._stable_id(value)


static func _nonnegative_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0
