class_name ShockGemMigration
extends RefCounted
## Validate the complete frozen schema30 envelope before opening schema31.
## Only the version changes; items, identities, revisions and rewards stay intact.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v30(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v30(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 31
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
