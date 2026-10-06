class_name AmbushGemMigration
extends RefCounted
## Open only the Ambush gem after complete frozen41 envelope validation.
## Source policy41, equipment39, rewards and every nonversion field stay intact.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v41(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v41(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 42
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
