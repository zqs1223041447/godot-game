extends SceneTree
## The root-owned redesign keeps visual hierarchy and the established input/data
## contracts separate. This fixture does not stand in for screenshot inspection.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-root-ui-"):
		quit(78)
		return
	root.size = Vector2i(1280,720)
	var arena: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	for unused: int in range(5): await process_frame
	arena.hud.open_panel("skills")
	arena.hud.open_panel("inventory")
	for unused: int in range(5): await process_frame
	var before: Dictionary = arena.state.snapshot()
	for side: String in ["left","right"]:
		var title: Label = arena.hud._dock_titles[side]
		check(title.get_theme_color("font_color").get_luminance() > 0.7,
			"Dark title band uses high-contrast ivory text: "+side)
		check(title.get_theme_font_size("font_size") <= 16,"Dock title stays compact")
	var rows: Control = arena.hud._skill_support_panel._rows
	var main: Control = rows.find_child("MainGem_00",true,false)
	var support: Control = rows.find_child("SupportGem_00_0",true,false)
	check(main.size.x > support.size.x,"Main art remains the visual anchor beside smaller sockets")
	check(main.find_child("GemIcon",true,false).mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Gem art does not capture the parent slot drag")
	check(rows.find_child("SkillGroupName_00",true,false).get_theme_font_size("font_size") <= 12,
		"Row names stay compact rather than large explanatory headers")
	var inventory: Control = arena.hud._inventory_panel
	var grid: Control = inventory._grid
	check(grid.grid_columns() == 8 and grid.grid_rows() == 6 and grid.bag_page_count() == 2,
		"Visual redesign leaves bag capacity and paging unchanged")
	check(not grid._has_caption({"size":Vector2i(2,3),"short_name":"测试装备"}),
		"Item names are not repeated inside every bag footprint")
	check(inventory._craft_controls._balance_label.visible == false,
		"No independent wallet counter is brought back by styling")
	var gear: Control = inventory.find_child("EquipmentSlotGrid",true,false)
	var toolbar: Control = inventory.find_child("BagHeader",true,false)
	check(toolbar.get_global_rect().position.y >= gear.get_global_rect().end.y,
		"Inventory operations stay with the bag below the equipment")
	check(arena.hud._dock_footers.left.text.is_empty() and arena.hud._dock_footers.right.text.is_empty(),
		"No permanent developer instruction footer returns")
	check(arena.state.snapshot() == before,"Presentation checks never mutate the canonical model")
	print("Root UI style: %d checks, %d failures" % [checks,failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
