class_name PreciseTechniqueMigration
extends RefCounted
## Open only the full original Precise Technique node after frozen44 validation.
## Source policy45 changes no inventory, points, rewards, or other saved fields.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v44(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v44(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 45
	return candidate if Rules.reason_v45(candidate, validate_talents, socket_ids).is_empty() else {}
