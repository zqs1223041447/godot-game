extends SceneTree
## Render-only fixture; actual mouse transfers are verified separately through CUA.
var output := OS.get_environment("DOCKED_CAPTURE_DIR")
var arena: Node2D
var records: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless" or output.is_empty():
		quit(78)
		return
	DirAccess.make_dir_recursive_absolute(output)
	for screen: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		for scale_pair: Vector2 in [Vector2(1.0,1.0),Vector2(1.1,1.2)]:
			root.size = screen
			arena = load("res://scenes/main.tscn").instantiate()
			root.add_child(arena)
			arena.set_process(false)
			arena.set_physics_process(false)
			# Dismiss the transient startup hint for clean, paused UI documentation.
			arena.hud._toast_left = 0.0
			arena.hud._toast.hide()
			var support_uid := ""
			for uid: String in arena.state.snapshot().items:
				if arena.state.item(uid).get("definition_id","") == "support:pierce": support_uid = uid
			if not support_uid.is_empty() and arena.state.location(support_uid).get("kind","") == "bag":
				arena.state.move_item(support_uid,{"kind":"skill_support","group_id":"group_000001","index":0},arena.state.revision(),"user://build_save.json")
			arena.visual_settings.ui_scale = scale_pair.x
			arena.visual_settings.font_scale = scale_pair.y
			arena.hud._apply_presentation()
			await settle()
			arena.hud.open_panel("skills")
			arena.hud.open_panel("inventory")
			await settle()
			var stem := "%d-ui%d-font%d" % [screen.x,roundi(scale_pair.x*100),roundi(scale_pair.y*100)]
			await capture(stem+"-skills-inventory")
			if screen.x == 2560 and scale_pair.x > 1.0:
				var skill_uid: String = arena.state.skill_group("group_000001").main_uid
				var slot := arena.hud._skill_support_panel._rows.find_child("MainGem_00",true,false) as Control
				var anchor: Rect2 = slot.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,slot.size)
				for entry: Array in [[skill_uid,"skill"],[support_uid,"support"],["swift_blade","equipment"]]:
					arena.hud._show_item_hover(str(entry[0]),anchor)
					await settle()
					await capture(stem+"-real-"+str(entry[1]))
					arena.hud._dismiss_item_hover()
			arena.hud.open_panel("character")
			await settle()
			await capture(stem+"-character-inventory")
			arena.hud.open_panel("talents")
			await settle()
			await capture(stem+"-talents")
			arena.hud.handle_menu_key(KEY_ESCAPE,true,false)
			await settle()
			records.append({"restored_route":arena.hud._menu_routes.snapshot(),"variant":stem})
			arena.queue_free()
			await process_frame
	var file := FileAccess.open(output.path_join("geometry.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t",true,true))
	print("DOCKED_NATIVE_CAPTURE_COMPLETE ",records.size())
	quit()

func settle() -> void:
	for index: int in range(6): await process_frame

func capture(stem: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output.path_join(stem+".png"))
	var record := {"variant":stem,"image_size":[image.get_width(),image.get_height()],"route":arena.hud._menu_routes.snapshot(),"controls":{}}
	for control_name: String in ["SkillsCharacterDock","InventoryDock","LeftDockContent","RightDockContent","RightDockScroll","CanonicalSkillPanel","CanonicalCharacterPanel","CharacterSheetBody","CharacterStatsGrid","SharedCanonicalBagGrid","EquipmentSlotGrid","BagPageControls","BagHeader","CanonicalCraftingControls","RecoveryQueue","BagGridHint","MainGem_00"]:
		var node := arena.hud.find_child(control_name,true,false) as Control
		if node == null: continue
		var rect: Rect2 = node.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,node.size)
		record.controls[control_name] = {"visible":node.is_visible_in_tree(),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]}
	var bag: Control = arena.hud._inventory_panel._grid
	var board: Rect2 = bag.get_global_transform_with_canvas()*bag.grid_rect()
	var inventory_scroll: ScrollContainer = arena.hud._dock_scrolls.right
	record.bag = {"board":[board.position.x,board.position.y,board.size.x,board.size.y],"columns":bag.grid_columns(),"rows":bag.grid_rows(),"cell_size":bag.grid_cell_size(),"outer_scroll":inventory_scroll.scroll_vertical,"outer_scroll_max":inventory_scroll.get_v_scroll_bar().max_value,"outer_scroll_page":inventory_scroll.get_v_scroll_bar().page}
	records.append(record)
