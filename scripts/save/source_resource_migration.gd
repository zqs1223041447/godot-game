class_name SourceResourceMigration
extends RefCounted
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
static func migrate_v21(source:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->Dictionary:
	if not Rules.reason_v21(source,validate_talents,socket_ids).is_empty():return {}
	var candidate:Dictionary=source.duplicate(true);candidate.version=Rules.V22_VERSION
	return candidate if Rules.reason_v22(candidate,validate_talents,socket_ids).is_empty() else {}
