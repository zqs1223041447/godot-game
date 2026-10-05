class_name ElementalResistanceCapMigration
extends RefCounted
## Open schema36 source vocabulary only after strict, frozen schema35 validation.
## Preserve every item, point, revision, UID, journey and allocation unchanged.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v35(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v35(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 36
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
