extends "res://tests/map_selection_cost_preview_test.gd"
## Reuse canonical UI authority snapshot and real selection signals, not its larger scenario.
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
func notes_check(id:String,expanded:bool)->void:
	var text:=Layout.description(id)
	var expected:=text if expanded else text.get_slice("。",0)+"。"
	check(panel._map_notes.text==expected,"Current selected map consumes exact authored description: "+id)
	check(not panel._map_notes_toggle.disabled and panel._map_notes_toggle.button_pressed==expanded,"Disclosure remains usable and retains selected expansion state")
	check(panel._map_notes.max_lines_visible==(-1 if expanded else 1),"Collapsed notes are bounded; expanded notes expose full text")
	check(panel._map_notes.get_parent().get_parent().size.x<=panel._content.size.x+1.0,"Notes card fits existing content width")
func capture_notes(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	var dir:=OS.get_environment("MAP_NOTES_CAPTURE_DIR")
	if not dir.is_empty():check(root.get_texture().get_image().save_png(dir+"/"+name+".png")==OK,"Native UI screenshot: "+name)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-map-notes-") or FileAccess.file_exists("user://build_save.json"):quit(78);return
	arena=ObservedArena.new();root.add_child(arena);arena.set_process(false);arena.set_physics_process(false);arena.hud.set_process(false);arena.auto_fire=false
	await settle();check(arena.save_build(),"Save isolated canonical profile")
	panel=arena.hud._town_view;panel.open_service("map_device");await settle()
	var before:=authority()
	for id:String in Maps.Catalog.MAPS:
		choose(panel._map_select,id);await settle();notes_check(id,false)
	check(authority()==before,"Reading and switching map notes changes no draft, model, resources, save or RNG")
	panel._map_notes_toggle.button_pressed=true;await settle()
	for id:String in ["old_garden","broken_ruins","sunwell_terrace","ginkgo_arcade","ruins_garden"]:
		choose(panel._map_select,id);await settle();notes_check(id,true)
	check(authority()==before,"Expanded map comparisons remain read-only")
	# Real viewport: show the card, then scroll to the unchanged action buttons.
	var scroll:=panel._content.get_parent() as ScrollContainer
	scroll.scroll_vertical=int(panel._map_notes_toggle.get_parent().get_parent().position.y)
	await settle();await capture_notes("expanded")
	panel._map_notes_toggle.button_pressed=false;await settle()
	scroll.scroll_vertical=0;await settle();await capture_notes("collapsed")
	scroll.ensure_control_visible(panel._map_launch);await settle()
	var visible_rect:=scroll.get_global_rect()
	states.append({"viewport":str(visible_rect),"prepare":str(panel._map_prepare.get_global_rect()),"launch":str(panel._map_launch.get_global_rect())})
	check(visible_rect.grow(1.0).encloses(panel._map_prepare.get_global_rect()) and visible_rect.grow(1.0).encloses(panel._map_launch.get_global_rect()),"Prepare and launch remain reachable inside viewport (one-pixel layout rounding)")
	await capture_notes("actions")
	# Only a user press prepares; rebuilding the panel must show the prepared map.
	choose(panel._map_select,"old_garden");await settle()
	scroll.ensure_control_visible(panel._map_prepare);await settle()
	var pointer:=InputEventMouseMotion.new();pointer.position=panel._map_prepare.get_global_rect().get_center();Input.parse_input_event(pointer)
	for down:bool in [true,false]:
		var click:=InputEventMouseButton.new();click.position=pointer.position;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=down;Input.parse_input_event(click)
	await settle()
	check(arena.normal_prepares==1 and arena.map_draft().map_id=="old_garden" and not panel._map_selection_dirty,"Actual prepare preserves its existing transaction")
	notes_check("old_garden",false)
	before=authority();panel._map_notes_toggle.button_pressed=true;await settle();notes_check("old_garden",true)
	check(authority()==before,"Expanding prepared map cannot prepare again or change launch authority")
	choose(panel._map_select,"ginkgo_arcade");await settle();notes_check("ginkgo_arcade",true)
	check(panel._map_launch.disabled and arena.map_draft().map_id=="old_garden","New map notes never enable the stale prepared map")
	# UI-source fault fixture only: actual selection signals exercise safe fallback.
	for missing:Variant in [null,{},42,"  "]:
		panel._map_descriptions["old_garden"]=missing
		choose(panel._map_select,"old_garden");await settle()
		check(panel._map_notes_toggle.disabled and panel._map_notes.text=="这张地图暂时没有可用说明。","Missing or malformed data clears prior map text safely")
		choose(panel._map_select,"ginkgo_arcade");await settle();notes_check("ginkgo_arcade",true)
	panel.hide();panel.open_service("map_device");await settle()
	notes_check("old_garden",false)
	check(panel._map_descriptions.old_garden==Layout.description("old_garden"),"Reopening loads fresh authored data instead of a stale UI fault fixture")
	check(arena.enter_town_test(arena.world_context().revision).ok,"Enter separate existing test profile")
	panel.open_service("map_device");await settle();choose(panel._map_select,"ginkgo_arcade");await settle()
	panel._map_notes_toggle.button_pressed=true;await settle();notes_check("ginkgo_arcade",true)
	check(arena.test_prepares==0,"Notes in test profile do not manufacture a prepared map")
	var report:={"checks":checks,"failures":failures.size(),"failed_labels":failures,"geometry":states,"display":DisplayServer.get_name(),"source":"Main.map_options -> ExplorationLayout.description","production_scope":"TownServicePanel presentation only","screenshots":OS.get_environment("MAP_NOTES_CAPTURE_DIR")}
	FileAccess.open(OS.get_environment("MAP_NOTES_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("MAP_NOTES ",JSON.stringify(report));arena.queue_free();await process_frame;quit(1 if not failures.is_empty() else 0)
