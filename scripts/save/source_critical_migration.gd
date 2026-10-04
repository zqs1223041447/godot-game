class_name SourceCriticalMigration
extends RefCounted
## Validate schema23 with its frozen vocabulary before opening schema24 effects.
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
static func migrate_v23(source:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->Dictionary:
	if not Rules.reason_v23(source,validate_talents,socket_ids).is_empty():return {}
	var candidate:Dictionary=source.duplicate(true);candidate.version=Rules.VERSION
	return candidate if Rules.reason(candidate,validate_talents,socket_ids).is_empty() else {}
