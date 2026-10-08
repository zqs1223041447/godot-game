class_name RuinsGardenMigration
extends RefCounted
## Validate the complete frozen four-map schema53 before opening Ruins Garden.
## Every old progress key, owned item, run/reward identity and revision stays intact.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v53(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v53(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 54
	candidate.journey.best_tiers["ruins_garden"] = 0
	return candidate if Rules.reason_v54(candidate, validate_talents, socket_ids).is_empty() else {}
