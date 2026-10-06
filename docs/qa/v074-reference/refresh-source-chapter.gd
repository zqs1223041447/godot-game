extends SceneTree
## Bounded correction: regenerate only the new chapter from its real authority.
const Exporter = preload("res://tools/export_reference.gd")

func _initialize() -> void:
	var path := "res://docs/reference/catalog.json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data.has("source_monster_movement"))
	data.source_monster_movement = Exporter.clean(Exporter.source_monster_movement_examples())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(data, "\t", true, true) + "\n")
	file.close()
	print("Regenerated only source_monster_movement from current authorities")
	quit(0)
