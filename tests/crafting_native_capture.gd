extends SceneTree
## Isolated Linux display fixture; actual mouse actions are observed, not emitted.
var arena: Node2D
var panel: InventoryPanel
var target: String
var spare_ids: Array[String] = []
var original: Dictionary
var directory: String
var report: Dictionary = {"inputs": [], "transactions": [], "cancel_count": 0}
var before: Dictionary
var capturing: bool = false

class Observer extends Node:
	var host: SceneTree
	func _input(event: InputEvent) -> void: host.observe(event)

func _initialize() -> void: call_deferred("run")

func save_report() -> void:
	var file := FileAccess.open(directory.path_join("native-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t",true,true))
	file.close()

func run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if OS.get_name()!="Linux" or DisplayServer.get_name()=="headless" or not isolated.begins_with("/tmp/godot-crafting-qa-native") or not OS.get_user_data_dir().begins_with(isolated+"/"):
		printerr("Native crafting fixture refuses non-rendering or non-isolated user data")
		quit(78)
		return
	directory = OS.get_environment("GODOT_CRAFT_NATIVE_OUT")
	if not directory.is_absolute_path():
		quit(78)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280,720)
	root.position = Vector2i(10,30)
	root.title = "v0.15 craft QA - cancel then recycle twice and calibrate"
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 150015
	target = arena.state.award_equipment(rng,16,"magic","local_weapon")
	for unused: int in range(2): spare_ids.append(arena.state.award_equipment(rng,16,"rare","current"))
	assert(not target.is_empty() and not spare_ids.has(""))
	original = arena.state.equipment_instances[target].duplicate(true)
	before = arena.state._snapshot()
	arena.hud.open_panel("inventory")
	panel = arena.hud._inventory_panel
	panel.select_item("item:"+spare_ids[0])
	var observer := Observer.new()
	observer.host = self
	root.add_child(observer)
	arena.state.changed.connect(changed)
	panel._craft_dialog.canceled.connect(cancelled)
	report.fixture = {"user_data_dir": OS.get_user_data_dir(), "source_items": arena.state.equipment_instances.duplicate(true),
		"changes": ["fresh isolated save", "three real catalog rewards at level16", "simulation held", "selection prepared between operations"],
		"wallet_granted": false, "target":target}
	save_report()
	await prepare_next()
	if OS.get_cmdline_user_args().has("--dialog-capture-only"):
		arena.visual_settings.font_scale = 1.2
		arena.hud._apply_presentation()
		panel.select_item("item:"+spare_ids[0])
		panel._request_craft("salvage",spare_ids[0],arena.state.equipment_instances[spare_ids[0]].duplicate(true))
		await capture("confirmation-maxfont-final")
		print("CRAFT_DIALOG_CAPTURE_COMPLETE")
		quit(0)
		return
	print("CRAFT_NATIVE_READY")

func observe(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		report.inputs.append({"mouse_button":event.button_index,"position":[event.position.x,event.position.y]})
	elif event is InputEventKey and event.pressed and not event.echo:
		report.inputs.append({"key":OS.get_keycode_string(event.physical_keycode)})
	save_report()

func cancelled() -> void:
	report.cancel_count += 1
	report.cancel_preserved = arena.state._snapshot() == before
	save_report()
	print("CRAFT_NATIVE_CANCEL ",report.cancel_preserved)

func changed() -> void:
	if not arena.state.crafting_change_already_saved(): return
	var snapshot: Dictionary = arena.state._snapshot()
	var record: Dictionary = {"revision":snapshot.crafting.revision,"balance":snapshot.crafting.materials.calibration_shard,
		"inventory_size":snapshot.inventory.size(),"saved_exact":FileAccess.get_file_as_string("user://build_save.json")==JSON.stringify(snapshot,"\t",true,true),
		"target":snapshot.equipment_instances.get(target,{}).duplicate(true)}
	report.transactions.append(record)
	before = snapshot
	save_report()
	print("CRAFT_NATIVE_TRANSACTION ",JSON.stringify(record))
	prepare_next.call_deferred()

func prepare_next() -> void:
	for unused: int in range(5): await process_frame
	var next: String = target
	for id: String in spare_ids:
		if arena.state.inventory.has(id):
			next = id
			break
	panel.select_item("item:"+next)
	for unused: int in range(5): await process_frame
	arena.hud._panel_scroll.ensure_control_visible(panel._craft_controls)
	for unused: int in range(5): await process_frame
	await capture("stage-%d" % int(arena.state.crafting.revision))
	if int(arena.state.crafting.revision)>=3:
		var result: Dictionary = arena.state.equipment_instances[target]
		var valid: bool = report.transactions.size()==3 and report.cancel_count>=1 and report.get("cancel_preserved",false)
		for transaction: Dictionary in report.transactions: valid = valid and transaction.saved_exact
		valid = valid and result.id==original.id and result.base_id==original.base_id and result.item_level==original.item_level
		for index: int in range(original.affixes.size()):
			valid = valid and result.affixes[index].id==original.affixes[index].id and result.affixes[index].tier==original.affixes[index].tier
		report.passed = valid
		save_report()
		print("CRAFT_NATIVE_PASS ", valid)
		# Rendering-only 720p/2K max-font captures; no claim of 2K physical input.
		for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
			root.size=resolution
			arena.visual_settings.ui_scale=1.1
			arena.visual_settings.font_scale=1.2
			arena.hud._apply_presentation()
			panel.select_item("item:"+target)
			for unused: int in range(5): await process_frame
			arena.hud._panel_scroll.ensure_control_visible(panel._craft_controls)
			await capture("inventory-%dx%d-maxfont" % [resolution.x,resolution.y])
		root.size=Vector2i(1280,720)
		print("CRAFT_NATIVE_CAPTURE_COMPLETE")

func capture(label: String) -> void:
	if capturing:return
	capturing=true
	for unused: int in range(8):await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK)
	capturing=false
