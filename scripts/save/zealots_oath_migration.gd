class_name ZealotsOathMigration
extends RefCounted
## Open the full Zealot's Oath source entry only after complete frozen40 validation.
## Preserve equipment vocabulary39 and every item, roll, point, UID and revision.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v40(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v40(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 41
	return candidate if Rules.reason_v41(candidate, validate_talents, socket_ids).is_empty() else {}
