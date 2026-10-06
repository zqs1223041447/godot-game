class_name FourthMapMigration
extends RefCounted
## Validate all frozen schema49 fields before opening the fourth map.
## Existing items, progress, pending awards and ordinals are never reconstructed.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v49(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v49(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 50
	candidate.journey.best_tiers["ginkgo_arcade"] = 0
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
