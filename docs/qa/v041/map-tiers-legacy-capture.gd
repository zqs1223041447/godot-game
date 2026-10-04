extends SceneTree
## Run against the untouched v40 project before making compiler changes.
## godot --headless --path <v40> --script <this-file> -- <output-file>
const Maps = preload("res://scripts/world/map_compiler.gd")
const Encounters = preload("res://scripts/encounters/encounter_catalog.gd")
func _initialize() -> void:
	var choices: Array = [[]]
	var ids: Array[String] = Encounters.get_ids()
	for id: String in ids:
		choices.append([id])
	for first: int in range(ids.size()):
		for second: int in range(first + 1, ids.size()):
			choices.append([ids[first], ids[second]])
	var records: Array = []
	for map_id: String in ["old_garden", "broken_ruins"]:
		for normal: Array in choices:
			for special: Array in [[], ["elemental_aegis"], ["frost_patrol"], ["storm_patrol"]]:
				records.append({"map_id": map_id, "normal": normal, "special": special,
					"result": Maps.compile(map_id, normal, special)})
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Provide exactly one output path")
		quit(1)
		return
	var file := FileAccess.open(arguments[0], FileAccess.WRITE)
	if file == null:
		push_error("Unable to write baseline")
		quit(1)
		return
	var data := var_to_bytes(records)
	file.store_buffer(data)
	file.close()
	print("Captured %d legacy compile results, %d bytes" % [records.size(), data.size()])
	quit()
