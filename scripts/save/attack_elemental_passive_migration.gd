class_name AttackElementalPassiveMigration
extends RefCounted
## Preserve the entire schema54 build, opening only the exact source effect in55.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v54(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v54(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 55
	return candidate if Rules.reason_v55(candidate, validate_talents, socket_ids).is_empty() else {}
