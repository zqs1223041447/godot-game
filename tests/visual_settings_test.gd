extends SceneTree
const Preferences = preload("res://scripts/visuals/visual_settings.gd")
var failures: int = 0
var checks: int = 0
func _initialize() -> void:
	call_deferred("run")
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+message)
func run() -> void:
	var preferences := Preferences.new()
	preferences.ui_scale = 1.1
	preferences.font_scale = 1.2
	preferences.effects_level = 0
	preferences.damage_numbers = false
	preferences.motion = false
	expect(preferences.save_settings("user://test_visual.cfg") == OK,"preferences save independently")
	var loaded := Preferences.new()
	loaded.load_settings("user://test_visual.cfg")
	expect(loaded.ui_scale == 1.1 and loaded.font_scale == 1.2 and loaded.effects_level == 0,"scale/effects roundtrip")
	expect(not loaded.damage_numbers and not loaded.motion,"accessibility flags roundtrip")
	var malformed := ConfigFile.new()
	malformed.set_value("display","ui_scale",999)
	malformed.set_value("display","font_scale","bad")
	malformed.set_value("display","effects_level",99)
	malformed.save("user://test_visual_bad.cfg")
	loaded.load_settings("user://test_visual_bad.cfg")
	expect(loaded.ui_scale == 1.0 and loaded.font_scale == 1.0 and loaded.effects_level == 2,"malformed settings sanitized")
	root.size = Vector2i(1280,720)
	var arena: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	await process_frame
	var origin: Vector2 = arena.player_pos
	var rng := RandomNumberGenerator.new()
	rng.seed = 501
	var gear_id: String = arena.state.award_equipment(rng,30,"rare")
	expect(not gear_id.is_empty(),"six-affix QA fixture granted")
	arena.hud.open_panel("inventory")
	var inventory: Control = arena.hud.find_child("InventoryPanel",true,false)
	inventory.select_item("item:"+gear_id)
	expect(arena.state.get_item_definition(gear_id).get("affix_lines",[]).size() == 6,"worst-case six-affix details")
	inventory._equip_selected()
	expect(arena.state.equipped.values().has(gear_id),"generated item equips through inspector")
	inventory._unequip_selected()
	expect(not arena.state.equipped.values().has(gear_id),"generated item unequips through inspector")
	for ui: float in Preferences.UI_SCALES:
		for font: float in Preferences.FONT_SCALES:
			arena.visual_settings.ui_scale = ui
			arena.visual_settings.font_scale = font
			arena.hud._apply_presentation()
			for panel: String in ["inventory","talents","skills","combat","monsters","settings","pause"]:
				arena.hud.open_panel(panel)
				for i: int in range(5):
					await process_frame
				var scroll: Control = arena.hud.find_child("PanelScroll",true,false)
				var body: Control = arena.hud.find_child("PanelBody",true,false)
				var frame: Control = arena.hud.find_child("BuildPanel",true,false)
				var hud_root: Control = arena.hud.get_node("HUDRoot")
				expect(frame.get_rect().end.y <= hud_root.size.y+1,"frame fits height %s %.1f %.1f"%[panel,ui,font])
				expect(body.size.x <= scroll.size.x+1,"no horizontal content clipping %s %.1f %.1f (body%.0f scroll%.0f)"%[panel,ui,font,body.size.x,scroll.size.x])
				expect(arena.player_pos == origin,"presentation never moves world")
	# Cancellation never deletes; a stale equipped target is still rejected by the model.
	inventory._discard_target = gear_id
	inventory._discard_dialog.canceled.emit()
	expect(inventory._discard_target.is_empty() and arena.state.inventory.has(gear_id),"cancel keeps generated equipment")
	inventory._discard_target = gear_id
	inventory._confirm_discard()
	expect(not arena.state.inventory.has(gear_id),"confirmed discard removes only synthetic generated equipment")
	print("visual_settings_test: %d checks, %d failures"%[checks,failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
