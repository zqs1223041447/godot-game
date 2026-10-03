extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const InventoryView = preload("res://scripts/ui/canonical_inventory_panel.gd")
const ThemeStyle = preload("res://scripts/visuals/visual_theme.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
var checks := 0
var failures := 0
var output := OS.get_environment("CANONICAL_INVENTORY_CAPTURE_DIR")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	var model := Model.new()
	var path := "user://inventory-%d.json" % Time.get_ticks_usec()
	check(model.save_build(path) == OK,"fixture save")
	var rng := RandomNumberGenerator.new()
	rng.seed = 14051
	var seen := {}
	for index: int in range(100):
		var uid: String = "gear_%06d" % model.snapshot().next_item_serial
		var item := Gear.generate_for_pool(rng,uid,30,"rare","nine_slot")
		var slot: String = Gear.base_definition(item.base_id).slot
		if seen.has(slot): continue
		check(model._admit_reward_item(Items.wrap_equipment(item)),"real catalog fixture admitted")
		var target: String = "ring_1" if slot == "ring" else slot
		check(model.move_item(uid,{"kind":"equipment","slot_id":target},model.revision(),path).ok,"actual equip to canonical target")
		seen[slot] = uid
		if seen.size() == 5: break
	check(seen.size() == 5,"all five new categories shown")
	var host := Control.new()
	host.theme = ThemeStyle.create_theme()
	root.add_child(host)
	var paper := PanelContainer.new()
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var surface: StyleBox = ThemeStyle.panel(Color("f1deb3"),ThemeStyle.BORDER,10,1,0)
	surface.book_cover = true
	paper.add_theme_stylebox_override("panel",surface)
	host.add_child(paper)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,20)
	paper.add_child(margin)
	var panel := InventoryView.new()
	margin.add_child(panel)
	panel.setup(model,path)
	for screen: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size = screen
		host.scale = Vector2.ONE * 1.1
		host.size = root.get_visible_rect().size / 1.1
		ThemeStyle.apply_font_scale(host,1.2)
		for i: int in range(8): await process_frame
		var world_bounds: Rect2 = Rect2(Vector2.ZERO,root.get_visible_rect().size)
		print("INVENTORY_LAYOUT ",screen," bounds=",world_bounds," host=",host.size," panel=",panel.get_global_rect()," paper=",panel._paper.get_global_rect())
		check(world_bounds.encloses(panel.get_global_rect()),"inventory body inside actual logical viewport")
		for slot: String in panel._slots:
			check(world_bounds.encloses(panel._slots[slot].get_global_rect()),"all nine targets inside viewport: " + slot + str(panel._slots[slot].get_global_rect()))
		check(panel._grid.grid_cell_size() >= 30.0,"shared grid remains readable")
		var bag_before: Dictionary = model.location("swift_blade")
		panel._activate_item("swift_blade")
		check(model.location("swift_blade").kind == "equipment","inventory action really equips")
		panel._return_to_bag("swift_blade")
		check(model.location("swift_blade").kind == "bag","unequip returns through atomic store")
		check(not bag_before.is_empty(),"original UID retained")
		if not output.is_empty() and DisplayServer.get_name() != "headless":
			DirAccess.make_dir_recursive_absolute(output)
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png(output.path_join("inventory-%d-ui110-font120.png" % screen.x))
	print("Canonical inventory body: %d checks, %d failures" % [checks,failures])
	host.queue_free()
	await process_frame
	quit(1 if failures else 0)
func check(ok: bool,label: String)->void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
