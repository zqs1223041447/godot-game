class_name FasterBurnMigration
extends RefCounted
## Validate frozen schema32 before opening the schema33 source vocabulary.
## Only the version changes; legal old allocations gain no new effects.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v32(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v32(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 33
	return candidate if Rules.reason_v33(candidate, validate_talents, socket_ids).is_empty() else {}
