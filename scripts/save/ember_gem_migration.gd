class_name EmberGemMigration
extends RefCounted
## Open schema29 only after proving the complete frozen schema28 envelope.
## No item grants, identity changes, reward rerolls, refunds or journey edits.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v28(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v28(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 29
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
