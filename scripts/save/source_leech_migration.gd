class_name SourceLeechMigration
extends RefCounted
## Validate schema24 with its frozen vocabulary before opening schema25 effects.
## Leech instances are transient combat state and never enter this envelope.
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
static func migrate_v24(source:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->Dictionary:
	if not Rules.reason_v24(source,validate_talents,socket_ids).is_empty():return {}
	var candidate:Dictionary=source.duplicate(true);candidate.version=25
	return candidate if Rules.reason(candidate,validate_talents,socket_ids).is_empty() else {}
