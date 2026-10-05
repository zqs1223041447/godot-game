class_name IgniteGemMigration
extends RefCounted
## Validate the frozen schema27 gem vocabulary before opening schema28.
## Only the envelope version changes: no gem grants, rerolls, refunds or journey edits.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v27(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v27(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 28
	return candidate if Rules.reason_v28(candidate, validate_talents, socket_ids).is_empty() else {}
