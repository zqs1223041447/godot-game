class_name FlaskItemMigration
extends RefCounted
## Once-only v17 -> v18 starter grant; the Store validates/backups raw bytes first.
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Flasks=preload("res://scripts/items/flask_catalog.gd")
static func migrate_v17(source:Variant,validate_talents:Callable=Callable(),socket_ids:Array=[])->Dictionary:
	if not Rules.reason_v17(source,validate_talents,socket_ids).is_empty():return {}
	var candidate:Dictionary=source.duplicate(true)
	candidate.version=Rules.VERSION
	var index:=1
	for id:String in ["flask:life","flask:mana"]:
		var serial:=index
		var uid:="migration_flask_%06d"%serial
		while candidate.items.has(uid):serial+=1;uid="migration_flask_%06d"%serial
		candidate.items[uid]=Flasks.create_instance(uid,id)
		candidate.locations[uid]={"kind":"flask_slot","slot_id":"flask_%d"%index}
		index+=1
	return candidate if Rules.reason(candidate,validate_talents,socket_ids).is_empty() else {}
