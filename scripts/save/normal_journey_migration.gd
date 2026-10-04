class_name NormalJourneyMigration
extends RefCounted
## Schema25 must pass its frozen envelope before a new empty journey is added.
## Never infer past kills, grant items or change the source passive vocabulary.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")

static func migrate_v25(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v25(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 26
	candidate["journey"] = Journey.empty()
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
