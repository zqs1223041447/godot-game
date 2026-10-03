extends SceneTree
## Native, isolated interaction fixture. It only prepares catalog items and
## records the actual UI/model results; all craft and drag actions are manual.
var arena: Node2D
var output := OS.get_environment("V022_CURRENCY_NATIVE_DIR")
var gear: Array[String] = []
var records: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if output.is_empty() or DisplayServer.get_name() == "headless" \
			or not isolated.begins_with("/workspace/scratch/a51485f153de/v022-currency-native-user/") \
			or not OS.get_user_data_dir().begins_with(isolated+"/"):
		quit(78)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	root.title = "v0.22 Currency Native QA"
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 220022
	for index: int in range(4):
		var uid: String = arena.state.award_equipment(rng,30,"rare" if index < 3 else "magic","current")
		if uid.is_empty(): push_error("Native currency fixture admission failed"); quit(1); return
		gear.append(uid)
	if arena.state.save_build() != OK: push_error("Native currency fixture save failed"); quit(1); return
	arena.state.changed.connect(record.call_deferred)
	arena.hud.open_panel("inventory")
	arena.hud._toast.hide()
	for unused: int in range(6): await process_frame
	record()
	print("CURRENCY_NATIVE_READY ", JSON.stringify(gear))

func record() -> void:
	var state = arena.state
	var snapshot: Dictionary = state.snapshot()
	var stacks: Dictionary = {}
	for uid: String in snapshot.items:
		if snapshot.items[uid].kind == "currency":
			stacks[uid] = {"quantity":snapshot.items[uid].payload.quantity,"location":snapshot.locations[uid]}
	var panel: Control = arena.hud._inventory_panel
	var grid: Control = panel._grid
	var cells: Dictionary = {}
	for uid: String in gear + Array(stacks.keys()):
		if snapshot.locations.has(uid) and snapshot.locations[uid].kind == "bag":
			var box: Rect2 = grid.get_global_transform_with_canvas()*grid.item_rect(uid)
			cells[uid] = {"name":state.item_definition(uid).name,"rect":[box.position.x,box.position.y,box.size.x,box.size.y]}
	var raw := FileAccess.get_file_as_string("user://build_save.json")
	var entry := {"revision":state.revision(),"balance":state.crafting_balance(),"stacks":stacks,"gear":cells,
		"successful_saves":state.successful_saves,"snapshot_matches_disk":raw == JSON.stringify(snapshot,"\t",true,true),
		"schema":snapshot.version,"crafting":snapshot.crafting,"bag_layout":state.bag_layout(),
		"layout_valid":state.Rules.reason(snapshot).is_empty(),"selected_uid":panel._selected_uid}
	records.append(entry)
	var file := FileAccess.open(output.path_join("native-currency-records.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t",true,true))
	file.close()
	print("CURRENCY_NATIVE_STATE ",JSON.stringify(entry))
