class_name EquipmentAffixMigration
extends RefCounted
## Validate the frozen schema26 equipment vocabulary before opening schema27.
## Only the envelope version changes: no rerolls, grants, journey resets or refunds.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v26(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v26(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 27
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
