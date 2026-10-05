class_name ManaGuardMigration
extends RefCounted
## Open only schema35 source mana-before-life vocabulary after frozen34 validation.
## Preserve original items, points, currency, UID order, journey and revisions.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v34(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v34(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 35
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
