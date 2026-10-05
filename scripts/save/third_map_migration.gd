class_name ThirdMapMigration
extends RefCounted
## Validate the complete frozen schema29 envelope before opening the third map.
## Preserve all existing progress and identities; no currency or item grants.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v29(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v29(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 30
	candidate.journey.best_tiers["sunwell_terrace"] = 0
	return candidate if Rules.reason_v30(candidate, validate_talents, socket_ids).is_empty() else {}
