class_name TelegraphProfiles
extends RefCounted
## Original standalone attack data. Runtime and future catalog adapters share this source.

const SCHEMA_VERSION: int = 1
const PROFILE_ID: String = "locked_circle"
const BALANCE_VERSION: String = "original-telegraphed-area-v1"
const MAX_ACTIVE: int = 100
const DEFAULTS: Dictionary = {
	"windup_seconds": 0.7, "recovery_seconds": 1.2,
	"radius": 90.0, "damage_multiplier": 1.4,
}
const LIMITS: Dictionary = {
	"windup_seconds": {"minimum": 0.001, "maximum": 60.0},
	"recovery_seconds": {"minimum": 0.001, "maximum": 60.0},
	"radius": {"minimum": 0.001, "maximum": 4096.0},
	"damage_multiplier": {"minimum": 0.0, "maximum": 100.0},
}


static func resolve(overrides: Variant = {}) -> Dictionary:
	if not overrides is Dictionary or overrides.size() > DEFAULTS.size():
		return {"ok": false, "reason": "Profile must be a bounded object"}
	var profile: Dictionary = DEFAULTS.duplicate(true)
	for key: Variant in overrides:
		if not key is String or not DEFAULTS.has(key):
			return {"ok": false, "reason": "Unknown profile field"}
		var value: Variant = overrides[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return {"ok": false, "reason": "Profile values must be finite numbers"}
		if float(value) < float(LIMITS[key].minimum) or float(value) > float(LIMITS[key].maximum):
			return {"ok": false, "reason": "Profile value outside bounds: " + key}
		profile[key] = float(value)
	return {"ok": true, "reason": "", "profile": profile}


static func metadata(overrides: Variant = {}) -> Dictionary:
	var checked: Dictionary = resolve(overrides)
	if not checked.ok:
		return checked
	return {
		"ok": true, "reason": "", "id": PROFILE_ID, "schema_version": SCHEMA_VERSION,
		"name": "锁点圆形蓄力攻击", "origin": "original", "source_refs": [],
		"balance_version": BALANCE_VERSION, "status": "standalone_not_integrated",
		"profile": checked.profile, "defaults": DEFAULTS.duplicate(true), "limits": LIMITS.duplicate(true),
		"max_active": MAX_ACTIVE, "max_sources_per_advance": MAX_ACTIVE,
		"max_events_per_attack": 1, "shape": "circle", "event_type": "circle_attack",
		"target_rule": "lock_center_at_start", "damage_rule": "contact_components_times_multiplier",
		"settlement": "DamageResolver/DefenseRules", "automatic_repeat": false,
		"states": ["windup", "recovery"], "spawn_rule": "reject_or_cancel_while_spawn_positive",
	}
