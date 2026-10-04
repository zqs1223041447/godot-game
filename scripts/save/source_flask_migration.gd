class_name SourceFlaskMigration
extends RefCounted
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
static func migrate_v22(source:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->Dictionary:
	if not Rules.reason_v22(source,validate_talents,socket_ids).is_empty():return {}
	var candidate:Dictionary=source.duplicate(true);candidate.version=Rules.V23_VERSION
	return candidate if Rules.reason_v23(candidate,validate_talents,socket_ids).is_empty() else {}
