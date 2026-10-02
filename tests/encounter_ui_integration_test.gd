extends SceneTree
const Catalog = preload("res://scripts/encounters/encounter_catalog.gd")
const Design = preload("res://scripts/visuals/visual_theme.gd")
var arena: Node2D
var checks: int=0
var failures: int=0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func settle() -> void:
	for frame: int in range(5):await process_frame
func choices() -> Control:
	return arena.hud._panel_body.find_child("EncounterControls",true,false)

func run() -> void:
	if OS.get_name()!="Linux" or not OS.get_data_dir().begins_with("/tmp/godot-"):
		push_error("Encounter UI requires isolated Linux XDG storage")
		quit(78);return
	root.size=Vector2i(1280,720)
	arena=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false);arena.hud.set_process(false)
	var hud: Node=arena.hud
	var build: Dictionary=arena.state._snapshot()
	var saved: PackedByteArray=FileAccess.get_file_as_bytes("user://build_save.json") if FileAccess.file_exists("user://build_save.json") else PackedByteArray()
	hud.open_panel("pause")
	await settle()
	var control: Control=choices()
	var dialog: ConfirmationDialog=hud._encounter_dialog
	expect(control!=null,"Pause embeds the existing independent choice component")
	var hint: Label=control.find_child("EncounterIntegration",true,false)
	for required: String in ["本轮","重开","不持久保存","无额外奖励"]:
		expect(hint.text.contains(required),"Visible contract includes "+required)
	var revision: int=arena.run_revision
	var rng_before: int=arena.rng.state
	for id: String in Catalog.get_ids():control._options[id].button_pressed=true
	expect(arena.encounter_selection().is_empty() and arena.run_revision==revision and arena.rng.state==rng_before,"Checkboxes only change the local draft")
	control._confirm.pressed.emit()
	await settle()
	expect(dialog.visible and hud._encounter_request_pending,"First confirmation opens the exact restart warning")
	for required: String in ["强健","迅行","结束当前战斗","构筑","材料保留","不增加奖励","不持久保存"]:
		expect(dialog.dialog_text.contains(required),"Concrete confirmation includes "+required)
	expect(arena.run_revision==revision and arena.rng.state==rng_before,"Opening warning performs no reset or RNG work")
	control._confirm.pressed.emit()
	expect(hud._encounter_request_revision==revision,"Repeated request cannot replace pending confirmation")
	dialog.canceled.emit()
	expect(not dialog.visible and not hud._encounter_request_pending and arena.encounter_selection().is_empty(),"Cancel leaves ordinary run unchanged")
	expect(arena.state._snapshot()==build,"Cancelled selection leaves every build field untouched")
	control._confirm.pressed.emit()
	dialog.confirmed.emit()
	expect(arena.run_revision==revision+1 and arena.encounter_selection()==Catalog.get_ids(),"Confirm starts exactly one selected run")
	var committed: int=arena.run_revision
	dialog.confirmed.emit();hud._confirm_encounter()
	expect(arena.run_revision==committed,"Duplicate confirmation cannot restart again")
	expect(arena.state._snapshot()==build,"Confirmed restart preserves build and crafting state")
	hud.open_panel("pause");await settle()
	control=choices()
	expect(control.get_selected_ids()==Catalog.get_ids(),"Reopened menu reflects active run IDs")
	control._confirm.pressed.emit()
	hud.open_panel("inventory")
	expect(not dialog.visible and not hud._encounter_request_pending,"Navigating away cancels the pending request")
	dialog.confirmed.emit()
	expect(arena.run_revision==committed,"Old hidden dialog cannot restart after newer navigation")
	hud.open_panel("pause");await settle()
	control=choices();control._confirm.pressed.emit()
	hud.refresh_build()
	expect(not dialog.visible and not hud._encounter_request_pending,"Rebuilt context cancels a stale pending request")
	await settle()
	control=choices();control._confirm.pressed.emit()
	arena.restart_run()
	expect(arena.encounter_selection()==Catalog.get_ids(),"Ordinary retry keeps active run selection")
	committed=arena.run_revision
	dialog.confirmed.emit()
	expect(arena.run_revision==committed,"Confirmation from an earlier run cannot act after retry")
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		for scale: float in [1.0,1.2]:
			root.size=resolution
			arena.visual_settings.font_scale=scale
			arena.visual_settings.ui_scale=1.1 if scale>1.0 else 1.0
			hud._apply_presentation();hud.open_panel("pause")
			await settle()
			control=choices()
			hud._panel_scroll.ensure_control_visible(control._confirm)
			await settle()
			for widget: Control in [control._confirm,control._options[Catalog.get_ids()[0]],control._options[Catalog.get_ids()[1]]]:
				expect(widget.get_theme_color("font_focus_color")==Design.TEXT,"Focus retains dark ink for every choice control")
				expect(widget.get_global_rect().position.x>=control.get_global_rect().position.x-0.1 and widget.get_global_rect().end.x<=control.get_global_rect().end.x+0.1,"Choice controls stay within original scroll width")
			var long_text: String="长原因需要完整换行并保持内容。".repeat(20)
			var tooltip: Label=control._confirm._make_custom_tooltip(long_text)
			expect(tooltip.text==long_text and tooltip.autowrap_mode==TextServer.AUTOWRAP_WORD_SMART and tooltip.custom_minimum_size.x<=420.0,"Long tooltip preserves all text and bounded wrapping")
			tooltip.free()
			control._confirm.pressed.emit();await settle()
			expect(dialog.size.x<=root.size.x and dialog.size.y<=root.size.y,"Confirmation fits actual window at both font scales")
			expect(dialog.theme.get_color("title_color","Window")==Color("f8ecd0") and dialog.get_ok_button().get_theme_color("font_focus_color")==Design.TEXT,"Confirmation retains legible wood title and ink buttons")
			dialog.canceled.emit()
	var after_saved: PackedByteArray=FileAccess.get_file_as_bytes("user://build_save.json") if FileAccess.file_exists("user://build_save.json") else PackedByteArray()
	expect(after_saved==saved and arena.state._snapshot()==build,"All selection/UI flows neither mutate nor persist build progress")
	arena.free();await process_frame
	print("Encounter UI integration: %d checks, %d failures" %[checks,failures])
	quit(1 if failures else 0)
