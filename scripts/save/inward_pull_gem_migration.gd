class_name InwardPullGemMigration
extends RefCounted
## Open only the Inward Pull gem after complete frozen42 envelope validation.
## Source policy41, equipment39, rewards and every nonversion field stay intact.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v42(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v42(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 43
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
