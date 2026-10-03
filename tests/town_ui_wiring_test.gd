extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v28root-ui-"):
		quit(78)
		return
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	var hud = arena.hud
	hud._menu_routes = load("res://scripts/ui/docked_menu_state.gd").new()
	hud._sync_menu_views()
	check(hud.handle_menu_key(KEY_C),"C consumed")
	check(hud._menu_routes.snapshot().left == "character" and not hud._menu_routes.snapshot().right_inventory,"C independently opens character")
	hud.open_panel("inventory")
	check(hud._menu_routes.snapshot().left == "character" and hud._menu_routes.snapshot().right_inventory,"Independent docks coexist")
	var old_panel = hud._inventory_panel
	var old_state = arena.state
	hud._world_action()
	check(arena.world_context().mode == "town", "Town entry works through HUD")
	check(hud._state == arena.state and hud._state != old_state, "HUD rebound to test model")
	check(not is_instance_valid(hud._inventory_panel),"Old inventory detached")
	check(old_panel.is_queued_for_deletion(),"Old model UI queued free")
	hud.open_panel("inventory")
	check(hud._inventory_panel.save_path == arena.build_save_path,"Bag writes active profile")
	hud.open_panel("skills")
	check(hud._skill_support_panel.save_path == arena.build_save_path,"Skill writes active profile")
	var view = hud._town_view
	view._select("equipment_merchant")
	check(view._content.get_child_count() == arena.town_stock("equipment_merchant").size(),"All equipment stock renders")
	view._content.get_child(0).get_child(2).pressed.emit()
	check(arena.state.revision() > old_state.revision(),"Actual buy button uses canonical transaction")
	view._select("map_device")
	view._craft_map()
	var launch = view._content.get_child(view._content.get_child_count()-1)
	check(not launch.disabled,"Craft enables start")
	launch.pressed.emit()
	check(arena.world_context().mode == "map" and not view.visible,"Actual launch button starts map")
	hud._world_action()
	check(hud._return_dialog.visible,"Abandon has confirmation")
	hud._return_dialog.confirmed.emit()
	check(arena.world_context().mode == "town","Confirmed return")
	var result: Dictionary = arena.leave_town_test(arena.world_context().revision)
	check(result.ok and hud._state == arena.state and arena.world_context().mode == "normal","Exit restores normal profile")
	check(not view._reset.visible and not hud._return_dialog.visible,"Switch closes old confirmations")
	print("Town UI wiring: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
