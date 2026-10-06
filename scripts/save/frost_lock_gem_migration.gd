class_name FrostLockGemMigration
extends RefCounted
## Open only Frost Lock after complete frozen46 validation.
## Source policy45, equipment46, inventory and all nonversion fields stay intact.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v46(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v46(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 47
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
