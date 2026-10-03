class_name ActiveSkillMigration
extends RefCounted
## Pure v16 -> v17 vocabulary upgrade. No item is granted, rerolled or relocated.
## The store owns original-byte backup and final validation before persistence.
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
static func migrate_v16(source: Variant, validate_talents: Callable=Callable(),socket_ids: Array=[])->Dictionary:
	if not Rules.reason_v16(source,validate_talents,socket_ids).is_empty():return {}
	var candidate: Dictionary=source.duplicate(true)
	candidate.version=Rules.VERSION
	return candidate
